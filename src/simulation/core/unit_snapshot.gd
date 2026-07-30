class_name UnitSnapshot
extends RefCounted

var entity_id: int
var position: Vector2
var move_target: Vector2
var is_moving: bool
var controller_id: int
var enabled: bool


func _init(unit: UnitState) -> void:
	entity_id = unit.entity_id
	position = unit.position
	move_target = unit.move_target
	is_moving = unit.has_move_target
	controller_id = unit.controller_id
	enabled = unit.enabled
