class_name SimulationEvent
extends RefCounted

enum Kind {
	COMMAND_ACCEPTED,
	COMMAND_REJECTED,
	UNIT_ARRIVED,
}

var tick: int
var kind: Kind
var entity_id: int
var detail: String


func _init(new_tick: int, new_kind: Kind, new_entity_id: int, new_detail: String = "") -> void:
	tick = new_tick
	kind = new_kind
	entity_id = new_entity_id
	detail = new_detail
