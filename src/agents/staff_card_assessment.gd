class_name StaffCardAssessment
extends RefCounted

var card_id: StringName
var commander_id: StringName
var deployment_state: int
var control_state: int
var current_strength: int
var available_strength: int
var authorized_strength: int
var position: Vector2
var organization: float
var organization_enabled: bool
var ammunition: int
var ammunition_capacity: int
var task_id: int
var supply_cost: int
var can_allocate: bool
var is_reserve: bool
var reason_key: StringName


func duplicate_value() -> StaffCardAssessment:
	var result := StaffCardAssessment.new()
	for field in to_dictionary():
		result.set(field, get(field))
	return result


func to_dictionary() -> Dictionary:
	return {
		"card_id": String(card_id), "commander_id": String(commander_id),
		"deployment_state": deployment_state, "control_state": control_state,
		"current_strength": current_strength, "available_strength": available_strength,
		"authorized_strength": authorized_strength, "position": [position.x, position.y],
		"organization": organization, "organization_enabled": organization_enabled,
		"ammunition": ammunition, "ammunition_capacity": ammunition_capacity,
		"task_id": task_id, "supply_cost": supply_cost, "can_allocate": can_allocate,
		"is_reserve": is_reserve, "reason_key": String(reason_key),
	}
