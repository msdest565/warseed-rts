class_name BuildingState
extends RefCounted

var entity_id: int
var definition_id: StringName
var faction_id: int
var controller_id: int
var position: Vector2
var max_health: float
var health: float
var enabled: bool = true
var rally_position: Vector2
var production_definition_id: StringName
var production_ticks_remaining: int = 0
var production_cost_paid: int = 0


func _init(
	new_entity_id: int,
	new_definition_id: StringName,
	new_faction_id: int,
	new_controller_id: int,
	new_position: Vector2,
	new_max_health: float
) -> void:
	entity_id = new_entity_id
	definition_id = new_definition_id
	faction_id = new_faction_id
	controller_id = new_controller_id
	position = new_position
	max_health = new_max_health
	health = new_max_health
	rally_position = new_position + Vector2(80.0, 0.0)
