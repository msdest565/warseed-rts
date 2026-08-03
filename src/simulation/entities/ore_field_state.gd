class_name OreFieldState
extends RefCounted

var entity_id: int
var position: Vector2
var ore_remaining: int


func _init(new_entity_id: int, new_position: Vector2, initial_ore: int) -> void:
	entity_id = new_entity_id
	position = new_position
	ore_remaining = initial_ore
