extends SceneTree

const OUTPUT_PATH := "res://artifacts/broken_bridge_ui_selfplay.png"
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _mouse_position := Vector2.ZERO
var _failed := false


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		_fail("real-input self-play requires a display")
		quit(2)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(VIEWPORT_SIZE)
	root.content_scale_size = VIEWPORT_SIZE
	await _wait_frames(3)
	var game := (load("res://scenes/game/broken_bridge.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	await _wait_frames(8)
	var host := game.simulation_host
	var planner := game.prebattle_planner
	if host.get_scenario_id() != &"broken_bridge" or planner == null or planner.start_button == null:
		_fail("Broken Bridge prebattle UI did not initialize")
		await _finish(game)
		return
	print("WARSEED_BROKEN_BRIDGE_UI_PREBATTLE valid=%s disabled=%s errors=%s starters=%s" % [
		planner.is_plan_valid(), planner.start_button.disabled, planner._validation_errors(), planner.get_plan().starting_unit_card_ids,
	])
	if planner.tutorial_toggle.button_pressed:
		await _click_control(planner.tutorial_toggle)
	await _click_control(planner.start_button)
	await _wait_frames(10)
	if not host.is_grey_ridge_battle_started():
		_fail("real Start Battle click did not start Broken Bridge")
		await _finish(game)
		return
	_validate_layout(game)

	var army_board := game.army_board
	var engineer_card := army_board._unit_card_buttons.get(&"bridge_engineer_group") as Button
	await _ensure_visible(army_board.get_node("Margin/Layout/Scroll") as ScrollContainer, engineer_card)
	await _click_control(engineer_card)
	var support_scroll := game.support_panel.get_node("Margin/Scroll") as ScrollContainer
	await _ensure_visible(support_scroll, game.support_panel.engineering_button)
	for _frame in range(180):
		if not game.support_panel.engineering_button.disabled:
			break
		await process_frame
	if game.support_panel.engineering_button.disabled:
		_fail("engineering support did not become available after selecting its deployed card")
	else:
		await _click_control(game.support_panel.engineering_button)
		Engine.time_scale = 4.0
		for _frame in range(240):
			if host.world.opened_engineering_routes.has(&"east_engineering_ford"):
				break
			await process_frame
		Engine.time_scale = 1.0
	if not host.world.opened_engineering_routes.has(&"east_engineering_ford"):
		_fail("real engineering-button click did not open the side route")

	var route_button := army_board._unit_card_route_buttons.get(&"ironwall_assault_group") as Button
	await _ensure_visible(army_board.get_node("Margin/Layout/Scroll") as ScrollContainer, route_button)
	await _click_control(route_button)
	if not game.input_controller.is_unit_card_route_planning(&"ironwall_assault_group"):
		_fail("real Route / Line click did not enter route planning")
	for _frame in range(180):
		if game.task_panel.instruction_label.text.contains(GameText.t(&"STATUS_ROUTE_TARGETING")):
			break
		await process_frame
	if not game.task_panel.instruction_label.text.contains(GameText.t(&"STATUS_ROUTE_TARGETING")):
		_fail("route planning did not expose its current mouse and keyboard controls")
	if not game.route_mode_hint.visible \
		or game.route_mode_hint_label.text != GameText.t(&"ROUTE_MODE_HINT_FORMATION") \
		or not game.route_mode_hint_label.text.contains("Enter") \
		or not game.route_mode_hint_label.text.contains("Backspace"):
		_fail("route planning did not show the persistent map shortcut hint: %s" % game.route_mode_hint_label.text)
	var blocked_target := Vector2.ZERO
	var blocked_target_found := false
	var map_hit_rect := game.get_grey_ridge_map_rect().grow(-36.0)
	for blocked_cell in host.world.logic_grid.get_blocked_cells():
		var candidate := host.world.logic_grid.cell_to_world(blocked_cell)
		if map_hit_rect.has_point(game.camera_controller.world_to_screen(candidate)):
			blocked_target = candidate
			blocked_target_found = true
			break
	if not blocked_target_found:
		_fail("could not find a visible blocked cell for rejection guidance testing")
	else:
		await _click_position(game.camera_controller.world_to_screen(blocked_target))
		var submit_button := army_board._unit_card_route_submit_buttons.get(&"ironwall_assault_group") as Button
		await _ensure_visible(army_board.get_node("Margin/Layout/Scroll") as ScrollContainer, submit_button)
		await _click_control(submit_button)
		for _frame in range(180):
			if game.task_panel.instruction_label.text.contains(GameText.t(&"REASON_PATH_UNAVAILABLE")):
				break
			await process_frame
		var rejection_guidance := game.task_panel.instruction_label.text
		if not game.input_controller.is_unit_card_route_planning(&"ironwall_assault_group"):
			_fail("a rejected route unexpectedly closed route planning")
		if not rejection_guidance.contains(GameText.t(&"REASON_PATH_UNAVAILABLE")) \
				or not rejection_guidance.contains(GameText.command_recovery(CommandValidationResult.Reason.PATH_UNAVAILABLE)) \
				or not rejection_guidance.contains(GameText.t(&"STATUS_ROUTE_TARGETING")):
			_fail("rejected route did not keep cause, recovery, and active controls visible: %s" % rejection_guidance)
		await _save_screenshot(OUTPUT_PATH)
	_send_key(KEY_C, true)
	await process_frame
	_send_key(KEY_C, false)
	await _wait_frames(4)
	if game.input_controller.is_unit_card_route_planning():
		_fail("C did not cancel route planning")
	if game.route_mode_hint.visible:
		_fail("route shortcut hint remained visible after C cancelled planning")

	var di_tian := army_board._commander_buttons.get(&"di_tian") as Button
	await _ensure_visible(army_board.get_node("Margin/Layout/Scroll") as ScrollContainer, di_tian)
	var bridge := host.world.battle_definition.region_dictionary()[&"central_relay"] as BattleRegionDefinition
	await _drag_control_to(di_tian, game.camera_controller.world_to_screen(bridge.position))
	await _wait_frames(10)
	var commander := host.current_snapshot.get_commander(&"di_tian")
	if commander == null or commander.target_position.distance_to(bridge.position) > 640.0:
		_fail("real commander-card drag did not establish the bridge objective")
	if not FileAccess.file_exists(OUTPUT_PATH):
		await _save_screenshot(OUTPUT_PATH)

	var enemy_hq := host.world.buildings.get(SimulationWorld.ENEMY_COMMAND_CENTER_ID) as BuildingState
	for commander_id in [&"di_tian", &"lin_mo"]:
		var commander_button := army_board._commander_buttons.get(commander_id) as Button
		await _ensure_visible(army_board.get_node("Margin/Layout/Scroll") as ScrollContainer, commander_button)
		await _drag_control_to(commander_button, game.camera_controller.world_to_screen(enemy_hq.position))
	Engine.time_scale = 32.0
	for _frame in range(2400):
		if game.battle_debrief.visible:
			break
		await process_frame
	Engine.time_scale = 1.0
	if not game.battle_debrief.visible:
		_fail("autonomous battle did not reach a debrief after real player orders")
	else:
		var record := host.get_campaign_record()
		if String(record.get("scenario_id", "")) != "broken_bridge" or (record.get("cards", {}) as Dictionary).size() != 6:
			_fail("Broken Bridge debrief did not persist its own six-card roster")
	print("WARSEED_BROKEN_BRIDGE_UI_SELFPLAY route_open=%s debrief=%s tick=%d output=%s" % [
		host.world.opened_engineering_routes.has(&"east_engineering_ford"), game.battle_debrief.visible,
		host.current_snapshot.tick, OUTPUT_PATH,
	])
	await _finish(game)


func _validate_layout(game: GameRoot) -> void:
	var map_rect := game.get_grey_ridge_map_rect()
	if map_rect.size.x < 760.0 or map_rect.size.y < 480.0:
		_fail("central map viewport is too small at 1280x720: %s" % map_rect)
	for panel in [game.army_board, game.task_panel, game.support_panel, game.minimap, game.scenario_status]:
		if not panel.visible:
			continue
		var overlap: Rect2 = panel.get_global_rect().intersection(map_rect)
		if overlap.size.x > 2.0 and overlap.size.y > 2.0:
			_fail("%s overlaps the dedicated map viewport by %s" % [panel.name, overlap.size])


func _click_control(control: Control) -> void:
	if control == null or not control.is_visible_in_tree():
		_fail("attempted to click a missing or hidden control")
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
	await _wait_frames(5)


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


func _ensure_visible(scroll: ScrollContainer, control: Control) -> void:
	if control == null:
		_fail("expected control was not created")
		return
	scroll.ensure_control_visible(control)
	await _wait_frames(4)


func _save_screenshot(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_fail("could not save UI screenshot: %s" % error_string(error))


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error("BROKEN BRIDGE UI SELFPLAY: %s" % message)


func _finish(game: Node) -> void:
	Engine.time_scale = 1.0
	if game != null:
		game.queue_free()
	await process_frame
	quit(1 if _failed else 0)
