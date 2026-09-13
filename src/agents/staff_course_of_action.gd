class_name StaffCourseOfAction
extends RefCounted

var plan_id: StringName
var profile_id: StringName
var kind: int
var name_key: StringName
var source_tick: int
var objective_region_id: StringName
var assignments: Array[StaffPlanAssignment] = []
var reserve_card_ids: Array[StringName] = []
var evidence_fact_ids: Array[StringName] = []
var reason_keys: Array[StringName] = []
var committed_strength: int
var reserve_strength: int
var supply_cost: int
var route_distance: float
var preparation_ticks: int
var known_threat_score: int
var uncertainty_score: int
var readiness_penalty: int
var risk_score: int
var objective_value: int
var utility_score: int
var route_is_navigation_path: bool = false


func duplicate_value() -> StaffCourseOfAction:
	var result := StaffCourseOfAction.new()
	for field in to_dictionary():
		if field not in ["assignments", "reserve_card_ids", "evidence_fact_ids", "reason_keys"]:
			result.set(field, get(field))
	for assignment in assignments:
		result.assignments.append(assignment.duplicate_value())
	result.reserve_card_ids.assign(reserve_card_ids)
	result.evidence_fact_ids.assign(evidence_fact_ids)
	result.reason_keys.assign(reason_keys)
	return result


func to_dictionary() -> Dictionary:
	var assigned: Array[Dictionary] = []
	for assignment in assignments:
		assigned.append(assignment.to_dictionary())
	return {"plan_id": String(plan_id), "profile_id": String(profile_id), "kind": kind,
		"name_key": String(name_key), "source_tick": source_tick, "objective_region_id": String(objective_region_id),
		"assignments": assigned, "reserve_card_ids": reserve_card_ids.duplicate(),
		"evidence_fact_ids": evidence_fact_ids.duplicate(), "reason_keys": reason_keys.duplicate(),
		"committed_strength": committed_strength, "reserve_strength": reserve_strength,
		"supply_cost": supply_cost, "route_distance": route_distance, "preparation_ticks": preparation_ticks,
		"known_threat_score": known_threat_score, "uncertainty_score": uncertainty_score,
		"readiness_penalty": readiness_penalty, "risk_score": risk_score, "objective_value": objective_value,
		"utility_score": utility_score, "route_is_navigation_path": route_is_navigation_path}


func fingerprint() -> String:
	return JSON.stringify(to_dictionary()).sha256_text()
