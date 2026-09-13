extends SceneTree

const REPORT_PATH := "res://artifacts/accessibility_resolution_matrix.json"
const RESOLUTION_ARGUMENT := "--matrix-resolution="
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1600),
	Vector2i(640, 800),
	Vector2i(480, 800),
]

var _mouse_position := Vector2.ZERO
var _failed := false
var _reports: Array[Dictionary] = []


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		_fail("accessibility resolution matrix requires a display")
		quit(2)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	var requested_resolutions := _requested_resolutions()
	for resolution in requested_resolutions:
		await _run_resolution(resolution)
		if _failed:
			break
	_write_report()
	print("WARSEED_ACCESSIBILITY_RESOLUTION_MATRIX resolutions=%d report=%s" % [_reports.size(), REPORT_PATH])
	await _finish(current_scene)


func _run_resolution(resolution: Vector2i) -> void:
	# Update the owning Window before the native size so a pending resize from
	# the previous scene cannot reapply its old size between matrix entries.
	root.content_scale_size = resolution
	root.size = resolution
	DisplayServer.window_set_size(resolution)
	# Keep the right-side options physically reachable when testing a window wider than the monitor.
	var screen_rect := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(Vector2i(mini(screen_rect.position.x, screen_rect.end.x - resolution.x), screen_rect.position.y))
	DisplayServer.window_move_to_foreground()
	root.content_scale_size = resolution
	_mouse_position = Vector2.ZERO
	await _wait_frames(12)
	var viewport_rect := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	if Vector2i(viewport_rect.size) != resolution:
		_fail("requested %s but Godot exposed viewport %s" % [resolution, viewport_rect.size])
		return
	var resolution_report := {
		"resolution": "%dx%d" % [resolution.x, resolution.y],
		"viewport_size": [viewport_rect.size.x, viewport_rect.size.y],
		"screens": {},
	}

	var selector := (load("res://scenes/game/battle_selector.tscn") as PackedScene).instantiate() as BattleSelector
	root.add_child(selector)
	current_scene = selector
	await _wait_frames(10)
	_validate_selector(selector, viewport_rect)
	await _save_screenshot(resolution, "operation_selector")
	resolution_report["screens"]["operation_selector"] = _screen_report([
		selector.title_label, selector.battle_list, selector.deploy_button,
		selector.replay_tutorial_button, selector.language_button, selector.exit_button,
	])
	await _click_control(selector.get_battle_button(&"grey_ridge"))
	if selector.get_selected_battle() == null or selector.get_selected_battle().scenario_id != &"grey_ridge":
		_fail("%s real operation click did not select Grey Ridge" % resolution)
	if root.gui_get_focus_owner() != selector.deploy_button:
		_fail("%s selector did not move keyboard focus to Deploy" % resolution)
	await _press_key(KEY_TAB)
	_validate_focus_owner(viewport_rect, "%s selector Tab" % resolution)
	await _click_control(selector.deploy_button)
	var game := await _wait_for_game_scene(90)
	if game == null:
		_fail("%s selector did not open Grey Ridge" % resolution)
		return

	var planner := game.prebattle_planner
	var planner_scroll := planner.get_node("Backdrop/Margin/Layout/Scroll") as ScrollContainer
	planner_scroll.ensure_control_visible(planner.tutorial_toggle)
	await _wait_frames(6)
	_validate_prebattle(planner, viewport_rect)
	await _save_screenshot(resolution, "prebattle")
	resolution_report["screens"]["prebattle"] = _screen_report([
		planner.get_node("Backdrop/Margin/Layout/Header"), planner_scroll,
		planner.roster_bar, planner.tutorial_toggle, planner.start_button,
		planner.get_node("Backdrop/Margin/Layout/Footer"),
	])
	if planner.tutorial_toggle.button_pressed:
		await _click_control(planner.tutorial_toggle)
	await _click_control(planner.start_button)
	await _wait_frames(14)
	if not game.simulation_host.is_grey_ridge_battle_started():
		_fail("%s Grey Ridge did not start from the real prebattle click" % resolution)
		return

	await _validate_battlefield(game, viewport_rect)
	await _verify_staff_plans(game, resolution)
	await _verify_tactical_planning(game, resolution)
	await _verify_contextual_card_decisions(game, resolution, viewport_rect)
	await _verify_control_handoff(game, resolution)
	await _verify_headquarters_decision(game, resolution)
	var zoom_report := await _verify_map_wheel_scope(game)
	await _save_screenshot(resolution, "battlefield")
	resolution_report["screens"]["battlefield"] = {
		"map_rect": _rect_array(game.get_grey_ridge_map_rect()),
		"map_wheel_scope": zoom_report,
		"pause_button": _rect_array(game.pause_button.get_global_rect()),
		"decision_desk": _rect_array(game.task_panel.get_global_rect()),
		"commander_board": _rect_array(game.army_board.get_global_rect()),
	}

	await _position_physical_pointer(game.pause_button.get_global_rect().get_center())
	_send_motion(game.pause_button.get_global_rect().get_center(), 0)
	await process_frame
	var pause_hover := root.gui_get_hovered_control()
	if pause_hover != game.pause_button:
		_fail("%s pause button is covered by %s" % [resolution, pause_hover.get_path() if pause_hover != null else "nothing"])
	var pause_press_events: Array[int] = []
	game.pause_button.pressed.connect(func() -> void: pause_press_events.append(1), CONNECT_ONE_SHOT)
	await _click_control(game.pause_button)
	if pause_press_events.is_empty():
		_fail("%s pause button was hovered but did not emit pressed" % resolution)
	await _wait_frames(5)
	_validate_pause(game.pause_menu, viewport_rect)
	if root.gui_get_focus_owner() != game.pause_menu.continue_button:
		_fail("%s visible pause button did not focus Continue" % resolution)
	await _click_control(game.pause_menu.continue_button)
	await _wait_frames(5)
	if paused or game.pause_menu.backdrop.visible:
		_fail("%s Continue did not resume after using the visible pause button" % resolution)
		return
	await _press_key(KEY_ESCAPE)
	await _wait_frames(5)
	_validate_pause(game.pause_menu, viewport_rect)
	if root.gui_get_focus_owner() != game.pause_menu.continue_button:
		_fail("%s pause menu did not focus Continue" % resolution)
	await _press_key(KEY_TAB)
	_validate_focus_owner(viewport_rect, "%s pause Tab" % resolution)
	await _save_screenshot(resolution, "pause")
	resolution_report["screens"]["pause"] = _screen_report([
		game.pause_menu.get_node("Backdrop/Menu"), game.pause_menu.continue_button,
		game.pause_menu.language_selector, game.pause_menu.operations_button,
		game.pause_menu.exit_button,
	])
	await _press_key(KEY_ESCAPE)
	await _wait_frames(5)
	if paused or game.pause_menu.backdrop.visible:
		_fail("%s second Esc did not close the pause menu and resume simulation" % resolution)
		return

	var record := ArmyRosterStore.build_battle_record(
		game.simulation_host.current_snapshot,
		{},
		&"grey_ridge"
	)
	game.battle_debrief.show_debrief(record)
	await _wait_frames(8)
	await _validate_debrief(game.battle_debrief, viewport_rect, game.simulation_host.current_snapshot.unit_cards.size())
	await _activate_debrief_button(game.battle_debrief.timeline_button)
	await _validate_debrief_rows(game.battle_debrief, viewport_rect, &"turning_point_id", -1, "turning points")
	await _save_screenshot(resolution, "debrief_timeline")
	await _activate_debrief_button(game.battle_debrief.cards_button)
	await _validate_debrief_rows(game.battle_debrief, viewport_rect, &"unit_card_id", game.simulation_host.current_snapshot.unit_cards.size(), "unit cards")
	await _focus_last_debrief_row(game.battle_debrief, viewport_rect)
	await _save_screenshot(resolution, "debrief_cards")
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		game.battle_debrief.refresh_locale()
		await _wait_frames(5)
		await _validate_debrief_rows(game.battle_debrief, viewport_rect, &"unit_card_id", game.simulation_host.current_snapshot.unit_cards.size(), "localized unit cards")
		await _save_screenshot(resolution, "debrief_cards_" + locale)
	await _activate_debrief_button(game.battle_debrief.causes_button)
	await _validate_debrief_rows(game.battle_debrief, viewport_rect, &"cause_id", -1, "causes")
	await _save_screenshot(resolution, "debrief_causes")
	resolution_report["screens"]["debrief"] = _screen_report([
		game.battle_debrief.get_node("Backdrop/Panel"),
		game.battle_debrief.timeline_button, game.battle_debrief.cards_button, game.battle_debrief.causes_button,
		game.battle_debrief.get_node("Backdrop/Panel/Margin/Layout/RowsScroll"),
		game.battle_debrief.fight_again_button,
		game.battle_debrief.return_to_operations_button, game.battle_debrief.feedback_button,
	])
	game.battle_debrief.feedback_button.pressed.emit()
	await _wait_frames(6)
	_send_motion(game.playtest_feedback_dialog.overall_rating.get_global_rect().get_center(), 0)
	await _wait_frames(6)
	await _validate_feedback(game.playtest_feedback_dialog, viewport_rect)
	await _save_screenshot(resolution, "feedback")
	resolution_report["screens"]["feedback"] = _screen_report([
		game.playtest_feedback_dialog.panel,
		game.playtest_feedback_dialog.overall_rating,
		game.playtest_feedback_dialog.priority_area,
		game.playtest_feedback_dialog.submit_button,
		game.playtest_feedback_dialog.retry_button,
		game.playtest_feedback_dialog.close_button,
	])
	game.playtest_feedback_dialog.visible = false
	game.battle_debrief.visible = false
	await _wait_frames(4)
	# A tall test window extends below the physical monitor. Bring the real
	# bottom-right history target onto the monitor before holding/clicking it.
	DisplayServer.window_set_position(Vector2i(mini(screen_rect.position.x, screen_rect.end.x - resolution.x), mini(screen_rect.position.y, screen_rect.end.y - resolution.y)))
	await _wait_frames(4)
	await _position_physical_pointer(game.command_desk.history_button.get_global_rect().get_center())
	_send_motion(game.command_desk.history_button.get_global_rect().get_center(), 0)
	await _wait_frames(2)
	if root.gui_get_hovered_control() != game.command_desk.history_button:
		_fail("%s history button hover was covered by %s" % [resolution, root.gui_get_hovered_control()])
	await _click_control(game.command_desk.history_button)
	await _wait_frames(5)
	if not game.command_desk.history_popup.visible or game.command_desk.get_decision_history_count() <= 0:
		_fail("%s decision history did not open with the submitted intent" % resolution)
	else:
		_expect_control_in_viewport(game.command_desk.history_text, viewport_rect, "decision history content")
		await _save_screenshot(resolution, "decision_history")
	game.command_desk.history_popup.hide()
	await _wait_frames(4)
	game.command_desk._perform_exception_action(&"stale:resolution-matrix", CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER)
	await _wait_frames(5)
	if not game.command_desk.decision_failure_dialog.visible or not game.command_desk.decision_failure_dialog.dialog_text.contains(GameText.t(&"DECISION_RESPONSE_STALE")):
		_fail("%s stale decision did not open a localized failure dialog" % resolution)
	elif game.command_desk.decision_failure_dialog.size.x > viewport_rect.size.x + 1.0:
		_fail("%s decision failure dialog is wider than the viewport" % resolution)
	else:
		await _save_screenshot(resolution, "decision_failure")
	print("WARSEED_ACCESSIBILITY_STAGE resolution=%s map=%s" % [resolution, game.get_grey_ridge_map_rect()])
	game.queue_free()
	await _wait_frames(5)
	current_scene = null
	resolution_report["screens"]["twelve_card_overview"] = await _verify_twelve_card_overview(resolution)
	resolution_report["screens"]["composition_persistence"] = await _verify_composition_persistence(resolution)
	resolution_report["screens"]["tactical_cards"] = await _verify_tactical_cards(resolution)
	_reports.append(resolution_report)


func _click_physical_control(control: Control) -> void:
	await _click_control(control)


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


func _verify_staff_plans(game: GameRoot, resolution: Vector2i) -> void:
	var host := game.simulation_host
	var desk := game.command_desk
	var panel := desk.staff_plan_panel
	var was_paused := host.is_tactical_paused()
	host.set_tactical_paused(true)
	await _wait_frames(3)
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		game._on_language_changed(locale)
		await _wait_frames(4)
		for label in [desk.commander_label, desk.objective_label, desk.axis_label, desk.risk_label, desk.reserve_label]:
			if label.visible == desk._compact:
				_fail("localized intent field labels must preserve the compact layout")
		await _click_control(desk.staff_plan_button)
		await _wait_frames(8)
		if not panel.visible or not host.is_tactical_paused() or panel.current_plans == null:
			_fail("staff comparison must open from the normal decision button with alternatives")
			return
		if panel.title_label.text == "STAFF_TITLE":
			_fail("staff title is not localized")
		_expect_no_horizontal_scroll(panel.scroll, "staff plan comparison")
		for button in panel._approve_buttons:
			panel.scroll.ensure_control_visible(button)
			await _wait_frames(4)
			if button.get_global_rect().intersection(panel.scroll.get_global_rect()).size.y < 30:
				_fail("each staff approval button must be reachable")
			button.grab_focus()
			if panel.gui_get_focus_owner() != button:
				_fail("staff approval must accept keyboard focus")
		panel.scroll.scroll_vertical = 0
		await _wait_frames(4)
		await _save_screenshot(resolution, "staff_plans_" + locale)
		var old_tick := host.current_snapshot.tick
		panel.budget.value = 1
		if panel.current_plans != null:
			_fail("editing staff conditions must invalidate old alternatives")
		await _click_popup_control(panel, panel.generate_button)
		if panel.current_plans == null or panel.current_plans.request.max_supply_cost != 1:
			_fail("staff request edits must regenerate plans")
		await _click_popup_control(panel, panel.reject_button)
		if panel.visible or host.current_snapshot.tick != old_tick or not host.is_tactical_paused():
			_fail("rejecting staff suggestions must preserve paused battle: visible=%s tick=%d/%d pause=%s reject=%s popup=%s" % [panel.visible,host.current_snapshot.tick,old_tick,host.is_tactical_paused(),panel.reject_button.get_global_rect(),panel.size])
	# Approve while paused: queue and published authority must remain distinct.
	await _click_control(desk.staff_plan_button)
	await _wait_frames(8)
	if panel.current_plans == null:
		_fail("staff approval requires alternatives")
		return
	await _click_popup_control(panel, panel._approve_buttons[0])
	if panel.visible or panel.pending_command_id == 0:
		_fail("staff approval must close with a pending command")
	if not host.current_snapshot.staff_plan_decisions.is_empty():
		_fail("paused approval cannot publish an applied decision")
	host.set_tactical_paused(false)
	host.advance_tick()
	host.set_tactical_paused(true)
	await _wait_frames(5)
	if panel.pending_command_id != 0 or host.current_snapshot.staff_plan_decisions.is_empty() or not host.current_snapshot.staff_plan_decisions[0].accepted:
		_fail("staff approval must receive its authority snapshot after resuming")
	await _save_screenshot(resolution, "staff_plan_approved")
	if host.current_snapshot.commander_task_graphs.is_empty() or not desk.staff_retreat_button.visible:
		_fail("approved plans must expose a real execution graph and retreat entry")
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		game._on_language_changed(locale)
		await _wait_frames(4)
		await _click_control(desk.staff_plan_button)
		await _wait_frames(5)
		if not panel.execution_label.visible or not panel.execution_label.text.contains(GameText.t(&"COMMANDER_GRAPH_CURRENT")):
			_fail("normal plan panel must expose localized per-card execution stages")
		_expect_no_horizontal_scroll(panel.scroll, "staff execution")
		await _save_screenshot(resolution, "staff_plan_execution_" + locale)
		await _click_popup_control(panel, panel.reject_button)
	await _click_control(desk.staff_retreat_button)
	var queued_retreat := false
	for command in host.world.command_queue.snapshot():
		if command is CommanderCardTaskCommand and command.action == CommanderCardTaskCommand.Action.RETREAT:
			queued_retreat = true
	if not queued_retreat:
		_fail("real retreat mouse click must enqueue the operation command")
	if host.current_snapshot.commander_task_graphs[0].retreat_requested:
		_fail("paused retreat must remain queued until the simulation advances")
	host.set_tactical_paused(false)
	host.advance_tick()
	host.set_tactical_paused(true)
	await _wait_frames(5)
	if not host.current_snapshot.commander_task_graphs[0].retreat_requested:
		_fail("real retreat button must request the graph retreat through authority")
	desk.staff_plan_status.visible = false
	host.set_tactical_paused(was_paused)


func _verify_headquarters_decision(game: GameRoot, resolution: Vector2i) -> void:
	var host := game.simulation_host
	host.set_tactical_paused(true)
	var scout: UnitState
	for id in (host.world.unit_cards[&"falcon_recon_group"] as UnitCardState).member_entity_ids:
		if (host.world.units[id] as UnitState).enabled:
			scout = host.world.units[id] as UnitState
			break
	if scout == null:
		_fail("headquarters visibility fixture requires a living observer")
		return
	var old_sight := scout.sight_range
	var old_base_sight := scout.base_sight_range
	scout.sight_range = 10000
	scout.base_sight_range = 10000
	host.world._update_faction_knowledge()
	host.set_tactical_paused(false)
	host.advance_tick()
	host.set_tactical_paused(true)
	game.command_desk.show_card_actions(CardActionSnapshot.ATTACK_HEADQUARTERS)
	await _wait_frames(5)
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		game._on_language_changed(locale)
		await _wait_frames(5)
		await _save_screenshot(resolution, "headquarters_decision_" + locale)
	var button: Button
	for row in game.command_desk.exception_rows.get_children():
		if row.has_node("Action") and (row.get_node("Action") as Button).text == GameText.t(&"CARD_ATTACK_HEADQUARTERS"):
			button = row.get_node("Action") as Button
			break
	if button == null:
		_fail("discovered enemy headquarters must offer a normal decision action")
	else:
		(game.command_desk.get_node("Exceptions/Scroll") as ScrollContainer).ensure_control_visible(button)
		await _wait_frames(5)
		await _click_control(button)
		var queued := false
		for command in host.world.command_queue.snapshot():
			if command is CommanderOrderCommand and command.hand_back_control:
				queued = true
		if not queued:
			_fail("headquarters decision mouse click must enqueue a commander attack")
		host.set_tactical_paused(false)
		host.advance_tick()
		host.set_tactical_paused(true)
		await _wait_frames(5)
		if not game.command_desk._pending_responses.is_empty():
			_fail("headquarters attack must confirm via applied snapshot")
	scout.sight_range = old_sight
	scout.base_sight_range = old_base_sight
	host.world._update_faction_knowledge()
	game.command_desk.show_card_actions(-2)
	host.set_tactical_paused(false)


func _click_popup_control(panel: StaffPlanPanel, button: Button) -> void:
	if not panel.is_ancestor_of(button):
		_fail("invalid staff popup control")
		return
	if panel.scroll.is_ancestor_of(button):
		panel.scroll.ensure_control_visible(button)
	await _wait_frames(5)
	var point := button.get_global_rect().get_center() + Vector2(panel.position)
	var presses: Array[int] = []
	var observe_press := func() -> void: presses.append(1)
	button.pressed.connect(observe_press)
	# Route through root input so Godot targets the embedded popup itself.
	# Button rectangles are popup-local; the input router needs root coordinates.
	await _click_position(point)
	if presses.size() != 1:
		_fail("staff popup mouse click must activate exactly once: %s (%d)" % [button.text, presses.size()])
	if is_instance_valid(button):
		button.pressed.disconnect(observe_press)


func _verify_control_handoff(game: GameRoot, resolution: Vector2i) -> void:
	var host := game.simulation_host
	var original_window_position := DisplayServer.window_get_position()
	host.set_process(false)
	for _tick in range(3):
		host.advance_tick()
	var card_id: StringName = &"ironwall_assault_group"
	game.input_controller.select_unit_card(card_id)
	host.submit_command(host.create_unit_card_control_command(card_id, UnitCardControlCommand.Action.STAY_MANUAL))
	host.advance_tick()
	await _wait_frames(6)
	var card_button := game.army_board._unit_card_buttons[card_id] as Button
	await _click_physical_control(card_button)
	await _press_key(KEY_SPACE)
	var frozen_tick := host.current_snapshot.tick
	var text_input := LineEdit.new()
	game.get_node("HUDLayer").add_child(text_input)
	text_input.grab_focus()
	var queue_before_text := host.get_queue_size()
	await _press_key(KEY_R)
	if host.get_queue_size() != queue_before_text:
		_fail("R in a text input must not submit a control handoff")
	text_input.queue_free()
	await _wait_frames(2)
	var popup := (game.army_board._posture_menus[&"di_tian"] as OptionButton).get_popup()
	popup.popup()
	await _wait_frames(3)
	await _press_key(KEY_R)
	if not popup.visible or host.get_queue_size() != queue_before_text:
		_fail("R in an open posture menu must not reach the battlefield")
	popup.hide()
	card_button.grab_focus()
	if not game.control_handoff_button.visible or not game.control_handoff_button.text.contains(GameText.t(&"CONTROL_AI_HINT") % 1):
		_fail("manual control must expose the top-left R handoff reminder")
	await _press_key(KEY_R)
	var queued := host.get_queue_size()
	var echo_key := InputEventKey.new()
	echo_key.keycode = KEY_R
	echo_key.pressed = true
	echo_key.echo = true
	Input.parse_input_event(echo_key)
	await _wait_frames(3)
	if queued != queue_before_text + 1 or host.get_queue_size() != queued or host.current_snapshot.tick != frozen_tick or host.current_snapshot.get_unit_card(card_id).control_state != UnitCardState.ControlState.PLAYER_CONTROLLED:
		_fail("focused R must queue exactly one handoff while tactical pause preserves authoritative state")
	await _save_screenshot(resolution, "manual_control_handoff_queued")
	await _press_key(KEY_SPACE)
	host.advance_tick()
	await _wait_frames(6)
	if host.current_snapshot.get_unit_card(card_id).control_state != UnitCardState.ControlState.AGENT_ASSIGNED:
		_fail("R must restore AI control even without an old return task")
	host.submit_command(host.create_unit_card_control_command(card_id, UnitCardControlCommand.Action.STAY_MANUAL))
	host.advance_tick()
	await _wait_frames(6)
	var queue_before_button := host.get_queue_size()
	await _click_physical_control(game.army_board._handoff_button)
	if host.get_queue_size() != queue_before_button + 1:
		_fail("visible army handoff button must submit one return command")
	host.advance_tick()
	await _wait_frames(6)
	if host.current_snapshot.get_unit_card(card_id).control_state != UnitCardState.ControlState.AGENT_ASSIGNED:
		_fail("visible handoff button must restore AI control")
	host.submit_command(host.create_unit_card_control_command(card_id, UnitCardControlCommand.Action.TAKEOVER))
	host.advance_tick()
	await _wait_frames(6)
	game.command_desk._select_metadata(game.command_desk.commander_selector, &"di_tian")
	await _click_physical_control(game.command_desk.apply_button)
	host.advance_tick()
	await _wait_frames(6)
	if host.current_snapshot.get_unit_card(card_id).control_state != UnitCardState.ControlState.AGENT_ASSIGNED:
		_fail("real decision approval must restore its commander's AI control")
	await _save_screenshot(resolution, "decision_handoff_confirmed")
	DisplayServer.window_set_position(original_window_position)
	host.set_process(true)


func _verify_twelve_card_overview(resolution: Vector2i) -> Dictionary:
	var game := (load("res://scenes/game/black_well.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	current_scene = game
	await _wait_frames(12)
	await _click_physical_control(game.prebattle_planner.start_button)
	await _wait_frames(12)
	var board := game.army_board
	var board_rect := board.get_global_rect()
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(resolution))
	_expect_control_in_viewport(board, viewport_rect, "twelve-card army overview")
	if board.get_commander_card_count() != 5 or board.get_unit_card_button_count() != 12:
		_fail("Black Well must show five commanders and twelve cards")
	var scroll := board.get_node("Margin/Layout/Scroll") as ScrollContainer
	if scroll.get_v_scroll_bar().visible or scroll.get_h_scroll_bar().visible:
		_fail("the complete army overview must not require a scrollbar")
	for button in board._unit_card_buttons.values():
		if not board_rect.encloses(button.get_global_rect()) or not viewport_rect.encloses(button.get_global_rect()):
			_fail("all twelve card rectangles must fit inside the visible army overview")
		_expect_minimum_target(button, "whole-card selection")
		if not button.disabled:
			await _click_physical_control(button)
			if not button.button_pressed:
				_fail("every displayed troop card must accept a real selection click")
	for button in board._commander_buttons.values():
		if not board_rect.encloses(button.get_global_rect()):
			_fail("every commander summary must fit inside the army overview")
	await _save_screenshot(resolution, "twelve_card_overview")
	var report := {"commanders": board.get_commander_card_count(), "cards": board.get_unit_card_button_count(), "board": _rect_array(board_rect), "map": _rect_array(game.get_grey_ridge_map_rect()), "scroll_required": false}
	game.queue_free()
	await _wait_frames(5)
	current_scene = null
	return report


func _verify_composition_persistence(resolution: Vector2i) -> Dictionary:
	var game := (load("res://scenes/game/black_well.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	current_scene = game
	await _wait_frames(12)
	var host := game.simulation_host
	host.set_process(false)
	host.world = TestCompositionPersistence.mixed_world()
	host._grey_ridge_army_plan = host.world.grey_ridge_army_plan.duplicate_plan()
	host.current_snapshot = host.world.create_snapshot()
	host.previous_snapshot = host.current_snapshot
	game._on_scenario_restarted(host.current_snapshot)
	game.prebattle_planner.configure(host)
	await _wait_frames(8)
	var planner := game.prebattle_planner
	var readiness := planner._readiness_labels[TestCompositionPersistence.MIXED_ID] as Label
	var stats := readiness.get_parent().get_node("Stats") as Label
	var scroll := planner.get_node("Backdrop/Margin/Layout/Scroll") as ScrollContainer
	scroll.ensure_control_visible(stats)
	await _wait_frames(6)
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(resolution))
	_expect_control_in_viewport(stats, viewport_rect, "mixed prebattle composition")
	if not stats.text.contains("8/8") or not stats.text.contains("4/4"):
		_fail("mixed prebattle must disclose each unit type and strength")
	await _save_screenshot(resolution, "mixed_prebattle")
	host._campaign_load_failed = true
	host._set_campaign_error(&"ROSTER_LOAD_FAILED", "SIMULATED: invalid roster field")
	scroll.ensure_control_visible(planner.roster_status.message)
	await _wait_frames(6)
	_expect_control_in_viewport(planner.roster_status.message, viewport_rect, "roster load failure")
	if not planner.start_button.disabled or planner.roster_status.retry_button.visible:
		_fail("invalid roster must visibly prevent starting without offering save retry")
	await _save_screenshot(resolution, "roster_load_failure")
	host._campaign_load_failed = false
	host._set_campaign_error(&"", "")
	planner.visible = false
	host._grey_ridge_battle_started = true
	game._on_scenario_restarted(host.current_snapshot)
	await _wait_frames(10)
	var button := game.army_board._unit_card_buttons[TestCompositionPersistence.MIXED_ID] as Button
	await _position_physical_pointer(button.get_global_rect().get_center())
	_send_motion(button.get_global_rect().get_center(), 0)
	await create_timer(1.25).timeout
	var tooltip := game.hover_tooltip
	if not tooltip.panel.visible or not tooltip.label.text.contains("8/8") or not tooltip.label.text.contains("4/4"):
		_fail("mixed battlefield delayed help must show both composition entries")
	_expect_control_in_viewport(tooltip.panel, viewport_rect, "mixed composition tooltip")
	await _save_screenshot(resolution, "mixed_composition_help")
	host._campaign_record = ArmyRosterStore.build_battle_record(host.current_snapshot)
	host._campaign_save_pending = true
	host._set_campaign_error(&"ROSTER_SAVE_FAILED", "SIMULATED: atomic replacement failed")
	game.battle_debrief.show_debrief(host.get_campaign_record())
	await _wait_frames(10)
	var status := game.battle_debrief.roster_status
	_expect_control_in_viewport(status.message, viewport_rect, "roster save failure")
	_expect_control_in_viewport(status.retry_button, viewport_rect, "roster save retry")
	if not game.battle_debrief.fight_again_button.disabled or not game.battle_debrief.return_to_operations_button.disabled:
		_fail("unsaved battle must prevent leaving the retained result")
	await _save_screenshot(resolution, "roster_save_failure")
	var original := host.get_campaign_record()
	await _click_control(status.retry_button)
	await _wait_frames(6)
	if host.has_campaign_error() or host._campaign_save_pending or host.get_campaign_record() != original or game.battle_debrief.return_to_operations_button.disabled:
		_fail("save retry must clear the error without duplicating the battle reward")
	game.queue_free()
	await _wait_frames(5)
	current_scene = null
	return {"entries": 2, "prebattle_details": true, "delayed_help": true, "load_blocked": true, "save_retry": true}


func _verify_tactical_cards(resolution: Vector2i) -> Dictionary:
	var game := (load("res://scenes/game/black_well.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	current_scene = game
	await _wait_frames(12)
	var host := game.simulation_host
	host.set_process(false)
	host.world = TestTacticalCards.sample_world()
	TestTacticalCards._quiet(host.world)
	host._grey_ridge_army_plan = host.world.grey_ridge_army_plan.duplicate_plan()
	host._grey_ridge_battle_started = true
	host.current_snapshot = host.world.create_snapshot()
	host.previous_snapshot = host.current_snapshot
	game.prebattle_planner.visible = false
	game._on_scenario_restarted(host.current_snapshot)
	await _wait_frames(12)
	var viewport := Rect2(Vector2.ZERO, Vector2(resolution))
	var board := game.army_board
	if board.get_unit_card_button_count() != 5:
		_fail("five tactical sample cards must be simultaneously selectable")
	for button in board._unit_card_buttons.values():
		_expect_control_in_viewport(button, board.get_global_rect(), "tactical overview card")
	var observer := board._unit_card_buttons[&"forward_observers"] as Button
	await _position_physical_pointer(observer.get_global_rect().get_center())
	_send_motion(observer.get_global_rect().get_center(), 0)
	await create_timer(1.25).timeout
	if not game.hover_tooltip.panel.visible or not game.hover_tooltip.label.text.contains(GameText.t(&"TACTICAL_OBSERVERS_HELP")):
		_fail("tactical card delayed help must explain cost and counterplay")
	_expect_control_in_viewport(game.hover_tooltip.panel, viewport, "tactical card tooltip")
	await _save_screenshot(resolution, "tactical_card_help")
	var desk := game.command_desk
	desk.show_card_actions(CardActionSnapshot.TACTICAL + TacticalAbilityDefinition.Kind.OBSERVE)
	await _wait_frames(6)
	var action := _first_card_decision_button(desk, CardActionSnapshot.TACTICAL + TacticalAbilityDefinition.Kind.OBSERVE)
	if action == null:
		_fail("observation action must be reachable in the normal decision panel")
	else:
		var scroll := desk.get_node("Exceptions/Scroll") as ScrollContainer
		scroll.ensure_control_visible(action)
		await _wait_frames(5)
		await _click_control(action)
		host.current_snapshot = host.world.advance_tick()
		await _wait_frames(5)
		if host.current_snapshot.get_unit_card(&"forward_observers").tactical_status_key != &"TACTICAL_PREPARING":
			_fail("real tactical action click must enter authoritative preparation")
		if board._tactical_activity(host.current_snapshot.get_commander(&"bai_jiuyang")) != 1:
			_fail("preparing a tactical action must mark its commander as working")
		await _save_screenshot(resolution, "tactical_card_preparing")
		for tick in range(22):
			host.current_snapshot = host.world.advance_tick()
		await _wait_frames(5)
		if host.current_snapshot.get_unit_card(&"forward_observers").tactical_status_key != &"TACTICAL_ACTIVE":
			_fail("tactical action must complete preparation through simulation ticks")
	TranslationServer.set_locale("en")
	game._on_language_changed("en")
	await _wait_frames(6)
	var english := CompositionText.from_snapshot(host.current_snapshot.get_unit_card(&"suppression_battery"))
	if not english.contains("Specialist ammunition") or english.contains("TACTICAL_BATTERY_HELP"):
		_fail("English tactical ammunition and counterplay help must resolve")
	TranslationServer.set_locale("zh_CN")
	game._on_language_changed("zh_CN")
	game.queue_free()
	await _wait_frames(5)
	current_scene = null
	return {"cards": 5, "real_action_click": true, "preparation": true, "delayed_help": true, "bilingual": true}


func _validate_selector(selector: BattleSelector, viewport_rect: Rect2) -> void:
	if selector == null or selector.get_selectable_battle_count() != 4:
		_fail("operation selector did not expose four battles")
		return
	for control in [
		selector.title_label, selector.battle_list,
		selector.get_node("SafeArea/Layout/Body/Dossier"), selector.training_status_label,
		selector.replay_tutorial_button, selector.deploy_button,
		selector.language_button, selector.exit_button,
	]:
		_expect_control_in_viewport(control as Control, viewport_rect, "selector")
	_expect_minimum_target(selector.deploy_button, "selector Deploy")
	_expect_minimum_target(selector.replay_tutorial_button, "selector Replay")


func _validate_prebattle(planner: PrebattlePlanner, viewport_rect: Rect2) -> void:
	if planner == null or not planner.visible or not planner.is_plan_valid():
		_fail("prebattle planner is unavailable or invalid")
		return
	for control in [
		planner.get_node("Backdrop/Margin/Layout/Header"),
		planner.get_node("Backdrop/Margin/Layout/Scroll"),
		planner.roster_bar, planner.tutorial_toggle,
		planner.get_node("Backdrop/Margin/Layout/Footer"), planner.start_button,
	]:
		_expect_control_in_viewport(control as Control, viewport_rect, "prebattle")
	var scroll := planner.get_node("Backdrop/Margin/Layout/Scroll") as ScrollContainer
	_expect_no_horizontal_scroll(scroll, "prebattle content")
	_expect_minimum_target(planner.tutorial_toggle, "prebattle tutorial toggle")
	_expect_minimum_target(planner.start_button, "prebattle Start")
	var doctrine := planner._doctrine_menus.get(&"bai_jiuyang") as OptionButton
	var posture := planner._posture_menus.get(&"bai_jiuyang") as OptionButton
	var detail := planner._tactical_detail_labels.get(&"bai_jiuyang") as Label
	if doctrine == null or posture == null or detail == null:
		_fail("prebattle tactical selectors or disclosure label are missing")
		return
	for field in [
		doctrine.get_parent().get_node("DoctrineLabel") as Label,
		posture.get_parent().get_node("PostureLabel") as Label,
		detail,
	]:
		_expect_control_in_viewport(field, viewport_rect, "prebattle tactical disclosure")
	posture.mouse_entered.emit()
	await _wait_frames(4)
	if not detail.text.contains(GameText.t(&"COMMANDER_POSTURE_CAUTIOUS_TOOLTIP")):
		_fail("hovering the posture selector did not disclose its selected battlefield effect")


func _validate_battlefield(game: GameRoot, viewport_rect: Rect2) -> void:
	var map_rect := game.get_grey_ridge_map_rect()
	if not viewport_rect.encloses(map_rect) or map_rect.size.x < (700.0 if viewport_rect.size.x >= 900.0 else 200.0) or map_rect.size.y < 240.0:
		_fail("battlefield map is too small or outside viewport: %s" % map_rect)
	var minimum_decision_height := 220.0 if viewport_rect.size.x >= 900.0 else 250.0
	if game.task_panel.size.y + 1.0 < minimum_decision_height:
		_fail("decision area is shorter than the contracted %.0f pixels: %s" % [minimum_decision_height, game.task_panel.size])
	for panel in [game.resource_bar, game.scenario_status, game.army_board, game.task_panel, game.support_panel, game.minimap]:
		if panel == null or not panel.visible:
			continue
		_expect_control_in_viewport(panel, viewport_rect, "battlefield panel")
		if panel.get_global_rect().intersection(map_rect).get_area() > 4.0:
			_fail("%s overlaps the dedicated map at %s" % [panel.name, map_rect])
	var visible_friendly_entities := 0
	for unit in game.simulation_host.current_snapshot.units:
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			visible_friendly_entities += 1
			if not game.world_presentation._proxies.has(unit.entity_id):
				_fail("friendly entity E%d has no battlefield proxy" % unit.entity_id)
	if visible_friendly_entities <= 0:
		_fail("battlefield exposes no friendly entities")
	if game.battlefield_overlay == null or game.battlefield_overlay.situation == null:
		_fail("battlefield situation overlay did not receive the player faction DTO")
		return
	if game.resource_bar.visible or game.scenario_status.visible or game.workflow_panel.visible or game.overlay_controls.visible:
		_fail("simplified card-battle HUD still exposes a legacy resource, status, workflow, or overlay-control panel")
	if not game.pause_button.visible or not map_rect.grow(1.0).encloses(game.pause_button.get_global_rect()):
		_fail("visible pause button is missing or outside the battlefield")
	_expect_minimum_target(game.pause_button, "battlefield pause")
	if not game.pause_button.pressed.is_connected(game._open_pause_menu):
		_fail("visible pause button is not connected to the shared PauseMenu")
	if not game.army_board.is_tactical_cards() or game.army_board.get_commander_card_count() != 4 or game.army_board.get_unit_card_button_count() != 6:
		_fail("bottom board must expose all four Grey Ridge commanders and six unit cards")
	if game.task_panel.position.x <= map_rect.end.x or game.army_board.position.y < map_rect.end.y:
		_fail("decisions must be right of the map and cards below it")
	if game.command_desk.exception_rows.get_parent().size.y < 180.0:
		_fail("right-side decisions must retain at least 180px of visible scrolling space")
	var lower_panels: Array[Control] = [game.support_panel, game.minimap, game.army_board, game.task_panel]
	for left_index in range(lower_panels.size()):
		for right_index in range(left_index + 1, lower_panels.size()):
			if lower_panels[left_index].get_global_rect().intersection(lower_panels[right_index].get_global_rect()).get_area() > 4.0:
				_fail("%s overlaps %s in the compact three-column HUD" % [lower_panels[left_index].name, lower_panels[right_index].name])
	game.input_controller.select_unit_card(&"falcon_recon_group")
	await _wait_frames(3)
	if game.battlefield_overlay.selected_unit_card_id != &"falcon_recon_group":
		_fail("whole-card selection did not reach the battlefield highlight")
	if game.command_desk == null or not game.command_desk.visible:
		_fail("high-level intent and exception command desk is missing")
		return
	_expect_control_in_viewport(game.command_desk, viewport_rect, "command desk")
	for selector in [
		game.command_desk.commander_selector, game.command_desk.objective_selector,
		game.command_desk.axis_selector, game.command_desk.risk_selector,
		game.command_desk.reserve_selector,
	]:
		_expect_control_in_viewport(selector, viewport_rect, "intent selector")
		_expect_minimum_target(selector, "intent selector %s" % selector.name)
	for button in [game.command_desk.apply_button, game.command_desk.cancel_button]:
		_expect_control_in_viewport(button, viewport_rect, "intent command")
		_expect_minimum_target(button, "intent command %s" % button.name)
	_expect_control_in_viewport(game.command_desk.guide_button, viewport_rect, "command guide")
	_expect_minimum_target(game.command_desk.guide_button, "command guide")
	_expect_control_in_viewport(game.command_desk.history_button, viewport_rect, "decision history")
	_expect_minimum_target(game.command_desk.history_button, "decision history")
	if game.command_desk.history_popup.visible:
		_fail("decision history should remain hidden until requested")
	game.command_desk.axis_selector.mouse_entered.emit()
	await _wait_frames(4)
	if game.battlefield_overlay.decision_preview_route.size() < 2 or game.battlefield_overlay.decision_preview_target.is_zero_approx():
		_fail("hovering the main-axis decision did not highlight its route and objective")
	game.command_desk.axis_selector.mouse_exited.emit()
	await _wait_frames(2)
	if not game.battlefield_overlay.decision_preview_route.is_empty() or not game.battlefield_overlay.decision_preview_target.is_zero_approx():
		_fail("leaving the main-axis decision did not clear its map preview")
	await _click_control(game.command_desk.guide_button)
	await _wait_frames(5)
	if not game.command_desk.guide_popup.visible or game.command_desk.guide_text.text.length() < 100:
		_fail("command guide did not open with complete contextual guidance")
	else:
		_expect_control_in_viewport(game.command_desk.guide_text, viewport_rect, "command guide content")
	game.command_desk.guide_popup.hide()
	await _wait_frames(3)
	await _click_physical_control(game.command_desk.apply_button)
	await _wait_frames(12)
	var selected_commander_id := game.command_desk.commander_selector.get_item_metadata(game.command_desk.commander_selector.selected) as StringName
	var commander := game.simulation_host.current_snapshot.get_commander(selected_commander_id)
	if commander == null or commander.active_intent_id.is_empty():
		_fail("mouse intent submission did not reach the authoritative commander snapshot")
	if game.contact_alert == null or not game.contact_alert.visible:
		_fail("command submission did not produce a visible receipt")
	else:
		var receipt_rect := game.contact_alert.get_global_rect()
		_expect_control_in_viewport(game.contact_alert, viewport_rect, "command receipt")
		if not map_rect.encloses(receipt_rect):
			_fail("command receipt is outside the dedicated map: %s" % receipt_rect)
		for protected_control in [game.resource_bar, game.scenario_status, game.overlay_controls]:
			if protected_control != null and protected_control.visible and receipt_rect.intersects(protected_control.get_global_rect()):
				_fail("command receipt overlaps %s" % protected_control.name)
	if game.command_desk.exception_rows.get_child_count() <= 0:
		_fail("exception queue did not expose either current exceptions or its resolved state")
	if game.command_desk.get_decision_history_count() <= 0:
		_fail("submitted intent was not retained in decision history")


func _validate_pause(pause_menu: PauseMenu, viewport_rect: Rect2) -> void:
	if pause_menu == null or not pause_menu.backdrop.visible or not paused:
		_fail("pause menu did not open")
		return
	for control in [
		pause_menu.get_node("Backdrop/Menu"), pause_menu.continue_button,
		pause_menu.language_selector, pause_menu.difficulty_selector,
		pause_menu.industrial_ai_selector, pause_menu.battlefield_ai_selector,
		pause_menu.battle_audio_toggle,
		pause_menu.operations_button, pause_menu.exit_button,
	]:
		_expect_control_in_viewport(control as Control, viewport_rect, "pause")
	for button in [pause_menu.continue_button, pause_menu.operations_button, pause_menu.exit_button]:
		_expect_minimum_target(button, "pause %s" % button.name)


func _validate_debrief(debrief: BattleDebrief, viewport_rect: Rect2, expected_card_count: int) -> void:
	if debrief == null or not debrief.visible:
		_fail("Grey Ridge debrief is unavailable")
		return
	for control in [
		debrief.get_node("Backdrop/Panel"),
		debrief.get_node("Backdrop/Panel/Margin/Layout/Result"),
		debrief.get_node("Backdrop/Panel/Margin/Layout/Summary"),
		debrief.timeline_button, debrief.cards_button, debrief.causes_button,
		debrief.get_node("Backdrop/Panel/Margin/Layout/RowsScroll"),
		debrief.get_node("Backdrop/Panel/Margin/Layout/Footer"),
		debrief.fight_again_button, debrief.return_to_operations_button, debrief.feedback_button,
	]:
		_expect_control_in_viewport(control as Control, viewport_rect, "debrief")
	var scroll := debrief.get_node("Backdrop/Panel/Margin/Layout/RowsScroll") as ScrollContainer
	_expect_no_horizontal_scroll(scroll, "debrief rows")
	for button in [debrief.timeline_button, debrief.cards_button, debrief.causes_button]:
		_expect_minimum_target(button, "debrief %s" % button.name)
	_expect_minimum_target(debrief.fight_again_button, "debrief Fight Again")
	_expect_minimum_target(debrief.return_to_operations_button, "debrief Operations")
	_expect_minimum_target(debrief.feedback_button, "debrief Feedback")
	if root.gui_get_focus_owner() != debrief.fight_again_button:
		_fail("debrief did not focus its first recovery action")
	await _press_key(KEY_TAB)
	_validate_focus_owner(viewport_rect, "debrief Tab")
	await _activate_debrief_button(debrief.cards_button)
	if not debrief.cards_button.button_pressed or debrief.timeline_button.button_pressed or debrief.causes_button.button_pressed:
		_fail("debrief view controls did not switch exclusively to unit cards")
	if debrief.rows.get_child_count() != expected_card_count:
		_fail("Grey Ridge debrief did not expose all persistent card rows")
	await _activate_debrief_button(debrief.causes_button)
	if not debrief.causes_button.button_pressed or debrief.timeline_button.button_pressed or debrief.cards_button.button_pressed:
		_fail("debrief view controls did not switch exclusively to causes")
	await _activate_debrief_button(debrief.timeline_button)
	if not debrief.timeline_button.button_pressed or debrief.cards_button.button_pressed or debrief.causes_button.button_pressed:
		_fail("debrief view controls did not switch exclusively to turning points")


func _validate_debrief_rows(debrief: BattleDebrief, viewport_rect: Rect2, identity_key: StringName, expected_count: int, context: String) -> void:
	var scroll := debrief.get_node("Backdrop/Panel/Margin/Layout/RowsScroll") as ScrollContainer
	_expect_no_horizontal_scroll(scroll, "debrief %s" % context)
	if expected_count >= 0 and debrief.rows.get_child_count() != expected_count:
		_fail("debrief %s row count is %d, expected %d" % [context, debrief.rows.get_child_count(), expected_count])
	if debrief.rows.get_child_count() <= 0:
		_fail("debrief %s view has no visible state" % context)
		return
	for row_variant in debrief.rows.get_children():
		var row := row_variant as Control
		if row == null:
			_fail("debrief %s contains a non-control row" % context)
			continue
		if expected_count >= 0 and (not row.has_meta(identity_key) or String(row.get_meta(identity_key, "")).is_empty()):
			_fail("debrief %s row is missing stable identity %s" % [context, identity_key])
		if row.size.x > scroll.size.x + 2.0:
			_fail("debrief %s row overflows horizontally: %.1f > %.1f" % [context, row.size.x, scroll.size.x])
	var first_row := debrief.rows.get_child(0) as Control
	scroll.scroll_vertical = 0
	await _wait_frames(4)
	if first_row.get_global_rect().intersection(scroll.get_global_rect()).size.y < 24.0 or first_row.get_global_rect().intersection(viewport_rect).get_area() <= 0.0:
		_fail("first debrief %s row is not visible in the scroll viewport" % context)


func _validate_feedback(dialog: PlaytestFeedbackDialog, viewport_rect: Rect2) -> void:
	if dialog == null or not dialog.visible:
		_fail("feedback form did not open from the debrief")
		return
	for control in [
		dialog.panel, dialog.overall_rating,
		dialog.submit_button, dialog.retry_button, dialog.close_button,
	]:
		_expect_control_in_viewport(control as Control, viewport_rect, "feedback")
	for button in [dialog.submit_button, dialog.retry_button, dialog.close_button]:
		_expect_minimum_target(button, "feedback %s" % button.name)
	var scroll := dialog.panel.get_node("Margin/Layout/Scroll") as ScrollContainer
	_expect_no_horizontal_scroll(scroll, "feedback form")
	scroll.ensure_control_visible(dialog.bug_details)
	await _wait_frames(6)
	for control in [dialog.encountered_bug, dialog.bug_details]:
		var clipped := (control as Control).get_global_rect().intersection(scroll.get_global_rect())
		if clipped.size.x < minf((control as Control).size.x, scroll.size.x) - 2.0 or clipped.size.y < 24.0:
			_fail("feedback control %s cannot be brought into the visible scroll viewport" % (control as Control).name)
	scroll.scroll_vertical = 0
	await _wait_frames(4)
	if root.gui_get_focus_owner() != dialog.overall_rating:
		_fail("feedback form did not focus its first question")


func _focus_last_debrief_row(debrief: BattleDebrief, viewport_rect: Rect2) -> void:
	var scroll := debrief.get_node("Backdrop/Panel/Margin/Layout/RowsScroll") as ScrollContainer
	var last_row := debrief.rows.get_child(debrief.rows.get_child_count() - 1) as Control
	scroll.ensure_control_visible(last_row)
	await _wait_frames(6)
	var clipped := last_row.get_global_rect().intersection(scroll.get_global_rect())
	if clipped.size.x < minf(last_row.size.x, scroll.size.x) - 2.0 or clipped.size.y <= 24.0:
		_fail("last debrief row cannot be brought into the visible scroll viewport")
	for child_variant in last_row.get_children():
		var child := child_variant as Control
		if child != null and child.get_global_rect().intersection(viewport_rect).get_area() <= 0.0:
			_fail("last debrief row child %s remains outside the viewport" % child.name)


func _verify_map_wheel_scope(game: GameRoot) -> Dictionary:
	var before := game.camera_controller.zoom.x
	var proxy := game.world_presentation._proxies.values()[0] as UnitProxy
	var before_unit_world_scale := proxy.scale.x
	var panel_position := game.support_panel.get_global_rect().get_center()
	_send_wheel(panel_position, MOUSE_BUTTON_WHEEL_UP)
	await _wait_frames(4)
	var after_panel := game.camera_controller.zoom.x
	if not is_equal_approx(before, after_panel):
		_fail("wheel over support UI changed map zoom")
	var map_position := game.get_grey_ridge_map_rect().get_center()
	_send_wheel(map_position, MOUSE_BUTTON_WHEEL_UP)
	await _wait_frames(4)
	var after_map := game.camera_controller.zoom.x
	if after_map <= after_panel:
		_fail("wheel over battlefield did not increase map zoom")
	var after_unit_world_scale := proxy.scale.x
	if not is_equal_approx(before_unit_world_scale, 1.0) or not is_equal_approx(after_unit_world_scale, 1.0):
		_fail("unit world scale changed with battlefield zoom: %.3f -> %.3f" % [before_unit_world_scale, after_unit_world_scale])
	return {
		"before": before,
		"after_panel": after_panel,
		"after_map": after_map,
		"unit_world_scale_before": before_unit_world_scale,
		"unit_world_scale_after": after_unit_world_scale,
	}


func _expect_control_in_viewport(control: Control, viewport_rect: Rect2, context: String) -> void:
	if control == null or not control.is_visible_in_tree():
		_fail("%s control is missing or hidden" % context)
		return
	var rect := control.get_global_rect()
	if not viewport_rect.grow(1.0).encloses(rect):
		_fail("%s control %s lies outside viewport: %s" % [context, control.name, rect])


func _expect_minimum_target(control: Control, context: String) -> void:
	if control.size.x < 32.0 or control.size.y < 32.0:
		_fail("%s target is smaller than 32x32: %s" % [context, control.size])


func _expect_no_horizontal_scroll(scroll: ScrollContainer, context: String) -> void:
	var bar := scroll.get_h_scroll_bar()
	if bar != null and bar.max_value > bar.page + 1.0:
		_fail("%s requires horizontal scrolling: max=%.1f page=%.1f" % [context, bar.max_value, bar.page])


func _validate_focus_owner(viewport_rect: Rect2, context: String) -> void:
	var focus := root.gui_get_focus_owner()
	if focus == null or not focus.is_visible_in_tree() or not viewport_rect.grow(1.0).encloses(focus.get_global_rect()):
		_fail("%s moved focus to a missing, hidden, or offscreen control" % context)


func _screen_report(controls: Array) -> Dictionary:
	var result := {}
	for control_variant in controls:
		var control := control_variant as Control
		if control != null:
			result[String(control.name)] = _rect_array(control.get_global_rect())
	return result


func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_PATH.get_base_dir()))
	var combined_reports: Array[Dictionary] = []
	if FileAccess.file_exists(REPORT_PATH):
		var existing_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPORT_PATH))
		if existing_variant is Dictionary:
			for existing_report_variant in (existing_variant as Dictionary).get("resolutions", []):
				var existing_report := existing_report_variant as Dictionary
				if not _reports.any(func(report: Dictionary) -> bool: return report.get("resolution", "") == existing_report.get("resolution", "")):
					combined_reports.append(existing_report)
	combined_reports.append_array(_reports)
	combined_reports.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _resolution_order(String(left.get("resolution", ""))) < _resolution_order(String(right.get("resolution", "")))
	)
	var report := {
		"format_version": 1,
		"input_mode": "real_mouse_and_keyboard_events",
		"resolution_count": combined_reports.size(),
		"resolutions": combined_reports,
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("could not open accessibility report path")
		return
	file.store_string(JSON.stringify(report, "\t"))
	if file.get_error() != OK:
		_fail("could not write accessibility report")


func _requested_resolutions() -> Array[Vector2i]:
	for argument in OS.get_cmdline_user_args():
		var value := String(argument)
		if not value.begins_with(RESOLUTION_ARGUMENT):
			continue
		var dimensions := value.trim_prefix(RESOLUTION_ARGUMENT).to_lower().split("x")
		if dimensions.size() != 2 or not dimensions[0].is_valid_int() or not dimensions[1].is_valid_int():
			_fail("invalid matrix resolution argument: %s" % value)
			return []
		var resolution := Vector2i(int(dimensions[0]), int(dimensions[1]))
		if not RESOLUTIONS.has(resolution):
			_fail("unsupported matrix resolution: %s" % resolution)
			return []
		return [resolution]
	var all_resolutions: Array[Vector2i] = []
	for resolution in RESOLUTIONS:
		all_resolutions.append(resolution)
	return all_resolutions


func _resolution_order(value: String) -> int:
	for index in range(RESOLUTIONS.size()):
		var resolution: Vector2i = RESOLUTIONS[index]
		if value == "%dx%d" % [resolution.x, resolution.y]:
			return index
	return RESOLUTIONS.size()


func _save_screenshot(resolution: Vector2i, screen_name: String) -> void:
	var directory := "res://artifacts/accessibility/%dx%d" % [resolution.x, resolution.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := "%s/%s.png" % [directory, screen_name]
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_fail("could not save %s: %s" % [path, error_string(error)])


func _wait_for_game_scene(frame_limit: int) -> GameRoot:
	for _frame in range(frame_limit):
		var game := current_scene as GameRoot
		if game != null and game.is_node_ready():
			return game
		await process_frame
	return null


func _click_control(control: Control) -> void:
	if control == null or not control.is_visible_in_tree() or control.disabled:
		_fail("attempted to click a missing, hidden, or disabled control")
		return
	await _click_position(control.get_global_rect().get_center())


func _activate_debrief_button(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	await _position_physical_pointer(point)
	_send_motion(button.get_global_rect().get_center(), 0)
	await _wait_frames(2)
	if root.gui_get_hovered_control() != button:
		_fail("debrief mouse hover did not resolve to %s at %s; actual=%s" % [button.name, button.get_global_rect(), root.gui_get_hovered_control()])
	button.grab_focus()
	await process_frame
	if root.gui_get_focus_owner() != button:
		_fail("debrief keyboard focus did not reach %s" % button.name)
	await _press_key(KEY_ENTER)


func _click_position(position: Vector2) -> void:
	await _position_physical_pointer(position)
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
	event.velocity = event.relative * 60.0
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
	Input.flush_buffered_events()


func _send_wheel(position: Vector2, button_index: MouseButton) -> void:
	_send_motion(position, 0)
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button_index
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button_index
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = InputEventKey.new()
	event.keycode = keycode
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame


func _press_modified_key(keycode: Key, alt_pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.alt_pressed = alt_pressed
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	event = InputEventKey.new()
	event.keycode = keycode
	event.alt_pressed = alt_pressed
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _wait_frames(4)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failed = true
	push_error("ACCESSIBILITY RESOLUTION MATRIX: %s" % message)


func _finish(scene: Node) -> void:
	paused = false
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _verify_contextual_card_decisions(game: GameRoot, resolution: Vector2i, viewport_rect: Rect2) -> void:
	var host := game.simulation_host
	var desk := game.command_desk
	# Freeze only automatic ticking; clicks still travel through the real UI/command path.
	host.set_process(false)
	game.set_process(false)
	var faction := host.world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
	faction.supply = faction.supply_capacity
	var card := host.world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	(host.world.units[card.member_entity_ids.back()] as UnitState).enabled = false
	var other_card := host.world.unit_cards[&"falcon_recon_group"] as UnitCardState
	(host.world.units[other_card.member_entity_ids.back()] as UnitState).enabled = false
	host.current_snapshot = host.world.advance_tick()
	var situation := CommandSituationSnapshot.new(host.current_snapshot.tick, SimulationWorld.LOCAL_PLAYER_ID, [], [])
	desk.update_command_situation(host.current_snapshot, situation)
	game.support_panel.update_snapshot(host.current_snapshot)
	var support_scroll := game.support_panel.get_node("Margin/Scroll") as ScrollContainer
	support_scroll.ensure_control_visible(game.support_panel.reinforcement_button)
	await _wait_frames(5)
	var support_presses: Array[int] = []
	game.support_panel.reinforcement_button.pressed.connect(func() -> void: support_presses.append(1), CONNECT_ONE_SHOT)
	await _click_control(game.support_panel.reinforcement_button)
	print("CARD_UI support presses=%d filter=%d hover=%s" % [support_presses.size(), desk._card_action_filter, root.gui_get_hovered_control()])
	await _wait_frames(5)
	var scroll := desk.get_node("Exceptions/Scroll") as ScrollContainer
	_expect_no_horizontal_scroll(scroll, "contextual card decisions")
	var decision_id := "card:ironwall_assault_group:%d:" % SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT
	var action := desk.exception_rows.get_node_or_null(NodePath(decision_id.validate_node_name() + "/Action")) as Button
	if action == null:
		_fail("%s support click did not expose the damaged card decision" % resolution)
		return
	scroll.ensure_control_visible(action)
	await _wait_frames(5)
	_expect_control_in_viewport(action, viewport_rect, "field reinforcement action")
	var strength_before := host.current_snapshot.get_unit_card(card.definition.definition_id).current_strength
	var history_before := desk.get_decision_history_count()
	var action_presses: Array[int] = []
	action.pressed.connect(func() -> void: action_presses.append(1), CONNECT_ONE_SHOT)
	await _save_screenshot(resolution, "card_reinforcement")
	var action_point := action.get_global_rect().get_center()
	await _position_physical_pointer(action_point)
	_send_motion(action_point, 0)
	await process_frame
	_send_button(action_point, true)
	await process_frame
	# A UI snapshot arriving between mouse-down and mouse-up must not destroy the button.
	host.current_snapshot = host.world.advance_tick()
	desk.update_command_situation(host.current_snapshot, situation)
	await _wait_frames(3)
	_send_button(action_point, false)
	await _wait_frames(3)
	host.current_snapshot = host.world.advance_tick()
	desk.update_command_situation(host.current_snapshot, situation)
	await _wait_frames(4)
	print("CARD_UI reinforcement presses=%d strength=%d before=%d history=%d before=%d receipt=%s" % [action_presses.size(), host.current_snapshot.get_unit_card(card.definition.definition_id).current_strength, strength_before, desk.get_decision_history_count(), history_before, desk.intent_status.text])
	if host.current_snapshot.get_unit_card(card.definition.definition_id).current_strength != strength_before + 1 or desk.get_decision_history_count() != history_before + 1:
		_fail("%s real reinforcement button did not replenish its bound card once" % resolution)
	game.support_panel.update_snapshot(host.current_snapshot)
	var cooldown_text := game.support_panel.reinforcement_button.text
	var cooldown_faction := host.current_snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var cooldown_seconds := ceili(maxi(0, cooldown_faction.reinforcement_cooldown_until_tick - host.current_snapshot.tick) * SimulationWorld.TICK_SECONDS)
	if cooldown_seconds <= 0 or not cooldown_text.ends_with(GameText.t(&"SUPPORT_COOLDOWN_REMAINING") % cooldown_seconds):
		_fail("the left support card must expose its real post-command cooldown")
	var other_action := _first_card_decision_button(desk, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT)
	if not game.support_panel.reinforcement_button.disabled or other_action == null or not other_action.disabled:
		_fail("reinforcement must grey both the left entry and the other damaged card's decision")
	if other_action != null:
		if not other_action.text.ends_with(GameText.t(&"SUPPORT_COOLDOWN_REMAINING") % cooldown_seconds):
			_fail("reinforcement decisions must display the same countdown as the left entry")
		scroll.ensure_control_visible(other_action)
		await _wait_frames(5)
		_expect_control_in_viewport(other_action, viewport_rect, "shared reinforcement cooldown")
		var queued_before := host.get_queue_size()
		await _click_position(other_action.get_global_rect().get_center())
		if host.get_queue_size() != queued_before:
			_fail("a disabled reinforcement decision must not enqueue another command")
	support_scroll.ensure_control_visible(game.support_panel.reinforcement_button)
	await _wait_frames(5)
	_expect_control_in_viewport(game.support_panel.reinforcement_button, viewport_rect, "left support cooldown")
	await _save_screenshot(resolution, "left_support_cooldown")
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		game._on_language_changed(locale)
		game._apply_grey_ridge_hud_layout()
		await _wait_frames(5)
		other_action = _first_card_decision_button(desk, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT)
		var remaining_text := GameText.t(&"SUPPORT_COOLDOWN_REMAINING") % cooldown_seconds
		if not game.support_panel.reinforcement_button.disabled or not game.support_panel.reinforcement_button.text.ends_with(remaining_text):
			_fail("localized left reinforcement must remain disabled with its countdown")
		if other_action == null or not other_action.disabled or not other_action.text.ends_with(remaining_text):
			_fail("localized reinforcement decision must remain disabled with the same countdown")
		if other_action != null:
			scroll.ensure_control_visible(other_action)
		support_scroll.ensure_control_visible(game.support_panel.reinforcement_button)
		await _wait_frames(5)
		_expect_no_horizontal_scroll(scroll, "localized reinforcement cooldown")
		var supply_label := game.support_panel.supply_label
		if supply_label.text != GameText.t(&"SUPPORT_SUPPLY_BALANCE") % [cooldown_faction.supply, cooldown_faction.supply_capacity]:
			_fail("supply counter must show the authoritative balance after reinforcement in both languages")
		_expect_control_in_viewport(supply_label, viewport_rect, "persistent supply balance")
		if not game.support_panel.get_global_rect().encloses(supply_label.get_global_rect()) or supply_label.get_global_rect().intersects(support_scroll.get_global_rect()):
			_fail("supply counter must remain above the scrolling support actions")
		if game.support_panel.get_global_rect().intersects(game.get_grey_ridge_map_rect()):
			_fail("localized support panel must not expand across the map")
		await _save_screenshot(resolution, "left_support_cooldown_" + locale)
	host.set_tactical_paused(true)
	await create_timer(0.25).timeout
	game.support_panel.update_snapshot(host.current_snapshot)
	if game.support_panel.reinforcement_button.text != cooldown_text:
		_fail("tactical pause must freeze the visible support countdown")
	host.set_tactical_paused(false)
	desk.show_card_actions(CardActionSnapshot.DEPLOY)
	await _wait_frames(5)
	action = _first_card_decision_button(desk, CardActionSnapshot.DEPLOY)
	if action == null:
		_fail("%s reserve decision was not reachable" % resolution)
		return
	scroll.ensure_control_visible(action)
	await _wait_frames(4)
	await _click_control(action)
	await _wait_frames(4)
	if desk._targeting_decision == null or game.battlefield_overlay.decision_preview_radius != host.world.battle_definition.deployment_radius:
		print("RESERVE_CLICK rect=%s scroll=%s hover=%s filter=%d targeting=%s radius=%f" % [action.get_global_rect(), scroll.get_global_rect(), root.gui_get_hovered_control(), desk._card_action_filter, desk._targeting_decision, game.battlefield_overlay.decision_preview_radius])
		_fail("%s reserve click did not enter targeting with a persistent HQ area preview" % resolution)
		return
	var reserve_id := desk._targeting_decision.unit_card_id
	await _save_screenshot(resolution, "reserve_targeting")
	var position := desk._targeting_decision.position + Vector2(0, -192)
	var screen := game.world_presentation.get_global_transform_with_canvas() * position
	if not game.get_grey_ridge_map_rect().has_point(screen):
		_fail("%s HQ reserve point is outside the usable map" % resolution)
		return
	_send_motion(screen, 0)
	_send_button(screen, true)
	await process_frame
	_send_button(screen, false)
	await _wait_frames(3)
	if desk._pending_responses.is_empty():
		_fail("%s real map click did not submit the reserve command" % resolution)
	for tick in range(host.current_snapshot.get_unit_card(reserve_id).deployment_ticks + 5):
		host.current_snapshot = host.world.advance_tick()
		desk.update_command_situation(host.current_snapshot, situation)
		if tick % 10 == 0:
			await process_frame
	if host.current_snapshot.get_unit_card(reserve_id).deployment_state != UnitCardState.DeploymentState.DEPLOYED or not desk._pending_responses.is_empty():
		_fail("%s reserve command did not confirm real members" % resolution)
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		desk.refresh_locale()
		desk.show_card_actions(-2)
		await _wait_frames(4)
		_expect_no_horizontal_scroll(scroll, "localized card decisions")
	await _save_screenshot(resolution, "card_decisions_confirmed")
	host.set_process(true)
	game.set_process(true)


func _first_card_decision_button(desk: CommandDesk, kind: int) -> Button:
	for row in desk.exception_rows.get_children():
		if row.is_queued_for_deletion() or not row.has_meta(&"card_decision_id"):
			continue
		for decision in desk.card_actions:
			if decision.decision_id == row.get_meta(&"card_decision_id") and decision.action_kind == kind:
				return row.get_node("Action") as Button
	return null


func _verify_tactical_planning(game: GameRoot, resolution: Vector2i) -> void:
	var host := game.simulation_host
	game.command_desk.apply_button.grab_focus()
	var history_count := game.command_desk.get_decision_history_count()
	await _press_key(KEY_SPACE)
	var frozen_tick := host.current_snapshot.tick
	if game.command_desk.apply_button.text != GameText.t(&"TACTICAL_APPROVE_QUEUE"):
		_fail("paused approval must say it queues the order")
	await create_timer(0.25).timeout
	if not host.is_tactical_paused() or paused or host.current_snapshot.tick != frozen_tick:
		_fail("Space must freeze only simulation time")
	if game.command_desk.get_decision_history_count() != history_count:
		_fail("Space activated the focused approval button")
	await _position_physical_pointer(game.get_grey_ridge_map_rect().get_center())
	_send_motion(game.get_grey_ridge_map_rect().get_center(), 0)
	await _wait_frames(3)
	var selector := game.command_desk.reserve_selector
	await _position_physical_pointer(selector.get_global_rect().get_center())
	_send_motion(selector.get_global_rect().get_center(), 0)
	await create_timer(0.7).timeout
	if not game.hover_tooltip.progress.visible or game.hover_tooltip.panel.visible:
		print("HOVER_DIAGNOSTIC mouse=%s wanted=%s key=%s elapsed=%s process=%s paused=%s context=%s" % [root.get_mouse_position(), selector.get_global_rect(), game.hover_tooltip._candidate_key, game.hover_tooltip._hover_seconds, game.is_processing(), paused, game.command_desk.get_hover_context(root.get_mouse_position())])
		_fail("hover must show progress after 0.5 seconds before showing text")
	await _save_screenshot(resolution, "tactical_hover_progress")
	await create_timer(0.5).timeout
	if not game.hover_tooltip.panel.visible or game.hover_tooltip.label.text.length() < 50:
		_fail("reserve policy must explain actual behavior after progress completes")
	await _save_screenshot(resolution, "tactical_reserve_help")
	await _click_control(game.command_desk.risk_selector)
	var popup := game.command_desk.risk_selector.get_popup()
	await _wait_frames(3)
	var popup_point := Vector2(popup.position) + Vector2(popup.size.x * 0.5, 18)
	root.warp_mouse(popup_point)
	_send_motion(popup_point, 0)
	await create_timer(1.2).timeout
	if not popup.visible or not game.hover_tooltip.panel.visible or not game.hover_tooltip._candidate_key.begins_with("intent-help:Risk"):
		_fail("open posture candidates must expose their own delayed tooltip")
	await _save_screenshot(resolution, "tactical_posture_help")
	popup.hide()
	var previous_window_position := DisplayServer.window_get_position()
	var screen_rect := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(Vector2i(previous_window_position.x, mini(screen_rect.position.y, screen_rect.end.y - resolution.y)))
	var army_option := game.army_board._posture_menus[&"di_tian"] as OptionButton
	await _click_control(army_option)
	var army_popup := army_option.get_popup()
	await _wait_frames(3)
	var army_point := Vector2(army_popup.position) + Vector2(army_popup.size.x * 0.5, 18)
	root.warp_mouse(army_point)
	_send_motion(army_point, 0)
	await create_timer(1.2).timeout
	if not game.hover_tooltip.panel.visible or not game.hover_tooltip._candidate_key.begins_with("army-posture:di_tian"):
		_fail("bottom commander posture must expose a delayed explanation")
	if game.hover_tooltip.panel.get_global_rect().intersects(Rect2(army_popup.position, army_popup.size)):
		_fail("bottom posture explanation must avoid the open menu")
	_expect_control_in_viewport(game.hover_tooltip.panel, Rect2(Vector2.ZERO, root.get_visible_rect().size), "bottom posture help")
	await _save_screenshot(resolution, "tactical_bottom_posture_help")
	army_popup.hide()
	DisplayServer.window_set_position(previous_window_position)
	_send_motion(game.get_grey_ridge_map_rect().get_center(), 0)
	await _wait_frames(2)
	game.command_desk._select_metadata(game.command_desk.axis_selector, &"")
	await _click_control(game.command_desk.apply_button)
	if host.get_queue_size() <= 0 or host.current_snapshot.tick != frozen_tick:
		_fail("paused approval must queue without advancing the battlefield")
	game.input_controller.begin_commander_route(&"bai_jiuyang")
	await _wait_frames(2)
	if game.input_controller.command_mode != InputController.CommandMode.COMMANDER_ROUTE_TARGETING:
		_fail("tactical pause must allow route planning")
	for pause_control in [game.pause_button, game.tactical_pause_button]:
		if game.route_mode_hint.get_global_rect().intersects(pause_control.get_global_rect()):
			_fail("route planning guidance must not overlap pause controls")
	await _save_screenshot(resolution, "tactical_route_planning")
	await _press_key(KEY_C)
	await _press_key(KEY_ESCAPE)
	if not paused:
		_fail("Esc menu must still open during tactical pause")
	game.pause_menu.close()
	if not host.is_tactical_paused():
		_fail("closing Esc menu must retain tactical pause")
	await _press_key(KEY_SPACE)
	await _wait_frames(15)
	if host.is_tactical_paused() or host.current_snapshot.tick <= frozen_tick:
		_fail("Space must resume queued orders and simulation")
