class_name BattleOutcome
extends RefCounted

enum Result {
	ONGOING,
	VICTORY,
	DEFEAT,
	ORDERED_WITHDRAWAL,
}

enum Grade {
	NONE,
	DECISIVE,
	TACTICAL,
	ORDERED,
	COLLAPSE,
}

var result: Result
var grade: Grade
var concluded_tick: int
var conclusion_group_id: StringName
var reason_objective_ids: Array[StringName]


func _init(
	new_result: Result = Result.ONGOING,
	new_grade: Grade = Grade.NONE,
	new_concluded_tick: int = -1,
	new_conclusion_group_id: StringName = &"",
	new_reason_objective_ids: Array[StringName] = []
) -> void:
	result = new_result
	grade = new_grade
	concluded_tick = new_concluded_tick
	conclusion_group_id = new_conclusion_group_id
	reason_objective_ids.assign(new_reason_objective_ids)


func is_terminal() -> bool:
	return result != Result.ONGOING


func result_key() -> StringName:
	return StringName(Result.keys()[result].to_lower())


func grade_key() -> StringName:
	return StringName(Grade.keys()[grade].to_lower())


func duplicate_value() -> BattleOutcome:
	return BattleOutcome.new(result, grade, concluded_tick, conclusion_group_id, reason_objective_ids)
