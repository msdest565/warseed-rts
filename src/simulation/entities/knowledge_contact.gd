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
var attack_range: float
var can_attack: bool = false
var last_seen_tick: int


static func from_unit(unit: UnitState, tick: int) -> KnowledgeContact:
	var contact := KnowledgeContact.new()
	contact.update_from_unit(unit, tick)
	return contact


func update_from_unit(unit: UnitState, tick: int) -> void:
	entity_id = unit.entity_id
	is_building = false
	definition_id = unit.definition_id
	faction_id = unit.faction_id
	position = unit.position
	max_health = unit.max_health
	health = unit.health
	enabled = unit.enabled
	attack_range = unit.attack_range
	can_attack = unit.can_attack
	last_seen_tick = tick


static func from_building(building: BuildingState, tick: int) -> KnowledgeContact:
	var contact := KnowledgeContact.new()
	contact.update_from_building(building, tick)
	return contact


func update_from_building(building: BuildingState, tick: int) -> void:
	entity_id = building.entity_id
	is_building = true
	definition_id = building.definition_id
	faction_id = building.faction_id
	position = building.position
	max_health = building.max_health
	health = building.health
	enabled = building.enabled
	attack_range = 0.0
	can_attack = false
	last_seen_tick = tick
