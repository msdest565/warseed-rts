class_name UnitCardState
extends RefCounted

const GROWTH_CATALOG = preload("res://data/army/growth_catalog.tres")

enum DeploymentState {
	RESERVE,
	DEPLOYING,
	DEPLOYED,
	WITHDRAWN,
	DISABLED,
}

enum ControlState {
	UNASSIGNED,
	AGENT_ASSIGNED,
	PLAYER_OVERRIDDEN,
	RETURNING,
	PLAYER_CONTROLLED,
}

var definition: UnitCardDefinition
var faction_id: int
var commander_definition_id: StringName
var member_entity_ids: Array[int] = []
var formation_id: int = 0
var deployment_state: DeploymentState
var deployment_ticks_remaining: int = 0
var deployment_position: Vector2
var fortified_ticks_remaining: int = 0
var rapid_mobility_ticks_remaining: int = 0
var control_state: ControlState = ControlState.UNASSIGNED
var assigned_agent_id: int = 0
var assigned_task_id: int = 0
var return_task_id: int = 0
var return_formation_id: int = 0
var takeover_reason: String = ""
var cumulative_losses: int = 0
var battles_survived: int = 0
var available_strength: int = 0
var honor_id: StringName
var equipment_id: StringName
var organization_enabled: bool = false
var organization: float = 0.0
var last_organization_band: int = -1
var last_damage_tick: int = -1000000
var last_total_health: float = 0.0
var last_active_strength: int = 0
var withdrawn_strength: int = 0
var withdrawn_tick: int = -1


func _init(new_definition: UnitCardDefinition, new_faction_id: int, new_member_entity_ids: Array[int]) -> void:
	definition = new_definition
	faction_id = new_faction_id
	commander_definition_id = definition.commander_definition_id
	member_entity_ids = new_member_entity_ids.duplicate()
	member_entity_ids.sort()
	available_strength = definition.authorized_strength
	deployment_state = DeploymentState.RESERVE if definition.starts_in_reserve else DeploymentState.DEPLOYED


func effective_supply_cost() -> int:
	var modifier := 0
	for growth_id in [honor_id, equipment_id]:
		var growth: Variant = GROWTH_CATALOG.get_growth(growth_id)
		if growth != null:
			modifier += growth.deployment_supply_cost_modifier
	return maxi(0, definition.supply_cost + modifier)
