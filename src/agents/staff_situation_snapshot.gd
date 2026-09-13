class_name StaffSituationSnapshot
extends RefCounted

const SCHEMA_ID := "warseed.staff-situation.v1"

var source_tick: int
var observer_faction_id: int
var supply: int
var population: int
var population_capacity: int
var unexplored_cell_count: int
var known_cell_count: int
var visible_hostile_count: int
var remembered_hostile_count: int
var allocatable_strength: int
var reserve_strength: int
var facts: Array[StaffSituationFact] = []
var cards: Array[StaffCardAssessment] = []


func duplicate_value() -> StaffSituationSnapshot:
	var result := StaffSituationSnapshot.new()
	for field in to_dictionary():
		if field not in ["schema_id", "facts", "cards"]:
			result.set(field, get(field))
	for fact in facts:
		result.facts.append(fact.duplicate_value())
	for card in cards:
		result.cards.append(card.duplicate_value())
	return result


func get_card(card_id: StringName) -> StaffCardAssessment:
	for card in cards:
		if card.card_id == card_id:
			return card
	return null


func to_dictionary() -> Dictionary:
	var fact_values: Array[Dictionary] = []
	var card_values: Array[Dictionary] = []
	for fact in facts:
		fact_values.append(fact.to_dictionary())
	for card in cards:
		card_values.append(card.to_dictionary())
	return {
		"schema_id": SCHEMA_ID, "source_tick": source_tick,
		"observer_faction_id": observer_faction_id, "supply": supply,
		"population": population, "population_capacity": population_capacity,
		"unexplored_cell_count": unexplored_cell_count, "known_cell_count": known_cell_count,
		"visible_hostile_count": visible_hostile_count, "remembered_hostile_count": remembered_hostile_count,
		"allocatable_strength": allocatable_strength, "reserve_strength": reserve_strength,
		"facts": fact_values, "cards": card_values,
	}


func canonical_json() -> String:
	return JSON.stringify(to_dictionary())


func fingerprint() -> String:
	return canonical_json().sha256_text()
