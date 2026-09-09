class_name ObjectiveState
extends RefCounted

enum Status {
	ACTIVE,
	COMPLETED,
	FAILED,
}

var definition: BattleObjectiveDefinition
var status: Status = Status.ACTIVE
var progress: float = 0.0
var changed_tick: int = -1


func _init(new_definition: BattleObjectiveDefinition) -> void:
	definition = new_definition


func complete(new_tick: int) -> bool:
	if status != Status.ACTIVE:
		return false
	status = Status.COMPLETED
	progress = 1.0
	changed_tick = new_tick
	return true


func fail(new_tick: int) -> bool:
	if status != Status.ACTIVE:
		return false
	status = Status.FAILED
	changed_tick = new_tick
	return true
