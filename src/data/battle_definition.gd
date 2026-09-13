class_name BattleDefinition
extends Resource

@export var scenario_id: StringName
@export var display_name_key: StringName
@export var operation_number: int = 0
@export_file("*.tscn") var scene_path: String = ""
@export var selector_briefing_key: StringName
@export var selector_mechanics_key: StringName
@export var available_in_selector: bool = false
@export var battlefield_bounds := Rect2(Vector2.ZERO, Vector2(6144.0, 4096.0))
@export var time_limit_ticks: int = 4800
@export var base_supply_interval_ticks: int = 200
@export var region_settlement_interval_ticks: int = 300
@export var starting_supply: int = 5
@export var supply_capacity: int = 10
@export var population_capacity: int = 40
@export var deployment_radius: float = 384.0
@export var player_headquarters_position: Vector2
@export var enemy_headquarters_position: Vector2
@export var friendly_formation_ids: Array[int] = []
@export var friendly_spawn_positions: Array[Vector2] = []
@export var next_dynamic_unit_id: int = 1100
@export var next_dynamic_formation_id: int = 1
@export var enemy_offensive_followup_tick: int = 1800
@export var enemy_agent_id: int
@export var enemy_task_id: int
@export var commander_definitions: Array[CommanderDefinition] = []
@export var unit_card_definitions: Array[UnitCardDefinition] = []
@export var doctrine_definitions: Array[DoctrineDefinition] = []
@export var starting_card_count: int = 0
@export var commander_agent_ids: Dictionary = {}
@export var default_commander_by_unit_card: Dictionary = {}
@export var default_doctrine_by_commander: Dictionary = {}
@export var default_posture_by_commander: Dictionary = {}
@export var default_starting_unit_card_ids: Array[StringName] = []
@export var strategic_regions: Array[BattleRegionDefinition] = []
@export var initial_intel: Array[BattleIntelDefinition] = []
@export var enemy_formations: Array[BattleFormationDefinition] = []
@export var support_abilities: Array[BattleSupportDefinition] = []
@export var enemy_plans: Array[BattleEnemyPlanDefinition] = []
@export var enemy_reaction_rules: Array[BattleReactionRuleDefinition] = []
@export var navigation_blocked_rects: Array[Rect2i] = []
@export var engineering_routes: Array[BattleEngineeringRouteDefinition] = []
@export var contact_fade_after_ticks: int = 0
@export var contact_expire_after_ticks: int = 0
@export var escort_unit_card_id: StringName
@export var escort_destination_region_id: StringName
@export var escort_arrival_radius: float = 0.0
@export var escort_supply_capacity_bonus: int = 0
@export var escort_supply_reward: int = 0
@export var escort_region_supply_bonus: int = 0
@export var enemy_intercepts_escort: bool = false
@export var escort_intercept_delay_ticks: int = 0
@export var withdrawal_region_id: StringName
@export var withdrawal_arrival_radius: float = 0.0
@export var organization_max: float = 0.0
@export var organization_damage_factor: float = 0.0
@export var organization_member_loss: float = 0.0
@export var organization_recovery_per_tick: float = 0.0
@export var organization_recovery_delay_ticks: int = 0
@export var organization_recovery_region_id: StringName
@export var organization_recovery_radius: float = 0.0
@export var organization_recovery_region_bonus: float = 0.0
@export var organization_low_threshold: float = 0.0
@export var objective_set: BattleObjectiveSetDefinition


func validate(unit_catalog: UnitDefinitionCatalog = null) -> DataValidationResult:
	var result := DataValidationResult.new()
	_require_id(result, scenario_id, "battle.scenario_id")
	_require_id(result, display_name_key, "battle.display_name_key")
	if available_in_selector:
		if operation_number <= 0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "selectable battle operation_number must be positive")
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
			result.add(DataValidationResult.Reason.RESOURCE_NOT_FOUND, "selectable battle scene_path='%s'" % scene_path)
		_require_id(result, selector_briefing_key, "battle.selector_briefing_key")
		_require_id(result, selector_mechanics_key, "battle.selector_mechanics_key")
	if battlefield_bounds.size.x <= 0.0 or battlefield_bounds.size.y <= 0.0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "battlefield_bounds must have positive size")
	if time_limit_ticks <= 0 or base_supply_interval_ticks <= 0 or region_settlement_interval_ticks <= 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "battle timing values must be positive")
	if starting_supply < 0 or supply_capacity < starting_supply or population_capacity <= 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "battle faction capacities are invalid")
	if enemy_agent_id <= 0 or enemy_task_id <= 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "battle enemy Agent and task IDs must be positive")
	if friendly_formation_ids.size() != friendly_spawn_positions.size() or friendly_formation_ids.size() < starting_card_count:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "friendly formation slots must match spawn positions and starting card count")

	var region_ids := _collect_resource_ids(result, strategic_regions, &"region_id", "regions")
	var commander_ids := _collect_resource_ids(result, commander_definitions, &"definition_id", "commanders")
	var unit_card_ids := _collect_resource_ids(result, unit_card_definitions, &"definition_id", "unit_cards")
	var doctrine_ids := _collect_resource_ids(result, doctrine_definitions, &"definition_id", "doctrines")
	for index in range(doctrine_definitions.size()):
		var doctrine := doctrine_definitions[index]
		if doctrine != null:
			result.issues.append_array(doctrine.validate("battle '%s'.doctrines[%d] '%s'" % [scenario_id, index, doctrine.definition_id]).issues)
	var formation_ids: Dictionary = {}
	var formation_role_ids: Dictionary = {}
	var enemy_card_ids: Dictionary = {}
	for index in range(enemy_formations.size()):
		var formation := enemy_formations[index]
		if formation == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "enemy_formations[%d]" % index)
			continue
		if formation.formation_id <= 0 or formation_ids.has(formation.formation_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID if formation_ids.has(formation.formation_id) else DataValidationResult.Reason.INVALID_VALUE, "enemy_formations[%d].formation_id=%d" % [index, formation.formation_id])
		formation_ids[formation.formation_id] = true
		_require_id(result, formation.role_id, "enemy_formations[%d].role_id" % index)
		if not formation.role_id.is_empty():
			if formation_role_ids.has(formation.role_id):
				result.add(DataValidationResult.Reason.DUPLICATE_ID, "enemy formation role '%s'" % formation.role_id)
			formation_role_ids[formation.role_id] = true
		if formation.strength <= 0 or formation.first_entity_id <= 0 or formation.faction_id <= 0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "enemy_formations[%d] has invalid strength, entity, or faction" % index)
		if formation.agent_id != enemy_agent_id or formation.task_id != enemy_task_id:
			result.add(DataValidationResult.Reason.INVALID_REFERENCE, "enemy_formations[%d] must reference battle enemy Agent/task %d/%d" % [index, enemy_agent_id, enemy_task_id])
		if unit_catalog != null and unit_catalog.get_unit(formation.unit_definition_id) == null:
			result.add(DataValidationResult.Reason.INVALID_REFERENCE, "enemy_formations[%d].unit_definition_id='%s'" % [index, formation.unit_definition_id])
		var card := formation.unit_card_definition
		if card != null:
			_require_id(result, card.definition_id, "enemy formation card ID")
			if enemy_card_ids.has(card.definition_id) or unit_card_ids.has(card.definition_id):
				result.add(DataValidationResult.Reason.DUPLICATE_ID, "enemy card '%s' collides with another card" % card.definition_id)
			enemy_card_ids[card.definition_id] = true
			result.issues.append_array(UnitCardCompositionCompiler.validate(card, unit_catalog).issues)
			if formation.faction_id == 1 or card.unit_definition_id != formation.unit_definition_id or card.authorized_strength != formation.strength or not card.composition.is_empty():
				result.add(DataValidationResult.Reason.INVALID_VALUE, "enemy card must match its homogeneous hostile formation")
			if organization_max <= 0.0 or not card.enforce_organization_rules or card.tactical_ability != null or card.tactical_weapon_override != null:
				result.add(DataValidationResult.Reason.INVALID_VALUE, "enemy formation cards require organization constraints and no unsupported active ability")

	for region in strategic_regions:
		if region == null:
			continue
		if region.radius <= 0.0 or region.supply_per_settlement < 0 or region.support_cooldown_ticks < 0 or region.capture_ticks <= 0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "region '%s' has invalid radius, supply, cooldown, or capture time" % region.region_id)
		for adjacent_id in region.adjacent_region_ids:
			_require_reference(result, region_ids, adjacent_id, "region '%s' adjacency" % region.region_id)
	for intel in initial_intel:
		if intel == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "initial_intel")
			continue
		_require_reference(result, region_ids, intel.region_id, "intel region")
		if intel.estimated_min < 0 or intel.estimated_max < intel.estimated_min:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "intel estimate for '%s' is invalid" % intel.region_id)
	for commander in commander_definitions:
		if commander == null:
			continue
		for doctrine_id in commander.available_doctrine_ids:
			_require_reference(result, doctrine_ids, doctrine_id, "commander '%s' doctrine" % commander.definition_id)
	for card in unit_card_definitions:
		if card == null:
			continue
		_require_reference(result, commander_ids, card.commander_definition_id, "unit card '%s' commander" % card.definition_id)
		result.issues.append_array(UnitCardCompositionCompiler.validate(card, unit_catalog).issues)
		if card.tactical_ability != null:
			result.issues.append_array(card.tactical_ability.validate(unit_catalog).issues)
			var has_capability := false
			for entry in UnitCardCompositionCompiler.compile(card):
				has_capability = has_capability or entry.unit_definition_id == card.tactical_ability.required_unit_id
			if not has_capability or organization_max <= 0.0:
				result.add(DataValidationResult.Reason.INVALID_VALUE, "tactical card needs its capability member and organization rules")
		if card.tactical_weapon_override != null:
			result.issues.append_array(card.tactical_weapon_override.validate().issues)
			if card.tactical_ability == null or card.tactical_ability.kind != TacticalAbilityDefinition.Kind.SUPPRESS:
				result.add(DataValidationResult.Reason.INVALID_VALUE, "card weapon override requires a suppression capability")
			elif unit_catalog != null:
				var weapon_unit := unit_catalog.get_unit(card.tactical_ability.required_unit_id)
				if weapon_unit == null or not weapon_unit.can_attack or weapon_unit.combat == null or card.tactical_weapon_override.minimum_range >= weapon_unit.combat.attack_range:
					result.add(DataValidationResult.Reason.INVALID_VALUE, "card weapon override requires a compatible armed member and firing range")
		if card.enforce_organization_rules and organization_max <= 0.0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "card organization constraints require organization rules")
		if card.authorized_strength <= 0 or card.command_cost <= 0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "unit card '%s' has invalid strength or command cost" % card.definition_id)
	if starting_card_count <= 0 or starting_card_count > unit_card_ids.size():
		result.add(DataValidationResult.Reason.INVALID_VALUE, "starting_card_count is outside the unit card roster")
	if default_starting_unit_card_ids.size() != starting_card_count:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "default starting cards do not match starting_card_count")
	for commander_id in commander_ids:
		if int(commander_agent_ids.get(commander_id, 0)) <= 0:
			result.add(DataValidationResult.Reason.INVALID_REFERENCE, "commander '%s' agent ID" % commander_id)
		_require_reference(result, doctrine_ids, default_doctrine_by_commander.get(commander_id, &"") as StringName, "commander '%s' default doctrine" % commander_id)
		if not default_posture_by_commander.has(commander_id):
			result.add(DataValidationResult.Reason.INVALID_REFERENCE, "commander '%s' default posture" % commander_id)
	for unit_card_id in unit_card_ids:
		_require_reference(result, commander_ids, default_commander_by_unit_card.get(unit_card_id, &"") as StringName, "unit card '%s' default commander" % unit_card_id)
	for unit_card_id in default_starting_unit_card_ids:
		_require_reference(result, unit_card_ids, unit_card_id, "default starting card")

	_collect_resource_ids(result, support_abilities, &"support_id", "support_abilities")
	for support in support_abilities:
		if support != null and (support.supply_cost < 0 or support.duration_ticks < 0 or support.cooldown_ticks < 0 or support.damage < 0.0 or support.move_speed_multiplier <= 0.0 or support.health_restore < 0.0 or support.organization_restore < 0.0):
			result.add(DataValidationResult.Reason.INVALID_VALUE, "support '%s' has invalid cost or timing" % support.support_id)
	_collect_resource_ids(result, enemy_reaction_rules, &"rule_id", "enemy_reaction_rules")
	for rule in enemy_reaction_rules:
		if rule != null and (rule.priority < 0 or rule.delay_ticks < 0 or rule.commitment_ticks < 0):
			result.add(DataValidationResult.Reason.INVALID_VALUE, "reaction rule '%s' has invalid timing or priority" % rule.rule_id)
	_collect_resource_ids(result, engineering_routes, &"route_id", "engineering_routes")
	for rect in navigation_blocked_rects:
		if rect.size.x <= 0 or rect.size.y <= 0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "navigation obstacle rectangles must have positive size")
	for route in engineering_routes:
		if route == null:
			continue
		_require_id(result, route.display_name_key, "engineering route '%s' display_name_key" % route.route_id)
		_require_reference(result, region_ids, route.linked_region_id, "engineering route '%s' linked region" % route.route_id)
		if route.cleared_rects.is_empty():
			result.add(DataValidationResult.Reason.INVALID_VALUE, "engineering route '%s' must clear at least one cell" % route.route_id)
		for rect in route.cleared_rects:
			if rect.size.x <= 0 or rect.size.y <= 0:
				result.add(DataValidationResult.Reason.INVALID_VALUE, "engineering route '%s' has an invalid clear rectangle" % route.route_id)
	if contact_fade_after_ticks < 0 or contact_expire_after_ticks < 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "contact decay timings cannot be negative")
	if contact_expire_after_ticks > 0 and contact_expire_after_ticks <= contact_fade_after_ticks:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "contact expiry must occur after contact fade begins")
	if not escort_unit_card_id.is_empty():
		_require_reference(result, unit_card_ids, escort_unit_card_id, "escort unit card")
		_require_reference(result, region_ids, escort_destination_region_id, "escort destination region")
		if escort_arrival_radius <= 0.0 or escort_supply_capacity_bonus < 0 or escort_supply_reward < 0 or escort_region_supply_bonus < 0 or escort_intercept_delay_ticks < 0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "escort objective has invalid radius or supply rewards")
	elif not escort_destination_region_id.is_empty() or enemy_intercepts_escort:
		result.add(DataValidationResult.Reason.INVALID_REFERENCE, "escort rules require escort_unit_card_id")
	if not withdrawal_region_id.is_empty():
		_require_reference(result, region_ids, withdrawal_region_id, "withdrawal region")
		if withdrawal_arrival_radius <= 0.0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "withdrawal objective requires a positive arrival radius")
	elif withdrawal_arrival_radius != 0.0:
		result.add(DataValidationResult.Reason.INVALID_REFERENCE, "withdrawal radius requires withdrawal_region_id")
	if organization_max > 0.0:
		if organization_damage_factor < 0.0 or organization_member_loss < 0.0 or organization_recovery_per_tick < 0.0 \
			or organization_recovery_delay_ticks < 0 or organization_low_threshold <= 0.0 or organization_low_threshold >= organization_max:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "organization rules contain invalid thresholds or rates")
		_require_reference(result, region_ids, organization_recovery_region_id, "organization recovery region")
		if organization_recovery_radius <= 0.0 or organization_recovery_region_bonus < 0.0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, "organization recovery region requires a positive radius and non-negative bonus")
	elif not organization_recovery_region_id.is_empty() or organization_recovery_radius != 0.0 or organization_recovery_region_bonus != 0.0:
		result.add(DataValidationResult.Reason.INVALID_REFERENCE, "organization recovery region requires organization_max")
	if available_in_selector and objective_set == null:
		result.add(DataValidationResult.Reason.NULL_REFERENCE, "selectable battle requires objective_set")
	elif objective_set != null:
		for issue in objective_set.validate(self).issues:
			result.issues.append(issue.duplicate(true))
	_collect_resource_ids(result, enemy_plans, &"plan_id", "enemy_plans")
	for plan in enemy_plans:
		if plan == null:
			continue
		_require_reference(result, formation_role_ids, plan.assault_formation_role_id, "plan '%s' assault formation" % plan.plan_id)
		_require_reference(result, formation_role_ids, plan.probe_formation_role_id, "plan '%s' probe formation" % plan.plan_id)
		_require_reference(result, region_ids, plan.assault_target_region_id, "plan '%s' assault target" % plan.plan_id)
		_require_reference(result, region_ids, plan.probe_target_region_id, "plan '%s' probe target" % plan.plan_id)
		for route_region_id in plan.assault_route_region_ids:
			_require_reference(result, region_ids, route_region_id, "plan '%s' route" % plan.plan_id)
		if plan.followup_tick >= 0:
			_require_reference(result, formation_role_ids, plan.followup_formation_role_id, "plan '%s' followup formation" % plan.plan_id)
			_require_reference(result, region_ids, plan.followup_target_region_id, "plan '%s' followup target" % plan.plan_id)
	var allowed_commander_ids: Array[StringName] = []
	allowed_commander_ids.assign(commander_ids.keys())
	var allowed_unit_card_ids: Array[StringName] = []
	allowed_unit_card_ids.assign(unit_card_ids.keys())
	var default_plan := create_default_army_plan()
	for plan_error in default_plan.validation_errors(commander_dictionary(), unit_card_dictionary(), doctrine_dictionary(), allowed_commander_ids, allowed_unit_card_ids, starting_card_count):
		result.add(DataValidationResult.Reason.INVALID_VALUE, "default army plan: %s" % plan_error)
	return result


func commander_dictionary() -> Dictionary:
	return _resource_dictionary(commander_definitions, &"definition_id")


func unit_card_dictionary() -> Dictionary:
	return _resource_dictionary(unit_card_definitions, &"definition_id")


func doctrine_dictionary() -> Dictionary:
	return _resource_dictionary(doctrine_definitions, &"definition_id")


func region_dictionary() -> Dictionary:
	return _resource_dictionary(strategic_regions, &"region_id")


func support_dictionary() -> Dictionary:
	return _resource_dictionary(support_abilities, &"support_id")


func support_for_kind(support_kind: int) -> BattleSupportDefinition:
	for support in support_abilities:
		if support != null and support.support_kind == support_kind:
			return support
	return null


func enemy_plan_dictionary() -> Dictionary:
	return _resource_dictionary(enemy_plans, &"plan_id")


func engineering_route_dictionary() -> Dictionary:
	return _resource_dictionary(engineering_routes, &"route_id")


func enemy_formation_by_role(role_id: StringName) -> BattleFormationDefinition:
	for formation in enemy_formations:
		if formation != null and formation.role_id == role_id:
			return formation
	return null


func create_default_army_plan() -> ArmyPlan:
	var plan := ArmyPlan.new()
	plan.commander_by_unit_card = default_commander_by_unit_card.duplicate()
	plan.doctrine_by_commander = default_doctrine_by_commander.duplicate()
	plan.posture_by_commander = default_posture_by_commander.duplicate()
	plan.starting_unit_card_ids.assign(default_starting_unit_card_ids)
	return plan


func _collect_resource_ids(result: DataValidationResult, resources: Array, property: StringName, label: String) -> Dictionary:
	var ids: Dictionary = {}
	for index in range(resources.size()):
		var resource := resources[index] as Resource
		if resource == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "%s[%d]" % [label, index])
			continue
		var identifier := resource.get(property) as StringName
		_require_id(result, identifier, "%s[%d].%s" % [label, index, property])
		if identifier.is_empty():
			continue
		if ids.has(identifier):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "%s '%s'" % [label, identifier])
		ids[identifier] = true
	return ids


func _resource_dictionary(resources: Array, property: StringName) -> Dictionary:
	var result: Dictionary = {}
	for resource_variant in resources:
		var resource := resource_variant as Resource
		if resource != null:
			result[resource.get(property) as StringName] = resource
	return result


func _require_id(result: DataValidationResult, identifier: StringName, detail: String) -> void:
	if identifier.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, detail)


func _require_reference(result: DataValidationResult, ids: Dictionary, identifier: StringName, detail: String) -> void:
	if identifier.is_empty() or not ids.has(identifier):
		result.add(DataValidationResult.Reason.INVALID_REFERENCE, "%s='%s'" % [detail, identifier])
