class_name AfterActionReviewProjector
extends RefCounted

const MAX_TURNING_POINTS := 7
const MAX_SUPPORTING_CAUSES := 4

var last_rejection_reason: StringName


func project(source_report: Dictionary, observer_faction_id: int) -> AfterActionReview:
	last_rejection_reason = &""
	if not _validate_source(source_report, observer_faction_id):
		return null
	var outcome := source_report.get("outcome", {}) as Dictionary
	var review := AfterActionReview.new(
		observer_faction_id,
		String(source_report["fingerprint"]),
		StringName(outcome.get("result", "in_progress")),
		StringName(outcome.get("grade", "none")),
		int(outcome.get("concluded_tick", source_report.get("final_tick", 0))),
		_build_turning_points(source_report),
		_build_card_contributions(source_report),
		_build_causes(source_report, outcome)
	)
	for value in source_report.get("enemy_observed_actions",[]):
		if not value is Dictionary: continue
		var entry := EnemyObservedAction.from_dictionary(value)
		if entry != null: review.enemy_observed_actions.append(entry)
	return review


func _validate_source(source_report: Dictionary, observer_faction_id: int) -> bool:
	if source_report.is_empty():
		last_rejection_reason = &"REPORT_REQUIRED"
		return false
	if String(source_report.get("schema_id", "")) != "warseed.gameplay_baseline.case.v1":
		last_rejection_reason = &"INVALID_REPORT_SCHEMA"
		return false
	if not bool(source_report.get("legal_observation_only", false)):
		last_rejection_reason = &"ILLEGAL_OBSERVATION_SOURCE"
		return false
	if int(source_report.get("observer_faction_id", -1)) != observer_faction_id:
		last_rejection_reason = &"WRONG_OBSERVER_FACTION"
		return false
	var expected_fingerprint := String(source_report.get("fingerprint", ""))
	var unsigned_report := source_report.duplicate(true)
	unsigned_report.erase("fingerprint")
	if expected_fingerprint.is_empty() or GameplayObservabilityReport.canonical_json(unsigned_report).sha256_text() != expected_fingerprint:
		last_rejection_reason = &"SOURCE_FINGERPRINT_MISMATCH"
		return false
	return true


func _build_turning_points(source_report: Dictionary) -> Array[AfterActionTurningPoint]:
	var merged: Dictionary = {}
	var source_points := source_report.get("causal_turning_points", []) as Array
	for value in source_points:
		var point := value as Dictionary
		if not _include_turning_point(point):
			continue
		_merge_turning_point(merged, point)
	if merged.size() < 3:
		for value in source_points:
			var point := value as Dictionary
			_merge_turning_point(merged, point)
			if merged.size() >= 3:
				break
	var ranked: Array[AfterActionTurningPoint] = []
	for value in merged.values():
		ranked.append(value as AfterActionTurningPoint)
	ranked.sort_custom(func(left: AfterActionTurningPoint, right: AfterActionTurningPoint) -> bool:
		if left.priority != right.priority:
			return left.priority > right.priority
		if left.first_tick != right.first_tick:
			return left.first_tick < right.first_tick
		return String(left.stable_id) < String(right.stable_id)
	)
	if ranked.size() > MAX_TURNING_POINTS:
		ranked.resize(MAX_TURNING_POINTS)
	ranked.sort_custom(func(left: AfterActionTurningPoint, right: AfterActionTurningPoint) -> bool:
		if left.first_tick != right.first_tick:
			return left.first_tick < right.first_tick
		return String(left.stable_id) < String(right.stable_id)
	)
	return ranked


func _include_turning_point(point: Dictionary) -> bool:
	var reason := String(point.get("reason_key", ""))
	if reason in [
		"battle_concluded", "building_destroyed", "region_control_changed",
		"first_high_level_order", "player_correction", "unit_card_takeover",
		"unit_card_return_result", "unit_card_loss", "supply_committed",
		"exception_opened", "exception_reopened", "exception_action",
		"tactical_action_started", "tactical_action_completed", "tactical_action_interrupted",
	]:
		return true
	if reason == "task_state_changed":
		var result := String(point.get("result", ""))
		return String(point.get("blocked_reason", "NONE")) != "NONE" or result.begins_with("COMPLETED") or result.begins_with("FAILED") or result.contains("RETREATING")
	return false


func _merge_turning_point(merged: Dictionary, point: Dictionary) -> void:
	if point.is_empty():
		return
	var tick := int(point.get("tick", 0))
	var reason := String(point.get("reason_key", "unknown"))
	var card_id := String(point.get("card_id", ""))
	var task_id := int(point.get("task_id", 0))
	var result := String(point.get("result", ""))
	var merge_key := _turning_point_merge_key(reason, card_id, task_id, result)
	if merged.has(merge_key):
		var existing := merged[merge_key] as AfterActionTurningPoint
		existing.last_tick = maxi(existing.last_tick, tick)
		existing.occurrences += 1
		return
	var stable_id := StringName("turn:%08d:%s" % [tick, merge_key.sha256_text().left(12)])
	merged[merge_key] = AfterActionTurningPoint.new(
		stable_id, tick, tick, String(point.get("actor_id", "")), StringName(card_id),
		task_id, StringName(reason), StringName(point.get("source_event", "")), result,
		1, _turning_point_priority(point)
	)


func _turning_point_merge_key(reason: String, card_id: String, task_id: int, result: String) -> String:
	if reason == "unit_card_loss":
		return "%s:%s" % [reason, card_id]
	if reason.begins_with("exception_"):
		return "%s:%s" % [reason, result]
	if reason == "region_control_changed":
		return "%s:%s" % [reason, result.get_slice(":", 0)]
	if reason == "task_state_changed":
		return "%s:%08d:%s" % [reason, task_id, result.get_slice(":", 0)]
	return "%s:%s:%08d:%s" % [reason, card_id, task_id, result]


func _turning_point_priority(point: Dictionary) -> int:
	var reason := String(point.get("reason_key", ""))
	match reason:
		"battle_concluded":
			return 100
		"building_destroyed":
			return 96
		"first_high_level_order":
			return 92
		"player_correction":
			return 90
		"region_control_changed":
			return 86
		"unit_card_return_result":
			return 84
		"unit_card_takeover":
			return 82
		"task_state_changed":
			return 80 if String(point.get("blocked_reason", "NONE")) != "NONE" else 72
		"unit_card_loss":
			return 76
		"exception_opened", "exception_reopened":
			return 74
		"exception_action":
			return 73
		"supply_committed":
			return 64
	return 40


func _build_card_contributions(source_report: Dictionary) -> Array[AfterActionCardContribution]:
	var result: Array[AfterActionCardContribution] = []
	for value in source_report.get("cards", []) as Array:
		var entry := AfterActionCardContribution.new(value as Dictionary)
		if not entry.unit_card_id.is_empty():
			result.append(entry)
	result.sort_custom(func(left: AfterActionCardContribution, right: AfterActionCardContribution) -> bool:
		return String(left.unit_card_id) < String(right.unit_card_id)
	)
	return result


func _build_causes(source_report: Dictionary, outcome: Dictionary) -> Array[AfterActionCause]:
	var result: Array[AfterActionCause] = []
	var reason_ids: Array[String] = []
	for value in outcome.get("reason_objective_ids", []) as Array:
		reason_ids.append(String(value))
	reason_ids.sort()
	result.append(AfterActionCause.new(
		&"cause:outcome", AfterActionCause.Role.PRIMARY, &"outcome",
		int(outcome.get("concluded_tick", source_report.get("final_tick", 0))),
		&"battle_outcome", &"AFTER_ACTION_CAUSE_OUTCOME", &"", 0,
		{
			"result": String(outcome.get("result", "in_progress")),
			"grade": String(outcome.get("grade", "none")),
			"conclusion_group_id": String(outcome.get("conclusion_group_id", "")),
			"reason_objective_ids": reason_ids,
		}
	))
	var supporting: Array[AfterActionCause] = []
	var blocked_task := _most_blocked_task(source_report)
	if not blocked_task.is_empty():
		var task_id := int(blocked_task.get("task_id", 0))
		supporting.append(AfterActionCause.new(
			StringName("cause:task:%08d" % task_id), AfterActionCause.Role.SUPPORTING,
			&"task_blocked", _latest_task_tick(source_report, task_id), &"task_snapshot",
			StringName(blocked_task.get("last_reason", "")), StringName(blocked_task.get("card_id", "")), task_id,
			{"blocked_count": int(blocked_task.get("blocked_count", 0)), "blocked_reason": String(blocked_task.get("last_reason", ""))}
		))
	var loss_card := _highest_loss_card(source_report)
	if not loss_card.is_empty():
		var card_id := StringName(loss_card.get("card_id", ""))
		supporting.append(AfterActionCause.new(
			StringName("cause:loss:%s" % card_id), AfterActionCause.Role.SUPPORTING,
			&"card_attrition", _latest_card_loss_tick(source_report, card_id), &"unit_destroyed",
			&"AFTER_ACTION_CAUSE_CARD_ATTRITION", card_id, 0,
			{"losses": int(loss_card.get("losses", 0)), "initial_strength": int(loss_card.get("initial_strength", 0)), "final_strength": int(loss_card.get("final_strength", 0))}
		))
	var unresolved := _first_unresolved_exception(source_report)
	if not unresolved.is_empty():
		supporting.append(AfterActionCause.new(
			StringName("cause:exception:%s" % unresolved.get("exception_id", "")), AfterActionCause.Role.SUPPORTING,
			&"unresolved_exception", int(unresolved.get("last_seen_tick", source_report.get("final_tick", 0))), &"command_situation",
			StringName(unresolved.get("reason_key", "")), StringName(unresolved.get("unit_card_id", "")), int(unresolved.get("task_id", 0)),
			{"exception_id": String(unresolved.get("exception_id", "")), "opened_count": int(unresolved.get("opened_count", 0)), "resolved_count": int(unresolved.get("resolved_count", 0))}
		))
	var task_summary := source_report.get("task_summary", {}) as Dictionary
	if int(task_summary.get("created", 0)) > 0 and int(task_summary.get("completed", 0)) == 0:
		supporting.append(AfterActionCause.new(
			&"cause:no_completed_tasks", AfterActionCause.Role.SUPPORTING,
			&"task_completion_shortfall", int(source_report.get("final_tick", 0)), &"task_summary",
			&"AFTER_ACTION_CAUSE_NO_COMPLETED_TASKS", &"", 0,
			{"created": int(task_summary.get("created", 0)), "completed": 0, "blocked": int(task_summary.get("blocked", 0))}
		))
	supporting.sort_custom(func(left: AfterActionCause, right: AfterActionCause) -> bool:
		return String(left.stable_id) < String(right.stable_id)
	)
	if supporting.size() > MAX_SUPPORTING_CAUSES:
		supporting.resize(MAX_SUPPORTING_CAUSES)
	result.append_array(supporting)
	return result


func _most_blocked_task(source_report: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for value in source_report.get("tasks", []) as Array:
		var task := value as Dictionary
		if int(task.get("blocked_count", 0)) > 0:
			candidates.append(task)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_count := int(left.get("blocked_count", 0))
		var right_count := int(right.get("blocked_count", 0))
		return left_count > right_count or left_count == right_count and int(left.get("task_id", 0)) < int(right.get("task_id", 0))
	)
	return {} if candidates.is_empty() else candidates[0]


func _highest_loss_card(source_report: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for value in source_report.get("cards", []) as Array:
		var card := value as Dictionary
		if int(card.get("losses", 0)) > 0:
			candidates.append(card)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_losses := int(left.get("losses", 0))
		var right_losses := int(right.get("losses", 0))
		return left_losses > right_losses or left_losses == right_losses and String(left.get("card_id", "")) < String(right.get("card_id", ""))
	)
	return {} if candidates.is_empty() else candidates[0]


func _first_unresolved_exception(source_report: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for value in source_report.get("exceptions", []) as Array:
		var exception := value as Dictionary
		if int(exception.get("opened_count", 0)) > int(exception.get("resolved_count", 0)):
			candidates.append(exception)
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_severity := int(left.get("severity", 0))
		var right_severity := int(right.get("severity", 0))
		return left_severity > right_severity or left_severity == right_severity and String(left.get("exception_id", "")) < String(right.get("exception_id", ""))
	)
	return {} if candidates.is_empty() else candidates[0]


func _latest_task_tick(source_report: Dictionary, task_id: int) -> int:
	var result := 0
	for value in source_report.get("task_transitions", []) as Array:
		var transition := value as Dictionary
		if int(transition.get("task_id", 0)) == task_id:
			result = maxi(result, int(transition.get("tick", 0)))
	return result


func _latest_card_loss_tick(source_report: Dictionary, card_id: StringName) -> int:
	var result := 0
	for value in source_report.get("causal_turning_points", []) as Array:
		var point := value as Dictionary
		if String(point.get("reason_key", "")) == "unit_card_loss" and StringName(point.get("card_id", "")) == card_id:
			result = maxi(result, int(point.get("tick", 0)))
	return result
