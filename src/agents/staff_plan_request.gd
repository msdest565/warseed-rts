class_name StaffPlanRequest
extends RefCounted

var objective_region_id: StringName
var max_supply_cost: int = 0
var risk_aversion: int = 2
var allowed_card_ids: Array[StringName] = []


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if objective_region_id.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "staff request requires an objective")
	if max_supply_cost < 0 or risk_aversion < 1 or risk_aversion > 3:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "staff budget or risk preference is invalid")
	var ids: Array[StringName] = []
	for id in allowed_card_ids:
		if id.is_empty() or ids.has(id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "allowed cards must be nonempty distinct IDs")
		ids.append(id)
	return result


func duplicate_value() -> StaffPlanRequest:
	var result := StaffPlanRequest.new()
	result.objective_region_id = objective_region_id
	result.max_supply_cost = max_supply_cost
	result.risk_aversion = risk_aversion
	result.allowed_card_ids.assign(allowed_card_ids)
	return result


func to_dictionary() -> Dictionary:
	var sorted_ids := allowed_card_ids.duplicate()
	sorted_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return {"objective_region_id": String(objective_region_id), "max_supply_cost": max_supply_cost,
		"risk_aversion": risk_aversion, "allowed_card_ids": sorted_ids}
