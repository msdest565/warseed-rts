class_name StaffPlanSet
extends RefCounted

const SCHEMA_ID := "warseed.staff-plans.v1"

var source_tick: int
var observer_faction_id: int
var source_fingerprint: String
var request: StaffPlanRequest
var plans: Array[StaffCourseOfAction] = []


func duplicate_value() -> StaffPlanSet:
	var result := StaffPlanSet.new()
	result.source_tick = source_tick
	result.observer_faction_id = observer_faction_id
	result.source_fingerprint = source_fingerprint
	result.request = request.duplicate_value()
	for plan in plans:
		result.plans.append(plan.duplicate_value())
	return result


func to_dictionary() -> Dictionary:
	var values: Array[Dictionary] = []
	for plan in plans:
		values.append(plan.to_dictionary())
	return {"schema_id": SCHEMA_ID, "source_tick": source_tick, "observer_faction_id": observer_faction_id,
		"source_fingerprint": source_fingerprint, "request": request.to_dictionary(), "plans": values}


func canonical_json() -> String:
	return JSON.stringify(to_dictionary())


func fingerprint() -> String:
	return canonical_json().sha256_text()
