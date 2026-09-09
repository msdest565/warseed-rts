class_name TestGameplayObservability
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_report_contract_and_determinism(failures)
	_test_strategy_knowledge_boundary(failures)
	_test_strategy_headquarters_target_requires_visible_snapshot(failures)
	_test_rejection_contract(failures)
	return failures


func _test_report_contract_and_determinism(failures: Array[String]) -> void:
	var first := _build_observed_fixture(failures)
	var second := _build_observed_fixture(failures)
	_expect(not first.is_empty(), "gameplay report fixture should produce a report", failures)
	_expect(GameplayObservabilityReport.canonical_json(first) == GameplayObservabilityReport.canonical_json(second), "identical observed command and event streams must serialize byte-equivalently", failures)
	_expect(String(first.get("fingerprint", "")) == String(second.get("fingerprint", "")), "identical observed command and event streams must preserve the same fingerprint", failures)
	_expect(String(first.get("schema_id", "")) == "warseed.gameplay_baseline.case.v1" and String(first.get("evidence_level", "")) == "SIMULATED", "gameplay report should identify its stable schema and evidence boundary", failures)
	_expect(bool(first.get("legal_observation_only", false)), "gameplay report fixture should consume only faction-legal snapshots", failures)
	_expect(not (first.get("first_high_level_order", {}) as Dictionary).is_empty(), "gameplay report should preserve the first accepted high-level order", failures)
	var command_summary := first.get("command_summary", {}) as Dictionary
	_expect(int(command_summary.get("accepted", 0)) >= 4 and int(command_summary.get("rejected", 0)) == 0, "gameplay report should distinguish accepted and rejected commands", failures)
	var task_summary := first.get("task_summary", {}) as Dictionary
	_expect(int(task_summary.get("created", 0)) > 0, "gameplay report should preserve Agent task creation", failures)
	var supply_summary := first.get("supply_summary", {}) as Dictionary
	_expect(int(supply_summary.get("total_committed", 0)) > 0, "gameplay report should preserve applied Supply commitments", failures)
	var control_summary := first.get("control_summary", {}) as Dictionary
	_expect(int(control_summary.get("takeovers", 0)) == 1, "gameplay report should preserve whole-card takeover sessions", failures)
	var cards := first.get("cards", []) as Array
	_expect(cards.size() == 4 and _has_card_contribution_fields(cards), "gameplay report should preserve a contribution record for every friendly card", failures)
	for point_variant in first.get("causal_turning_points", []):
		var point := point_variant as Dictionary
		_expect(_has_required_causal_fields(point), "every causal turning point should carry tick, actor/card/task, reason, source, and result", failures)


func _build_observed_fixture(failures: Array[String]) -> Dictionary:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT)
	var report := GameplayObservabilityReport.new(&"grey_ridge", world.enemy_opening_plan_id, &"fixture", 1701, SimulationWorld.LOCAL_PLAYER_ID, world.battle_definition.time_limit_ticks)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	_expect(report.start(snapshot), "gameplay report should accept the player's faction snapshot", failures)
	var event_cursor := 0
	report.observe(snapshot, _event_slice(world.events, event_cursor))
	event_cursor = world.events.size()

	var commands: Array[Dictionary] = [
		{
			"command": CommanderOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, &"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"),
			"descriptor": {"category": "commander", "action": "objective", "actor_id": "di_tian", "reason_key": "fixture_order"},
		},
		{
			"command": DeployUnitCardCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, &"thunder_fire_group", world.battle_definition.player_headquarters_position + Vector2(-192.0, -64.0)),
			"descriptor": {"category": "unit_card", "action": "deploy", "card_id": "thunder_fire_group", "reason_key": "fixture_deployment"},
		},
		{
			"command": UnitCardControlCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, &"ironwall_assault_group", UnitCardControlCommand.Action.TAKEOVER),
			"descriptor": {"category": "unit_card", "action": "card_control", "card_id": "ironwall_assault_group", "reason_key": "fixture_takeover"},
		},
	]
	for item in commands:
		var command := item["command"] as GameCommand
		var validation := world.submit_command(command)
		report.record_command(command, validation, item["descriptor"] as Dictionary)
		_expect(validation.is_accepted(), "observability fixture command should be accepted: %s" % validation.describe(), failures)
	snapshot = world.advance_tick()
	report.observe(snapshot, _event_slice(world.events, event_cursor))
	event_cursor = world.events.size()

	var return_command := UnitCardControlCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, &"ironwall_assault_group", UnitCardControlCommand.Action.RETURN_TO_COMMANDER)
	var return_validation := world.submit_command(return_command)
	report.record_command(return_command, return_validation, {"category": "unit_card", "action": "card_control", "card_id": "ironwall_assault_group", "reason_key": "fixture_return"})
	_expect(return_validation.is_accepted(), "observability fixture return command should be accepted", failures)
	for _tick in range(8):
		snapshot = world.advance_tick()
		report.observe(snapshot, _event_slice(world.events, event_cursor))
		event_cursor = world.events.size()
	report.finish(snapshot)
	return report.create_report()


func _test_strategy_knowledge_boundary(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT)
	var before := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var enemy_unit := world.units[1001] as UnitState
	var original_position := enemy_unit.position
	var original_health := enemy_unit.health
	enemy_unit.position = Vector2(5900.0, 300.0)
	enemy_unit.health = 1.0
	var after := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var first_agent := GreyRidgeBaselineStrategy.new()
	var second_agent := GreyRidgeBaselineStrategy.new()
	var first_intents := first_agent.decide(&"reserve_policy", before, {})
	var second_intents := second_agent.decide(&"reserve_policy", after, {})
	_expect(_intent_fingerprint(first_intents) == _intent_fingerprint(second_intents), "strategy output must not change when only hidden enemy true state changes", failures)
	_expect(before.get_building(SimulationWorld.ENEMY_COMMAND_CENTER_ID) == null and before.get_faction(SimulationWorld.ENEMY_PLAYER_ID).supply == 0, "strategy observation must redact hidden headquarters and private enemy Supply", failures)
	var forbidden_agent := GreyRidgeBaselineStrategy.new()
	_expect(forbidden_agent.decide(&"reserve_policy", world.create_true_state_snapshot(), {}).is_empty() and forbidden_agent.last_rejection_reason == "TRUE_STATE_FORBIDDEN", "strategy agent must reject diagnostic true-state snapshots", failures)
	var forbidden_report := GameplayObservabilityReport.new()
	_expect(not forbidden_report.start(world.create_true_state_snapshot()) and forbidden_report.illegal_input_reason == "TRUE_STATE_FORBIDDEN", "runtime gameplay recorder must reject diagnostic true-state snapshots", failures)
	enemy_unit.position = original_position
	enemy_unit.health = original_health


func _test_strategy_headquarters_target_requires_visible_snapshot(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT)
	world.current_tick = 500
	var issued := {
		"deploy_armor": true,
		"di_aggressive": true,
		"di_central": true,
		"bai_central": true,
		"takeover_ironwall": true,
		"advance_ironwall": true,
	}
	var strategy := GreyRidgeBaselineStrategy.new()
	var hidden_intents := strategy.decide(&"concentrated_attack", world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID), issued)
	_expect(not _has_formation_attack_intent(hidden_intents), "strategy must not target an unobserved enemy headquarters", failures)
	var ironwall := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var formation := world.formations[ironwall.formation_id] as FormationState
	var headquarters := world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState
	formation.anchor_position = headquarters.position + Vector2(0.0, 192.0)
	for entity_id in ironwall.member_entity_ids:
		var member := world.units[entity_id] as UnitState
		member.position = formation.anchor_position
	world._update_faction_knowledge()
	var visible_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var visible_headquarters := visible_snapshot.get_building(SimulationWorld.ENEMY_COMMAND_CENTER_ID)
	_expect(visible_headquarters != null and visible_headquarters.is_visible, "fixture must reveal the headquarters through legal faction vision", failures)
	var visible_intents := strategy.decide(&"concentrated_attack", visible_snapshot, issued)
	_expect(_formation_attack_target(visible_intents) == SimulationWorld.ENEMY_COMMAND_CENTER_ID, "strategy may target the headquarters only after its ID appears in the legal snapshot", failures)


func _test_rejection_contract(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var strategy := GreyRidgeBaselineStrategy.new()
	_expect(strategy.decide(&"unknown", world.create_snapshot(), {}).is_empty() and strategy.last_rejection_reason == "UNKNOWN_STRATEGY_ID", "unknown baseline strategy ids must fail explicitly", failures)
	var wrong_observer := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	_expect(strategy.decide(&"split_axis", wrong_observer, {}).is_empty() and strategy.last_rejection_reason == "WRONG_OBSERVER_FACTION", "player baseline strategy must reject another faction's observation", failures)


func _event_slice(events: Array[SimulationEvent], start: int) -> Array[SimulationEvent]:
	var result: Array[SimulationEvent] = []
	for index in range(start, events.size()):
		result.append(events[index])
	return result


func _has_required_causal_fields(point: Dictionary) -> bool:
	for key in ["tick", "actor_id", "card_id", "task_id", "reason_key", "source_event", "result"]:
		if not point.has(key):
			return false
	return true


func _has_card_contribution_fields(cards: Array) -> bool:
	for card_variant in cards:
		var card := card_variant as Dictionary
		for key in ["initial_strength", "peak_strength", "final_strength", "losses", "damage_dealt", "damage_taken", "kills", "tasks_completed", "tasks_blocked"]:
			if not card.has(key):
				return false
	return true


func _intent_fingerprint(intents: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for intent in intents:
		parts.append("%s:%s:%s:%s" % [intent.get("action_key", ""), intent.get("action", ""), intent.get("actor_id", ""), intent.get("card_id", "")])
	return "|".join(parts).sha256_text()


func _has_formation_attack_intent(intents: Array[Dictionary]) -> bool:
	return _formation_attack_target(intents) != 0


func _formation_attack_target(intents: Array[Dictionary]) -> int:
	for intent in intents:
		if String(intent.get("action", "")) == "formation_attack":
			return int(intent.get("target_entity_id", 0))
	return 0


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
