extends SceneTree

const OUTPUT_PATH := "res://artifacts/fog_forest_ui_selfplay.png"
const DEBRIEF_OUTPUT_PATH := "res://artifacts/fog_forest_ui_debrief.png"
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
	var game := (load("res://scenes/game/fog_forest.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	await _wait_frames(8)
	var host := game.simulation_host
	var planner := game.prebattle_planner
	game.tutorial_panel.persistence_enabled = false
	if host.get_scenario_id() != &"fog_forest" or planner == null or planner.start_button == null:
		_fail("Fog Forest prebattle UI did not initialize")
		await _finish(game)
		return
	if not planner.is_plan_valid() or planner.start_button.disabled:
		_fail("Fog Forest default army plan is not valid: %s" % [planner._validation_errors()])
		await _finish(game)
		return
	await _click_control(planner.start_button)
	await _wait_frames(10)
	print("WARSEED_FOG_FOREST_UI_STAGE battle_started")
	if not host.is_grey_ridge_battle_started() or not game.tutorial_panel.is_active():
		_fail("real Start Battle click did not start Fog Forest with its tutorial")
		await _finish(game)
		return
	_validate_layout(game)

	var army_board := game.army_board
	var scroll := army_board.get_node("Margin/Layout/Scroll") as ScrollContainer
	var node := host.world.strategic_regions[&"forward_supply_node"] as StrategicRegionState
	var bai := army_board._commander_buttons.get(&"bai_jiuyang") as Button
	await _ensure_visible(scroll, bai)
	bai = army_board._commander_buttons.get(&"bai_jiuyang") as Button
	await _drag_control_to(bai, game.camera_controller.world_to_screen(node.position))
	await _wait_frames(8)
	_expect_step(game.tutorial_panel, TutorialPanel.Step.AIR_RECON, "recon commander objective")

	await _click_control(game.support_panel.recon_button)
	await _wait_frames(5)
	_expect_step(game.tutorial_panel, TutorialPanel.Step.RESERVE_DEPLOYMENT, "air recon")

	var pathfinder_deploy := army_board._unit_card_deploy_buttons.get(&"pathfinder_recon_group") as Button
	await _ensure_visible(scroll, pathfinder_deploy)
	pathfinder_deploy = army_board._unit_card_deploy_buttons.get(&"pathfinder_recon_group") as Button
	await _click_control(pathfinder_deploy)
	await _wait_frames(8)
	_expect_step(game.tutorial_panel, TutorialPanel.Step.FORMATION_ROUTE, "pathfinder deployment")

	var route_button := army_board._unit_card_route_buttons.get(&"ironwall_assault_group") as Button
	await _ensure_visible(scroll, route_button)
	route_button = army_board._unit_card_route_buttons.get(&"ironwall_assault_group") as Button
	await _click_control(route_button)
	await _wait_frames(3)
	var ironwall := host.current_snapshot.get_unit_card(&"ironwall_assault_group")
	var formation := host.current_snapshot.get_formation(ironwall.formation_id) if ironwall != null else null
	if formation == null:
		_fail("Ironwall formation disappeared before route training")
	else:
		await _click_position(game.camera_controller.world_to_screen(formation.anchor_position + Vector2(0.0, -320.0)))
		var submit_button := army_board._unit_card_route_submit_buttons.get(&"ironwall_assault_group") as Button
		await _ensure_visible(scroll, submit_button)
		submit_button = army_board._unit_card_route_submit_buttons.get(&"ironwall_assault_group") as Button
		await _click_control(submit_button)
	await _wait_frames(14)
	_expect_step(game.tutorial_panel, TutorialPanel.Step.RETURN_TO_COMMANDER, "escort route")

	var return_button := army_board._unit_card_control_buttons.get(&"ironwall_assault_group") as Button
	await _ensure_visible(scroll, return_button)
	return_button = army_board._unit_card_control_buttons.get(&"ironwall_assault_group") as Button
	await _click_control(return_button)
	await _wait_frames(8)
	_expect_step(game.tutorial_panel, TutorialPanel.Step.BATTLE_DEBRIEF, "return to commander")

	var di := army_board._commander_buttons.get(&"di_tian") as Button
	await _ensure_visible(scroll, di)
	di = army_board._commander_buttons.get(&"di_tian") as Button
	await _drag_control_to(di, game.camera_controller.world_to_screen(node.position))
	Engine.time_scale = 12.0
	for _frame in range(600):
		if host.world.escort_supply_node_active or game.battle_debrief.visible:
			break
		await process_frame
	Engine.time_scale = 1.0
	if not host.world.escort_supply_node_active:
		_fail("real commander drag did not deliver the logistics column to the forward node")
	print("WARSEED_FOG_FOREST_UI_STAGE node=%s tick=%d" % [host.world.escort_supply_node_active, host.current_snapshot.tick])
	var logistics := host.current_snapshot.get_unit_card(&"frontline_logistics_column")
	if logistics == null or logistics.member_entity_ids.is_empty():
		_fail("logistics card did not expand into visible battlefield entities")
	else:
		for entity_id in logistics.member_entity_ids:
			if not game.world_presentation._proxies.has(entity_id):
				_fail("transport E%d has no battlefield proxy" % entity_id)
	await _save_screenshot(OUTPUT_PATH)

	var enemy_hq := host.world.buildings.get(SimulationWorld.ENEMY_COMMAND_CENTER_ID) as BuildingState
	for commander_id in [&"bai_jiuyang", &"di_tian", &"lin_mo"]:
		var commander_button := army_board._commander_buttons.get(commander_id) as Button
		await _ensure_visible(scroll, commander_button)
		commander_button = army_board._commander_buttons.get(commander_id) as Button
		await _drag_control_to(commander_button, game.camera_controller.world_to_screen(enemy_hq.position))
	Engine.time_scale = 32.0
	for _frame in range(2600):
		if game.battle_debrief.visible:
			break
		await process_frame
	Engine.time_scale = 1.0
	if not game.battle_debrief.visible:
		_fail("Fog Forest did not reach a debrief after real player orders")
	else:
		var record := host.get_campaign_record()
		if String(record.get("scenario_id", "")) != "fog_forest" or (record.get("cards", {}) as Dictionary).size() != 6:
			_fail("Fog Forest debrief did not persist its six-card roster")
		await _wait_frames(2)
		await _save_screenshot(DEBRIEF_OUTPUT_PATH)
	print("WARSEED_FOG_FOREST_UI_SELFPLAY node=%s debrief=%s tick=%d map=%s" % [
		host.world.escort_supply_node_active, game.battle_debrief.visible,
		host.current_snapshot.tick, game.get_grey_ridge_map_rect(),
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


func _ensure_visible(scroll: ScrollContainer, control: Control) -> void:
	if control == null:
		_fail("expected army-board control was not created")
		return
	scroll.ensure_control_visible(control)
	await _wait_frames(4)


func _expect_step(tutorial: TutorialPanel, expected: TutorialPanel.Step, action: String) -> void:
	if tutorial.current_step != expected:
		_fail("%s left tutorial at %s instead of %s" % [action, TutorialPanel.Step.keys()[tutorial.current_step], TutorialPanel.Step.keys()[expected]])


func _save_screenshot(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_fail("could not save Fog Forest screenshot: %s" % error_string(error))


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error("FOG FOREST UI SELFPLAY: %s" % message)


func _finish(game: Node) -> void:
	Engine.time_scale = 1.0
	if game != null:
		game.queue_free()
	await process_frame
	quit(1 if _failed else 0)
