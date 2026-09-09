extends SceneTree

const BATTLE_OUTPUT_PATH := "res://artifacts/black_well_ui_battle.png"
const DEBRIEF_OUTPUT_PATH := "res://artifacts/black_well_ui_debrief.png"
const CONTINUITY_OUTPUT_PATH := "res://artifacts/black_well_ui_continuity.png"
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
	await _wait_frames(4)
	var game := (load("res://scenes/game/black_well.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	current_scene = game
	await _wait_frames(10)
	print("WARSEED_BLACK_WELL_UI_STAGE prebattle_ready")
	var host := game.simulation_host
	var planner := game.prebattle_planner
	var battlefield_bounds := host.world.battle_definition.battlefield_bounds
	if host.get_scenario_id() != &"black_well" or planner == null or planner.start_button == null:
		_fail("Black Well prebattle UI did not initialize")
		await _finish(game)
		return
	if planner._commander_definitions.size() != 5 or planner._unit_card_definitions.size() != 12:
		_fail("prebattle planner does not expose five commanders and twelve cards")
	if not planner.is_plan_valid() or planner.start_button.disabled:
		_fail("default Black Well army plan is invalid: %s" % [planner._validation_errors()])
		await _finish(game)
		return
	await _touch_five_commander_setups(planner)
	print("WARSEED_BLACK_WELL_UI_STAGE commander_setups_touched")
	await _click_control(planner.start_button)
	await _wait_frames(12)
	if not host.is_grey_ridge_battle_started() or not game.tutorial_panel.is_active():
		_fail("real Start Battle click did not start Black Well training")
		await _finish(game)
		return
	print("WARSEED_BLACK_WELL_UI_STAGE battle_started")
	_validate_layout_and_world(game)

	var army_board := game.army_board
	var army_scroll := army_board.get_node("Margin/Layout/Scroll") as ScrollContainer
	var regions := host.world.battle_definition.region_dictionary()
	var lu := army_board._commander_buttons.get(&"lu_zheng") as Button
	await _ensure_visible(army_scroll, lu)
	await _drag_control_to(lu, game.camera_controller.world_to_screen((regions[&"black_well_core"] as BattleRegionDefinition).position))
	await _wait_for_tutorial_step(game.tutorial_panel, TutorialPanel.Step.AIR_RECON, 60, "Lu Zheng core objective")
	print("WARSEED_BLACK_WELL_UI_STAGE core_ordered")

	var gu := army_board._commander_buttons.get(&"gu_hanxing") as Button
	await _ensure_visible(army_scroll, gu)
	await _drag_control_to(gu, game.camera_controller.world_to_screen((regions[&"slag_rail"] as BattleRegionDefinition).position))
	await _wait_for_tutorial_step(game.tutorial_panel, TutorialPanel.Step.RESERVE_DEPLOYMENT, 60, "Gu Hanxing second axis")
	print("WARSEED_BLACK_WELL_UI_STAGE second_axis_ordered")

	var recovery_deploy := army_board._unit_card_deploy_buttons.get(&"battlefield_recovery_company") as Button
	await _ensure_visible(army_scroll, recovery_deploy)
	recovery_deploy = army_board._unit_card_deploy_buttons.get(&"battlefield_recovery_company") as Button
	await _click_control(recovery_deploy)
	await _wait_for_tutorial_step(game.tutorial_panel, TutorialPanel.Step.FORMATION_ROUTE, 60, "headquarters reserve deployment")
	print("WARSEED_BLACK_WELL_UI_STAGE reserve_deployed")

	lu = army_board._commander_buttons.get(&"lu_zheng") as Button
	await _ensure_visible(army_scroll, lu)
	await _drag_control_to(lu, game.camera_controller.world_to_screen((regions[&"withdrawal_corridor"] as BattleRegionDefinition).position))
	Engine.time_scale = 16.0
	for _frame in range(420):
		var guard := host.current_snapshot.get_unit_card(&"blackwell_guard_battalion")
		if guard != null and guard.deployment_state == UnitCardState.DeploymentState.WITHDRAWN:
			break
		await process_frame
	Engine.time_scale = 1.0
	var withdrawn_guard := host.current_snapshot.get_unit_card(&"blackwell_guard_battalion")
	if withdrawn_guard == null or withdrawn_guard.deployment_state != UnitCardState.DeploymentState.WITHDRAWN:
		_fail("real commander drag did not withdraw the complete Black Well guard card")
	await _wait_for_tutorial_step(game.tutorial_panel, TutorialPanel.Step.RETURN_TO_COMMANDER, 30, "complete card withdrawal")
	print("WARSEED_BLACK_WELL_UI_STAGE withdrawal_checked state=%s" % [withdrawn_guard.deployment_state if withdrawn_guard != null else -1])
	await _save_screenshot(BATTLE_OUTPUT_PATH)

	Engine.time_scale = 64.0
	for _frame in range(1800):
		if game.battle_debrief.visible:
			break
		await process_frame
	Engine.time_scale = 1.0
	if not game.battle_debrief.visible:
		_fail("Black Well did not reach a debrief within its authoritative time limit")
		await _finish(game)
		return
	print("WARSEED_BLACK_WELL_UI_STAGE debrief_visible tick=%d" % host.current_snapshot.tick)
	await _wait_for_tutorial_step(game.tutorial_panel, TutorialPanel.Step.BATTLE_DEBRIEF, 30, "battle conclusion")
	await _wait_frames(4)
	await _select_first_affordable_equipment(game.battle_debrief)
	var growth_card_id := _record_growth_card(host.get_campaign_record())
	if growth_card_id.is_empty():
		_fail("real debrief input did not attach an equipment choice to a persistent card")
	if not ArmyRosterStore.runtime_persistence_allowed() \
			and not ArmyRosterStore.save_record(host.get_campaign_record()):
		_fail("isolated UI self-play could not persist its test-only campaign roster")
	print("WARSEED_BLACK_WELL_UI_STAGE growth_selected card=%s" % growth_card_id)
	await _save_screenshot(DEBRIEF_OUTPUT_PATH)

	await _click_control(game.battle_debrief.return_to_operations_button)
	await _wait_frames(16)
	var selector := current_scene as BattleSelector
	if selector == null:
		_fail("Return to Operations did not open the battle selector")
	else:
		if not selector._black_well_continuity_confirmed:
			_fail("selector did not confirm the Black Well growth on the same card ID")
		var persisted := ArmyRosterStore.load_record()
		var persisted_card := (persisted.get("cards", {}) as Dictionary).get(String(growth_card_id), {}) as Dictionary
		if persisted_card.is_empty() or String(persisted_card.get("equipment_id", "")).is_empty():
			_fail("shared roster lost the selected Black Well equipment after scene return")
		await _save_screenshot(CONTINUITY_OUTPUT_PATH)
	print("WARSEED_BLACK_WELL_UI_STAGE operations_returned selector=%s" % [selector != null])
	print("WARSEED_BLACK_WELL_UI_SELFPLAY withdrawn=%s growth_card=%s selector=%s map=%s" % [
		withdrawn_guard.withdrawn_strength if withdrawn_guard != null else 0,
		growth_card_id, selector != null, battlefield_bounds,
	])
	await _finish(selector)


func _touch_five_commander_setups(planner: PrebattlePlanner) -> void:
	for panel_variant in planner.commander_grid.get_children():
		var panel := panel_variant as Control
		var posture := _find_nth_option_button(panel, 1)
		if posture == null:
			_fail("commander setup panel is missing its posture menu")
			continue
		await _click_control(posture)
		_send_key(KEY_ESCAPE, true)
		await process_frame
		_send_key(KEY_ESCAPE, false)
		await _wait_frames(2)


func _find_nth_option_button(root_control: Control, target_index: int) -> OptionButton:
	var found: Array[OptionButton] = []
	_find_option_buttons(root_control, found)
	return found[target_index] if target_index >= 0 and target_index < found.size() else null


func _find_option_buttons(node: Node, found: Array[OptionButton]) -> void:
	for child in node.get_children():
		if child is OptionButton:
			found.append(child as OptionButton)
		_find_option_buttons(child, found)


func _select_first_affordable_equipment(debrief: BattleDebrief) -> void:
	var equipment_menu: MenuButton
	for row_variant in debrief.rows.get_children():
		var row := row_variant as BoxContainer
		if row == null or row.get_child_count() < 3:
			continue
		var actions := row.get_child(2) as BoxContainer
		if actions != null and actions.get_child_count() >= 3:
			var candidate := actions.get_child(2) as MenuButton
			if candidate != null and not candidate.disabled:
				equipment_menu = candidate
				break
	if equipment_menu == null:
		_fail("debrief exposes no affordable equipment growth menu")
		return
	await _click_control(equipment_menu)
	await _wait_frames(4)
	var popup := equipment_menu.get_popup()
	var option_index := -1
	for index in range(popup.item_count):
		if not popup.is_item_disabled(index):
			option_index = index
			break
	if option_index < 0 or not popup.visible:
		_fail("equipment popup did not expose an enabled choice")
		return
	for _index in range(option_index + 1):
		_send_key(KEY_DOWN, true)
		await process_frame
		_send_key(KEY_DOWN, false)
		await process_frame
	_send_key(KEY_ENTER, true)
	await process_frame
	_send_key(KEY_ENTER, false)
	await _wait_frames(8)


func _record_growth_card(record: Dictionary) -> StringName:
	var cards := record.get("cards", {}) as Dictionary
	for card_id in cards:
		var card := cards[card_id] as Dictionary
		if not String(card.get("equipment_id", "")).is_empty():
			return StringName(card_id)
	return &""


func _validate_layout_and_world(game: GameRoot) -> void:
	var map_rect := game.get_grey_ridge_map_rect()
	if map_rect.size.x < 760.0 or map_rect.size.y < 480.0:
		_fail("central map viewport is too small at 1280x720: %s" % map_rect)
	var expected_bounds := game.simulation_host.world.battle_definition.battlefield_bounds
	if game.camera_controller.get_world_rect() != expected_bounds or game.minimap.world_rect != expected_bounds:
		_fail("camera and minimap did not adopt the Black Well scenario bounds")
	if not game.camera_controller.get_visible_world_rect().encloses(expected_bounds):
		_fail("initial camera fit does not show the complete expanded Black Well map")
	for panel in [game.army_board, game.task_panel, game.support_panel, game.minimap, game.scenario_status]:
		if panel.visible and panel.get_global_rect().intersection(map_rect).get_area() > 4.0:
			_fail("%s overlaps the dedicated central map viewport" % panel.name)
	for unit in game.simulation_host.current_snapshot.units:
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID \
				and not game.world_presentation._proxies.has(unit.entity_id):
			_fail("friendly entity E%d has no visible battlefield proxy" % unit.entity_id)


func _wait_for_tutorial_step(tutorial: TutorialPanel, expected: TutorialPanel.Step, frame_limit: int, action: String) -> void:
	for _frame in range(frame_limit):
		if tutorial.current_step == expected:
			return
		await process_frame
	_fail("%s left tutorial at %s instead of %s" % [
		action, TutorialPanel.Step.keys()[tutorial.current_step], TutorialPanel.Step.keys()[expected],
	])


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


func _send_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _ensure_visible(scroll: ScrollContainer, control: Control) -> void:
	if control == null:
		_fail("expected army-board control was not created")
		return
	scroll.ensure_control_visible(control)
	await _wait_frames(5)


func _save_screenshot(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_fail("could not save Black Well UI screenshot: %s" % error_string(error))


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error("BLACK WELL UI SELFPLAY: %s" % message)


func _finish(scene: Node) -> void:
	Engine.time_scale = 1.0
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)
