class_name BattlefieldOverlayControls
extends PanelContainer

signal layer_visibility_changed(frontlines: bool, tasks: bool, threats: bool, intelligence: bool)

@onready var title_label: Label = $Margin/Layout/Header/Title
@onready var summary_label: Label = $Margin/Layout/Header/Summary
@onready var frontline_button: Button = $Margin/Layout/Toggles/Frontline
@onready var task_button: Button = $Margin/Layout/Toggles/Tasks
@onready var threat_button: Button = $Margin/Layout/Toggles/Threats
@onready var intelligence_button: Button = $Margin/Layout/Toggles/Intelligence
@onready var legend_label: Label = $Margin/Layout/Legend

var situation: BattlefieldSituationSnapshot


func _ready() -> void:
	for button in [frontline_button, task_button, threat_button, intelligence_button]:
		button.toggled.connect(_emit_visibility)
	refresh_locale()
	set_process_unhandled_key_input(true)


func update_situation(new_situation: BattlefieldSituationSnapshot) -> void:
	situation = new_situation
	_update_summary()


func refresh_locale() -> void:
	if title_label == null:
		return
	title_label.text = GameText.t(&"OVERLAY_TITLE")
	frontline_button.text = GameText.t(&"OVERLAY_FRONTLINE")
	task_button.text = GameText.t(&"OVERLAY_TASKS")
	threat_button.text = GameText.t(&"OVERLAY_THREATS")
	intelligence_button.text = GameText.t(&"OVERLAY_INTELLIGENCE")
	frontline_button.tooltip_text = GameText.t(&"OVERLAY_FRONTLINE_TOOLTIP")
	task_button.tooltip_text = GameText.t(&"OVERLAY_TASKS_TOOLTIP")
	threat_button.tooltip_text = GameText.t(&"OVERLAY_THREATS_TOOLTIP")
	intelligence_button.tooltip_text = GameText.t(&"OVERLAY_INTELLIGENCE_TOOLTIP")
	legend_label.text = GameText.t(&"OVERLAY_LEGEND")
	_update_summary()


func set_compact(compact: bool) -> void:
	if title_label != null:
		title_label.visible = not compact
	if legend_label != null:
		legend_label.visible = not compact
	var font_size := 10 if compact else 11
	for button in [frontline_button, task_button, threat_button, intelligence_button]:
		if button != null:
			button.add_theme_font_size_override("font_size", font_size)


func get_visibility_state() -> Dictionary:
	return {
		"frontlines": frontline_button.button_pressed,
		"tasks": task_button.button_pressed,
		"threats": threat_button.button_pressed,
		"intelligence": intelligence_button.button_pressed,
	}


func _emit_visibility(_pressed: bool = false) -> void:
	layer_visibility_changed.emit(
		frontline_button.button_pressed,
		task_button.button_pressed,
		threat_button.button_pressed,
		intelligence_button.button_pressed
	)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or not key.alt_pressed:
		return
	var button: Button
	match key.keycode:
		KEY_1: button = frontline_button
		KEY_2: button = task_button
		KEY_3: button = threat_button
		KEY_4: button = intelligence_button
	if button == null:
		return
	button.button_pressed = not button.button_pressed
	get_viewport().set_input_as_handled()


func _update_summary() -> void:
	if summary_label == null:
		return
	if situation == null:
		summary_label.text = GameText.t(&"OVERLAY_SUMMARY_EMPTY")
		return
	var known_threats := 0
	var stale_threats := 0
	for threat in situation.threat_zones:
		if bool(threat["known_threat"]):
			known_threats += 1
		if int(threat["age_ticks"]) >= BattlefieldSituationProjector.CONTACT_RECENT_TICKS:
			stale_threats += 1
	summary_label.text = GameText.t(&"OVERLAY_SUMMARY") % [situation.task_axes.size(), known_threats, stale_threats]
