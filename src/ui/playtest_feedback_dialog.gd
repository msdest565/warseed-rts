class_name PlaytestFeedbackDialog
extends CanvasLayer

const PRIORITY_AREAS := [
	["units", &"FEEDBACK_AREA_UNITS"],
	["maps", &"FEEDBACK_AREA_MAPS"],
	["economy", &"FEEDBACK_AREA_ECONOMY"],
	["cards", &"FEEDBACK_AREA_CARDS"],
	["objectives", &"FEEDBACK_AREA_OBJECTIVES"],
	["commander_ai", &"FEEDBACK_AREA_COMMANDER_AI"],
	["campaign_story", &"FEEDBACK_AREA_CAMPAIGN_STORY"],
	["controls_ui", &"FEEDBACK_AREA_CONTROLS_UI"],
	["pacing_balance", &"FEEDBACK_AREA_PACING_BALANCE"],
]

var simulation_host: SimulationHost
var overall_rating: OptionButton
var objective_clarity: OptionButton
var controls_clarity: OptionButton
var agent_usefulness: OptionButton
var priority_area: OptionButton
var best_part: TextEdit
var biggest_problem: TextEdit
var suggestions: TextEdit
var encountered_bug: CheckButton
var bug_details: TextEdit
var status_label: Label
var submit_button: Button
var retry_button: Button
var close_button: Button
var panel: PanelContainer
var _http_request: HTTPRequest
var _record: Dictionary = {}
var _pending_delivery: Array[Dictionary] = []
var _active_payload: Dictionary = {}
var _feedback_endpoint := ""
var _suppressed_hover_tooltip: HoverTooltip


func _ready() -> void:
	_feedback_endpoint = PlaytestFeedbackStore.endpoint_from_arguments(OS.get_cmdline_user_args())
	_build_ui()
	refresh_locale()
	visible = false
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.connect(_apply_responsive_layout)


func configure(host: SimulationHost) -> void:
	simulation_host = host


func open_feedback(record: Dictionary) -> void:
	_record = record.duplicate(true)
	var hover_tooltip := get_parent().get_node_or_null("HoverTooltip") as HoverTooltip
	if hover_tooltip != null and hover_tooltip.is_node_ready():
		hover_tooltip.clear()
		hover_tooltip.visible = false
		_suppressed_hover_tooltip = hover_tooltip
	visible = true
	_apply_responsive_layout()
	_refresh_pending_status()
	overall_rating.grab_focus()


func refresh_locale() -> void:
	if panel == null:
		return
	panel.get_node("Margin/Layout/Title").text = GameText.t(&"FEEDBACK_TITLE")
	panel.get_node("Margin/Layout/Intro").text = GameText.t(&"FEEDBACK_INTRO")
	panel.get_node("Margin/Layout/Privacy").text = GameText.t(&"FEEDBACK_PRIVACY")
	_set_question_text("Overall/Label", &"FEEDBACK_OVERALL")
	_set_question_text("ObjectiveClarity/Label", &"FEEDBACK_OBJECTIVE_CLARITY")
	_set_question_text("ControlsClarity/Label", &"FEEDBACK_CONTROLS_CLARITY")
	_set_question_text("AgentUsefulness/Label", &"FEEDBACK_AGENT_USEFULNESS")
	_set_question_text("Priority/Label", &"FEEDBACK_PRIORITY")
	_set_field_label("BestPart/Label", &"FEEDBACK_BEST_PART")
	_set_field_label("BiggestProblem/Label", &"FEEDBACK_BIGGEST_PROBLEM")
	_set_field_label("Suggestions/Label", &"FEEDBACK_SUGGESTIONS")
	_set_field_label("BugDetails/Label", &"FEEDBACK_BUG_DETAILS")
	encountered_bug.text = GameText.t(&"FEEDBACK_ENCOUNTERED_BUG")
	submit_button.text = GameText.t(&"FEEDBACK_SUBMIT")
	retry_button.text = GameText.t(&"FEEDBACK_RETRY")
	close_button.text = GameText.t(&"FEEDBACK_CLOSE")
	_refresh_rating_options(overall_rating)
	_refresh_rating_options(objective_clarity)
	_refresh_rating_options(controls_clarity)
	_refresh_rating_options(agent_usefulness)
	_refresh_priority_options()
	_refresh_pending_status()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.008, 0.012, 0.013, 0.96)
	add_child(backdrop)

	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	backdrop.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.032, 0.033, 0.99)
	style.border_color = Color(0.31, 0.39, 0.39)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.96, 0.78, 0.28))
	layout.add_child(title)
	var intro := Label.new()
	intro.name = "Intro"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color(0.78, 0.84, 0.81))
	layout.add_child(intro)
	var privacy := Label.new()
	privacy.name = "Privacy"
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.add_theme_font_size_override("font_size", 11)
	privacy.add_theme_color_override("font_color", Color(0.55, 0.76, 0.72))
	layout.add_child(privacy)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var form := VBoxContainer.new()
	form.name = "Form"
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	scroll.add_child(form)
	overall_rating = _add_option_question(form, "Overall")
	objective_clarity = _add_option_question(form, "ObjectiveClarity")
	controls_clarity = _add_option_question(form, "ControlsClarity")
	agent_usefulness = _add_option_question(form, "AgentUsefulness")
	priority_area = _add_option_question(form, "Priority")
	best_part = _add_text_question(form, "BestPart", 64.0)
	biggest_problem = _add_text_question(form, "BiggestProblem", 80.0)
	suggestions = _add_text_question(form, "Suggestions", 80.0)
	encountered_bug = CheckButton.new()
	encountered_bug.name = "EncounteredBug"
	encountered_bug.toggled.connect(func(enabled: bool) -> void: bug_details.editable = enabled)
	form.add_child(encountered_bug)
	bug_details = _add_text_question(form, "BugDetails", 70.0)
	bug_details.editable = false

	status_label = Label.new()
	status_label.name = "Status"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color(0.72, 0.79, 0.76))
	layout.add_child(status_label)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 8)
	layout.add_child(actions)
	submit_button = _add_action_button(actions, "Submit", _on_submit_pressed)
	retry_button = _add_action_button(actions, "Retry", _on_retry_pressed)
	close_button = _add_action_button(actions, "Close", _on_close_pressed)

	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	_http_request.timeout = 10.0
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)
	_apply_responsive_layout()


func _add_option_question(parent: VBoxContainer, node_name: String) -> OptionButton:
	var row := BoxContainer.new()
	row.name = node_name
	row.vertical = false
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := Label.new()
	label.name = "Label"
	label.custom_minimum_size.x = 300.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "Option"
	option.custom_minimum_size = Vector2(250.0, 38.0)
	row.add_child(option)
	return option


func _add_text_question(parent: VBoxContainer, node_name: String, height: float) -> TextEdit:
	var group := VBoxContainer.new()
	group.name = node_name
	parent.add_child(group)
	var label := Label.new()
	label.name = "Label"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	group.add_child(label)
	var editor := TextEdit.new()
	editor.name = "Input"
	editor.custom_minimum_size.y = height
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	group.add_child(editor)
	return editor


func _add_action_button(parent: HBoxContainer, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size.y = 42.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _set_question_text(path: String, key: StringName) -> void:
	(panel.get_node("Margin/Layout/Scroll/Form/%s" % path) as Label).text = GameText.t(key)


func _set_field_label(path: String, key: StringName) -> void:
	(panel.get_node("Margin/Layout/Scroll/Form/%s" % path) as Label).text = GameText.t(key)


func _refresh_rating_options(option: OptionButton) -> void:
	var selected := option.selected
	option.clear()
	option.add_item(GameText.t(&"FEEDBACK_RATING_CHOOSE"))
	option.set_item_metadata(0, 0)
	for rating in range(1, 6):
		option.add_item(GameText.t(&"FEEDBACK_RATING_VALUE") % rating)
		option.set_item_metadata(rating, rating)
	option.select(clampi(selected, 0, 5))


func _refresh_priority_options() -> void:
	var selected_id := _selected_metadata(priority_area)
	priority_area.clear()
	priority_area.add_item(GameText.t(&"FEEDBACK_PRIORITY_CHOOSE"))
	priority_area.set_item_metadata(0, "")
	for item in PRIORITY_AREAS:
		priority_area.add_item(GameText.t(item[1]))
		priority_area.set_item_metadata(priority_area.item_count - 1, item[0])
	for index in range(priority_area.item_count):
		if String(priority_area.get_item_metadata(index)) == selected_id:
			priority_area.select(index)
			break


func _on_submit_pressed() -> void:
	var responses := _collect_responses()
	var context := _build_context()
	var payload := PlaytestFeedbackStore.create_submission(context, responses)
	var errors := PlaytestFeedbackStore.validate_submission(payload)
	if not errors.is_empty():
		status_label.text = GameText.t(&"FEEDBACK_VALIDATION_ERROR")
		status_label.modulate = Color(1.0, 0.58, 0.42)
		return
	var pending_path := PlaytestFeedbackStore.save_pending(payload)
	if pending_path.is_empty():
		status_label.text = GameText.t(&"FEEDBACK_SAVE_ERROR")
		status_label.modulate = Color(1.0, 0.48, 0.38)
		return
	_clear_form()
	status_label.modulate = Color.WHITE
	_queue_delivery(payload)


func _on_retry_pressed() -> void:
	if _http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_pending_delivery = PlaytestFeedbackStore.load_pending(ArmyRosterStore.active_playtest_session_id())
	_deliver_next()


func _queue_delivery(payload: Dictionary) -> void:
	_pending_delivery.append(payload.duplicate(true))
	_deliver_next()


func _deliver_next() -> void:
	if not _active_payload.is_empty():
		return
	if _pending_delivery.is_empty():
		_refresh_pending_status()
		return
	if _feedback_endpoint.is_empty():
		status_label.text = GameText.t(&"FEEDBACK_SAVED_OFFLINE")
		_refresh_retry_button()
		return
	_active_payload = _pending_delivery.pop_front()
	status_label.text = GameText.t(&"FEEDBACK_SENDING")
	var error := _http_request.request(
		_feedback_endpoint,
		PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(_active_payload)
	)
	if error != OK:
		_active_payload = {}
		status_label.text = GameText.t(&"FEEDBACK_SAVED_OFFLINE")
		_refresh_retry_button()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var delivered := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var archived := delivered and PlaytestFeedbackStore.mark_sent(_active_payload)
	if archived:
		status_label.text = GameText.t(&"FEEDBACK_SENT")
		status_label.modulate = Color(0.42, 0.86, 0.68)
	else:
		status_label.text = GameText.t(&"FEEDBACK_SAVED_OFFLINE")
		status_label.modulate = Color(0.88, 0.76, 0.38)
	_active_payload = {}
	if archived:
		if _pending_delivery.is_empty():
			_refresh_retry_button()
		else:
			_deliver_next()
	else:
		_pending_delivery.clear()
		_refresh_retry_button()


func _collect_responses() -> Dictionary:
	return {
		"overall_rating": int(_selected_metadata(overall_rating)),
		"objective_clarity": int(_selected_metadata(objective_clarity)),
		"controls_clarity": int(_selected_metadata(controls_clarity)),
		"agent_usefulness": int(_selected_metadata(agent_usefulness)),
		"priority_area": _selected_metadata(priority_area),
		"best_part": best_part.text,
		"biggest_problem": biggest_problem.text,
		"suggestions": suggestions.text,
		"encountered_bug": encountered_bug.button_pressed,
		"bug_details": bug_details.text,
	}


func _build_context() -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2.ZERO
	return {
		"build_id": ProjectSettings.get_setting("application/config/version", "development"),
		"anonymous_session_id": ArmyRosterStore.active_playtest_session_id(),
		"scenario_id": String(simulation_host.get_scenario_id()) if simulation_host != null else String(_record.get("last_scenario_id", "unknown")),
		"outcome": String(_record.get("last_result", "unknown")),
		"battle_count": int(_record.get("battle_count", 0)),
		"locale": TranslationServer.get_locale(),
		"viewport": {"width": roundi(viewport_size.x), "height": roundi(viewport_size.y)},
	}


func _selected_metadata(option: OptionButton) -> String:
	return str(option.get_item_metadata(option.selected)) if option.selected >= 0 else ""


func _clear_form() -> void:
	overall_rating.select(0)
	objective_clarity.select(0)
	controls_clarity.select(0)
	agent_usefulness.select(0)
	priority_area.select(0)
	best_part.clear()
	biggest_problem.clear()
	suggestions.clear()
	encountered_bug.button_pressed = false
	bug_details.clear()
	bug_details.editable = false


func _refresh_pending_status() -> void:
	if status_label == null:
		return
	var count := PlaytestFeedbackStore.load_pending(ArmyRosterStore.active_playtest_session_id()).size()
	status_label.text = GameText.t(&"FEEDBACK_PENDING_COUNT") % count if count > 0 else GameText.t(&"FEEDBACK_READY")
	status_label.modulate = Color(0.72, 0.79, 0.76)
	_refresh_retry_button(count)


func _refresh_retry_button(known_count: int = -1) -> void:
	if retry_button == null:
		return
	var count := known_count
	if count < 0:
		count = PlaytestFeedbackStore.load_pending(ArmyRosterStore.active_playtest_session_id()).size()
	retry_button.disabled = count <= 0 or _feedback_endpoint.is_empty()
	retry_button.tooltip_text = GameText.t(&"FEEDBACK_SERVER_UNCONFIGURED") if _feedback_endpoint.is_empty() else ""


func _on_close_pressed() -> void:
	visible = false
	if _suppressed_hover_tooltip != null and is_instance_valid(_suppressed_hover_tooltip):
		_suppressed_hover_tooltip.visible = true
	_suppressed_hover_tooltip = null


func _apply_responsive_layout() -> void:
	if panel == null or get_viewport() == null:
		return
	var size := get_viewport().get_visible_rect().size
	var width := minf(900.0, size.x - 16.0)
	var height := minf(720.0, size.y - 16.0)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	var compact := size.x < 700.0
	for node_name in ["Overall", "ObjectiveClarity", "ControlsClarity", "AgentUsefulness", "Priority"]:
		var row := panel.get_node("Margin/Layout/Scroll/Form/%s" % node_name) as BoxContainer
		row.vertical = compact
		(row.get_node("Label") as Label).custom_minimum_size.x = 0.0 if compact else 300.0
		(row.get_node("Option") as OptionButton).custom_minimum_size.x = 0.0 if compact else 250.0
