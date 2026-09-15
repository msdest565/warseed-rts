class_name EnemyOperationSnapshot
extends RefCounted

var operation_id: StringName
var doctrine: EnemyOperationDoctrine
var phases: Array[EnemyOperationPhaseSnapshot] = []
var retreat_position: Vector2
var locked_tick: int = 0
var initial_strength: int = 0
var withdrawing: bool = false
var withdrawn_formation_ids: Array[int] = []
var committed_formation_ids: Array[int] = []
var reserve_policy: EnemyReservePolicy
var initial_committed_strength: int = 0
var reserve_committed_strength: int = 0

func duplicate_value() -> EnemyOperationSnapshot:
	var result := EnemyOperationSnapshot.new()
	result.operation_id = operation_id
	result.doctrine = doctrine.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyOperationDoctrine
	result.retreat_position = retreat_position
	result.locked_tick = locked_tick
	result.initial_strength = initial_strength
	result.withdrawing = withdrawing
	result.withdrawn_formation_ids.assign(withdrawn_formation_ids)
	result.committed_formation_ids.assign(committed_formation_ids)
	result.reserve_policy = reserve_policy.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyReservePolicy if reserve_policy != null else null
	result.initial_committed_strength = initial_committed_strength
	result.reserve_committed_strength = reserve_committed_strength
	for phase in phases: result.phases.append(phase.duplicate_value())
	return result
