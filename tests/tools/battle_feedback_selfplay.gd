extends SceneTree

const VIEWPORT_SIZE := Vector2i(1280, 720)
const REPORT_PATH := "res://artifacts/battle_feedback_selfplay.json"
const CAPTURE_DIRECTORY := "res://artifacts/battle-feedback"
const AUDIO_DIRECTORY := "res://artifacts/battle-feedback/audio"

var _mouse_position := Vector2.ZERO
var _failed := false
var _captures: Dictionary = {}
var _capture_ticks: Dictionary = {}


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		_fail("battle feedback self-play requires a display")
		quit(2)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(VIEWPORT_SIZE)
	root.content_scale_size = VIEWPORT_SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUDIO_DIRECTORY))
	await _wait_frames(5)

	var game := (load("res://scenes/game/grey_ridge.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	current_scene = game
	await _wait_frames(10)
	var host := game.simulation_host
	var planner := game.prebattle_planner
	if planner == null or planner.start_button == null or not planner.is_plan_valid():
		_fail("Grey Ridge prebattle did not expose a valid real-input start")
		await _finish(game)
		return
	if planner.tutorial_toggle.button_pressed:
		await _click_control(planner.tutorial_toggle)
	await _click_control(planner.start_button)
	await _wait_frames(12)
	if not host.is_grey_ridge_battle_started():
		_fail("real prebattle click did not start the battle")
		await _finish(game)
		return

	var director := game.battle_feedback_director
	_export_audio_bank(director)
	var army_scroll := game.army_board.get_node("Margin/Layout/Scroll") as ScrollContainer
	var commander_button := game.army_board._commander_buttons.get(&"di_tian") as Button
	await _ensure_visible(army_scroll, commander_button)
	var east_region := host.world.battle_definition.region_dictionary().get(&"eastern_supply") as BattleRegionDefinition
	if east_region == null:
		east_region = host.world.battle_definition.region_dictionary().values()[0] as BattleRegionDefinition
	await _drag_control_to(commander_button, game.camera_controller.world_to_screen(east_region.position))
	await _wait_frames(8)

	var enemy_attack_result := _order_enemy_attack_move_to_player_headquarters(host)
	if enemy_attack_result == null or not enemy_attack_result.is_accepted():
		_fail("enemy feedback probe could not enter the shared command pipeline: %s" % [enemy_attack_result.describe() if enemy_attack_result != null else "missing result"])
		await _finish(game)
		return

	Engine.time_scale = 4.0
	for _frame in range(3000):
		await _capture_current_feedback(game, director, host.current_snapshot.tick)
		if _captures.has("engagement") and _captures.has("focus") and _captures.has("pressure") and _captures.has("headquarters"):
			break
		if game.battle_debrief.visible:
			break
		await process_frame
	Engine.time_scale = 1.0
	await _wait_frames(5)
	await _capture_current_feedback(game, director, host.current_snapshot.tick)

	for required in ["engagement", "focus", "pressure", "headquarters"]:
		if not _captures.has(required):
			_fail("real battle did not expose required %s feedback before conclusion" % required)
	if director.peak_concurrent_voice_count <= 0 or director.peak_concurrent_voice_count > BattleFeedbackDirector.MAX_CONCURRENT_VOICES:
		_fail("battle mix reported an invalid voice peak: %d" % director.peak_concurrent_voice_count)
	var map_rect := game.get_grey_ridge_map_rect()
	if game.contact_alert.get_global_rect().intersection(map_rect).get_area() > 4.0:
		_fail("battle alert text overlaps the dedicated map viewport")

	var report := {
		"format_version": 1,
		"scenario_id": String(host.get_scenario_id()),
		"input_mode": "real_mouse_and_shared_enemy_agent_command",
		"tick": host.current_snapshot.tick,
		"feedback_counts": {
			"engagement": director.get_feedback_count(BattleFeedbackDirector.Cue.ENGAGEMENT),
			"focus_fire": director.get_feedback_count(BattleFeedbackDirector.Cue.FOCUS_FIRE),
			"under_pressure": director.get_feedback_count(BattleFeedbackDirector.Cue.UNDER_PRESSURE),
			"reinforcement": director.get_feedback_count(BattleFeedbackDirector.Cue.REINFORCEMENT),
			"scout_report": director.get_feedback_count(BattleFeedbackDirector.Cue.SCOUT_REPORT),
			"headquarters_critical": director.get_feedback_count(BattleFeedbackDirector.Cue.HEADQUARTERS_CRITICAL),
		},
		"audio": {
			"play_count": director.play_count,
			"dropped_count": director.dropped_audio_count,
			"preempted_count": director.preempted_audio_count,
			"max_concurrent_voices": director.peak_concurrent_voice_count,
			"voice_limit": BattleFeedbackDirector.MAX_CONCURRENT_VOICES,
			"directory": AUDIO_DIRECTORY,
		},
		"captures": _captures.duplicate(true),
		"capture_ticks": _capture_ticks.duplicate(true),
		"passed": not _failed,
	}
	_write_report(report)
	print("WARSEED_BATTLE_FEEDBACK_SELFPLAY tick=%d captures=%s voices=%d/%d play=%d drop=%d preempt=%d report=%s" % [
		host.current_snapshot.tick, _captures.keys(), director.peak_concurrent_voice_count,
		BattleFeedbackDirector.MAX_CONCURRENT_VOICES, director.play_count,
		director.dropped_audio_count, director.preempted_audio_count, REPORT_PATH,
	])
	await _finish(game)


func _order_enemy_attack_move_to_player_headquarters(host: SimulationHost) -> CommandValidationResult:
	var enemy_formation: FormationState
	for formation_variant in host.world.formations.values():
		var formation := formation_variant as FormationState
		var leader := host.world.units.get(formation.leader_entity_id) as UnitState
		if leader != null and leader.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			enemy_formation = formation
			break
	if enemy_formation == null:
		return null
	var headquarters := host.world.buildings.get(SimulationWorld.PLAYER_COMMAND_CENTER_ID) as BuildingState
	var destination := Vector2.ZERO
	for radius_variant in [192.0, 256.0, 320.0, 448.0]:
		var radius := float(radius_variant)
		for angle_index in range(8):
			var candidate: Vector2 = headquarters.position + Vector2.RIGHT.rotated(float(angle_index) * TAU / 8.0) * radius
			if not host.world.logic_grid.is_world_position_walkable(candidate):
				continue
			if not host.world.pathfinder.find_path(enemy_formation.anchor_position, candidate).is_empty():
				destination = candidate
				break
		if not destination.is_zero_approx():
			break
	if destination.is_zero_approx():
		return null
	var command := AttackMoveCommand.new(
		host.world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID,
		GameCommand.IssuerKind.AGENT, host.world.current_tick,
		enemy_formation.leader_entity_id, enemy_formation.formation_id,
		destination
	)
	command.agent_id = host.world.battle_definition.enemy_agent_id
	command.task_id = host.world.battle_definition.enemy_task_id
	return host.world.submit_command(command)


func _capture_current_feedback(game: GameRoot, director: BattleFeedbackDirector, tick: int) -> void:
	var labels_by_message := {
		&"BATTLE_FEEDBACK_ENGAGEMENT": "engagement",
		&"BATTLE_FEEDBACK_FOCUS_FIRE": "focus",
		&"BATTLE_FEEDBACK_UNDER_PRESSURE": "pressure",
		&"BATTLE_FEEDBACK_LOSS": "pressure",
		&"BATTLE_FEEDBACK_HEADQUARTERS_CRITICAL": "headquarters",
	}
	var label := String(labels_by_message.get(director.last_message_key, ""))
	if label.is_empty() or _captures.has(label):
		return
	await process_frame
	var path := "%s/%s.png" % [CAPTURE_DIRECTORY, label]
	await _save_screenshot(path)
	_captures[label] = path
	_capture_ticks[label] = tick


func _export_audio_bank(director: BattleFeedbackDirector) -> void:
	var names := {
		BattleFeedbackDirector.Cue.ENGAGEMENT: "engagement",
		BattleFeedbackDirector.Cue.VOLLEY: "volley",
		BattleFeedbackDirector.Cue.IMPACT: "impact",
		BattleFeedbackDirector.Cue.FOCUS_FIRE: "focus_fire",
		BattleFeedbackDirector.Cue.UNDER_PRESSURE: "under_pressure",
		BattleFeedbackDirector.Cue.REINFORCEMENT: "reinforcement",
		BattleFeedbackDirector.Cue.SCOUT_REPORT: "scout_report",
		BattleFeedbackDirector.Cue.HEADQUARTERS_CRITICAL: "headquarters_critical",
		BattleFeedbackDirector.Cue.VICTORY: "victory",
		BattleFeedbackDirector.Cue.DEFEAT: "defeat",
	}
	for cue in names:
		var stream := director._streams.get(cue) as AudioStreamWAV
		if stream == null or stream.data.is_empty():
			_fail("audio bank is missing cue %s" % names[cue])
			continue
		var path := ProjectSettings.globalize_path("%s/%s.wav" % [AUDIO_DIRECTORY, names[cue]])
		var error := stream.save_to_wav(path)
		if error != OK:
			_fail("could not export %s cue: %s" % [names[cue], error_string(error)])


func _click_control(control: Control) -> void:
	if control == null or not control.is_visible_in_tree() or control.disabled:
		_fail("attempted to click a missing, hidden, or disabled control")
		return
	await _click_position(control.get_global_rect().get_center())


func _click_position(position: Vector2) -> void:
	_send_motion(position, 0)
	await process_frame
	_send_button(position, true)
	await process_frame
	_send_button(position, false)
	await _wait_frames(3)


func _drag_control_to(control: Control, target: Vector2) -> void:
	if control == null or not control.is_visible_in_tree():
		_fail("attempted to drag a missing or hidden commander card")
		return
	var start := control.get_global_rect().get_center()
	_send_motion(start, 0)
	await process_frame
	_send_button(start, true)
	await process_frame
	_send_motion(start + Vector2(-18.0, 0.0), MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_send_motion(target, MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_send_button(target, false)
	await _wait_frames(6)


func _send_motion(position: Vector2, button_mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - _mouse_position
	event.button_mask = button_mask
	_mouse_position = position
	Input.parse_input_event(event)


func _send_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)


func _ensure_visible(scroll: ScrollContainer, control: Control) -> void:
	if control == null:
		_fail("expected army-board control is missing")
		return
	scroll.ensure_control_visible(control)
	await _wait_frames(5)


func _save_screenshot(path: String) -> void:
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_fail("could not save feedback screenshot: %s" % error_string(error))


func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("could not open battle feedback report")
		return
	file.store_string(JSON.stringify(report, "\t"))
	if file.get_error() != OK:
		_fail("could not write battle feedback report")


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error("BATTLE FEEDBACK SELFPLAY: %s" % message)


func _finish(game: Node) -> void:
	Engine.time_scale = 1.0
	paused = false
	if game != null and is_instance_valid(game):
		game.queue_free()
	await process_frame
	quit(1 if _failed else 0)
