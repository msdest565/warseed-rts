class_name OreFieldSnapshot
extends RefCounted

var entity_id: int
var position: Vector2
var ore_remaining: int


func _init(ore_field: OreFieldState) -> void:
	entity_id = ore_field.entity_id
	position = ore_field.position
	ore_remaining = ore_field.ore_remaining
