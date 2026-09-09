class_name BattleConclusionEvent
extends SimulationEvent

var outcome: BattleOutcome


func _init(new_tick: int, new_outcome: BattleOutcome) -> void:
	outcome = new_outcome.duplicate_value()
	var reasons := PackedStringArray()
	for objective_id in outcome.reason_objective_ids:
		reasons.append(String(objective_id))
	var event_detail := "result=%s;grade=%s;group=%s;objectives=%s" % [
		outcome.result_key(), outcome.grade_key(), outcome.conclusion_group_id, ",".join(reasons),
	]
	super(new_tick, SimulationEvent.Kind.BATTLE_CONCLUDED, 0, event_detail)
