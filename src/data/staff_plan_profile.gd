class_name StaffPlanProfile
extends Resource

enum Kind { DIRECT, RECON_FIRST, FLANK }

@export var profile_id: StringName
@export var kind: Kind = Kind.DIRECT
@export var name_key: StringName
@export var force_percent: int = 100
@export var preparation_ticks: int = 0
@export var risk_weight: int = 2
@export var permits_reserve_deployment: bool = false


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if profile_id.is_empty() or name_key.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "staff profile requires stable ID and name key")
	if kind < Kind.DIRECT or kind > Kind.FLANK:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "unsupported staff profile kind")
	if force_percent < 1 or force_percent > 100 or preparation_ticks < 0 or preparation_ticks > 600 or risk_weight < 1 or risk_weight > 5:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "staff profile force/timing/risk is out of bounds")
	return result
