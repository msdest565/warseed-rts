class_name ArmyRosterResult
extends RefCounted

enum Status { MISSING, LOADED, MIGRATED, SAVED, FAILED }

var status: Status = Status.FAILED
var record: Dictionary = {}
var source_version: int = 0
var errors: PackedStringArray = []
var backup_path: String = ""


func is_success() -> bool:
	return status in [Status.LOADED, Status.MIGRATED, Status.SAVED]


func fail(detail: String) -> ArmyRosterResult:
	status = Status.FAILED
	record = {}
	errors.append(detail)
	return self
