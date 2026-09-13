class_name StaffSituationFact
extends RefCounted

enum Category { THREAT, OPPORTUNITY, GAP }
enum Kind {
	VISIBLE_CONTACT, REMEMBERED_CONTACT, INTEL_ESTIMATE, CAPTURE_CANDIDATE,
	UNKNOWN_REGION, STRENGTH_SHORTFALL, LOW_ORGANIZATION, LOW_AMMUNITION,
	BLOCKED_TASK, INSUFFICIENT_SUPPLY,
}

var fact_id: StringName
var category: Category
var kind: Kind
var reason_key: StringName
var source_key: StringName
var blocked_reason: int
var source_tick: int
var last_observed_tick: int
var confidence_percent: int
var entity_id: int
var report_id: int
var task_id: int
var region_id: StringName
var card_id: StringName
var position: Vector2
var estimated_min: int
var estimated_max: int
var has_estimate: bool
var contradictory: bool
var current_value: float
var required_value: float


func duplicate_value() -> StaffSituationFact:
	var result := StaffSituationFact.new()
	for field in to_dictionary():
		result.set(field, get(field))
	return result


func to_dictionary() -> Dictionary:
	return {
		"fact_id": String(fact_id), "category": int(category), "kind": int(kind),
		"reason_key": String(reason_key), "source_key": String(source_key), "blocked_reason": blocked_reason, "source_tick": source_tick,
		"last_observed_tick": last_observed_tick, "confidence_percent": confidence_percent,
		"entity_id": entity_id, "report_id": report_id, "task_id": task_id,
		"region_id": String(region_id), "card_id": String(card_id),
		"position": [position.x, position.y], "estimated_min": estimated_min,
		"estimated_max": estimated_max, "has_estimate": has_estimate,
		"contradictory": contradictory, "current_value": current_value,
		"required_value": required_value,
	}
