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
	PATH_UNAVAILABLE,
	FRIENDLY_TARGET,
	INSUFFICIENT_ORE,
	PRODUCTION_BUSY,
	INVALID_DEFINITION,
	INVALID_BUILDING,
	INVALID_RESOURCE,
	HIDDEN_TARGET,
	AGENT_OVERRIDE_BLOCKED,
	INVALID_TASK,
	INVALID_DISPOSITION,
	TASK_CONFLICT,
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
