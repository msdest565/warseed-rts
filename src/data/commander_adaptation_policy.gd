class_name CommanderAdaptationPolicy
extends Resource

@export var policy_id: StringName = &"bounded_commander_adjustment"
@export var interval_ticks: int = 30
@export var max_reserve_commits: int = 1
@export var max_reinforcements: int = 2
@export var max_replans: int = 2
@export var retreat_ratio: float = 0.42
@export var reinforce_ratio: float = 0.75


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if policy_id.is_empty() or interval_ticks < 1 or max_reserve_commits < 0 or max_reinforcements < 0 or max_replans < 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "invalid adjustment limits")
	if not is_finite(retreat_ratio) or not is_finite(reinforce_ratio) or retreat_ratio <= 0.0 or reinforce_ratio <= retreat_ratio or reinforce_ratio > 1.0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "invalid adjustment ratios")
	return result
