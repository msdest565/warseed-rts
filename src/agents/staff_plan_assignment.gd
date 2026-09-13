class_name StaffPlanAssignment
extends RefCounted

enum Role { ADVANCE, RECONNAISSANCE, FLANK }

var card_id: StringName
var commander_id: StringName
var role: Role
var objective_region_id: StringName
var axis_region_id: StringName
var route_points: PackedVector2Array = PackedVector2Array()
var strength: int
var requires_deployment: bool
var supply_cost: int
var preparation_ticks: int


func duplicate_value() -> StaffPlanAssignment:
	var result := StaffPlanAssignment.new()
	for field in to_dictionary():
		if field != "route_points":
			result.set(field, get(field))
	result.route_points = route_points.duplicate()
	return result


func to_dictionary() -> Dictionary:
	var points: Array = []
	for point in route_points:
		points.append([point.x, point.y])
	return {"card_id": String(card_id), "commander_id": String(commander_id), "role": int(role),
		"objective_region_id": String(objective_region_id), "axis_region_id": String(axis_region_id),
		"route_points": points, "strength": strength, "requires_deployment": requires_deployment,
		"supply_cost": supply_cost, "preparation_ticks": preparation_ticks}
