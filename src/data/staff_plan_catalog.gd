class_name StaffPlanCatalog
extends Resource

@export var profiles: Array[StaffPlanProfile] = []


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if profiles.size() < 2 or profiles.size() > 3:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "staff catalog requires two or three alternatives")
	var ids: Array[StringName] = []
	var kinds: Array[int] = []
	for profile in profiles:
		if profile == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "staff profile is missing")
			continue
		result.issues.append_array(profile.validate().issues)
		if ids.has(profile.profile_id) or kinds.has(profile.kind):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "staff profile IDs and kinds must be distinct")
		ids.append(profile.profile_id)
		kinds.append(profile.kind)
	return result
