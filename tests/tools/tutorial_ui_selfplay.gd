extends SceneTree

const T5_OUTPUT_PATH := "res://artifacts/tutorial_ui_selfplay_t5.png"
const T6_OUTPUT_PATH := "res://artifacts/tutorial_ui_selfplay_debrief.png"
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _mouse_position := Vector2.ZERO
var _failed := false


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		_fail("tutorial UI self-play requires a real display")
		quit(2)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(VIEWPORT_SIZE)
	root.content_scale_size = VIEWPORT_SIZE
	await _wait_frames(3)

	var game := (load("res://scenes/game/grey_ridge.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	await _wait_frames(5)
	var host := game.simulation_host
	var planner := game.prebattle_planner
	var tutorial := game.tutorial_panel
	tutorial.persistence_enabled = false
	if planner == null or planner.start_button == null or not planner.start_button.visible:
		_fail("prebattle start control is not visible")
		await _finish(game)
		return
	await _click_control(planner.start_button)
	await _wait_frames(8)
	if not host.is_grey_ridge_battle_started() or not tutorial.is_active():
		_fail("battle or tutorial did not start after a real Start Battle click")
		await _finish(game)
		return

	var army_board := game.army_board
	var commander_button := army_board._commander_buttons.get(&"di_tian") as Button
	var central_screen := game.camera_controller.world_to_screen(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	await _drag_control_to(commander_button, central_screen)
	await _wait_frames(8)
	_expect_step(tutorial, TutorialPanel.Step.AIR_RECON, "commander drag")

	await _click_control(game.support_panel.recon_button)
	host.advance_tick()
	await _wait_frames(5)
	_expect_step(tutorial, TutorialPanel.Step.RESERVE_DEPLOYMENT, "air reconnaissance")

	var thunder_deploy := army_board._unit_card_deploy_buttons.get(&"thunder_fire_group") as Button
	await _ensure_army_control_visible(army_board, thunder_deploy)
	if thunder_deploy == null or thunder_deploy.disabled:
		_fail("Thunder Fire reserve deployment is not available after air reconnaissance")
	else:
		await _click_control(thunder_deploy)
	host.advance_tick()
	await _wait_frames(8)
	_expect_step(tutorial, TutorialPanel.Step.FORMATION_ROUTE, "reserve deployment")

	var route_button := army_board._unit_card_route_buttons.get(&"ironwall_assault_group") as Button
	await _ensure_army_control_visible(army_board, route_button)
	route_button = army_board._unit_card_route_buttons.get(&"ironwall_assault_group") as Button
	await _click_control(route_button)
	await _wait_frames(3)
	var ironwall := host.current_snapshot.get_unit_card(&"ironwall_assault_group")
	var formation := host.current_snapshot.get_formation(ironwall.formation_id) if ironwall != null else null
	if formation == null:
		_fail("Ironwall formation disappeared before route training")
	else:
		var route_world := formation.anchor_position + Vector2(0.0, -300.0)
		await _click_position(game.camera_controller.world_to_screen(route_world))
		var submit_button := army_board._unit_card_route_submit_buttons.get(&"ironwall_assault_group") as Button
		await _ensure_army_control_visible(army_board, submit_button)
		submit_button = army_board._unit_card_route_submit_buttons.get(&"ironwall_assault_group") as Button
		await _click_control(submit_button)
	await _wait_frames(16)
	_expect_step(tutorial, TutorialPanel.Step.RETURN_TO_COMMANDER, "whole-card route")

	var return_button := army_board._unit_card_control_buttons.get(&"ironwall_assault_group") as Button
	await _ensure_army_control_visible(army_board, return_button)
	return_button = army_board._unit_card_control_buttons.get(&"ironwall_assault_group") as Button
	await _click_control(return_button)
	await _wait_frames(10)
	_expect_step(tutorial, TutorialPanel.Step.BATTLE_DEBRIEF, "return to commander")

	var tutorial_events := 0
	for event_variant in host.get_playtest_summary().get("events", []):
		var event := event_variant as Dictionary
		if String(event.get("type", "")) == "tutorial_step_completed":
			tutorial_events += 1
	if tutorial_events < 5:
		_fail("expected five recorded tutorial step completions, got %d" % tutorial_events)
	await _save_screenshot(T5_OUTPUT_PATH)
	print("WARSEED_TUTORIAL_UI_SELFPLAY_T5 step=%s events=%d output=%s" % [
		TutorialPanel.Step.keys()[tutorial.current_step], tutorial_events, T5_OUTPUT_PATH,
	])

	var enemy_headquarters := host.world.buildings.get(SimulationWorld.ENEMY_COMMAND_CENTER_ID) as BuildingState
	if enemy_headquarters == null:
		_fail("hostile headquarters is unavailable for the final player objective")
	else:
		for commander_id in [&"bai_jiuyang", &"di_tian", &"lin_mo"]:
			var button := army_board._commander_buttons.get(commander_id) as Button
			await _ensure_army_control_visible(army_board, button)
			await _drag_control_to(button, game.camera_controller.world_to_screen(enemy_headquarters.position))
	Engine.time_scale = 32.0
	for _frame in range(2400):
		if game.battle_debrief.visible:
			break
		await process_frame
	Engine.time_scale = 1.0
	await _wait_frames(5)
	if not game.battle_debrief.visible:
		_fail("accelerated autonomous battle did not reach a real victory or defeat")
	else:
		var record := host.get_campaign_record()
		var cards := record.get("cards", {}) as Dictionary
		var final_events := 0
		for event_variant in host.get_playtest_summary().get("events", []):
			var event := event_variant as Dictionary
			if String(event.get("type", "")) == "tutorial_step_completed":
				final_events += 1
		if tutorial.current_step != TutorialPanel.Step.COMPLETE or final_events < 6:
			_fail("battle debrief did not satisfy tutorial T6")
		await _click_control(game.battle_debrief.cards_button)
		await _wait_frames(3)
		if cards.size() != 4 or game.battle_debrief.rows.get_child_count() != 4:
			_fail("battle debrief did not create four persistent unit-card records")
		await _save_screenshot(T6_OUTPUT_PATH)
		print("WARSEED_TUTORIAL_UI_SELFPLAY_T6 result=%s ticks=%d cards=%d events=%d output=%s" % [
			String(record.get("last_result", "unknown")), host.current_snapshot.tick,
			cards.size(), final_events, T6_OUTPUT_PATH,
		])
	await _finish(game)


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
	await _wait_frames(2)


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


func _ensure_army_control_visible(army_board: ArmyBoard, control: Control) -> void:
	if control == null:
		_fail("army-board control was not created")
		return
	var scroll := army_board.get_node("Margin/Layout/Scroll") as ScrollContainer
	scroll.ensure_control_visible(control)
	await _wait_frames(3)


func _expect_step(tutorial: TutorialPanel, expected: TutorialPanel.Step, action: String) -> void:
	if tutorial.current_step != expected:
		_fail("%s left tutorial at %s instead of %s" % [
			action, TutorialPanel.Step.keys()[tutorial.current_step], TutorialPanel.Step.keys()[expected],
		])


func _save_screenshot(output_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var error := root.get_texture().get_image().save_png(output_path)
	if error != OK:
		_fail("could not save tutorial UI screenshot: %s" % error_string(error))


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error("TUTORIAL UI SELFPLAY: %s" % message)


func _finish(game: Node) -> void:
	Engine.time_scale = 1.0
	if game != null:
		game.queue_free()
	await process_frame
	quit(1 if _failed else 0)
