class_name GameRoot
extends Node

@onready var simulation_host: SimulationHost = $SimulationHost
@onready var world_presentation: WorldPresentation = $WorldPresentation
@onready var input_controller: InputController = $InputController
@onready var camera_controller: CameraController = $CameraController
@onready var selection_overlay: SelectionOverlay = $SelectionLayer/SelectionOverlay
@onready var minimap: MinimapControl = $HUDLayer/Minimap
@onready var task_panel: TaskPanel = $HUDLayer/TaskPanel
@onready var resource_bar = $HUDLayer/ResourceBar
@onready var workflow_panel: WorkflowPanel = $HUDLayer/WorkflowPanel
@onready var debug_layer: DebugLayer = $DebugLayer
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var hover_tooltip: HoverTooltip = $HoverTooltip
@onready var contact_alert: ContactAlert = $HUDLayer/ContactAlert
@onready var command_feedback: CommandFeedback = $CommandFeedback
@onready var battle_feedback_director: BattleFeedbackDirector = $BattleFeedbackDirector
@onready var map_frame: PanelContainer = $HUDLayer/MapFrame
@onready var map_mask_top: ColorRect = $HUDLayer/MapMaskTop
@onready var map_mask_left: ColorRect = $HUDLayer/MapMaskLeft
@onready var map_mask_right: ColorRect = $HUDLayer/MapMaskRight
@onready var map_mask_bottom: ColorRect = $HUDLayer/MapMaskBottom
@onready var route_mode_hint: PanelContainer = $HUDLayer/RouteModeHint
@onready var route_mode_hint_label: Label = $HUDLayer/RouteModeHint/Label
@onready var army_board: ArmyBoard = $HUDLayer/ArmyBoard
@onready var battlefield: Battlefield = $Battlefield
@onready var scenario_status: ScenarioStatus = $HUDLayer/ScenarioStatus
@onready var support_panel: SupportPanel = $HUDLayer/SupportPanel
@onready var tutorial_panel: TutorialPanel = $HUDLayer/TaskPanel/Margin/Layout/Tutorial
@onready var battle_debrief: BattleDebrief = $BattleDebrief
@onready var playtest_feedback_dialog: PlaytestFeedbackDialog = $PlaytestFeedbackDialog
@onready var prebattle_planner: PrebattlePlanner = $PrebattlePlanner
@onready var battlefield_overlay: BattlefieldOverlay = $BattlefieldOverlay
@onready var overlay_controls: BattlefieldOverlayControls = $HUDLayer/BattlefieldOverlayControls
@onready var command_desk: CommandDesk = $HUDLayer/TaskPanel/Margin/Layout/CommandDesk
@onready var pause_button: Button = $HUDLayer/PauseButton

var _last_ui_snapshot_tick: int = -1
var _visible_hostile_ids: Dictionary = {}
var _last_contact_alert_tick: Dictionary = {}
var _pending_ui_snapshot: WorldSnapshot
var _pending_ui_phase: int = -1
var _pending_situation: BattlefieldSituationSnapshot
var _situation_projector := BattlefieldSituationProjector.new()
var _pending_command_situation: CommandSituationSnapshot
var _command_situation_projector := CommandSituationProjector.new()

const CONTACT_ALERT_COOLDOWN_TICKS := 50
const GREY_RIDGE_OUTER_MARGIN := 10.0
const GREY_RIDGE_SIDE_WIDTH := 232.0
const GREY_RIDGE_GUTTER := 8.0
const GREY_RIDGE_TOP_BAR_HEIGHT := 54.0
const GREY_RIDGE_COMMAND_HEIGHT := 220.0
const GREY_RIDGE_NARROW_COMMAND_HEIGHT := 250.0
const GREY_RIDGE_MIN_DESKTOP_WIDTH := 900.0

var _grey_ridge_map_rect := Rect2()
var _grey_ridge_fitted_map_rect := Rect2()


func _ready() -> void:
	if command_feedback == null:
		command_feedback = get_node_or_null("CommandFeedback") as CommandFeedback
	if battle_feedback_director == null:
		battle_feedback_director = get_node_or_null("BattleFeedbackDirector") as BattleFeedbackDirector
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_grey_ridge_hud_layout):
		viewport.size_changed.connect(_apply_grey_ridge_hud_layout)
	if not prebattle_planner.visibility_changed.is_connected(_update_grey_ridge_panel_visibility):
		prebattle_planner.visibility_changed.connect(_update_grey_ridge_panel_visibility)
	if overlay_controls != null and not overlay_controls.layer_visibility_changed.is_connected(_on_overlay_visibility_changed):
		overlay_controls.layer_visibility_changed.connect(_on_overlay_visibility_changed)
	if pause_button != null and not pause_button.pressed.is_connected(_open_pause_menu):
		pause_button.pressed.connect(_open_pause_menu)
	_configure_scenario_ui()
	input_controller.simulation_host = simulation_host
	input_controller.world_presentation = world_presentation
	input_controller.camera_controller = camera_controller
	input_controller.selection_overlay = selection_overlay
	input_controller.move_intent_changed.connect(_on_move_intent_changed)
	input_controller.pending_intent_cleared.connect(world_presentation.clear_pending_move_target)
	input_controller.build_preview_changed.connect(world_presentation.set_build_preview)
	input_controller.build_preview_cleared.connect(world_presentation.clear_build_preview)
	input_controller.attack_targeting_started.connect(world_presentation.begin_attack_targeting)
	input_controller.attack_preview_changed.connect(world_presentation.set_attack_preview)
	input_controller.attack_preview_cleared.connect(world_presentation.clear_attack_preview)
	input_controller.formation_plan_preview_changed.connect(world_presentation.set_formation_plan_preview)
	input_controller.formation_plan_preview_cleared.connect(world_presentation.clear_formation_plan_preview)
	input_controller.commander_intent_preview_changed.connect(world_presentation.set_commander_intent_preview)
	input_controller.commander_intent_preview_cleared.connect(world_presentation.clear_commander_intent_preview)
	input_controller.commander_plan_preview_changed.connect(world_presentation.set_commander_plan_preview)
	input_controller.commander_plan_preview_cleared.connect(world_presentation.clear_commander_plan_preview)
	task_panel.simulation_host = simulation_host
	task_panel.input_controller = input_controller
	command_desk.configure(simulation_host, input_controller, camera_controller)
	if not command_desk.decision_preview_changed.is_connected(battlefield_overlay.set_decision_preview):
		command_desk.decision_preview_changed.connect(battlefield_overlay.set_decision_preview)
	if not command_desk.decision_preview_cleared.is_connected(battlefield_overlay.clear_decision_preview):
		command_desk.decision_preview_cleared.connect(battlefield_overlay.clear_decision_preview)
	army_board.input_controller = input_controller
	if not input_controller.command_mode_changed.is_connected(_on_command_mode_changed):
		input_controller.command_mode_changed.connect(_on_command_mode_changed)
	_on_command_mode_changed(input_controller.command_mode)
	support_panel.simulation_host = simulation_host
	support_panel.input_controller = input_controller
	tutorial_panel.configure(simulation_host)
	if not tutorial_panel.visibility_changed.is_connected(_update_tutorial_layout):
		tutorial_panel.visibility_changed.connect(_update_tutorial_layout)
	battle_debrief.configure(simulation_host)
	playtest_feedback_dialog.configure(simulation_host)
	prebattle_planner.configure(simulation_host)
	_update_grey_ridge_panel_visibility()
	_update_tutorial_layout()
	simulation_host.scenario_restarted.connect(_on_scenario_restarted)
	if command_feedback != null and not simulation_host.command_evaluated.is_connected(command_feedback.play_result):
		simulation_host.command_evaluated.connect(command_feedback.play_result)
	if contact_alert != null and not simulation_host.command_evaluated.is_connected(contact_alert.show_command_result):
		simulation_host.command_evaluated.connect(contact_alert.show_command_result)
	if battle_feedback_director != null:
		battle_feedback_director.reset(simulation_host.world.events.size())
		if not battle_feedback_director.feedback_emitted.is_connected(contact_alert.show_battle_feedback):
			battle_feedback_director.feedback_emitted.connect(contact_alert.show_battle_feedback)
		if not battle_feedback_director.effect_requested.is_connected(world_presentation.play_battle_feedback_effect):
			battle_feedback_director.effect_requested.connect(world_presentation.play_battle_feedback_effect)
	if not task_panel.headquarters_settings_changed.is_connected(_on_headquarters_settings_changed):
		task_panel.headquarters_settings_changed.connect(_on_headquarters_settings_changed)
	workflow_panel.simulation_host = simulation_host
	pause_menu.language_changed.connect(_on_language_changed)
	pause_menu.enemy_difficulty_changed.connect(simulation_host.set_enemy_difficulty)
	pause_menu.agent_authorization_changed.connect(simulation_host.set_agent_authorization)
	pause_menu.battle_audio_enabled_changed.connect(_on_battle_audio_enabled_changed)
	pause_menu.set_ai_settings(
		simulation_host.get_enemy_difficulty(),
		simulation_host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID),
		simulation_host.get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID)
	)
	_on_language_changed(TranslationServer.get_locale())


func _open_pause_menu() -> void:
	if pause_menu != null:
		pause_menu.open()


func _configure_scenario_ui() -> void:
	var is_grey_ridge := SimulationWorld.is_card_battle_kind(simulation_host.scenario_kind)
	battlefield.scenario_kind = simulation_host.scenario_kind
	battlefield.battle_definition = simulation_host.world.battle_definition
	battlefield.logic_grid = simulation_host.world.logic_grid
	minimap.logic_grid = simulation_host.world.logic_grid
	var world_rect := simulation_host.world.battle_definition.battlefield_bounds if simulation_host.world.battle_definition != null else SimulationWorld.BATTLEFIELD_BOUNDS
	camera_controller.set_world_rect(world_rect)
	minimap.set_world_rect(world_rect)
	battlefield.queue_redraw()
	map_frame.visible = is_grey_ridge
	for map_mask in _map_masks():
		map_mask.visible = is_grey_ridge
	workflow_panel.visible = not is_grey_ridge
	resource_bar.visible = not is_grey_ridge
	scenario_status.visible = false
	support_panel.visible = is_grey_ridge
	overlay_controls.visible = false
	pause_button.visible = is_grey_ridge
	army_board.set_commander_only(is_grey_ridge)
	if route_mode_hint != null:
		route_mode_hint.visible = false
	scenario_status.configure(simulation_host)
	support_panel.configure(simulation_host)
	if not is_grey_ridge:
		camera_controller.clear_active_screen_rect()
		return
	camera_controller.position = logic_grid_position(Vector2i(48, 45))
	camera_controller.zoom = Vector2.ONE * 0.75
	var layout := task_panel.get_node("Margin/Layout")
	for node_name in ["OperationsSeparator", "Operations", "ProductionSeparator", "ProductionSection"]:
		var section := layout.get_node_or_null(node_name) as CanvasItem
		if section != null:
			section.visible = false
	var develop_button := layout.get_node_or_null("Strategic/Commands/Develop") as CanvasItem
	if develop_button != null:
		develop_button.visible = false
	for node_path in ["Intel/Mission", "Intel/SelectionTitle", "Intel/TaskStatus"]:
		var compacted := layout.get_node_or_null(node_path) as CanvasItem
		if compacted != null:
			compacted.visible = false
	if command_desk != null:
		command_desk.visible = true
	_apply_grey_ridge_hud_layout()


func _update_grey_ridge_panel_visibility() -> void:
	if simulation_host == null or not SimulationWorld.is_card_battle_kind(simulation_host.scenario_kind):
		return
	var planning := prebattle_planner != null and prebattle_planner.visible
	army_board.visible = not planning
	task_panel.visible = not planning
	support_panel.visible = not planning
	minimap.visible = not planning
	overlay_controls.visible = false
	pause_button.visible = not planning
	_update_route_mode_hint(input_controller.command_mode)
	if not planning:
		_last_ui_snapshot_tick = -1
	_apply_grey_ridge_hud_layout()


func _apply_grey_ridge_hud_layout() -> void:
	if simulation_host == null or not SimulationWorld.is_card_battle_kind(simulation_host.scenario_kind):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var planning := prebattle_planner != null and prebattle_planner.visible
	if planning:
		_apply_grey_ridge_planning_layout(viewport_size)
	elif viewport_size.x >= GREY_RIDGE_MIN_DESKTOP_WIDTH:
		_apply_grey_ridge_desktop_layout(viewport_size)
	else:
		_apply_grey_ridge_narrow_layout(viewport_size)
	_layout_route_mode_hint()
	_update_map_masks(viewport_size)
	_update_tutorial_layout()
	camera_controller.set_active_screen_rect(_grey_ridge_map_rect)
	if not _grey_ridge_fitted_map_rect.is_equal_approx(_grey_ridge_map_rect):
		camera_controller.fit_world_in_screen_rect(_grey_ridge_map_rect)
		_grey_ridge_fitted_map_rect = _grey_ridge_map_rect
	else:
		camera_controller.clamp_to_bounds()


func _apply_grey_ridge_planning_layout(viewport_size: Vector2) -> void:
	_set_narrow_header_typography(viewport_size.x < GREY_RIDGE_MIN_DESKTOP_WIDTH)
	_set_grey_ridge_compact_panels(viewport_size.x < GREY_RIDGE_MIN_DESKTOP_WIDTH)
	_grey_ridge_map_rect = Rect2(Vector2.ZERO, viewport_size)
	_set_hud_rect(map_frame, _grey_ridge_map_rect)
	_layout_overlay_controls(viewport_size.x < GREY_RIDGE_MIN_DESKTOP_WIDTH)


func _apply_grey_ridge_desktop_layout(viewport_size: Vector2) -> void:
	_set_narrow_header_typography(false)
	_set_grey_ridge_compact_panels(false)
	minimap.visible = true
	var side_width := GREY_RIDGE_SIDE_WIDTH
	minimap.custom_minimum_size = Vector2(side_width, 188.0)
	var center_left := GREY_RIDGE_OUTER_MARGIN + side_width + GREY_RIDGE_GUTTER
	var center_right := viewport_size.x - center_left
	var command_top := viewport_size.y - GREY_RIDGE_OUTER_MARGIN - GREY_RIDGE_COMMAND_HEIGHT
	var map_top := GREY_RIDGE_OUTER_MARGIN
	var map_bottom := command_top - GREY_RIDGE_GUTTER
	_set_hud_rect(support_panel, Rect2(
		GREY_RIDGE_OUTER_MARGIN, GREY_RIDGE_OUTER_MARGIN,
		side_width, viewport_size.y - GREY_RIDGE_OUTER_MARGIN - 204.0
	))
	_set_hud_rect(minimap, Rect2(GREY_RIDGE_OUTER_MARGIN, viewport_size.y - 204.0, side_width, 188.0))
	_set_hud_rect(army_board, Rect2(viewport_size.x - GREY_RIDGE_OUTER_MARGIN - side_width, GREY_RIDGE_OUTER_MARGIN, side_width, viewport_size.y - GREY_RIDGE_OUTER_MARGIN * 2.0))
	_set_hud_rect(task_panel, Rect2(center_left, command_top, center_right - center_left, GREY_RIDGE_COMMAND_HEIGHT))
	_grey_ridge_map_rect = Rect2(center_left, map_top, center_right - center_left, map_bottom - map_top)
	_set_hud_rect(map_frame, _grey_ridge_map_rect)
	_layout_pause_button()


func _apply_grey_ridge_narrow_layout(viewport_size: Vector2) -> void:
	_set_narrow_header_typography(true)
	_set_grey_ridge_compact_panels(true)
	var margin := 8.0
	var gap := 8.0
	var lower_height := clampf(viewport_size.y * 0.28, 190.0, 228.0)
	var map_height := maxf(180.0, viewport_size.y - GREY_RIDGE_NARROW_COMMAND_HEIGHT - lower_height - margin * 2.0 - gap * 2.0)
	_grey_ridge_map_rect = Rect2(margin, margin, viewport_size.x - margin * 2.0, map_height)
	_set_hud_rect(map_frame, _grey_ridge_map_rect)
	_layout_pause_button()
	var task_top := _grey_ridge_map_rect.end.y + gap
	_set_hud_rect(task_panel, Rect2(margin, task_top, viewport_size.x - margin * 2.0, GREY_RIDGE_NARROW_COMMAND_HEIGHT))
	var lower_top := task_top + GREY_RIDGE_NARROW_COMMAND_HEIGHT + gap
	var column_width := (viewport_size.x - margin * 2.0 - gap * 2.0) / 3.0
	for panel in [support_panel, minimap, army_board]:
		panel.custom_minimum_size = Vector2.ZERO
		panel.clip_contents = true
	_set_hud_rect(support_panel, Rect2(margin, lower_top, column_width, lower_height))
	_set_hud_rect(minimap, Rect2(margin + column_width + gap, lower_top, column_width, lower_height))
	_set_hud_rect(army_board, Rect2(margin + (column_width + gap) * 2.0, lower_top, column_width, lower_height))
	minimap.visible = true


func _set_narrow_header_typography(narrow: bool) -> void:
	if resource_bar != null and resource_bar.label != null:
		resource_bar.label.add_theme_font_size_override("font_size", 12 if narrow else 16)
		resource_bar.label.clip_text = true
	if scenario_status != null and scenario_status.title_label != null:
		scenario_status.title_label.add_theme_font_size_override("font_size", 13 if narrow else 16)
	if overlay_controls != null:
		overlay_controls.set_compact(narrow)
	if command_desk != null:
		command_desk.set_compact(narrow)
	if support_panel != null:
		var pair_selector := support_panel.get_node_or_null("Margin/Scroll/Layout/Pair") as OptionButton
		if pair_selector != null:
			pair_selector.fit_to_longest_item = not narrow
			pair_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var support_layout := support_panel.get_node_or_null("Margin/Scroll/Layout") as Container
		if support_layout != null:
			for child in support_layout.get_children():
				var button := child as Button
				if button != null:
					button.clip_text = narrow


func _layout_overlay_controls(compact: bool) -> void:
	if overlay_controls == null or _grey_ridge_map_rect.size.x <= 0.0:
		return
	var margin := 8.0
	var width := _grey_ridge_map_rect.size.x - margin * 2.0 if compact else minf(540.0, _grey_ridge_map_rect.size.x - margin * 2.0)
	var height := 64.0 if compact else 82.0
	_set_hud_rect(overlay_controls, Rect2(_grey_ridge_map_rect.position + Vector2(margin, margin), Vector2(width, height)))


func _layout_pause_button() -> void:
	if pause_button == null or _grey_ridge_map_rect.size.x <= 0.0:
		return
	var position := Vector2(
		_grey_ridge_map_rect.end.x - 56.0,
		_grey_ridge_map_rect.position.y + 8.0
	)
	_set_hud_rect(pause_button, Rect2(position, Vector2(48.0, 40.0)))


func _set_grey_ridge_compact_panels(compact: bool) -> void:
	if scenario_status != null:
		var status_margin := scenario_status.get_node_or_null("Margin") as MarginContainer
		if status_margin != null:
			status_margin.add_theme_constant_override("margin_left", 6 if compact else 12)
			status_margin.add_theme_constant_override("margin_right", 6 if compact else 12)
			status_margin.add_theme_constant_override("margin_top", 4 if compact else 6)
			status_margin.add_theme_constant_override("margin_bottom", 4 if compact else 6)
		for label in [scenario_status.title_label, scenario_status.objective_label]:
			if label == null:
				continue
			label.custom_minimum_size = Vector2.ZERO
			label.clip_text = compact
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if task_panel == null:
		return
	var task_margin := task_panel.get_node_or_null("Margin") as MarginContainer
	if task_margin != null:
		task_margin.add_theme_constant_override("margin_top", 5 if compact else 9)
		task_margin.add_theme_constant_override("margin_bottom", 5 if compact else 9)
	var layout := task_panel.get_node_or_null("Margin/Layout") as HBoxContainer
	if layout == null:
		return
	layout.add_theme_constant_override("separation", 6 if compact else 9)
	var intel := layout.get_node_or_null("Intel") as Control
	var strategic := layout.get_node_or_null("Strategic") as Control
	var desk := layout.get_node_or_null("CommandDesk") as Control
	if intel != null:
		intel.custom_minimum_size.x = 0.0 if compact else 220.0
	if strategic != null:
		strategic.custom_minimum_size.x = 0.0 if compact else 145.0
	var strategic_title := layout.get_node_or_null("Strategic/Title") as Control
	if strategic_title != null:
		strategic_title.visible = not compact
	var strategic_guidance := layout.get_node_or_null("Strategic/DirectiveLabel") as Label
	if strategic_guidance != null:
		strategic_guidance.custom_minimum_size = Vector2.ZERO
		strategic_guidance.clip_text = compact
		strategic_guidance.max_lines_visible = 2 if compact else -1
	var directive := layout.get_node_or_null("Strategic/Directive") as Control
	if directive != null:
		directive.custom_minimum_size.y = 26.0 if compact else 30.0
	var commands := layout.get_node_or_null("Strategic/Commands") as GridContainer
	if commands != null:
		commands.add_theme_constant_override("h_separation", 3 if compact else 5)
		commands.add_theme_constant_override("v_separation", 3 if compact else 5)
		for child_variant in commands.get_children():
			var button := child_variant as Button
			if button != null:
				button.custom_minimum_size.y = 22.0 if compact else 26.0


func _update_tutorial_layout() -> void:
	if tutorial_panel == null or task_panel == null:
		return
	var layout := task_panel.get_node_or_null("Margin/Layout") as HBoxContainer
	if layout == null:
		return
	var intel := layout.get_node_or_null("Intel") as Control
	var separator := layout.get_node_or_null("IntelSeparator") as Control
	var strategic := layout.get_node_or_null("Strategic") as Control
	var desk := layout.get_node_or_null("CommandDesk") as Control
	var viewport := get_viewport()
	var narrow := viewport != null and viewport.get_visible_rect().size.x < GREY_RIDGE_MIN_DESKTOP_WIDTH
	var training := tutorial_panel.visible
	var card_battle := simulation_host != null and SimulationWorld.is_card_battle_kind(simulation_host.scenario_kind)
	if card_battle and desk != null:
		if intel != null:
			intel.visible = training and not narrow
		if separator != null:
			separator.visible = training and not narrow
		if strategic != null:
			strategic.visible = false
		if desk != null:
			desk.visible = not training
	else:
		if intel != null:
			intel.visible = not training or not narrow
		if separator != null:
			separator.visible = not training or not narrow
		if strategic != null:
			strategic.visible = not training
		if desk != null:
			desk.visible = false


func _set_hud_rect(control: Control, rect: Rect2) -> void:
	if control == null:
		return
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _layout_route_mode_hint() -> void:
	if route_mode_hint == null or _grey_ridge_map_rect.size.x <= 0.0:
		return
	var available_width := maxf(0.0, _grey_ridge_map_rect.size.x - 20.0)
	var hint_width := minf(660.0, available_width)
	var hint_height := 42.0 if hint_width >= 520.0 else 56.0
	var hint_position := Vector2(
		_grey_ridge_map_rect.get_center().x - hint_width * 0.5,
		_grey_ridge_map_rect.position.y + (84.0 if overlay_controls != null and overlay_controls.visible else 10.0)
	)
	_set_hud_rect(route_mode_hint, Rect2(hint_position, Vector2(hint_width, hint_height)))


func _on_command_mode_changed(mode: InputController.CommandMode) -> void:
	if army_board != null:
		army_board.update_command_mode(mode)
	_update_route_mode_hint(mode)


func _update_route_mode_hint(mode: InputController.CommandMode) -> void:
	if route_mode_hint == null or route_mode_hint_label == null:
		return
	var route_mode := mode in [
		InputController.CommandMode.FORMATION_ROUTE_TARGETING,
		InputController.CommandMode.COMMANDER_ROUTE_TARGETING,
	]
	var planning_screen_open := prebattle_planner != null and prebattle_planner.visible
	route_mode_hint.visible = route_mode and not planning_screen_open and simulation_host != null and SimulationWorld.is_card_battle_kind(simulation_host.scenario_kind)
	if not route_mode_hint.visible:
		return
	route_mode_hint_label.text = GameText.t(
		&"ROUTE_MODE_HINT_COMMANDER" if mode == InputController.CommandMode.COMMANDER_ROUTE_TARGETING else &"ROUTE_MODE_HINT_FORMATION"
	)
	_layout_route_mode_hint()


func _update_map_masks(viewport_size: Vector2) -> void:
	var masks := _map_masks()
	if masks.size() != 4:
		return
	_set_hud_rect(masks[0], Rect2(0.0, 0.0, viewport_size.x, _grey_ridge_map_rect.position.y))
	_set_hud_rect(masks[1], Rect2(0.0, _grey_ridge_map_rect.position.y, _grey_ridge_map_rect.position.x, _grey_ridge_map_rect.size.y))
	_set_hud_rect(masks[2], Rect2(_grey_ridge_map_rect.end.x, _grey_ridge_map_rect.position.y, viewport_size.x - _grey_ridge_map_rect.end.x, _grey_ridge_map_rect.size.y))
	_set_hud_rect(masks[3], Rect2(0.0, _grey_ridge_map_rect.end.y, viewport_size.x, viewport_size.y - _grey_ridge_map_rect.end.y))


func _map_masks() -> Array[ColorRect]:
	var masks: Array[ColorRect] = []
	for node_name in [&"MapMaskTop", &"MapMaskLeft", &"MapMaskRight", &"MapMaskBottom"]:
		var mask := get_node_or_null("HUDLayer/%s" % node_name) as ColorRect
		if mask != null:
			masks.append(mask)
	return masks


func get_grey_ridge_map_rect() -> Rect2:
	return _grey_ridge_map_rect


func logic_grid_position(cell: Vector2i) -> Vector2:
	return LogicGrid.WORLD_ORIGIN + Vector2(cell) * LogicGrid.CELL_SIZE + Vector2.ONE * LogicGrid.CELL_SIZE * 0.5


func _on_move_intent_changed(target_position: Vector2, _intent_sequence: int) -> void:
	world_presentation.set_pending_move_target(target_position)


func _on_language_changed(_locale: String) -> void:
	task_panel.refresh_locale()
	resource_bar.refresh_locale()
	workflow_panel.refresh_locale()
	contact_alert.refresh_locale()
	army_board.refresh_locale()
	scenario_status.refresh_locale()
	support_panel.refresh_locale()
	tutorial_panel.refresh_locale()
	battle_debrief.refresh_locale()
	playtest_feedback_dialog.refresh_locale()
	prebattle_planner.refresh_locale()
	overlay_controls.refresh_locale()
	command_desk.refresh_locale()
	if pause_button != null:
		pause_button.text = "||"
		pause_button.tooltip_text = GameText.t(&"PAUSE_BATTLE_TOOLTIP")
	input_controller.refresh_locale_status()
	battlefield.refresh_locale()
	world_presentation.refresh_locale()
	_update_route_mode_hint(input_controller.command_mode)


func _on_headquarters_settings_changed() -> void:
	pause_menu.set_ai_settings(
		simulation_host.get_enemy_difficulty(),
		simulation_host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID),
		simulation_host.get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID)
	)


func _on_battle_audio_enabled_changed(enabled: bool) -> void:
	if battle_feedback_director != null:
		battle_feedback_director.set_audio_enabled(enabled)
	if contact_alert != null:
		contact_alert.set_audio_enabled(enabled)
	if command_feedback != null:
		command_feedback.set_audio_enabled(enabled)


func _on_scenario_restarted(_snapshot: WorldSnapshot) -> void:
	input_controller.reset_for_new_scenario()
	command_desk.reset_decision_session()
	_on_command_mode_changed(InputController.CommandMode.NORMAL)
	_last_ui_snapshot_tick = -1
	_pending_ui_snapshot = null
	_pending_ui_phase = -1
	_pending_situation = null
	_pending_command_situation = null
	_visible_hostile_ids.clear()
	_last_contact_alert_tick.clear()
	if battle_feedback_director != null:
		battle_feedback_director.reset(simulation_host.world.events.size())
	_grey_ridge_fitted_map_rect = Rect2()
	battlefield.battle_definition = simulation_host.world.battle_definition
	battlefield.logic_grid = simulation_host.world.logic_grid
	minimap.logic_grid = simulation_host.world.logic_grid
	var world_rect := simulation_host.world.battle_definition.battlefield_bounds if simulation_host.world.battle_definition != null else SimulationWorld.BATTLEFIELD_BOUNDS
	camera_controller.set_world_rect(world_rect)
	minimap.set_world_rect(world_rect)
	battlefield.queue_redraw()
	minimap.queue_redraw()
	battlefield_overlay.set_situation(null)
	camera_controller.position = logic_grid_position(Vector2i(48, 45))
	camera_controller.zoom = Vector2.ONE * 0.75


func _process(delta: float) -> void:
	_update_unit_presentation_for_zoom()
	input_controller.prune_selection()
	world_presentation.set_snapshots(
		simulation_host.previous_snapshot,
		simulation_host.current_snapshot,
		simulation_host.get_interpolation_alpha()
	)
	battlefield_overlay.set_selected_unit_card(input_controller.selected_unit_card_id)
	if input_controller.pending_move_active and simulation_host.get_queue_size() == 0:
		world_presentation.clear_pending_move_target()
	var snapshot := simulation_host.current_snapshot
	if snapshot != null and snapshot.tick != _last_ui_snapshot_tick:
		_last_ui_snapshot_tick = snapshot.tick
		if battle_feedback_director != null:
			battle_feedback_director.process_events(simulation_host.world.events, snapshot)
		_process_new_contacts(snapshot)
		_pending_situation = _project_situation(snapshot)
		_pending_command_situation = _command_situation_projector.project(
			snapshot, _pending_situation, SimulationWorld.LOCAL_PLAYER_ID
		) if _pending_situation != null else null
		_pending_ui_snapshot = snapshot
		_pending_ui_phase = 0
	_advance_pending_ui_refresh()
	_update_hover_tooltip(delta)


func _update_unit_presentation_for_zoom() -> void:
	var is_card_battle := SimulationWorld.is_card_battle_kind(simulation_host.scenario_kind)
	world_presentation.set_unit_labels_visible(not is_card_battle or camera_controller.zoom.x >= 0.42)


func _advance_pending_ui_refresh() -> void:
	if _pending_ui_snapshot == null or _pending_ui_phase < 0:
		return
	match _pending_ui_phase:
		0:
			battlefield_overlay.set_situation(_pending_situation)
			overlay_controls.update_situation(_pending_situation)
			command_desk.update_command_situation(_pending_ui_snapshot, _pending_command_situation)
			resource_bar.update_situation(_pending_situation)
			resource_bar.update_snapshot(_pending_ui_snapshot)
			scenario_status.update_snapshot(_pending_ui_snapshot)
			tutorial_panel.observe_snapshot(_pending_ui_snapshot)
		1:
			minimap.set_situation(_pending_situation)
			minimap.set_state(_pending_ui_snapshot, camera_controller, input_controller.selected_entity_ids)
		2:
			task_panel.update_snapshot(_pending_ui_snapshot)
			workflow_panel.update_snapshot(_pending_ui_snapshot)
			support_panel.update_snapshot(_pending_ui_snapshot)
			army_board.update_snapshot(_pending_ui_snapshot)
			if debug_layer.visible:
				debug_layer.update_status(
					_pending_ui_snapshot,
					input_controller.selected_entity_id,
					simulation_host.get_queue_size(),
					input_controller.last_command_status,
					simulation_host.get_tick_timing_snapshot(),
					simulation_host.get_true_state_snapshot_for_debug(),
					simulation_host.get_enemy_phase_name(),
					simulation_host.get_enemy_difficulty_name(),
					simulation_host.get_enemy_decision_summary(),
					simulation_host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID),
					simulation_host.get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID)
				)
	_pending_ui_phase += 1
	if _pending_ui_phase > 2:
		_pending_ui_snapshot = null
		_pending_ui_phase = -1
		_pending_situation = null
		_pending_command_situation = null


func _project_situation(snapshot: WorldSnapshot) -> BattlefieldSituationSnapshot:
	if snapshot == null or simulation_host == null or not SimulationWorld.is_card_battle_kind(simulation_host.scenario_kind):
		return null
	var battle := simulation_host.world.battle_definition
	var bounds := battle.battlefield_bounds if battle != null else SimulationWorld.BATTLEFIELD_BOUNDS
	var base_interval := battle.base_supply_interval_ticks if battle != null else BattlefieldSituationProjector.DEFAULT_BASE_SUPPLY_INTERVAL_TICKS
	var region_interval := battle.region_settlement_interval_ticks if battle != null else BattlefieldSituationProjector.DEFAULT_REGION_SETTLEMENT_INTERVAL_TICKS
	var support_costs := {}
	if battle != null:
		for support in battle.support_abilities:
			support_costs[String(support.support_id)] = support.supply_cost
	return _situation_projector.project(snapshot, SimulationWorld.LOCAL_PLAYER_ID, bounds, base_interval, region_interval, support_costs)


func _on_overlay_visibility_changed(frontlines: bool, tasks: bool, threats: bool, intelligence: bool) -> void:
	if battlefield_overlay != null:
		battlefield_overlay.set_layer_visibility(frontlines, tasks, threats, intelligence)
	if minimap != null:
		minimap.set_layer_visibility(frontlines, tasks, threats, intelligence)


func _process_new_contacts(snapshot: WorldSnapshot) -> void:
	var currently_visible: Dictionary = {}
	for unit in snapshot.units:
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID or not unit.enabled or not unit.is_visible_to_local_player:
			continue
		currently_visible[unit.entity_id] = true
		if not _visible_hostile_ids.has(unit.entity_id) and snapshot.tick - int(_last_contact_alert_tick.get(unit.entity_id, -CONTACT_ALERT_COOLDOWN_TICKS)) >= CONTACT_ALERT_COOLDOWN_TICKS:
			minimap.add_contact_ping(unit.position)
			contact_alert.show_contact(unit.definition_id, false, false)
			if battle_feedback_director != null:
				battle_feedback_director.notify_contact(snapshot.tick)
			_last_contact_alert_tick[unit.entity_id] = snapshot.tick
	for building in snapshot.buildings:
		if building.faction_id == SimulationWorld.LOCAL_PLAYER_ID or not building.enabled or not building.is_visible:
			continue
		currently_visible[building.entity_id] = true
		if not _visible_hostile_ids.has(building.entity_id) and snapshot.tick - int(_last_contact_alert_tick.get(building.entity_id, -CONTACT_ALERT_COOLDOWN_TICKS)) >= CONTACT_ALERT_COOLDOWN_TICKS:
			minimap.add_contact_ping(building.position)
			contact_alert.show_contact(building.definition_id, true, false)
			if battle_feedback_director != null:
				battle_feedback_director.notify_contact(snapshot.tick)
			_last_contact_alert_tick[building.entity_id] = snapshot.tick
	_visible_hostile_ids = currently_visible


func _update_hover_tooltip(delta: float) -> void:
	if pause_menu.backdrop.visible or prebattle_planner.visible or battle_debrief.visible:
		hover_tooltip.clear()
		return
	var mouse_position := get_viewport().get_mouse_position()
	var context := task_panel.get_hover_context(mouse_position)
	if context.is_empty() and task_panel.get_global_rect().has_point(mouse_position):
		hover_tooltip.clear()
		return
	if context.is_empty():
		context = _world_hover_context(input_controller._screen_to_world(mouse_position))
	hover_tooltip.update_candidate(
		String(context.get("key", "")), String(context.get("text", "")), mouse_position, delta
	)


func _world_hover_context(world_position: Vector2) -> Dictionary:
	var snapshot := simulation_host.current_snapshot
	if snapshot == null:
		return {}
	var hit_radius := InputController.HIT_RADIUS_SCREEN / camera_controller.zoom.x
	var nearest_unit: UnitSnapshot
	var nearest_distance := INF
	for unit in snapshot.units:
		if not unit.enabled or unit.faction_id != SimulationWorld.LOCAL_PLAYER_ID and not unit.is_visible_to_local_player:
			continue
		var distance := unit.position.distance_to(world_position)
		if distance <= hit_radius and distance < nearest_distance:
			nearest_unit = unit
			nearest_distance = distance
	if nearest_unit != null:
		return {"key": "world-unit:%d" % nearest_unit.entity_id, "text": GameText.unit_tooltip(nearest_unit.definition_id)}
	var nearest_contact: UnitSnapshot
	nearest_distance = INF
	for unit in snapshot.units:
		if not unit.enabled or unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID or unit.is_visible_to_local_player:
			continue
		var distance := unit.position.distance_to(world_position)
		if distance <= hit_radius and distance < nearest_distance:
			nearest_contact = unit
			nearest_distance = distance
	if nearest_contact != null:
		return {
			"key": "world-intel-contact:%d:%d" % [nearest_contact.entity_id, nearest_contact.last_seen_tick],
			"text": GameText.intel_contact_tooltip(nearest_contact.definition_id),
		}
	for building in snapshot.buildings:
		if building.enabled and building.position.distance_to(world_position) <= 72.0:
			return {"key": "world-building:%d" % building.entity_id, "text": GameText.building_tooltip(building.definition_id)}
	for ore_field in snapshot.ore_fields:
		if ore_field.position.distance_to(world_position) <= 52.0:
			return {
				"key": "ore:%d" % ore_field.entity_id,
				"text": GameText.t(&"ORE_TOOLTIP") % ore_field.ore_remaining,
			}
	return {}
