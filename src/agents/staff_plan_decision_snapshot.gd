class_name StaffPlanDecisionSnapshot
extends RefCounted

var faction_id: int
var command_id: int
var decided_tick: int
var accepted: bool
var reason: CommandValidationResult.Reason = CommandValidationResult.Reason.NONE
var approved_plan: StaffCourseOfAction


func duplicate_value() -> StaffPlanDecisionSnapshot:
	var result := StaffPlanDecisionSnapshot.new()
	result.faction_id = faction_id
	result.command_id = command_id
	result.decided_tick = decided_tick
	result.accepted = accepted
	result.reason = reason
	result.approved_plan = approved_plan.duplicate_value() if approved_plan != null else null
	return result
