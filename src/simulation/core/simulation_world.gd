class_name SimulationWorld
extends RefCounted

const TICK_SECONDS := 0.1
const BATTLEFIELD_BOUNDS := Rect2(Vector2.ZERO, Vector2(3072.0, 2048.0))
const INITIAL_UNIT_ID := 1
const DEFAULT_FORMATION_ID := 1
const LOCAL_PLAYER_ID := 1
const ENEMY_PLAYER_ID := 2
const DEFAULT_ENEMY_UNIT_ID := 1001
const PLAYER_COMMAND_CENTER_ID := 2001
const PLAYER_FACTORY_ID := 2002
const PLAYER_SUPPORT_ID := 2003
const ENEMY_COMMAND_CENTER_ID := 2101
const DEFAULT_ORE_FIELD_ID := 3001
const TEST_AGENT_ID := 101
const TEST_TASK_ID := 1
const UNIT_CATALOG: UnitDefinitionCatalog = preload("res://data/units/unit_catalog.tres")
const BUILDING_CATALOG: BuildingDefinitionCatalog = preload("res://data/buildings/building_catalog.tres")
const DEFAULT_UNIT_DEFINITION: UnitDefinition = preload("res://data/units/scout_vehicle.tres")

var current_tick: int = 0
var units: Dictionary = {}
var formations: Dictionary = {}
var factions: Dictionary = {}
var buildings: Dictionary = {}
var ore_fields: Dictionary = {}
var faction_knowledge: Dictionary = {}
var tasks: Dictionary = {}
var agents: Array[DeterministicFormationAgent] = []
var enemy_raid_agent := EnemyRaidAgent.new()
var mission_state := MissionState.new()
var command_queue := CommandQueue.new()
var command_validator := CommandValidator.new()
var logic_grid := LogicGrid.create_test_map()
var metrics := SimulationMetrics.new()
var pathfinder := GridPathfinder.new(logic_grid, metrics)
var formation_movement := FormationMovementSystem.new(logic_grid, pathfinder)
var combat_system := CombatSystem.new()
var economy_system := EconomySystem.new()
var strategic_task_system := StrategicTaskSystem.new()
var events: Array[SimulationEvent] = []
var projectiles: Dictionary = {}
var _next_projectile_id: int = 1
var _next_unit_id: int = 1100
var _next_command_id: int = 1
var _next_task_id: int = 1


func _init(create_default_units: bool = true, create_test_agent: bool = false) -> void:
	if create_default_units:
		_setup_default_scenario()
	_update_faction_knowledge()
	if create_default_units and create_test_agent:
		_create_default_agent_task()


func _create_default_agent_task() -> void:
	var task := TaskState.new(_next_task_id, TEST_AGENT_ID, [1, 2, 3, 4, 5])
	_next_task_id += 1
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
	factions[ENEMY_PLAYER_ID] = FactionState.new(ENEMY_PLAYER_ID, ENEMY_PLAYER_ID, 300)
	_create_default_formation()
	_create_default_enemy()
	_create_default_buildings()
	ore_fields[DEFAULT_ORE_FIELD_ID] = OreFieldState.new(DEFAULT_ORE_FIELD_ID, logic_grid.cell_to_world(Vector2i(18, 8)), 1200)


func _create_default_buildings() -> void:
	_add_building(PLAYER_COMMAND_CENTER_ID, &"command_center", LOCAL_PLAYER_ID, logic_grid.cell_to_world(Vector2i(4, 8)))
	_add_building(PLAYER_FACTORY_ID, &"automated_factory", LOCAL_PLAYER_ID, logic_grid.cell_to_world(Vector2i(7, 8)))
	_add_building(PLAYER_SUPPORT_ID, &"forward_support_station", LOCAL_PLAYER_ID, logic_grid.cell_to_world(Vector2i(10, 8)))
	_add_building(ENEMY_COMMAND_CENTER_ID, &"command_center", ENEMY_PLAYER_ID, logic_grid.cell_to_world(Vector2i(78, 8)))


func _add_building(entity_id: int, definition_id: StringName, faction_id: int, position: Vector2) -> void:
	var definition := BUILDING_CATALOG.get_building(definition_id)
	var building := BuildingState.new(entity_id, definition_id, faction_id, faction_id, position, definition.max_health)
	buildings[entity_id] = building


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
	var anchor := logic_grid.cell_to_world(LogicGrid.MAP_DEFINITION.player_spawn_cell)
	var enemy_position := anchor + Vector2(64.0, 0.0)
	var enemy := UnitState.new(DEFAULT_ENEMY_UNIT_ID, enemy_position, 0.0, ENEMY_PLAYER_ID)
	_apply_unit_definition(enemy, DEFAULT_UNIT_DEFINITION)
	enemy.max_health = 240.0
	enemy.health = enemy.max_health
	enemy.attack_damage = 0.0
	units[enemy.entity_id] = enemy


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


func allocate_command_id() -> int:
	var allocated := _next_command_id
	_next_command_id += 1
	return allocated


func submit_command(command: GameCommand) -> CommandValidationResult:
	_update_faction_knowledge()
	var result := command_validator.validate(command, units, BATTLEFIELD_BOUNDS, pathfinder, formations, buildings, ore_fields, factions, UNIT_CATALOG, BUILDING_CATALOG, faction_knowledge, logic_grid, tasks)
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


func _is_direct_player_order(command: GameCommand) -> bool:
	if command.issuer_kind != GameCommand.IssuerKind.PLAYER:
		return false
	return command is MoveCommand or command is FormationMoveCommand or command is StopCommand or command is AttackCommand or command is HarvestCommand


func advance_tick() -> WorldSnapshot:
	var event_start := events.size()
	var commands := command_queue.drain()
	metrics.record_commands_applied(commands.size())
	for command in commands:
		_apply_command(command)
	for agent in agents:
		agent.advance(self)
	strategic_task_system.advance(self)
	enemy_raid_agent.advance(self)
	_update_faction_knowledge()
	_drop_hidden_attack_targets()
	_update_combat_orders()
	formation_movement.advance(formations, units, events, current_tick)
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if not unit.following_formation:
			_advance_unit(unit)
	_complete_rejoins()
	_next_projectile_id = combat_system.advance(units, projectiles, _next_projectile_id, events, current_tick)
	_next_unit_id = economy_system.advance(units, buildings, ore_fields, factions, UNIT_CATALOG, BUILDING_CATALOG, _next_unit_id, events, current_tick)
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


func _drop_hidden_attack_targets() -> void:
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if unit.attack_target_entity_id == 0 or not units.has(unit.attack_target_entity_id):
			continue
		var target := units[unit.attack_target_entity_id] as UnitState
		if target.faction_id != unit.faction_id and not is_entity_visible_to_faction(target.entity_id, unit.faction_id):
			_clear_attack_target(unit, "hidden")


func _update_combat_orders() -> void:
	for formation_id in formations.keys():
		var formation := formations[formation_id] as FormationState
		if formation.order_kind == FormationState.OrderKind.MOVE:
			continue
		var target_id := formation.order_target_entity_id
		if formation.order_kind == FormationState.OrderKind.ATTACK_MOVE and target_id == 0:
			target_id = _find_nearest_enemy(formation.anchor_position, 320.0)
			if target_id != 0:
				formation.order_target_entity_id = target_id
		if target_id == 0 or not units.has(target_id) or not (units[target_id] as UnitState).enabled:
			if formation.order_kind == FormationState.OrderKind.ATTACK_TARGET:
				formation.order_kind = FormationState.OrderKind.IDLE
				formation.engagement_state = FormationState.EngagementState.NONE
				formation.order_target_entity_id = 0
			elif formation.order_kind == FormationState.OrderKind.ATTACK_MOVE and formation.order_target_entity_id != 0:
				formation.order_target_entity_id = 0
				formation.engagement_state = FormationState.EngagementState.NONE
				_resume_formation_route(formation)
			continue
		var target := units[target_id] as UnitState
		var all_in_range := true
		for entity_id in formation.member_entity_ids:
			var member := units[entity_id] as UnitState
			if member.enabled and member.following_formation and member.formation_id == formation.formation_id and member.position.distance_to(target.position) > member.attack_range:
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
				var destination := target.position
				if formation.pursuit_target_cell != logic_grid.world_to_cell(destination) or not formation.is_moving:
					formation.target_position = destination
					formation.path = pathfinder.find_path(formation.anchor_position, destination)
					formation.path_index = 1
					formation.is_moving = formation.path.size() > 1
					formation.pursuit_target_cell = logic_grid.world_to_cell(destination)


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


func _find_nearest_enemy(origin: Vector2, radius: float) -> int:
	var best_id := 0
	var best_distance := INF
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if not unit.enabled or unit.faction_id == LOCAL_PLAYER_ID or not is_entity_visible_to_faction(unit.entity_id, LOCAL_PLAYER_ID):
			continue
		var distance := origin.distance_squared_to(unit.position)
		if distance <= radius * radius and (distance < best_distance or (is_equal_approx(distance, best_distance) and unit.entity_id < best_id)):
			best_id = unit.entity_id
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
		unit.following_formation = false
		unit.formation_id = 0
		unit.formation_slot_id = -1
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
	unit.formation_id = 0
	unit.formation_slot_id = -1
	unit.following_formation = false
	unit.rejoin_pending = false
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_CONTROL_CHANGED, unit.entity_id, UnitState.ControlState.keys()[state]))


func _start_rejoin(unit: UnitState, formation_id: int, task_id: int) -> void:
	if not formations.has(formation_id):
		return
	var formation := formations[formation_id] as FormationState
	var slot_id := formation.get_slot_id(unit.entity_id)
	if slot_id < 0:
		slot_id = formation.member_entity_ids.size()
		formation.member_entity_ids.append(unit.entity_id)
		formation.member_entity_ids.sort()
		formation.slot_by_entity_id[unit.entity_id] = slot_id
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
	if command is HarvestCommand:
		var harvest := command as HarvestCommand
		var harvester := units[harvest.target_entity_id] as UnitState
		harvester.harvest_ore_field_entity_id = harvest.ore_field_entity_id
		harvester.harvest_refinery_entity_id = harvest.refinery_building_entity_id
		harvester.harvest_ticks_remaining = EconomySystem.HARVEST_INTERVAL_TICKS
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
		var formation := formations[formation_command.formation_id] as FormationState
		formation.order_kind = FormationState.OrderKind.ATTACK_MOVE if command is AttackMoveCommand else FormationState.OrderKind.MOVE
		formation.engagement_state = FormationState.EngagementState.NONE
		formation.order_destination = formation_command.target_position
		formation.order_target_entity_id = 0
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
			_clear_attack_target(member, "command_move")
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
		_clear_attack_target(unit, "command_move")
		unit.following_formation = false
		unit.move_target = (command as MoveCommand).target_position
		unit.path = pathfinder.find_path(unit.position, unit.move_target)
		unit.path_index = 1
		unit.has_move_target = unit.path.size() > 1
		unit.is_attack_moving = false


func _apply_strategic_order(command: StrategicOrderCommand) -> void:
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
			participants.assign((formations[command.formation_id] as FormationState).member_entity_ids)
		StrategicOrderCommand.OrderKind.ATTACK_TARGET:
			kind = TaskState.Kind.ATTACK_TARGET
			participants.assign((formations[command.formation_id] as FormationState).member_entity_ids)
	var task := TaskState.new(_next_task_id, agent_id, participants)
	_next_task_id += 1
	task.kind = kind
	task.formation_id = command.formation_id
	task.target_entity_id = command.objective_entity_id
	task.target_position = command.target_position
	task.target_radius = command.target_radius
	task.accepted_tick = current_tick
	task.progress_target = 2 if kind == TaskState.Kind.DEVELOP_RESOURCE else StrategicTaskSystem.DEFEND_HOLD_TICKS
	if kind == TaskState.Kind.DEVELOP_RESOURCE:
		task.baseline_value = (ore_fields[command.objective_entity_id] as OreFieldState).ore_remaining
		task.expected_unit_count = _count_friendly_definition(&"harvester")
	elif command.formation_id != 0:
		var formation := formations[command.formation_id] as FormationState
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
		unit.has_move_target = false
		unit.path = PackedVector2Array()
		unit.path_index = 0
		unit.move_target = unit.position
		unit.desired_position = unit.position
		unit.is_recovering = false
		unit.recovery_path = PackedVector2Array()
		unit.recovery_path_index = 0
		unit.is_attack_moving = false
		unit.attack_target_entity_id = command.attack_target_entity_id
		events.append(SimulationEvent.new(
			current_tick,
			SimulationEvent.Kind.ATTACK_STARTED,
			unit.entity_id,
			"target=%d" % command.attack_target_entity_id
		))


func _clear_attack_target(unit: UnitState, reason: String) -> void:
	if unit.attack_target_entity_id == 0:
		return
	var target_id := unit.attack_target_entity_id
	unit.attack_target_entity_id = 0
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
		_clear_attack_target(unit, "command_stop")
		unit.has_move_target = false
		unit.path = PackedVector2Array()
		unit.path_index = 0
		unit.move_target = unit.position
		unit.desired_position = unit.position
		unit.is_recovering = false
		unit.recovery_path = PackedVector2Array()
		unit.recovery_path_index = 0
		unit.is_attack_moving = false


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


func spawn_enemy_raid_unit(entity_id: int, agent_id: int, task_id: int) -> UnitState:
	if units.has(entity_id):
		return units[entity_id] as UnitState
	var definition := UNIT_CATALOG.get_unit(&"assault_vehicle")
	var spawn_position := logic_grid.cell_to_world(Vector2i(70, 12))
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
