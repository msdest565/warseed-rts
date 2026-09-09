extends SceneTree

const REPORT_PATH := "res://artifacts/balance/grey_ridge_full_match_baseline.json"
const CASE_SCHEMA_ID := "warseed.gameplay_baseline.case.v1"
const FIXED_SEED := 1701
const OPENING_PLAN_IDS: Array[StringName] = [
	SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT,
	SimulationWorld.ENEMY_PLAN_WESTERN_HOOK,
	SimulationWorld.ENEMY_PLAN_WESTERN_FEINT,
]
const SUCCESS_STRATEGY_IDS: Array[StringName] = [&"split_axis", &"concentrated_attack"]
const INFERIOR_STRATEGY_IDS: Array[StringName] = [&"recon_then_commit", &"reserve_policy", &"no_intervention"]


func _initialize() -> void:
	var failures: Array[String] = []
	var cases: Array[Dictionary] = []
	var repeat_fingerprints: Array[Dictionary] = []
	var selected_plan_ids := _selected_ids(OPENING_PLAN_IDS, "WARSEED_PLAN_FILTER")
	var selected_strategy_ids := _selected_ids(GreyRidgeBaselineStrategy.STRATEGY_IDS, "WARSEED_STRATEGY_FILTER")
	var repeat_count := clampi(int(OS.get_environment("WARSEED_REPEAT_COUNT")), 1, 2) if not OS.get_environment("WARSEED_REPEAT_COUNT").is_empty() else 2
	if selected_plan_ids.is_empty():
		failures.append("WARSEED_PLAN_FILTER did not select an allowed plan")
	if selected_strategy_ids.is_empty():
		failures.append("WARSEED_STRATEGY_FILTER did not select an allowed strategy")
	for plan_id in selected_plan_ids:
		for strategy_id in selected_strategy_ids:
			var first := _run_case(plan_id, strategy_id, failures)
			var second := _run_case(plan_id, strategy_id, failures) if repeat_count == 2 else first
			var first_json := GameplayObservabilityReport.canonical_json(first)
			var second_json := GameplayObservabilityReport.canonical_json(second)
			var key := "%s/%s" % [strategy_id, plan_id]
			var matches: bool = first_json == second_json and first.get("fingerprint", "") == second.get("fingerprint", "")
			if not matches:
				failures.append("%s produced nondeterministic full-match reports" % key)
			cases.append(first)
			repeat_fingerprints.append({"case_id": key, "fingerprint": first.get("fingerprint", ""), "repeat_match": matches})
			print("WARSEED_FULL_MATCH %s tick=%d outcome=%s fingerprint=%s" % [key, first.get("final_tick", -1), (first.get("outcome", {}) as Dictionary).get("result", "unknown"), first.get("fingerprint", "")])
	var expected_case_count := selected_plan_ids.size() * selected_strategy_ids.size()
	if cases.size() != expected_case_count:
		failures.append("full-match matrix produced %d/%d required cases" % [cases.size(), expected_case_count])
	for case_index in range(cases.size()):
		var case_report := cases[case_index]
		if case_report.is_empty() or String(case_report.get("schema_id", "")) != CASE_SCHEMA_ID:
			failures.append("full-match matrix case %d is empty or has an invalid schema" % case_index)
	var quality_audit := _audit_strategy_quality(cases, selected_plan_ids, selected_strategy_ids, failures)
	var report := {
		"format_version": 1,
		"schema_id": "warseed.grey_ridge_full_match_baseline.v1",
		"evidence_level": GameplayObservabilityReport.EVIDENCE_LEVEL,
		"scenario_id": "grey_ridge",
		"fixed_seed": FIXED_SEED,
		"tick_rate_hz": roundi(1.0 / SimulationWorld.TICK_SECONDS),
		"enemy_plan_ids": _strings(selected_plan_ids),
		"strategy_ids": _strings(selected_strategy_ids),
		"case_count": cases.size(),
		"repeat_count_per_case": repeat_count,
		"determinism_passed": failures.is_empty(),
		"repeat_fingerprints": repeat_fingerprints,
		"quality_audit": quality_audit,
		"interpretation_boundary": "Automated full-match evidence compares strategy outcomes and causal completeness; it does not establish human comprehension or subjective fun.",
		"cases": cases,
		"failures": failures,
	}
	var canonical_without_fingerprint := GameplayObservabilityReport.canonical_json(report)
	report["fingerprint"] = canonical_without_fingerprint.sha256_text()
	if not _save_report(report):
		failures.append("could not write normalized baseline report to %s" % REPORT_PATH)
	if failures.is_empty():
		print("WARSEED Grey Ridge full-match baseline passed: %d strategies x %d plans x %d deterministic runs; report=%s" % [selected_strategy_ids.size(), selected_plan_ids.size(), repeat_count, REPORT_PATH])
		quit(0)
		return
	for failure in failures:
		push_error("FULL MATCH BASELINE FAILED: %s" % failure)
	quit(1)


func _run_case(plan_id: StringName, strategy_id: StringName, failures: Array[String]) -> Dictionary:
	if not OPENING_PLAN_IDS.has(plan_id):
		failures.append("unknown Grey Ridge opening plan: %s" % plan_id)
		return {}
	if not GreyRidgeBaselineStrategy.STRATEGY_IDS.has(strategy_id):
		failures.append("unknown Grey Ridge baseline strategy: %s" % strategy_id)
		return {}
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, plan_id)
	var max_ticks := world.battle_definition.time_limit_ticks
	var observer := GameplayObservabilityReport.new(&"grey_ridge", plan_id, strategy_id, FIXED_SEED, SimulationWorld.LOCAL_PLAYER_ID, max_ticks)
	var strategy := GreyRidgeBaselineStrategy.new()
	var issued_actions: Dictionary = {}
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	if not observer.start(snapshot):
		failures.append("%s/%s recorder rejected initial faction snapshot: %s" % [strategy_id, plan_id, observer.illegal_input_reason])
	var event_cursor := 0
	observer.observe(snapshot, _event_slice(world.events, event_cursor))
	observer.observe_command_situation(_command_situation(world, snapshot))
	event_cursor = world.events.size()
	while not snapshot.outcome.is_terminal() and world.current_tick < max_ticks:
		var intents := strategy.decide(strategy_id, snapshot, issued_actions)
		if not strategy.last_rejection_reason.is_empty():
			failures.append("%s/%s strategy observation rejected: %s" % [strategy_id, plan_id, strategy.last_rejection_reason])
			break
		for intent in intents:
			var action_key := String(intent.get("action_key", ""))
			var command := _command_for_intent(world, snapshot, intent)
			if command == null:
				failures.append("%s/%s could not build action %s" % [strategy_id, plan_id, action_key])
				issued_actions[action_key] = false
				continue
			var validation := world.submit_command(command)
			observer.record_command(command, validation, intent)
			issued_actions[action_key] = validation.is_accepted()
			if not validation.is_accepted():
				failures.append("%s/%s action %s rejected: %s" % [strategy_id, plan_id, action_key, validation.describe()])
		snapshot = world.advance_tick()
		observer.observe(snapshot, _event_slice(world.events, event_cursor))
		if snapshot.tick % 10 == 0 or snapshot.outcome.is_terminal():
			observer.observe_command_situation(_command_situation(world, snapshot))
		event_cursor = world.events.size()
	observer.finish(snapshot)
	var result := observer.create_report()
	if world.enemy_opening_plan_id != plan_id:
		failures.append("%s/%s changed its locked enemy plan" % [strategy_id, plan_id])
	if not snapshot.outcome.is_terminal():
		failures.append("%s/%s did not reach an authoritative outcome by tick %d" % [strategy_id, plan_id, max_ticks])
	if strategy_id != &"no_intervention" and (result.get("first_high_level_order", {}) as Dictionary).is_empty():
		failures.append("%s/%s did not issue an accepted high-level order" % [strategy_id, plan_id])
	if not bool(result.get("legal_observation_only", false)):
		failures.append("%s/%s consumed an illegal observation: %s" % [strategy_id, plan_id, result.get("illegal_input_reason", "")])
	for log_entry in world.enemy_reaction_log:
		if not log_entry.contains("source=LOCKED_OPENING_PLAN") and not log_entry.contains("source=LOCKED_PLAN_TIMELINE") and not log_entry.contains("source=LEGAL_FACTION_OBSERVATION"):
			failures.append("%s/%s produced unaudited hostile logic: %s" % [strategy_id, plan_id, log_entry])
			break
	return result


func _command_for_intent(world: SimulationWorld, snapshot: WorldSnapshot, intent: Dictionary) -> GameCommand:
	match String(intent.get("action", "")):
		"deploy":
			return DeployUnitCardCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, intent.get("card_id", &"") as StringName, intent.get("position", Vector2.ZERO) as Vector2)
		"objective":
			return CommanderOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, intent.get("actor_id", &"") as StringName, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, intent.get("position", Vector2.ZERO) as Vector2, intent.get("region_id", &"") as StringName)
		"posture":
			return CommanderOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, intent.get("actor_id", &"") as StringName, CommanderOrderCommand.OrderKind.SET_POSTURE, Vector2.ZERO, &"", int(intent.get("posture", CommanderState.Posture.BALANCED)) as CommanderState.Posture)
		"air_recon":
			return SupportOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, SupportOrderCommand.SupportKind.AIR_RECON, intent.get("primary_region_id", &"") as StringName, intent.get("secondary_region_id", &"") as StringName)
		"support":
			return SupportOrderCommand.new(
				world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
				world.current_tick, int(intent.get("support_kind", SupportOrderCommand.SupportKind.AIR_RECON)) as SupportOrderCommand.SupportKind,
				intent.get("primary_region_id", &"") as StringName, intent.get("secondary_region_id", &"") as StringName,
				intent.get("card_id", &"") as StringName
			)
		"card_control":
			return UnitCardControlCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, intent.get("card_id", &"") as StringName, int(intent.get("control_action", UnitCardControlCommand.Action.TAKEOVER)) as UnitCardControlCommand.Action)
		"formation_move":
			var card := snapshot.get_unit_card(intent.get("card_id", &"") as StringName)
			if card == null:
				return null
			var formation := snapshot.get_formation(card.formation_id)
			if formation == null:
				return null
			var formation_state := world.formations.get(card.formation_id) as FormationState
			if formation_state == null:
				return null
			var resolved_position := world.find_formation_deployment_position(formation_state, intent.get("position", Vector2.ZERO) as Vector2, 384.0)
			if not resolved_position.is_finite():
				resolved_position = formation.anchor_position
			return FormationMoveCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, formation.leader_entity_id, formation.formation_id, resolved_position)
		"formation_attack_move":
			var card := snapshot.get_unit_card(intent.get("card_id", &"") as StringName)
			if card == null:
				return null
			var formation := snapshot.get_formation(card.formation_id)
			if formation == null:
				return null
			var formation_state := world.formations.get(card.formation_id) as FormationState
			if formation_state == null:
				return null
			var route_points := intent.get("route_points", PackedVector2Array()) as PackedVector2Array
			var resolved_position := world.find_formation_deployment_position(formation_state, intent.get("position", Vector2.ZERO) as Vector2, 256.0, route_points)
			if not resolved_position.is_finite():
				resolved_position = formation.anchor_position
			return AttackMoveCommand.new(
				world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
				world.current_tick, formation.leader_entity_id, formation.formation_id, resolved_position, route_points
			)
		"formation_attack":
			var card := snapshot.get_unit_card(intent.get("card_id", &"") as StringName)
			if card == null:
				return null
			var formation := snapshot.get_formation(card.formation_id)
			if formation == null:
				return null
			return AttackCommand.new(
				world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
				world.current_tick, formation.leader_entity_id, int(intent.get("target_entity_id", 0)), formation.formation_id
			)
	return null


func _event_slice(events: Array[SimulationEvent], start: int) -> Array[SimulationEvent]:
	var result: Array[SimulationEvent] = []
	for index in range(start, events.size()):
		result.append(events[index])
	return result


func _command_situation(world: SimulationWorld, snapshot: WorldSnapshot) -> CommandSituationSnapshot:
	var support_costs := {}
	for support in world.battle_definition.support_abilities:
		support_costs[String(support.support_id)] = support.supply_cost
	var situation := BattlefieldSituationProjector.new().project(
		snapshot, SimulationWorld.LOCAL_PLAYER_ID, world.battle_definition.battlefield_bounds,
		world.battle_definition.base_supply_interval_ticks,
		world.battle_definition.region_settlement_interval_ticks, support_costs
	)
	return CommandSituationProjector.new().project(snapshot, situation, SimulationWorld.LOCAL_PLAYER_ID)


func _save_report(report: Dictionary) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(REPORT_PATH.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(GameplayObservabilityReport.canonical_json(report, "\t"))
	file.close()
	return true


func _strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result


func _selected_ids(allowed_ids: Array[StringName], environment_key: String) -> Array[StringName]:
	var requested := OS.get_environment(environment_key).strip_edges()
	if requested.is_empty():
		return allowed_ids.duplicate()
	var selected: Array[StringName] = []
	for raw_id in requested.split(",", false):
		var requested_id := StringName(raw_id.strip_edges())
		if allowed_ids.has(requested_id) and not selected.has(requested_id):
			selected.append(requested_id)
	if selected.is_empty():
		push_error("%s did not contain an allowed id" % environment_key)
	return selected


func _audit_strategy_quality(
	cases: Array[Dictionary],
	selected_plan_ids: Array[StringName],
	selected_strategy_ids: Array[StringName],
	failures: Array[String]
) -> Dictionary:
	var profiles: Dictionary = {}
	for strategy_id in selected_strategy_ids:
		profiles[String(strategy_id)] = _strategy_profile(cases, strategy_id)
	var runs_full_gate := selected_plan_ids == OPENING_PLAN_IDS and selected_strategy_ids == GreyRidgeBaselineStrategy.STRATEGY_IDS
	if not runs_full_gate:
		return {
			"status": "DIAGNOSTIC_ONLY",
			"full_matrix_required": true,
			"profiles": profiles,
		}
	var failure_count_before := failures.size()
	for strategy_id in SUCCESS_STRATEGY_IDS:
		for plan_id in OPENING_PLAN_IDS:
			var report := _case_report(cases, strategy_id, plan_id)
			_expect_quality(not report.is_empty(), "%s/%s is missing from the quality matrix" % [strategy_id, plan_id], failures)
			if report.is_empty():
				continue
			var outcome := report.get("outcome", {}) as Dictionary
			_expect_quality(String(outcome.get("result", "")) == "victory" and String(outcome.get("conclusion_group_id", "")) == "headquarters_victory", "%s/%s must reach headquarters victory" % [strategy_id, plan_id], failures)
			_expect_quality(int((report.get("command_summary", {}) as Dictionary).get("rejected", 0)) == 0, "%s/%s must not reject strategy commands" % [strategy_id, plan_id], failures)
			_expect_quality(int((report.get("command_summary", {}) as Dictionary).get("player_corrections", 0)) <= 2, "%s/%s exceeds the correction budget" % [strategy_id, plan_id], failures)
			_expect_quality(int((report.get("command_summary", {}) as Dictionary).get("accepted", 0)) >= 7, "%s/%s lacks a complete command sequence" % [strategy_id, plan_id], failures)
			_expect_quality(_has_causal_reason(report, "building_destroyed") and _has_causal_reason(report, "battle_concluded"), "%s/%s lacks headquarters-destruction or conclusion causality" % [strategy_id, plan_id], failures)
			_expect_quality(_tasks_have_coherent_terminal_reasons(report), "%s/%s contains a blocked or terminal task without a reason" % [strategy_id, plan_id], failures)
			var first_order := report.get("first_high_level_order", {}) as Dictionary
			_expect_quality(not first_order.is_empty() and int(first_order.get("tick", 999999)) <= 300, "%s/%s did not issue a timely high-level order" % [strategy_id, plan_id], failures)
			if strategy_id == &"split_axis":
				_expect_quality(_has_command_reason(report, "split_axis_fire_support") and _has_command_reason(report, "split_axis_western_exploitation") and (_has_command_reason(report, "split_axis_headquarters_assault") or _has_command_reason(report, "split_axis_reserve_headquarters_assault")), "%s/%s lacks the split shaping-to-exploitation chain" % [strategy_id, plan_id], failures)
				_expect_quality(_cards_contribute_and_survive(report, [&"thunder_fire_group", &"armored_spearhead"]), "%s/%s lacks a surviving decisive split-axis card contribution" % [strategy_id, plan_id], failures)
			else:
				_expect_quality(_has_command_reason(report, "concentrated_reserve_commit") and _has_command_reason(report, "concentrated_main_effort") and _has_command_reason(report, "concentrated_vanguard_control") and _has_command_reason(report, "concentrated_headquarters_breakthrough"), "%s/%s lacks the concentrated mass-and-breakthrough chain" % [strategy_id, plan_id], failures)
				_expect_quality(_cards_contribute_and_survive(report, [&"ironwall_assault_group", &"armored_spearhead"]), "%s/%s lacks a surviving decisive concentrated card contribution" % [strategy_id, plan_id], failures)
	for strategy_id in INFERIOR_STRATEGY_IDS:
		for plan_id in OPENING_PLAN_IDS:
			var report := _case_report(cases, strategy_id, plan_id)
			_expect_quality(not report.is_empty(), "%s/%s is missing from the inferior-strategy matrix" % [strategy_id, plan_id], failures)
			if report.is_empty():
				continue
			var outcome := report.get("outcome", {}) as Dictionary
			_expect_quality(String(outcome.get("result", "")) == "defeat", "%s/%s must remain a stable inferior-strategy defeat" % [strategy_id, plan_id], failures)
			_expect_quality(not String(outcome.get("conclusion_group_id", "")).is_empty() and not (outcome.get("reason_objective_ids", []) as Array).is_empty(), "%s/%s must retain an authoritative defeat reason" % [strategy_id, plan_id], failures)
			if strategy_id == &"no_intervention":
				_expect_quality(int((report.get("command_summary", {}) as Dictionary).get("accepted", -1)) == 0, "%s/%s must remain a true zero-command control" % [strategy_id, plan_id], failures)
			else:
				var first_order := report.get("first_high_level_order", {}) as Dictionary
				_expect_quality(not first_order.is_empty() and int(first_order.get("tick", 999999)) <= 300, "%s/%s lacks its active inferior high-level order" % [strategy_id, plan_id], failures)
				if strategy_id == &"recon_then_commit":
					_expect_quality(_has_command_reason(report, "recon_before_commitment") and _has_command_reason(report, "commit_after_visible_intel"), "%s/%s no longer represents reconnaissance followed by commitment" % [strategy_id, plan_id], failures)
				elif strategy_id == &"reserve_policy":
					_expect_quality(_has_command_reason(report, "preserve_reserve") and _has_command_reason(report, "forward_defense_with_reserve") and _has_command_reason(report, "reserve_triggered_by_legal_observation"), "%s/%s no longer represents a static defense with delayed reserve commitment" % [strategy_id, plan_id], failures)
	var split_profile := profiles.get("split_axis", {}) as Dictionary
	var concentrated_profile := profiles.get("concentrated_attack", {}) as Dictionary
	_expect_quality(int(concentrated_profile.get("total_supply_committed", 0)) < int(split_profile.get("total_supply_committed", 0)), "concentrated_attack must retain the Supply-efficiency advantage", failures)
	_expect_quality(int(split_profile.get("total_surviving_strength", 0)) > int(concentrated_profile.get("total_surviving_strength", 0)), "split_axis must retain the force-preservation advantage", failures)
	return {
		"status": "PASS" if failures.size() == failure_count_before else "FAIL",
		"full_matrix_required": true,
		"successful_strategy_ids": _strings(SUCCESS_STRATEGY_IDS),
		"inferior_strategy_ids": _strings(INFERIOR_STRATEGY_IDS),
		"profiles": profiles,
	}


func _strategy_profile(cases: Array[Dictionary], strategy_id: StringName) -> Dictionary:
	var wins := 0
	var defeats := 0
	var final_tick_total := 0
	var total_supply := 0
	var total_losses := 0
	var total_survivors := 0
	var total_corrections := 0
	var case_count := 0
	for report in cases:
		if StringName(report.get("strategy_id", "")) != strategy_id:
			continue
		case_count += 1
		var outcome := report.get("outcome", {}) as Dictionary
		if String(outcome.get("result", "")) == "victory":
			wins += 1
		elif String(outcome.get("result", "")) == "defeat":
			defeats += 1
		final_tick_total += int(report.get("final_tick", 0))
		total_supply += int((report.get("supply_summary", {}) as Dictionary).get("total_committed", 0))
		total_corrections += int((report.get("command_summary", {}) as Dictionary).get("player_corrections", 0))
		for card_variant in report.get("cards", []):
			var card := card_variant as Dictionary
			total_losses += int(card.get("losses", 0))
			total_survivors += int(card.get("final_strength", 0))
	return {
		"case_count": case_count,
		"wins": wins,
		"defeats": defeats,
		"mean_final_tick": float(final_tick_total) / float(case_count) if case_count > 0 else 0.0,
		"total_supply_committed": total_supply,
		"total_losses": total_losses,
		"total_surviving_strength": total_survivors,
		"total_corrections": total_corrections,
	}


func _case_report(cases: Array[Dictionary], strategy_id: StringName, plan_id: StringName) -> Dictionary:
	for report in cases:
		if StringName(report.get("strategy_id", "")) == strategy_id and StringName(report.get("enemy_plan_id", "")) == plan_id:
			return report
	return {}


func _has_command_reason(report: Dictionary, reason_key: String) -> bool:
	for command_variant in report.get("commands", []):
		if String((command_variant as Dictionary).get("reason_key", "")) == reason_key:
			return true
	return false


func _has_causal_reason(report: Dictionary, reason_key: String) -> bool:
	for point_variant in report.get("causal_turning_points", []):
		if String((point_variant as Dictionary).get("reason_key", "")) == reason_key:
			return true
	return false


func _cards_contribute_and_survive(report: Dictionary, decisive_card_ids: Array[StringName]) -> bool:
	var combined_damage := 0.0
	var has_survivor := false
	for card_variant in report.get("cards", []):
		var card := card_variant as Dictionary
		if not decisive_card_ids.has(StringName(card.get("card_id", ""))):
			continue
		combined_damage += float(card.get("damage_dealt", 0.0))
		has_survivor = has_survivor or int(card.get("final_strength", 0)) > 0
	return combined_damage >= 1500.0 and has_survivor


func _tasks_have_coherent_terminal_reasons(report: Dictionary) -> bool:
	for task_variant in report.get("tasks", []):
		var task := task_variant as Dictionary
		if String(task.get("final_lifecycle", "")) in ["BLOCKED", "FAILED", "CANCELLED"] and String(task.get("last_reason", "")).is_empty():
			return false
	return true


func _expect_quality(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("QUALITY: %s" % message)
