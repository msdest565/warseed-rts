class_name TestObservability
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_deterministic_metrics_and_snapshot_copy(failures)
	_test_host_timing_is_separate(failures)
	_test_playtest_session_summary_and_serialization(failures)
	_test_playtest_feedback_store(failures)
	_test_isolated_playtest_paths(failures)
	_test_isolated_test_persistence_opt_in(failures)
	_test_host_classifies_grey_ridge_playtest_commands(failures)
	_test_tutorial_progress_store(failures)
	_test_tutorial_receives_only_accepted_actions(failures)
	return failures


func _test_playtest_feedback_store(failures: Array[String]) -> void:
	var root := "user://warseed_test_feedback_store"
	var pending_directory := "%s/pending" % root
	var sent_directory := "%s/sent" % root
	var endpoint := PlaytestFeedbackStore.endpoint_from_arguments(PackedStringArray([
		"--feedback-url=http://127.0.0.1:8765/feedback",
	]))
	_expect(endpoint == "http://127.0.0.1:8765/feedback", "feedback endpoint should be accepted only from an explicit HTTP user argument", failures)
	_expect(
		PlaytestFeedbackStore.endpoint_from_arguments(PackedStringArray(["--feedback-url=file:///unsafe"])).is_empty(),
		"feedback endpoint should reject non-HTTP schemes",
		failures
	)
	var payload := PlaytestFeedbackStore.create_submission({
		"build_id": "test-build",
		"anonymous_session_id": "Observer 01",
		"scenario_id": "grey_ridge",
		"outcome": "victory",
		"battle_count": 2,
		"locale": "zh_CN",
		"viewport": {"width": 1920, "height": 1080},
	}, {
		"overall_rating": 4,
		"objective_clarity": 5,
		"controls_clarity": 3,
		"agent_usefulness": 4,
		"priority_area": "commander_ai",
		"best_part": "Card command",
		"biggest_problem": "Agent intent needed more context",
		"suggestions": "Expose the current reason",
		"encountered_bug": false,
		"bug_details": "",
	})
	var pending_path := PlaytestFeedbackStore.save_pending(payload, root)
	_expect(not pending_path.is_empty() and FileAccess.file_exists(pending_path), "valid feedback should be atomically persisted before delivery", failures)
	var pending := PlaytestFeedbackStore.load_pending("observer_01", root)
	_expect(
		pending.size() == 1 and String(pending[0].get("feedback_id", "")) == String(payload.get("feedback_id", "")),
		"pending feedback should round-trip without losing its stable id",
		failures
	)
	_expect(PlaytestFeedbackStore.mark_sent(payload, root), "a delivered feedback record should be archived locally", failures)
	var sent_path := "%s/%s.json" % [sent_directory, String(payload.get("feedback_id", ""))]
	_expect(not FileAccess.file_exists(pending_path) and FileAccess.file_exists(sent_path), "sent archival should remove only the matching pending item", failures)
	var invalid := payload.duplicate(true)
	(invalid["responses"] as Dictionary)["overall_rating"] = 0
	_expect(not PlaytestFeedbackStore.validate_submission(invalid).is_empty(), "required feedback fields should be validated before persistence or delivery", failures)
	for path in [pending_path, sent_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for directory in [pending_directory, sent_directory, root]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


func _test_deterministic_metrics_and_snapshot_copy(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var initial := world.create_snapshot().metrics
	var accepted := FormationMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, Vector2(800.0, 336.0))
	var rejected := MoveCommand.new(2, 1, GameCommand.IssuerKind.PLAYER, 0, 99, Vector2(500.0, 360.0))
	world.submit_command(accepted)
	world.submit_command(rejected)
	var before_tick := world.create_snapshot().metrics
	_expect(before_tick.commands_submitted_total == 2, "metrics should count all submitted commands", failures)
	_expect(before_tick.get_command_count(CommandValidationResult.Status.ACCEPTED) == 1, "metrics should count accepted commands", failures)
	_expect(before_tick.get_command_count(CommandValidationResult.Status.REJECTED) == 1, "metrics should count rejected commands", failures)
	_expect(before_tick.commands_applied_total == 0, "commands should count applied only at tick boundary", failures)
	world.advance_tick()
	var after_tick := world.create_snapshot().metrics
	_expect(after_tick.commands_applied_total == 1, "accepted command should count as applied after drain", failures)
	_expect(after_tick.path_requests_total >= 2, "validation and application path calls should be observable", failures)
	_expect(after_tick.events_emitted_total == 2, "accepted and rejected command events should count once", failures)
	_expect(initial.commands_submitted_total == 0, "old metrics snapshot must remain immutable", failures)

	var replay := SimulationWorld.new()
	replay.submit_command(FormationMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, Vector2(800.0, 336.0)))
	replay.submit_command(MoveCommand.new(2, 1, GameCommand.IssuerKind.PLAYER, 0, 99, Vector2(500.0, 360.0)))
	replay.advance_tick()
	var replay_metrics := replay.create_snapshot().metrics
	_expect(replay_metrics.commands_submitted_total == after_tick.commands_submitted_total, "metric replay should preserve command totals", failures)
	_expect(replay_metrics.path_requests_total == after_tick.path_requests_total, "metric replay should preserve path totals", failures)
	_expect(replay_metrics.events_emitted_total == after_tick.events_emitted_total, "metric replay should preserve event totals", failures)


func _test_host_timing_is_separate(failures: Array[String]) -> void:
	var host := SimulationHost.new()
	Engine.get_main_loop().root.add_child(host)
	host._ready()
	host._process(0.25)
	var timing := host.get_tick_timing_snapshot()
	_expect(timing.sample_count == 2, "host should record one timing sample per fixed tick", failures)
	_expect(timing.last_usec >= 0 and timing.average_usec >= 0.0, "host timing should be non-negative", failures)
	_expect(timing.max_usec >= timing.last_usec, "host max timing should include last sample", failures)
	_expect(not "last_tick_usec" in host.current_snapshot, "wall-clock timing must not enter authoritative snapshot", failures)
	host.free()


func _test_playtest_session_summary_and_serialization(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var recorder := PlaytestSessionRecorder.new()
	recorder.start(world.create_snapshot(), 1, world.enemy_opening_plan_id, {
		"duration_seconds": 14.25,
		"plan_changes": 5,
		"invalid_plan_changes": 2,
	})
	recorder.record_ui_event("commander_card_selected", &"di_tian", 5)
	recorder.record_ui_event("unit_card_selected", &"ironwall_assault_group", 6)
	recorder.record_ui_event("diagnostic_individual_mode_enabled", &"", 7)
	var accepted := CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	var commander := CommanderOrderCommand.new(100, 1, 20, &"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	recorder.record_command(commander, accepted, {"category": "commander", "subject": "di_tian", "action": "objective", "counts_as_replan": true, "uses_intel": true})
	var direct := FormationMoveCommand.new(101, 1, GameCommand.IssuerKind.PLAYER, 50, 9, SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	recorder.record_command(direct, accepted, {"category": "unit_card", "subject": "ironwall_assault_group", "action": "direct_order_takeover", "counts_as_replan": true, "uses_intel": true})
	var corrected := FormationMoveCommand.new(102, 1, GameCommand.IssuerKind.PLAYER, 60, 9, SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID, SimulationWorld.GREY_RIDGE_WEST_POSITION)
	recorder.record_command(corrected, accepted, {"category": "unit_card", "subject": "ironwall_assault_group", "action": "direct_order", "counts_as_replan": true, "uses_intel": true})
	var rejected_override := CommandValidationResult.new(CommandValidationResult.Status.REJECTED, CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED)
	recorder.record_command(corrected, rejected_override, {"category": "unit_card", "subject": "ironwall_assault_group", "action": "direct_order"})
	var ironwall := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	(world.units[ironwall.member_entity_ids[-1]] as UnitState).enabled = false
	(world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).victorious = true
	var record := ArmyRosterStore.build_battle_record(world.create_snapshot())
	var finish_events: Array[SimulationEvent] = []
	finish_events.assign(world.events)
	finish_events.append(SimulationEvent.new(60, SimulationEvent.Kind.COMMAND_REJECTED, 0, "REJECTED: AGENT_OVERRIDE_BLOCKED"))
	recorder.finish(world.create_snapshot(), record, finish_events)
	var summary := recorder.create_summary()
	var rejected_event_has_reason := false
	for event_variant in summary.get("events", []):
		var event := event_variant as Dictionary
		if String(event.get("type", "")) == "command_rejected" and String(event.get("detail", "")).contains("reason=AGENT_OVERRIDE_BLOCKED"):
			rejected_event_has_reason = true
	_expect(is_equal_approx(float(summary["prebattle_duration_seconds"]), 14.25) and int(summary["prebattle_plan_changes"]) == 5 and int(summary["prebattle_invalid_plan_changes"]) == 2, "playtest summary should preserve normalized prebattle composition metrics", failures)
	_expect(is_equal_approx(float(summary["first_commander_command_seconds"]), 2.0) and is_equal_approx(float(summary["first_unit_card_command_seconds"]), 5.0), "playtest summary should measure first effective commander and unit-card commands from authoritative ticks", failures)
	_expect(int(summary["replans"]) == 1 and is_equal_approx(float(summary["direct_control_ratio"]), 2.0 / 3.0), "playtest summary should measure repeated orders and coarse/direct command balance", failures)
	_expect(int(summary["intel_actions_measured"]) == 1 and is_equal_approx(float(summary["average_intel_action_delay_seconds"]), 2.0), "playtest summary should measure the first action following each new intelligence report", failures)
	_expect(int(summary["takeovers"]) == 1 and int(summary["battle_losses"]) == 1 and int(summary["diagnostic_individual_mode_activations"]) == 1, "playtest summary should include control-granularity attempts and real card losses", failures)
	_expect(int(summary["rejected_player_commands"]) == 1 and int(summary["agent_override_rejections"]) == 1, "playtest summary should not double-count one override rejection observed through the command and event paths", failures)
	_expect(rejected_event_has_reason, "rejected playtest command events should preserve the authoritative validation reason", failures)
	var path := "user://warseed_test_playtest_summary.json"
	_expect(recorder.save_to_path(path), "playtest summaries should serialize to a local structured JSON record", failures)
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_expect(parsed is Dictionary and int((parsed as Dictionary).get("format_version", 0)) == PlaytestSessionRecorder.FORMAT_VERSION and ((parsed as Dictionary).get("events", []) as Array).size() >= 7, "serialized playtest record should preserve its version and bounded event trail", failures)
	var normalized := PlaytestSessionRecorder.new()
	normalized.start(world.create_snapshot(), 0, world.enemy_opening_plan_id, {
		"duration_seconds": -1.0,
		"plan_changes": 2,
		"invalid_plan_changes": 4,
	})
	var normalized_summary := normalized.create_summary()
	_expect(float(normalized_summary["prebattle_duration_seconds"]) == 0.0 and int(normalized_summary["prebattle_plan_changes"]) == 2 and int(normalized_summary["prebattle_invalid_plan_changes"]) == 2, "prebattle metrics should reject negative values and cap invalid states at total changes", failures)


func _test_host_classifies_grey_ridge_playtest_commands(failures: Array[String]) -> void:
	var host := SimulationHost.new()
	host.scenario_kind = SimulationWorld.ScenarioKind.GREY_RIDGE
	Engine.get_main_loop().root.add_child(host)
	host._ready()
	host.start_grey_ridge(ArmyPlan.grey_ridge_default())
	var commander_result := host.submit_command(host.create_commander_objective_command(&"di_tian", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION))
	var takeover_result := host.submit_command(host.create_unit_card_control_command(&"ironwall_assault_group", UnitCardControlCommand.Action.TAKEOVER))
	var recon_descriptor := host._playtest_command_descriptor(host.create_support_order_command(SupportOrderCommand.SupportKind.AIR_RECON, &"west_mine", &"central_relay"))
	var fortify_descriptor := host._playtest_command_descriptor(host.create_support_order_command(SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY, &"", &"", &"ironwall_assault_group"))
	var reinforcement_descriptor := host._playtest_command_descriptor(host.create_support_order_command(SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"", &"", &"ironwall_assault_group"))
	var summary := host.get_playtest_summary()
	_expect(commander_result.is_accepted() and takeover_result.is_accepted(), "Grey Ridge host fixture should accept representative commander and unit-card commands", failures)
	_expect(int(summary["commander_commands"]) == 1 and int(summary["unit_card_commands"]) == 1 and int(summary["takeovers"]) == 1, "SimulationHost should classify accepted playtest commands without bypassing the command pipeline", failures)
	_expect(recon_descriptor.get("action") == "air_recon" and fortify_descriptor.get("action") == "fortify" and reinforcement_descriptor.get("action") == "field_reinforcement", "playtest telemetry should distinguish all three support actions, especially field reinforcement", failures)
	host.free()


func _test_tutorial_progress_store(failures: Array[String]) -> void:
	var path := "user://warseed_test_tutorial_progress.json"
	var roster_path := "user://warseed_test_tutorial_roster.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(roster_path))
	var initial := TutorialProgressStore.load_state(path)
	_expect(int(initial["format_version"]) == 2 and TutorialProgressStore.is_scenario_enabled(&"grey_ridge", path), "a new profile should use the per-operation tutorial format", failures)
	_expect(TutorialProgressStore.begin_scenario(&"grey_ridge", path), "starting an enabled tutorial should persist in-progress state", failures)
	_expect(TutorialProgressStore.get_scenario_status(&"grey_ridge", path) == TutorialProgressStore.STATUS_IN_PROGRESS, "Grey Ridge should report in-progress without changing other operations", failures)
	_expect(TutorialProgressStore.get_scenario_status(&"fog_forest", path) == TutorialProgressStore.STATUS_NOT_STARTED, "tutorial progress should remain isolated per operation", failures)
	_expect(TutorialProgressStore.mark_scenario_skipped(&"fog_forest", path), "an operation tutorial should support an explicit skipped state", failures)
	_expect(not TutorialProgressStore.is_scenario_enabled(&"fog_forest", path) and TutorialProgressStore.is_scenario_enabled(&"black_well", path), "skipping one tutorial must not disable another operation", failures)
	_expect(TutorialProgressStore.mark_scenario_completed(&"grey_ridge", path), "an operation tutorial should persist completion", failures)
	_expect(not TutorialProgressStore.is_scenario_enabled(&"grey_ridge", path) and TutorialProgressStore.get_scenario_status(&"grey_ridge", path) == TutorialProgressStore.STATUS_COMPLETED, "completed training should stay off until replayed", failures)
	var roster_file := FileAccess.open(roster_path, FileAccess.WRITE)
	if roster_file != null:
		roster_file.store_string("{\"cards\":{\"persistent\":true}}")
		roster_file.flush()
	var roster_before := FileAccess.get_file_as_string(roster_path)
	_expect(TutorialProgressStore.reset_scenario(&"grey_ridge", path), "replay should reset only the selected operation", failures)
	_expect(TutorialProgressStore.is_scenario_enabled(&"grey_ridge", path) and TutorialProgressStore.get_scenario_status(&"grey_ridge", path) == TutorialProgressStore.STATUS_NOT_STARTED, "replay should re-enable the selected tutorial from its first step", failures)
	_expect(FileAccess.get_file_as_string(roster_path) == roster_before, "tutorial replay must not mutate the persistent army record", failures)

	var legacy_file := FileAccess.open(path, FileAccess.WRITE)
	if legacy_file != null:
		legacy_file.store_string(JSON.stringify({"format_version": 1, "enabled": false, "completed": true, "black_well_pending_card_id": "legacy_card", "black_well_pending_growth_id": "legacy_growth"}))
		legacy_file.flush()
	var migrated := TutorialProgressStore.load_state(path)
	_expect(int(migrated["format_version"]) == 2 and TutorialProgressStore.get_scenario_status(&"broken_bridge", path) == TutorialProgressStore.STATUS_COMPLETED, "v1 global completion should migrate without unexpectedly replaying guidance", failures)
	_expect(String(migrated["black_well_pending_card_id"]) == "legacy_card", "v1 Black Well continuity data should survive migration", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(roster_path))


func _test_tutorial_receives_only_accepted_actions(failures: Array[String]) -> void:
	var host := SimulationHost.new()
	host.scenario_kind = SimulationWorld.ScenarioKind.GREY_RIDGE
	Engine.get_main_loop().root.add_child(host)
	host._ready()
	host.start_grey_ridge(ArmyPlan.grey_ridge_default())
	var recorded_actions: Array[Dictionary] = []
	host.player_action_recorded.connect(func(descriptor: Dictionary) -> void: recorded_actions.append(descriptor))
	var rejected := host.submit_command(host.create_commander_objective_command(&"di_tian", Vector2(-5000.0, -5000.0)))
	_expect(not rejected.is_accepted() and recorded_actions.is_empty(), "a rejected command must never advance tutorial progress", failures)
	var accepted := host.submit_command(host.create_commander_objective_command(&"di_tian", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION))
	_expect(accepted.is_accepted() and recorded_actions.size() == 1 and String(recorded_actions[0].get("action", "")) == "objective", "an accepted player command should emit one structured tutorial action", failures)
	var route := host.create_formation_move_command(
		SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID,
		SimulationWorld.GREY_RIDGE_CENTRAL_POSITION,
		GameCommand.IssuerKind.PLAYER,
		PackedVector2Array([SimulationWorld.GREY_RIDGE_CENTRAL_POSITION + Vector2(0.0, 320.0)])
	)
	var route_descriptor := host._playtest_command_descriptor(route)
	_expect(bool(route_descriptor.get("route_planned", false)), "whole-card routes should expose tutorial metadata only when a waypoint or deployment line exists", failures)
	host.free()


func _test_isolated_playtest_paths(failures: Array[String]) -> void:
	var session_id := ArmyRosterStore.playtest_session_id_from_arguments(PackedStringArray(["--playtest-session=Observer 01/../../Alpha"]))
	_expect(session_id == "observer_01_alpha", "playtest session ids should be normalized to a bounded traversal-safe directory component", failures)
	_expect(ArmyRosterStore.campaign_record_path_for_session(session_id) == "user://playtest_runs/observer_01_alpha/grey_ridge_roster.json", "isolated sessions should use a separate campaign record", failures)
	_expect(ArmyRosterStore.playtest_record_directory_for_session(session_id) == "user://playtest_runs/observer_01_alpha/playtests", "isolated sessions should keep raw playtest records beside their isolated roster", failures)
	_expect(ArmyRosterStore.campaign_record_path_for_session("../Bypass") == "user://playtest_runs/bypass/grey_ridge_roster.json", "path helpers should normalize session ids again even when called without the command-line parser", failures)
	_expect(ArmyRosterStore.campaign_record_path_for_session("") == ArmyRosterStore.DEFAULT_PATH, "normal runs must preserve the existing campaign record path", failures)
	var recorder := PlaytestSessionRecorder.new()
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	recorder.start(world.create_snapshot(), 1, world.enemy_opening_plan_id, {}, session_id, ArmyRosterStore.playtest_record_directory_for_session(session_id))
	var summary := recorder.create_summary()
	_expect(String(summary.get("playtest_session_id", "")) == session_id and recorder.latest_record_path() == "user://playtest_runs/observer_01_alpha/playtests/latest_grey_ridge.json", "isolated session identity and latest-record path should remain observable without entering simulation state", failures)
	var isolated_test_path := "user://warseed_test_playtest_runs/nested/grey_ridge_roster.json"
	var isolated_record := {
		"format_version": ArmyRosterStore.FORMAT_VERSION,
		"content_version": ArmyRosterMigration.CONTENT_VERSION,
		"battle_count": 2,
		"replacement_points": 4,
		"merit": 1,
		"cards": {},
	}
	_expect(ArmyRosterStore.save_record(isolated_record, isolated_test_path), "isolated campaign persistence should create its nested session directory", failures)
	var loaded_record := ArmyRosterStore.load_record(isolated_test_path)
	_expect(int(loaded_record.get("battle_count", 0)) == 2 and int(loaded_record.get("replacement_points", 0)) == 4, "isolated campaign persistence should read back the same session record", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_test_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_test_path.get_base_dir()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(isolated_test_path.get_base_dir().get_base_dir()))


func _test_isolated_test_persistence_opt_in(failures: Array[String]) -> void:
	var test_args := PackedStringArray(["--script", "res://tests/tools/four_operation_campaign_selfplay.gd"])
	_expect(
		not ArmyRosterStore.runtime_persistence_allowed_for_arguments(test_args, PackedStringArray()),
		"test scripts must keep campaign persistence disabled by default",
		failures
	)
	_expect(
		not ArmyRosterStore.runtime_persistence_allowed_for_arguments(
			test_args,
			PackedStringArray([ArmyRosterStore.ALLOW_TEST_CAMPAIGN_PERSISTENCE_ARGUMENT])
		),
		"test persistence opt-in must still require an isolated playtest session",
		failures
	)
	_expect(
		ArmyRosterStore.runtime_persistence_allowed_for_arguments(
			test_args,
			PackedStringArray([
				"--playtest-session=four-operation-chain",
				ArmyRosterStore.ALLOW_TEST_CAMPAIGN_PERSISTENCE_ARGUMENT,
			])
		),
		"an explicit isolated UI self-play session should be allowed to verify cross-scene persistence",
		failures
	)
	_expect(
		ArmyRosterStore.runtime_persistence_allowed_for_arguments(
			PackedStringArray(["--path", "."]),
			PackedStringArray()
		),
		"normal game runs must retain campaign persistence",
		failures
	)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
