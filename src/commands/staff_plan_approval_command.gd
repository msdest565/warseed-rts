class_name StaffPlanApprovalCommand
extends GameCommand

var request: StaffPlanRequest
var profile_id: StringName
var expected_fingerprint: String


func _init(id: int, faction: int, tick: int, new_request: StaffPlanRequest, new_profile: StringName, fingerprint: String) -> void:
	super(id, faction, IssuerKind.PLAYER, tick, 0)
	request = new_request.duplicate_value() if new_request != null else null
	profile_id = new_profile
	expected_fingerprint = fingerprint


func duplicate_value() -> StaffPlanApprovalCommand:
	var result := StaffPlanApprovalCommand.new(command_id, issuer_id, issued_tick, request, profile_id, expected_fingerprint)
	result.issuer_kind = issuer_kind
	return result
