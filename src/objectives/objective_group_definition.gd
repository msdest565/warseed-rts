class_name ObjectiveGroupDefinition
extends Resource

enum Rule {
	ALL,
	ANY,
}

@export var group_id: StringName
@export var rule: Rule = Rule.ALL
@export var objective_ids: Array[StringName] = []
@export var outcome_result: BattleOutcome.Result = BattleOutcome.Result.VICTORY
@export var outcome_grade: BattleOutcome.Grade = BattleOutcome.Grade.DECISIVE
@export var priority: int = 0


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if group_id.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "objective group requires group_id")
	if objective_ids.is_empty():
		result.add(DataValidationResult.Reason.INVALID_VALUE, "objective group '%s' requires at least one objective" % group_id)
	if outcome_result == BattleOutcome.Result.ONGOING:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "objective group '%s' must produce a terminal result" % group_id)
	if priority < 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "objective group '%s' cannot use negative priority" % group_id)
	var seen: Dictionary = {}
	for objective_id in objective_ids:
		if objective_id.is_empty() or seen.has(objective_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID if seen.has(objective_id) else DataValidationResult.Reason.EMPTY_ID, "objective group '%s' has an invalid objective reference" % group_id)
		seen[objective_id] = true
	return result
