class_name AfterActionCause
extends RefCounted

enum Role {
	PRIMARY,
	SUPPORTING,
}

var stable_id: StringName
var role: Role
var kind: StringName
var source_tick: int
var source_event: StringName
var reason_key: StringName
var unit_card_id: StringName
var task_id: int
var facts: Dictionary


func _init(
	new_stable_id: StringName,
	new_role: Role,
	new_kind: StringName,
	new_source_tick: int,
	new_source_event: StringName,
	new_reason_key: StringName,
	new_unit_card_id: StringName = &"",
	new_task_id: int = 0,
	new_facts: Dictionary = {}
) -> void:
	stable_id = new_stable_id
	role = new_role
	kind = new_kind
	source_tick = new_source_tick
	source_event = new_source_event
	reason_key = new_reason_key
	unit_card_id = new_unit_card_id
	task_id = new_task_id
	facts = new_facts.duplicate(true)


func duplicate_entry() -> AfterActionCause:
	return AfterActionCause.new(
		stable_id, role, kind, source_tick, source_event, reason_key,
		unit_card_id, task_id, facts
	)


func to_dictionary() -> Dictionary:
	return {
		"stable_id": String(stable_id),
		"role": role,
		"kind": String(kind),
		"source_tick": source_tick,
		"source_event": String(source_event),
		"reason_key": String(reason_key),
		"card_id": String(unit_card_id),
		"task_id": task_id,
		"facts": facts.duplicate(true),
	}
