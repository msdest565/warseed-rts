class_name AfterActionTurningPoint
extends RefCounted

var stable_id: StringName
var first_tick: int
var last_tick: int
var actor_id: String
var unit_card_id: StringName
var task_id: int
var reason_key: StringName
var source_event: StringName
var result: String
var occurrences: int
var priority: int


func _init(
	new_stable_id: StringName,
	new_first_tick: int,
	new_last_tick: int,
	new_actor_id: String,
	new_unit_card_id: StringName,
	new_task_id: int,
	new_reason_key: StringName,
	new_source_event: StringName,
	new_result: String,
	new_occurrences: int = 1,
	new_priority: int = 0
) -> void:
	stable_id = new_stable_id
	first_tick = new_first_tick
	last_tick = new_last_tick
	actor_id = new_actor_id
	unit_card_id = new_unit_card_id
	task_id = new_task_id
	reason_key = new_reason_key
	source_event = new_source_event
	result = new_result
	occurrences = new_occurrences
	priority = new_priority


func duplicate_entry() -> AfterActionTurningPoint:
	return AfterActionTurningPoint.new(
		stable_id, first_tick, last_tick, actor_id, unit_card_id, task_id,
		reason_key, source_event, result, occurrences, priority
	)


func to_dictionary() -> Dictionary:
	return {
		"stable_id": String(stable_id),
		"first_tick": first_tick,
		"last_tick": last_tick,
		"actor_id": actor_id,
		"card_id": String(unit_card_id),
		"task_id": task_id,
		"reason_key": String(reason_key),
		"source_event": String(source_event),
		"result": result,
		"occurrences": occurrences,
	}
