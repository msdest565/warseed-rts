class_name InputLatencySnapshot
extends RefCounted

var intent_sequence: int
var intent_target: Vector2
var validation_usec: int
var coalesced_count: int
var authoritative_tick: int


func _init(
	new_intent_sequence: int,
	new_intent_target: Vector2,
	new_validation_usec: int,
	new_coalesced_count: int,
	new_authoritative_tick: int
) -> void:
	intent_sequence = new_intent_sequence
	intent_target = new_intent_target
	validation_usec = new_validation_usec
	coalesced_count = new_coalesced_count
	authoritative_tick = new_authoritative_tick
