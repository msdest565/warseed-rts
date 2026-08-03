class_name BuildingSnapshot
extends RefCounted

var entity_id: int
var definition_id: StringName
var faction_id: int
var controller_id: int
var position: Vector2
var max_health: float
var health: float
var enabled: bool
var rally_position: Vector2
var production_definition_id: StringName
var production_ticks_remaining: int
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
		enabled = contact.enabled
		rally_position = contact.position
		production_definition_id = &""
		production_ticks_remaining = 0
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
	enabled = building.enabled
	rally_position = building.rally_position
	production_definition_id = building.production_definition_id
	production_ticks_remaining = building.production_ticks_remaining
