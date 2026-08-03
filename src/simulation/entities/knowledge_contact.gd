class_name KnowledgeContact
extends RefCounted

var entity_id: int
var is_building: bool
var definition_id: StringName
var faction_id: int
var position: Vector2
var max_health: float
var health: float
var enabled: bool
var last_seen_tick: int


static func from_unit(unit: UnitState, tick: int) -> KnowledgeContact:
	var contact := KnowledgeContact.new()
	contact.entity_id = unit.entity_id
	contact.is_building = false
	contact.definition_id = unit.definition_id
	contact.faction_id = unit.faction_id
	contact.position = unit.position
	contact.max_health = unit.max_health
	contact.health = unit.health
	contact.enabled = unit.enabled
	contact.last_seen_tick = tick
	return contact


static func from_building(building: BuildingState, tick: int) -> KnowledgeContact:
	var contact := KnowledgeContact.new()
	contact.entity_id = building.entity_id
	contact.is_building = true
	contact.definition_id = building.definition_id
	contact.faction_id = building.faction_id
	contact.position = building.position
	contact.max_health = building.max_health
	contact.health = building.health
	contact.enabled = building.enabled
	contact.last_seen_tick = tick
	return contact
