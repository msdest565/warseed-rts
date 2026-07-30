class_name CommandValidationResult
extends RefCounted

enum Status {
	ACCEPTED,
	REJECTED,
	DEFERRED,
}

enum Reason {
	NONE,
	INVALID_TARGET,
	NOT_CONTROLLER,
	ENTITY_DISABLED,
	INVALID_POSITION,
}

var status: Status
var reason: Reason


func _init(new_status: Status, new_reason: Reason = Reason.NONE) -> void:
	status = new_status
	reason = new_reason


func is_accepted() -> bool:
	return status == Status.ACCEPTED


func describe() -> String:
	if status == Status.ACCEPTED:
		return "Accepted"
	return "%s: %s" % [Status.keys()[status], Reason.keys()[reason]]
