class_name CommanderSnapshot
extends RefCounted

var definition_id: StringName
var display_name_key: StringName
var faction_id: int
var capacity: int
var personality_key: StringName
var specialty_keys: Array[StringName]
var doctrine_keys: Array[StringName]
var subordinate_unit_card_ids: Array[StringName]
var agent_id: int = 0
var posture: CommanderState.Posture = CommanderState.Posture.BALANCED
var target_position: Vector2
var target_region_id: StringName
var planned_route: PackedVector2Array
var current_task_ids: Array[int]
var last_detail: String
var behavior_state_key: StringName
var behavior_reason_key: StringName
var behavior_changed_tick: int
var estimated_arrival_min_ticks: int
var estimated_arrival_max_ticks: int
var risk_key: StringName
var risk_reason_key: StringName
var exit_condition_key: StringName
var doctrine_slot_count: int
var equipped_doctrine_ids: Array[StringName]
var available_doctrine_ids: Array[StringName]
var active_intent_id: StringName
var intent_objective_region_id: StringName
var intent_axis_region_id: StringName
var intent_reserve_policy: CommanderState.ReservePolicy
var intent_accepted_tick: int


func _init(state: CommanderState) -> void:
	definition_id = state.definition.definition_id
	display_name_key = state.definition.display_name_key
	faction_id = state.faction_id
	capacity = state.definition.capacity
	personality_key = state.definition.personality_key
	specialty_keys = state.definition.specialty_keys.duplicate()
	doctrine_keys = state.definition.doctrine_keys.duplicate()
	subordinate_unit_card_ids = state.subordinate_unit_card_ids.duplicate()
	agent_id = state.agent_id
	posture = state.posture
	target_position = state.target_position
	target_region_id = state.target_region_id
	planned_route = state.planned_route.duplicate()
	current_task_ids = state.current_task_ids.duplicate()
	last_detail = state.last_detail
	behavior_state_key = state.behavior_state_key
	behavior_reason_key = state.behavior_reason_key
	behavior_changed_tick = state.behavior_changed_tick
	estimated_arrival_min_ticks = state.estimated_arrival_min_ticks
	estimated_arrival_max_ticks = state.estimated_arrival_max_ticks
	risk_key = state.risk_key
	risk_reason_key = state.risk_reason_key
	exit_condition_key = state.exit_condition_key
	doctrine_slot_count = state.doctrine_slot_count
	equipped_doctrine_ids = state.equipped_doctrine_ids.duplicate()
	available_doctrine_ids = state.available_doctrine_ids.duplicate()
	active_intent_id = state.active_intent_id
	intent_objective_region_id = state.intent_objective_region_id
	intent_axis_region_id = state.intent_axis_region_id
	intent_reserve_policy = state.intent_reserve_policy
	intent_accepted_tick = state.intent_accepted_tick
