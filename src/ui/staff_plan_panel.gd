class_name StaffPlanPanel
extends PopupPanel

signal status_changed(message: String)

var host: SimulationHost
var objective_selector: OptionButton
var budget: SpinBox
var risk: OptionButton
var card_choices: GridContainer
var plan_rows: GridContainer
var status_label: Label
var title_label: Label
var subtitle_label: Label
var generate_button: Button
var reject_button: Button
var objective_label: Label
var budget_label: Label
var risk_label: Label
var cards_label: Label
var scroll: ScrollContainer
var current_plans: StaffPlanSet
var pending_command_id: int = 0
var _was_paused := false
var _restoring_pause := false
var _request := StaffPlanRequest.new()
var _choices: Dictionary[StringName, CheckBox] = {}
var _approve_buttons: Array[Button] = []


func _ready() -> void:
	wrap_controls = false
	_build()
	popup_hide.connect(_on_closed)
	set_process(true)


func open_plans(new_host: SimulationHost, objective_id: StringName) -> void:
	if new_host == null or new_host.current_snapshot == null or not new_host.is_grey_ridge_battle_started():
		return
	host = new_host
	_was_paused = host.is_tactical_paused()
	host.set_tactical_paused(true)
	_request = StaffPlanRequest.new()
	_request.objective_region_id = objective_id
	current_plans = null
	_populate()
	var viewport_size := get_tree().root.get_visible_rect().size
	min_size = Vector2i.ZERO
	max_size = Vector2i(minf(1120.0, viewport_size.x - 24.0), minf(760.0, viewport_size.y - 24.0))
	size = max_size
	plan_rows.columns = 3 if size.x >= 950 else 1
	card_choices.columns = 3 if size.x >= 800 else 2
	refresh_locale()
	popup_centered(size)
	generate()
	generate_button.grab_focus()


func reset_session() -> void:
	pending_command_id = 0
	current_plans = null
	if visible:
		hide()
	host = null


func _build() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.035, 0.055, 0.06, 1.0)
	background.border_color = Color(0.22, 0.55, 0.49, 1.0)
	background.set_border_width_all(2)
	add_theme_stylebox_override("panel", background)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)
	title_label = _label(22)
	layout.add_child(title_label)
	subtitle_label = _label(13)
	layout.add_child(subtitle_label)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	var fields := GridContainer.new()
	fields.columns = 2
	content.add_child(fields)
	objective_label = _label()
	fields.add_child(objective_label)
	objective_selector = OptionButton.new()
	objective_selector.fit_to_longest_item = false
	objective_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_selector.item_selected.connect(_edited.unbind(1))
	fields.add_child(objective_selector)
	budget_label = _label()
	fields.add_child(budget_label)
	budget = SpinBox.new()
	budget.min_value = 0
	budget.max_value = 1000
	budget.step = 1
	budget.value_changed.connect(_edited.unbind(1))
	fields.add_child(budget)
	risk_label = _label()
	fields.add_child(risk_label)
	risk = OptionButton.new()
	risk.fit_to_longest_item = false
	risk.item_selected.connect(_edited.unbind(1))
	fields.add_child(risk)
	cards_label = _label()
	content.add_child(cards_label)
	card_choices = GridContainer.new()
	content.add_child(card_choices)
	generate_button = _button(&"STAFF_GENERATE", generate)
	content.add_child(generate_button)
	plan_rows = GridContainer.new()
	plan_rows.add_theme_constant_override("h_separation", 12)
	plan_rows.add_theme_constant_override("v_separation", 12)
	content.add_child(plan_rows)
	status_label = _label()
	layout.add_child(status_label)
	reject_button = _button(&"STAFF_REJECT", _reject)
	layout.add_child(reject_button)


func _populate() -> void:
	objective_selector.clear()
	var snapshot := host.current_snapshot
	var regions := snapshot.strategic_regions.duplicate()
	regions.sort_custom(func(a: StrategicRegionSnapshot, b: StrategicRegionSnapshot) -> bool: return String(a.region_id) < String(b.region_id))
	for region in regions:
		if not region.capturable or region.controller_faction_id == snapshot.observer_faction_id:
			continue
		objective_selector.add_item(GameText.t(region.display_name_key))
		objective_selector.set_item_metadata(objective_selector.item_count - 1, region.region_id)
		if region.region_id == _request.objective_region_id:
			objective_selector.select(objective_selector.item_count - 1)
	budget.set_value_no_signal(_request.max_supply_cost)
	_clear_children(card_choices)
	_choices.clear()
	var cards := snapshot.unit_cards.duplicate()
	cards.sort_custom(func(a: UnitCardSnapshot, b: UnitCardSnapshot) -> bool: return String(a.definition_id) < String(b.definition_id))
	for card in cards:
		if card.faction_id != snapshot.observer_faction_id:
			continue
		var choice := CheckBox.new()
		choice.text = GameText.t(card.display_name_key)
		choice.clip_text = true
		choice.tooltip_text = choice.text
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.button_pressed = true
		choice.toggled.connect(_edited.unbind(1))
		card_choices.add_child(choice)
		_choices[card.definition_id] = choice


func refresh_locale() -> void:
	if title_label == null:
		return
	title_label.text = GameText.t(&"STAFF_TITLE")
	subtitle_label.text = GameText.t(&"STAFF_COMPARE_HINT")
	objective_label.text = GameText.t(&"STAFF_OBJECTIVE")
	budget_label.text = GameText.t(&"STAFF_BUDGET")
	risk_label.text = GameText.t(&"STAFF_RISK_PREFERENCE")
	cards_label.text = GameText.t(&"STAFF_ALLOWED_CARDS")
	generate_button.text = GameText.t(&"STAFF_GENERATE")
	reject_button.text = GameText.t(&"STAFF_REJECT")
	var selected := maxi(0, risk.selected)
	risk.clear()
	for key in [&"STAFF_RISK_LOW", &"STAFF_RISK_MEDIUM", &"STAFF_RISK_HIGH"]:
		risk.add_item(GameText.t(key))
	risk.select(selected if current_plans != null else _request.risk_aversion - 1)
	if host != null and host.current_snapshot != null:
		for index in range(objective_selector.item_count):
			var region := host.current_snapshot.get_strategic_region(objective_selector.get_item_metadata(index))
			if region != null:
				objective_selector.set_item_text(index, GameText.t(region.display_name_key))
		for id in _choices:
			var card := host.current_snapshot.get_unit_card(id)
			if card != null:
				_choices[id].text = GameText.t(card.display_name_key)
				_choices[id].tooltip_text = _choices[id].text
	_rebuild_plans()


func generate() -> void:
	if host == null or objective_selector.selected < 0:
		_set_status(GameText.t(&"STAFF_NO_ALTERNATIVES"))
		return
	_request.objective_region_id = objective_selector.get_item_metadata(objective_selector.selected)
	_request.max_supply_cost = int(budget.value)
	_request.risk_aversion = risk.selected + 1
	_request.allowed_card_ids.clear()
	for id in _choices:
		if _choices[id].button_pressed:
			_request.allowed_card_ids.append(id)
	current_plans = host.get_staff_plans(_request) if not _request.allowed_card_ids.is_empty() else null
	_rebuild_plans()
	_set_status(GameText.t(&"STAFF_CHOOSE") if current_plans != null else GameText.t(&"STAFF_NO_ALTERNATIVES"))


func _edited() -> void:
	current_plans = null
	_rebuild_plans()
	_set_status(GameText.t(&"STAFF_EDITED"))


func _rebuild_plans() -> void:
	if plan_rows == null:
		return
	_clear_children(plan_rows)
	_approve_buttons.clear()
	if current_plans == null:
		return
	for plan in current_plans.plans:
		var panel := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.07, 0.1, 0.11, 1.0)
		card_style.border_color = Color(0.19, 0.29, 0.29, 1.0)
		card_style.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", card_style)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plan_rows.add_child(panel)
		var margin := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 10)
		panel.add_child(margin)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		margin.add_child(column)
		var heading := _label(18)
		heading.text = GameText.t(plan.name_key)
		column.add_child(heading)
		var summary := _label()
		summary.text = GameText.t(&"STAFF_PLAN_SUMMARY") % [plan.committed_strength, plan.reserve_strength, plan.supply_cost,
			float(plan.preparation_ticks) / 10.0, plan.risk_score, plan.utility_score]
		column.add_child(summary)
		var detail := _label(12)
		var lines: PackedStringArray = []
		for assignment in plan.assignments:
			var card := host.current_snapshot.get_unit_card(assignment.card_id)
			var region := host.current_snapshot.get_strategic_region(assignment.axis_region_id)
			lines.append(GameText.t(&"STAFF_ASSIGNMENT") % [GameText.t(card.display_name_key) if card != null else String(assignment.card_id),
				assignment.strength, GameText.t(&"STAFF_ROLE_%d" % assignment.role),
				GameText.t(region.display_name_key) if region != null else String(assignment.axis_region_id)])
		lines.append(GameText.t(&"STAFF_RISK_COMPONENTS") % [plan.known_threat_score, plan.uncertainty_score, plan.readiness_penalty])
		detail.text = "\n".join(lines)
		column.add_child(detail)
		var approve := _button(&"STAFF_APPROVE", _approve.bind(plan))
		approve.disabled = pending_command_id != 0
		column.add_child(approve)
		_approve_buttons.append(approve)


func _approve(plan: StaffCourseOfAction) -> void:
	if host == null or current_plans == null or pending_command_id != 0:
		return
	var command := host.create_staff_plan_approval_command(current_plans.request, plan)
	var result := host.submit_command(command)
	if not result.is_accepted():
		_set_status(GameText.t(&"STAFF_APPROVAL_FAILED") % GameText.t(StringName("REASON_%s" % CommandValidationResult.Reason.keys()[result.reason])))
		return
	pending_command_id = command.command_id
	_set_status(GameText.t(&"STAFF_QUEUED"))
	hide()


func _process(_delta: float) -> void:
	if pending_command_id == 0 or host == null or not is_instance_valid(host) or host.current_snapshot == null:
		return
	for decision in host.current_snapshot.staff_plan_decisions:
		if decision.command_id != pending_command_id:
			continue
		pending_command_id = 0
		_set_status(GameText.t(&"STAFF_APPROVED") if decision.accepted else GameText.t(&"STAFF_APPROVAL_FAILED") %
			GameText.t(StringName("REASON_%s" % CommandValidationResult.Reason.keys()[decision.reason])))
		break


func _reject() -> void:
	current_plans = null
	_set_status(GameText.t(&"STAFF_REJECTED"))
	hide()


func _on_closed() -> void:
	if host != null and is_instance_valid(host) and not _restoring_pause:
		_restoring_pause = true
		host.set_tactical_paused(_was_paused)
		_restoring_pause = false


func _set_status(message: String) -> void:
	status_label.text = message
	status_changed.emit(message)


func _label(font_size: int = 13) -> Label:
	var label := Label.new()
	label.size.x = 300
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(key: StringName, callback: Callable) -> Button:
	var button := Button.new()
	button.text = GameText.t(key)
	button.clip_text = true
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	return button


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
