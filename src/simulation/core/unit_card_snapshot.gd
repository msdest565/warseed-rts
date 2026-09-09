class_name UnitCardSnapshot
extends RefCounted

var definition_id: StringName
var display_name_key: StringName
var role_key: StringName
var unit_definition_id: StringName
var commander_definition_id: StringName
var faction_id: int
var command_cost: int
var authorized_strength: int
var current_strength: int = 0
var member_entity_ids: Array[int]
var active_member_entity_ids: Array[int] = []
var center_position: Vector2
var assigned_task_id: int = 0
var is_player_overridden: bool = false
var formation_id: int = 0
var deployment_state: UnitCardState.DeploymentState
var deployment_ticks_remaining: int = 0
var deployment_ticks: int = 0
var deployment_position: Vector2
var supply_cost: int = 0
var fortified_ticks_remaining: int = 0
var control_state: UnitCardState.ControlState = UnitCardState.ControlState.UNASSIGNED
var assigned_agent_id: int = 0
var return_task_id: int = 0
var return_formation_id: int = 0
var returning_member_count: int = 0
var terrain_kind: UnitState.TerrainKind = UnitState.TerrainKind.NONE
var terrain_effect_key: StringName = &"TERRAIN_EFFECT_NONE"
var cumulative_losses: int = 0
var battles_survived: int = 0
var honor_id: StringName
var equipment_id: StringName
var organization_enabled: bool = false
var organization: float = 0.0
var organization_state_key: StringName = &"ORGANIZATION_STABLE"
var withdrawn_strength: int = 0
var withdrawn_tick: int = -1


func _init(state: UnitCardState, units: Dictionary) -> void:
	definition_id = state.definition.definition_id
	display_name_key = state.definition.display_name_key
	role_key = state.definition.role_key
	unit_definition_id = state.definition.unit_definition_id
	commander_definition_id = state.commander_definition_id
	faction_id = state.faction_id
	command_cost = state.definition.command_cost
	authorized_strength = state.definition.authorized_strength
	member_entity_ids = state.member_entity_ids.duplicate()
	formation_id = state.formation_id
	deployment_state = state.deployment_state
	deployment_ticks_remaining = state.deployment_ticks_remaining
	deployment_ticks = state.definition.deployment_ticks
	deployment_position = state.deployment_position
	supply_cost = state.effective_supply_cost()
	fortified_ticks_remaining = state.fortified_ticks_remaining
	control_state = state.control_state
	assigned_agent_id = state.assigned_agent_id
	return_task_id = state.return_task_id
	return_formation_id = state.return_formation_id
	cumulative_losses = state.cumulative_losses
	battles_survived = state.battles_survived
	honor_id = state.honor_id
	equipment_id = state.equipment_id
	organization_enabled = state.organization_enabled
	organization = state.organization
	organization_state_key = _organization_state_key(organization)
	withdrawn_strength = state.withdrawn_strength
	withdrawn_tick = state.withdrawn_tick
	var position_sum := Vector2.ZERO
	var shared_task_id := -1
	var terrain_counts: Dictionary = {}
	var terrain_effect_by_kind: Dictionary = {}
	for entity_id in member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit == null or not unit.enabled:
			continue
		active_member_entity_ids.append(entity_id)
		position_sum += unit.position
		is_player_overridden = is_player_overridden or unit.control_state == UnitState.ControlState.TEMPORARILY_OVERRIDDEN
		if unit.rejoin_pending:
			returning_member_count += 1
		terrain_counts[unit.terrain_kind] = int(terrain_counts.get(unit.terrain_kind, 0)) + 1
		terrain_effect_by_kind[unit.terrain_kind] = unit.terrain_effect_key
		if shared_task_id == -1:
			shared_task_id = unit.assigned_task_id
		elif shared_task_id != unit.assigned_task_id:
			shared_task_id = 0
	current_strength = active_member_entity_ids.size()
	if deployment_state == UnitCardState.DeploymentState.WITHDRAWN:
		current_strength = withdrawn_strength
	center_position = position_sum / current_strength if current_strength > 0 else Vector2.ZERO
	assigned_task_id = state.assigned_task_id if state.assigned_task_id != 0 else max(shared_task_id, 0)
	var dominant_count := 0
	for kind_variant in terrain_counts:
		var count := int(terrain_counts[kind_variant])
		if count > dominant_count:
			dominant_count = count
			terrain_kind = int(kind_variant)
			terrain_effect_key = terrain_effect_by_kind[kind_variant]


func _organization_state_key(value: float) -> StringName:
	if value <= 0.0:
		return &"ORGANIZATION_BROKEN"
	if value < 30.0:
		return &"ORGANIZATION_SHAKEN"
	if value < 60.0:
		return &"ORGANIZATION_PRESSURED"
	return &"ORGANIZATION_STABLE"
