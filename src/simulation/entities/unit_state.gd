class_name UnitState
extends RefCounted

var entity_id: int
var position: Vector2
var move_target: Vector2
var has_move_target: bool = false
var move_speed: float
var controller_id: int
var enabled: bool = true


func _init(
	new_entity_id: int,
	new_position: Vector2,
	new_move_speed: float,
	new_controller_id: int
) -> void:
	entity_id = new_entity_id
	position = new_position
	move_target = new_position
	move_speed = new_move_speed
	controller_id = new_controller_id
