class_name BuildingState
extends RefCounted

const MAX_PRODUCTION_QUEUE_SIZE := 5

var entity_id: int
var definition_id: StringName
var faction_id: int
var controller_id: int
var position: Vector2
var max_health: float
var health: float
var armor: float = 0.0
var enabled: bool = true
var operational: bool = true
var under_construction: bool = false
var construction_ticks_total: int = 0
var construction_ticks_remaining: int = 0
var builder_entity_id: int = 0
var footprint_cells: Array[Vector2i] = []
var rally_position: Vector2
var production_rally_position: Vector2
var production_definition_id: StringName
var production_ticks_remaining: int = 0
var production_cost_paid: int = 0
var production_queue: Array[StringName] = []


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
	production_rally_position = rally_position


func production_count() -> int:
	return production_queue.size() + int(not production_definition_id.is_empty())
