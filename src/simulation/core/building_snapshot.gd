class_name BuildingSnapshot
extends RefCounted

var entity_id: int
var definition_id: StringName
var faction_id: int
var controller_id: int
var position: Vector2
var max_health: float
var health: float
var armor: float
var enabled: bool
var operational: bool
var under_construction: bool
var construction_ticks_total: int
var construction_ticks_remaining: int
var builder_entity_id: int
var footprint_cells: Array[Vector2i]
var rally_position: Vector2
var production_rally_position: Vector2
var production_definition_id: StringName
var production_ticks_remaining: int
var production_queue: Array[StringName]
var is_visible: bool = true
var last_seen_tick: int = -1


func _init(building: BuildingState = null, contact: KnowledgeContact = null) -> void:
	if contact != null:
		entity_id = contact.entity_id
		definition_id = contact.definition_id
		faction_id = contact.faction_id
		controller_id = contact.faction_id
		position = contact.position
		max_health = contact.max_health
		health = contact.health
		armor = 0.0
		enabled = contact.enabled
		operational = contact.enabled
		under_construction = false
		construction_ticks_total = 0
		construction_ticks_remaining = 0
		builder_entity_id = 0
		footprint_cells = []
		rally_position = contact.position
		production_rally_position = contact.position
		production_definition_id = &""
		production_ticks_remaining = 0
		production_queue = []
		is_visible = false
		last_seen_tick = contact.last_seen_tick
		return
	entity_id = building.entity_id
	definition_id = building.definition_id
	faction_id = building.faction_id
	controller_id = building.controller_id
	position = building.position
	max_health = building.max_health
	health = building.health
	armor = building.armor
	enabled = building.enabled
	operational = building.operational
	under_construction = building.under_construction
	construction_ticks_total = building.construction_ticks_total
	construction_ticks_remaining = building.construction_ticks_remaining
	builder_entity_id = building.builder_entity_id
	footprint_cells.assign(building.footprint_cells)
	rally_position = building.rally_position
	production_rally_position = building.production_rally_position
	production_definition_id = building.production_definition_id
	production_ticks_remaining = building.production_ticks_remaining
	production_queue.assign(building.production_queue)
