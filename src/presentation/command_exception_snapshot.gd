class_name CommandExceptionSnapshot
extends RefCounted

enum Kind {
	BLOCKED,
	EXPOSED,
	LOW_ORGANIZATION,
	LOW_SUPPLY,
	REINFORCEMENT_REQUEST,
}

enum Severity {
	INFO,
	WARNING,
	CRITICAL,
}

enum Action {
	FOCUS,
	RESUME_TASK,
	CANCEL_TASK,
	DISENGAGE_COMMANDER,
	REQUEST_REINFORCEMENT,
	KEEP_PLAN,
	RETURN_TO_COMMANDER,
}

var exception_id: StringName
var kind: Kind
var severity: Severity
var reason_key: StringName
var source_tick: int
var commander_id: StringName
var unit_card_id: StringName
var unit_card_name_key: StringName
var task_id: int
var position: Vector2
var value_current: float
var value_limit: float
var action_ids: Array[int]


func _init(
	new_exception_id: StringName,
	new_kind: Kind,
	new_severity: Severity,
	new_reason_key: StringName,
	new_source_tick: int,
	new_commander_id: StringName = &"",
	new_unit_card_id: StringName = &"",
	new_unit_card_name_key: StringName = &"",
	new_task_id: int = 0,
	new_position: Vector2 = Vector2.ZERO,
	new_value_current: float = 0.0,
	new_value_limit: float = 0.0,
	new_action_ids: Array[int] = []
) -> void:
	exception_id = new_exception_id
	kind = new_kind
	severity = new_severity
	reason_key = new_reason_key
	source_tick = new_source_tick
	commander_id = new_commander_id
	unit_card_id = new_unit_card_id
	unit_card_name_key = new_unit_card_name_key
	task_id = new_task_id
	position = new_position
	value_current = new_value_current
	value_limit = new_value_limit
	action_ids = new_action_ids.duplicate()


func to_dictionary() -> Dictionary:
	return {
		"exception_id": String(exception_id),
		"kind": kind,
		"severity": severity,
		"reason_key": String(reason_key),
		"source_tick": source_tick,
		"commander_id": String(commander_id),
		"unit_card_id": String(unit_card_id),
		"unit_card_name_key": String(unit_card_name_key),
		"task_id": task_id,
		"position": [snappedf(position.x, 0.001), snappedf(position.y, 0.001)],
		"value_current": snappedf(value_current, 0.001),
		"value_limit": snappedf(value_limit, 0.001),
		"action_ids": action_ids.duplicate(),
	}
