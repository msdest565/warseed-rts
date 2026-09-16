class_name AfterActionReview
extends RefCounted

const FORMAT_VERSION := 1
const SCHEMA_ID := "warseed.after_action_review.v1"

var enemy_observed_actions: Array[EnemyObservedAction] = []
var observer_faction_id: int
var source_fingerprint: String
var result: StringName
var grade: StringName
var concluded_tick: int
var turning_points: Array[AfterActionTurningPoint]
var card_contributions: Array[AfterActionCardContribution]
var causes: Array[AfterActionCause]


func _init(
	new_observer_faction_id: int,
	new_source_fingerprint: String,
	new_result: StringName,
	new_grade: StringName,
	new_concluded_tick: int,
	new_turning_points: Array[AfterActionTurningPoint],
	new_card_contributions: Array[AfterActionCardContribution],
	new_causes: Array[AfterActionCause]
) -> void:
	observer_faction_id = new_observer_faction_id
	source_fingerprint = new_source_fingerprint
	result = new_result
	grade = new_grade
	concluded_tick = new_concluded_tick
	turning_points = new_turning_points
	card_contributions = new_card_contributions
	causes = new_causes


func duplicate_review() -> AfterActionReview:
	var points: Array[AfterActionTurningPoint] = []
	for entry in turning_points:
		points.append(entry.duplicate_entry())
	var cards: Array[AfterActionCardContribution] = []
	for entry in card_contributions:
		cards.append(entry.duplicate_entry())
	var copied_causes: Array[AfterActionCause] = []
	for entry in causes:
		copied_causes.append(entry.duplicate_entry())
	var copy := AfterActionReview.new(
		observer_faction_id, source_fingerprint, result, grade, concluded_tick,
		points, cards, copied_causes
	)
	for entry in enemy_observed_actions: copy.enemy_observed_actions.append(entry.duplicate_value())
	return copy


func to_dictionary() -> Dictionary:
	var points: Array[Dictionary] = []
	for entry in turning_points:
		points.append(entry.to_dictionary())
	var cards: Array[Dictionary] = []
	for entry in card_contributions:
		cards.append(entry.to_dictionary())
	var cause_records: Array[Dictionary] = []
	for entry in causes:
		cause_records.append(entry.to_dictionary())
	var observations: Array[Dictionary] = []
	for entry in enemy_observed_actions: observations.append(entry.to_dictionary())
	var result_dictionary := {
		"enemy_observed_actions": observations,
		"format_version": FORMAT_VERSION,
		"schema_id": SCHEMA_ID,
		"observer_faction_id": observer_faction_id,
		"source_fingerprint": source_fingerprint,
		"result": String(result),
		"grade": String(grade),
		"concluded_tick": concluded_tick,
		"turning_points": points,
		"card_contributions": cards,
		"causes": cause_records,
	}
	result_dictionary["fingerprint"] = GameplayObservabilityReport.canonical_json(result_dictionary).sha256_text()
	return result_dictionary


func fingerprint() -> String:
	return String(to_dictionary()["fingerprint"])
