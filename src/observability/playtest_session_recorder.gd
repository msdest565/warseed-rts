class_name PlaytestSessionRecorder
extends RefCounted

const FORMAT_VERSION := 3
const DEFAULT_DIRECTORY := "user://playtests"
const LATEST_PATH := "user://playtests/latest_grey_ridge.json"
const MAX_EVENTS := 256

var scenario_id := "grey_ridge"
var playtest_session_id := ""
var output_directory := DEFAULT_DIRECTORY
var battle_number: int = 1
var opening_plan_id: StringName
var started_tick: int = 0
var latest_tick: int = 0
var started_unix_time: int = 0
var prebattle_duration_seconds: float = 0.0
var prebattle_plan_changes: int = 0
var prebattle_invalid_plan_changes: int = 0
var completed: bool = false
var result := "in_progress"
var requested_second_battle: bool = false
var first_commander_command_tick: int = -1
var first_unit_card_command_tick: int = -1
var latest_intel_tick: int = -1
var latest_intel_report_id: int = 0
var last_acted_intel_tick: int = -1
var accepted_player_commands: int = 0
var rejected_player_commands: int = 0
var commander_commands: int = 0
var unit_card_commands: int = 0
var support_commands: int = 0
var replans: int = 0
var takeovers: int = 0
var returns_to_commander: int = 0
var deployments: int = 0
var doctrine_changes: int = 0
var posture_changes: int = 0
var intent_commands: int = 0
var intent_cancellations: int = 0
var exception_actions: int = 0
var exception_acknowledgements: int = 0
var diagnostic_individual_mode_activations: int = 0
var commander_card_selections: int = 0
var unit_card_selections: int = 0
var agent_override_rejections: int = 0
var battle_losses: int = 0
var intel_action_delay_ticks: Array[int] = []
var events: Array[Dictionary] = []
var saved_path := ""

var _last_replan_tick_by_subject: Dictionary = {}


func start(
	snapshot: WorldSnapshot,
	new_battle_number: int,
	new_opening_plan_id: StringName,
	prebattle_metrics: Dictionary = {},
	new_playtest_session_id: String = "",
	new_output_directory: String = DEFAULT_DIRECTORY,
	new_scenario_id: StringName = &"grey_ridge"
) -> void:
	scenario_id = String(new_scenario_id)
	battle_number = maxi(1, new_battle_number)
	opening_plan_id = new_opening_plan_id
	playtest_session_id = new_playtest_session_id
	output_directory = new_output_directory if not new_output_directory.is_empty() else DEFAULT_DIRECTORY
	prebattle_duration_seconds = maxf(0.0, float(prebattle_metrics.get("duration_seconds", 0.0)))
	prebattle_plan_changes = maxi(0, int(prebattle_metrics.get("plan_changes", 0)))
	prebattle_invalid_plan_changes = mini(prebattle_plan_changes, maxi(0, int(prebattle_metrics.get("invalid_plan_changes", 0))))
	started_tick = snapshot.tick if snapshot != null else 0
	latest_tick = started_tick
	started_unix_time = int(Time.get_unix_time_from_system())
	observe_snapshot(snapshot)
	_append_event(started_tick, "session_started", String(opening_plan_id))


func observe_snapshot(snapshot: WorldSnapshot) -> void:
	if snapshot == null:
		return
	latest_tick = maxi(latest_tick, snapshot.tick)
	for report in snapshot.intel_reports:
		if report.superseded:
			continue
		if report.observed_tick > latest_intel_tick or report.observed_tick == latest_intel_tick and report.report_id > latest_intel_report_id:
			latest_intel_tick = report.observed_tick
			latest_intel_report_id = report.report_id


func record_command(command: GameCommand, validation: CommandValidationResult, descriptor: Dictionary) -> void:
	if command == null or command.issuer_kind != GameCommand.IssuerKind.PLAYER or descriptor.is_empty():
		return
	latest_tick = maxi(latest_tick, command.issued_tick)
	var category := String(descriptor.get("category", "other"))
	var subject := String(descriptor.get("subject", ""))
	var action := String(descriptor.get("action", ""))
	if validation.is_accepted():
		accepted_player_commands += 1
		match category:
			"commander":
				commander_commands += 1
				if first_commander_command_tick < 0:
					first_commander_command_tick = command.issued_tick
			"unit_card":
				unit_card_commands += 1
				if first_unit_card_command_tick < 0:
					first_unit_card_command_tick = command.issued_tick
			"support":
				support_commands += 1
		_record_accepted_action(command.issued_tick, descriptor)
	else:
		rejected_player_commands += 1
		if validation.reason == CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED:
			agent_override_rejections += 1
	var detail := "%s:%s:%s" % [category, subject, action]
	if not validation.is_accepted():
		detail += ";reason=%s" % CommandValidationResult.Reason.keys()[validation.reason]
	_append_event(command.issued_tick, "command_%s" % ("accepted" if validation.is_accepted() else "rejected"), detail)


func _record_accepted_action(tick: int, descriptor: Dictionary) -> void:
	var action := String(descriptor.get("action", ""))
	if bool(descriptor.get("counts_as_replan", false)):
		var replan_key := "%s:%s" % [descriptor.get("category", ""), descriptor.get("subject", "")]
		if _last_replan_tick_by_subject.has(replan_key):
			replans += 1
		_last_replan_tick_by_subject[replan_key] = tick
	if bool(descriptor.get("uses_intel", false)) and latest_intel_tick >= 0 and latest_intel_tick > last_acted_intel_tick:
		intel_action_delay_ticks.append(maxi(0, tick - latest_intel_tick))
		last_acted_intel_tick = latest_intel_tick
	match action:
		"takeover", "direct_order_takeover":
			takeovers += 1
		"return_to_commander":
			returns_to_commander += 1
		"deploy":
			deployments += 1
		"doctrine":
			doctrine_changes += 1
		"posture":
			posture_changes += 1
		"intent":
			intent_commands += 1
		"cancel_intent":
			intent_cancellations += 1


func record_ui_event(event_type: String, subject: StringName, tick: int) -> void:
	latest_tick = maxi(latest_tick, tick)
	match event_type:
		"commander_card_selected":
			commander_card_selections += 1
		"unit_card_selected":
			unit_card_selections += 1
		"diagnostic_individual_mode_enabled":
			diagnostic_individual_mode_activations += 1
	if event_type.begins_with("exception_action_"):
		exception_actions += 1
	elif event_type == "exception_acknowledged":
		exception_acknowledgements += 1
	_append_event(tick, event_type, String(subject))


func finish(snapshot: WorldSnapshot, campaign_record: Dictionary, simulation_events: Array[SimulationEvent] = []) -> void:
	observe_snapshot(snapshot)
	completed = true
	result = String(campaign_record.get("last_result", "defeat"))
	battle_losses = 0
	var cards := campaign_record.get("cards", {}) as Dictionary
	for card_variant in cards.values():
		var card := card_variant as Dictionary
		battle_losses += maxi(0, int(card.get("last_battle_losses", 0)))
	agent_override_rejections = maxi(agent_override_rejections, _count_agent_override_rejections(simulation_events))
	_append_event(latest_tick, "session_finished", result)


func mark_second_battle_requested(tick: int) -> void:
	requested_second_battle = true
	latest_tick = maxi(latest_tick, tick)
	_append_event(tick, "second_battle_requested", "")


func create_summary() -> Dictionary:
	var duration_ticks := maxi(0, latest_tick - started_tick)
	var duration_minutes := maxf(float(duration_ticks) * SimulationWorld.TICK_SECONDS / 60.0, 1.0 / 60.0)
	var coarse_and_direct := commander_commands + unit_card_commands
	var direct_control_ratio := float(unit_card_commands) / float(coarse_and_direct) if coarse_and_direct > 0 else 0.0
	var average_intel_delay_ticks := 0.0
	for delay in intel_action_delay_ticks:
		average_intel_delay_ticks += delay
	if not intel_action_delay_ticks.is_empty():
		average_intel_delay_ticks /= float(intel_action_delay_ticks.size())
	return {
		"format_version": FORMAT_VERSION,
		"scenario_id": scenario_id,
		"playtest_session_id": playtest_session_id,
		"battle_number": battle_number,
		"opening_plan_id": String(opening_plan_id),
		"started_unix_time": started_unix_time,
		"prebattle_duration_seconds": prebattle_duration_seconds,
		"prebattle_plan_changes": prebattle_plan_changes,
		"prebattle_invalid_plan_changes": prebattle_invalid_plan_changes,
		"completed": completed,
		"result": result,
		"requested_second_battle": requested_second_battle,
		"duration_ticks": duration_ticks,
		"duration_seconds": float(duration_ticks) * SimulationWorld.TICK_SECONDS,
		"first_commander_command_seconds": _tick_offset_seconds(first_commander_command_tick),
		"first_unit_card_command_seconds": _tick_offset_seconds(first_unit_card_command_tick),
		"accepted_player_commands": accepted_player_commands,
		"rejected_player_commands": rejected_player_commands,
		"commander_commands": commander_commands,
		"unit_card_commands": unit_card_commands,
		"support_commands": support_commands,
		"direct_control_ratio": direct_control_ratio,
		"replans": replans,
		"replans_per_minute": float(replans) / duration_minutes,
		"average_intel_action_delay_seconds": average_intel_delay_ticks * SimulationWorld.TICK_SECONDS if not intel_action_delay_ticks.is_empty() else -1.0,
		"intel_actions_measured": intel_action_delay_ticks.size(),
		"takeovers": takeovers,
		"returns_to_commander": returns_to_commander,
		"deployments": deployments,
		"doctrine_changes": doctrine_changes,
		"posture_changes": posture_changes,
		"intent_commands": intent_commands,
		"intent_cancellations": intent_cancellations,
		"exception_actions": exception_actions,
		"exception_acknowledgements": exception_acknowledgements,
		"commander_card_selections": commander_card_selections,
		"unit_card_selections": unit_card_selections,
		"diagnostic_individual_mode_activations": diagnostic_individual_mode_activations,
		"agent_override_rejections": agent_override_rejections,
		"battle_losses": battle_losses,
		"observer_checks_required": ["card_entity_recognition", "commander_behavior_explanation", "enemy_reaction_explanation", "second_battle_intent"],
		"events": events.duplicate(true),
	}


func save_to_path(path: String) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(create_summary(), "\t"))
	if file.get_error() != OK:
		return false
	saved_path = path
	return true


func default_archive_path() -> String:
	return "%s/%s_b%03d_%d.json" % [output_directory, scenario_id, battle_number, started_unix_time]


func latest_record_path() -> String:
	return "%s/latest_%s.json" % [output_directory, scenario_id]


func _append_event(tick: int, event_type: String, detail: String) -> void:
	if events.size() >= MAX_EVENTS:
		return
	events.append({"tick": tick, "type": event_type, "detail": detail})


func _tick_offset_seconds(tick: int) -> float:
	return float(tick - started_tick) * SimulationWorld.TICK_SECONDS if tick >= 0 else -1.0


func _count_agent_override_rejections(simulation_events: Array[SimulationEvent]) -> int:
	var count := 0
	for event in simulation_events:
		if event.kind == SimulationEvent.Kind.COMMAND_REJECTED and event.detail.contains("AGENT_OVERRIDE_BLOCKED"):
			count += 1
	return count
