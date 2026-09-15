class_name EnemyOperationDoctrine
extends Resource

@export var doctrine_id: StringName = &"deliberate_pressure"
@export var max_committed_strength: int = 40
@export_range(0.0, 1.0) var retreat_strength_ratio: float = 0.25
@export var minimum_commitment_ticks: int = 0

func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if doctrine_id.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "enemy doctrine ID required")
	if max_committed_strength <= 0 or minimum_commitment_ticks < 0 or not is_finite(retreat_strength_ratio) or retreat_strength_ratio < 0.0 or retreat_strength_ratio > 1.0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "enemy doctrine limits invalid")
	return result
