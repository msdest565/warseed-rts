extends SceneTree

const VIEWPORT_SIZE := Vector2i(1280, 720)
const REPORT_PATH := "res://artifacts/four_operation_campaign_selfplay.json"
const START_OUTPUT_PATH := "res://artifacts/four_operation_campaign_start.png"
const MID_OUTPUT_PATH := "res://artifacts/four_operation_campaign_mid.png"
const CONTINUITY_OUTPUT_PATH := "res://artifacts/four_operation_campaign_continuity.png"
const FINAL_OUTPUT_PATH := "res://artifacts/four_operation_campaign_final.png"
const SHARED_CARD_ID := &"falcon_recon_group"
const OPERATIONS := [
	{"scenario_id": &"grey_ridge", "operation_number": 1},
	{"scenario_id": &"broken_bridge", "operation_number": 2},
	{"scenario_id": &"fog_forest", "operation_number": 3},
	{"scenario_id": &"black_well", "operation_number": 4},
]

var _mouse_position := Vector2.ZERO
var _failed := false
var _operation_reports: Array[Dictionary] = []
var _growth_selection: Dictionary = {}
var _replenishment_count := 0
var _continuity_before_black_well: Dictionary = {}
var _growth_continuity_before_black_well: Dictionary = {}


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		_fail("four-operation campaign self-play requires a display")
		quit(2)
		return
	var session_id := ArmyRosterStore.active_playtest_session_id()
	if session_id.is_empty() or not ArmyRosterStore.runtime_persistence_allowed():
		_fail("run with an isolated --playtest-session and --allow-test-campaign-persistence")
		quit(2)
		return
	var roster_path := ArmyRosterStore.campaign_record_path_for_session(session_id)
	if FileAccess.file_exists(roster_path) and not ArmyRosterStore.load_record(roster_path).is_empty():
		_fail("isolated session already contains a roster; use a fresh session id: %s" % roster_path)
		quit(2)
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	root.size = VIEWPORT_SIZE
	DisplayServer.window_set_size(VIEWPORT_SIZE)
	root.content_scale_size = VIEWPORT_SIZE
	await _wait_frames(5)
	var selector := (load("res://scenes/game/battle_selector.tscn") as PackedScene).instantiate() as BattleSelector
	root.add_child(selector)
	current_scene = selector
	await _wait_frames(10)
	await _save_screenshot(START_OUTPUT_PATH)

	for operation_index in range(OPERATIONS.size()):
		var operation := OPERATIONS[operation_index] as Dictionary
		selector = current_scene as BattleSelector
		if selector == null:
			_fail("operation %d did not begin at the operation selector" % (operation_index + 1))
			break
		var scenario_id := operation["scenario_id"] as StringName
		await _click_control(selector.get_battle_button(scenario_id))
		await _click_control(selector.deploy_button)
		var game := await _wait_for_game_scene(90)
		if game == null:
			_fail("selector did not open %s" % scenario_id)
			break
		await _play_operation(game, operation_index, operation)
		if _failed or operation_index == OPERATIONS.size() - 1:
			break
		await _click_control(game.battle_debrief.return_to_operations_button)
		selector = await _wait_for_selector_scene(90)
		if selector == null:
			_fail("%s debrief did not return to operations" % scenario_id)
			break

	var final_record := ArmyRosterStore.load_record(roster_path)
	if _operation_reports.size() != OPERATIONS.size():
		_fail("campaign chain completed %d of %d operations" % [_operation_reports.size(), OPERATIONS.size()])
	if int(final_record.get("battle_count", 0)) != OPERATIONS.size():
		_fail("shared roster recorded %d battles instead of four" % int(final_record.get("battle_count", 0)))
	if _growth_selection.is_empty():
		_fail("four debriefs never exposed an affordable persistent growth choice")
	if _replenishment_count <= 0:
		_fail("four debriefs never allowed a damaged card to be replenished through the UI")
	_write_report(session_id, roster_path, final_record)
	print("WARSEED_FOUR_OPERATION_CAMPAIGN_SELFPLAY operations=%d battles=%d replenishments=%d growth=%s report=%s" % [
		_operation_reports.size(), int(final_record.get("battle_count", 0)), _replenishment_count,
		String(_growth_selection.get("growth_id", "none")), REPORT_PATH,
	])
	await _finish(current_scene)


func _play_operation(game: GameRoot, operation_index: int, operation: Dictionary) -> void:
	var host := game.simulation_host
	var planner := game.prebattle_planner
	var scenario_id := operation["scenario_id"] as StringName
	if host == null or planner == null or host.get_scenario_id() != scenario_id:
		_fail("%s initialized with the wrong simulation host" % scenario_id)
		return
	if int(host.get_campaign_record().get("battle_count", 0)) != operation_index:
		_fail("%s did not load the previous operations' shared roster" % scenario_id)
		return
	if scenario_id == &"black_well":
		_continuity_before_black_well = _card_record(host.get_campaign_record(), SHARED_CARD_ID)
		if _continuity_before_black_well.is_empty():
			_fail("Black Well did not inherit the shared Falcon card")
			return
		if not _growth_selection.is_empty():
			var growth_card_id := StringName(_growth_selection.get("card_id", ""))
			_growth_continuity_before_black_well = _card_record(host.get_campaign_record(), growth_card_id)
			if _growth_continuity_before_black_well.is_empty() \
					or String(_growth_continuity_before_black_well.get("honor_id", "")) != String(_growth_selection.get("growth_id", "")):
				_fail("Black Well lost the growth attached to %s in an earlier operation" % growth_card_id)
				return
		await _save_screenshot(CONTINUITY_OUTPUT_PATH)
	if not planner.is_plan_valid() or planner.start_button.disabled:
		_fail("%s default plan became invalid after campaign losses: %s" % [scenario_id, planner._validation_errors()])
		return
	if planner.tutorial_toggle.button_pressed:
		await _click_control(planner.tutorial_toggle)
	if planner.tutorial_toggle.button_pressed:
		_fail("%s tutorial toggle did not respond to a real click" % scenario_id)
		return
	await _click_control(planner.start_button)
	await _wait_frames(12)
	if not host.is_grey_ridge_battle_started():
		_fail("%s did not start after the real Start Battle click" % scenario_id)
		return

	var enemy_hq := host.world.buildings.get(SimulationWorld.ENEMY_COMMAND_CENTER_ID) as BuildingState
	if enemy_hq == null:
		_fail("%s has no enemy headquarters target" % scenario_id)
		return
	var army_board := game.army_board
	var army_scroll := army_board.get_node("Margin/Layout/Scroll") as ScrollContainer
	var commander_ids: Array[StringName] = []
	for commander_id_variant in army_board._commander_buttons.keys():
		commander_ids.append(commander_id_variant as StringName)
	commander_ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for commander_id in commander_ids:
		var commander_button := army_board._commander_buttons.get(commander_id) as Button
		await _ensure_visible(army_scroll, commander_button)
		commander_button = army_board._commander_buttons.get(commander_id) as Button
		await _drag_control_to(commander_button, game.camera_controller.world_to_screen(enemy_hq.position))

	var opening_plan_id := String(host.world.enemy_opening_plan_id)
	Engine.time_scale = 64.0
	for _frame in range(2800):
		if game.battle_debrief.visible:
			break
		await process_frame
	Engine.time_scale = 1.0
	await _wait_frames(6)
	if not game.battle_debrief.visible:
		_fail("%s did not reach a debrief within its authoritative time limit" % scenario_id)
		return

	var record_before_actions := host.get_campaign_record()
	if int(record_before_actions.get("battle_count", 0)) != operation_index + 1:
		_fail("%s conclusion did not increment the shared battle count" % scenario_id)
		return
	if String(record_before_actions.get("last_scenario_id", "")) != String(scenario_id):
		_fail("%s conclusion wrote the wrong scenario identity" % scenario_id)
		return
	await _click_control(game.battle_debrief.cards_button)
	if game.battle_debrief._active_view != BattleDebrief.ReviewView.CARDS:
		_fail("campaign purchases require the visible troop-card review")
		return
	if _growth_selection.is_empty():
		_growth_selection = await _select_first_affordable_honor(game.battle_debrief, host)
	var replenishment := await _replenish_first_affordable_card(game.battle_debrief, host)
	if not replenishment.is_empty():
		_replenishment_count += int(replenishment.get("restored", 0))
	var record_after_actions := host.get_campaign_record()
	var operation_report := {
		"operation_number": int(operation.get("operation_number", operation_index + 1)),
		"scenario_id": String(scenario_id),
		"locked_enemy_plan_id": opening_plan_id,
		"result": String(record_after_actions.get("last_result", "unknown")),
		"conclusion_tick": host.current_snapshot.tick,
		"battle_count": int(record_after_actions.get("battle_count", 0)),
		"replacement_points_before_actions": int(record_before_actions.get("replacement_points", 0)),
		"replacement_points_after_actions": int(record_after_actions.get("replacement_points", 0)),
		"merit_after_actions": int(record_after_actions.get("merit", 0)),
		"campaign_days": int(record_after_actions.get("campaign_days", 0)),
		"battle_losses": _total_last_battle_losses(record_before_actions),
		"replenishment": replenishment,
		"shared_card": _card_record(record_after_actions, SHARED_CARD_ID),
	}
	_operation_reports.append(operation_report)
	if operation_index == 1:
		await _save_screenshot(MID_OUTPUT_PATH)
	if operation_index == OPERATIONS.size() - 1:
		await _save_screenshot(FINAL_OUTPUT_PATH)
	print("WARSEED_FOUR_OPERATION_STAGE operation=%d scenario=%s result=%s tick=%d battle_count=%d" % [
		operation_index + 1, String(scenario_id), operation_report["result"],
		host.current_snapshot.tick, operation_report["battle_count"],
	])


func _select_first_affordable_honor(debrief: BattleDebrief, host: SimulationHost) -> Dictionary:
	for row_variant in debrief.rows.get_children():
		var row := row_variant as BoxContainer
		if row == null or not row.has_meta(&"unit_card_id") or row.get_child_count() < 3:
			continue
		var actions := row.get_child(2) as BoxContainer
		var honor := actions.get_child(1) as MenuButton if actions != null and actions.get_child_count() >= 2 else null
		if honor == null or honor.disabled:
			continue
		var card_id := StringName(row.get_meta(&"unit_card_id", ""))
		var before := _card_record(host.get_campaign_record(), card_id)
		await _ensure_debrief_row_visible(debrief, row)
		await _click_control(honor)
		await _wait_frames(4)
		var popup := honor.get_popup()
		var option_index := -1
		for index in range(popup.item_count):
			if not popup.is_item_disabled(index):
				option_index = index
				break
		if option_index < 0 or not popup.visible:
			_fail("affordable honor menu did not expose an enabled keyboard choice")
			return {}
		for _index in range(option_index + 1):
			await _press_key(KEY_DOWN)
		await _press_key(KEY_ENTER)
		await _wait_frames(8)
		var after := _card_record(host.get_campaign_record(), card_id)
		var growth_id := String(after.get("honor_id", ""))
		if growth_id.is_empty() or growth_id == String(before.get("honor_id", "")):
			_fail("real honor menu input did not update the campaign roster")
			return {}
		return {"card_id": String(card_id), "growth_id": growth_id}
	return {}


func _replenish_first_affordable_card(debrief: BattleDebrief, host: SimulationHost) -> Dictionary:
	await _wait_frames(4)
	for row_variant in debrief.rows.get_children():
		var row := row_variant as BoxContainer
		if row == null or not row.has_meta(&"unit_card_id") or row.get_child_count() < 3:
			continue
		var actions := row.get_child(2) as BoxContainer
		var replenish := actions.get_child(0) as Button if actions != null and actions.get_child_count() >= 1 else null
		if replenish == null or replenish.disabled:
			continue
		var card_id := StringName(row.get_meta(&"unit_card_id", ""))
		var before := _card_record(host.get_campaign_record(), card_id)
		await _ensure_debrief_row_visible(debrief, row)
		await _click_control(replenish)
		await _wait_frames(8)
		var after := _card_record(host.get_campaign_record(), card_id)
		var restored := int(after.get("available_strength", 0)) - int(before.get("available_strength", 0))
		if restored <= 0:
			_fail("real replenish click did not restore the selected card")
			return {}
		return {"card_id": String(card_id), "restored": restored}
	return {}

func _card_record(record: Dictionary, card_id: StringName) -> Dictionary:
	var source := (record.get("cards", {}) as Dictionary).get(String(card_id), {}) as Dictionary
	if source.is_empty():
		return {}
	return {
		"authorized_strength": int(source.get("authorized_strength", 0)),
		"available_strength": int(source.get("available_strength", 0)),
		"organization": float(source.get("organization", 0.0)),
		"cumulative_losses": int(source.get("cumulative_losses", 0)),
		"battles_survived": int(source.get("battles_survived", 0)),
		"honor_id": String(source.get("honor_id", "")),
		"equipment_id": String(source.get("equipment_id", "")),
		"last_status": String(source.get("last_status", "unknown")),
		"last_scenario_id": String(source.get("last_scenario_id", "")),
	}


func _total_last_battle_losses(record: Dictionary) -> int:
	var result := 0
	for card_variant in (record.get("cards", {}) as Dictionary).values():
		result += int((card_variant as Dictionary).get("last_battle_losses", 0))
	return result


func _write_report(session_id: String, roster_path: String, final_record: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	var report := {
		"format_version": 1,
		"playtest_session_id": session_id,
		"campaign_roster_path": roster_path,
		"input_mode": "real_mouse_and_keyboard_events",
		"operations": _operation_reports,
		"growth_selection": _growth_selection,
		"replenished_strength": _replenishment_count,
		"black_well_inherited_shared_card": _continuity_before_black_well,
		"black_well_inherited_growth_card": _growth_continuity_before_black_well,
		"final_battle_count": int(final_record.get("battle_count", 0)),
		"final_replacement_points": int(final_record.get("replacement_points", 0)),
		"final_merit": int(final_record.get("merit", 0)),
		"final_shared_card": _card_record(final_record, SHARED_CARD_ID),
		"screenshots": [START_OUTPUT_PATH, MID_OUTPUT_PATH, CONTINUITY_OUTPUT_PATH, FINAL_OUTPUT_PATH],
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("could not open campaign report path")
		return
	file.store_string(JSON.stringify(report, "\t"))
	if file.get_error() != OK:
		_fail("could not write campaign report")


func _wait_for_game_scene(frame_limit: int) -> GameRoot:
	for _frame in range(frame_limit):
		var game := current_scene as GameRoot
		if game != null and game.is_node_ready():
			return game
		await process_frame
	return null


func _wait_for_selector_scene(frame_limit: int) -> BattleSelector:
	for _frame in range(frame_limit):
		var selector := current_scene as BattleSelector
		if selector != null and selector.is_node_ready():
			return selector
		await process_frame
	return null


func _click_control(control: Control) -> void:
	if control == null or not control.is_visible_in_tree() or control.disabled:
		_fail("attempted to click a missing, hidden, or disabled control")
		return
	await _click_position(control.get_global_rect().get_center())


func _click_position(position: Vector2) -> void:
	await _position_physical_pointer(position)
	_send_motion(position, 0)
	await process_frame
	_send_button(position, true)
	await process_frame
	_send_button(position, false)
	await _wait_frames(4)


func _drag_control_to(control: Control, target: Vector2) -> void:
	if control == null or not control.is_visible_in_tree():
		_fail("attempted to drag a missing or hidden commander card")
		return
	var start := control.get_global_rect().get_center()
	await _position_physical_pointer(start)
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


func _position_physical_pointer(point: Vector2) -> void:
	DisplayServer.window_move_to_foreground()
	await _wait_frames(2)
	var usable := DisplayServer.screen_get_usable_rect()
	var position := Vector2(DisplayServer.window_get_position())
	var physical_point := position + point
	var visible_point := physical_point.clamp(Vector2(usable.position) + Vector2(8, 8), Vector2(usable.end) - Vector2(8, 8))
	if not physical_point.is_equal_approx(visible_point):
		DisplayServer.window_set_position(Vector2i(position + visible_point - physical_point))
		await _wait_frames(4)
	root.warp_mouse(point)
	await _wait_frames(2)


func _send_motion(position: Vector2, button_mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - _mouse_position
	event.button_mask = button_mask
	_mouse_position = position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _send_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)


func _press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = keycode
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _ensure_visible(scroll: ScrollContainer, control: Control) -> void:
	if control == null:
		_fail("expected army-board control was not created")
		return
	scroll.ensure_control_visible(control)
	await _wait_frames(5)


func _ensure_debrief_row_visible(debrief: BattleDebrief, row: Control) -> void:
	var scroll := debrief.get_node("Backdrop/Panel/Margin/Layout/RowsScroll") as ScrollContainer
	scroll.ensure_control_visible(row)
	await _wait_frames(5)


func _save_screenshot(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_fail("could not save campaign screenshot %s: %s" % [path, error_string(error)])


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error("FOUR OPERATION CAMPAIGN SELFPLAY: %s" % message)


func _finish(scene: Node) -> void:
	Engine.time_scale = 1.0
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)
