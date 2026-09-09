extends SceneTree

const DESKTOP_OUTPUT := "res://artifacts/operation_selector_1280x720.png"
const NARROW_OUTPUT := "res://artifacts/operation_selector_640x800.png"
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _mouse_position := Vector2.ZERO
var _failed := false


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		_fail("operation-selector self-play requires a display")
		quit(2)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(VIEWPORT_SIZE)
	root.content_scale_size = VIEWPORT_SIZE
	await _wait_frames(5)
	TutorialProgressStore.mark_scenario_completed(&"fog_forest")
	var roster_path := ArmyRosterStore.campaign_record_path_for_session(
		ArmyRosterStore.active_playtest_session_id(),
		&"fog_forest"
	)
	var roster_before := FileAccess.get_file_as_string(roster_path) if FileAccess.file_exists(roster_path) else ""

	var selector := (load("res://scenes/game/battle_selector.tscn") as PackedScene).instantiate() as BattleSelector
	root.add_child(selector)
	current_scene = selector
	await _wait_frames(8)
	_validate_selector(selector, 4)
	await _save_screenshot(DESKTOP_OUTPUT)

	await _click_control(selector.get_battle_button(&"fog_forest"))
	if not selector.training_status_label.text.contains(GameText.t(&"TUTORIAL_STATUS_COMPLETED")):
		_fail("selected operation did not show its completed tutorial state")
	await _click_control(selector.replay_tutorial_button)
	if TutorialProgressStore.get_scenario_status(&"fog_forest") != TutorialProgressStore.STATUS_NOT_STARTED:
		_fail("real replay click did not reset Fog Forest training")
	if not TutorialProgressStore.is_scenario_enabled(&"fog_forest"):
		_fail("real replay click did not enable Fog Forest training")
	var roster_after := FileAccess.get_file_as_string(roster_path) if FileAccess.file_exists(roster_path) else ""
	if roster_after != roster_before:
		_fail("tutorial replay changed the persistent army record")
	await _click_control(selector.deploy_button)
	await _wait_frames(14)
	var fog_forest := current_scene as GameRoot
	if fog_forest == null or fog_forest.simulation_host.get_scenario_id() != &"fog_forest":
		_fail("real selector clicks did not open Fog Forest")
		await _finish()
		return
	if fog_forest.prebattle_planner == null \
			or not fog_forest.prebattle_planner.tutorial_toggle.button_pressed:
		_fail("replayed Fog Forest training was not enabled in its prebattle planner")

	_send_key(KEY_ESCAPE, true)
	await process_frame
	_send_key(KEY_ESCAPE, false)
	await _wait_frames(4)
	if not fog_forest.pause_menu.backdrop.visible or not paused:
		_fail("Esc did not open the battle pause menu")
	await _click_control(fog_forest.pause_menu.operations_button)
	await _wait_frames(4)
	if not fog_forest.pause_menu.return_confirmation.visible:
		_fail("unfinished battle return did not open a confirmation")
	_send_key(KEY_ENTER, true)
	await process_frame
	_send_key(KEY_ENTER, false)
	await _wait_frames(14)
	selector = current_scene as BattleSelector
	if selector == null:
		_fail("confirmed unfinished-battle return did not reach operations")
		await _finish()
		return

	DisplayServer.window_set_size(Vector2i(640, 800))
	root.content_scale_size = Vector2i(640, 800)
	await _wait_frames(10)
	_validate_selector(selector, 4)
	await _save_screenshot(NARROW_OUTPUT)

	DisplayServer.window_set_size(VIEWPORT_SIZE)
	root.content_scale_size = VIEWPORT_SIZE
	await _wait_frames(8)
	await _click_control(selector.get_battle_button(&"grey_ridge"))
	await _click_control(selector.deploy_button)
	await _wait_frames(14)
	var grey_ridge := current_scene as GameRoot
	if grey_ridge == null or grey_ridge.simulation_host.get_scenario_id() != &"grey_ridge":
		_fail("real selector clicks did not open Grey Ridge")
		await _finish()
		return
	grey_ridge.battle_debrief.show_debrief(ArmyRosterStore.build_battle_record(grey_ridge.simulation_host.current_snapshot))
	await _wait_frames(5)
	await _click_control(grey_ridge.battle_debrief.return_to_operations_button)
	await _wait_frames(14)
	if not current_scene is BattleSelector:
		_fail("debrief return button did not reach operations")

	print("WARSEED_OPERATION_SELECTOR_SELFPLAY desktop=%s narrow=%s" % [DESKTOP_OUTPUT, NARROW_OUTPUT])
	await _finish()


func _validate_selector(selector: BattleSelector, expected_count: int) -> void:
	if selector == null or selector.get_selectable_battle_count() != expected_count:
		_fail("selector did not show the expected playable battle count")
		return
	var viewport_rect := Rect2(Vector2.ZERO, root.content_scale_size)
	for control in [selector.title_label, selector.battle_list, selector.training_status_label, selector.replay_tutorial_button, selector.deploy_button, selector.language_button, selector.exit_button]:
		if control == null or not control.is_visible_in_tree() or not viewport_rect.encloses(control.get_global_rect()):
			_fail("selector control is missing or outside the viewport: %s" % (control.name if control != null else "null"))


func _click_control(control: Control) -> void:
	if control == null or not control.is_visible_in_tree() or control.disabled:
		_fail("attempted to click a missing, hidden, or disabled selector control")
		return
	await _click_position(control.get_global_rect().get_center())


func _click_position(position: Vector2) -> void:
	_send_motion(position, 0)
	await process_frame
	_send_button(position, true)
	await process_frame
	_send_button(position, false)
	await _wait_frames(4)


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


func _send_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _save_screenshot(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_fail("could not save selector screenshot: %s" % error_string(error))


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error("OPERATION SELECTOR SELFPLAY: %s" % message)


func _finish() -> void:
	paused = false
	await process_frame
	quit(1 if _failed else 0)
