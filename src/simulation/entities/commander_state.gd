class_name CommanderState
extends RefCounted

enum Posture {
	CAUTIOUS,
	BALANCED,
	AGGRESSIVE,
	HOLD,
	DISENGAGE,
}

enum ReservePolicy {
	HOLD,
	REINFORCE_ON_REQUEST,
	COMMIT_AVAILABLE,
}

var definition: CommanderDefinition
var faction_id: int
var subordinate_unit_card_ids: Array[StringName] = []
var agent_id: int = 0
var posture: Posture = Posture.BALANCED
var target_position: Vector2
var target_region_id: StringName
var planned_route: PackedVector2Array = PackedVector2Array()
var current_task_ids: Array[int] = []
var last_detail: String = ""
var behavior_state_key: StringName = &"COMMANDER_BEHAVIOR_STANDING_BY"
var behavior_reason_key: StringName = &"COMMANDER_REASON_NO_ACTIVE_TASK"
var behavior_changed_tick: int = 0
var estimated_arrival_min_ticks: int = -1
var estimated_arrival_max_ticks: int = -1
var risk_key: StringName = &"COMMANDER_RISK_UNKNOWN"
var risk_reason_key: StringName = &"COMMANDER_RISK_REASON_NO_RELIABLE_INTEL"
var exit_condition_key: StringName = &"COMMANDER_EXIT_AWAIT_ORDER"
var doctrine_slot_count: int = 1
var equipped_doctrine_ids: Array[StringName] = []
var available_doctrine_ids: Array[StringName] = []
var active_intent_id: StringName
var intent_objective_region_id: StringName
var intent_axis_region_id: StringName
var intent_reserve_policy: ReservePolicy = ReservePolicy.HOLD
var intent_accepted_tick: int = -1


func _init(new_definition: CommanderDefinition, new_faction_id: int) -> void:
	definition = new_definition
	faction_id = new_faction_id


func attach_unit_card(unit_card_id: StringName) -> void:
	if not subordinate_unit_card_ids.has(unit_card_id):
		subordinate_unit_card_ids.append(unit_card_id)
		subordinate_unit_card_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
			return String(left) < String(right)
		)


func set_task_ids(task_ids: Array[int]) -> void:
	current_task_ids = task_ids.duplicate()
	current_task_ids.sort()


func set_behavior(state_key: StringName, reason_key: StringName, tick: int) -> void:
	if behavior_state_key == state_key and behavior_reason_key == reason_key:
		return
	behavior_state_key = state_key
	behavior_reason_key = reason_key
	behavior_changed_tick = tick
	last_detail = "%s:%s" % [state_key, reason_key]


func equip_doctrine(doctrine_id: StringName, slot_index: int = 0) -> bool:
	if slot_index < 0 or slot_index >= doctrine_slot_count or not available_doctrine_ids.has(doctrine_id):
		return false
	while equipped_doctrine_ids.size() < doctrine_slot_count:
		equipped_doctrine_ids.append(&"")
	equipped_doctrine_ids[slot_index] = doctrine_id
	return true


func has_doctrine(doctrine_id: StringName) -> bool:
	return equipped_doctrine_ids.has(doctrine_id)


func set_high_level_intent(
	intent_id: StringName,
	objective_region_id: StringName,
	axis_region_id: StringName,
	reserve_policy: ReservePolicy,
	tick: int
) -> void:
	active_intent_id = intent_id
	intent_objective_region_id = objective_region_id
	intent_axis_region_id = axis_region_id
	intent_reserve_policy = reserve_policy
	intent_accepted_tick = tick


func clear_high_level_intent() -> void:
	active_intent_id = &""
	intent_objective_region_id = &""
	intent_axis_region_id = &""
	intent_reserve_policy = ReservePolicy.HOLD
	intent_accepted_tick = -1
