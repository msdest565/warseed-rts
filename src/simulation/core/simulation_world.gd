class_name SimulationWorld
extends RefCounted

const TICK_SECONDS := 0.1
const BATTLEFIELD_BOUNDS := Rect2(Vector2.ZERO, Vector2(3072.0, 2048.0))
const INITIAL_UNIT_ID := 1
const DEFAULT_FORMATION_ID := 1
const LOCAL_PLAYER_ID := 1
const ENEMY_PLAYER_ID := 2
const DEFAULT_ENEMY_UNIT_ID := 1001
const ENEMY_HARVESTER_ID := 1002
const ENEMY_ENGINEER_ID := 1003
const PLAYER_COMMAND_CENTER_ID := 2001
const PLAYER_FACTORY_ID := 2002
const PLAYER_SUPPORT_ID := 2003
const ENEMY_COMMAND_CENTER_ID := 2101
const FIRST_CONSTRUCTED_BUILDING_ID := 2200
const DEFAULT_ORE_FIELD_ID := 3001
const ENEMY_ORE_FIELD_ID := 3002
const PLAYER_EXPANSION_ORE_FIELD_ID := 3003
const ENEMY_EXPANSION_ORE_FIELD_ID := 3004
const PRIMARY_ORE_CAPACITY := 10000
const EXPANSION_ORE_CAPACITY := 8000
const TEST_AGENT_ID := 101
const TEST_TASK_ID := 1
const UNIT_CATALOG: UnitDefinitionCatalog = preload("res://data/units/unit_catalog.tres")
const BUILDING_CATALOG: BuildingDefinitionCatalog = preload("res://data/buildings/building_catalog.tres")
const DEFAULT_UNIT_DEFINITION: UnitDefinition = preload("res://data/units/scout_vehicle.tres")
const ENEMY_DIFFICULTY_EASY: EnemyDifficultyProfile = preload("res://data/ai/enemy_easy.tres")
const ENEMY_DIFFICULTY_NORMAL: EnemyDifficultyProfile = preload("res://data/ai/enemy_normal.tres")
const ENEMY_DIFFICULTY_HARD: EnemyDifficultyProfile = preload("res://data/ai/enemy_hard.tres")
const ENEMY_DIFFICULTY_EXPERT: EnemyDifficultyProfile = preload("res://data/ai/enemy_expert.tres")
const INDUSTRIAL_POLICY: AgentPolicy = preload("res://data/ai/industrial_assisted.tres")
const BATTLEFIELD_POLICY: AgentPolicy = preload("res://data/ai/battlefield_assisted.tres")
const ENEMY_POLICY: AgentPolicy = preload("res://data/ai/enemy_autonomous.tres")
const WRECK_LIFETIME_TICKS := 70
const FRIENDLY_AUTONOMY_INTERVAL_TICKS := 20

var current_tick: int = 0
var units: Dictionary = {}
var formations: Dictionary = {}
var factions: Dictionary = {}
var buildings: Dictionary = {}
var ore_fields: Dictionary = {}
var faction_knowledge: Dictionary = {}
var tasks: Dictionary = {}
var agent_policies: Dictionary = {}
var agents: Array[DeterministicFormationAgent] = []
var enemy_raid_agent: EnemyRaidAgent
var mission_state := MissionState.new()
var command_queue := CommandQueue.new()
var command_validator := CommandValidator.new()
var logic_grid := LogicGrid.create_test_map()
var metrics := SimulationMetrics.new()
var pathfinder := GridPathfinder.new(logic_grid, metrics)
var formation_movement := FormationMovementSystem.new(logic_grid, pathfinder)
var combat_system := CombatSystem.new()
var economy_system := EconomySystem.new()
var engineering_system := EngineeringSystem.new()
var strategic_task_system := StrategicTaskSystem.new()
var events: Array[SimulationEvent] = []
var projectiles: Dictionary = {}
var _next_projectile_id: int = 1
var _next_unit_id: int = 1100
var _next_formation_id: int = 2
var _next_building_id: int = FIRST_CONSTRUCTED_BUILDING_ID
var _next_command_id: int = 1
var _next_task_id: int = 1
var _last_friendly_autonomy_tick: int = -FRIENDLY_AUTONOMY_INTERVAL_TICKS


func _init(create_default_units: bool = true, create_test_agent: bool = false) -> void:
	_configure_ai()
	if create_default_units:
		_setup_default_scenario()
	_update_faction_knowledge()
	if create_default_units and create_test_agent:
		_create_default_agent_task()


func _configure_ai() -> void:
	agent_policies.clear()
	_register_agent_policy(INDUSTRIAL_POLICY)
	_register_agent_policy(BATTLEFIELD_POLICY)
	_register_agent_policy(ENEMY_POLICY)
	var test_policy := AgentPolicy.new()
	test_policy.agent_id = TEST_AGENT_ID
	test_policy.faction_id = LOCAL_PLAYER_ID
	test_policy.domain = AgentPolicy.Domain.TEST
	test_policy.authorization = AgentPolicy.Authorization.ASSISTED
	agent_policies[test_policy.agent_id] = test_policy
	enemy_raid_agent = EnemyRaidAgent.new(ENEMY_DIFFICULTY_NORMAL.duplicate(true) as EnemyDifficultyProfile)


func _register_agent_policy(template: AgentPolicy) -> void:
	var policy := template.duplicate(true) as AgentPolicy
	agent_policies[policy.agent_id] = policy


func set_agent_authorization(agent_id: int, authorization: AgentPolicy.Authorization) -> bool:
	var policy := agent_policies.get(agent_id) as AgentPolicy
	if policy == null or policy.domain == AgentPolicy.Domain.ENEMY:
		return false
	policy.authorization = authorization
	command_queue.remove_if(func(command: GameCommand) -> bool: return _required_agent_id(command) == agent_id and not _agent_authorization_allows(command))
	if not policy.allows_explicit_tasks() or not policy.allows_proactive_tasks():
		for task_variant in tasks.values():
			var task := task_variant as TaskState
			var authorization_lost := not policy.allows_explicit_tasks() or task.requires_proactive_authorization and not policy.allows_proactive_tasks()
			if task.agent_id == agent_id and authorization_lost and task.lifecycle == TaskState.Lifecycle.EXECUTING:
				task.set_lifecycle(TaskState.Lifecycle.PAUSED, current_tick, TaskState.BlockedReason.NONE, "Paused because Agent authorization no longer permits this task")
				_stop_task_formation(task)
	return true


func get_agent_authorization(agent_id: int) -> AgentPolicy.Authorization:
	var policy := agent_policies.get(agent_id) as AgentPolicy
	return policy.authorization if policy != null else AgentPolicy.Authorization.ADVISORY


func get_agent_recommendation_key(agent_id: int) -> StringName:
	if _has_open_task_for_agent(agent_id):
		return &"AI_RECOMMENDATION_ACTIVE"
	if agent_id == StrategicTaskSystem.INDUSTRIAL_AGENT_ID:
		for unit_variant in units.values():
			var unit := unit_variant as UnitState
			if unit.enabled and unit.faction_id == LOCAL_PLAYER_ID and unit.can_harvest:
				return &"AI_RECOMMENDATION_DEVELOP"
		return &"AI_RECOMMENDATION_NEED_HARVESTER"
	if agent_id == StrategicTaskSystem.BATTLEFIELD_AGENT_ID:
		for unit_variant in units.values():
			var contact := unit_variant as UnitState
			if contact.enabled and contact.faction_id != LOCAL_PLAYER_ID and is_entity_visible_to_faction(contact.entity_id, LOCAL_PLAYER_ID):
				return &"AI_RECOMMENDATION_ATTACK"
		for unit_variant in units.values():
			var unit := unit_variant as UnitState
			if unit.enabled and unit.faction_id == LOCAL_PLAYER_ID and unit.definition_id == &"scout_vehicle" and unit.assigned_task_id == 0:
				return &"AI_RECOMMENDATION_SCOUT"
		return &"AI_RECOMMENDATION_DEFEND"
	return &"AI_RECOMMENDATION_NONE"


func set_enemy_difficulty(difficulty: EnemyDifficultyProfile.Difficulty) -> void:
	var template := ENEMY_DIFFICULTY_NORMAL
	match difficulty:
		EnemyDifficultyProfile.Difficulty.EASY:
			template = ENEMY_DIFFICULTY_EASY
		EnemyDifficultyProfile.Difficulty.HARD:
			template = ENEMY_DIFFICULTY_HARD
		EnemyDifficultyProfile.Difficulty.EXPERT:
			template = ENEMY_DIFFICULTY_EXPERT
	enemy_raid_agent.set_difficulty_profile(template.duplicate(true) as EnemyDifficultyProfile)


func get_enemy_difficulty() -> EnemyDifficultyProfile.Difficulty:
	return enemy_raid_agent.difficulty_profile.difficulty


func _create_default_agent_task() -> void:
	var task := TaskState.new(_next_task_id, TEST_AGENT_ID, [1, 2, 3, 4, 5])
	_next_task_id += 1
	task.faction_id = LOCAL_PLAYER_ID
	task.target_position = logic_grid.cell_to_world(Vector2i(20, 8))
	task.priority = 10
	task.set_lifecycle(TaskState.Lifecycle.EXECUTING, current_tick)
	tasks[task.task_id] = task
	for entity_id in task.participant_entity_ids:
		var unit := units[entity_id] as UnitState
		unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
		unit.assigned_agent_id = TEST_AGENT_ID
		unit.assigned_task_id = task.task_id
		unit.original_formation_id = unit.formation_id
	agents.append(DeterministicFormationAgent.new(TEST_AGENT_ID, task.task_id, DEFAULT_FORMATION_ID, task.target_position))


func _setup_default_scenario() -> void:
	factions[LOCAL_PLAYER_ID] = FactionState.new(LOCAL_PLAYER_ID, LOCAL_PLAYER_ID, 500)
	factions[ENEMY_PLAYER_ID] = FactionState.new(ENEMY_PLAYER_ID, ENEMY_PLAYER_ID, 1400)
	_create_default_formation()
	_create_default_enemy()
	_create_default_buildings()
	ore_fields[DEFAULT_ORE_FIELD_ID] = OreFieldState.new(DEFAULT_ORE_FIELD_ID, logic_grid.cell_to_world(Vector2i(20, 10)), PRIMARY_ORE_CAPACITY)
	ore_fields[ENEMY_ORE_FIELD_ID] = OreFieldState.new(ENEMY_ORE_FIELD_ID, logic_grid.cell_to_world(LogicGrid.MAP_DEFINITION.enemy_spawn_cell + Vector2i(-6, 3)), PRIMARY_ORE_CAPACITY)
	ore_fields[PLAYER_EXPANSION_ORE_FIELD_ID] = OreFieldState.new(PLAYER_EXPANSION_ORE_FIELD_ID, logic_grid.cell_to_world(Vector2i(34, 22)), EXPANSION_ORE_CAPACITY)
	ore_fields[ENEMY_EXPANSION_ORE_FIELD_ID] = OreFieldState.new(ENEMY_EXPANSION_ORE_FIELD_ID, logic_grid.cell_to_world(Vector2i(67, 43)), EXPANSION_ORE_CAPACITY)


func _create_default_buildings() -> void:
	_add_building(PLAYER_COMMAND_CENTER_ID, &"command_center", LOCAL_PLAYER_ID, logic_grid.cell_to_world(Vector2i(5, 8)))
	_add_building(PLAYER_FACTORY_ID, &"automated_factory", LOCAL_PLAYER_ID, logic_grid.cell_to_world(Vector2i(9, 6)))
	_add_building(PLAYER_SUPPORT_ID, &"forward_support_station", LOCAL_PLAYER_ID, logic_grid.cell_to_world(Vector2i(6, 13)))
	_add_building(ENEMY_COMMAND_CENTER_ID, &"command_center", ENEMY_PLAYER_ID, logic_grid.cell_to_world(LogicGrid.MAP_DEFINITION.enemy_spawn_cell))


func _add_building(entity_id: int, definition_id: StringName, faction_id: int, position: Vector2) -> void:
	var definition := BUILDING_CATALOG.get_building(definition_id)
	var building := BuildingState.new(entity_id, definition_id, faction_id, faction_id, position, definition.max_health)
	building.armor = definition.armor
	building.footprint_cells = logic_grid.get_footprint_cells(position, definition.footprint_size)
	building.rally_position = _default_work_position(building.footprint_cells, position)
	buildings[entity_id] = building
	_set_building_occupancy(building, true)


func _create_default_formation() -> void:
	var anchor := logic_grid.cell_to_world(LogicGrid.MAP_DEFINITION.player_spawn_cell)
	var member_ids: Array[int] = [1, 2, 3, 4, 5]
	var formation := FormationState.new(DEFAULT_FORMATION_ID, member_ids, anchor)
	formations[DEFAULT_FORMATION_ID] = formation
	var definitions: Array[StringName] = [&"harvester", &"engineer_vehicle", &"scout_vehicle", &"assault_vehicle", &"missile_vehicle"]
	for entity_id in member_ids:
		var slot_id := formation.get_slot_id(entity_id)
		var position := anchor + formation.get_wide_offset(slot_id)
		var definition := UNIT_CATALOG.get_unit(definitions[slot_id])
		var unit := UnitState.new(entity_id, position, definition.move_speed, LOCAL_PLAYER_ID)
		_apply_unit_definition(unit, definition)
		unit.formation_id = DEFAULT_FORMATION_ID
		unit.formation_slot_id = slot_id
		unit.following_formation = true
		unit.desired_position = position
		units[entity_id] = unit


func _create_default_enemy() -> void:
	var enemy_position := logic_grid.cell_to_world(LogicGrid.MAP_DEFINITION.enemy_spawn_cell + Vector2i(-4, 0))
	var enemy := UnitState.new(DEFAULT_ENEMY_UNIT_ID, enemy_position, 0.0, ENEMY_PLAYER_ID)
	_apply_unit_definition(enemy, DEFAULT_UNIT_DEFINITION)
	enemy.control_state = UnitState.ControlState.AGENT_ASSIGNED
	enemy.assigned_agent_id = EnemyRaidAgent.AGENT_ID
	enemy.assigned_task_id = EnemyRaidAgent.TASK_ID
	units[enemy.entity_id] = enemy
	_add_enemy_agent_unit(ENEMY_HARVESTER_ID, &"harvester", LogicGrid.MAP_DEFINITION.enemy_spawn_cell + Vector2i(-5, 2))
	_add_enemy_agent_unit(ENEMY_ENGINEER_ID, &"engineer_vehicle", LogicGrid.MAP_DEFINITION.enemy_spawn_cell + Vector2i(-5, -2))


func _add_enemy_agent_unit(entity_id: int, definition_id: StringName, cell: Vector2i) -> void:
	var definition := UNIT_CATALOG.get_unit(definition_id)
	var unit := UnitState.new(entity_id, logic_grid.cell_to_world(cell), definition.move_speed, ENEMY_PLAYER_ID)
	_apply_unit_definition(unit, definition)
	unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
	unit.assigned_agent_id = EnemyRaidAgent.AGENT_ID
	unit.assigned_task_id = EnemyRaidAgent.TASK_ID
	units[entity_id] = unit


func _apply_unit_definition(unit: UnitState, definition: UnitDefinition) -> void:
	unit.definition_id = definition.definition_id
	unit.move_speed = definition.move_speed
	unit.max_health = definition.combat.max_health
	unit.health = unit.max_health
	unit.armor = definition.combat.armor
	unit.attack_damage = definition.combat.attack_power
	unit.attack_range = definition.combat.attack_range
	unit.attacks_per_second = definition.combat.attacks_per_second
	unit.attack_cooldown_ticks = maxi(1, ceili(10.0 / unit.attacks_per_second))
	unit.projectile_speed = definition.combat.projectile_speed
	unit.sight_range = definition.sight_range
	unit.can_attack = definition.can_attack
	unit.can_accept_attack_orders = definition.can_accept_attack_orders
	unit.auto_retaliate = definition.auto_retaliate
	unit.can_harvest = definition.can_harvest
	unit.can_construct = definition.can_construct
	unit.can_repair = definition.can_repair


func allocate_command_id() -> int:
	var allocated := _next_command_id
	_next_command_id += 1
	return allocated


func submit_command(command: GameCommand) -> CommandValidationResult:
	var result := validate_command(command)
	if result.is_accepted() and _is_direct_player_order(command):
		var takeover_formation_id := 0
		if command is FormationMoveCommand:
			takeover_formation_id = (command as FormationMoveCommand).formation_id
		elif command is StopCommand:
			takeover_formation_id = (command as StopCommand).formation_id
		elif command is AttackCommand:
			takeover_formation_id = (command as AttackCommand).formation_id
		if takeover_formation_id != 0 and formations.has(takeover_formation_id):
			for entity_id in (formations[takeover_formation_id] as FormationState).member_entity_ids:
				_begin_player_takeover(units[entity_id] as UnitState, command, true)
		elif units.has(command.target_entity_id):
			_begin_player_takeover(units[command.target_entity_id] as UnitState, command)
	metrics.record_command_result(result)
	var event_start := events.size()
	var event_kind := SimulationEvent.Kind.COMMAND_REJECTED
	if result.is_accepted():
		command_queue.enqueue(command)
		event_kind = SimulationEvent.Kind.COMMAND_ACCEPTED
	events.append(SimulationEvent.new(current_tick, event_kind, command.target_entity_id, result.describe()))
	metrics.record_events(events, event_start)
	return result


func validate_command(command: GameCommand) -> CommandValidationResult:
	_update_faction_knowledge()
	var result := command_validator.validate(command, units, BATTLEFIELD_BOUNDS, pathfinder, formations, buildings, ore_fields, factions, UNIT_CATALOG, BUILDING_CATALOG, faction_knowledge, logic_grid, tasks)
	if result.is_accepted() and not _agent_authorization_allows(command):
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED)
	return result


func _agent_authorization_allows(command: GameCommand) -> bool:
	var required_agent_id := _required_agent_id(command)
	if required_agent_id == 0:
		return true
	var policy := agent_policies.get(required_agent_id) as AgentPolicy
	if policy == null or policy.faction_id != command.issuer_id:
		return false
	if command is StrategicOrderCommand and command.issuer_kind == GameCommand.IssuerKind.AGENT:
		return policy.allows_proactive_tasks()
	return policy.allows_explicit_tasks()


func _required_agent_id(command: GameCommand) -> int:
	if command is StrategicOrderCommand:
		return StrategicTaskSystem.INDUSTRIAL_AGENT_ID if (command as StrategicOrderCommand).order_kind == StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE else StrategicTaskSystem.BATTLEFIELD_AGENT_ID
	if command.issuer_kind == GameCommand.IssuerKind.AGENT:
		return command.agent_id
	return 0


func _advance_friendly_autonomy() -> void:
	if current_tick - _last_friendly_autonomy_tick < FRIENDLY_AUTONOMY_INTERVAL_TICKS:
		return
	_last_friendly_autonomy_tick = current_tick
	var industrial_policy := agent_policies.get(StrategicTaskSystem.INDUSTRIAL_AGENT_ID) as AgentPolicy
	if industrial_policy != null and industrial_policy.allows_proactive_tasks() and not _has_open_task_for_agent(industrial_policy.agent_id):
		_submit_autonomous_industrial_order(industrial_policy)
	var battlefield_policy := agent_policies.get(StrategicTaskSystem.BATTLEFIELD_AGENT_ID) as AgentPolicy
	if battlefield_policy != null and battlefield_policy.allows_proactive_tasks() and not _has_open_task_for_agent(battlefield_policy.agent_id):
		_submit_autonomous_battlefield_order(battlefield_policy)


func _has_open_task_for_agent(agent_id: int) -> bool:
	for task_variant in tasks.values():
		var task := task_variant as TaskState
		if task.agent_id == agent_id and task.lifecycle in [TaskState.Lifecycle.WAITING, TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING, TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]:
			return true
	return false


func _submit_autonomous_industrial_order(policy: AgentPolicy) -> void:
	var snapshot := create_faction_snapshot(policy.faction_id)
	var best_ore: OreFieldSnapshot
	for ore_field in snapshot.ore_fields:
		if ore_field.ore_remaining > 0 and (best_ore == null or ore_field.ore_remaining > best_ore.ore_remaining or ore_field.ore_remaining == best_ore.ore_remaining and ore_field.entity_id < best_ore.entity_id):
			best_ore = ore_field
	if best_ore == null:
		return
	var command := StrategicOrderCommand.new(
		allocate_command_id(), policy.faction_id, current_tick,
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE, 0, best_ore.entity_id, best_ore.position, 0.0,
		GameCommand.IssuerKind.AGENT
	)
	command.agent_id = policy.agent_id
	submit_command(command)


func _submit_autonomous_battlefield_order(policy: AgentPolicy) -> void:
	var formation := formations.get(DEFAULT_FORMATION_ID) as FormationState
	if formation == null or formation.member_entity_ids.is_empty():
		return
	var snapshot := create_faction_snapshot(policy.faction_id)
	var best_target: UnitSnapshot
	var best_distance := INF
	for contact in snapshot.units:
		if contact.faction_id == policy.faction_id or not contact.enabled or not contact.is_visible_to_local_player:
			continue
		var distance := formation.anchor_position.distance_squared_to(contact.position)
		if distance < best_distance or is_equal_approx(distance, best_distance) and (best_target == null or contact.entity_id < best_target.entity_id):
			best_target = contact
			best_distance = distance
	var command: StrategicOrderCommand
	if best_target != null:
		command = StrategicOrderCommand.new(
			allocate_command_id(), policy.faction_id, current_tick,
			StrategicOrderCommand.OrderKind.ATTACK_TARGET, formation.formation_id, best_target.entity_id, best_target.position, 0.0,
			GameCommand.IssuerKind.AGENT
		)
	else:
		var scout_ids: Array[int] = []
		for unit_variant in units.values():
			var unit := unit_variant as UnitState
			if unit.enabled and unit.faction_id == policy.faction_id and unit.definition_id == &"scout_vehicle" and unit.assigned_task_id == 0:
				scout_ids.append(unit.entity_id)
				break
		if scout_ids.is_empty():
			return
		command = StrategicOrderCommand.new(
			allocate_command_id(), policy.faction_id, current_tick,
			StrategicOrderCommand.OrderKind.SCOUT_AREA, 0, 0,
			logic_grid.cell_to_world(Vector2i(70, 42)), 224.0,
			GameCommand.IssuerKind.AGENT
		)
		command.participant_entity_ids.assign(scout_ids)
	command.agent_id = policy.agent_id
	submit_command(command)


func _is_direct_player_order(command: GameCommand) -> bool:
	if command.issuer_kind != GameCommand.IssuerKind.PLAYER:
		return false
	return command is MoveCommand or command is FormationMoveCommand or command is StopCommand or command is AttackCommand or command is HarvestCommand or command is BuildBuildingCommand or command is RepairBuildingCommand


func advance_tick() -> WorldSnapshot:
	var event_start := events.size()
	var commands := command_queue.drain()
	metrics.record_commands_applied(commands.size())
	for command in commands:
		_apply_command(command)
	for agent in agents:
		agent.advance(self)
	strategic_task_system.advance(self)
	_advance_friendly_autonomy()
	enemy_raid_agent.advance(self)
	_update_faction_knowledge()
	_drop_hidden_attack_targets()
	_update_worker_self_defense()
	_update_combat_orders()
	formation_movement.advance(formations, units, events, current_tick)
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if not unit.following_formation:
			_advance_unit(unit)
	_complete_rejoins()
	engineering_system.advance(units, buildings, BUILDING_CATALOG, events, current_tick)
	_next_projectile_id = combat_system.advance(units, buildings, projectiles, _next_projectile_id, events, current_tick)
	_cleanup_expired_wrecks()
	_release_destroyed_building_occupancy()
	_next_unit_id = economy_system.advance(units, buildings, ore_fields, factions, UNIT_CATALOG, BUILDING_CATALOG, pathfinder, _next_unit_id, events, current_tick)
	_update_victory()
	mission_state.update_completed(current_tick)
	metrics.record_events(events, event_start)
	current_tick += 1
	_update_faction_knowledge()
	return create_snapshot()


func create_true_state_snapshot() -> WorldSnapshot:
	var unit_snapshots: Array[UnitSnapshot] = []
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		unit_snapshots.append(UnitSnapshot.new(units[entity_id] as UnitState))
	var formation_snapshots: Array[FormationSnapshot] = []
	var formation_ids := formations.keys()
	formation_ids.sort()
	for formation_id in formation_ids:
		formation_snapshots.append(FormationSnapshot.new(formations[formation_id] as FormationState))
	var projectile_snapshots: Array[ProjectileSnapshot] = []
	var projectile_ids := projectiles.keys()
	projectile_ids.sort()
	for projectile_id in projectile_ids:
		projectile_snapshots.append(ProjectileSnapshot.new(projectiles[projectile_id] as ProjectileState))
	var ore_snapshots: Array[OreFieldSnapshot] = []
	var ore_ids := ore_fields.keys()
	ore_ids.sort()
	for ore_id in ore_ids:
		ore_snapshots.append(OreFieldSnapshot.new(ore_fields[ore_id] as OreFieldState))
	var building_snapshots: Array[BuildingSnapshot] = []
	var building_ids := buildings.keys()
	building_ids.sort()
	for building_id in building_ids:
		building_snapshots.append(BuildingSnapshot.new(buildings[building_id] as BuildingState))
	var faction_snapshots: Array[FactionSnapshot] = []
	var faction_ids := factions.keys()
	faction_ids.sort()
	for faction_id in faction_ids:
		faction_snapshots.append(FactionSnapshot.new(factions[faction_id] as FactionState))
	var task_snapshots := _create_task_snapshots()
	return WorldSnapshot.new(current_tick, unit_snapshots, formation_snapshots, projectile_snapshots, metrics.create_snapshot(), faction_snapshots, building_snapshots, ore_snapshots, 0, null, true, task_snapshots, MissionSnapshot.new(mission_state))


func create_snapshot(faction_id: int = LOCAL_PLAYER_ID) -> WorldSnapshot:
	return create_faction_snapshot(faction_id)


func create_faction_snapshot(faction_id: int) -> WorldSnapshot:
	_ensure_faction_knowledge(faction_id)
	var knowledge := faction_knowledge[faction_id] as FactionKnowledge
	var unit_snapshots: Array[UnitSnapshot] = []
	var building_snapshots: Array[BuildingSnapshot] = []
	var formation_snapshots: Array[FormationSnapshot] = []
	var projectile_snapshots: Array[ProjectileSnapshot] = []
	var faction_snapshots: Array[FactionSnapshot] = []
	var ore_snapshots: Array[OreFieldSnapshot] = []
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if unit.faction_id == faction_id:
			var friendly_snapshot := UnitSnapshot.new(unit)
			friendly_snapshot.is_visible_to_local_player = true
			friendly_snapshot.last_seen_tick = current_tick
			friendly_snapshot.last_seen_position = unit.position
			unit_snapshots.append(friendly_snapshot)
		elif knowledge.is_visible(logic_grid.world_to_cell(unit.position)):
			var hostile_snapshot := UnitSnapshot.new(unit)
			hostile_snapshot.is_visible_to_local_player = true
			hostile_snapshot.last_seen_tick = current_tick
			hostile_snapshot.last_seen_position = unit.position
			unit_snapshots.append(hostile_snapshot)
		elif knowledge.hostile_contacts.has(entity_id):
			var contact := knowledge.hostile_contacts[entity_id] as KnowledgeContact
			if not contact.is_building:
				unit_snapshots.append(UnitSnapshot.new(null, contact))
	var building_ids := buildings.keys()
	building_ids.sort()
	for building_id in building_ids:
		var building := buildings[building_id] as BuildingState
		if building.faction_id == faction_id or knowledge.is_visible(logic_grid.world_to_cell(building.position)):
			var building_snapshot := BuildingSnapshot.new(building)
			building_snapshot.last_seen_tick = current_tick
			building_snapshots.append(building_snapshot)
		elif knowledge.hostile_contacts.has(building_id):
			var contact := knowledge.hostile_contacts[building_id] as KnowledgeContact
			if contact.is_building:
				building_snapshots.append(BuildingSnapshot.new(null, contact))
	for formation_id in formations.keys():
		var formation := formations[formation_id] as FormationState
		if not formation.member_entity_ids.is_empty() and units.has(formation.leader_entity_id) and (units[formation.leader_entity_id] as UnitState).faction_id == faction_id:
			formation_snapshots.append(FormationSnapshot.new(formation))
	for projectile_id in projectiles.keys():
		var projectile := projectiles[projectile_id] as ProjectileState
		if projectile.faction_id == faction_id or knowledge.is_visible(logic_grid.world_to_cell(projectile.position)):
			projectile_snapshots.append(ProjectileSnapshot.new(projectile))
	for faction_id_variant in factions.keys():
		var known_faction_id := int(faction_id_variant)
		faction_snapshots.append(FactionSnapshot.new(factions[known_faction_id] as FactionState, known_faction_id == faction_id))
	for ore_id in ore_fields.keys():
		var ore_field := ore_fields[ore_id] as OreFieldState
		if knowledge.get_cell_state(logic_grid.world_to_cell(ore_field.position)) != FactionKnowledge.CellState.UNEXPLORED:
			ore_snapshots.append(OreFieldSnapshot.new(ore_field))
	return WorldSnapshot.new(current_tick, unit_snapshots, formation_snapshots, projectile_snapshots, metrics.create_snapshot(), faction_snapshots, building_snapshots, ore_snapshots, faction_id, FactionKnowledgeSnapshot.new(knowledge), false, _create_task_snapshots(), MissionSnapshot.new(mission_state))


func _create_task_snapshots() -> Array[TaskSnapshot]:
	var snapshots: Array[TaskSnapshot] = []
	var task_ids := tasks.keys()
	task_ids.sort()
	for task_id in task_ids:
		snapshots.append(TaskSnapshot.new(tasks[task_id] as TaskState))
	return snapshots


func _update_faction_knowledge() -> void:
	var faction_ids := factions.keys()
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if not faction_ids.has(unit.faction_id):
			faction_ids.append(unit.faction_id)
	for building_variant in buildings.values():
		var building := building_variant as BuildingState
		if not faction_ids.has(building.faction_id):
			faction_ids.append(building.faction_id)
	faction_ids.sort()
	for faction_id_variant in faction_ids:
		var faction_id := int(faction_id_variant)
		_ensure_faction_knowledge(faction_id)
		var knowledge := faction_knowledge[faction_id] as FactionKnowledge
		knowledge.begin_update()
		for unit_variant in units.values():
			var unit := unit_variant as UnitState
			if unit.enabled and unit.faction_id == faction_id:
				knowledge.reveal(logic_grid.world_to_cell(unit.position), ceili(unit.sight_range / LogicGrid.CELL_SIZE))
		for building_variant in buildings.values():
			var building := building_variant as BuildingState
			if building.enabled and building.faction_id == faction_id:
				var definition := BUILDING_CATALOG.get_building(building.definition_id)
				var sight_range := definition.sight_range if definition != null else 256.0
				knowledge.reveal(logic_grid.world_to_cell(building.position), ceili(sight_range / LogicGrid.CELL_SIZE))
		_update_contacts(knowledge)
	var local_knowledge := faction_knowledge.get(LOCAL_PLAYER_ID) as FactionKnowledge
	if local_knowledge != null:
		for unit_variant in units.values():
			var unit := unit_variant as UnitState
			unit.is_visible_to_local_player = unit.faction_id == LOCAL_PLAYER_ID or local_knowledge.is_visible(logic_grid.world_to_cell(unit.position))
			if unit.is_visible_to_local_player:
				unit.last_seen_tick = current_tick
				unit.last_seen_position = unit.position


func _ensure_faction_knowledge(faction_id: int) -> void:
	if not faction_knowledge.has(faction_id):
		faction_knowledge[faction_id] = FactionKnowledge.new(faction_id, LogicGrid.GRID_SIZE)


func _update_contacts(knowledge: FactionKnowledge) -> void:
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if unit.faction_id != knowledge.faction_id and knowledge.is_visible(logic_grid.world_to_cell(unit.position)):
			knowledge.hostile_contacts[entity_id] = KnowledgeContact.from_unit(unit, current_tick)
	var building_ids := buildings.keys()
	building_ids.sort()
	for building_id in building_ids:
		var building := buildings[building_id] as BuildingState
		if building.faction_id != knowledge.faction_id and knowledge.is_visible(logic_grid.world_to_cell(building.position)):
			knowledge.hostile_contacts[building_id] = KnowledgeContact.from_building(building, current_tick)


func is_entity_visible_to_faction(entity_id: int, faction_id: int) -> bool:
	_ensure_faction_knowledge(faction_id)
	var knowledge := faction_knowledge[faction_id] as FactionKnowledge
	if units.has(entity_id):
		var unit := units[entity_id] as UnitState
		return unit.faction_id == faction_id or knowledge.is_visible(logic_grid.world_to_cell(unit.position))
	if buildings.has(entity_id):
		var building := buildings[entity_id] as BuildingState
		return building.faction_id == faction_id or knowledge.is_visible(logic_grid.world_to_cell(building.position))
	return false


func is_entity_enabled(entity_id: int) -> bool:
	if units.has(entity_id):
		return (units[entity_id] as UnitState).enabled
	if buildings.has(entity_id):
		return (buildings[entity_id] as BuildingState).enabled
	return false


func get_entity_position(entity_id: int) -> Vector2:
	if units.has(entity_id):
		return (units[entity_id] as UnitState).position
	if buildings.has(entity_id):
		return (buildings[entity_id] as BuildingState).position
	return Vector2.ZERO


func get_entity_faction_id(entity_id: int) -> int:
	if units.has(entity_id):
		return (units[entity_id] as UnitState).faction_id
	if buildings.has(entity_id):
		return (buildings[entity_id] as BuildingState).faction_id
	return 0


func get_attack_destination(entity_id: int, origin: Vector2) -> Vector2:
	if units.has(entity_id):
		return (units[entity_id] as UnitState).position
	var building := buildings.get(entity_id) as BuildingState
	if building == null:
		return origin
	var best_position := building.rally_position
	var best_distance := INF
	for cell in logic_grid.get_footprint_work_cells(building.footprint_cells):
		var candidate := logic_grid.cell_to_world(cell)
		var candidate_path := pathfinder.find_path(origin, candidate)
		if candidate_path.is_empty():
			continue
		var distance := origin.distance_squared_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best_position = candidate
	return best_position


func _drop_hidden_attack_targets() -> void:
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if unit.attack_target_entity_id == 0:
			continue
		var target_faction_id := get_entity_faction_id(unit.attack_target_entity_id)
		if target_faction_id == 0:
			_clear_attack_target(unit, "missing")
			continue
		if target_faction_id != unit.faction_id and not is_entity_visible_to_faction(unit.attack_target_entity_id, unit.faction_id):
			_clear_attack_target(unit, "hidden")


func _update_worker_self_defense() -> void:
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var worker := units[entity_id] as UnitState
		if not worker.enabled or not worker.auto_retaliate or not worker.can_attack or worker.can_accept_attack_orders:
			continue
		if worker.harvest_ore_field_entity_id == 0 and worker.work_kind == UnitState.WorkKind.NONE:
			_clear_attack_target(worker, "worker_idle")
			continue
		if worker.attack_target_entity_id != 0:
			var target_id := worker.attack_target_entity_id
			if is_entity_enabled(target_id) and get_entity_faction_id(target_id) != worker.faction_id and is_entity_visible_to_faction(target_id, worker.faction_id):
				if worker.position.distance_to(get_entity_position(target_id)) <= worker.attack_range * 1.15:
					continue
			_clear_attack_target(worker, "retaliation_range")
		var nearby_target := _find_nearest_enemy_for_faction(worker.position, worker.faction_id, worker.attack_range)
		if nearby_target != 0:
			worker.attack_target_entity_id = nearby_target
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ATTACK_STARTED, worker.entity_id, "target=%d;retaliate=1" % nearby_target))


func _update_combat_orders() -> void:
	for formation_id in formations.keys():
		var formation := formations[formation_id] as FormationState
		if formation.order_kind == FormationState.OrderKind.MOVE:
			continue
		var target_id := formation.order_target_entity_id
		if formation.order_kind == FormationState.OrderKind.ATTACK_MOVE and target_id == 0:
			var leader := units.get(formation.leader_entity_id) as UnitState
			if leader != null:
				target_id = _find_nearest_enemy_for_faction(formation.anchor_position, leader.faction_id, minf(leader.sight_range, 320.0))
			if target_id != 0:
				formation.order_target_entity_id = target_id
		if target_id == 0 or not is_entity_enabled(target_id):
			if formation.order_kind == FormationState.OrderKind.ATTACK_TARGET:
				formation.order_kind = FormationState.OrderKind.IDLE
				formation.engagement_state = FormationState.EngagementState.NONE
				formation.order_target_entity_id = 0
			elif formation.order_kind == FormationState.OrderKind.ATTACK_MOVE and formation.order_target_entity_id != 0:
				formation.order_target_entity_id = 0
				formation.engagement_state = FormationState.EngagementState.NONE
				_resume_formation_route(formation)
			continue
		var target_position := get_entity_position(target_id)
		var all_in_range := true
		for entity_id in formation.member_entity_ids:
			var member := units[entity_id] as UnitState
			if member.enabled and member.following_formation and member.formation_id == formation.formation_id and member.position.distance_to(target_position) > member.attack_range:
				all_in_range = false
				break
		if all_in_range:
			formation.engagement_state = FormationState.EngagementState.ENGAGING
			formation.is_moving = false
			formation.path = PackedVector2Array()
			for entity_id in formation.member_entity_ids:
				var member := units[entity_id] as UnitState
				if member.enabled and member.following_formation and member.formation_id == formation.formation_id:
					member.attack_target_entity_id = target_id
		else:
			formation.engagement_state = FormationState.EngagementState.PURSUING
			if formation.order_kind == FormationState.OrderKind.ATTACK_TARGET:
				var destination := get_attack_destination(target_id, formation.anchor_position)
				if formation.pursuit_target_cell != logic_grid.world_to_cell(destination) or not formation.is_moving:
					formation.target_position = destination
					formation.path = pathfinder.find_path(formation.anchor_position, destination)
					formation.path_index = 1
					formation.is_moving = formation.path.size() > 1
					formation.pursuit_target_cell = logic_grid.world_to_cell(destination)
	_update_individual_combat_orders()


func _update_individual_combat_orders() -> void:
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if not unit.enabled or unit.following_formation or not unit.can_attack:
			continue
		if unit.attack_target_entity_id == 0 and unit.is_attack_moving:
			var acquired_target := _find_nearest_enemy_for_faction(unit.position, unit.faction_id, minf(unit.sight_range, 320.0))
			if acquired_target != 0:
				unit.attack_target_entity_id = acquired_target
				unit.pursuit_target_cell = Vector2i(-1, -1)
				events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ATTACK_STARTED, unit.entity_id, "target=%d;attack_move=1" % acquired_target))
		if unit.attack_target_entity_id == 0:
			if unit.is_attack_moving and not unit.has_move_target and unit.position.distance_to(unit.attack_move_destination) > FormationMovementSystem.ARRIVAL_TOLERANCE:
				_start_individual_attack_path(unit, unit.attack_move_destination)
			continue
		var target_id := unit.attack_target_entity_id
		if not is_entity_enabled(target_id) or get_entity_faction_id(target_id) == unit.faction_id:
			_clear_attack_target(unit, "invalid")
			continue
		var target_position := get_entity_position(target_id)
		if unit.position.distance_to(target_position) <= unit.attack_range:
			unit.has_move_target = false
			unit.path = PackedVector2Array()
			unit.path_index = 0
			unit.pursuit_target_cell = logic_grid.world_to_cell(target_position)
			continue
		if not unit.can_accept_attack_orders:
			continue
		var destination := get_attack_destination(target_id, unit.position)
		var destination_cell := logic_grid.world_to_cell(destination)
		if unit.pursuit_target_cell != destination_cell or not unit.has_move_target:
			_start_individual_attack_path(unit, destination)
			unit.pursuit_target_cell = destination_cell


func _start_individual_attack_path(unit: UnitState, destination: Vector2) -> void:
	unit.path = pathfinder.find_path(unit.position, destination)
	unit.path_index = 1
	unit.has_move_target = unit.path.size() > 1


func _resume_formation_route(formation: FormationState) -> void:
	formation.target_position = formation.order_destination
	formation.path = pathfinder.find_path(formation.anchor_position, formation.order_destination)
	formation.path_index = 1
	formation.is_moving = formation.path.size() > 1
	for entity_id in formation.member_entity_ids:
		var member := units[entity_id] as UnitState
		if member.enabled:
			member.attack_target_entity_id = 0
			member.is_attack_moving = true
			member.following_formation = true
			member.has_move_target = formation.is_moving


func _find_nearest_enemy_for_faction(origin: Vector2, faction_id: int, radius: float) -> int:
	var best_id := 0
	var best_distance := INF
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if not unit.enabled or unit.faction_id == faction_id or not is_entity_visible_to_faction(unit.entity_id, faction_id):
			continue
		var distance := origin.distance_squared_to(unit.position)
		if distance <= radius * radius and (distance < best_distance or (is_equal_approx(distance, best_distance) and unit.entity_id < best_id)):
			best_id = unit.entity_id
			best_distance = distance
	for building_variant in buildings.values():
		var building := building_variant as BuildingState
		if not building.enabled or building.faction_id == faction_id or not is_entity_visible_to_faction(building.entity_id, faction_id):
			continue
		var distance := origin.distance_squared_to(building.position)
		if distance <= radius * radius and (distance < best_distance or (is_equal_approx(distance, best_distance) and building.entity_id < best_id)):
			best_id = building.entity_id
			best_distance = distance
	return best_id


func _begin_player_takeover(unit: UnitState, command: GameCommand, preserve_formation: bool = false) -> void:
	unit.last_command_id = command.command_id
	unit.last_command_tick = current_tick
	if unit.control_state != UnitState.ControlState.AGENT_ASSIGNED:
		return
	unit.control_state = UnitState.ControlState.TEMPORARILY_OVERRIDDEN
	unit.return_task_id = unit.assigned_task_id
	unit.original_formation_id = unit.formation_id
	unit.takeover_reason = command.get_class()
	if unit.definition_id == &"missile_vehicle":
		mission_state.missile_taken_over = true
	if not preserve_formation:
		_remove_unit_from_formation(unit)
	if tasks.has(unit.assigned_task_id):
		var task := tasks[unit.assigned_task_id] as TaskState
		task.remove_participant(unit.entity_id)
		task.set_lifecycle(TaskState.Lifecycle.BLOCKED, current_tick, TaskState.BlockedReason.PARTICIPANT_OVERRIDDEN, "E%d temporarily overridden by player" % unit.entity_id)
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, task.task_id, "BLOCKED:PARTICIPANT_OVERRIDDEN"))
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_CONTROL_CHANGED, unit.entity_id, "TEMPORARILY_OVERRIDDEN;task=%d" % unit.return_task_id))


func _apply_disposition(command: UnitDispositionCommand) -> void:
	var unit := units[command.target_entity_id] as UnitState
	match command.disposition:
		UnitDispositionCommand.Disposition.RETURN:
			_start_rejoin(unit, unit.original_formation_id, unit.return_task_id)
		UnitDispositionCommand.Disposition.JOIN:
			_start_rejoin(unit, command.destination_formation_id, 0)
		UnitDispositionCommand.Disposition.STAY:
			_detach_unit(unit, UnitState.ControlState.UNASSIGNED)
		UnitDispositionCommand.Disposition.MANUAL:
			_detach_unit(unit, UnitState.ControlState.PLAYER_CONTROLLED)


func _detach_unit(unit: UnitState, state: UnitState.ControlState) -> void:
	unit.control_state = state
	unit.assigned_agent_id = 0
	unit.assigned_task_id = 0
	unit.return_task_id = 0
	_remove_unit_from_formation(unit)
	unit.rejoin_pending = false
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_CONTROL_CHANGED, unit.entity_id, UnitState.ControlState.keys()[state]))


func _start_rejoin(unit: UnitState, formation_id: int, task_id: int) -> void:
	if not formations.has(formation_id):
		return
	var formation := formations[formation_id] as FormationState
	var slot_id := formation.get_slot_id(unit.entity_id)
	if slot_id < 0:
		slot_id = formation.add_member(unit.entity_id)
	var rejoin_point := formation.sample_anchor_history(FormationMovementSystem.COLUMN_SPACING * slot_id)
	if formation.mode == FormationState.MovementMode.WIDE:
		var tangent := formation.initial_path_direction
		var lateral := Vector2(-tangent.y, tangent.x)
		var offset := formation.get_wide_offset(slot_id)
		rejoin_point = formation.anchor_position + tangent * offset.x + lateral * offset.y
	var rejoin_path := pathfinder.find_path_to_first_reachable(unit.position, rejoin_point, formation.anchor_history)
	if rejoin_path.is_empty():
		if task_id != 0 and tasks.has(task_id):
			(tasks[task_id] as TaskState).set_lifecycle(TaskState.Lifecycle.BLOCKED, current_tick, TaskState.BlockedReason.PATH_UNAVAILABLE, "E%d cannot reach formation" % unit.entity_id)
		return
	unit.rejoin_formation_id = formation_id
	unit.rejoin_slot_id = slot_id
	unit.rejoin_pending = true
	unit.path = rejoin_path
	unit.path_index = 1
	unit.has_move_target = rejoin_path.size() > 1
	unit.move_target = rejoin_point
	unit.following_formation = false
	unit.control_state = UnitState.ControlState.TEMPORARILY_OVERRIDDEN
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_REJOIN_STARTED, unit.entity_id, "formation=%d;slot=%d" % [formation_id, slot_id]))


func _complete_rejoins() -> void:
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if not unit.rejoin_pending or unit.has_move_target:
			continue
		unit.formation_id = unit.rejoin_formation_id
		unit.formation_slot_id = unit.rejoin_slot_id
		unit.following_formation = true
		unit.rejoin_pending = false
		if unit.return_task_id != 0 and tasks.has(unit.return_task_id):
			var task := tasks[unit.return_task_id] as TaskState
			task.add_participant(unit.entity_id)
			task.set_lifecycle(TaskState.Lifecycle.EXECUTING, current_tick)
			if task.kind != TaskState.Kind.FORMATION_MOVE_TEST:
				task.set_phase(TaskState.Phase.PREPARING, current_tick, "Participant returned; task resumed")
			else:
				for agent in agents:
					if agent.task_id == task.task_id:
						agent.command_issued = false
			unit.assigned_task_id = task.task_id
			unit.assigned_agent_id = task.agent_id
			unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
		else:
			unit.control_state = UnitState.ControlState.UNASSIGNED
		if unit.definition_id == &"missile_vehicle" and mission_state.missile_taken_over:
			mission_state.missile_returned = true
			mission_state.update_completed(current_tick)
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_REJOIN_COMPLETED, unit.entity_id, "formation=%d" % unit.formation_id))


func _apply_command(command: GameCommand) -> void:
	if command is StrategicOrderCommand:
		_apply_strategic_order(command as StrategicOrderCommand)
		return
	if command is TaskControlCommand:
		_apply_task_control(command as TaskControlCommand)
		return
	if command is UnitDispositionCommand:
		_apply_disposition(command as UnitDispositionCommand)
		return
	if command is BuildBuildingCommand:
		_apply_build(command as BuildBuildingCommand)
		return
	if command is RepairBuildingCommand:
		_apply_repair(command as RepairBuildingCommand)
		return
	if command is HarvestCommand:
		var harvest := command as HarvestCommand
		var harvester := units[harvest.target_entity_id] as UnitState
		harvester.harvest_ore_field_entity_id = harvest.ore_field_entity_id
		harvester.harvest_refinery_entity_id = harvest.refinery_building_entity_id
		harvester.harvest_phase = UnitState.HarvestPhase.TO_FIELD
		harvester.harvest_ticks_remaining = 0
		harvester.cargo_ore = 0
		_prepare_manual_worker(harvester)
		_start_unit_path(harvester, (ore_fields[harvest.ore_field_entity_id] as OreFieldState).position)
	elif command is ProduceUnitCommand:
		var production := command as ProduceUnitCommand
		var factory := buildings[production.target_entity_id] as BuildingState
		var definition := UNIT_CATALOG.get_unit(production.unit_definition_id)
		(factions[factory.faction_id] as FactionState).ore -= definition.production_cost
		factory.production_definition_id = definition.definition_id
		factory.production_ticks_remaining = definition.production_ticks
		factory.production_cost_paid = definition.production_cost
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.PRODUCTION_STARTED, factory.entity_id, "definition=%s;cost=%d" % [definition.definition_id, definition.production_cost]))
	elif command is StopCommand:
		_apply_stop(command as StopCommand)
	elif command is AttackCommand:
		_apply_attack(command as AttackCommand)
	elif command is FormationMoveCommand:
		var formation_command := command as FormationMoveCommand
		if formation_command.formation_id == 0:
			var unit := units[formation_command.target_entity_id] as UnitState
			_cancel_unit_job(unit)
			_clear_attack_target(unit, "command_move")
			_remove_unit_from_formation(unit)
			unit.move_target = formation_command.target_position
			unit.attack_move_destination = formation_command.target_position
			unit.path = pathfinder.find_path(unit.position, unit.move_target)
			unit.path_index = 1
			unit.has_move_target = unit.path.size() > 1
			unit.is_attack_moving = command is AttackMoveCommand
			unit.pursuit_target_cell = Vector2i(-1, -1)
			return
		if command is AttackMoveCommand:
			_detach_noncombat_members(formation_command.formation_id)
		var formation := formations[formation_command.formation_id] as FormationState
		formation.order_kind = FormationState.OrderKind.ATTACK_MOVE if command is AttackMoveCommand else FormationState.OrderKind.MOVE
		formation.engagement_state = FormationState.EngagementState.NONE
		formation.order_destination = formation_command.target_position
		formation.order_target_entity_id = 0
		formation.pursuit_target_cell = Vector2i(-1, -1)
		formation.target_position = formation_command.target_position
		formation.path = pathfinder.find_path(formation.anchor_position, formation.target_position)
		formation.path_index = 1
		formation.is_moving = formation.path.size() > 1
		formation.clear_corridor_ticks = 0
		var initial_direction := Vector2.RIGHT
		if formation.path.size() > 1:
			initial_direction = formation.path[1] - formation.path[0]
		formation.reset_anchor_history(initial_direction)
		for entity_id in formation.member_entity_ids:
			var member := units[entity_id] as UnitState
			_cancel_unit_job(member)
			_clear_attack_target(member, "command_move")
			member.formation_id = formation.formation_id
			member.formation_slot_id = formation.get_slot_id(member.entity_id)
			member.following_formation = true
			member.has_move_target = formation.is_moving
			member.move_target = formation.target_position
			member.is_attack_moving = command is AttackMoveCommand
			member.is_recovering = false
			member.recovery_path = PackedVector2Array()
			member.recovery_path_index = 0
			member.recovery_attempts = 0
			member.ticks_without_progress = 0
	elif command is MoveCommand:
		var unit := units[command.target_entity_id] as UnitState
		_cancel_unit_job(unit)
		_clear_attack_target(unit, "command_move")
		_remove_unit_from_formation(unit)
		unit.move_target = (command as MoveCommand).target_position
		unit.path = pathfinder.find_path(unit.position, unit.move_target)
		unit.path_index = 1
		unit.has_move_target = unit.path.size() > 1
		unit.is_attack_moving = false
		unit.attack_move_destination = unit.position
		unit.pursuit_target_cell = Vector2i(-1, -1)


func _apply_build(command: BuildBuildingCommand) -> void:
	var engineer := units[command.target_entity_id] as UnitState
	_cancel_unit_job(engineer)
	var definition := BUILDING_CATALOG.get_building(command.building_definition_id)
	var faction := factions[engineer.faction_id] as FactionState
	faction.ore -= definition.build_cost
	var snapped_position := logic_grid.cell_to_world(logic_grid.world_to_cell(command.build_position))
	var building := BuildingState.new(
		_next_building_id,
		definition.definition_id,
		engineer.faction_id,
		engineer.controller_id,
		snapped_position,
		definition.max_health
	)
	_next_building_id += 1
	building.armor = definition.armor
	building.health = definition.max_health * 0.1
	building.operational = false
	building.under_construction = true
	building.construction_ticks_total = definition.build_ticks
	building.construction_ticks_remaining = definition.build_ticks
	building.builder_entity_id = engineer.entity_id
	building.footprint_cells = logic_grid.get_footprint_cells(snapped_position, definition.footprint_size)
	building.rally_position = _default_work_position(building.footprint_cells, snapped_position)
	buildings[building.entity_id] = building
	_set_building_occupancy(building, true)
	_prepare_manual_worker(engineer)
	engineer.work_kind = UnitState.WorkKind.CONSTRUCT
	engineer.work_target_building_id = building.entity_id
	_start_unit_path_to_building(engineer, building)
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.BUILDING_PLACED, building.entity_id, "definition=%s;builder=%d;cost=%d" % [definition.definition_id, engineer.entity_id, definition.build_cost]))


func _apply_repair(command: RepairBuildingCommand) -> void:
	var engineer := units[command.target_entity_id] as UnitState
	_cancel_unit_job(engineer)
	var building := buildings[command.building_entity_id] as BuildingState
	_prepare_manual_worker(engineer)
	engineer.work_kind = UnitState.WorkKind.REPAIR
	engineer.work_target_building_id = building.entity_id
	_start_unit_path_to_building(engineer, building)
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.REPAIR_STARTED, building.entity_id, "engineer=%d" % engineer.entity_id))


func _prepare_manual_worker(unit: UnitState) -> void:
	_clear_attack_target(unit, "work_order")
	_remove_unit_from_formation(unit)
	unit.is_attack_moving = false
	unit.work_kind = UnitState.WorkKind.NONE
	unit.work_target_building_id = 0


func _cancel_unit_job(unit: UnitState) -> void:
	if unit.work_target_building_id != 0 and buildings.has(unit.work_target_building_id):
		var work_building := buildings[unit.work_target_building_id] as BuildingState
		if work_building.builder_entity_id == unit.entity_id:
			work_building.builder_entity_id = 0
	unit.work_kind = UnitState.WorkKind.NONE
	unit.work_target_building_id = 0
	unit.harvest_ore_field_entity_id = 0
	unit.harvest_refinery_entity_id = 0
	unit.harvest_ticks_remaining = 0
	unit.harvest_phase = UnitState.HarvestPhase.IDLE
	unit.cargo_ore = 0


func _start_unit_path(unit: UnitState, destination: Vector2) -> void:
	unit.move_target = destination
	unit.desired_position = destination
	unit.path = pathfinder.find_path(unit.position, destination)
	unit.path_index = 1
	unit.has_move_target = unit.path.size() > 1


func _start_unit_path_to_building(unit: UnitState, building: BuildingState) -> void:
	var best_path := PackedVector2Array()
	for cell in logic_grid.get_footprint_work_cells(building.footprint_cells):
		var candidate_path := pathfinder.find_path(unit.position, logic_grid.cell_to_world(cell))
		if candidate_path.is_empty():
			continue
		if best_path.is_empty() or candidate_path.size() < best_path.size():
			best_path = candidate_path
	unit.path = best_path
	unit.path_index = 1
	unit.has_move_target = best_path.size() > 1
	unit.move_target = best_path[-1] if not best_path.is_empty() else unit.position
	unit.desired_position = unit.move_target


func _apply_strategic_order(command: StrategicOrderCommand) -> void:
	if command.order_kind in [StrategicOrderCommand.OrderKind.DEFEND_AREA, StrategicOrderCommand.OrderKind.ATTACK_TARGET]:
		_detach_noncombat_members(command.formation_id)
	var resolved_formation_id := command.formation_id
	if command.order_kind in [StrategicOrderCommand.OrderKind.DEFEND_AREA, StrategicOrderCommand.OrderKind.ATTACK_TARGET, StrategicOrderCommand.OrderKind.SCOUT_AREA] and resolved_formation_id == 0:
		resolved_formation_id = _create_task_formation(command.participant_entity_ids)
	var participants: Array[int] = []
	var agent_id := StrategicTaskSystem.BATTLEFIELD_AGENT_ID
	var kind := TaskState.Kind.DEFEND_AREA
	match command.order_kind:
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE:
			agent_id = StrategicTaskSystem.INDUSTRIAL_AGENT_ID
			kind = TaskState.Kind.DEVELOP_RESOURCE
			var unit_ids := units.keys()
			unit_ids.sort()
			for entity_id in unit_ids:
				var unit := units[entity_id] as UnitState
				if unit.enabled and unit.faction_id == command.issuer_id and unit.definition_id == &"harvester":
					participants.append(entity_id)
					break
		StrategicOrderCommand.OrderKind.DEFEND_AREA:
			kind = TaskState.Kind.DEFEND_AREA
			participants = _combat_participants(resolved_formation_id)
		StrategicOrderCommand.OrderKind.ATTACK_TARGET:
			kind = TaskState.Kind.ATTACK_TARGET
			participants = _combat_participants(resolved_formation_id)
		StrategicOrderCommand.OrderKind.SCOUT_AREA:
			kind = TaskState.Kind.SCOUT_AREA
			participants = _scout_participants(resolved_formation_id)
	var task := TaskState.new(_next_task_id, agent_id, participants)
	_next_task_id += 1
	task.faction_id = command.issuer_id
	task.kind = kind
	task.formation_id = resolved_formation_id
	task.target_entity_id = command.objective_entity_id
	task.target_position = command.target_position
	task.target_radius = command.target_radius
	task.accepted_tick = current_tick
	task.requires_proactive_authorization = command.issuer_kind == GameCommand.IssuerKind.AGENT
	task.progress_target = 2 if kind == TaskState.Kind.DEVELOP_RESOURCE else (StrategicTaskSystem.SCOUT_OBSERVE_TICKS if kind == TaskState.Kind.SCOUT_AREA else StrategicTaskSystem.DEFEND_HOLD_TICKS)
	if kind == TaskState.Kind.DEVELOP_RESOURCE:
		task.baseline_value = (ore_fields[command.objective_entity_id] as OreFieldState).ore_remaining
		task.expected_unit_count = _count_friendly_definition(&"harvester")
	elif resolved_formation_id != 0:
		var formation := formations[resolved_formation_id] as FormationState
		task.route = pathfinder.find_path(formation.anchor_position, command.target_position)
	task.set_lifecycle(TaskState.Lifecycle.EXECUTING, current_tick)
	task.set_phase(TaskState.Phase.PREPARING, current_tick, "Assigned to %s" % ("industrial supervisor" if agent_id == StrategicTaskSystem.INDUSTRIAL_AGENT_ID else "battlefield commander"))
	tasks[task.task_id] = task
	for entity_id in participants:
		var unit := units[entity_id] as UnitState
		unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
		unit.assigned_agent_id = task.agent_id
		unit.assigned_task_id = task.task_id
		unit.original_formation_id = unit.formation_id
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, task.task_id, "EXECUTING:%s" % TaskState.Kind.keys()[task.kind]))


func _create_task_formation(participant_entity_ids: Array[int]) -> int:
	var valid_ids: Array[int] = []
	var anchor := Vector2.ZERO
	for entity_id in participant_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit == null or not unit.enabled:
			continue
		valid_ids.append(entity_id)
		anchor += unit.position
	if valid_ids.is_empty():
		return 0
	anchor /= valid_ids.size()
	for entity_id in valid_ids:
		_remove_unit_from_formation(units[entity_id] as UnitState)
	var formation := FormationState.new(_next_formation_id, valid_ids, anchor)
	_next_formation_id += 1
	formations[formation.formation_id] = formation
	for entity_id in valid_ids:
		var unit := units[entity_id] as UnitState
		unit.formation_id = formation.formation_id
		unit.formation_slot_id = formation.get_slot_id(entity_id)
		unit.following_formation = true
		unit.desired_position = anchor + formation.get_wide_offset(unit.formation_slot_id)
	return formation.formation_id


func _apply_task_control(command: TaskControlCommand) -> void:
	var task := tasks[command.controlled_task_id] as TaskState
	match command.action:
		TaskControlCommand.Action.PAUSE:
			task.set_lifecycle(TaskState.Lifecycle.PAUSED, current_tick, TaskState.BlockedReason.NONE, "Paused by player")
			_stop_task_formation(task)
		TaskControlCommand.Action.RESUME:
			task.set_lifecycle(TaskState.Lifecycle.EXECUTING, current_tick, TaskState.BlockedReason.NONE, "Resumed by player")
			if task.kind in [TaskState.Kind.DEFEND_AREA, TaskState.Kind.ATTACK_TARGET]:
				task.set_phase(TaskState.Phase.PREPARING, current_tick, "Replanning after resume")
		TaskControlCommand.Action.CANCEL:
			task.set_lifecycle(TaskState.Lifecycle.CANCELLED, current_tick, TaskState.BlockedReason.NONE, "Cancelled by player")
			task.set_phase(TaskState.Phase.DONE, current_tick, "Cancelled by player")
			_stop_task_formation(task)
			release_task_participants(task)
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, task.task_id, "%s:%s" % [TaskState.Lifecycle.keys()[task.lifecycle], task.last_detail]))


func _stop_task_formation(task: TaskState) -> void:
	if task.formation_id == 0 or not formations.has(task.formation_id):
		return
	var formation := formations[task.formation_id] as FormationState
	_apply_stop(StopCommand.new(allocate_command_id(), LOCAL_PLAYER_ID, GameCommand.IssuerKind.AGENT, current_tick, formation.leader_entity_id, formation.formation_id))


func release_task_participants(task: TaskState) -> void:
	for entity_id in task.participant_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit == null or unit.assigned_task_id != task.task_id or unit.control_state == UnitState.ControlState.TEMPORARILY_OVERRIDDEN:
			continue
		unit.control_state = UnitState.ControlState.UNASSIGNED
		unit.assigned_agent_id = 0
		unit.assigned_task_id = 0


func _count_friendly_definition(definition_id: StringName) -> int:
	var count := 0
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.faction_id == LOCAL_PLAYER_ID and unit.definition_id == definition_id:
			count += 1
	return count


func _apply_attack(command: AttackCommand) -> void:
	var entity_ids: Array[int] = []
	if command.formation_id != 0:
		_detach_noncombat_members(command.formation_id)
		var formation := formations[command.formation_id] as FormationState
		formation.is_moving = false
		formation.path = PackedVector2Array()
		formation.target_position = formation.anchor_position
		formation.order_kind = FormationState.OrderKind.ATTACK_TARGET
		formation.engagement_state = FormationState.EngagementState.PURSUING
		formation.order_destination = formation.anchor_position
		formation.order_target_entity_id = command.attack_target_entity_id
		entity_ids.assign(formation.member_entity_ids)
	else:
		entity_ids.append(command.target_entity_id)
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if not unit.can_attack or not unit.can_accept_attack_orders:
			continue
		var preserve_harvest := unit.can_harvest and unit.harvest_ore_field_entity_id != 0
		if not preserve_harvest:
			_cancel_unit_job(unit)
		if command.formation_id != 0:
			var formation := formations[command.formation_id] as FormationState
			unit.formation_id = formation.formation_id
			unit.formation_slot_id = formation.get_slot_id(unit.entity_id)
			unit.following_formation = true
		else:
			_remove_unit_from_formation(unit)
		if not preserve_harvest:
			unit.has_move_target = false
			unit.path = PackedVector2Array()
			unit.path_index = 0
			unit.move_target = unit.position
			unit.desired_position = unit.position
			unit.is_recovering = false
			unit.recovery_path = PackedVector2Array()
			unit.recovery_path_index = 0
			unit.is_attack_moving = false
			unit.attack_move_destination = unit.position
		unit.pursuit_target_cell = Vector2i(-1, -1)
		unit.attack_target_entity_id = command.attack_target_entity_id
		events.append(SimulationEvent.new(
			current_tick,
			SimulationEvent.Kind.ATTACK_STARTED,
			unit.entity_id,
			"target=%d" % command.attack_target_entity_id
		))


func _combat_participants(formation_id: int) -> Array[int]:
	var result: Array[int] = []
	if not formations.has(formation_id):
		return result
	for entity_id in (formations[formation_id] as FormationState).member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled and unit.can_attack and unit.can_accept_attack_orders:
			result.append(entity_id)
	return result


func _scout_participants(formation_id: int) -> Array[int]:
	var result: Array[int] = []
	if not formations.has(formation_id):
		return result
	for entity_id in (formations[formation_id] as FormationState).member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled and unit.definition_id == &"scout_vehicle":
			result.append(entity_id)
	return result


func _detach_noncombat_members(formation_id: int) -> void:
	if not formations.has(formation_id):
		return
	var formation := formations[formation_id] as FormationState
	var member_ids := formation.member_entity_ids.duplicate()
	for entity_id in member_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and (not unit.can_attack or not unit.can_accept_attack_orders):
			_remove_unit_from_formation(unit)


func _clear_attack_target(unit: UnitState, reason: String) -> void:
	if unit.attack_target_entity_id == 0:
		return
	var target_id := unit.attack_target_entity_id
	unit.attack_target_entity_id = 0
	unit.pursuit_target_cell = Vector2i(-1, -1)
	events.append(SimulationEvent.new(
		current_tick,
		SimulationEvent.Kind.TARGET_LOST,
		unit.entity_id,
		"target=%d;reason=%s" % [target_id, reason]
	))


func _apply_stop(command: StopCommand) -> void:
	var entity_ids: Array[int] = []
	if command.formation_id != 0:
		var formation := formations[command.formation_id] as FormationState
		formation.is_moving = false
		formation.path = PackedVector2Array()
		formation.target_position = formation.anchor_position
		formation.order_kind = FormationState.OrderKind.IDLE
		formation.engagement_state = FormationState.EngagementState.NONE
		formation.order_target_entity_id = 0
		entity_ids.assign(formation.member_entity_ids)
	else:
		entity_ids.append(command.target_entity_id)
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		_cancel_unit_job(unit)
		_clear_attack_target(unit, "command_stop")
		if command.formation_id == 0:
			_remove_unit_from_formation(unit)
		unit.has_move_target = false
		unit.path = PackedVector2Array()
		unit.path_index = 0
		unit.move_target = unit.position
		unit.desired_position = unit.position
		unit.is_recovering = false
		unit.recovery_path = PackedVector2Array()
		unit.recovery_path_index = 0
		unit.is_attack_moving = false
		unit.attack_move_destination = unit.position
		unit.pursuit_target_cell = Vector2i(-1, -1)


func _remove_unit_from_formation(unit: UnitState) -> void:
	var previous_formation_id := unit.formation_id
	if previous_formation_id != 0 and formations.has(previous_formation_id):
		(formations[previous_formation_id] as FormationState).remove_member(unit.entity_id)
	unit.formation_id = 0
	unit.formation_slot_id = -1
	unit.following_formation = false


func _cleanup_expired_wrecks() -> void:
	var expired_ids: Array[int] = []
	for entity_id in units.keys():
		var unit := units[entity_id] as UnitState
		if not unit.enabled and unit.death_tick >= 0 and current_tick - unit.death_tick >= WRECK_LIFETIME_TICKS:
			expired_ids.append(entity_id)
	for entity_id in expired_ids:
		var unit := units[entity_id] as UnitState
		_remove_unit_from_formation(unit)
		for task_variant in tasks.values():
			(task_variant as TaskState).remove_participant(entity_id)
		for knowledge_variant in faction_knowledge.values():
			(knowledge_variant as FactionKnowledge).hostile_contacts.erase(entity_id)
		units.erase(entity_id)


func _update_victory() -> void:
	var alive_command_centers: Dictionary = {}
	for faction_id in factions.keys():
		alive_command_centers[faction_id] = 0
	for building_variant in buildings.values():
		var building := building_variant as BuildingState
		if building.definition_id == &"command_center" and building.enabled and building.health > 0.0:
			alive_command_centers[building.faction_id] = int(alive_command_centers.get(building.faction_id, 0)) + 1
	for faction_id in factions.keys():
		var faction := factions[faction_id] as FactionState
		if int(alive_command_centers.get(faction_id, 0)) == 0 and not faction.defeated:
			faction.defeated = true
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.FACTION_DEFEATED, faction_id))
	for faction_id in factions.keys():
		var faction := factions[faction_id] as FactionState
		if faction.defeated or faction.victorious:
			continue
		var all_opponents_defeated := true
		for opponent_id in factions.keys():
			if opponent_id != faction_id and not (factions[opponent_id] as FactionState).defeated:
				all_opponents_defeated = false
		if all_opponents_defeated:
			faction.victorious = true
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.FACTION_VICTORIOUS, faction_id))


func destroy_building(entity_id: int) -> void:
	if not buildings.has(entity_id):
		return
	var building := buildings[entity_id] as BuildingState
	building.health = 0.0
	building.enabled = false
	building.operational = false
	building.under_construction = false
	_set_building_occupancy(building, false)
	building.footprint_cells.clear()


func _set_building_occupancy(building: BuildingState, occupied: bool) -> void:
	for cell in building.footprint_cells:
		logic_grid.set_blocked(cell, occupied)


func _release_destroyed_building_occupancy() -> void:
	for building_variant in buildings.values():
		var building := building_variant as BuildingState
		if building.enabled or building.footprint_cells.is_empty():
			continue
		_set_building_occupancy(building, false)
		building.footprint_cells.clear()


func _default_work_position(footprint_cells: Array[Vector2i], fallback: Vector2) -> Vector2:
	var candidates := logic_grid.get_footprint_work_cells(footprint_cells)
	if candidates.is_empty():
		return fallback
	return logic_grid.cell_to_world(candidates[0])


func spawn_enemy_raid_unit(entity_id: int, agent_id: int, task_id: int, definition_id: StringName = &"assault_vehicle") -> UnitState:
	if units.has(entity_id):
		return units[entity_id] as UnitState
	var definition := UNIT_CATALOG.get_unit(definition_id)
	var spawn_position := logic_grid.cell_to_world(LogicGrid.MAP_DEFINITION.enemy_spawn_cell + Vector2i(-4, -4))
	var unit := UnitState.new(entity_id, spawn_position, definition.move_speed, ENEMY_PLAYER_ID)
	_apply_unit_definition(unit, definition)
	unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
	unit.assigned_agent_id = agent_id
	unit.assigned_task_id = task_id
	units[entity_id] = unit
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_PRODUCED, entity_id, "enemy_raid"))
	_update_faction_knowledge()
	return unit


func _advance_unit(unit: UnitState) -> void:
	if not unit.enabled or not unit.has_move_target:
		return
	var travel_remaining := unit.move_speed * TICK_SECONDS
	while travel_remaining > 0.0 and unit.has_move_target:
		var waypoint := unit.path[unit.path_index]
		var offset := waypoint - unit.position
		if offset.length() <= travel_remaining:
			unit.position = waypoint
			travel_remaining -= offset.length()
			unit.path_index += 1
			if unit.path_index >= unit.path.size():
				unit.has_move_target = false
				unit.path = PackedVector2Array()
				events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_ARRIVED, unit.entity_id))
		else:
			unit.position += offset.normalized() * travel_remaining
			travel_remaining = 0.0
