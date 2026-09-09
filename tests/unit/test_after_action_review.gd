class_name TestAfterActionReview
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_projection_contract(failures)
	_test_rejection_and_value_copy(failures)
	_test_live_host_capture(failures)
	_test_hidden_building_event_filter(failures)
	return failures


func _test_projection_contract(failures: Array[String]) -> void:
	var source := _signed_source_report()
	var first_projector := AfterActionReviewProjector.new()
	var second_projector := AfterActionReviewProjector.new()
	var first := first_projector.project(source, SimulationWorld.LOCAL_PLAYER_ID)
	var second := second_projector.project(source, SimulationWorld.LOCAL_PLAYER_ID)
	_expect(first != null and second != null, "signed legal reports should produce an after-action review", failures)
	if first == null or second == null:
		return
	_expect(first.turning_points.size() >= 3 and first.turning_points.size() <= 7, "after-action review should select three to seven turning points", failures)
	_expect(first.fingerprint() == second.fingerprint(), "identical reports should produce the same after-action fingerprint", failures)
	_expect(GameplayObservabilityReport.canonical_json(first.to_dictionary()) == GameplayObservabilityReport.canonical_json(second.to_dictionary()), "identical reviews should serialize byte-equivalently", failures)
	var loss_entry: AfterActionTurningPoint
	for entry in first.turning_points:
		if entry.reason_key == &"unit_card_loss":
			loss_entry = entry
	_expect(loss_entry != null and loss_entry.occurrences == 3 and loss_entry.first_tick == 120 and loss_entry.last_tick == 140, "repeated losses from one card should collapse into one traceable interval", failures)
	_expect(first.card_contributions.size() == 2 and first.card_contributions[0].unit_card_id == &"falcon_recon_group" and first.card_contributions[1].unit_card_id == &"ironwall_assault_group", "card contributions should preserve stable card ordering", failures)
	var ironwall := first.card_contributions[1]
	_expect(ironwall.losses == 3 and ironwall.damage_dealt == 810.0 and ironwall.tasks_blocked == 2, "card contribution should preserve measured losses, damage, and task facts", failures)
	_expect(first.causes.size() >= 3 and first.causes[0].role == AfterActionCause.Role.PRIMARY and first.causes[0].facts.get("conclusion_group_id", "") == "collapse", "cause chain should begin with the authoritative outcome", failures)
	var source_ids: Dictionary = {}
	for point in source.get("causal_turning_points", []) as Array:
		source_ids[String(point.get("reason_key", ""))] = true
	for entry in first.turning_points:
		_expect(source_ids.has(String(entry.reason_key)), "every selected turning point should cite a source report fact", failures)


func _test_rejection_and_value_copy(failures: Array[String]) -> void:
	var source := _signed_source_report()
	var projector := AfterActionReviewProjector.new()
	var review := projector.project(source, SimulationWorld.LOCAL_PLAYER_ID)
	var copied := review.duplicate_review() if review != null else null
	if review != null and copied != null:
		review.turning_points[0].result = "mutated"
		review.card_contributions[0].losses = 999
		review.causes[0].facts["result"] = "mutated"
		_expect(copied.turning_points[0].result != "mutated" and copied.card_contributions[0].losses != 999 and copied.causes[0].facts.get("result", "") == "defeat", "after-action snapshots should be deep value copies", failures)
	var tampered := source.duplicate(true)
	(tampered.get("outcome", {}) as Dictionary)["result"] = "victory"
	_expect(projector.project(tampered, SimulationWorld.LOCAL_PLAYER_ID) == null and projector.last_rejection_reason == &"SOURCE_FINGERPRINT_MISMATCH", "tampered source reports should fail closed", failures)
	var wrong_faction := source.duplicate(true)
	wrong_faction["observer_faction_id"] = SimulationWorld.ENEMY_PLAYER_ID
	_resign(wrong_faction)
	_expect(projector.project(wrong_faction, SimulationWorld.LOCAL_PLAYER_ID) == null and projector.last_rejection_reason == &"WRONG_OBSERVER_FACTION", "wrong-faction reports should be rejected", failures)
	var illegal := source.duplicate(true)
	illegal["legal_observation_only"] = false
	_resign(illegal)
	_expect(projector.project(illegal, SimulationWorld.LOCAL_PLAYER_ID) == null and projector.last_rejection_reason == &"ILLEGAL_OBSERVATION_SOURCE", "reports derived from illegal observations should be rejected", failures)


func _test_live_host_capture(failures: Array[String]) -> void:
	var host := SimulationHost.new()
	host.scenario_kind = SimulationWorld.ScenarioKind.GREY_RIDGE
	host.world = SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT)
	host.current_snapshot = host.world.create_snapshot()
	host.previous_snapshot = host.current_snapshot
	host._grey_ridge_battle_started = true
	host._start_playtest_session()
	var command := host.create_high_level_intent_command(
		&"di_tian", &"central_relay", &"central_relay",
		CommanderState.Posture.BALANCED, CommanderState.ReservePolicy.HOLD
	)
	var validation := host.submit_command(command)
	for _tick in range(12):
		host.advance_tick()
	var report := host.get_gameplay_observability_report()
	_expect(validation.is_accepted(), "live capture fixture intent should pass the real command pipeline", failures)
	_expect(bool(report.get("legal_observation_only", false)) and int(report.get("observer_faction_id", 0)) == SimulationWorld.LOCAL_PLAYER_ID, "live host capture should use the player's legal faction snapshot", failures)
	_expect(not (report.get("first_high_level_order", {}) as Dictionary).is_empty(), "live host capture should preserve accepted high-level intent", failures)
	_expect((report.get("cards", []) as Array).size() == 4 and (report.get("exception_summary", {}) as Dictionary).has("unique"), "live host capture should preserve card facts and sampled exception state", failures)
	host.free()


func _test_hidden_building_event_filter(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	_expect(snapshot.get_building(SimulationWorld.ENEMY_COMMAND_CENTER_ID) == null, "hidden-event fixture requires an unknown enemy headquarters", failures)
	var local_member_id := 0
	for unit in snapshot.units:
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID and not unit.unit_card_id.is_empty():
			local_member_id = unit.entity_id
			break
	_expect(local_member_id != 0, "hidden-event fixture requires a deployed friendly card member", failures)
	if local_member_id == 0:
		return
	const HIDDEN_ATTACKER_ID := 987654
	var report := GameplayObservabilityReport.new(&"grey_ridge", world.enemy_opening_plan_id, &"hidden_filter", 0, SimulationWorld.LOCAL_PLAYER_ID, 100)
	report.start(snapshot)
	report.observe(snapshot, [
		SimulationEvent.new(1, SimulationEvent.Kind.BUILDING_DESTROYED, SimulationWorld.ENEMY_COMMAND_CENTER_ID),
		SimulationEvent.new(1, SimulationEvent.Kind.BUILDING_DESTROYED, SimulationWorld.PLAYER_COMMAND_CENTER_ID),
		SimulationEvent.new(1, SimulationEvent.Kind.DAMAGE_APPLIED, HIDDEN_ATTACKER_ID, "target=%d;amount=100.0;remaining=0.0" % local_member_id),
		SimulationEvent.new(1, SimulationEvent.Kind.UNIT_DESTROYED, local_member_id),
	])
	var turning_points := report.create_report().get("causal_turning_points", []) as Array
	var destroyed: Array = turning_points.filter(func(point: Dictionary) -> bool: return String(point.get("reason_key", "")) == "building_destroyed")
	var losses: Array = turning_points.filter(func(point: Dictionary) -> bool: return String(point.get("reason_key", "")) == "unit_card_loss")
	_expect(destroyed.size() == 1 and String((destroyed[0] as Dictionary).get("result", "")) == str(SimulationWorld.PLAYER_COMMAND_CENTER_ID), "after-action capture should exclude destruction of buildings unknown to the observer", failures)
	_expect(losses.size() == 1 and String((losses[0] as Dictionary).get("actor_id", "")) == "0", "after-action capture should not identify an attacker absent from the observer's legal knowledge", failures)


func _signed_source_report() -> Dictionary:
	var report := {
		"format_version": 1,
		"schema_id": "warseed.gameplay_baseline.case.v1",
		"evidence_level": "SIMULATED",
		"scenario_id": "grey_ridge",
		"enemy_plan_id": "central_assault",
		"strategy_id": "fixture",
		"seed": 1701,
		"observer_faction_id": SimulationWorld.LOCAL_PLAYER_ID,
		"tick_rate_hz": 10,
		"started_tick": 0,
		"final_tick": 300,
		"max_ticks": 4800,
		"legal_observation_only": true,
		"illegal_input_reason": "",
		"first_high_level_order": {"tick": 10},
		"command_summary": {"accepted": 2, "rejected": 0, "player_corrections": 0},
		"commands": [],
		"player_corrections": [],
		"supply_summary": {"total_committed": 3, "commitment_count": 1},
		"supply_commitments": [],
		"task_summary": {"created": 2, "replaced": 0, "blocked": 1, "retreated": 0, "completed": 0, "failed": 1, "cancelled": 0},
		"tasks": [
			{"task_id": 7, "card_id": "ironwall_assault_group", "blocked_count": 2, "last_reason": "PATH_UNAVAILABLE"},
		],
		"task_transitions": [
			{"tick": 160, "task_id": 7}, {"tick": 190, "task_id": 7},
		],
		"control_summary": {"takeovers": 0, "returned": 0},
		"control_sessions": [],
		"exception_summary": {"unique": 1, "opened": 1, "resolved": 0, "active": 1, "player_actions": 0},
		"exceptions": [
			{"exception_id": "blocked:00000007", "kind": CommandExceptionSnapshot.Kind.BLOCKED, "severity": CommandExceptionSnapshot.Severity.CRITICAL, "reason_key": "COMMAND_EXCEPTION_BLOCKED_PATH_UNAVAILABLE", "unit_card_id": "ironwall_assault_group", "task_id": 7, "last_seen_tick": 250, "opened_count": 1, "resolved_count": 0},
		],
		"exception_transitions": [],
		"cards": [
			{"card_id": "ironwall_assault_group", "authorized_strength": 12, "initial_strength": 12, "peak_strength": 12, "final_strength": 9, "losses": 3, "damage_dealt": 810.0, "damage_taken": 500.0, "kills": 2, "tasks_completed": 0, "tasks_blocked": 2, "final_deployment_state": "DEPLOYED", "final_control_state": "AGENT_ASSIGNED"},
			{"card_id": "falcon_recon_group", "authorized_strength": 8, "initial_strength": 8, "peak_strength": 8, "final_strength": 8, "losses": 0, "damage_dealt": 0.0, "damage_taken": 0.0, "kills": 0, "tasks_completed": 0, "tasks_blocked": 0, "final_deployment_state": "DEPLOYED", "final_control_state": "AGENT_ASSIGNED"},
		],
		"outcome": {"result": "defeat", "grade": "collapse", "concluded_tick": 300, "conclusion_group_id": "collapse", "reason_objective_ids": ["protect_headquarters"]},
		"causal_turning_points": [
			{"tick": 10, "actor_id": "di_tian", "card_id": "", "task_id": 0, "reason_key": "first_high_level_order", "source_event": "command_accepted", "result": "intent"},
			{"tick": 80, "actor_id": "1", "card_id": "", "task_id": 0, "reason_key": "region_control_changed", "source_event": "region_control_changed", "result": "central_relay:1"},
			{"tick": 120, "actor_id": "1001", "card_id": "ironwall_assault_group", "task_id": 0, "reason_key": "unit_card_loss", "source_event": "unit_destroyed", "result": "11"},
			{"tick": 130, "actor_id": "1002", "card_id": "ironwall_assault_group", "task_id": 0, "reason_key": "unit_card_loss", "source_event": "unit_destroyed", "result": "12"},
			{"tick": 140, "actor_id": "1003", "card_id": "ironwall_assault_group", "task_id": 0, "reason_key": "unit_card_loss", "source_event": "unit_destroyed", "result": "13"},
			{"tick": 160, "actor_id": "202", "card_id": "ironwall_assault_group", "task_id": 7, "reason_key": "task_state_changed", "source_event": "task_snapshot", "result": "BLOCKED:ADVANCING", "blocked_reason": "PATH_UNAVAILABLE"},
			{"tick": 250, "actor_id": "player_staff", "card_id": "ironwall_assault_group", "task_id": 7, "reason_key": "exception_opened", "source_event": "command_situation", "result": "blocked:00000007"},
			{"tick": 300, "actor_id": "1", "card_id": "", "task_id": 0, "reason_key": "battle_concluded", "source_event": "battle_concluded", "result": "result=defeat"},
		],
	}
	_resign(report)
	return report


func _resign(report: Dictionary) -> void:
	report.erase("fingerprint")
	report["fingerprint"] = GameplayObservabilityReport.canonical_json(report).sha256_text()


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
