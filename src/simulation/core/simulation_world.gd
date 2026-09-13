class_name SimulationWorld
extends RefCounted

enum ScenarioKind {
	LEGACY_RTS,
	GREY_RIDGE,
	BROKEN_BRIDGE,
	FOG_FOREST,
	BLACK_WELL,
}

const TICK_SECONDS := 0.1
const BATTLEFIELD_BOUNDS := Rect2(Vector2.ZERO, Vector2(6144.0, 4096.0))
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
const COMMANDER_AGENT_BAI_JIUYANG := 201
const COMMANDER_AGENT_DI_TIAN := 202
const COMMANDER_AGENT_LIN_MO := 203
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
const COMMANDER_BAI_JIUYANG: CommanderDefinition = preload("res://data/army/bai_jiuyang.tres")
const COMMANDER_DI_TIAN: CommanderDefinition = preload("res://data/army/di_tian.tres")
const UNIT_CARD_FALCON: UnitCardDefinition = preload("res://data/army/falcon_recon_group.tres")
const UNIT_CARD_IRONWALL: UnitCardDefinition = preload("res://data/army/ironwall_assault_group.tres")
const COMMANDER_LIN_MO: CommanderDefinition = preload("res://data/army/lin_mo.tres")
const UNIT_CARD_ARMORED_SPEARHEAD: UnitCardDefinition = preload("res://data/army/armored_spearhead.tres")
const UNIT_CARD_THUNDER_FIRE: UnitCardDefinition = preload("res://data/army/thunder_fire_group.tres")
const DOCTRINE_COVERT_SEARCH: DoctrineDefinition = preload("res://data/army/covert_search.tres")
const DOCTRINE_ALTERNATING_COVER: DoctrineDefinition = preload("res://data/army/alternating_cover.tres")
const DOCTRINE_FIRE_PREPARATION: DoctrineDefinition = preload("res://data/army/fire_preparation.tres")
const DOCTRINE_CONCENTRATED_BREAKTHROUGH: DoctrineDefinition = preload("res://data/army/concentrated_breakthrough.tres")
const GREY_RIDGE_SUPPLY_INTERVAL_TICKS := 200
const GREY_RIDGE_REGION_INTERVAL_TICKS := 300
const GREY_RIDGE_TIME_LIMIT_TICKS := 4800
const GREY_RIDGE_FALCON_FORMATION_ID := 1
const GREY_RIDGE_IRONWALL_FORMATION_ID := 2
const GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID := 3
const GREY_RIDGE_ENEMY_PROBE_FORMATION_ID := 4
const GREY_RIDGE_ENEMY_PROBE_FIRST_ENTITY_ID := DEFAULT_ENEMY_UNIT_ID + 12
const GREY_RIDGE_DEPLOYMENT_RADIUS := 384.0
const GREY_RIDGE_REGION_RADIUS := 220.0
const SUPPORT_COST := 2
const SUPPORT_DURATION_TICKS := 200
const SUPPORT_COOLDOWN_TICKS := 300
const CENTRAL_RELAY_SUPPORT_COOLDOWN_TICKS := 150
const FIELD_REINFORCEMENT_STRENGTH := 2
const FORTIFICATION_ARMOR_BONUS := 4.0
const GREY_RIDGE_WEST_POSITION := Vector2(1440.0, 2080.0)
const GREY_RIDGE_CENTRAL_POSITION := Vector2(3072.0, 2080.0)
const GREY_RIDGE_EAST_POSITION := Vector2(4704.0, 2080.0)
const WRECK_LIFETIME_TICKS := 70
const FRIENDLY_AUTONOMY_INTERVAL_TICKS := 5
const FRIENDLY_DEFENSE_RADIUS := 448.0
const FRIENDLY_SCOUT_RADIUS := 96.0
const AUTONOMY_PRIORITY_SCOUT := 20
const AUTONOMY_PRIORITY_DEFEND := 40
const AUTONOMY_PRIORITY_ATTACK := 80
const AUTONOMY_PRIORITY_BASE_THREAT := 100
const REGION_CAPTURE_DECAY_PER_TICK := 2
const ENEMY_STRATEGIC_DECISION_INTERVAL_TICKS := 50
const ENEMY_STRATEGIC_PRIORITY_SCOUT := 35
const ENEMY_STRATEGIC_PRIORITY_CAPTURE := 55
const ENEMY_STRATEGIC_PRIORITY_ATTACK := 90
const COORDINATED_ENGAGEMENT_TICKS := 60
const COMMANDER_THREAT_CLUSTER_RADIUS := 360.0
const COMMANDER_SUPPORT_DISTANCE := 1280.0
const FORMATION_AUTO_ENGAGE_RADIUS := 420.0
const COMMANDER_PRIMARY_POWER_RATIO := 0.85
const COMMANDER_REINFORCED_POWER_RATIO := 1.05
const GREY_RIDGE_OPENING_COMMITMENT_TICKS := 180
const GREY_RIDGE_FEINT_REDIRECT_TICK := 240
const GREY_RIDGE_FEINT_COMMITMENT_TICKS := 300
const GREY_RIDGE_OFFENSIVE_FOLLOWUP_TICK := 1800
const ENEMY_PLAN_CENTRAL_ASSAULT: StringName = &"central_assault"
const ENEMY_PLAN_WESTERN_HOOK: StringName = &"western_hook"
const ENEMY_PLAN_WESTERN_FEINT: StringName = &"western_feint"

var current_tick: int = 0
var scenario_kind: ScenarioKind = ScenarioKind.LEGACY_RTS
var units: Dictionary = {}
var formations: Dictionary = {}
var factions: Dictionary = {}
var buildings: Dictionary = {}
var ore_fields: Dictionary = {}
var faction_knowledge: Dictionary = {}
var tasks: Dictionary = {}
var agent_policies: Dictionary = {}
var commanders: Dictionary = {}
var unit_cards: Dictionary = {}
var strategic_regions: Dictionary = {}
var battle_definition: BattleDefinition
var doctrine_definitions: Dictionary = {
	&"covert_search": DOCTRINE_COVERT_SEARCH,
	&"alternating_cover": DOCTRINE_ALTERNATING_COVER,
	&"fire_preparation": DOCTRINE_FIRE_PREPARATION,
	&"concentrated_breakthrough": DOCTRINE_CONCENTRATED_BREAKTHROUGH,
}
var air_recon_until_by_faction: Dictionary = {}
var intel_reports: Array[IntelReportState] = []
var enemy_reaction_rules: Array[EnemyReactionRuleState] = []
var opened_engineering_routes: Dictionary = {}
var enemy_reaction_committed_until_tick: int = GREY_RIDGE_OPENING_COMMITMENT_TICKS
var enemy_reaction_log: Array[String] = []
var enemy_opening_plan_id: StringName = ENEMY_PLAN_CENTRAL_ASSAULT
var enemy_opening_followup_executed: bool = false
var enemy_offensive_followup_executed: bool = false
var escort_supply_node_active: bool = false
var enemy_escort_intercept_target_id: int = 0
var enemy_escort_observed_tick: int = -1
var grey_ridge_army_plan: ArmyPlan = ArmyPlan.grey_ridge_default()
var _next_intel_report_id: int = 1
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
var tactical_ability_system := TacticalAbilitySystem.new()
var economy_system := EconomySystem.new()
var engineering_system := EngineeringSystem.new()
var strategic_task_system := StrategicTaskSystem.new()
var strategic_headquarters := StrategicHeadquarters.new()
var objective_system := ObjectiveSystem.new()
var _doctrine_effect_registry := DoctrineEffectRegistry.new()
var battle_outcome := BattleOutcome.new()
var events: Array[SimulationEvent] = []
var projectiles: Dictionary = {}
var _next_projectile_id: int = 1
var _next_unit_id: int = 1100
var _next_formation_id: int = 2
var _next_building_id: int = FIRST_CONSTRUCTED_BUILDING_ID
var _next_command_id: int = 1
var staff_plan_system := StaffPlanSystem.new()
var _next_task_id: int = 1
var _last_friendly_autonomy_tick: int = -FRIENDLY_AUTONOMY_INTERVAL_TICKS
var _next_enemy_strategic_decision_tick: int = 0
var _is_advancing_tick: bool = false
var tick_profile_enabled: bool = false
var last_tick_profile_usec: Dictionary = {}


func _init(
	create_default_units: bool = true,
	create_test_agent: bool = false,
	new_scenario_kind: ScenarioKind = ScenarioKind.LEGACY_RTS,
	army_roster_record: Dictionary = {},
	locked_enemy_opening_plan_id: StringName = &"",
	army_plan: ArmyPlan = null
) -> void:
	scenario_kind = new_scenario_kind
	if is_card_battle():
		var content_result := BattleContentLoader.load_battle(scenario_id_for_kind(scenario_kind))
		if not content_result.is_valid():
			push_error("Battle content '%s' is invalid: %s" % [scenario_id_for_kind(scenario_kind), content_result.validation.issues])
			return
		battle_definition = content_result.battle
		objective_system.configure(battle_definition.objective_set)
		battle_outcome = objective_system.outcome
		_configure_battle_navigation()
		doctrine_definitions = battle_definition.doctrine_dictionary()
		enemy_opening_plan_id = _select_enemy_opening_plan(army_roster_record, locked_enemy_opening_plan_id)
		grey_ridge_army_plan = army_plan.duplicate_plan() if army_plan != null else battle_definition.create_default_army_plan()
		if not get_grey_ridge_army_plan_errors(grey_ridge_army_plan).is_empty():
			grey_ridge_army_plan = battle_definition.create_default_army_plan()
	_configure_ai()
	if create_default_units:
		if is_card_battle():
			_setup_grey_ridge_scenario()
			ArmyRosterStore.apply_to_world(self, army_roster_record)
		else:
			_setup_default_scenario()
	_update_faction_knowledge()
	if create_default_units and create_test_agent and scenario_kind == ScenarioKind.LEGACY_RTS:
		_create_default_agent_task()
	_update_commander_behavior_feedback()


static func scenario_id_for_kind(kind: ScenarioKind) -> StringName:
	match kind:
		ScenarioKind.GREY_RIDGE:
			return &"grey_ridge"
		ScenarioKind.BROKEN_BRIDGE:
			return &"broken_bridge"
		ScenarioKind.FOG_FOREST:
			return &"fog_forest"
		ScenarioKind.BLACK_WELL:
			return &"black_well"
	return &"legacy_rts"


static func is_card_battle_kind(kind: ScenarioKind) -> bool:
	return kind in [ScenarioKind.GREY_RIDGE, ScenarioKind.BROKEN_BRIDGE, ScenarioKind.FOG_FOREST, ScenarioKind.BLACK_WELL]


func is_card_battle() -> bool:
	return is_card_battle_kind(scenario_kind)


func get_scenario_id() -> StringName:
	return battle_definition.scenario_id if battle_definition != null else scenario_id_for_kind(scenario_kind)


func _configure_battle_navigation() -> void:
	logic_grid = LogicGrid.create_for_battle(battle_definition)
	pathfinder = GridPathfinder.new(logic_grid, metrics)
	formation_movement = FormationMovementSystem.new(logic_grid, pathfinder)


func _select_enemy_opening_plan(record: Dictionary, requested_plan_id: StringName) -> StringName:
	var plan_ids := battle_definition.enemy_plan_dictionary().keys() if battle_definition != null else [ENEMY_PLAN_CENTRAL_ASSAULT, ENEMY_PLAN_WESTERN_HOOK, ENEMY_PLAN_WESTERN_FEINT]
	plan_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	if plan_ids.is_empty():
		return &""
	if plan_ids.has(requested_plan_id):
		return requested_plan_id
	var preferred_order: Array[StringName] = [ENEMY_PLAN_CENTRAL_ASSAULT, ENEMY_PLAN_WESTERN_HOOK, ENEMY_PLAN_WESTERN_FEINT]
	var ordered_ids: Array[StringName] = []
	for preferred_id in preferred_order:
		if plan_ids.has(preferred_id):
			ordered_ids.append(preferred_id)
	for plan_id in plan_ids:
		if not ordered_ids.has(plan_id):
			ordered_ids.append(plan_id)
	return ordered_ids[int(record.get("battle_count", 0)) % ordered_ids.size()]


func get_grey_ridge_army_plan_errors(plan: ArmyPlan) -> Array[StringName]:
	if plan == null:
		return [&"ARMY_PLAN_ERROR_MISSING"]
	return plan.validation_errors(
		_grey_ridge_commander_definitions(),
		_grey_ridge_unit_card_definitions(),
		doctrine_definitions,
		_battle_commander_ids(),
		_battle_unit_card_ids(),
		battle_definition.starting_card_count if battle_definition != null else ArmyPlan.STARTING_CARD_COUNT
	)


func _grey_ridge_commander_definitions() -> Dictionary:
	if battle_definition != null:
		return battle_definition.commander_dictionary()
	return {
		COMMANDER_BAI_JIUYANG.definition_id: COMMANDER_BAI_JIUYANG,
		COMMANDER_DI_TIAN.definition_id: COMMANDER_DI_TIAN,
		COMMANDER_LIN_MO.definition_id: COMMANDER_LIN_MO,
	}


func _grey_ridge_unit_card_definitions() -> Dictionary:
	if battle_definition != null:
		return battle_definition.unit_card_dictionary()
	return {
		UNIT_CARD_FALCON.definition_id: UNIT_CARD_FALCON,
		UNIT_CARD_IRONWALL.definition_id: UNIT_CARD_IRONWALL,
		UNIT_CARD_ARMORED_SPEARHEAD.definition_id: UNIT_CARD_ARMORED_SPEARHEAD,
		UNIT_CARD_THUNDER_FIRE.definition_id: UNIT_CARD_THUNDER_FIRE,
	}


func _battle_commander_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_grey_ridge_commander_definitions().keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


func _battle_unit_card_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_grey_ridge_unit_card_definitions().keys())
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


func _battlefield_bounds() -> Rect2:
	return battle_definition.battlefield_bounds if battle_definition != null else BATTLEFIELD_BOUNDS


func _configure_ai() -> void:
	agent_policies.clear()
	_register_agent_policy(INDUSTRIAL_POLICY)
	_register_agent_policy(BATTLEFIELD_POLICY)
	_register_agent_policy(ENEMY_POLICY)
	if battle_definition != null and battle_definition.enemy_agent_id != ENEMY_POLICY.agent_id:
		var scenario_enemy_policy := ENEMY_POLICY.duplicate(true) as AgentPolicy
		scenario_enemy_policy.agent_id = battle_definition.enemy_agent_id
		agent_policies[scenario_enemy_policy.agent_id] = scenario_enemy_policy
	_register_named_commander_policy(COMMANDER_AGENT_BAI_JIUYANG)
	_register_named_commander_policy(COMMANDER_AGENT_DI_TIAN)
	_register_named_commander_policy(COMMANDER_AGENT_LIN_MO)
	if battle_definition != null:
		for agent_id_variant in battle_definition.commander_agent_ids.values():
			var commander_agent_id := int(agent_id_variant)
			if not agent_policies.has(commander_agent_id):
				_register_named_commander_policy(commander_agent_id)
	var test_policy := AgentPolicy.new()
	test_policy.agent_id = TEST_AGENT_ID
	test_policy.faction_id = LOCAL_PLAYER_ID
	test_policy.domain = AgentPolicy.Domain.TEST
	test_policy.authorization = AgentPolicy.Authorization.ASSISTED
	agent_policies[test_policy.agent_id] = test_policy
	enemy_raid_agent = EnemyRaidAgent.new(ENEMY_DIFFICULTY_NORMAL.duplicate(true) as EnemyDifficultyProfile)


func _register_named_commander_policy(agent_id: int) -> void:
	var policy := AgentPolicy.new()
	policy.agent_id = agent_id
	policy.faction_id = LOCAL_PLAYER_ID
	policy.domain = AgentPolicy.Domain.BATTLEFIELD
	policy.authorization = AgentPolicy.Authorization.ASSISTED
	agent_policies[agent_id] = policy


func _register_agent_policy(template: AgentPolicy) -> void:
	var policy := template.duplicate(true) as AgentPolicy
	agent_policies[policy.agent_id] = policy


func set_agent_authorization(agent_id: int, authorization: AgentPolicy.Authorization) -> bool:
	var policy := agent_policies.get(agent_id) as AgentPolicy
	if policy == null or policy.domain == AgentPolicy.Domain.ENEMY:
		return false
	policy.authorization = authorization
	if agent_id in [StrategicTaskSystem.INDUSTRIAL_AGENT_ID, StrategicTaskSystem.BATTLEFIELD_AGENT_ID]:
		if authorization != AgentPolicy.Authorization.AUTONOMOUS and strategic_headquarters.directive != StrategicHeadquarters.Directive.NONE:
			strategic_headquarters.set_directive(StrategicHeadquarters.Directive.NONE)
		elif strategic_headquarters.directive == StrategicHeadquarters.Directive.NONE and get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID) == AgentPolicy.Authorization.AUTONOMOUS and get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID) == AgentPolicy.Authorization.AUTONOMOUS:
			strategic_headquarters.set_directive(StrategicHeadquarters.Directive.BALANCED)
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
	_setup_default_army_roster()
	_create_default_enemy()
	_create_default_buildings()
	ore_fields[DEFAULT_ORE_FIELD_ID] = OreFieldState.new(DEFAULT_ORE_FIELD_ID, logic_grid.cell_to_world(Vector2i(20, 10)), PRIMARY_ORE_CAPACITY)
	ore_fields[ENEMY_ORE_FIELD_ID] = OreFieldState.new(ENEMY_ORE_FIELD_ID, logic_grid.cell_to_world(LogicGrid.MAP_DEFINITION.enemy_spawn_cell + Vector2i(-6, 3)), PRIMARY_ORE_CAPACITY)
	ore_fields[PLAYER_EXPANSION_ORE_FIELD_ID] = OreFieldState.new(PLAYER_EXPANSION_ORE_FIELD_ID, logic_grid.cell_to_world(Vector2i(34, 22)), EXPANSION_ORE_CAPACITY)
	ore_fields[ENEMY_EXPANSION_ORE_FIELD_ID] = OreFieldState.new(ENEMY_EXPANSION_ORE_FIELD_ID, logic_grid.cell_to_world(Vector2i(67, 43)), EXPANSION_ORE_CAPACITY)


func _setup_grey_ridge_scenario() -> void:
	var local_faction := FactionState.new(LOCAL_PLAYER_ID, LOCAL_PLAYER_ID, 0)
	local_faction.supply = battle_definition.starting_supply
	local_faction.supply_capacity = battle_definition.supply_capacity
	local_faction.population = 0
	local_faction.population_capacity = battle_definition.population_capacity
	factions[LOCAL_PLAYER_ID] = local_faction
	var enemy_faction := FactionState.new(ENEMY_PLAYER_ID, ENEMY_PLAYER_ID, 0)
	enemy_faction.population = 0
	enemy_faction.population_capacity = battle_definition.population_capacity
	enemy_faction.supply_capacity = battle_definition.supply_capacity
	factions[ENEMY_PLAYER_ID] = enemy_faction
	for region_definition in battle_definition.strategic_regions:
		strategic_regions[region_definition.region_id] = StrategicRegionState.new(
			region_definition.region_id, region_definition.display_name_key, region_definition.terrain_key,
			region_definition.position, region_definition.radius, region_definition.supply_per_settlement,
			region_definition.adjacent_region_ids, region_definition.support_cooldown_ticks,
			region_definition.capturable, region_definition.capture_ticks
		)
	for intel in battle_definition.initial_intel:
		_add_intel_report(
			LOCAL_PLAYER_ID, intel.source_key, intel.target_category_key, intel.estimated_min, intel.estimated_max,
			intel.region_id, intel.direction_key, intel.confidence_key, intel.eta_min_ticks, intel.eta_max_ticks,
			intel.has_estimate
		)

	_add_building(PLAYER_COMMAND_CENTER_ID, &"command_center", LOCAL_PLAYER_ID, battle_definition.player_headquarters_position)
	_add_building(ENEMY_COMMAND_CENTER_ID, &"command_center", ENEMY_PLAYER_ID, battle_definition.enemy_headquarters_position)

	var friendly_member_ids_by_card: Dictionary = {}
	var next_friendly_entity_id := INITIAL_UNIT_ID
	for index in range(grey_ridge_army_plan.starting_unit_card_ids.size()):
		var unit_card_id := grey_ridge_army_plan.starting_unit_card_ids[index]
		var card_definition := _grey_ridge_unit_card_definitions()[unit_card_id] as UnitCardDefinition
		var member_ids := _create_scenario_formation(
			battle_definition.friendly_formation_ids[index],
			LOCAL_PLAYER_ID,
			card_definition.unit_definition_id,
			card_definition.authorized_strength,
			battle_definition.friendly_spawn_positions[index],
			next_friendly_entity_id,
			Vector2.DOWN, 0, 0, UnitCardCompositionCompiler.expand(card_definition)
		)
		friendly_member_ids_by_card[unit_card_id] = member_ids
		next_friendly_entity_id += member_ids.size()
	for formation_definition in battle_definition.enemy_formations:
		var member_ids := _create_scenario_formation(
			formation_definition.formation_id, formation_definition.faction_id,
			formation_definition.unit_definition_id, formation_definition.strength,
			formation_definition.spawn_position, formation_definition.first_entity_id,
			formation_definition.facing, formation_definition.agent_id, formation_definition.task_id
		)
		for entity_id in member_ids:
			(units[entity_id] as UnitState).tactical_role = formation_definition.tactical_role as UnitState.TacticalRole
		if formation_definition.unit_card_definition != null:
			var enemy_card := UnitCardState.new(formation_definition.unit_card_definition, formation_definition.faction_id, member_ids)
			enemy_card.formation_id = formation_definition.formation_id
			enemy_card.deployment_state = UnitCardState.DeploymentState.DEPLOYED
			enemy_card.control_state = UnitCardState.ControlState.AGENT_ASSIGNED
			enemy_card.assigned_agent_id = formation_definition.agent_id
			enemy_card.assigned_task_id = formation_definition.task_id
			enemy_card.organization_enabled = battle_definition.organization_max > 0.0
			enemy_card.organization = battle_definition.organization_max
			_bind_unit_card_members(enemy_card)
			_reset_unit_card_organization_baseline(enemy_card)
			unit_cards[enemy_card.definition.definition_id] = enemy_card
	_setup_grey_ridge_army_roster(friendly_member_ids_by_card)
	_initialize_grey_ridge_commander_tasks()
	_setup_grey_ridge_enemy_reaction_table()
	_next_unit_id = battle_definition.next_dynamic_unit_id
	_next_formation_id = battle_definition.next_dynamic_formation_id

	var assault_definition := battle_definition.enemy_formation_by_role(&"assault")
	var probe_definition := battle_definition.enemy_formation_by_role(&"probe")
	var enemy_formation := formations[assault_definition.formation_id] as FormationState
	var enemy_probe := formations[probe_definition.formation_id] as FormationState
	_apply_grey_ridge_opening_plan(enemy_formation, enemy_probe)
	_refresh_battle_population()


func _apply_grey_ridge_opening_plan(enemy_formation: FormationState, enemy_probe: FormationState) -> void:
	var plan := battle_definition.enemy_plan_dictionary().get(enemy_opening_plan_id) as BattleEnemyPlanDefinition
	if plan == null:
		return
	var assault_target := plan.assault_target_position
	var assault_route := PackedVector2Array()
	for region_id in plan.assault_route_region_ids:
		var region_definition := battle_definition.region_dictionary().get(region_id) as BattleRegionDefinition
		if region_definition != null:
			assault_route.append(region_definition.position)
	var probe_target := plan.probe_target_position
	var action := String(plan.action_key)
	enemy_reaction_committed_until_tick = plan.commitment_ticks
	_apply_locked_formation_move(enemy_formation, assault_target, assault_route)
	_apply_locked_formation_move(enemy_probe, probe_target)
	enemy_reaction_log.append("tick=0;source=LOCKED_OPENING_PLAN;plan=%s;action=%s;formations=%d,%d;commit_until=%d" % [
		enemy_opening_plan_id, action, enemy_formation.formation_id, enemy_probe.formation_id,
		enemy_reaction_committed_until_tick,
	])


func _apply_locked_formation_move(formation: FormationState, target: Vector2, route: PackedVector2Array = PackedVector2Array()) -> void:
	var command := FormationMoveCommand.new(
		allocate_command_id(), ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT, current_tick,
		formation.leader_entity_id, formation.formation_id, target, route
	)
	command.agent_id = battle_definition.enemy_agent_id
	command.task_id = battle_definition.enemy_task_id
	_apply_command(command)


func _setup_grey_ridge_enemy_reaction_table() -> void:
	enemy_reaction_rules.clear()
	for definition in battle_definition.enemy_reaction_rules:
		enemy_reaction_rules.append(EnemyReactionRuleState.new(
			definition.rule_id, definition.priority,
			definition.trigger_kind as EnemyReactionRuleState.TriggerKind,
			definition.action_kind as EnemyReactionRuleState.ActionKind,
			definition.delay_ticks, definition.commitment_ticks
		))


func _setup_grey_ridge_army_roster(friendly_member_ids_by_card: Dictionary) -> void:
	for commander_id in _battle_commander_ids():
		var definition := _grey_ridge_commander_definitions()[commander_id] as CommanderDefinition
		var commander := CommanderState.new(definition, LOCAL_PLAYER_ID)
		commander.agent_id = int(battle_definition.commander_agent_ids[commander_id])
		commander.posture = int(grey_ridge_army_plan.posture_by_commander[commander_id]) as CommanderState.Posture
		commander.available_doctrine_ids.assign(definition.available_doctrine_ids)
		commander.equip_doctrine(grey_ridge_army_plan.doctrine_by_commander[commander_id] as StringName)
		commanders[commander_id] = commander
	var card_definitions := _grey_ridge_unit_card_definitions()
	for unit_card_id in _battle_unit_card_ids():
		var member_ids: Array[int] = []
		member_ids.assign(friendly_member_ids_by_card.get(unit_card_id, []))
		var unit_card := UnitCardState.new(card_definitions[unit_card_id] as UnitCardDefinition, LOCAL_PLAYER_ID, member_ids)
		unit_card.organization_enabled = battle_definition.organization_max > 0.0
		unit_card.organization = battle_definition.organization_max if unit_card.organization_enabled else 0.0
		unit_card.commander_definition_id = grey_ridge_army_plan.commander_by_unit_card[unit_card_id] as StringName
		unit_card.deployment_state = UnitCardState.DeploymentState.DEPLOYED if not member_ids.is_empty() else UnitCardState.DeploymentState.RESERVE
		if unit_card.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
			unit_card.formation_id = battle_definition.friendly_formation_ids[grey_ridge_army_plan.starting_unit_card_ids.find(unit_card_id)]
		_bind_unit_card_members(unit_card)
		_reset_unit_card_organization_baseline(unit_card)
		unit_cards[unit_card_id] = unit_card
		(commanders[unit_card.commander_definition_id] as CommanderState).attach_unit_card(unit_card_id)


func _bind_unit_card_members(unit_card: UnitCardState) -> void:
	var role := UnitState.TacticalRole.NONE
	match unit_card.definition.role_key:
		&"UNIT_CARD_ROLE_RECON":
			role = UnitState.TacticalRole.SCOUT
		&"UNIT_CARD_ROLE_ASSAULT":
			role = UnitState.TacticalRole.ASSAULT
		&"UNIT_CARD_ROLE_ARMOR":
			role = UnitState.TacticalRole.ARMOR
		&"UNIT_CARD_ROLE_FIREPOWER":
			role = UnitState.TacticalRole.FIREPOWER
	for entity_id in unit_card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null:
			unit.unit_card_id = unit_card.definition.definition_id
			var ability := unit_card.definition.tactical_ability
			if not unit.card_weapon_initialized and unit_card.definition.tactical_weapon_override != null and ability != null and unit.definition_id == ability.required_unit_id:
				unit.configure_tactical_weapon(unit_card.definition.tactical_weapon_override)
				unit.card_weapon_initialized = true
			if unit.composition_entry_id.is_empty():
				unit.composition_entry_id = &"main"
			var entry := unit_card.get_composition_entry(unit.composition_entry_id)
			if entry != null:
				if not entry.member_entity_ids.has(entity_id):
					entry.member_entity_ids.append(entity_id)
				unit.tactical_role = UnitCardCompositionCompiler.ROLES.find(entry.formation_role) as UnitState.TacticalRole
			else:
				unit.tactical_role = role
	apply_unit_card_persistent_modifiers(unit_card)


func apply_unit_card_persistent_modifiers(unit_card: UnitCardState) -> void:
	var attack_multiplier := 1.0
	var armor_bonus := 0.0
	var move_speed_multiplier := 1.0
	var sight_range_multiplier := 1.0
	var attack_range_multiplier := 1.0
	for growth_id in [unit_card.honor_id, unit_card.equipment_id]:
		var growth: Variant = ArmyRosterStore.GROWTH_CATALOG.get_growth(growth_id)
		if growth == null:
			continue
		attack_multiplier *= growth.attack_multiplier
		armor_bonus += growth.armor_bonus
		move_speed_multiplier *= growth.move_speed_multiplier
		sight_range_multiplier *= growth.sight_range_multiplier
		attack_range_multiplier *= growth.attack_range_multiplier
	for entity_id in unit_card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit == null or not unit.enabled:
			continue
		var definition := UNIT_CATALOG.get_unit(unit.definition_id)
		if definition == null or definition.combat == null:
			continue
		unit.base_move_speed = definition.move_speed
		unit.base_armor = definition.combat.armor
		unit.base_attack_damage = definition.combat.attack_power
		unit.base_attack_range = definition.combat.attack_range
		unit.base_sight_range = definition.sight_range
		unit.base_attack_damage *= attack_multiplier
		unit.base_armor = maxf(0.0, unit.base_armor + armor_bonus)
		unit.base_move_speed *= move_speed_multiplier
		unit.base_sight_range *= sight_range_multiplier
		unit.base_attack_range *= attack_range_multiplier
		unit.move_speed = unit.base_move_speed
		unit.armor = unit.base_armor
		unit.attack_damage = unit.base_attack_damage
		unit.attack_range = unit.base_attack_range
		unit.sight_range = unit.base_sight_range


func _initialize_grey_ridge_commander_tasks() -> void:
	var headquarters := buildings[PLAYER_COMMAND_CENTER_ID] as BuildingState
	for commander_id in _battle_commander_ids():
		var commander := commanders[commander_id] as CommanderState
		var initial_target := headquarters.position
		for unit_card_id in commander.subordinate_unit_card_ids:
			var unit_card := unit_cards[unit_card_id] as UnitCardState
			if unit_card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and formations.has(unit_card.formation_id):
				initial_target = (formations[unit_card.formation_id] as FormationState).anchor_position
				break
		commander.target_position = initial_target
		commander.target_region_id = &""
		_assign_commander_objective(commander, initial_target, &"")


func _add_intel_report(
	faction_id: int,
	source_key: StringName,
	target_category_key: StringName,
	estimated_min: int,
	estimated_max: int,
	region_id: StringName,
	direction_key: StringName,
	confidence_key: StringName,
	eta_min_ticks: int = -1,
	eta_max_ticks: int = -1,
	has_estimate: bool = true
) -> void:
	var report := IntelReportState.new(
		_next_intel_report_id, faction_id, source_key, current_tick, target_category_key,
		estimated_min, estimated_max, region_id, direction_key, confidence_key,
		eta_min_ticks, eta_max_ticks, has_estimate
	)
	_next_intel_report_id += 1
	var previous: IntelReportState
	for index in range(intel_reports.size() - 1, -1, -1):
		var candidate := intel_reports[index]
		if candidate.faction_id == faction_id and candidate.region_id == region_id and not candidate.superseded:
			previous = candidate
			break
	if previous != null and (report.has_estimate or not previous.has_estimate):
		previous.superseded = true
		report.superseded_report_ids = previous.superseded_report_ids.duplicate()
		report.superseded_report_ids.append(previous.report_id)
		report.merged_report_count = previous.merged_report_count + 1
		if previous.has_estimate and report.has_estimate:
			var ranges_overlap := report.estimated_min <= previous.estimated_max and previous.estimated_min <= report.estimated_max
			if ranges_overlap:
				report.estimated_min = maxi(report.estimated_min, previous.estimated_min)
				report.estimated_max = mini(report.estimated_max, previous.estimated_max)
			else:
				report.estimated_min = mini(report.estimated_min, previous.estimated_min)
				report.estimated_max = maxi(report.estimated_max, previous.estimated_max)
				report.contradictory = true
				report.confidence_key = &"INTEL_CONFIDENCE_CONFLICTED"
	intel_reports.append(report)


func _create_scenario_formation(
	formation_id: int,
	faction_id: int,
	definition_id: StringName,
	count: int,
	anchor: Vector2,
	first_entity_id: int,
	forward: Vector2,
	agent_id: int = 0,
	task_id: int = 0,
	composition_members: Array[UnitCardCompositionEntry] = []
) -> Array[int]:
	var member_ids: Array[int] = []
	for index in range(count):
		member_ids.append(first_entity_id + index)
	var formation := FormationState.new(formation_id, member_ids, anchor)
	formation.reset_anchor_history(forward)
	formations[formation_id] = formation
	var definition := UNIT_CATALOG.get_unit(definition_id)
	var lateral := Vector2(-forward.y, forward.x)
	for entity_id in member_ids:
		var slot_id := formation.get_slot_id(entity_id)
		if not composition_members.is_empty():
			definition = UNIT_CATALOG.get_unit(composition_members[slot_id].unit_definition_id)
		var offset := formation.get_wide_offset(slot_id)
		var position := anchor + forward * offset.x + lateral * offset.y
		var unit := UnitState.new(entity_id, position, definition.move_speed, faction_id)
		_apply_unit_definition(unit, definition)
		if not composition_members.is_empty():
			unit.composition_entry_id = composition_members[slot_id].entry_id
		unit.formation_id = formation_id
		unit.formation_slot_id = slot_id
		unit.following_formation = true
		unit.desired_position = position
		if agent_id != 0:
			unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
			unit.assigned_agent_id = agent_id
			unit.assigned_task_id = task_id
		units[entity_id] = unit
	return member_ids


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
	building.production_rally_position = _default_production_rally_position(position)
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


func _setup_default_army_roster() -> void:
	var bai := CommanderState.new(COMMANDER_BAI_JIUYANG, LOCAL_PLAYER_ID)
	var di := CommanderState.new(COMMANDER_DI_TIAN, LOCAL_PLAYER_ID)
	var falcon := UnitCardState.new(UNIT_CARD_FALCON, LOCAL_PLAYER_ID, [3])
	var ironwall := UnitCardState.new(UNIT_CARD_IRONWALL, LOCAL_PLAYER_ID, [4, 5])
	bai.attach_unit_card(falcon.definition.definition_id)
	di.attach_unit_card(ironwall.definition.definition_id)
	commanders[bai.definition.definition_id] = bai
	commanders[di.definition.definition_id] = di
	unit_cards[falcon.definition.definition_id] = falcon
	unit_cards[ironwall.definition.definition_id] = ironwall


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
	unit.base_move_speed = definition.move_speed
	unit.max_health = definition.combat.max_health
	unit.health = unit.max_health
	unit.armor = definition.combat.armor
	unit.base_armor = definition.combat.armor
	unit.attack_damage = definition.combat.attack_power
	unit.base_attack_damage = definition.combat.attack_power
	unit.attack_range = definition.combat.attack_range
	unit.base_attack_range = definition.combat.attack_range
	unit.attacks_per_second = definition.combat.attacks_per_second
	unit.attack_cooldown_ticks = maxi(1, ceili(10.0 / unit.attacks_per_second))
	unit.projectile_speed = definition.combat.projectile_speed
	unit.sight_range = definition.sight_range
	unit.base_sight_range = definition.sight_range
	if definition.tactical_weapon != null:
		unit.configure_tactical_weapon(definition.tactical_weapon)
	if definition.definition_id == &"scout_vehicle":
		unit.tactical_role = UnitState.TacticalRole.SCOUT
	elif definition.definition_id == &"missile_vehicle":
		unit.tactical_role = UnitState.TacticalRole.FIREPOWER
	elif definition.definition_id == &"assault_vehicle":
		unit.tactical_role = UnitState.TacticalRole.ASSAULT
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
			var unit_card := _unit_card_for_formation(takeover_formation_id)
			if unit_card != null:
				_begin_unit_card_takeover(unit_card, command)
			else:
				for entity_id in (formations[takeover_formation_id] as FormationState).member_entity_ids:
					_begin_player_takeover(units[entity_id] as UnitState, command, true)
		elif units.has(command.target_entity_id):
			_begin_player_takeover(units[command.target_entity_id] as UnitState, command)
	metrics.record_command_result(result)
	var event_start := events.size()
	var event_kind := SimulationEvent.Kind.COMMAND_REJECTED
	if result.is_accepted():
		if command is CommanderOrderCommand:
			var commander_order := command as CommanderOrderCommand
			if commander_order.order_kind == CommanderOrderCommand.OrderKind.SET_POSTURE \
					and commander_order.posture == CommanderState.Posture.DISENGAGE:
				_cancel_pending_commander_automation(commander_order.commander_id)
		command_queue.enqueue(command.duplicate_value() if command is StaffPlanApprovalCommand else command)
		event_kind = SimulationEvent.Kind.COMMAND_ACCEPTED
	events.append(SimulationEvent.new(current_tick, event_kind, command.target_entity_id, result.describe()))
	metrics.record_events(events, event_start)
	return result


func _cancel_pending_commander_automation(commander_id: StringName) -> void:
	var commander := commanders.get(commander_id) as CommanderState
	if commander == null:
		return
	command_queue.remove_if(func(queued: GameCommand) -> bool:
		return queued.issuer_kind == GameCommand.IssuerKind.AGENT and queued.agent_id == commander.agent_id
	)


func validate_command(command: GameCommand) -> CommandValidationResult:
	if battle_outcome.is_terminal():
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.BATTLE_CONCLUDED)
	# Agent orders submitted during a tick share the authoritative knowledge
	# refreshed immediately before agent evaluation.
	if not _is_advancing_tick:
		_update_faction_knowledge()
	if command is StaffPlanApprovalCommand:
		for queued in command_queue.snapshot():
			if queued is StaffPlanApprovalCommand and queued.issuer_id == command.issuer_id:
				return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.TASK_CONFLICT)
		return staff_plan_system.validate(self, command as StaffPlanApprovalCommand)
	var result := tactical_ability_system.validate(self, command as TacticalAbilityCommand) if command is TacticalAbilityCommand else command_validator.validate(command, units, _battlefield_bounds(), pathfinder, formations, buildings, ore_fields, factions, UNIT_CATALOG, BUILDING_CATALOG, faction_knowledge, logic_grid, tasks, unit_cards, strategic_regions, commanders, doctrine_definitions, battle_definition)
	if result.is_accepted() and command is CommanderOrderCommand:
		result = _validate_resolved_commander_objective(command as CommanderOrderCommand)
	if result.is_accepted() and command is ProduceUnitCommand:
		result = _validate_pending_production(command as ProduceUnitCommand)
	if result.is_accepted() and command is DeployUnitCardCommand:
		result = _validate_pending_unit_card_deployment(command as DeployUnitCardCommand)
	if result.is_accepted() and command is SupportOrderCommand:
		result = _validate_pending_support_order(command as SupportOrderCommand)
	if result.is_accepted() and (command is FormationMoveCommand or command is AttackCommand or command is MoveCommand):
		var unit := units.get(command.target_entity_id) as UnitState
		var card := unit_cards.get(unit.unit_card_id) as UnitCardState if unit != null else null
		if card != null and (card.definition.tactical_ability != null or card.uses_tactical_organization()):
			if command.issuer_kind == GameCommand.IssuerKind.AGENT and card.tactical_command != null:
				return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.TACTICAL_BUSY)
			if card.organization_enabled and card.organization <= 0.0 and (command is AttackMoveCommand or command is AttackCommand):
				return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.LOW_ORGANIZATION)
	if result.is_accepted() and not _agent_authorization_allows(command):
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED)
	return result


func _validate_resolved_commander_objective(command: CommanderOrderCommand) -> CommandValidationResult:
	if command.order_kind not in [CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, CommanderOrderCommand.OrderKind.ASSIGN_INTENT]:
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	var commander := commanders.get(command.commander_id) as CommanderState
	if commander == null:
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INVALID_TARGET)
	var deployed_cards: Array[UnitCardState] = []
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := unit_cards.get(unit_card_id) as UnitCardState
		if unit_card != null and unit_card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and formations.has(unit_card.formation_id):
			deployed_cards.append(unit_card)
	for index in range(deployed_cards.size()):
		var unit_card := deployed_cards[index]
		if unit_card.uses_tactical_organization():
			if unit_card.organization <= 0.0 and commander.posture != CommanderState.Posture.DISENGAGE:
				return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.LOW_ORGANIZATION)
			if unit_card.organization < 30.0:
				for doctrine_id in commander.equipped_doctrine_ids:
					var doctrine := doctrine_definitions.get(doctrine_id) as DoctrineDefinition
					if doctrine == null:
						continue
					for effect in doctrine.effects:
						if effect.effect.kind == DoctrineActionDefinition.Kind.STAGED_DEPARTURE:
							return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.LOW_ORGANIZATION)
		var formation := formations[unit_card.formation_id] as FormationState
		var desired_target := _commander_card_target(commander, unit_card, deployed_cards.size(), index, command.target_position, formation)
		var radius := _commander_task_radius(commander, TaskState.Kind.SCOUT_AREA if unit_card.definition.role_key == &"UNIT_CARD_ROLE_RECON" else TaskState.Kind.DEFEND_AREA)
		var resolved_target := find_formation_deployment_position(formation, desired_target, radius, command.route_points)
		if not resolved_target.is_finite():
			return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.PATH_UNAVAILABLE)
		var probe := FormationMoveCommand.new(
			command.command_id, command.issuer_id, GameCommand.IssuerKind.PLAYER, command.issued_tick,
			formation.leader_entity_id, formation.formation_id, resolved_target, command.route_points
		)
		var probe_result := command_validator.validate(
			probe, units, _battlefield_bounds(), pathfinder, formations, buildings, ore_fields, factions,
			UNIT_CATALOG, BUILDING_CATALOG, faction_knowledge, logic_grid, tasks, unit_cards,
			strategic_regions, commanders, doctrine_definitions, battle_definition
		)
		if not probe_result.is_accepted():
			return probe_result
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_pending_unit_card_deployment(command: DeployUnitCardCommand) -> CommandValidationResult:
	var unit_card := unit_cards.get(command.unit_card_id) as UnitCardState
	if unit_card == null:
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INVALID_TARGET)
	var resolved_position := find_unit_card_deployment_position(unit_card, command.deployment_position)
	if not resolved_position.is_finite():
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INVALID_POSITION)
	command.deployment_position = resolved_position
	var pending_supply := 0
	var pending_population := 0
	for queued_command in command_queue.snapshot():
		if queued_command is SupportOrderCommand and queued_command.issuer_id == unit_card.faction_id:
			var queued_support := queued_command as SupportOrderCommand
			pending_supply += get_support_cost(queued_support.support_kind)
			if queued_support.support_kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
				pending_population += _field_reinforcement_count(unit_cards.get(queued_support.unit_card_id) as UnitCardState)
			continue
		if queued_command is TacticalAbilityCommand and queued_command.issuer_id == unit_card.faction_id:
			var tactical_card := unit_cards.get(queued_command.unit_card_id) as UnitCardState
			if tactical_card != null and tactical_card.definition.tactical_ability != null:
				pending_supply += tactical_card.definition.tactical_ability.supply_cost
			continue
		if not queued_command is DeployUnitCardCommand:
			continue
		var queued_deployment := queued_command as DeployUnitCardCommand
		if queued_deployment.unit_card_id == command.unit_card_id:
			return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
		var queued_card := unit_cards.get(queued_deployment.unit_card_id) as UnitCardState
		if queued_card != null and queued_card.faction_id == unit_card.faction_id:
			pending_supply += queued_card.effective_supply_cost()
			pending_population += queued_card.available_strength
	var faction := factions.get(unit_card.faction_id) as FactionState
	if faction == null:
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INVALID_TARGET)
	if faction.supply - pending_supply < unit_card.effective_supply_cost():
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INSUFFICIENT_SUPPLY)
	if faction.population + pending_population + unit_card.available_strength > faction.population_capacity:
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.POPULATION_FULL)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func find_unit_card_deployment_position(unit_card: UnitCardState, desired_position: Vector2) -> Vector2:
	if unit_card == null or unit_card.available_strength <= 0:
		return Vector2(INF, INF)
	var headquarters := buildings.get(PLAYER_COMMAND_CENTER_ID) as BuildingState
	if headquarters == null or not headquarters.enabled:
		return Vector2(INF, INF)
	var deployment_radius := battle_definition.deployment_radius if battle_definition != null else GREY_RIDGE_DEPLOYMENT_RADIUS
	if _unit_card_formation_fits_at(unit_card, desired_position, Vector2.UP) \
			and desired_position.distance_to(headquarters.position) <= deployment_radius:
		return desired_position
	var candidates: Array[Vector2] = []
	var center_cell := logic_grid.world_to_cell(desired_position)
	var cell_radius := maxi(1, ceili(deployment_radius / LogicGrid.CELL_SIZE))
	for y_offset in range(-cell_radius, cell_radius + 1):
		for x_offset in range(-cell_radius, cell_radius + 1):
			var cell := center_cell + Vector2i(x_offset, y_offset)
			if not logic_grid.is_in_bounds(cell) or logic_grid.is_blocked(cell):
				continue
			var candidate := logic_grid.cell_to_world(cell)
			if candidate.distance_to(headquarters.position) <= deployment_radius:
				candidates.append(candidate)
	candidates.sort_custom(func(first: Vector2, second: Vector2) -> bool:
		var first_distance := first.distance_squared_to(desired_position)
		var second_distance := second.distance_squared_to(desired_position)
		return first_distance < second_distance or (is_equal_approx(first_distance, second_distance) and (first.y < second.y or first.y == second.y and first.x < second.x))
	)
	for candidate in candidates:
		if _unit_card_formation_fits_at(unit_card, candidate, Vector2.UP):
			return candidate
	return Vector2(INF, INF)


func _unit_card_formation_fits_at(unit_card: UnitCardState, anchor: Vector2, forward: Vector2) -> bool:
	var member_ids: Array[int] = []
	for index in range(unit_card.available_strength):
		member_ids.append(index + 1)
	var formation := FormationState.new(-1, member_ids, anchor)
	var normalized_forward := forward.normalized() if not forward.is_zero_approx() else Vector2.UP
	var lateral := Vector2(-normalized_forward.y, normalized_forward.x)
	for slot_id in range(member_ids.size()):
		var offset := formation.get_wide_offset(slot_id)
		var slot_position := anchor + normalized_forward * offset.x + lateral * offset.y
		if not _battlefield_bounds().has_point(slot_position) or not logic_grid.is_world_position_walkable(slot_position):
			return false
	return true


func _validate_pending_support_order(command: SupportOrderCommand) -> CommandValidationResult:
	var pending_supply := 0
	var pending_population := 0
	for queued_command in command_queue.snapshot():
		if queued_command.issuer_id != command.issuer_id:
			continue
		if queued_command is DeployUnitCardCommand:
			var queued_card := unit_cards.get((queued_command as DeployUnitCardCommand).unit_card_id) as UnitCardState
			if queued_card != null:
				pending_supply += queued_card.effective_supply_cost()
				pending_population += queued_card.available_strength
		elif queued_command is SupportOrderCommand:
			var queued_support := queued_command as SupportOrderCommand
			if queued_support.support_kind == command.support_kind:
				return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
			pending_supply += get_support_cost(queued_support.support_kind)
			if queued_support.support_kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
				pending_population += _field_reinforcement_count(unit_cards.get(queued_support.unit_card_id) as UnitCardState)
		elif queued_command is TacticalAbilityCommand:
			var tactical_card := unit_cards.get(queued_command.unit_card_id) as UnitCardState
			if tactical_card != null and tactical_card.definition.tactical_ability != null:
				pending_supply += tactical_card.definition.tactical_ability.supply_cost
	var faction := factions.get(command.issuer_id) as FactionState
	if faction == null or faction.supply - pending_supply < get_support_cost(command.support_kind):
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INSUFFICIENT_SUPPLY)
	if command.support_kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
		var reinforcement_count := _field_reinforcement_count(unit_cards.get(command.unit_card_id) as UnitCardState)
		if faction.population + pending_population + reinforcement_count > faction.population_capacity:
			return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.POPULATION_FULL)
	var cooldown_until := _support_cooldown_until(faction, command.support_kind)
	if cooldown_until > current_tick:
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.SUPPORT_COOLDOWN)
	if command.support_kind == SupportOrderCommand.SupportKind.AIR_RECON:
		var active_regions := air_recon_until_by_faction.get(command.issuer_id, {}) as Dictionary
		for region_id in [command.primary_region_id, command.secondary_region_id]:
			if int(active_regions.get(region_id, 0)) > current_tick:
				return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
	elif command.support_kind == SupportOrderCommand.SupportKind.ENGINEERING_ROUTE:
		if opened_engineering_routes.has(command.primary_region_id):
			return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _support_cooldown_until(faction: FactionState, support_kind: SupportOrderCommand.SupportKind) -> int:
	if faction.support_cooldown_until_by_kind.has(support_kind):
		return int(faction.support_cooldown_until_by_kind[support_kind])
	match support_kind:
		SupportOrderCommand.SupportKind.AIR_RECON:
			return faction.air_recon_cooldown_until_tick
		SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY:
			return faction.fortify_cooldown_until_tick
		SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
			return faction.reinforcement_cooldown_until_tick
	return 0


func _field_reinforcement_count(unit_card: UnitCardState) -> int:
	if unit_card == null:
		return 0
	var active_strength := 0
	for entity_id in unit_card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			active_strength += 1
	var faction := factions.get(unit_card.faction_id) as FactionState
	var population_room := maxi(0, faction.population_capacity - faction.population) if faction != null else 0
	var definition := get_support_definition(SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT)
	var configured_strength := definition.strength if definition != null else FIELD_REINFORCEMENT_STRENGTH
	return mini(configured_strength, mini(maxi(0, unit_card.definition.authorized_strength - active_strength), population_room))


func _validate_pending_production(command: ProduceUnitCommand) -> CommandValidationResult:
	var building := buildings.get(command.target_entity_id) as BuildingState
	var definition := UNIT_CATALOG.get_unit(command.unit_definition_id)
	if building == null or definition == null:
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INVALID_DEFINITION)
	var pending_for_building := 0
	var pending_cost := 0
	for queued_command in command_queue.snapshot():
		if not queued_command is ProduceUnitCommand:
			continue
		var queued_production := queued_command as ProduceUnitCommand
		var queued_building := buildings.get(queued_production.target_entity_id) as BuildingState
		var queued_definition := UNIT_CATALOG.get_unit(queued_production.unit_definition_id)
		if queued_building != null and queued_building.faction_id == building.faction_id and queued_definition != null:
			pending_cost += queued_definition.production_cost
		if queued_production.target_entity_id == building.entity_id:
			pending_for_building += 1
	if building.production_count() + pending_for_building >= BuildingState.MAX_PRODUCTION_QUEUE_SIZE:
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.PRODUCTION_QUEUE_FULL)
	var faction := factions.get(building.faction_id) as FactionState
	if faction == null or faction.ore - pending_cost < definition.production_cost:
		return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.INSUFFICIENT_ORE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


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
		if command.issuer_kind == GameCommand.IssuerKind.AGENT and command.agent_id != 0:
			return command.agent_id
		return StrategicTaskSystem.INDUSTRIAL_AGENT_ID if (command as StrategicOrderCommand).order_kind == StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE else StrategicTaskSystem.BATTLEFIELD_AGENT_ID
	if command.issuer_kind == GameCommand.IssuerKind.AGENT:
		return command.agent_id
	return 0


func _advance_friendly_autonomy() -> void:
	if current_tick - _last_friendly_autonomy_tick < FRIENDLY_AUTONOMY_INTERVAL_TICKS:
		return
	_last_friendly_autonomy_tick = current_tick
	strategic_headquarters.advance(self)
	var industrial_policy := agent_policies.get(StrategicTaskSystem.INDUSTRIAL_AGENT_ID) as AgentPolicy
	if industrial_policy != null and industrial_policy.allows_proactive_tasks() and strategic_headquarters.should_start_industrial_development(self) and not _has_open_task_for_agent(industrial_policy.agent_id):
		_submit_autonomous_industrial_order(industrial_policy)
	var battlefield_policy := agent_policies.get(StrategicTaskSystem.BATTLEFIELD_AGENT_ID) as AgentPolicy
	if battlefield_policy != null and battlefield_policy.allows_proactive_tasks():
		_submit_autonomous_battlefield_orders(battlefield_policy)


func get_headquarters_decision_key() -> StringName:
	return strategic_headquarters.last_decision_key


func get_headquarters_budget_snapshot() -> Dictionary:
	return strategic_headquarters.budget_snapshot()


func set_headquarters_directive(new_directive: StrategicHeadquarters.Directive) -> bool:
	if new_directive < StrategicHeadquarters.Directive.NONE or new_directive > StrategicHeadquarters.Directive.OFFENSIVE:
		return false
	strategic_headquarters.set_directive(new_directive)
	var authorization: AgentPolicy.Authorization = AgentPolicy.Authorization.ASSISTED if new_directive == StrategicHeadquarters.Directive.NONE else AgentPolicy.Authorization.AUTONOMOUS
	set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, authorization)
	set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, authorization)
	_cancel_proactive_battlefield_tasks("Replanned by a direct General Staff directive")
	_last_friendly_autonomy_tick = current_tick - FRIENDLY_AUTONOMY_INTERVAL_TICKS
	return true


func get_headquarters_directive() -> StrategicHeadquarters.Directive:
	return strategic_headquarters.directive


func get_headquarters_directive_key() -> StringName:
	return strategic_headquarters.directive_key()


func _cancel_proactive_battlefield_tasks(detail: String) -> void:
	command_queue.remove_if(func(command: GameCommand) -> bool:
		return command is StrategicOrderCommand and command.issuer_kind == GameCommand.IssuerKind.AGENT and command.agent_id == StrategicTaskSystem.BATTLEFIELD_AGENT_ID
	)
	for task_variant in tasks.values():
		var task := task_variant as TaskState
		if task.agent_id != StrategicTaskSystem.BATTLEFIELD_AGENT_ID or not task.requires_proactive_authorization or not _is_open_task(task):
			continue
		task.set_lifecycle(TaskState.Lifecycle.CANCELLED, current_tick, TaskState.BlockedReason.NONE, detail)
		task.set_phase(TaskState.Phase.DONE, current_tick, detail)
		_stop_task_formation(task)
		release_task_participants(task)
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, task.task_id, "CANCELLED:headquarters_directive"))


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


func _submit_autonomous_battlefield_orders(policy: AgentPolicy) -> void:
	var snapshot := create_faction_snapshot(policy.faction_id)
	var base_position := _faction_base_position(policy.faction_id)
	var contact := _best_visible_hostile(snapshot, base_position)
	var open_combat_task := _find_open_battlefield_task(policy.agent_id, false)
	var combat_ids := _autonomous_combat_units(policy.faction_id, open_combat_task)
	var hold_territory := strategic_headquarters.directive in [StrategicHeadquarters.Directive.ECONOMY_FIRST, StrategicHeadquarters.Directive.DEFENSIVE]
	if not contact.is_empty() and not combat_ids.is_empty():
		var target_position := contact["position"] as Vector2
		var target_id := int(contact["entity_id"])
		var threatens_base := target_position.distance_to(base_position) <= FRIENDLY_DEFENSE_RADIUS
		if threatens_base:
			if open_combat_task == null or open_combat_task.kind != TaskState.Kind.DEFEND_AREA or open_combat_task.priority < AUTONOMY_PRIORITY_BASE_THREAT:
				_submit_autonomous_defense(policy, combat_ids, base_position, AUTONOMY_PRIORITY_BASE_THREAT, open_combat_task.task_id if open_combat_task != null else 0)
		elif hold_territory:
			if open_combat_task == null or open_combat_task.kind != TaskState.Kind.DEFEND_AREA:
				_submit_autonomous_defense(policy, combat_ids, base_position, AUTONOMY_PRIORITY_DEFEND, open_combat_task.task_id if open_combat_task != null else 0)
		elif open_combat_task == null or open_combat_task.kind != TaskState.Kind.ATTACK_TARGET or open_combat_task.target_entity_id != target_id:
			_submit_autonomous_attack(policy, combat_ids, target_id, target_position, open_combat_task.task_id if open_combat_task != null else 0)
	elif open_combat_task == null and not combat_ids.is_empty():
		_submit_autonomous_defense(policy, combat_ids, base_position, AUTONOMY_PRIORITY_DEFEND)

	if _find_open_battlefield_task(policy.agent_id, true) == null:
		var scout := _first_available_autonomous_unit(policy.faction_id, &"scout_vehicle")
		if scout != null:
			var scout_target := find_reachable_scout_target(policy.faction_id, scout.position)
			if not scout_target.is_equal_approx(scout.position):
				var scout_command := StrategicOrderCommand.new(
					allocate_command_id(), policy.faction_id, current_tick,
					StrategicOrderCommand.OrderKind.SCOUT_AREA, 0, 0,
					scout_target, FRIENDLY_SCOUT_RADIUS, GameCommand.IssuerKind.AGENT
				)
				scout_command.agent_id = policy.agent_id
				scout_command.strategic_priority = AUTONOMY_PRIORITY_SCOUT
				scout_command.participant_entity_ids.assign([scout.entity_id])
				submit_command(scout_command)


func _submit_autonomous_defense(policy: AgentPolicy, participant_ids: Array[int], position: Vector2, priority: int, replaces_task_id: int = 0) -> void:
	var command := StrategicOrderCommand.new(
		allocate_command_id(), policy.faction_id, current_tick,
		StrategicOrderCommand.OrderKind.DEFEND_AREA, 0, 0,
		position, FRIENDLY_DEFENSE_RADIUS, GameCommand.IssuerKind.AGENT
	)
	command.agent_id = policy.agent_id
	command.strategic_priority = priority
	command.replaces_task_id = replaces_task_id
	command.participant_entity_ids.assign(participant_ids)
	submit_command(command)


func _submit_autonomous_attack(policy: AgentPolicy, participant_ids: Array[int], target_id: int, target_position: Vector2, replaces_task_id: int = 0) -> void:
	var command := StrategicOrderCommand.new(
		allocate_command_id(), policy.faction_id, current_tick,
		StrategicOrderCommand.OrderKind.ATTACK_TARGET, 0, target_id,
		target_position, 0.0, GameCommand.IssuerKind.AGENT
	)
	command.agent_id = policy.agent_id
	command.strategic_priority = AUTONOMY_PRIORITY_ATTACK
	command.replaces_task_id = replaces_task_id
	command.participant_entity_ids.assign(participant_ids)
	submit_command(command)


func _find_open_battlefield_task(agent_id: int, scout_task: bool) -> TaskState:
	var task_ids := tasks.keys()
	task_ids.sort()
	for task_id in task_ids:
		var task := tasks[task_id] as TaskState
		if task.agent_id != agent_id or not _is_open_task(task):
			continue
		if (task.kind == TaskState.Kind.SCOUT_AREA) == scout_task and task.kind != TaskState.Kind.DEVELOP_RESOURCE:
			return task
	return null


func _is_open_task(task: TaskState) -> bool:
	return task.lifecycle in [TaskState.Lifecycle.WAITING, TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING, TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]


func _autonomous_combat_units(faction_id: int, current_task: TaskState) -> Array[int]:
	var result: Array[int] = []
	var unit_ids := units.keys()
	unit_ids.sort()
	for entity_id in unit_ids:
		var unit := units[entity_id] as UnitState
		if not unit.enabled or unit.faction_id != faction_id or not unit.can_attack or not unit.can_accept_attack_orders:
			continue
		if unit.can_harvest or unit.can_construct or unit.definition_id == &"scout_vehicle" or unit.control_state == UnitState.ControlState.TEMPORARILY_OVERRIDDEN:
			continue
		if unit.assigned_task_id == 0 or current_task != null and unit.assigned_task_id == current_task.task_id:
			result.append(unit.entity_id)
	return result


func _first_available_autonomous_unit(faction_id: int, definition_id: StringName) -> UnitState:
	var unit_ids := units.keys()
	unit_ids.sort()
	for entity_id in unit_ids:
		var unit := units[entity_id] as UnitState
		if unit.enabled and unit.faction_id == faction_id and unit.definition_id == definition_id and unit.assigned_task_id == 0 and unit.control_state != UnitState.ControlState.TEMPORARILY_OVERRIDDEN:
			return unit
	return null


func _faction_base_position(faction_id: int) -> Vector2:
	var building_ids := buildings.keys()
	building_ids.sort()
	for building_id in building_ids:
		var building := buildings[building_id] as BuildingState
		if building.enabled and building.faction_id == faction_id and building.definition_id == &"command_center":
			return building.rally_position
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.faction_id == faction_id:
			return unit.position
	return logic_grid.cell_to_world(Vector2i(1, 1))


func _best_visible_hostile(snapshot: WorldSnapshot, origin: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for contact in snapshot.units:
		if contact.faction_id == snapshot.observer_faction_id or not contact.enabled or not contact.is_visible_to_local_player:
			continue
		var distance := origin.distance_squared_to(contact.position)
		if distance < best_distance or is_equal_approx(distance, best_distance) and (best.is_empty() or contact.entity_id < int(best["entity_id"])):
			best = {"entity_id": contact.entity_id, "position": contact.position}
			best_distance = distance
	for contact in snapshot.buildings:
		if contact.faction_id == snapshot.observer_faction_id or not contact.enabled or not contact.is_visible:
			continue
		var distance := origin.distance_squared_to(contact.position)
		if distance < best_distance or is_equal_approx(distance, best_distance) and (best.is_empty() or contact.entity_id < int(best["entity_id"])):
			best = {"entity_id": contact.entity_id, "position": contact.position}
			best_distance = distance
	return best


func find_reachable_scout_target(faction_id: int, origin: Vector2, excluded_position: Vector2 = Vector2(-1.0, -1.0)) -> Vector2:
	_ensure_faction_knowledge(faction_id)
	var knowledge := faction_knowledge[faction_id] as FactionKnowledge
	var origin_cell := logic_grid.world_to_cell(origin)
	var base_cell := logic_grid.world_to_cell(_faction_base_position(faction_id))
	var map_center := Vector2(logic_grid.grid_size) * 0.5
	var exploration_heading := (map_center - Vector2(base_cell)).normalized()
	var candidates: Array[Vector2i] = []
	for cell in knowledge.unexplored_frontier_cells():
		if not logic_grid.is_blocked(cell):
			candidates.append(cell)
	candidates.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		var first_offset := Vector2(first - origin_cell)
		var second_offset := Vector2(second - origin_cell)
		var first_score := first_offset.length() - first_offset.dot(exploration_heading) * 0.35
		var second_score := second_offset.length() - second_offset.dot(exploration_heading) * 0.35
		return first_score < second_score or (is_equal_approx(first_score, second_score) and (first.y < second.y or first.y == second.y and first.x < second.x))
	)
	for index in range(mini(candidates.size(), 32)):
		var target := logic_grid.cell_to_world(candidates[index])
		if target.distance_to(excluded_position) <= LogicGrid.CELL_SIZE:
			continue
		if not pathfinder.find_path(origin, target).is_empty():
			return target
	return origin


func _is_direct_player_order(command: GameCommand) -> bool:
	if command.issuer_kind != GameCommand.IssuerKind.PLAYER:
		return false
	return command is MoveCommand or command is FormationMoveCommand or command is StopCommand or command is AttackCommand or command is HarvestCommand or command is BuildBuildingCommand or command is RepairBuildingCommand


func advance_tick() -> WorldSnapshot:
	if battle_outcome.is_terminal():
		return create_snapshot()
	_is_advancing_tick = true
	var profile_started_usec := Time.get_ticks_usec() if tick_profile_enabled else 0
	var event_start := events.size()
	var commands := command_queue.drain()
	var refresh_knowledge_before_agents := current_tick == 0
	metrics.record_commands_applied(commands.size())
	for command in commands:
		if command is SupportOrderCommand or command is BuildBuildingCommand:
			refresh_knowledge_before_agents = true
		_apply_command(command)
	var unit_count_before_deployments := units.size()
	_advance_unit_card_deployments()
	refresh_knowledge_before_agents = refresh_knowledge_before_agents or units.size() != unit_count_before_deployments
	_advance_support_effects()
	_update_grey_ridge_terrain_effects()
	tactical_ability_system.advance(self)
	if refresh_knowledge_before_agents:
		_update_faction_knowledge()
	if is_card_battle():
		_advance_card_battle_doctrine_actions()
	profile_started_usec = _record_tick_profile_section(&"commands_and_knowledge", profile_started_usec)
	for agent in agents:
		agent.advance(self)
	strategic_task_system.advance(self)
	if is_card_battle():
		tactical_ability_system.propose_commands(self)
	if scenario_kind == ScenarioKind.LEGACY_RTS:
		_advance_friendly_autonomy()
		enemy_raid_agent.advance(self)
	if is_card_battle():
		_advance_grey_ridge_locked_plan_followup()
		_advance_escort_interception()
		_advance_grey_ridge_enemy_reactions()
		_advance_enemy_strategic_ai()
	profile_started_usec = _record_tick_profile_section(&"agents_and_tasks", profile_started_usec)
	_drop_hidden_attack_targets()
	_update_worker_self_defense()
	_update_commander_combat_coordination()
	profile_started_usec = _record_tick_profile_section(&"movement_coordination", profile_started_usec)
	_update_shared_formation_responses()
	profile_started_usec = _record_tick_profile_section(&"movement_shared_response", profile_started_usec)
	_update_combat_orders()
	profile_started_usec = _record_tick_profile_section(&"movement_orders", profile_started_usec)
	formation_movement.advance(formations, units, events, current_tick)
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if not unit.following_formation:
			_advance_unit(unit)
	_complete_rejoins()
	_advance_limited_withdrawals()
	profile_started_usec = _record_tick_profile_section(&"movement", profile_started_usec)
	_update_grey_ridge_terrain_effects(false)
	engineering_system.advance(units, buildings, BUILDING_CATALOG, events, current_tick)
	tactical_ability_system.prepare_weapons(self)
	_next_projectile_id = combat_system.advance(units, buildings, projectiles, _next_projectile_id, events, current_tick)
	_advance_unit_card_organization()
	_cleanup_expired_wrecks()
	_refresh_battle_population()
	_release_destroyed_building_occupancy()
	_next_unit_id = economy_system.advance(units, buildings, ore_fields, factions, UNIT_CATALOG, BUILDING_CATALOG, pathfinder, _next_unit_id, events, current_tick)
	if scenario_kind == ScenarioKind.LEGACY_RTS:
		_update_victory()
	else:
		_update_command_center_defeats()
	mission_state.update_completed(current_tick)
	profile_started_usec = _record_tick_profile_section(&"combat_and_economy", profile_started_usec)
	current_tick += 1
	_advance_grey_ridge_economy()
	_advance_strategic_regions()
	_advance_escort_supply_node()
	if is_card_battle():
		battle_outcome = objective_system.advance(self, events, current_tick)
	_update_faction_knowledge()
	_update_commander_behavior_feedback()
	metrics.record_events(events, event_start)
	profile_started_usec = _record_tick_profile_section(&"post_tick_knowledge", profile_started_usec)
	var snapshot := create_snapshot()
	_record_tick_profile_section(&"snapshot", profile_started_usec)
	_is_advancing_tick = false
	return snapshot


func _record_tick_profile_section(section: StringName, started_usec: int) -> int:
	if not tick_profile_enabled:
		return 0
	var now := Time.get_ticks_usec()
	last_tick_profile_usec[section] = now - started_usec
	return now


func _apply_unit_card_deployment(command: DeployUnitCardCommand) -> void:
	var unit_card := unit_cards[command.unit_card_id] as UnitCardState
	var faction := factions[unit_card.faction_id] as FactionState
	var supply_cost := unit_card.effective_supply_cost()
	faction.supply -= supply_cost
	unit_card.deployment_state = UnitCardState.DeploymentState.DEPLOYING
	unit_card.deployment_ticks_remaining = unit_card.definition.deployment_ticks
	unit_card.deployment_position = command.deployment_position
	events.append(SimulationEvent.new(
		current_tick,
		SimulationEvent.Kind.UNIT_CARD_DEPLOYMENT_STARTED,
		0,
		"card=%s;commander=%s;cost=%d;ticks=%d;position=%.1f,%.1f" % [
			unit_card.definition.definition_id,
			unit_card.commander_definition_id,
			supply_cost,
			unit_card.deployment_ticks_remaining,
			unit_card.deployment_position.x,
			unit_card.deployment_position.y,
		]
	))
	events.append(SimulationEvent.new(
		current_tick,
		SimulationEvent.Kind.SUPPLY_CHANGED,
		unit_card.faction_id,
		"supply=%d;delta=-%d;source=deployment;card=%s" % [faction.supply, supply_cost, unit_card.definition.definition_id]
	))
	_refresh_battle_population()


func _apply_support_order(command: SupportOrderCommand) -> void:
	var faction := factions[command.issuer_id] as FactionState
	var support_definition := get_support_definition(command.support_kind)
	var supply_cost := support_definition.supply_cost if support_definition != null else SUPPORT_COST
	var duration_ticks := support_definition.duration_ticks if support_definition != null else SUPPORT_DURATION_TICKS
	faction.supply -= supply_cost
	var cooldown_until := current_tick + _support_cooldown_duration(command.issuer_id, command.support_kind)
	faction.support_cooldown_until_by_kind[command.support_kind] = cooldown_until
	match command.support_kind:
		SupportOrderCommand.SupportKind.AIR_RECON:
			faction.air_recon_cooldown_until_tick = cooldown_until
			var active_regions := air_recon_until_by_faction.get(command.issuer_id, {}) as Dictionary
			for region_id in [command.primary_region_id, command.secondary_region_id]:
				active_regions[region_id] = current_tick + duration_ticks
				var region := strategic_regions[region_id] as StrategicRegionState
				var hostile_count := 0
				for unit_variant in units.values():
					var unit := unit_variant as UnitState
					if unit.enabled and unit.faction_id != command.issuer_id and unit.position.distance_to(region.position) <= region.radius:
						hostile_count += 1
				_add_intel_report(command.issuer_id, &"INTEL_SOURCE_AIR", &"INTEL_HOSTILE_FORCE", hostile_count, hostile_count, region_id, &"INTEL_DIRECTION_CURRENT", &"INTEL_CONFIDENCE_HIGH", 0, 0, true)
			air_recon_until_by_faction[command.issuer_id] = active_regions
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPORT_STARTED, command.issuer_id, "air_recon=%s,%s;until=%d" % [command.primary_region_id, command.secondary_region_id, current_tick + duration_ticks]))
		SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY:
			faction.fortify_cooldown_until_tick = cooldown_until
			var unit_card := unit_cards[command.unit_card_id] as UnitCardState
			unit_card.fortified_ticks_remaining = duration_ticks
			var formation := formations[unit_card.formation_id] as FormationState
			_apply_stop(StopCommand.new(allocate_command_id(), command.issuer_id, GameCommand.IssuerKind.AGENT, current_tick, formation.leader_entity_id, formation.formation_id))
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPORT_STARTED, command.issuer_id, "fortify=%s;until=%d" % [command.unit_card_id, current_tick + duration_ticks]))
		SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
			faction.reinforcement_cooldown_until_tick = cooldown_until
			var reinforced_card := unit_cards[command.unit_card_id] as UnitCardState
			var reinforced_ids := _apply_field_reinforcement(reinforced_card)
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPORT_STARTED, command.issuer_id, "reinforce=%s;strength=%d;until=%d" % [command.unit_card_id, reinforced_ids.size(), cooldown_until]))
			if not reinforced_ids.is_empty():
				events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_CARD_REINFORCED, reinforced_ids[0], "card=%s;strength=%d" % [command.unit_card_id, reinforced_ids.size()]))
		SupportOrderCommand.SupportKind.ENGINEERING_ROUTE:
			var route := battle_definition.engineering_route_dictionary().get(command.primary_region_id) as BattleEngineeringRouteDefinition
			if route == null:
				return
			for rect in route.cleared_rects:
				for x in range(rect.position.x, rect.end.x):
					for y in range(rect.position.y, rect.end.y):
						logic_grid.set_blocked(Vector2i(x, y), false)
			opened_engineering_routes[route.route_id] = current_tick
			faction.opened_engineering_route_ids.append(route.route_id)
			var route_position := _engineering_route_center(route)
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ENGINEERING_ROUTE_OPENED, command.issuer_id, "route=%s;region=%s;engineer_card=%s;grid_revision=%d;position=%.1f,%.1f" % [route.route_id, route.linked_region_id, command.unit_card_id, logic_grid.revision, route_position.x, route_position.y]))
		SupportOrderCommand.SupportKind.FIRE_SUPPORT:
			var target_region := strategic_regions[command.primary_region_id] as StrategicRegionState
			var hit_count := _apply_fire_support(command.issuer_id, target_region, support_definition.damage)
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPORT_STARTED, command.issuer_id, "fire_support=%s;hits=%d" % [command.primary_region_id, hit_count]))
		SupportOrderCommand.SupportKind.RAPID_MOBILITY:
			var mobility_card := unit_cards[command.unit_card_id] as UnitCardState
			mobility_card.rapid_mobility_ticks_remaining = duration_ticks
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPORT_STARTED, command.issuer_id, "rapid_mobility=%s;until=%d" % [command.unit_card_id, current_tick + duration_ticks]))
		SupportOrderCommand.SupportKind.FRONTLINE_LOGISTICS:
			var logistics_card := unit_cards[command.unit_card_id] as UnitCardState
			var restored := _apply_frontline_logistics(logistics_card, support_definition)
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPORT_STARTED, command.issuer_id, "frontline_logistics=%s;restored=%.1f" % [command.unit_card_id, restored]))
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPLY_CHANGED, command.issuer_id, "supply=%d;delta=-%d;source=support;support_kind=%d;card=%s" % [faction.supply, supply_cost, command.support_kind, command.unit_card_id]))


func _apply_fire_support(issuer_id: int, region: StrategicRegionState, damage: float) -> int:
	var hits := 0
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if unit == null or not unit.enabled or unit.faction_id == issuer_id or unit.position.distance_to(region.position) > region.radius:
			continue
		var applied := maxf(1.0, damage - unit.armor)
		unit.health = maxf(0.0, unit.health - applied)
		hits += 1
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.DAMAGE_APPLIED, issuer_id, "target=%d;amount=%.3f;remaining=%.3f;source=fire_support" % [unit.entity_id, applied, unit.health]))
		if unit.health <= 0.0:
			unit.enabled = false
			unit.death_tick = current_tick
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_DESTROYED, unit.entity_id, "source=fire_support"))
	return hits


func _engineering_route_center(route: BattleEngineeringRouteDefinition) -> Vector2:
	if route == null or route.cleared_rects.is_empty():
		return Vector2.ZERO
	var bounds := route.cleared_rects[0]
	var center_cell := Vector2(bounds.position) + Vector2(bounds.size) * 0.5
	return center_cell * LogicGrid.CELL_SIZE


func _apply_frontline_logistics(card: UnitCardState, definition: BattleSupportDefinition) -> float:
	var restored := 0.0
	for entity_id in card.member_entity_ids:
		var member := units.get(entity_id) as UnitState
		if member == null or not member.enabled:
			continue
		var before := member.health
		member.health = minf(member.max_health, member.health + definition.health_restore)
		restored += member.health - before
	if card.organization_enabled and battle_definition != null:
		var before_organization := card.organization
		card.organization = minf(battle_definition.organization_max, card.organization + definition.organization_restore)
		restored += card.organization - before_organization
		_reset_unit_card_organization_baseline(card)
	return restored


func _apply_field_reinforcement(unit_card: UnitCardState) -> Array[int]:
	var reinforced_ids: Array[int] = []
	if unit_card == null or not formations.has(unit_card.formation_id):
		return reinforced_ids
	var formation := formations[unit_card.formation_id] as FormationState
	_prune_disabled_formation_members(formation)
	var reinforcement_count := _field_reinforcement_count(unit_card)
	if reinforcement_count <= 0:
		return reinforced_ids
	var ordered_entries: Array[UnitCardCompositionState] = unit_card.composition.duplicate()
	ordered_entries.sort_custom(func(a: UnitCardCompositionState, b: UnitCardCompositionState) -> bool:
		return a.replacement_priority < b.replacement_priority if a.replacement_priority != b.replacement_priority else String(a.entry_id) < String(b.entry_id)
	)
	var reinforced_entries: Array[UnitCardCompositionState] = []
	for entry in ordered_entries:
		var missing := entry.authorized_strength - entry.active_count(units)
		for _index in range(mini(missing, reinforcement_count - reinforced_ids.size())):
			var entity_id := _next_unit_id
			_next_unit_id += 1
			formation.add_member(entity_id)
			unit_card.member_entity_ids.append(entity_id)
			reinforced_ids.append(entity_id)
			reinforced_entries.append(entry)
	var tangent := formation.initial_path_direction
	if tangent.is_zero_approx():
		tangent = Vector2.RIGHT
	var lateral := Vector2(-tangent.y, tangent.x)
	for entity_id in reinforced_ids:
		var entry := reinforced_entries[reinforced_ids.find(entity_id)]
		var definition := UNIT_CATALOG.get_unit(entry.unit_definition_id)
		var slot_id := formation.get_slot_id(entity_id)
		var offset := formation.get_wide_offset(slot_id)
		var spawn_position := formation.anchor_position + tangent * offset.x + lateral * offset.y
		if not logic_grid.is_world_position_walkable(spawn_position):
			spawn_position = formation.anchor_position
		var unit := UnitState.new(entity_id, spawn_position, definition.move_speed, unit_card.faction_id)
		_apply_unit_definition(unit, definition)
		unit.composition_entry_id = entry.entry_id
		unit.formation_id = formation.formation_id
		unit.formation_slot_id = slot_id
		unit.following_formation = true
		unit.desired_position = spawn_position
		unit.has_move_target = formation.is_moving
		unit.move_target = formation.target_position
		unit.original_formation_id = formation.formation_id
		match unit_card.control_state:
			UnitCardState.ControlState.AGENT_ASSIGNED, UnitCardState.ControlState.RETURNING:
				unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
				unit.assigned_agent_id = unit_card.assigned_agent_id
				unit.assigned_task_id = unit_card.assigned_task_id
				if tasks.has(unit.assigned_task_id):
					(tasks[unit.assigned_task_id] as TaskState).add_participant(entity_id)
			UnitCardState.ControlState.PLAYER_OVERRIDDEN:
				unit.control_state = UnitState.ControlState.TEMPORARILY_OVERRIDDEN
				unit.assigned_agent_id = unit_card.assigned_agent_id
				unit.assigned_task_id = unit_card.assigned_task_id
				unit.return_task_id = unit_card.return_task_id
			UnitCardState.ControlState.PLAYER_CONTROLLED:
				unit.control_state = UnitState.ControlState.PLAYER_CONTROLLED
			_:
				unit.control_state = UnitState.ControlState.UNASSIGNED
		units[entity_id] = unit
	unit_card.member_entity_ids.sort()
	formation.rebuild_slots()
	for entity_id in formation.member_entity_ids:
		var member := units.get(entity_id) as UnitState
		if member != null:
			member.formation_slot_id = formation.get_slot_id(entity_id)
	_bind_unit_card_members(unit_card)
	_refresh_battle_population()
	return reinforced_ids


func _support_cooldown_duration(faction_id: int, support_kind: int = SupportOrderCommand.SupportKind.AIR_RECON) -> int:
	var definition := get_support_definition(support_kind)
	var cooldown_ticks := definition.cooldown_ticks if definition != null else SUPPORT_COOLDOWN_TICKS
	for region_variant in strategic_regions.values():
		var region := region_variant as StrategicRegionState
		if region.controller_faction_id == faction_id and not region.contested:
			cooldown_ticks = mini(cooldown_ticks, region.support_cooldown_ticks)
	return cooldown_ticks


func get_support_definition(support_kind: int) -> BattleSupportDefinition:
	return battle_definition.support_for_kind(support_kind) if battle_definition != null else null


func get_support_cost(support_kind: int) -> int:
	var definition := get_support_definition(support_kind)
	return definition.supply_cost if definition != null else SUPPORT_COST


func _update_grey_ridge_terrain_effects(force_refresh: bool = true) -> void:
	if not is_card_battle():
		return
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if not unit.enabled:
			continue
		var previous_terrain := unit.terrain_kind
		var current_terrain := _terrain_kind_at(unit.position)
		if not force_refresh and current_terrain == previous_terrain:
			continue
		unit.terrain_kind = current_terrain
		unit.move_speed = unit.base_move_speed
		unit.armor = unit.base_armor
		unit.attack_damage = unit.base_attack_damage
		unit.attack_range = unit.base_attack_range
		unit.sight_range = unit.base_sight_range
		unit.terrain_effect_key = &"TERRAIN_EFFECT_NONE"
		var unit_card := unit_cards.get(unit.unit_card_id) as UnitCardState
		if unit_card != null and unit_card.fortified_ticks_remaining > 0:
			var fortify := get_support_definition(SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY)
			unit.armor += fortify.armor_bonus if fortify != null else FORTIFICATION_ARMOR_BONUS
		if unit_card != null and unit_card.rapid_mobility_ticks_remaining > 0:
			var mobility := get_support_definition(SupportOrderCommand.SupportKind.RAPID_MOBILITY)
			unit.move_speed *= mobility.move_speed_multiplier if mobility != null else 1.25
		match unit.terrain_kind:
			UnitState.TerrainKind.OPEN:
				if unit.tactical_role == UnitState.TacticalRole.ARMOR:
					unit.move_speed *= 1.1
					unit.attack_damage *= 1.2
					unit.terrain_effect_key = &"TERRAIN_EFFECT_OPEN_ARMOR"
				elif unit.tactical_role == UnitState.TacticalRole.FIREPOWER:
					unit.attack_range *= 1.1
					unit.terrain_effect_key = &"TERRAIN_EFFECT_OPEN_FIREPOWER"
			UnitState.TerrainKind.RUINS:
				if unit.tactical_role == UnitState.TacticalRole.ASSAULT:
					unit.armor += 2.0
					unit.attack_damage *= 1.15
					unit.terrain_effect_key = &"TERRAIN_EFFECT_RUINS_ASSAULT"
				elif unit.tactical_role == UnitState.TacticalRole.ARMOR:
					unit.move_speed *= 0.7
					unit.attack_range *= 0.8
					unit.terrain_effect_key = &"TERRAIN_EFFECT_RUINS_ARMOR"
			UnitState.TerrainKind.FOREST:
				if unit.tactical_role == UnitState.TacticalRole.SCOUT:
					unit.move_speed *= 1.1
					unit.sight_range *= 1.25
					unit.terrain_effect_key = &"TERRAIN_EFFECT_FOREST_SCOUT"
				elif unit.tactical_role == UnitState.TacticalRole.ASSAULT:
					unit.armor += 1.0
					unit.terrain_effect_key = &"TERRAIN_EFFECT_FOREST_ASSAULT"
				elif unit.tactical_role == UnitState.TacticalRole.FIREPOWER:
					unit.move_speed *= 0.8
					unit.attack_range *= 0.7
					unit.terrain_effect_key = &"TERRAIN_EFFECT_FOREST_FIREPOWER"
			UnitState.TerrainKind.BRIDGE:
				unit.move_speed *= 0.82
				unit.armor = maxf(0.0, unit.armor - 1.0)
				unit.terrain_effect_key = &"TERRAIN_EFFECT_BRIDGE_EXPOSED"
			UnitState.TerrainKind.HIGH_GROUND:
				if unit.tactical_role == UnitState.TacticalRole.FIREPOWER:
					unit.attack_range *= 1.2
					unit.sight_range *= 1.25
					unit.terrain_effect_key = &"TERRAIN_EFFECT_HIGH_GROUND_FIREPOWER"
				elif unit.tactical_role == UnitState.TacticalRole.SCOUT:
					unit.sight_range *= 1.18
					unit.terrain_effect_key = &"TERRAIN_EFFECT_HIGH_GROUND_SCOUT"
		if unit.terrain_kind != previous_terrain:
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_TERRAIN_CHANGED, unit.entity_id, "terrain=%s;role=%s;effect=%s" % [UnitState.TerrainKind.keys()[unit.terrain_kind], UnitState.TacticalRole.keys()[unit.tactical_role], unit.terrain_effect_key]))


func _terrain_kind_at(position: Vector2) -> UnitState.TerrainKind:
	if battle_definition != null:
		var closest: BattleRegionDefinition
		var closest_distance := INF
		for region in battle_definition.strategic_regions:
			var distance := position.distance_to(region.position)
			if distance <= region.radius and distance < closest_distance:
				closest = region
				closest_distance = distance
		if closest != null:
			match closest.terrain_key:
				&"TERRAIN_OPEN":
					return UnitState.TerrainKind.OPEN
				&"TERRAIN_RUINS":
					return UnitState.TerrainKind.RUINS
				&"TERRAIN_FOREST":
					return UnitState.TerrainKind.FOREST
				&"TERRAIN_BRIDGE":
					return UnitState.TerrainKind.BRIDGE
				&"TERRAIN_HIGH_GROUND":
					return UnitState.TerrainKind.HIGH_GROUND
	return UnitState.TerrainKind.NONE


func _advance_support_effects() -> void:
	for card_variant in unit_cards.values():
		var unit_card := card_variant as UnitCardState
		if unit_card.fortified_ticks_remaining > 0:
			unit_card.fortified_ticks_remaining -= 1
			if unit_card.fortified_ticks_remaining == 0:
				events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPORT_ENDED, unit_card.faction_id, "fortify=%s" % unit_card.definition.definition_id))
		if unit_card.rapid_mobility_ticks_remaining > 0:
			unit_card.rapid_mobility_ticks_remaining -= 1
			if unit_card.rapid_mobility_ticks_remaining == 0:
				events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPORT_ENDED, unit_card.faction_id, "rapid_mobility=%s" % unit_card.definition.definition_id))
	for faction_id in air_recon_until_by_faction:
		var active_regions := air_recon_until_by_faction[faction_id] as Dictionary
		var expired_ids: Array[StringName] = []
		for region_id in active_regions:
			if int(active_regions[region_id]) <= current_tick:
				expired_ids.append(region_id)
		for region_id in expired_ids:
			active_regions.erase(region_id)
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.SUPPORT_ENDED, int(faction_id), "air_recon=%s" % region_id))


func _advance_unit_card_deployments() -> void:
	var card_ids := unit_cards.keys()
	card_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	for card_id in card_ids:
		var unit_card := unit_cards[card_id] as UnitCardState
		if unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYING:
			continue
		unit_card.deployment_ticks_remaining = maxi(0, unit_card.deployment_ticks_remaining - 1)
		if unit_card.deployment_ticks_remaining > 0:
			continue
		var composition_members := UnitCardCompositionCompiler.expand(unit_card.definition, unit_card)
		if composition_members.is_empty():
			unit_card.deployment_state = UnitCardState.DeploymentState.DISABLED
			continue
		var formation_id := _next_formation_id
		_next_formation_id += 1
		var first_entity_id := _next_unit_id
		var member_ids := _create_scenario_formation(
			formation_id,
			unit_card.faction_id,
			composition_members[0].unit_definition_id,
			composition_members.size(),
			unit_card.deployment_position,
			first_entity_id,
			Vector2.UP, 0, 0, composition_members
		)
		_next_unit_id += member_ids.size()
		unit_card.member_entity_ids = member_ids
		unit_card.formation_id = formation_id
		unit_card.deployment_state = UnitCardState.DeploymentState.DEPLOYED
		_bind_unit_card_members(unit_card)
		_reset_unit_card_organization_baseline(unit_card)
		var commander := commanders.get(unit_card.commander_definition_id) as CommanderState
		if commander != null:
			_assign_commander_objective(commander, commander.target_position, commander.target_region_id, commander.planned_route)
		events.append(SimulationEvent.new(
			current_tick,
			SimulationEvent.Kind.UNIT_CARD_DEPLOYED,
			first_entity_id,
			"card=%s;formation=%d;strength=%d" % [
				unit_card.definition.definition_id,
				formation_id,
				member_ids.size(),
			]
		))
	_refresh_battle_population()


func _refresh_battle_population() -> void:
	if not is_card_battle():
		return
	var population_by_faction: Dictionary = {}
	for faction_id in factions:
		population_by_faction[faction_id] = 0
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if unit.enabled:
			population_by_faction[unit.faction_id] = int(population_by_faction.get(unit.faction_id, 0)) + 1
	for card_variant in unit_cards.values():
		var unit_card := card_variant as UnitCardState
		if unit_card.deployment_state == UnitCardState.DeploymentState.DEPLOYING:
			population_by_faction[unit_card.faction_id] = int(population_by_faction.get(unit_card.faction_id, 0)) + unit_card.available_strength
	for faction_id in factions:
		(factions[faction_id] as FactionState).population = int(population_by_faction.get(faction_id, 0))


func _advance_grey_ridge_economy() -> void:
	var interval := battle_definition.base_supply_interval_ticks if battle_definition != null else GREY_RIDGE_SUPPLY_INTERVAL_TICKS
	if not is_card_battle() or current_tick == 0 or current_tick % interval != 0:
		return
	var faction := factions[LOCAL_PLAYER_ID] as FactionState
	var previous_supply := faction.supply
	faction.supply = mini(faction.supply_capacity, faction.supply + 1)
	if faction.supply != previous_supply:
		events.append(SimulationEvent.new(
			current_tick,
			SimulationEvent.Kind.SUPPLY_CHANGED,
			LOCAL_PLAYER_ID,
			"supply=%d;delta=1;source=base_income" % faction.supply
		))


func _advance_strategic_regions() -> void:
	if not is_card_battle():
		return
	var region_ids := strategic_regions.keys()
	region_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for region_id in region_ids:
		var region := strategic_regions[region_id] as StrategicRegionState
		if not region.capturable:
			continue
		var occupying_factions: Dictionary = {}
		for unit_variant in units.values():
			var unit := unit_variant as UnitState
			var card := unit_cards.get(unit.unit_card_id) as UnitCardState
			if card != null and card.uses_tactical_organization() and card.organization <= 0.0 and region.controller_faction_id != unit.faction_id:
				continue
			if unit.enabled and unit.tactical_role != UnitState.TacticalRole.SCOUT and unit.definition_id != &"supply_truck" and unit.position.distance_to(region.position) <= region.radius:
				occupying_factions[unit.faction_id] = int(occupying_factions.get(unit.faction_id, 0)) + 1
		var previous_controller := region.controller_faction_id
		var previous_contested := region.contested
		var previous_capture_faction := region.capture_faction_id
		region.contested = occupying_factions.size() > 1
		if occupying_factions.size() == 1:
			var occupying_faction_id := int(occupying_factions.keys()[0])
			if occupying_faction_id == region.controller_faction_id:
				region.capture_faction_id = occupying_faction_id
				region.capture_progress_ticks = region.capture_required_ticks
			else:
				if region.capture_faction_id != occupying_faction_id:
					region.capture_faction_id = occupying_faction_id
					region.capture_progress_ticks = 0
				region.capture_progress_ticks = mini(region.capture_required_ticks, region.capture_progress_ticks + 1)
				if previous_capture_faction != occupying_faction_id:
					events.append(SimulationEvent.new(
						current_tick, SimulationEvent.Kind.REGION_CAPTURE_STARTED, occupying_faction_id,
						"region=%s;faction=%d;progress=%d;required=%d" % [region.region_id, occupying_faction_id, region.capture_progress_ticks, region.capture_required_ticks]
					))
				if region.capture_progress_ticks >= region.capture_required_ticks:
					region.controller_faction_id = occupying_faction_id
		elif occupying_factions.is_empty():
			if region.controller_faction_id != 0:
				if region.capture_faction_id != 0 and region.capture_faction_id != region.controller_faction_id and region.capture_progress_ticks > 0:
					events.append(SimulationEvent.new(
						current_tick, SimulationEvent.Kind.REGION_CAPTURE_INTERRUPTED, region.capture_faction_id,
						"region=%s;faction=%d" % [region.region_id, region.capture_faction_id]
					))
				region.capture_faction_id = region.controller_faction_id
				region.capture_progress_ticks = region.capture_required_ticks
			elif region.capture_progress_ticks > 0:
				region.capture_progress_ticks = maxi(0, region.capture_progress_ticks - REGION_CAPTURE_DECAY_PER_TICK)
				if region.capture_progress_ticks == 0:
					var interrupted_faction := region.capture_faction_id
					region.capture_faction_id = 0
					events.append(SimulationEvent.new(
						current_tick, SimulationEvent.Kind.REGION_CAPTURE_INTERRUPTED, interrupted_faction,
						"region=%s;faction=%d" % [region.region_id, interrupted_faction]
					))
		if region.controller_faction_id != previous_controller or region.contested != previous_contested:
			events.append(SimulationEvent.new(
				current_tick,
				SimulationEvent.Kind.REGION_CONTROL_CHANGED,
				0,
				"region=%s;controller=%d;contested=%s;capture_faction=%d;progress=%d;required=%d" % [
					region.region_id, region.controller_faction_id, region.contested,
					region.capture_faction_id, region.capture_progress_ticks, region.capture_required_ticks,
				]
			))
		var settlement_interval := battle_definition.region_settlement_interval_ticks if battle_definition != null else GREY_RIDGE_REGION_INTERVAL_TICKS
		if current_tick == 0 or current_tick % settlement_interval != 0:
			continue
		if region.controller_faction_id == 0 or region.contested:
			continue
		var faction := factions.get(region.controller_faction_id) as FactionState
		if faction == null:
			continue
		var previous_supply := faction.supply
		faction.supply = mini(faction.supply_capacity, faction.supply + region.supply_per_settlement)
		var credited_supply := faction.supply - previous_supply
		region.last_settlement_tick = current_tick
		events.append(SimulationEvent.new(
			current_tick,
			SimulationEvent.Kind.REGION_SETTLED,
			region.controller_faction_id,
			"region=%s;credited=%d;supply=%d" % [region.region_id, credited_supply, faction.supply]
		))
		if credited_supply > 0:
			events.append(SimulationEvent.new(
				current_tick,
				SimulationEvent.Kind.SUPPLY_CHANGED,
				region.controller_faction_id,
				"supply=%d;delta=%d;source=%s" % [faction.supply, credited_supply, region.region_id]
			))


func _advance_escort_supply_node() -> void:
	if not is_card_battle() or battle_definition == null or battle_definition.escort_unit_card_id.is_empty() or escort_supply_node_active:
		return
	var escort_card := unit_cards.get(battle_definition.escort_unit_card_id) as UnitCardState
	var destination := strategic_regions.get(battle_definition.escort_destination_region_id) as StrategicRegionState
	if escort_card == null or destination == null or escort_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
		return
	var arrived_entity_id := 0
	for entity_id in escort_card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled and unit.position.distance_to(destination.position) <= battle_definition.escort_arrival_radius:
			arrived_entity_id = entity_id
			break
	if arrived_entity_id == 0:
		return
	escort_supply_node_active = true
	destination.supply_node_active = true
	destination.supply_per_settlement += battle_definition.escort_region_supply_bonus
	var faction := factions.get(escort_card.faction_id) as FactionState
	if faction == null:
		return
	faction.supply_capacity += battle_definition.escort_supply_capacity_bonus
	var previous_supply := faction.supply
	faction.supply = mini(faction.supply_capacity, faction.supply + battle_definition.escort_supply_reward)
	var credited_supply := faction.supply - previous_supply
	events.append(SimulationEvent.new(
		current_tick, SimulationEvent.Kind.SUPPLY_NODE_ACTIVATED, arrived_entity_id,
		"region=%s;card=%s;capacity_bonus=%d;credited=%d;region_income=%d" % [
			destination.region_id, escort_card.definition.definition_id,
			battle_definition.escort_supply_capacity_bonus, credited_supply, destination.supply_per_settlement,
		]
	))
	if credited_supply > 0:
		events.append(SimulationEvent.new(
			current_tick, SimulationEvent.Kind.SUPPLY_CHANGED, faction.faction_id,
			"supply=%d;delta=%d;source=%s" % [faction.supply, credited_supply, destination.region_id]
		))


func _advance_escort_interception() -> void:
	if battle_definition == null or not battle_definition.enemy_intercepts_escort or escort_supply_node_active:
		return
	var enemy_knowledge := faction_knowledge.get(ENEMY_PLAYER_ID) as FactionKnowledge
	if enemy_knowledge == null:
		return
	var target_contact: KnowledgeContact
	for entity_id in enemy_knowledge.visible_hostile_unit_ids:
		var contact := enemy_knowledge.hostile_contacts.get(entity_id) as KnowledgeContact
		if contact == null or not contact.enabled or contact.definition_id != &"supply_truck":
			continue
		if target_contact == null or contact.entity_id < target_contact.entity_id:
			target_contact = contact
	if target_contact == null:
		enemy_escort_observed_tick = -1
		return
	if enemy_escort_observed_tick < 0:
		enemy_escort_observed_tick = current_tick
		events.append(SimulationEvent.new(
			current_tick, SimulationEvent.Kind.ENEMY_REACTION_ARMED, target_contact.entity_id,
			"rule=escort_intercept;source=LEGAL_FACTION_OBSERVATION;delay=%d" % battle_definition.escort_intercept_delay_ticks
		))
		return
	if current_tick - enemy_escort_observed_tick < battle_definition.escort_intercept_delay_ticks:
		return
	var interceptors := _enemy_formation_state(&"probe")
	if interceptors == null:
		interceptors = _enemy_formation_state(&"assault")
	if interceptors == null:
		return
	_prune_disabled_formation_members(interceptors)
	if interceptors.member_entity_ids.is_empty():
		return
	var command := AttackCommand.new(
		allocate_command_id(), ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT, current_tick,
		interceptors.leader_entity_id, target_contact.entity_id, interceptors.formation_id
	)
	command.agent_id = battle_definition.enemy_agent_id
	command.task_id = battle_definition.enemy_task_id
	var result := submit_command(command)
	if not result.is_accepted():
		enemy_reaction_log.append("tick=%d;rule=escort_intercept;source=LEGAL_FACTION_OBSERVATION;target=%d;command_rejected=%s" % [current_tick, target_contact.entity_id, result.describe()])
		enemy_escort_observed_tick = -1
		return
	enemy_escort_intercept_target_id = target_contact.entity_id
	enemy_reaction_committed_until_tick = current_tick + 120
	var detail := "rule=escort_intercept;source=LEGAL_FACTION_OBSERVATION;observed_tick=%d;target=%d;commit_until=%d" % [
		current_tick, target_contact.entity_id, enemy_reaction_committed_until_tick,
	]
	enemy_reaction_log.append("tick=%d;%s" % [current_tick, detail])
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ENEMY_REACTION_COMMITTED, interceptors.leader_entity_id, detail))


func _reset_unit_card_organization_baseline(card: UnitCardState) -> void:
	if card == null:
		return
	var total_health := 0.0
	var active_strength := 0
	for entity_id in card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit == null or not unit.enabled:
			continue
		total_health += unit.health
		active_strength += 1
	card.last_total_health = total_health
	card.last_active_strength = active_strength
	card.last_organization_band = _organization_band(card.organization)


func refresh_unit_card_organization_baseline(card: UnitCardState) -> void:
	_reset_unit_card_organization_baseline(card)


func _advance_unit_card_organization() -> void:
	if battle_definition == null or battle_definition.organization_max <= 0.0:
		return
	var card_ids := unit_cards.keys()
	card_ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for card_id in card_ids:
		var card := unit_cards[card_id] as UnitCardState
		if card == null or not card.organization_enabled or card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		var total_health := 0.0
		var suppression := 0.0
		var suppression_events: Array[SimulationEvent] = []
		var active_strength := 0
		var position_sum := Vector2.ZERO
		for entity_id in card.member_entity_ids:
			var unit := units.get(entity_id) as UnitState
			if unit == null or not unit.enabled:
				continue
			total_health += unit.health
			suppression += unit.pending_suppression
			suppression_events.append_array(unit.pending_suppression_events)
			unit.pending_suppression_events.clear()
			unit.pending_suppression = 0.0
			active_strength += 1
			position_sum += unit.position
		var previous_band := _organization_band(card.organization)
		var suppression_budget := minf(card.organization, suppression) if active_strength > 0 else 0.0
		for suppression_event in suppression_events:
			suppression_event.applied_amount = minf(suppression_event.applied_amount, suppression_budget)
			suppression_budget -= suppression_event.applied_amount
		var health_loss := maxf(0.0, card.last_total_health - total_health)
		var member_loss := maxi(0, card.last_active_strength - active_strength)
		if active_strength <= 0:
			card.organization = 0.0
		elif health_loss > 0.0 or member_loss > 0 or suppression > 0.0:
			card.organization -= suppression
			card.organization -= health_loss * battle_definition.organization_damage_factor
			card.organization -= float(member_loss) * battle_definition.organization_member_loss
			card.last_damage_tick = current_tick
		elif current_tick - card.last_damage_tick >= battle_definition.organization_recovery_delay_ticks:
			var recovery := battle_definition.organization_recovery_per_tick
			var center := position_sum / float(active_strength)
			var recovery_region := strategic_regions.get(battle_definition.organization_recovery_region_id) as StrategicRegionState
			if recovery_region != null and center.distance_to(recovery_region.position) <= battle_definition.organization_recovery_radius:
				recovery += battle_definition.organization_recovery_region_bonus
				var commander := commanders.get(card.commander_definition_id) as CommanderState
				if commander != null and commander.has_doctrine(&"rally_reorganization"):
					recovery += battle_definition.organization_recovery_region_bonus
			card.organization += recovery * _unit_card_organization_recovery_multiplier(card)
		card.organization = clampf(card.organization, 0.0, battle_definition.organization_max)
		card.last_total_health = total_health
		card.last_active_strength = active_strength
		var current_band := _organization_band(card.organization)
		if current_band != previous_band:
			card.last_organization_band = current_band
			events.append(SimulationEvent.new(
				current_tick,
				SimulationEvent.Kind.UNIT_CARD_ORGANIZATION_CHANGED,
				_card_leader_entity_id(card),
				"card=%s;organization=%.2f;band=%d" % [card.definition.definition_id, card.organization, current_band]
			))
	# Impacts on disabled or non-organized cards cannot contribute organization loss.
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		for suppression_event in unit.pending_suppression_events:
			suppression_event.applied_amount = 0.0
		unit.pending_suppression_events.clear()


func _unit_card_organization_recovery_multiplier(card: UnitCardState) -> float:
	var multiplier := 1.0
	for growth_id in [card.honor_id, card.equipment_id]:
		var growth: Variant = ArmyRosterStore.GROWTH_CATALOG.get_growth(growth_id)
		if growth != null:
			multiplier *= growth.organization_recovery_multiplier
	return multiplier


func _advance_limited_withdrawals() -> void:
	if battle_definition == null or battle_definition.withdrawal_region_id.is_empty():
		return
	var withdrawal_region := strategic_regions.get(battle_definition.withdrawal_region_id) as StrategicRegionState
	if withdrawal_region == null:
		return
	var card_ids := unit_cards.keys()
	card_ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for card_id in card_ids:
		var card := unit_cards[card_id] as UnitCardState
		if card == null or card.faction_id != LOCAL_PLAYER_ID or card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		if not _unit_card_targets_withdrawal(card, withdrawal_region):
			continue
		var survivors: Array[int] = []
		var all_inside := true
		for entity_id in card.member_entity_ids:
			var unit := units.get(entity_id) as UnitState
			if unit == null or not unit.enabled:
				continue
			survivors.append(entity_id)
			if unit.position.distance_to(withdrawal_region.position) > battle_definition.withdrawal_arrival_radius:
				all_inside = false
		if survivors.is_empty() or not all_inside:
			continue
		_complete_unit_card_withdrawal(card, survivors)


func _unit_card_targets_withdrawal(card: UnitCardState, withdrawal_region: StrategicRegionState) -> bool:
	var task := _task_for_unit_card(card.definition.definition_id)
	if task != null and (task.target_position.distance_to(withdrawal_region.position) <= withdrawal_region.radius \
		or task.final_target_position.distance_to(withdrawal_region.position) <= withdrawal_region.radius):
		return true
	var commander := commanders.get(card.commander_definition_id) as CommanderState
	return commander != null and commander.target_region_id == withdrawal_region.region_id


func _complete_unit_card_withdrawal(card: UnitCardState, survivors: Array[int]) -> void:
	var former_formation_id := card.formation_id
	var event_entity_id := survivors[0] if not survivors.is_empty() else 0
	card.withdrawn_strength = survivors.size()
	card.withdrawn_tick = current_tick
	card.available_strength = survivors.size()
	for entry in card.composition:
		entry.withdrawn_strength = entry.active_count(units)
		entry.available_strength = entry.withdrawn_strength
	card.deployment_state = UnitCardState.DeploymentState.WITHDRAWN
	card.control_state = UnitCardState.ControlState.UNASSIGNED
	card.assigned_task_id = 0
	card.formation_id = 0
	for entity_id in survivors:
		var unit := units.get(entity_id) as UnitState
		if unit == null:
			continue
		unit.enabled = false
		unit.attack_target_entity_id = 0
		unit.has_move_target = false
		unit.following_formation = false
		unit.formation_id = 0
	if former_formation_id != 0:
		formations.erase(former_formation_id)
	events.append(SimulationEvent.new(
		current_tick,
		SimulationEvent.Kind.UNIT_CARD_WITHDRAWN,
		event_entity_id,
		"card=%s;strength=%d;organization=%.2f" % [card.definition.definition_id, card.withdrawn_strength, card.organization]
	))


func _organization_band(value: float) -> int:
	if value <= 0.0:
		return 0
	if value < 30.0:
		return 1
	if value < 60.0:
		return 2
	return 3


func _card_leader_entity_id(card: UnitCardState) -> int:
	var formation := formations.get(card.formation_id) as FormationState
	if formation != null:
		return formation.leader_entity_id
	for entity_id in card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			return entity_id
	return 0
	enemy_escort_observed_tick = -1


func _advance_grey_ridge_enemy_reactions() -> void:
	var formation := _enemy_formation_state(&"assault")
	if formation == null:
		return
	_prune_disabled_formation_members(formation)
	if formation.member_entity_ids.is_empty():
		return
	var enemy_knowledge := faction_knowledge.get(ENEMY_PLAYER_ID) as FactionKnowledge
	if enemy_knowledge == null:
		return
	var ready_rule: EnemyReactionRuleState
	var ready_observation: Dictionary = {}
	for rule in enemy_reaction_rules:
		var observation := _enemy_reaction_observation(rule, enemy_knowledge, formation)
		if not bool(observation.get("active", false)):
			rule.observed_tick = -1
			continue
		if rule.observed_tick < 0:
			rule.observed_tick = current_tick
			rule.last_target_entity_id = int(observation.get("target_entity_id", 0))
			rule.last_target_position = observation.get("target_position", Vector2.ZERO) as Vector2
			rule.last_reason = String(observation.get("reason", ""))
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ENEMY_REACTION_ARMED, formation.leader_entity_id, "rule=%s;observation=%s;delay=%d" % [rule.rule_id, rule.last_reason, rule.delay_ticks]))
		if current_tick < enemy_reaction_committed_until_tick or current_tick - rule.observed_tick < rule.delay_ticks:
			continue
		if ready_rule == null or rule.priority > ready_rule.priority:
			ready_rule = rule
			ready_observation = observation
	if ready_rule != null:
		var reacting_formation := _formation_for_enemy_reaction(ready_rule, ready_observation, formation)
		_commit_enemy_reaction(ready_rule, ready_observation, reacting_formation)


func _advance_enemy_strategic_ai() -> void:
	if battle_definition == null or current_tick < enemy_reaction_committed_until_tick or current_tick < _next_enemy_strategic_decision_tick:
		return
	_next_enemy_strategic_decision_tick = current_tick + ENEMY_STRATEGIC_DECISION_INTERVAL_TICKS
	var enemy_agent_id := battle_definition.enemy_agent_id
	var enemy_policy := agent_policies.get(enemy_agent_id) as AgentPolicy
	if enemy_policy == null or enemy_policy.faction_id != ENEMY_PLAYER_ID or not enemy_policy.allows_proactive_tasks():
		return
	var probe := _enemy_formation_state(&"probe")
	if probe != null:
		_prune_disabled_formation_members(probe)
		if not probe.member_entity_ids.is_empty() and _formation_has_scout(probe) and _open_task_for_formation(ENEMY_PLAYER_ID, probe.formation_id) == null and not probe.is_moving:
			_submit_enemy_scout_order(probe, enemy_agent_id)
	var assault := _enemy_formation_state(&"assault")
	if assault == null:
		return
	_prune_disabled_formation_members(assault)
	var locked_followup_tick := battle_definition.enemy_offensive_followup_tick
	if assault.member_entity_ids.is_empty() or not enemy_offensive_followup_executed \
		or current_tick < locked_followup_tick + 300 or assault.is_moving \
		or assault.order_target_entity_id != 0 or assault.engagement_state != FormationState.EngagementState.NONE:
		return
	var open_task := _open_task_for_formation(ENEMY_PLAYER_ID, assault.formation_id)
	var contact := _best_visible_hostile(create_faction_snapshot(ENEMY_PLAYER_ID), assault.anchor_position)
	if not contact.is_empty():
		var target_id := int(contact.get("entity_id", 0))
		if open_task == null or open_task.kind != TaskState.Kind.ATTACK_TARGET or open_task.target_entity_id != target_id:
			_submit_enemy_attack_order(assault, target_id, contact.get("position", assault.anchor_position) as Vector2, enemy_agent_id, open_task)
		return
	if open_task != null and open_task.kind == TaskState.Kind.DEFEND_AREA:
		var held_region := _region_near_position(open_task.target_position)
		if held_region != null and (held_region.controller_faction_id != ENEMY_PLAYER_ID or held_region.contested):
			return
	var capture_region := _best_enemy_capture_region(assault.anchor_position)
	if capture_region != null and (open_task == null or open_task.target_position.distance_to(capture_region.position) > 1.0):
		_submit_enemy_capture_order(assault, capture_region, enemy_agent_id, open_task)


func _submit_enemy_scout_order(formation: FormationState, enemy_agent_id: int) -> void:
	var target := find_reachable_scout_target(ENEMY_PLAYER_ID, formation.anchor_position)
	if target.is_equal_approx(formation.anchor_position):
		return
	var command := StrategicOrderCommand.new(
		allocate_command_id(), ENEMY_PLAYER_ID, current_tick,
		StrategicOrderCommand.OrderKind.SCOUT_AREA, formation.formation_id, 0,
		target, FRIENDLY_SCOUT_RADIUS, GameCommand.IssuerKind.AGENT
	)
	command.agent_id = enemy_agent_id
	command.strategic_priority = ENEMY_STRATEGIC_PRIORITY_SCOUT
	submit_command(command)


func _submit_enemy_attack_order(formation: FormationState, target_id: int, target_position: Vector2, enemy_agent_id: int, replaced_task: TaskState) -> void:
	if target_id == 0:
		return
	var command := StrategicOrderCommand.new(
		allocate_command_id(), ENEMY_PLAYER_ID, current_tick,
		StrategicOrderCommand.OrderKind.ATTACK_TARGET, formation.formation_id, target_id,
		target_position, 0.0, GameCommand.IssuerKind.AGENT
	)
	command.agent_id = enemy_agent_id
	command.strategic_priority = ENEMY_STRATEGIC_PRIORITY_ATTACK
	command.replaces_task_id = replaced_task.task_id if replaced_task != null else 0
	submit_command(command)


func _submit_enemy_capture_order(formation: FormationState, region: StrategicRegionState, enemy_agent_id: int, replaced_task: TaskState) -> void:
	var deployment_position := find_formation_deployment_position(
		formation, region.position, clampf(region.radius * 0.55, 96.0, 192.0)
	)
	if not deployment_position.is_finite() or deployment_position.distance_to(region.position) > region.radius:
		return
	var command := StrategicOrderCommand.new(
		allocate_command_id(), ENEMY_PLAYER_ID, current_tick,
		StrategicOrderCommand.OrderKind.DEFEND_AREA, formation.formation_id, 0,
		deployment_position, clampf(region.radius * 0.35, 72.0, 144.0), GameCommand.IssuerKind.AGENT
	)
	command.agent_id = enemy_agent_id
	command.strategic_priority = ENEMY_STRATEGIC_PRIORITY_CAPTURE
	command.replaces_task_id = replaced_task.task_id if replaced_task != null else 0
	submit_command(command)


func _best_enemy_capture_region(origin: Vector2) -> StrategicRegionState:
	var best: StrategicRegionState
	var best_score := -INF
	var region_ids := strategic_regions.keys()
	region_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for region_id in region_ids:
		var region := strategic_regions[region_id] as StrategicRegionState
		if region == null or not region.capturable or region.controller_faction_id == ENEMY_PLAYER_ID and not region.contested:
			continue
		if pathfinder.find_path(origin, region.position).is_empty():
			continue
		var score := float(region.supply_per_settlement * 100) - origin.distance_to(region.position) / 64.0
		if region.controller_faction_id == LOCAL_PLAYER_ID:
			score += 75.0
		if region.contested:
			score += 30.0
		if score > best_score:
			best = region
			best_score = score
	return best


func _region_near_position(position: Vector2) -> StrategicRegionState:
	for region_variant in strategic_regions.values():
		var region := region_variant as StrategicRegionState
		if region != null and region.capturable and position.distance_to(region.position) <= region.radius:
			return region
	return null


func _open_task_for_formation(faction_id: int, formation_id: int) -> TaskState:
	for task_variant in tasks.values():
		var task := task_variant as TaskState
		if task.faction_id == faction_id and task.formation_id == formation_id and _is_open_task(task):
			return task
	return null


func _formation_has_scout(formation: FormationState) -> bool:
	for entity_id in formation.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled and unit.definition_id == &"scout_vehicle":
			return true
	return false


func _advance_grey_ridge_locked_plan_followup() -> void:
	var plan := battle_definition.enemy_plan_dictionary().get(enemy_opening_plan_id) as BattleEnemyPlanDefinition if battle_definition != null else null
	if plan != null and plan.followup_tick >= 0 and not enemy_opening_followup_executed and current_tick >= plan.followup_tick:
		var probe := _enemy_formation_state(plan.followup_formation_role_id)
		if probe != null:
			_prune_disabled_formation_members(probe)
			if probe.member_entity_ids.is_empty():
				enemy_opening_followup_executed = true
				enemy_reaction_log.append("tick=%d;source=LOCKED_PLAN_TIMELINE;plan=%s;action=FEINT_ABORTED;reason=probe_destroyed" % [current_tick, enemy_opening_plan_id])
			elif not probe.is_moving and probe.order_target_entity_id == 0:
				var redirect := FormationMoveCommand.new(
					allocate_command_id(), ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT, current_tick,
					probe.leader_entity_id, probe.formation_id, plan.followup_target_position
				)
				redirect.agent_id = battle_definition.enemy_agent_id
				redirect.task_id = battle_definition.enemy_task_id
				if submit_command(redirect).is_accepted():
					enemy_opening_followup_executed = true
					enemy_reaction_log.append("tick=%d;source=LOCKED_PLAN_TIMELINE;plan=%s;action=FEINT_REDIRECT_CENTRAL;formation=%d;commit_until=%d" % [
						current_tick, enemy_opening_plan_id, probe.formation_id, enemy_reaction_committed_until_tick,
					])
	_advance_grey_ridge_offensive_followup()


func _advance_grey_ridge_offensive_followup() -> void:
	var followup_tick := battle_definition.enemy_offensive_followup_tick if battle_definition != null else GREY_RIDGE_OFFENSIVE_FOLLOWUP_TICK
	if current_tick < followup_tick or current_tick < enemy_reaction_committed_until_tick:
		return
	var formation := _enemy_formation_state(&"assault")
	var headquarters := buildings.get(PLAYER_COMMAND_CENTER_ID) as BuildingState
	if formation == null or headquarters == null or not headquarters.enabled:
		return
	_prune_disabled_formation_members(formation)
	if formation.member_entity_ids.is_empty() or formation.is_moving or formation.order_target_entity_id != 0:
		return
	var desired_position := get_attack_destination(PLAYER_COMMAND_CENTER_ID, formation.anchor_position)
	var deployment_radius := battle_definition.deployment_radius if battle_definition != null else GREY_RIDGE_DEPLOYMENT_RADIUS
	var destination := find_formation_deployment_position(formation, desired_position, deployment_radius)
	if not destination.is_finite():
		return
	var command := AttackMoveCommand.new(
		allocate_command_id(), ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT, current_tick,
		formation.leader_entity_id, formation.formation_id, destination
	)
	command.agent_id = battle_definition.enemy_agent_id
	command.task_id = battle_definition.enemy_task_id
	if not submit_command(command).is_accepted():
		return
	if not enemy_offensive_followup_executed:
		enemy_offensive_followup_executed = true
		enemy_reaction_log.append("tick=%d;source=LOCKED_PLAN_TIMELINE;plan=%s;action=EXPLOIT_PLAYER_HEADQUARTERS;formation=%d" % [
			current_tick, enemy_opening_plan_id, formation.formation_id,
		])


func _formation_for_enemy_reaction(
	rule: EnemyReactionRuleState,
	observation: Dictionary,
	fallback: FormationState
) -> FormationState:
	var probe := _enemy_formation_state(&"probe")
	if probe != null:
		_prune_disabled_formation_members(probe)
	if probe == null or probe.member_entity_ids.is_empty():
		return fallback
	if rule.trigger_kind == EnemyReactionRuleState.TriggerKind.VISIBLE_FLANK_FORCE:
		return probe
	if rule.trigger_kind == EnemyReactionRuleState.TriggerKind.VISIBLE_HQ_THREAT:
		var target_position := observation.get("target_position", fallback.anchor_position) as Vector2
		if probe.anchor_position.distance_squared_to(target_position) < fallback.anchor_position.distance_squared_to(target_position):
			return probe
	return fallback


func _enemy_formation_state(role_id: StringName) -> FormationState:
	if battle_definition == null:
		return null
	var definition := battle_definition.enemy_formation_by_role(role_id)
	return formations.get(definition.formation_id) as FormationState if definition != null else null


func _enemy_reaction_observation(rule: EnemyReactionRuleState, enemy_knowledge: FactionKnowledge, formation: FormationState) -> Dictionary:
	var enemy_headquarters := buildings.get(ENEMY_COMMAND_CENTER_ID) as BuildingState
	if enemy_headquarters == null or not enemy_headquarters.enabled:
		return {"active": false}
	if rule.trigger_kind == EnemyReactionRuleState.TriggerKind.OWN_FORCE_DEPLETED:
		return {
			"active": formation.member_entity_ids.size() <= 5,
			"target_position": enemy_headquarters.position,
			"region_id": &"enemy_headquarters",
			"reason": "own_survivors=%d" % formation.member_entity_ids.size(),
		}
	var best_contact: KnowledgeContact
	var best_distance := INF
	var matched_region: StringName = &""
	for entity_id in enemy_knowledge.visible_hostile_unit_ids:
		var contact := enemy_knowledge.hostile_contacts.get(entity_id) as KnowledgeContact
		if contact == null or not contact.enabled or contact.faction_id == ENEMY_PLAYER_ID:
			continue
		var matches := false
		var distance := INF
		var region_id: StringName = &""
		match rule.trigger_kind:
			EnemyReactionRuleState.TriggerKind.VISIBLE_HQ_THREAT:
				distance = contact.position.distance_to(enemy_headquarters.position)
				matches = distance <= 460.0
				region_id = &"enemy_headquarters"
			EnemyReactionRuleState.TriggerKind.VISIBLE_CENTRAL_FORCE:
				var central := battle_definition.strategic_regions[1] if battle_definition != null and battle_definition.strategic_regions.size() > 1 else null
				var central_position := central.position if central != null else GREY_RIDGE_CENTRAL_POSITION
				var central_radius := central.radius if central != null else GREY_RIDGE_REGION_RADIUS
				distance = contact.position.distance_to(central_position)
				matches = distance <= central_radius
				region_id = central.region_id if central != null else &"central_relay"
			EnemyReactionRuleState.TriggerKind.VISIBLE_FLANK_FORCE:
				var west := battle_definition.strategic_regions[0] if battle_definition != null and not battle_definition.strategic_regions.is_empty() else null
				var east := battle_definition.strategic_regions[-1] if battle_definition != null and not battle_definition.strategic_regions.is_empty() else null
				var west_distance := contact.position.distance_to(west.position if west != null else GREY_RIDGE_WEST_POSITION)
				var east_distance := contact.position.distance_to(east.position if east != null else GREY_RIDGE_EAST_POSITION)
				distance = minf(west_distance, east_distance)
				var flank_radius := west.radius if west_distance <= east_distance and west != null else (east.radius if east != null else GREY_RIDGE_REGION_RADIUS)
				matches = distance <= flank_radius
				region_id = (west.region_id if west != null else &"west_mine") if west_distance <= east_distance else (east.region_id if east != null else &"east_supply")
		if matches and (distance < best_distance or is_equal_approx(distance, best_distance) and (best_contact == null or contact.entity_id < best_contact.entity_id)):
			best_contact = contact
			best_distance = distance
			matched_region = region_id
	if best_contact == null:
		return {"active": false}
	return {
		"active": true,
		"target_entity_id": best_contact.entity_id,
		"target_position": best_contact.position,
		"region_id": matched_region,
		"reason": "visible_contact=%d;region=%s;observed_tick=%d" % [best_contact.entity_id, matched_region, current_tick],
	}


func _commit_enemy_reaction(rule: EnemyReactionRuleState, observation: Dictionary, formation: FormationState) -> void:
	var command: GameCommand
	var target_entity_id := int(observation.get("target_entity_id", 0))
	var target_position := observation.get("target_position", formation.anchor_position) as Vector2
	if rule.action_kind == EnemyReactionRuleState.ActionKind.WITHDRAW_TO_HEADQUARTERS or target_entity_id == 0:
		command = FormationMoveCommand.new(allocate_command_id(), ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT, current_tick, formation.leader_entity_id, formation.formation_id, target_position)
	else:
		command = AttackCommand.new(allocate_command_id(), ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT, current_tick, formation.leader_entity_id, target_entity_id, formation.formation_id)
	command.agent_id = battle_definition.enemy_agent_id
	command.task_id = battle_definition.enemy_task_id
	var result := submit_command(command)
	if not result.is_accepted():
		rule.last_reason = "%s;command_rejected=%s" % [rule.last_reason, result.describe()]
		return
	rule.last_fired_tick = current_tick
	rule.fired_count += 1
	rule.last_target_entity_id = target_entity_id
	rule.last_target_position = target_position
	enemy_reaction_committed_until_tick = current_tick + rule.commitment_ticks
	var detail := "rule=%s;source=LEGAL_FACTION_OBSERVATION;observed_tick=%d;delay=%d;action=%s;target=%d;commit_until=%d" % [rule.rule_id, rule.observed_tick, rule.delay_ticks, EnemyReactionRuleState.ActionKind.keys()[rule.action_kind], target_entity_id, enemy_reaction_committed_until_tick]
	enemy_reaction_log.append("tick=%d;%s" % [current_tick, detail])
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ENEMY_REACTION_COMMITTED, formation.leader_entity_id, detail))
	if is_entity_visible_to_faction(formation.leader_entity_id, LOCAL_PLAYER_ID):
		_add_intel_report(LOCAL_PLAYER_ID, &"INTEL_SOURCE_CARDINAL", &"INTEL_ENEMY_MANEUVER", formation.member_entity_ids.size(), formation.member_entity_ids.size(), observation.get("region_id", &"") as StringName, &"INTEL_DIRECTION_CURRENT", &"INTEL_CONFIDENCE_HIGH", 0, 0, true)
	rule.observed_tick = -1


func _prune_disabled_formation_members(formation: FormationState) -> void:
	var active_ids: Array[int] = []
	for entity_id in formation.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			active_ids.append(entity_id)
	if active_ids.size() == formation.member_entity_ids.size():
		return
	formation.member_entity_ids = active_ids
	formation.rebuild_slots()
	for entity_id in active_ids:
		var unit := units[entity_id] as UnitState
		unit.formation_slot_id = formation.get_slot_id(entity_id)


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
	return WorldSnapshot.new(current_tick, unit_snapshots, formation_snapshots, projectile_snapshots, metrics.create_snapshot(), faction_snapshots, building_snapshots, ore_snapshots, 0, null, true, task_snapshots, MissionSnapshot.new(mission_state), _create_commander_snapshots(), _create_unit_card_snapshots(), _create_strategic_region_snapshots(), _create_intel_report_snapshots(), _create_enemy_reaction_snapshots(), objective_system.create_snapshots(), battle_outcome, staff_plan_system.create_snapshots(0))


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
				var contact_snapshot := UnitSnapshot.new(null, contact)
				contact_snapshot.intel_freshness = _contact_freshness(contact)
				unit_snapshots.append(contact_snapshot)
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
	return WorldSnapshot.new(current_tick, unit_snapshots, formation_snapshots, projectile_snapshots, metrics.create_snapshot(), faction_snapshots, building_snapshots, ore_snapshots, faction_id, FactionKnowledgeSnapshot.new(knowledge), false, _create_task_snapshots(), MissionSnapshot.new(mission_state), _create_commander_snapshots(faction_id), _create_unit_card_snapshots(faction_id), _create_strategic_region_snapshots(), _create_intel_report_snapshots(faction_id), [], objective_system.create_snapshots(), battle_outcome, staff_plan_system.create_snapshots(faction_id))


func _create_task_snapshots() -> Array[TaskSnapshot]:
	var snapshots: Array[TaskSnapshot] = []
	var task_ids := tasks.keys()
	task_ids.sort()
	for task_id in task_ids:
		snapshots.append(TaskSnapshot.new(tasks[task_id] as TaskState))
	return snapshots


func _create_commander_snapshots(faction_id: int = 0) -> Array[CommanderSnapshot]:
	var snapshots: Array[CommanderSnapshot] = []
	var commander_ids := commanders.keys()
	commander_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for commander_id in commander_ids:
		var commander := commanders[commander_id] as CommanderState
		if faction_id == 0 or commander.faction_id == faction_id:
			snapshots.append(CommanderSnapshot.new(commander))
	return snapshots


func _create_unit_card_snapshots(faction_id: int = 0) -> Array[UnitCardSnapshot]:
	var snapshots: Array[UnitCardSnapshot] = []
	var unit_card_ids := unit_cards.keys()
	unit_card_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for unit_card_id in unit_card_ids:
		var unit_card := unit_cards[unit_card_id] as UnitCardState
		if faction_id == 0 or unit_card.faction_id == faction_id:
			snapshots.append(UnitCardSnapshot.new(unit_card, units))
	return snapshots


func _create_strategic_region_snapshots() -> Array[StrategicRegionSnapshot]:
	var snapshots: Array[StrategicRegionSnapshot] = []
	var region_ids := strategic_regions.keys()
	region_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for region_id in region_ids:
		snapshots.append(StrategicRegionSnapshot.new(strategic_regions[region_id] as StrategicRegionState))
	return snapshots


func _create_intel_report_snapshots(faction_id: int = 0) -> Array[IntelReportSnapshot]:
	var snapshots: Array[IntelReportSnapshot] = []
	for report in intel_reports:
		if faction_id == 0 or report.faction_id == faction_id:
			snapshots.append(IntelReportSnapshot.new(report, current_tick))
	return snapshots


func _create_enemy_reaction_snapshots() -> Array[EnemyReactionSnapshot]:
	var snapshots: Array[EnemyReactionSnapshot] = []
	for rule in enemy_reaction_rules:
		snapshots.append(EnemyReactionSnapshot.new(rule))
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
				var sensor_range := unit.sight_range
				var sensor_card := unit_cards.get(unit.unit_card_id) as UnitCardState
				if sensor_card != null:
					sensor_range = maxf(sensor_range, tactical_ability_system.observation_range(sensor_card, current_tick))
				knowledge.reveal(logic_grid.world_to_cell(unit.position), ceili(sensor_range / LogicGrid.CELL_SIZE))
		for building_variant in buildings.values():
			var building := building_variant as BuildingState
			if building.enabled and building.faction_id == faction_id:
				var definition := BUILDING_CATALOG.get_building(building.definition_id)
				var sight_range := definition.sight_range if definition != null else 256.0
				knowledge.reveal(logic_grid.world_to_cell(building.position), ceili(sight_range / LogicGrid.CELL_SIZE))
		var active_recon_regions := air_recon_until_by_faction.get(faction_id, {}) as Dictionary
		for region_id in active_recon_regions:
			if int(active_recon_regions[region_id]) > current_tick and strategic_regions.has(region_id):
				var region := strategic_regions[region_id] as StrategicRegionState
				knowledge.reveal(logic_grid.world_to_cell(region.position), ceili(region.radius / LogicGrid.CELL_SIZE))
		_update_contacts(knowledge)
		tactical_ability_system.update_identification(self, knowledge)
		_prune_expired_contacts(knowledge)
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
		faction_knowledge[faction_id] = FactionKnowledge.new(faction_id, logic_grid.grid_size)


func _update_contacts(knowledge: FactionKnowledge) -> void:
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if unit.faction_id != knowledge.faction_id and knowledge.is_visible(logic_grid.world_to_cell(unit.position)):
			var contact := knowledge.hostile_contacts.get(entity_id) as KnowledgeContact
			if contact == null or contact.is_building:
				contact = KnowledgeContact.new()
				knowledge.hostile_contacts[entity_id] = contact
			contact.update_from_unit(unit, current_tick)
			knowledge.visible_hostile_unit_ids.append(int(entity_id))
	var building_ids := buildings.keys()
	building_ids.sort()
	for building_id in building_ids:
		var building := buildings[building_id] as BuildingState
		if building.faction_id != knowledge.faction_id and knowledge.is_visible(logic_grid.world_to_cell(building.position)):
			var contact := knowledge.hostile_contacts.get(building_id) as KnowledgeContact
			if contact == null or not contact.is_building:
				contact = KnowledgeContact.new()
				knowledge.hostile_contacts[building_id] = contact
			contact.update_from_building(building, current_tick)
			knowledge.visible_hostile_building_ids.append(int(building_id))


func _prune_expired_contacts(knowledge: FactionKnowledge) -> void:
	var expiry_ticks := battle_definition.contact_expire_after_ticks if battle_definition != null else 0
	if expiry_ticks <= 0:
		return
	var contact_ids := knowledge.hostile_contacts.keys()
	contact_ids.sort()
	for entity_id in contact_ids:
		var contact := knowledge.hostile_contacts[entity_id] as KnowledgeContact
		var remains_visible := knowledge.visible_hostile_building_ids.has(int(entity_id)) if contact.is_building else knowledge.visible_hostile_unit_ids.has(int(entity_id))
		if remains_visible or current_tick - contact.last_seen_tick < expiry_ticks:
			continue
		knowledge.hostile_contacts.erase(entity_id)
		events.append(SimulationEvent.new(
			current_tick, SimulationEvent.Kind.INTEL_CONTACT_EXPIRED, int(entity_id),
			"faction=%d;last_seen_tick=%d;age=%d" % [knowledge.faction_id, contact.last_seen_tick, current_tick - contact.last_seen_tick]
		))


func _contact_freshness(contact: KnowledgeContact) -> float:
	if battle_definition == null or battle_definition.contact_expire_after_ticks <= 0:
		return 1.0
	var fade_tick := battle_definition.contact_fade_after_ticks
	var age := maxi(0, current_tick - contact.last_seen_tick)
	if age <= fade_tick:
		return 1.0
	var fade_duration := maxi(1, battle_definition.contact_expire_after_ticks - fade_tick)
	return clampf(1.0 - float(age - fade_tick) / float(fade_duration), 0.0, 1.0)


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
			var aggressor := units.get(target_id) as UnitState
			if worker.attack_is_retaliation and aggressor != null and aggressor.enabled and aggressor.can_attack \
				and aggressor.faction_id != worker.faction_id \
				and aggressor.attack_target_entity_id == worker.entity_id \
				and is_entity_visible_to_faction(target_id, worker.faction_id):
				if worker.position.distance_to(get_entity_position(target_id)) <= worker.attack_range * 1.15:
					continue
			_clear_attack_target(worker, "retaliation_ended")
		var aggressor_id := _find_worker_aggressor(worker)
		if aggressor_id != 0:
			worker.attack_target_entity_id = aggressor_id
			worker.attack_is_retaliation = true
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ATTACK_STARTED, worker.entity_id, "target=%d;retaliate=1" % aggressor_id))


func _find_worker_aggressor(worker: UnitState) -> int:
	var best_id := 0
	var best_distance := INF
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var enemy := units[entity_id] as UnitState
		if not enemy.enabled or not enemy.can_attack or enemy.faction_id == worker.faction_id or enemy.attack_target_entity_id != worker.entity_id:
			continue
		if not is_entity_visible_to_faction(enemy.entity_id, worker.faction_id):
			continue
		var distance := worker.position.distance_squared_to(enemy.position)
		if distance > worker.attack_range * worker.attack_range or distance >= best_distance:
			continue
		best_id = enemy.entity_id
		best_distance = distance
	return best_id


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
		var members_out_of_range := 0
		for entity_id in formation.member_entity_ids:
			var member := units[entity_id] as UnitState
			if not member.enabled or not member.following_formation or member.formation_id != formation.formation_id or not member.can_attack:
				continue
			# Every member owns its target immediately; weapon range only decides
			# whether the formation must keep closing the distance.
			member.attack_target_entity_id = target_id
			member.attack_is_retaliation = false
			if member.position.distance_to(target_position) > member.attack_range:
				members_out_of_range += 1
		if members_out_of_range == 0:
			formation.engagement_state = FormationState.EngagementState.ENGAGING
			formation.is_moving = false
			formation.path = PackedVector2Array()
		else:
			formation.engagement_state = FormationState.EngagementState.PURSUING
			if formation.order_kind == FormationState.OrderKind.ATTACK_TARGET:
				var destination := get_attack_destination(target_id, formation.anchor_position)
				var destination_cell := logic_grid.world_to_cell(destination)
				var target_moved := formation.pursuit_target_cell != destination_cell
				var repath_due := current_tick - formation.last_repath_tick >= 5
				if target_moved or not formation.is_moving and repath_due:
					formation.target_position = destination
					formation.path = pathfinder.find_path(formation.anchor_position, destination)
					formation.path_index = 1
					formation.is_moving = formation.path.size() > 1
					formation.pursuit_target_cell = destination_cell
					formation.last_repath_tick = current_tick
	_update_individual_combat_orders()


func _update_commander_combat_coordination() -> void:
	var commander_ids := commanders.keys()
	commander_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
		return String(left) < String(right)
	)
	for commander_id in commander_ids:
		var commander := commanders[commander_id] as CommanderState
		if commander == null or commander.posture == CommanderState.Posture.DISENGAGE:
			continue
		var combat_cards := _commander_agent_combat_cards(commander)
		if combat_cards.is_empty():
			continue
		var target_id := _select_commander_focus_target(combat_cards, commander.faction_id)
		if target_id == 0:
			continue
		var active_cards: Array[UnitCardState] = []
		for card in combat_cards:
			var formation := formations.get(card.formation_id) as FormationState
			var may_proactively_engage := commander.faction_id == LOCAL_PLAYER_ID \
				and formation != null \
				and formation.anchor_position.distance_to(get_entity_position(target_id)) <= FORMATION_AUTO_ENGAGE_RADIUS
			if formation != null and (_formation_is_attacked_by(formation, target_id) \
				or _formation_has_target_in_weapon_range(formation, target_id) \
				or may_proactively_engage):
				active_cards.append(card)
		if active_cards.is_empty():
			continue
		var reinforcement_cards: Array[UnitCardState] = []
		for candidate in _commander_reinforcement_candidates(commander, combat_cards, active_cards, target_id):
			reinforcement_cards.append(candidate)
		for card in active_cards + reinforcement_cards:
			_queue_commander_focus_attack(commander, card, target_id, not reinforcement_cards.has(card))
		if not reinforcement_cards.is_empty():
			for card in active_cards:
				var task := _task_for_unit_card(card.definition.definition_id)
				if task != null:
					task.reinforcement_committed = true


func _commander_agent_combat_cards(commander: CommanderState) -> Array[UnitCardState]:
	var result: Array[UnitCardState] = []
	for unit_card_id in commander.subordinate_unit_card_ids:
		var card := unit_cards.get(unit_card_id) as UnitCardState
		if card == null or card.deployment_state != UnitCardState.DeploymentState.DEPLOYED \
			or card.control_state != UnitCardState.ControlState.AGENT_ASSIGNED \
			or not formations.has(card.formation_id) or card.definition.role_key == &"UNIT_CARD_ROLE_RECON":
			continue
		var task := _task_for_unit_card(unit_card_id)
		if not _task_allows_tactical_response(task):
			continue
		result.append(card)
	return result


func _select_commander_focus_target(cards: Array[UnitCardState], faction_id: int) -> int:
	var best_id := 0
	var best_is_aggressor := false
	var best_can_attack := false
	var best_health_fraction := INF
	var best_distance := INF
	for card in cards:
		var formation := formations.get(card.formation_id) as FormationState
		if formation == null:
			continue
		var candidate_id := _nearest_visible_formation_aggressor(formation, faction_id)
		if candidate_id == 0:
			var engagement_radius := FORMATION_AUTO_ENGAGE_RADIUS if faction_id == LOCAL_PLAYER_ID else 0.0
			candidate_id = _select_visible_target_in_formation_weapon_range(formation, faction_id, engagement_radius)
		if candidate_id == 0:
			continue
		var hostile := units.get(candidate_id) as UnitState
		var is_aggressor := _formation_is_attacked_by(formation, candidate_id)
		var can_attack := hostile != null and hostile.can_attack
		var max_health := hostile.max_health if hostile != null else (buildings[candidate_id] as BuildingState).max_health
		var health := hostile.health if hostile != null else (buildings[candidate_id] as BuildingState).health
		var health_fraction := health / maxf(1.0, max_health)
		var distance := formation.anchor_position.distance_squared_to(get_entity_position(candidate_id))
		var is_better := best_id == 0 \
			or is_aggressor and not best_is_aggressor \
			or is_aggressor == best_is_aggressor and can_attack and not best_can_attack \
			or is_aggressor == best_is_aggressor and can_attack == best_can_attack and health_fraction < best_health_fraction \
			or is_aggressor == best_is_aggressor and can_attack == best_can_attack and is_equal_approx(health_fraction, best_health_fraction) and distance < best_distance \
			or is_aggressor == best_is_aggressor and can_attack == best_can_attack and is_equal_approx(health_fraction, best_health_fraction) and is_equal_approx(distance, best_distance) and candidate_id < best_id
		if is_better:
			best_id = candidate_id
			best_is_aggressor = is_aggressor
			best_can_attack = can_attack
			best_health_fraction = health_fraction
			best_distance = distance
	return best_id


func _formation_is_attacked_by(formation: FormationState, hostile_id: int) -> bool:
	var hostile := units.get(hostile_id) as UnitState
	return hostile != null and formation.member_entity_ids.has(hostile.attack_target_entity_id)


func _formation_has_target_in_weapon_range(formation: FormationState, target_id: int) -> bool:
	if not is_entity_enabled(target_id):
		return false
	var target_position := get_entity_position(target_id)
	for member_id in formation.member_entity_ids:
		var member := units.get(member_id) as UnitState
		if member != null and member.enabled and member.can_attack and member.can_accept_attack_orders \
			and member.position.distance_to(target_position) <= member.attack_range:
			return true
	return false


func _queue_commander_focus_attack(commander: CommanderState, card: UnitCardState, target_id: int, primary: bool) -> void:
	var formation := formations.get(card.formation_id) as FormationState
	var task := _task_for_unit_card(card.definition.definition_id)
	if formation == null or task == null:
		return
	if formation.order_target_entity_id == target_id and task.coordinated_target_entity_id == target_id:
		task.coordinated_support_until_tick = current_tick + COORDINATED_ENGAGEMENT_TICKS
		return
	var attack := AttackCommand.new(
		allocate_command_id(), commander.faction_id, GameCommand.IssuerKind.AGENT, current_tick,
		formation.leader_entity_id, target_id, formation.formation_id
	)
	attack.agent_id = commander.agent_id
	attack.task_id = task.task_id
	if submit_command(attack).is_accepted():
		_mark_task_coordinated_engagement(task, target_id)
		task.last_detail = "Commander focus fire" if primary else "Commander reinforcement committed"


func _unit_card_combat_power(card: UnitCardState) -> float:
	var power := 0.0
	for entity_id in card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit == null or not unit.enabled or not unit.can_attack:
			continue
		power += unit.health / maxf(1.0, unit.max_health) * unit.attack_damage * unit.attacks_per_second
	if card.organization_enabled and battle_definition != null and battle_definition.organization_max > 0.0:
		var organization_ratio := clampf(card.organization / battle_definition.organization_max, 0.0, 1.0)
		power *= lerpf(0.35, 1.0, organization_ratio)
	return power


func _observed_enemy_power_near(target_id: int, faction_id: int) -> float:
	var knowledge := faction_knowledge.get(faction_id) as FactionKnowledge
	if knowledge == null:
		return 0.0
	var target_position := get_entity_position(target_id)
	var power := 0.0
	for entity_id in knowledge.visible_hostile_unit_ids:
		var contact := knowledge.hostile_contacts.get(entity_id) as KnowledgeContact
		if contact == null or not contact.enabled or not contact.can_attack \
			or contact.position.distance_to(target_position) > COMMANDER_THREAT_CLUSTER_RADIUS:
			continue
		var definition := UNIT_CATALOG.get_unit(contact.definition_id)
		if definition == null or definition.combat == null:
			continue
		power += contact.health / maxf(1.0, contact.max_health) * definition.combat.attack_power * definition.combat.attacks_per_second
	return power


func _commander_reinforcement_candidates(
	commander: CommanderState,
	combat_cards: Array[UnitCardState],
	active_cards: Array[UnitCardState],
	target_id: int
) -> Array[UnitCardState]:
	var result: Array[UnitCardState] = []
	var target_position := get_entity_position(target_id)
	var committed_power := 0.0
	var observed_enemy_power := _observed_enemy_power_near(target_id, commander.faction_id)
	for active_card in active_cards:
		committed_power += _unit_card_combat_power(active_card)
	if commander.faction_id != LOCAL_PLAYER_ID \
		and committed_power >= observed_enemy_power * COMMANDER_PRIMARY_POWER_RATIO:
		return result
	for card in combat_cards:
		if active_cards.has(card):
			continue
		var formation := formations.get(card.formation_id) as FormationState
		var support_distance := COMMANDER_SUPPORT_DISTANCE * (1.35 if commander.has_doctrine(&"mutual_support") or commander.has_doctrine(&"reserve_commitment") else 1.0)
		if formation == null or formation.anchor_position.distance_to(target_position) > support_distance:
			continue
		if pathfinder.find_path(formation.anchor_position, get_attack_destination(target_id, formation.anchor_position)).is_empty():
			continue
		result.append(card)
	result.sort_custom(func(first: UnitCardState, second: UnitCardState) -> bool:
		var first_formation := formations[first.formation_id] as FormationState
		var second_formation := formations[second.formation_id] as FormationState
		var first_distance := first_formation.anchor_position.distance_squared_to(target_position)
		var second_distance := second_formation.anchor_position.distance_squared_to(target_position)
		return first_distance < second_distance or (is_equal_approx(first_distance, second_distance) and String(first.definition.definition_id) < String(second.definition.definition_id))
	)
	if commander.faction_id == LOCAL_PLAYER_ID:
		return result
	var viable_result: Array[UnitCardState] = []
	for candidate in result:
		viable_result.append(candidate)
		committed_power += _unit_card_combat_power(candidate)
		if committed_power >= observed_enemy_power * COMMANDER_REINFORCED_POWER_RATIO:
			return viable_result
	return []


func _update_shared_formation_responses() -> void:
	var formation_ids := formations.keys()
	formation_ids.sort()
	for formation_id in formation_ids:
		var formation := formations[formation_id] as FormationState
		if formation.order_target_entity_id != 0 or formation.order_kind in [FormationState.OrderKind.ATTACK_TARGET, FormationState.OrderKind.ATTACK_MOVE]:
			continue
		var leader := units.get(formation.leader_entity_id) as UnitState
		if leader == null:
			continue
		var task := tasks.get(leader.assigned_task_id) as TaskState
		if not _task_allows_tactical_response(task) or _formation_is_scouting(formation):
			continue
		if task != null and task.coordinated_target_entity_id != 0:
			continue
		var engagement_radius := FORMATION_AUTO_ENGAGE_RADIUS if leader.faction_id == LOCAL_PLAYER_ID else 0.0
		var target_id := _select_visible_target_in_formation_weapon_range(formation, leader.faction_id, engagement_radius)
		if target_id == 0:
			continue
		if leader.control_state != UnitState.ControlState.AGENT_ASSIGNED:
			_assign_autonomous_in_range_target(formation, target_id)
			continue
		var response := AttackCommand.new(
			allocate_command_id(), leader.faction_id, GameCommand.IssuerKind.AGENT,
			current_tick, leader.entity_id, target_id, formation.formation_id
		)
		response.agent_id = leader.assigned_agent_id
		response.task_id = leader.assigned_task_id
		if submit_command(response).is_accepted() and task != null:
			_mark_task_coordinated_engagement(task, target_id)


func _task_allows_tactical_response(task: TaskState) -> bool:
	if task == null:
		return true
	if task.lifecycle != TaskState.Lifecycle.EXECUTING:
		return false
	if task.kind == TaskState.Kind.SCOUT_AREA:
		return false
	return task.phase not in [TaskState.Phase.EVADING, TaskState.Phase.RETREATING]


func _formation_is_scouting(formation: FormationState) -> bool:
	for entity_id in formation.member_entity_ids:
		var member := units.get(entity_id) as UnitState
		if member != null and member.enabled and member.tactical_role == UnitState.TacticalRole.SCOUT:
			return true
	return false


func _select_visible_target_in_formation_weapon_range(formation: FormationState, faction_id: int, engagement_radius: float = 0.0) -> int:
	var best_id := 0
	var best_is_aggressor := false
	var best_can_attack := false
	var best_health_fraction := INF
	var best_distance := INF
	var member_ids: Dictionary = {}
	var firing_members: Array[UnitState] = []
	for member_id in formation.member_entity_ids:
		member_ids[member_id] = true
		var member := units.get(member_id) as UnitState
		if member != null and member.enabled and member.can_attack and member.can_accept_attack_orders:
			firing_members.append(member)
	if firing_members.is_empty() and engagement_radius <= 0.0:
		return 0
	var candidate_ids: Array[int] = []
	var knowledge := faction_knowledge.get(faction_id) as FactionKnowledge
	if knowledge != null:
		for entity_id in knowledge.visible_hostile_unit_ids:
			candidate_ids.append(int(entity_id))
		for entity_id in knowledge.visible_hostile_building_ids:
			candidate_ids.append(int(entity_id))
	else:
		for entity_id in units.keys():
			candidate_ids.append(int(entity_id))
		for entity_id in buildings.keys():
			candidate_ids.append(int(entity_id))
	candidate_ids.sort()
	for entity_id in candidate_ids:
		if not is_entity_enabled(entity_id) or get_entity_faction_id(entity_id) == faction_id or not is_entity_visible_to_faction(entity_id, faction_id):
			continue
		var target_position := get_entity_position(entity_id)
		var nearest_firing_distance := INF
		for member in firing_members:
			var distance := member.position.distance_to(target_position)
			if distance <= member.attack_range:
				nearest_firing_distance = minf(nearest_firing_distance, distance)
		var anchor_distance := formation.anchor_position.distance_to(target_position)
		if not is_finite(nearest_firing_distance) and (engagement_radius <= 0.0 or anchor_distance > engagement_radius):
			continue
		if not is_finite(nearest_firing_distance):
			nearest_firing_distance = anchor_distance
		var hostile := units.get(entity_id) as UnitState
		var is_aggressor := hostile != null and member_ids.has(hostile.attack_target_entity_id)
		var can_attack := hostile != null and hostile.can_attack
		var health_fraction := 1.0
		if hostile != null:
			health_fraction = hostile.health / maxf(1.0, hostile.max_health)
		else:
			var building := buildings.get(entity_id) as BuildingState
			health_fraction = building.health / maxf(1.0, building.max_health)
		var is_better := best_id == 0 \
			or is_aggressor and not best_is_aggressor \
			or is_aggressor == best_is_aggressor and can_attack and not best_can_attack \
			or is_aggressor == best_is_aggressor and can_attack == best_can_attack and health_fraction < best_health_fraction \
			or is_aggressor == best_is_aggressor and can_attack == best_can_attack and is_equal_approx(health_fraction, best_health_fraction) and nearest_firing_distance < best_distance \
			or is_aggressor == best_is_aggressor and can_attack == best_can_attack and is_equal_approx(health_fraction, best_health_fraction) and is_equal_approx(nearest_firing_distance, best_distance) and entity_id < best_id
		if is_better:
			best_id = entity_id
			best_is_aggressor = is_aggressor
			best_can_attack = can_attack
			best_health_fraction = health_fraction
			best_distance = nearest_firing_distance
	return best_id


func _assign_autonomous_in_range_target(formation: FormationState, target_id: int) -> void:
	var target_position := get_entity_position(target_id)
	for member_id in formation.member_entity_ids:
		var member := units.get(member_id) as UnitState
		if member == null or not member.enabled or not member.can_attack or not member.can_accept_attack_orders:
			continue
		if member.position.distance_to(target_position) > member.attack_range:
			continue
		if member.attack_target_entity_id != target_id:
			member.attack_target_entity_id = target_id
			member.attack_is_retaliation = true
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ATTACK_STARTED, member.entity_id, "target=%d;autonomous=1" % target_id))


func _mark_task_coordinated_engagement(task: TaskState, target_id: int) -> void:
	task.coordinated_target_entity_id = target_id
	task.coordinated_support_until_tick = current_tick + COORDINATED_ENGAGEMENT_TICKS
	task.set_phase(TaskState.Phase.ENGAGING, current_tick, "Coordinated focus fire on E%d" % target_id)


func _nearest_visible_formation_aggressor(formation: FormationState, faction_id: int) -> int:
	var member_ids: Dictionary = {}
	for member_id in formation.member_entity_ids:
		member_ids[member_id] = true
	var best_id := 0
	var best_distance := INF
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var hostile := units[entity_id] as UnitState
		if not hostile.enabled or hostile.faction_id == faction_id or not member_ids.has(hostile.attack_target_entity_id):
			continue
		if not is_entity_visible_to_faction(hostile.entity_id, faction_id):
			continue
		var distance := hostile.position.distance_squared_to(formation.anchor_position)
		if distance > COMMANDER_THREAT_CLUSTER_RADIUS * COMMANDER_THREAT_CLUSTER_RADIUS:
			continue
		if distance < best_distance:
			best_id = hostile.entity_id
			best_distance = distance
	return best_id


func _update_individual_combat_orders() -> void:
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if not unit.enabled or unit.following_formation or not unit.can_attack:
			continue
		if unit.attack_target_entity_id == 0 and unit.can_accept_attack_orders and unit.tactical_role != UnitState.TacticalRole.SCOUT:
			var acquisition_radius := minf(unit.sight_range, 320.0) if unit.is_attack_moving else unit.attack_range
			var acquired_target := _find_nearest_enemy_for_faction(unit.position, unit.faction_id, acquisition_radius)
			if acquired_target != 0:
				unit.attack_target_entity_id = acquired_target
				unit.attack_is_retaliation = false
				unit.pursuit_target_cell = Vector2i(-1, -1)
				events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ATTACK_STARTED, unit.entity_id, "target=%d;autonomous=%d" % [acquired_target, int(not unit.is_attack_moving)]))
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
			member.attack_is_retaliation = false
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


func _apply_commander_order(command: CommanderOrderCommand) -> void:
	var commander := commanders[command.commander_id] as CommanderState
	if command.issuer_kind == GameCommand.IssuerKind.PLAYER and command.order_kind != CommanderOrderCommand.OrderKind.CANCEL_INTENT and (command.hand_back_control or command.order_kind == CommanderOrderCommand.OrderKind.ASSIGN_INTENT):
		for card_id in commander.subordinate_unit_card_ids:
			var card := unit_cards.get(card_id) as UnitCardState
			if card != null and card.faction_id == commander.faction_id and card.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
				_release_card_for_commander(card, "PLAYER_EXECUTION_ORDER")
	if command.order_kind == CommanderOrderCommand.OrderKind.SET_POSTURE:
		commander.posture = command.posture
		if commander.posture == CommanderState.Posture.DISENGAGE:
			commander.clear_high_level_intent()
			_assign_commander_objective(commander, _commander_disengage_position(commander), &"")
		elif commander.posture == CommanderState.Posture.HOLD:
			_reissue_commander_tasks_at_current_positions(commander)
		else:
			_assign_commander_objective(commander, commander.target_position, commander.target_region_id, commander.planned_route)
		commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", _commander_posture_reason_key(commander.posture), current_tick)
	elif command.order_kind == CommanderOrderCommand.OrderKind.CANCEL_INTENT:
		_cancel_commander_intent(commander)
		commander.set_behavior(&"COMMANDER_BEHAVIOR_STANDING_BY", &"COMMANDER_REASON_NO_ACTIVE_TASK", current_tick)
	elif command.order_kind == CommanderOrderCommand.OrderKind.ASSIGN_INTENT:
		commander.posture = command.posture
		commander.set_high_level_intent(
			command.intent_id, command.target_region_id, command.main_axis_region_id,
			command.reserve_policy, current_tick
		)
		_assign_commander_objective(commander, command.target_position, command.target_region_id, command.route_points)
		commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", &"COMMANDER_REASON_OBJECTIVE_COORDINATION", current_tick)
	else:
		_assign_commander_objective(commander, command.target_position, command.target_region_id, command.route_points)
		commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", &"COMMANDER_REASON_OBJECTIVE_COORDINATION", current_tick)
	events.append(SimulationEvent.new(
		current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, 0,
		"COMMANDER_%s;behavior=%s;reason=%s;posture=%s;intent=%s;objective=%s;axis=%s;reserve=%s" % [
			commander.definition.definition_id, commander.behavior_state_key, commander.behavior_reason_key,
			CommanderState.Posture.keys()[commander.posture], commander.active_intent_id,
			commander.intent_objective_region_id, commander.intent_axis_region_id,
			CommanderState.ReservePolicy.keys()[commander.intent_reserve_policy],
		]
	))


func _cancel_commander_intent(commander: CommanderState) -> void:
	for task_id in commander.current_task_ids.duplicate():
		var task := tasks.get(task_id) as TaskState
		if task == null or task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
			continue
		task.set_lifecycle(TaskState.Lifecycle.CANCELLED, current_tick, TaskState.BlockedReason.NONE, "High-level intent cancelled by player")
		task.set_phase(TaskState.Phase.DONE, current_tick, "High-level intent cancelled by player")
		_stop_task_formation(task)
		release_task_participants(task)
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, task.task_id, "CANCELLED:HIGH_LEVEL_INTENT"))
	for unit_card_id in commander.subordinate_unit_card_ids:
		var card := unit_cards.get(unit_card_id) as UnitCardState
		if card == null or card.control_state in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.PLAYER_CONTROLLED, UnitCardState.ControlState.RETURNING]:
			continue
		card.assigned_task_id = 0
		card.assigned_agent_id = 0
		card.control_state = UnitCardState.ControlState.UNASSIGNED
	commander.set_task_ids([])
	commander.clear_high_level_intent()


func _apply_equip_doctrine(command: EquipDoctrineCommand) -> void:
	var commander := commanders[command.commander_id] as CommanderState
	commander.equip_doctrine(command.doctrine_id, command.slot_index)
	_assign_commander_objective(commander, commander.target_position, commander.target_region_id, commander.planned_route)
	commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", _commander_doctrine_reason_key(command.doctrine_id), current_tick)
	events.append(SimulationEvent.new(
		current_tick, SimulationEvent.Kind.DOCTRINE_EQUIPPED, 0,
		"commander=%s;doctrine=%s;position=%.1f,%.1f" % [command.commander_id, command.doctrine_id, commander.target_position.x, commander.target_position.y]
	))
	events.append(SimulationEvent.new(
		current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, 0,
		"COMMANDER_%s;doctrine=%s;slot=%d" % [commander.definition.definition_id, command.doctrine_id, command.slot_index]
	))


func _assign_commander_objective(
	commander: CommanderState,
	target_position: Vector2,
	target_region_id: StringName,
	planned_route: PackedVector2Array = PackedVector2Array()
) -> void:
	commander.target_position = target_position
	commander.target_region_id = target_region_id
	commander.planned_route = planned_route.duplicate()
	var deployed_cards: Array[UnitCardState] = []
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := unit_cards.get(unit_card_id) as UnitCardState
		if unit_card != null and unit_card.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
			deployed_cards.append(unit_card)
	var task_ids: Array[int] = []
	for index in range(deployed_cards.size()):
		var unit_card := deployed_cards[index]
		var formation := formations.get(unit_card.formation_id) as FormationState
		var card_target := _commander_card_target(commander, unit_card, deployed_cards.size(), index, target_position, formation)
		var existing_task := _task_for_unit_card(unit_card.definition.definition_id)
		if unit_card.control_state in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.RETURNING] and existing_task != null:
			existing_task.target_position = card_target
			existing_task.target_radius = _commander_task_radius(commander, existing_task.kind)
			existing_task.last_detail = "Commander objective updated while unit card remains under player control"
			task_ids.append(existing_task.task_id)
			continue
		var task := _assign_unit_card_task(commander, unit_card, card_target, commander.planned_route)
		if task != null:
			task_ids.append(task.task_id)
	commander.set_task_ids(task_ids)


func _commander_card_target(
	commander: CommanderState,
	unit_card: UnitCardState,
	deployed_card_count: int,
	card_index: int,
	target_position: Vector2,
	formation: FormationState
) -> Vector2:
	if commander.posture == CommanderState.Posture.HOLD and not commander.has_doctrine(&"elastic_defense") and formation != null:
		return formation.anchor_position
	var role_key := unit_card.definition.role_key if unit_card != null and unit_card.definition != null else &""
	var doctrine_offset := 0.0
	if commander.has_doctrine(&"rapid_bridging") and role_key == &"UNIT_CARD_ROLE_ENGINEERING":
		doctrine_offset = 220.0
	elif commander.has_doctrine(&"overwatch_lattice") and role_key == &"UNIT_CARD_ROLE_FIREPOWER":
		doctrine_offset = 320.0
	elif commander.has_doctrine(&"elastic_defense"):
		doctrine_offset = 200.0
	var doctrine_target := target_position
	if doctrine_offset > 0.0:
		var toward_base := (_faction_base_position(commander.faction_id) - target_position).normalized()
		if not toward_base.is_zero_approx():
			doctrine_target += toward_base * doctrine_offset
	var offset_index := float(card_index) - float(deployed_card_count - 1) * 0.5
	var narrow := _commander_effect(commander, DoctrineActionDefinition.Kind.NARROW_FRONTAGE)
	var spacing := narrow.effect.formation_spacing if narrow != null else (72.0 if commander.has_doctrine(&"mutual_support") else 112.0)
	return doctrine_target + Vector2(offset_index * spacing, 0.0)


func _reissue_commander_tasks_at_current_positions(commander: CommanderState) -> void:
	var task_ids: Array[int] = []
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := unit_cards.get(unit_card_id) as UnitCardState
		if unit_card == null or unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or not formations.has(unit_card.formation_id):
			continue
		var task := _assign_unit_card_task(commander, unit_card, (formations[unit_card.formation_id] as FormationState).anchor_position)
		if task != null:
			task_ids.append(task.task_id)
	commander.set_task_ids(task_ids)


func _assign_unit_card_task(
	commander: CommanderState,
	unit_card: UnitCardState,
	target_position: Vector2,
	planned_route: PackedVector2Array = PackedVector2Array()
) -> TaskState:
	if unit_card.control_state in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.RETURNING]:
		return _task_for_unit_card(unit_card.definition.definition_id)
	var old_task := _task_for_unit_card(unit_card.definition.definition_id)
	if old_task != null and old_task.lifecycle in [TaskState.Lifecycle.WAITING, TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING, TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]:
		old_task.set_lifecycle(TaskState.Lifecycle.CANCELLED, current_tick, TaskState.BlockedReason.NONE, "Replaced by commander objective")
		old_task.set_phase(TaskState.Phase.DONE, current_tick, "Replaced by commander objective")
		_stop_task_formation(old_task)
		release_task_participants(old_task)
	var participants: Array[int] = []
	for entity_id in unit_card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			participants.append(entity_id)
	if participants.is_empty() or not formations.has(unit_card.formation_id):
		return null
	var kind := TaskState.Kind.DEFEND_AREA if commander.posture == CommanderState.Posture.DISENGAGE \
		else (TaskState.Kind.SCOUT_AREA if unit_card.definition.role_key == &"UNIT_CARD_ROLE_RECON" else TaskState.Kind.DEFEND_AREA)
	var task := TaskState.new(_next_task_id, commander.agent_id, participants)
	_next_task_id += 1
	task.faction_id = commander.faction_id
	task.kind = kind
	task.formation_id = unit_card.formation_id
	var formation := formations[unit_card.formation_id] as FormationState
	task.final_target_position = target_position
	task.planned_route = planned_route.duplicate()
	task.target_radius = _commander_task_radius(commander, kind)
	var resolved_target := find_formation_deployment_position(formation, target_position, task.target_radius, task.planned_route)
	task.target_position = resolved_target if resolved_target.is_finite() else target_position
	var recon := _commander_effect(commander, DoctrineActionDefinition.Kind.CAUTIOUS_RECON)
	if recon != null and kind == TaskState.Kind.SCOUT_AREA and formation.anchor_position.distance_to(target_position) > recon.effect.staging_distance:
		var staged_target := formation.anchor_position.lerp(target_position, recon.effect.staging_fraction)
		var resolved_stage := find_formation_deployment_position(formation, staged_target, task.target_radius, task.planned_route)
		task.final_target_position = task.target_position
		task.target_position = resolved_stage if resolved_stage.is_finite() else staged_target
		task.has_staged_target = true
	task.priority = 60
	task.accepted_tick = current_tick
	task.persistent_order = true
	var equipped_definitions: Array[DoctrineDefinition] = []
	for doctrine_id in commander.equipped_doctrine_ids:
		var definition := doctrine_definitions.get(doctrine_id) as DoctrineDefinition
		if definition != null and not definition.effects.is_empty():
			equipped_definitions.append(definition)
	var effect_parameters: DoctrineTaskParameters
	if not equipped_definitions.is_empty():
		effect_parameters = _doctrine_effect_registry.create_task_parameters(
			create_faction_snapshot(commander.faction_id), commander.faction_id,
			commander.definition.definition_id, unit_card.definition.definition_id, equipped_definitions
		)
	if effect_parameters != null and effect_parameters.applied:
		task.doctrine_effect = effect_parameters.duplicate_value()
		task.activation_tick = effect_parameters.activation_tick
		task.requires_observed_contact = effect_parameters.requires_observed_contact
	elif commander.has_doctrine(&"overwatch_lattice") and unit_card.definition.role_key == &"UNIT_CARD_ROLE_FIREPOWER":
		task.activation_tick = current_tick + 30
	elif commander.has_doctrine(&"reserve_commitment"):
		task.activation_tick = current_tick + maxi(0, _deployed_unit_card_index(commander, unit_card.definition.definition_id)) * 12
	task.unit_card_id = unit_card.definition.definition_id
	task.progress_target = StrategicTaskSystem.SCOUT_OBSERVE_TICKS if kind == TaskState.Kind.SCOUT_AREA else StrategicTaskSystem.DEFEND_HOLD_TICKS
	task.route = _build_task_planned_route(formation.anchor_position, task.target_position, task.planned_route)
	task.set_lifecycle(TaskState.Lifecycle.EXECUTING, current_tick)
	task.set_phase(TaskState.Phase.PREPARING, current_tick, "Assigned by %s" % commander.definition.definition_id)
	tasks[task.task_id] = task
	unit_card.control_state = UnitCardState.ControlState.AGENT_ASSIGNED
	unit_card.assigned_agent_id = commander.agent_id
	unit_card.assigned_task_id = task.task_id
	unit_card.return_task_id = 0
	unit_card.return_formation_id = 0
	for entity_id in participants:
		var unit := units[entity_id] as UnitState
		unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
		unit.assigned_agent_id = commander.agent_id
		unit.assigned_task_id = task.task_id
		unit.original_formation_id = unit_card.formation_id
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, task.task_id, "EXECUTING:COMMANDER_CARD:%s" % unit_card.definition.definition_id))
	return task


func _build_task_planned_route(start_position: Vector2, target_position: Vector2, route_points: PackedVector2Array) -> PackedVector2Array:
	var probe := FormationMoveCommand.new(0, LOCAL_PLAYER_ID, GameCommand.IssuerKind.AGENT, current_tick, 0, 0, target_position, route_points)
	return _build_formation_route(start_position, probe)


func _deployed_unit_card_index(commander: CommanderState, target_unit_card_id: StringName) -> int:
	var deployed_index := 0
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := unit_cards.get(unit_card_id) as UnitCardState
		if unit_card == null or unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		if unit_card_id == target_unit_card_id:
			return deployed_index
		deployed_index += 1
	return 0


func _task_for_unit_card(unit_card_id: StringName) -> TaskState:
	var task_ids := tasks.keys()
	task_ids.sort()
	for task_id in task_ids:
		var task := tasks[task_id] as TaskState
		if task.unit_card_id == unit_card_id and task.lifecycle in [TaskState.Lifecycle.WAITING, TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING, TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]:
			return task
	return null


func _advance_card_battle_doctrine_actions() -> void:
	_advance_reserve_commitment_doctrine()
	if battle_definition == null or battle_definition.engineering_routes.is_empty():
		return
	var commander_ids := commanders.keys()
	commander_ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for commander_id in commander_ids:
		var commander := commanders[commander_id] as CommanderState
		if commander == null or commander.posture == CommanderState.Posture.DISENGAGE or not commander.has_doctrine(&"rapid_bridging"):
			continue
		for route in battle_definition.engineering_routes:
			if route == null or opened_engineering_routes.has(route.route_id) or not _commander_targets_engineering_route(commander, route):
				continue
			var engineer_card := _deployed_engineering_card_for_commander(commander)
			if engineer_card == null:
				continue
			var faction := factions.get(commander.faction_id) as FactionState
			if faction == null or faction.supply < get_support_cost(SupportOrderCommand.SupportKind.ENGINEERING_ROUTE):
				continue
			var order := SupportOrderCommand.new(
				allocate_command_id(), commander.faction_id, GameCommand.IssuerKind.AGENT, current_tick,
				SupportOrderCommand.SupportKind.ENGINEERING_ROUTE, route.route_id, &"", engineer_card.definition.definition_id
			)
			order.agent_id = commander.agent_id
			if submit_command(order).is_accepted():
				commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", &"COMMANDER_REASON_RAPID_BRIDGING_AXIS", current_tick)


func _advance_reserve_commitment_doctrine() -> void:
	for commander_variant in commanders.values():
		var commander := commander_variant as CommanderState
		if commander == null or commander.posture == CommanderState.Posture.DISENGAGE or not commander.has_doctrine(&"reserve_commitment"):
			continue
		var estimate := _commander_hostile_estimate(commander)
		if not bool(estimate.get("reliable", false)):
			continue
		var active_strength := 0
		var reserve_card: UnitCardState
		for unit_card_id in commander.subordinate_unit_card_ids:
			var card := unit_cards.get(unit_card_id) as UnitCardState
			if card == null:
				continue
			if card.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
				active_strength += _active_unit_card_member_count(card)
			elif reserve_card == null and card.deployment_state == UnitCardState.DeploymentState.RESERVE and card.available_strength > 0:
				reserve_card = card
		if reserve_card == null or int(estimate.get("hostile_count", 0)) <= active_strength:
			continue
		var headquarters := buildings.get(PLAYER_COMMAND_CENTER_ID) as BuildingState
		if headquarters == null:
			continue
		var lateral := float(abs(String(reserve_card.definition.definition_id).hash()) % 5 - 2) * 48.0
		var deployment_position := headquarters.position + Vector2(lateral, -160.0)
		var deploy := DeployUnitCardCommand.new(allocate_command_id(), commander.faction_id, GameCommand.IssuerKind.AGENT, current_tick, reserve_card.definition.definition_id, deployment_position)
		deploy.agent_id = commander.agent_id
		if submit_command(deploy).is_accepted():
			commander.set_behavior(&"COMMANDER_BEHAVIOR_COORDINATING", &"COMMANDER_REASON_RESERVE_COMMITMENT", current_tick)


func _active_unit_card_member_count(card: UnitCardState) -> int:
	var count := 0
	for entity_id in card.member_entity_ids:
		var member := units.get(entity_id) as UnitState
		if member != null and member.enabled:
			count += 1
	return count


func _commander_targets_engineering_route(commander: CommanderState, route: BattleEngineeringRouteDefinition) -> bool:
	if commander.target_region_id == route.linked_region_id:
		return true
	var region := strategic_regions.get(route.linked_region_id) as StrategicRegionState
	return region != null and commander.target_position.distance_to(region.position) <= region.radius


func _deployed_engineering_card_for_commander(commander: CommanderState) -> UnitCardState:
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := unit_cards.get(unit_card_id) as UnitCardState
		if unit_card != null and unit_card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and unit_card.has_active_unit_type(&"engineer_vehicle", units):
			return unit_card
	return null


func _commander_effect(commander: CommanderState, kind: DoctrineActionDefinition.Kind) -> DoctrineEffectDefinition:
	return _doctrine_effect_registry.find_effect(commander.equipped_doctrine_ids, doctrine_definitions, kind)


func _commander_task_radius(commander: CommanderState, kind: TaskState.Kind) -> float:
	var posture := commander.posture
	if kind == TaskState.Kind.SCOUT_AREA:
		var recon := _commander_effect(commander, DoctrineActionDefinition.Kind.CAUTIOUS_RECON)
		if recon != null:
			return recon.effect.task_radius
		return 176.0 if posture == CommanderState.Posture.CAUTIOUS else 128.0
	var narrow := _commander_effect(commander, DoctrineActionDefinition.Kind.NARROW_FRONTAGE)
	if narrow != null:
		return narrow.effect.task_radius
	if commander.has_doctrine(&"elastic_defense"):
		return 224.0
	if commander.has_doctrine(&"fighting_withdrawal") and battle_definition != null and commander.target_region_id == battle_definition.withdrawal_region_id:
		return 80.0
	match posture:
		CommanderState.Posture.CAUTIOUS:
			return 192.0
		CommanderState.Posture.AGGRESSIVE:
			return 72.0
		CommanderState.Posture.HOLD:
			return 224.0
		CommanderState.Posture.DISENGAGE:
			return 128.0
	return 128.0


func _commander_disengage_position(commander: CommanderState) -> Vector2:
	var base_position := _faction_base_position(commander.faction_id)
	var inward_heading := (_battlefield_bounds().get_center() - base_position).normalized()
	if inward_heading.is_zero_approx():
		return base_position
	var base_cell := logic_grid.world_to_cell(base_position)
	var candidates: Array[Vector2] = []
	for y_offset in range(-20, 21):
		for x_offset in range(-20, 21):
			var cell := base_cell + Vector2i(x_offset, y_offset)
			if logic_grid.is_in_bounds(cell):
				candidates.append(logic_grid.cell_to_world(cell))
	candidates.sort_custom(func(first: Vector2, second: Vector2) -> bool:
		var first_offset := first - base_position
		var second_offset := second - base_position
		var first_score := first_offset.length() - first_offset.dot(inward_heading) * 0.35
		var second_score := second_offset.length() - second_offset.dot(inward_heading) * 0.35
		return first_score < second_score or (is_equal_approx(first_score, second_score) and (first.y < second.y or first.y == second.y and first.x < second.x))
	)
	for candidate in candidates:
		var supports_all_deployed_cards := true
		for unit_card_id in commander.subordinate_unit_card_ids:
			var unit_card := unit_cards.get(unit_card_id) as UnitCardState
			if unit_card == null or unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or not formations.has(unit_card.formation_id):
				continue
			if not _formation_can_deploy_at(formations[unit_card.formation_id] as FormationState, candidate):
				supports_all_deployed_cards = false
				break
		if supports_all_deployed_cards:
			return candidate
	return base_position


func _formation_can_deploy_at(
	formation: FormationState,
	destination: Vector2,
	planned_route: PackedVector2Array = PackedVector2Array()
) -> bool:
	if not _battlefield_bounds().has_point(destination):
		return false
	var route := _build_task_planned_route(formation.anchor_position, destination, planned_route)
	if route.is_empty():
		return false
	var tangent := Vector2.RIGHT
	if route.size() >= 2:
		tangent = (route[-1] - route[-2]).normalized()
	var lateral := Vector2(-tangent.y, tangent.x)
	for slot_id in range(formation.member_entity_ids.size()):
		var offset := formation.get_wide_offset(slot_id)
		var slot_position := destination + tangent * offset.x + lateral * offset.y
		if not _battlefield_bounds().has_point(slot_position) or not logic_grid.is_world_position_walkable(slot_position):
			return false
	return true


func find_formation_deployment_position(
	formation: FormationState,
	desired_position: Vector2,
	search_radius: float,
	planned_route: PackedVector2Array = PackedVector2Array()
) -> Vector2:
	if _formation_can_deploy_at(formation, desired_position, planned_route):
		return desired_position
	var candidates: Array[Vector2] = []
	var center_cell := logic_grid.world_to_cell(desired_position)
	var cell_radius := maxi(1, ceili(search_radius / LogicGrid.CELL_SIZE))
	for y_offset in range(-cell_radius, cell_radius + 1):
		for x_offset in range(-cell_radius, cell_radius + 1):
			var cell := center_cell + Vector2i(x_offset, y_offset)
			if not logic_grid.is_in_bounds(cell) or logic_grid.is_blocked(cell):
				continue
			var candidate := logic_grid.cell_to_world(cell)
			if candidate.distance_to(desired_position) <= search_radius:
				candidates.append(candidate)
	candidates.sort_custom(func(first: Vector2, second: Vector2) -> bool:
		var first_distance := first.distance_squared_to(desired_position)
		var second_distance := second.distance_squared_to(desired_position)
		return first_distance < second_distance or (is_equal_approx(first_distance, second_distance) and (first.y < second.y or first.y == second.y and first.x < second.x))
	)
	for candidate in candidates:
		if _formation_can_deploy_at(formation, candidate, planned_route):
			return candidate
	return Vector2(INF, INF)


func is_cautious_commander_agent(agent_id: int) -> bool:
	for commander_variant in commanders.values():
		var commander := commander_variant as CommanderState
		if commander.agent_id == agent_id:
			return commander.posture == CommanderState.Posture.CAUTIOUS or (_commander_effect(commander, DoctrineActionDefinition.Kind.CAUTIOUS_RECON) != null)
	return false


func commander_agent_has_doctrine(agent_id: int, doctrine_id: StringName) -> bool:
	for commander_variant in commanders.values():
		var commander := commander_variant as CommanderState
		if commander.agent_id == agent_id:
			return commander.has_doctrine(doctrine_id)
	return false


func _update_commander_behavior_feedback() -> void:
	for commander_variant in commanders.values():
		var commander := commander_variant as CommanderState
		_update_commander_outlook(commander)
		var control_feedback := _commander_control_feedback(commander)
		if not control_feedback.is_empty():
			commander.set_behavior(control_feedback[0], control_feedback[1], current_tick)
			continue
		var selected_task := _select_commander_feedback_task(commander)
		if selected_task == null:
			var has_deployed_card := false
			for unit_card_id in commander.subordinate_unit_card_ids:
				var unit_card := unit_cards.get(unit_card_id) as UnitCardState
				has_deployed_card = has_deployed_card or (unit_card != null and unit_card.deployment_state == UnitCardState.DeploymentState.DEPLOYED)
			commander.set_behavior(
				&"COMMANDER_BEHAVIOR_STANDING_BY",
				&"COMMANDER_REASON_NO_ACTIVE_TASK" if has_deployed_card else &"COMMANDER_REASON_FORCE_IN_RESERVE",
				current_tick
			)
			continue
		_apply_task_feedback_to_commander(commander, selected_task)


func _update_commander_outlook(commander: CommanderState) -> void:
	var active_tasks: Array[TaskState] = []
	for task_id in commander.current_task_ids:
		var task := tasks.get(task_id) as TaskState
		if task != null and task.lifecycle not in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
			active_tasks.append(task)
	var has_player_control := false
	var has_returning_card := false
	var active_strength := 0
	var authorized_strength := 0
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := unit_cards.get(unit_card_id) as UnitCardState
		if unit_card == null:
			continue
		authorized_strength += unit_card.definition.authorized_strength
		has_returning_card = has_returning_card or unit_card.control_state == UnitCardState.ControlState.RETURNING
		has_player_control = has_player_control or unit_card.control_state in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.PLAYER_CONTROLLED]
		for entity_id in unit_card.member_entity_ids:
			var unit := units.get(entity_id) as UnitState
			if unit != null and unit.enabled:
				active_strength += 1

	commander.estimated_arrival_min_ticks = -1
	commander.estimated_arrival_max_ticks = -1
	if not active_tasks.is_empty() and not has_player_control and not has_returning_card:
		var eta_values: Array[int] = []
		var has_unknown_eta := false
		for task in active_tasks:
			var eta_ticks := _estimate_commander_task_arrival_ticks(task)
			if eta_ticks < 0:
				has_unknown_eta = true
			else:
				eta_values.append(eta_ticks)
		if not has_unknown_eta and not eta_values.is_empty():
			eta_values.sort()
			commander.estimated_arrival_min_ticks = eta_values[0]
			commander.estimated_arrival_max_ticks = eta_values[-1]

	if has_returning_card or has_player_control:
		commander.exit_condition_key = &"COMMANDER_EXIT_RETURN_CARD"
	elif active_tasks.is_empty():
		commander.exit_condition_key = &"COMMANDER_EXIT_AWAIT_ORDER"
	elif commander.posture == CommanderState.Posture.DISENGAGE:
		commander.exit_condition_key = &"COMMANDER_EXIT_SAFE_RALLY"
	elif commander.posture == CommanderState.Posture.HOLD:
		commander.exit_condition_key = &"COMMANDER_EXIT_HOLD_OR_REORDER"
	elif commander.posture == CommanderState.Posture.CAUTIOUS or (_commander_effect(commander, DoctrineActionDefinition.Kind.CAUTIOUS_RECON) != null):
		commander.exit_condition_key = &"COMMANDER_EXIT_CONTACT_OR_REORDER"
	else:
		commander.exit_condition_key = &"COMMANDER_EXIT_OBJECTIVE_OR_REORDER"

	if active_strength <= 0:
		commander.risk_key = &"COMMANDER_RISK_UNKNOWN"
		commander.risk_reason_key = &"COMMANDER_RISK_REASON_FORCE_IN_RESERVE"
		return
	if authorized_strength > 0 and active_strength * 2 < authorized_strength:
		commander.risk_key = &"COMMANDER_RISK_HIGH"
		commander.risk_reason_key = &"COMMANDER_RISK_REASON_FORCE_DEPLETED"
		return
	var estimate := _commander_hostile_estimate(commander)
	if bool(estimate.get("conflicted", false)) and int(estimate.get("visible_count", 0)) == 0:
		commander.risk_key = &"COMMANDER_RISK_UNKNOWN"
		commander.risk_reason_key = &"COMMANDER_RISK_REASON_CONFLICTING_INTEL"
		return
	if not bool(estimate.get("reliable", false)):
		var region := strategic_regions.get(commander.target_region_id) as StrategicRegionState
		if region != null and region.controller_faction_id == commander.faction_id and not region.contested:
			commander.risk_key = &"COMMANDER_RISK_LOW"
			commander.risk_reason_key = &"COMMANDER_RISK_REASON_AREA_CONTROLLED"
		else:
			commander.risk_key = &"COMMANDER_RISK_UNKNOWN"
			commander.risk_reason_key = &"COMMANDER_RISK_REASON_NO_RELIABLE_INTEL"
		return
	var hostile_estimate := int(estimate.get("hostile_count", 0))
	if hostile_estimate <= 0:
		commander.risk_key = &"COMMANDER_RISK_LOW"
		commander.risk_reason_key = &"COMMANDER_RISK_REASON_AREA_CONFIRMED_CLEAR"
	elif hostile_estimate >= active_strength:
		commander.risk_key = &"COMMANDER_RISK_HIGH"
		commander.risk_reason_key = &"COMMANDER_RISK_REASON_CONTACT_OUTNUMBERED"
	elif hostile_estimate * 2 >= active_strength:
		commander.risk_key = &"COMMANDER_RISK_ELEVATED"
		commander.risk_reason_key = &"COMMANDER_RISK_REASON_CONTACT_PARITY"
	else:
		commander.risk_key = &"COMMANDER_RISK_LOW"
		commander.risk_reason_key = &"COMMANDER_RISK_REASON_CONTACT_ADVANTAGE"


func _estimate_commander_task_arrival_ticks(task: TaskState) -> int:
	if task.lifecycle in [TaskState.Lifecycle.BLOCKED, TaskState.Lifecycle.PAUSED]:
		return -1
	if task.phase in [TaskState.Phase.ENGAGING, TaskState.Phase.SCOUTING, TaskState.Phase.HOLDING]:
		return 0
	if task.requires_observed_contact and not _faction_has_visible_hostile(task.faction_id):
		return -1
	var formation := formations.get(task.formation_id) as FormationState
	if formation == null:
		return -1
	var using_formation_route := formation.is_moving and not formation.path.is_empty()
	var route := formation.path if using_formation_route else task.route
	var route_index := formation.path_index if using_formation_route else 0
	var cursor := formation.anchor_position
	var remaining_distance := 0.0
	for index in range(clampi(route_index, 0, route.size()), route.size()):
		remaining_distance += cursor.distance_to(route[index])
		cursor = route[index]
	if route.is_empty():
		remaining_distance = formation.anchor_position.distance_to(task.target_position)
	remaining_distance = maxf(0.0, remaining_distance - task.target_radius)
	var movement_ticks := ceili(remaining_distance / (FormationMovementSystem.ANCHOR_MOVE_SPEED * TICK_SECONDS))
	return maxi(0, task.activation_tick - current_tick) + movement_ticks


func _faction_has_visible_hostile(faction_id: int) -> bool:
	var knowledge := faction_knowledge.get(faction_id) as FactionKnowledge
	if knowledge == null:
		return false
	for contact_variant in knowledge.hostile_contacts.values():
		var contact := contact_variant as KnowledgeContact
		if contact.enabled and not contact.is_building and contact.faction_id != faction_id and knowledge.is_visible(logic_grid.world_to_cell(contact.position)):
			return true
	return false


func _commander_hostile_estimate(commander: CommanderState) -> Dictionary:
	var target_radius := 320.0
	var target_region := strategic_regions.get(commander.target_region_id) as StrategicRegionState
	if target_region != null:
		target_radius = target_region.radius + 64.0
	var known_count := 0
	var visible_count := 0
	var knowledge := faction_knowledge.get(commander.faction_id) as FactionKnowledge
	if knowledge != null:
		for contact_variant in knowledge.hostile_contacts.values():
			var contact := contact_variant as KnowledgeContact
			if not contact.enabled or contact.is_building or contact.faction_id == commander.faction_id or contact.position.distance_to(commander.target_position) > target_radius:
				continue
			known_count += 1
			if knowledge.is_visible(logic_grid.world_to_cell(contact.position)):
				visible_count += 1
	var reported_count := 0
	var has_report := false
	var conflicted := false
	if not commander.target_region_id.is_empty():
		for report in intel_reports:
			if report.faction_id != commander.faction_id or report.region_id != commander.target_region_id or report.superseded or current_tick - report.observed_tick > 300:
				continue
			conflicted = conflicted or report.contradictory
			if report.has_estimate:
				has_report = true
				reported_count = maxi(reported_count, report.estimated_max)
	return {
		"hostile_count": maxi(known_count, reported_count),
		"visible_count": visible_count,
		"reliable": known_count > 0 or has_report,
		"conflicted": conflicted,
	}


func _commander_control_feedback(commander: CommanderState) -> Array[StringName]:
	var has_player_control := false
	var feedback: Array[StringName] = []
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := unit_cards.get(unit_card_id) as UnitCardState
		if unit_card == null:
			continue
		if unit_card.control_state == UnitCardState.ControlState.RETURNING:
			feedback.assign([&"COMMANDER_BEHAVIOR_RETURNING", &"COMMANDER_REASON_CARD_RETURNING"])
			return feedback
		has_player_control = has_player_control or unit_card.control_state in [
			UnitCardState.ControlState.PLAYER_OVERRIDDEN,
			UnitCardState.ControlState.PLAYER_CONTROLLED,
		]
	if has_player_control:
		feedback.assign([&"COMMANDER_BEHAVIOR_COORDINATING", &"COMMANDER_REASON_CARD_PLAYER_CONTROLLED"])
	return feedback


func _select_commander_feedback_task(commander: CommanderState) -> TaskState:
	var selected: TaskState
	var selected_score := -1
	for task_id in commander.current_task_ids:
		var task := tasks.get(task_id) as TaskState
		if task == null or task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
			continue
		var score := _commander_task_feedback_score(task)
		if score > selected_score or score == selected_score and (selected == null or task.task_id < selected.task_id):
			selected = task
			selected_score = score
	return selected


func _commander_task_feedback_score(task: TaskState) -> int:
	if task.lifecycle == TaskState.Lifecycle.BLOCKED:
		return 100
	if task.lifecycle == TaskState.Lifecycle.PAUSED:
		return 95
	match task.phase:
		TaskState.Phase.RETREATING, TaskState.Phase.EVADING:
			return 90
		TaskState.Phase.ENGAGING:
			return 80
		TaskState.Phase.PREPARING:
			return 70
		TaskState.Phase.MUSTERING, TaskState.Phase.ADVANCING, TaskState.Phase.RETURNING:
			return 60
		TaskState.Phase.SCOUTING, TaskState.Phase.HOLDING:
			return 50
	return 10


func _apply_task_feedback_to_commander(commander: CommanderState, task: TaskState) -> void:
	if task.lifecycle == TaskState.Lifecycle.BLOCKED:
		commander.set_behavior(&"COMMANDER_BEHAVIOR_BLOCKED", _commander_blocked_reason_key(task.blocked_reason), current_tick)
		return
	if task.lifecycle == TaskState.Lifecycle.PAUSED:
		commander.set_behavior(&"COMMANDER_BEHAVIOR_STANDING_BY", &"COMMANDER_REASON_TASK_PAUSED", current_tick)
		return
	if commander.has_doctrine(&"fighting_withdrawal") and battle_definition != null and commander.target_region_id == battle_definition.withdrawal_region_id:
		commander.set_behavior(&"COMMANDER_BEHAVIOR_DISENGAGING", &"COMMANDER_REASON_FIGHTING_WITHDRAWAL", current_tick)
		return
	if task.phase == TaskState.Phase.PREPARING:
		if task.requires_observed_contact:
			commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", &"COMMANDER_REASON_FIRE_PREPARATION_VISION", current_tick)
		elif commander.has_doctrine(&"rapid_bridging") and _task_has_role(task, &"UNIT_CARD_ROLE_ENGINEERING"):
			commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", &"COMMANDER_REASON_RAPID_BRIDGING_AXIS", current_tick)
		elif current_tick < task.activation_tick and commander.has_doctrine(&"overwatch_lattice") and _task_has_role(task, &"UNIT_CARD_ROLE_FIREPOWER"):
			commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", &"COMMANDER_REASON_OVERWATCH_LATTICE_STAGING", current_tick)
		elif current_tick < task.activation_tick and task.doctrine_effect != null and task.doctrine_effect.applied:
			commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", task.doctrine_effect.waiting_reason_key, current_tick)
		elif task.has_staged_target and (_commander_effect(commander, DoctrineActionDefinition.Kind.CAUTIOUS_RECON) != null):
			commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", &"COMMANDER_REASON_COVERT_SEARCH_STAGING", current_tick)
		else:
			commander.set_behavior(&"COMMANDER_BEHAVIOR_PREPARING", &"COMMANDER_REASON_OBJECTIVE_COORDINATION", current_tick)
		return
	match task.phase:
		TaskState.Phase.ENGAGING:
			commander.set_behavior(&"COMMANDER_BEHAVIOR_ENGAGING", &"COMMANDER_REASON_MUTUAL_SUPPORT" if commander.has_doctrine(&"mutual_support") and task.reinforcement_committed else &"COMMANDER_REASON_CONTACT_IN_OBJECTIVE", current_tick)
		TaskState.Phase.RETREATING:
			commander.set_behavior(&"COMMANDER_BEHAVIOR_DISENGAGING", &"COMMANDER_REASON_LOSS_THRESHOLD", current_tick)
		TaskState.Phase.EVADING:
			commander.set_behavior(&"COMMANDER_BEHAVIOR_EVADING", &"COMMANDER_REASON_ENCOUNTER_DISENGAGEMENT" if commander.has_doctrine(&"encounter_disengagement") else &"COMMANDER_REASON_CAUTIOUS_AVOIDS_DISADVANTAGE", current_tick)
		TaskState.Phase.SCOUTING:
			commander.set_behavior(
				&"COMMANDER_BEHAVIOR_OBSERVING",
				&"COMMANDER_REASON_COVERT_SEARCH_OBSERVATION" if (_commander_effect(commander, DoctrineActionDefinition.Kind.CAUTIOUS_RECON) != null) else &"COMMANDER_REASON_RECON_OBSERVATION",
				current_tick
			)
		TaskState.Phase.HOLDING:
			commander.set_behavior(&"COMMANDER_BEHAVIOR_HOLDING", &"COMMANDER_REASON_ELASTIC_DEFENSE" if commander.has_doctrine(&"elastic_defense") else &"COMMANDER_REASON_RALLY_REORGANIZATION" if commander.has_doctrine(&"rally_reorganization") else _commander_posture_reason_key(commander.posture), current_tick)
		TaskState.Phase.RETURNING:
			commander.set_behavior(&"COMMANDER_BEHAVIOR_RETURNING", _commander_posture_reason_key(commander.posture), current_tick)
		TaskState.Phase.MUSTERING, TaskState.Phase.ADVANCING:
			commander.set_behavior(
				&"COMMANDER_BEHAVIOR_DISENGAGING" if commander.posture == CommanderState.Posture.DISENGAGE else &"COMMANDER_BEHAVIOR_ADVANCING",
				_commander_posture_reason_key(commander.posture),
				current_tick
			)
		_:
			commander.set_behavior(&"COMMANDER_BEHAVIOR_STANDING_BY", &"COMMANDER_REASON_OBJECTIVE_COORDINATION", current_tick)


func _commander_posture_reason_key(posture: CommanderState.Posture) -> StringName:
	return StringName("COMMANDER_REASON_POSTURE_%s" % CommanderState.Posture.keys()[posture])


func _commander_doctrine_reason_key(doctrine_id: StringName) -> StringName:
	var definition := doctrine_definitions.get(doctrine_id) as DoctrineDefinition
	if definition != null and not definition.effects.is_empty():
		return definition.effects[0].reason.waiting_reason_key
	match doctrine_id:
		&"rapid_bridging":
			return &"COMMANDER_REASON_RAPID_BRIDGING_AXIS"
		&"overwatch_lattice":
			return &"COMMANDER_REASON_OVERWATCH_LATTICE_STAGING"
		&"elastic_defense":
			return &"COMMANDER_REASON_ELASTIC_DEFENSE"
		&"encounter_disengagement":
			return &"COMMANDER_REASON_ENCOUNTER_DISENGAGEMENT"
		&"fighting_withdrawal":
			return &"COMMANDER_REASON_FIGHTING_WITHDRAWAL"
		&"reserve_commitment":
			return &"COMMANDER_REASON_RESERVE_COMMITMENT"
		&"mutual_support":
			return &"COMMANDER_REASON_MUTUAL_SUPPORT"
		&"rally_reorganization":
			return &"COMMANDER_REASON_RALLY_REORGANIZATION"
	return &"COMMANDER_REASON_OBJECTIVE_COORDINATION"


func _task_has_role(task: TaskState, role_key: StringName) -> bool:
	var unit_card := unit_cards.get(task.unit_card_id) as UnitCardState
	return unit_card != null and unit_card.definition != null and unit_card.definition.role_key == role_key


func _commander_blocked_reason_key(reason: TaskState.BlockedReason) -> StringName:
	return StringName("COMMANDER_REASON_BLOCKED_%s" % TaskState.BlockedReason.keys()[reason])


func _begin_unit_card_takeover(unit_card: UnitCardState, command: GameCommand) -> void:
	if unit_card.control_state == UnitCardState.ControlState.RETURNING:
		return
	var original_task_id := unit_card.assigned_task_id
	var original_agent_id := unit_card.assigned_agent_id
	for entity_id in unit_card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit == null or not unit.enabled:
			continue
		if original_task_id == 0 and unit.assigned_task_id != 0:
			original_task_id = unit.assigned_task_id
			original_agent_id = unit.assigned_agent_id
	unit_card.return_task_id = original_task_id
	unit_card.return_formation_id = unit_card.formation_id
	unit_card.assigned_task_id = original_task_id
	unit_card.assigned_agent_id = original_agent_id
	unit_card.takeover_reason = command.get_class()
	unit_card.control_state = UnitCardState.ControlState.PLAYER_OVERRIDDEN if original_task_id != 0 else UnitCardState.ControlState.PLAYER_CONTROLLED
	for entity_id in unit_card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			_begin_player_takeover(unit, command, true)
	events.append(SimulationEvent.new(
		current_tick, SimulationEvent.Kind.UNIT_CONTROL_CHANGED, 0,
		"UNIT_CARD_%s;%s;task=%d" % [unit_card.definition.definition_id, UnitCardState.ControlState.keys()[unit_card.control_state], unit_card.return_task_id]
	))


func _unit_card_for_formation(formation_id: int) -> UnitCardState:
	for card_variant in unit_cards.values():
		var unit_card := card_variant as UnitCardState
		if unit_card.formation_id == formation_id and unit_card.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
			return unit_card
	return null


func _apply_unit_card_control(command: UnitCardControlCommand) -> void:
	var unit_card := unit_cards[command.unit_card_id] as UnitCardState
	match command.action:
		UnitCardControlCommand.Action.TAKEOVER:
			_begin_unit_card_takeover(unit_card, command)
			if formations.has(unit_card.formation_id):
				var formation := formations[unit_card.formation_id] as FormationState
				_apply_stop(StopCommand.new(allocate_command_id(), command.issuer_id, GameCommand.IssuerKind.PLAYER, current_tick, formation.leader_entity_id, formation.formation_id))
		UnitCardControlCommand.Action.RETURN_TO_COMMANDER:
			_return_card_to_commander(unit_card)
		UnitCardControlCommand.Action.STAY_MANUAL:
			unit_card.control_state = UnitCardState.ControlState.PLAYER_CONTROLLED
			unit_card.assigned_agent_id = 0
			unit_card.assigned_task_id = 0
			unit_card.return_task_id = 0
			unit_card.return_formation_id = 0
			for entity_id in unit_card.member_entity_ids:
				var unit := units.get(entity_id) as UnitState
				if unit == null or not unit.enabled:
					continue
				unit.control_state = UnitState.ControlState.PLAYER_CONTROLLED
				unit.assigned_agent_id = 0
				unit.assigned_task_id = 0
				unit.return_task_id = 0
				unit.rejoin_pending = false
	events.append(SimulationEvent.new(
		current_tick, SimulationEvent.Kind.UNIT_CONTROL_CHANGED, 0,
		"UNIT_CARD_%s;%s" % [unit_card.definition.definition_id, UnitCardState.ControlState.keys()[unit_card.control_state]]
	))


func _release_card_for_commander(card: UnitCardState, reason: String) -> bool:
	if card.control_state not in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.PLAYER_CONTROLLED, UnitCardState.ControlState.RETURNING]:
		return false
	card.control_state = UnitCardState.ControlState.UNASSIGNED
	card.return_task_id = 0
	card.return_formation_id = 0
	card.takeover_reason = ""
	var formation := formations.get(card.formation_id) as FormationState
	if formation != null:
		_apply_stop(StopCommand.new(allocate_command_id(), card.faction_id, GameCommand.IssuerKind.AGENT, current_tick, formation.leader_entity_id, formation.formation_id))
	for entity_id in card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit == null or not unit.enabled:
			continue
		unit.rejoin_pending = false
		unit.return_task_id = 0
		unit.takeover_reason = ""
		unit.control_state = UnitState.ControlState.UNASSIGNED
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_CONTROL_CHANGED, 0, "UNIT_CARD_%s;AI_HANDOFF;reason=%s" % [card.definition.definition_id, reason]))
	return true


func _return_card_to_commander(card: UnitCardState) -> void:
	var commander := commanders[card.commander_definition_id] as CommanderState
	var previous_task := tasks.get(card.return_task_id) as TaskState
	var valid_previous := previous_task != null and previous_task.unit_card_id == card.definition.definition_id and previous_task.agent_id == commander.agent_id and previous_task.lifecycle not in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]
	if valid_previous and card.return_formation_id == card.formation_id and formations.has(card.return_formation_id):
		card.control_state = UnitCardState.ControlState.RETURNING
		var reachable := true
		for entity_id in card.member_entity_ids:
			var unit := units.get(entity_id) as UnitState
			if unit != null and unit.enabled:
				_start_rejoin(unit, card.return_formation_id, card.return_task_id)
				reachable = reachable and unit.rejoin_pending
		if reachable:
			return
	_release_card_for_commander(card, "PLAYER_RETURN")
	var deployed_count := 0
	for card_id in commander.subordinate_unit_card_ids:
		var subordinate := unit_cards.get(card_id) as UnitCardState
		if subordinate != null and subordinate.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
			deployed_count += 1
	var target := _commander_card_target(commander, card, deployed_count, _deployed_unit_card_index(commander, card.definition.definition_id), commander.target_position, formations.get(card.formation_id) as FormationState)
	var route := commander.planned_route
	if commander.current_task_ids.is_empty() and commander.active_intent_id.is_empty():
		target = (formations[card.formation_id] as FormationState).anchor_position
		route = PackedVector2Array()
	var task := _assign_unit_card_task(commander, card, target, route)
	var task_ids: Array[int] = []
	for task_id in commander.current_task_ids:
		var existing := tasks.get(task_id) as TaskState
		if existing != null and existing.unit_card_id != card.definition.definition_id:
			task_ids.append(task_id)
	if task != null:
		task_ids.append(task.task_id)
	commander.set_task_ids(task_ids)


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
	var completed_task_ids: Dictionary = {}
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
			unit.assigned_task_id = task.task_id
			unit.assigned_agent_id = task.agent_id
			unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
			completed_task_ids[task.task_id] = true
		else:
			unit.control_state = UnitState.ControlState.UNASSIGNED
		unit.return_task_id = 0
		if unit.definition_id == &"missile_vehicle" and mission_state.missile_taken_over:
			mission_state.missile_returned = true
			mission_state.update_completed(current_tick)
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_REJOIN_COMPLETED, unit.entity_id, "formation=%d" % unit.formation_id))
	for task_id_variant in completed_task_ids:
		var task_id := int(task_id_variant)
		if _has_pending_task_return(task_id):
			continue
		var task := tasks[task_id] as TaskState
		task.set_lifecycle(TaskState.Lifecycle.EXECUTING, current_tick)
		if task.kind != TaskState.Kind.FORMATION_MOVE_TEST:
			task.set_phase(TaskState.Phase.PREPARING, current_tick, "Unit card returned; task resumed")
		else:
			for agent in agents:
				if agent.task_id == task.task_id:
					agent.command_issued = false
	_refresh_unit_card_control_states()


func _has_pending_task_return(task_id: int) -> bool:
	for unit_variant in units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.return_task_id == task_id and unit.control_state == UnitState.ControlState.TEMPORARILY_OVERRIDDEN:
			return true
	return false


func _refresh_unit_card_control_states() -> void:
	for card_variant in unit_cards.values():
		var unit_card := card_variant as UnitCardState
		if unit_card.control_state != UnitCardState.ControlState.RETURNING:
			continue
		var still_returning := false
		var all_agent_assigned := true
		for entity_id in unit_card.member_entity_ids:
			var unit := units.get(entity_id) as UnitState
			if unit == null or not unit.enabled:
				continue
			still_returning = still_returning or unit.rejoin_pending
			all_agent_assigned = all_agent_assigned and unit.control_state == UnitState.ControlState.AGENT_ASSIGNED
		if still_returning:
			continue
		unit_card.control_state = UnitCardState.ControlState.AGENT_ASSIGNED if all_agent_assigned and unit_card.return_task_id != 0 else UnitCardState.ControlState.UNASSIGNED
		unit_card.assigned_task_id = unit_card.return_task_id if unit_card.control_state == UnitCardState.ControlState.AGENT_ASSIGNED else 0
		if unit_card.control_state != UnitCardState.ControlState.AGENT_ASSIGNED:
			unit_card.assigned_agent_id = 0
		unit_card.return_task_id = 0
		unit_card.return_formation_id = 0
		unit_card.takeover_reason = ""


func _apply_command(command: GameCommand) -> void:
	if command is StaffPlanApprovalCommand:
		staff_plan_system.apply(self, command as StaffPlanApprovalCommand)
		return
	if _is_direct_player_order(command) or command is UnitCardControlCommand or command is CommanderOrderCommand:
		tactical_ability_system.cancel_for_order(self, command)
	if command is TacticalAbilityCommand:
		tactical_ability_system.start(self, command as TacticalAbilityCommand)
		return
	if command is EquipDoctrineCommand:
		_apply_equip_doctrine(command as EquipDoctrineCommand)
		return
	if command is CommanderOrderCommand:
		_apply_commander_order(command as CommanderOrderCommand)
		return
	if command is UnitCardControlCommand:
		_apply_unit_card_control(command as UnitCardControlCommand)
		return
	if command is SupportOrderCommand:
		_apply_support_order(command as SupportOrderCommand)
		return
	if command is DeployUnitCardCommand:
		_apply_unit_card_deployment(command as DeployUnitCardCommand)
		return
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
		if factory.production_definition_id.is_empty():
			_start_building_production(factory, definition)
		else:
			factory.production_queue.append(definition.definition_id)
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.PRODUCTION_QUEUED, factory.entity_id, "definition=%s;position=%d;cost=%d" % [definition.definition_id, factory.production_count() - 1, definition.production_cost]))
	elif command is CancelProductionCommand:
		_apply_cancel_production(command as CancelProductionCommand)
	elif command is SetRallyPointCommand:
		var rally := command as SetRallyPointCommand
		var rally_building := buildings[rally.target_entity_id] as BuildingState
		rally_building.production_rally_position = rally.rally_position
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.RALLY_POINT_SET, rally_building.entity_id, "position=%.1f,%.1f" % [rally.rally_position.x, rally.rally_position.y]))
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
		var formation := formations.get(formation_command.formation_id) as FormationState
		if formation == null:
			return
		formation.order_kind = FormationState.OrderKind.ATTACK_MOVE if command is AttackMoveCommand else FormationState.OrderKind.MOVE
		formation.engagement_state = FormationState.EngagementState.NONE
		formation.order_destination = formation_command.target_position
		formation.order_target_entity_id = 0
		formation.pursuit_target_cell = Vector2i(-1, -1)
		formation.target_position = formation_command.target_position
		formation.planned_route = formation_command.route_points.duplicate()
		formation.has_deployment_line = formation_command.has_deployment_line
		formation.deployment_line_start = formation_command.deployment_line_start
		formation.deployment_line_end = formation_command.deployment_line_end
		formation.path = _build_formation_route(formation.anchor_position, formation_command)
		formation.path_index = 1
		formation.is_moving = formation.path.size() > 1
		formation.clear_corridor_ticks = 0
		var initial_direction := Vector2.RIGHT
		if formation.path.size() > 1:
			initial_direction = formation.path[1] - formation.path[0]
		formation.reset_anchor_history(initial_direction)
		for entity_id in formation.member_entity_ids:
			var member := units.get(entity_id) as UnitState
			if member == null or not member.enabled:
				continue
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


func _build_formation_route(start_position: Vector2, command: FormationMoveCommand) -> PackedVector2Array:
	var destinations := command.route_points.duplicate()
	if destinations.is_empty() or not destinations[-1].is_equal_approx(command.target_position):
		destinations.append(command.target_position)
	var result := PackedVector2Array([start_position])
	var segment_start := start_position
	for destination in destinations:
		var segment := pathfinder.find_path(segment_start, destination)
		if segment.is_empty():
			return PackedVector2Array()
		for index in range(1, segment.size()):
			if result.is_empty() or not result[-1].is_equal_approx(segment[index]):
				result.append(segment[index])
		segment_start = destination
	return result


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
	building.production_rally_position = _default_production_rally_position(snapped_position)
	buildings[building.entity_id] = building
	_set_building_occupancy(building, true)
	_prepare_manual_worker(engineer)
	engineer.work_kind = UnitState.WorkKind.CONSTRUCT
	engineer.work_target_building_id = building.entity_id
	_start_unit_path_to_building(engineer, building)
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.BUILDING_PLACED, building.entity_id, "definition=%s;builder=%d;cost=%d" % [definition.definition_id, engineer.entity_id, definition.build_cost]))


func _start_building_production(building: BuildingState, definition: UnitDefinition) -> void:
	building.production_definition_id = definition.definition_id
	building.production_ticks_remaining = definition.production_ticks
	building.production_cost_paid = definition.production_cost
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.PRODUCTION_STARTED, building.entity_id, "definition=%s;cost=%d" % [definition.definition_id, definition.production_cost]))


func _default_production_rally_position(building_position: Vector2) -> Vector2:
	var outward_x := 1.0 if building_position.x < _battlefield_bounds().get_center().x else -1.0
	return building_position + Vector2(outward_x * LogicGrid.CELL_SIZE * 5.0, 0.0)


func _apply_cancel_production(command: CancelProductionCommand) -> void:
	var building := buildings[command.target_entity_id] as BuildingState
	var refund := 0
	var cancelled_definition: StringName
	if command.queue_index == 0:
		cancelled_definition = building.production_definition_id
		refund = floori(building.production_cost_paid * 0.75)
		building.production_definition_id = &""
		building.production_ticks_remaining = 0
		building.production_cost_paid = 0
		if not building.production_queue.is_empty():
			var next_definition_id: StringName = building.production_queue.pop_front()
			_start_building_production(building, UNIT_CATALOG.get_unit(next_definition_id))
	else:
		var waiting_index := command.queue_index - 1
		cancelled_definition = building.production_queue[waiting_index]
		var definition: UnitDefinition = UNIT_CATALOG.get_unit(cancelled_definition)
		refund = definition.production_cost if definition != null else 0
		building.production_queue.remove_at(waiting_index)
	(factions[building.faction_id] as FactionState).ore += refund
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.PRODUCTION_CANCELLED, building.entity_id, "definition=%s;refund=%d;index=%d" % [cancelled_definition, refund, command.queue_index]))


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
	_preempt_autonomous_tasks_for(command)
	if command.order_kind in [StrategicOrderCommand.OrderKind.DEFEND_AREA, StrategicOrderCommand.OrderKind.ATTACK_TARGET]:
		_detach_noncombat_members(command.formation_id)
	var resolved_formation_id := command.formation_id
	if command.order_kind in [StrategicOrderCommand.OrderKind.DEFEND_AREA, StrategicOrderCommand.OrderKind.ATTACK_TARGET, StrategicOrderCommand.OrderKind.SCOUT_AREA] and resolved_formation_id == 0:
		resolved_formation_id = _create_task_formation(command.participant_entity_ids)
	var participants: Array[int] = []
	var agent_id := command.agent_id if command.issuer_kind == GameCommand.IssuerKind.AGENT and command.agent_id != 0 else StrategicTaskSystem.BATTLEFIELD_AGENT_ID
	var kind := TaskState.Kind.DEFEND_AREA
	match command.order_kind:
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE:
			agent_id = command.agent_id if command.issuer_kind == GameCommand.IssuerKind.AGENT and command.agent_id != 0 else StrategicTaskSystem.INDUSTRIAL_AGENT_ID
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
	task.priority = command.strategic_priority if command.strategic_priority > 0 else _default_task_priority(kind)
	task.accepted_tick = current_tick
	task.requires_proactive_authorization = command.issuer_kind == GameCommand.IssuerKind.AGENT
	task.progress_target = 2 if kind == TaskState.Kind.DEVELOP_RESOURCE else (StrategicTaskSystem.SCOUT_OBSERVE_TICKS if kind == TaskState.Kind.SCOUT_AREA else StrategicTaskSystem.DEFEND_HOLD_TICKS)
	if kind == TaskState.Kind.DEVELOP_RESOURCE:
		task.baseline_value = (ore_fields[command.objective_entity_id] as OreFieldState).ore_remaining
		task.expected_unit_count = _count_friendly_definition(&"harvester")
	elif resolved_formation_id != 0:
		var formation := formations[resolved_formation_id] as FormationState
		task.route = pathfinder.find_path(formation.anchor_position, command.target_position)
		if kind == TaskState.Kind.SCOUT_AREA:
			task.last_progress_position = formation.anchor_position
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


func _preempt_autonomous_tasks_for(command: StrategicOrderCommand) -> void:
	if command.issuer_kind != GameCommand.IssuerKind.AGENT or command.strategic_priority <= 0:
		return
	var requested_participants := _strategic_command_participants(command)
	var task_ids := tasks.keys()
	task_ids.sort()
	for task_id in task_ids:
		var task := tasks[task_id] as TaskState
		if task.agent_id != command.agent_id or task.faction_id != command.issuer_id or not task.requires_proactive_authorization or not _is_open_task(task):
			continue
		var explicitly_replaced := command.replaces_task_id == task.task_id
		if (not explicitly_replaced and task.priority >= command.strategic_priority) or not _participant_ids_overlap(requested_participants, task.participant_entity_ids):
			continue
		task.set_lifecycle(TaskState.Lifecycle.CANCELLED, current_tick, TaskState.BlockedReason.NONE, "Replaced by a new autonomous battlefield decision")
		task.set_phase(TaskState.Phase.DONE, current_tick, "Replaced by a new autonomous battlefield decision")
		_stop_task_formation(task)
		release_task_participants(task)
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, task.task_id, "CANCELLED:preempted"))


func _strategic_command_participants(command: StrategicOrderCommand) -> Array[int]:
	var result: Array[int] = []
	if command.formation_id != 0 and formations.has(command.formation_id):
		if command.order_kind == StrategicOrderCommand.OrderKind.SCOUT_AREA:
			return _scout_participants(command.formation_id)
		return _combat_participants(command.formation_id)
	result.assign(command.participant_entity_ids)
	result.sort()
	return result


func _participant_ids_overlap(first: Array[int], second: Array[int]) -> bool:
	for entity_id in first:
		if second.has(entity_id):
			return true
	return false


func _default_task_priority(kind: TaskState.Kind) -> int:
	match kind:
		TaskState.Kind.ATTACK_TARGET:
			return AUTONOMY_PRIORITY_ATTACK
		TaskState.Kind.DEFEND_AREA:
			return AUTONOMY_PRIORITY_DEFEND
		TaskState.Kind.SCOUT_AREA:
			return AUTONOMY_PRIORITY_SCOUT
	return 0


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
	_apply_stop(StopCommand.new(allocate_command_id(), task.faction_id, GameCommand.IssuerKind.AGENT, current_tick, formation.leader_entity_id, formation.formation_id))


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
		formation.planned_route = PackedVector2Array()
		formation.has_deployment_line = false
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
		if not unit.enabled or not unit.can_attack or not unit.can_accept_attack_orders:
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
		unit.attack_is_retaliation = false
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
		unit.attack_is_retaliation = false
		return
	var target_id := unit.attack_target_entity_id
	unit.attack_target_entity_id = 0
	unit.attack_is_retaliation = false
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
		var interrupted_movement := formation.is_moving
		formation.is_moving = false
		formation.path = PackedVector2Array()
		formation.planned_route = PackedVector2Array()
		formation.has_deployment_line = false
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
		var previous_formation := formations[previous_formation_id] as FormationState
		previous_formation.remove_member(unit.entity_id)
		if previous_formation.member_entity_ids.is_empty():
			formations.erase(previous_formation_id)
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
		unit.armor = unit.base_armor
		_remove_unit_from_formation(unit)
		for task_variant in tasks.values():
			(task_variant as TaskState).remove_participant(entity_id)
		for knowledge_variant in faction_knowledge.values():
			(knowledge_variant as FactionKnowledge).hostile_contacts.erase(entity_id)
		units.erase(entity_id)


func _update_victory() -> void:
	_update_command_center_defeats()
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


func _update_command_center_defeats() -> void:
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
