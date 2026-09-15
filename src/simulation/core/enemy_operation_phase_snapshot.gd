class_name EnemyOperationPhaseSnapshot
extends RefCounted

enum Status { WAITING, ACTIVE, COMPLETED, FAILED, CANCELLED }
var definition: EnemyOperationPhaseDefinition
var formation_id: int
var status: Status = Status.WAITING
var command_id: int = 0
var started_tick: int = -1
var changed_tick: int = 0
var reason: StringName = &"LOCKED_TIMELINE"

func duplicate_value() -> EnemyOperationPhaseSnapshot:
	var result := EnemyOperationPhaseSnapshot.new()
	result.definition = definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyOperationPhaseDefinition
	result.formation_id = formation_id
	result.status = status
	result.command_id = command_id
	result.started_tick = started_tick
	result.changed_tick = changed_tick
	result.reason = reason
	return result
