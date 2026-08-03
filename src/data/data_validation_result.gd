class_name DataValidationResult
extends RefCounted

enum Reason {
	NULL_REFERENCE,
	EMPTY_ID,
	DUPLICATE_ID,
	EMPTY_DISPLAY_NAME,
	INVALID_MOVE_SPEED,
	INVALID_COMBAT,
	INVALID_MAX_HEALTH,
	INVALID_ARMOR,
	INVALID_ATTACK_POWER,
	INVALID_ATTACK_RANGE,
	INVALID_ATTACK_SPEED,
	INVALID_PROJECTILE_SPEED,
	INVALID_COST,
}

var issues: Array[Dictionary] = []


func add(reason: Reason, detail: String) -> void:
	issues.append({"reason": reason, "detail": detail})


func is_valid() -> bool:
	return issues.is_empty()


func has_reason(reason: Reason) -> bool:
	for issue in issues:
		if issue["reason"] == reason:
			return true
	return false
