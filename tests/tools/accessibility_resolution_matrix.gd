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
	DisplayServer.window_set_size(resolution)
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
	var zoom_report := await _verify_map_wheel_scope(game)
	await _save_screenshot(resolution, "battlefield")
	resolution_report["screens"]["battlefield"] = {
		"map_rect": _rect_array(game.get_grey_ridge_map_rect()),
		"map_wheel_scope": zoom_report,
		"pause_button": _rect_array(game.pause_button.get_global_rect()),
		"decision_desk": _rect_array(game.task_panel.get_global_rect()),
		"commander_board": _rect_array(game.army_board.get_global_rect()),
	}

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
	_reports.append(resolution_report)
	print("WARSEED_ACCESSIBILITY_STAGE resolution=%s map=%s" % [resolution, game.get_grey_ridge_map_rect()])
	game.queue_free()
	await _wait_frames(5)
	current_scene = null


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
	if not viewport_rect.encloses(map_rect) or map_rect.size.x < 440.0 or map_rect.size.y < 240.0:
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
	if not game.army_board.is_commander_only() or game.army_board.get_commander_card_count() != 3 or game.army_board.get_unit_card_button_count() != 0:
		_fail("right-hand board is not limited to the three friendly commander cards")
	var lower_panels: Array[Control] = [game.support_panel, game.minimap, game.army_board]
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
	await _click_control(game.command_desk.apply_button)
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
	_send_motion(button.get_global_rect().get_center(), 0)
	await process_frame
	if root.gui_get_hovered_control() != button:
		_fail("debrief mouse hover did not resolve to %s" % button.name)
	button.grab_focus()
	await process_frame
	if root.gui_get_focus_owner() != button:
		_fail("debrief keyboard focus did not reach %s" % button.name)
	await _press_key(KEY_ENTER)


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


func _send_wheel(position: Vector2, button_index: MouseButton) -> void:
	_send_motion(position, 0)
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button_index
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button_index
	event.pressed = false
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


func _press_modified_key(keycode: Key, alt_pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.alt_pressed = alt_pressed
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = keycode
	event.alt_pressed = alt_pressed
	event.pressed = false
	Input.parse_input_event(event)
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
