class_name ContactAlert
extends PanelContainer

const DISPLAY_SECONDS := 3.0

@onready var message_label: Label = $Message
@onready var alert_audio: AudioStreamPlayer = $AlertAudio

var _remaining: float = 0.0
var _contact_definition_id: StringName = &""
var _is_building: bool = false
var _audio_play_count: int = 0
var _message_key: StringName
var _message_arguments: Array = []
var _message_priority: int = 0
var audio_enabled: bool = true


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_audio()


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		visible = false


func show_contact(definition_id: StringName, is_building: bool = false, play_contact_audio: bool = true) -> void:
	if visible and _remaining > 0.6 and not _message_key.is_empty():
		return
	_contact_definition_id = definition_id
	_is_building = is_building
	_message_key = &""
	_message_arguments.clear()
	_message_priority = BattleFeedbackDirector.Severity.INFO
	_remaining = DISPLAY_SECONDS
	refresh_locale()
	visible = true
	if audio_enabled and play_contact_audio:
		_audio_play_count += 1
		var audio := _ensure_audio()
		if audio != null and audio.is_inside_tree():
			audio.play()


func show_battle_feedback(message_key: StringName, arguments: Array, severity: int) -> bool:
	if visible and _remaining > 0.6 and severity < _message_priority:
		return false
	_contact_definition_id = &""
	_message_key = message_key
	_message_arguments = arguments.duplicate()
	_message_priority = severity
	_remaining = 3.6 if severity == BattleFeedbackDirector.Severity.CRITICAL else 2.6
	refresh_locale()
	visible = true
	return true


func show_command_result(result: CommandValidationResult) -> bool:
	if result == null:
		return false
	var severity := BattleFeedbackDirector.Severity.INFO if result.is_accepted() else BattleFeedbackDirector.Severity.WARNING
	return show_battle_feedback(&"BATTLE_FEEDBACK_COMMAND_RESULT", [GameText.command_result(result)], severity)


func get_audio_play_count() -> int:
	return _audio_play_count


func set_audio_enabled(enabled: bool) -> void:
	audio_enabled = enabled
	if not enabled and alert_audio != null:
		alert_audio.stop()


func _ensure_audio() -> AudioStreamPlayer:
	if alert_audio == null:
		alert_audio = get_node_or_null("AlertAudio") as AudioStreamPlayer
	if alert_audio != null and alert_audio.stream == null:
		alert_audio.volume_db = -10.0
		alert_audio.stream = UIFeedbackAudio.create_tone(PackedFloat32Array([620.0, 880.0, 740.0]), 0.07, 0.22)
	return alert_audio


func refresh_locale() -> void:
	if message_label == null:
		return
	if not _message_key.is_empty():
		var localized_arguments: Array = []
		for argument in _message_arguments:
			localized_arguments.append(GameText.t(argument as StringName) if argument is StringName else argument)
		message_label.text = GameText.t(_message_key) % localized_arguments if not localized_arguments.is_empty() else GameText.t(_message_key)
		message_label.add_theme_color_override("font_color", _severity_color(_message_priority))
		return
	if _contact_definition_id.is_empty():
		return
	var contact_name := GameText.building_name(_contact_definition_id) if _is_building else GameText.unit_name(_contact_definition_id)
	message_label.text = GameText.t(&"CONTACT_ALERT") % contact_name
	message_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.67))


func _severity_color(severity: int) -> Color:
	if severity == BattleFeedbackDirector.Severity.CRITICAL:
		return Color(1.0, 0.38, 0.28)
	if severity == BattleFeedbackDirector.Severity.WARNING:
		return Color(1.0, 0.72, 0.3)
	return Color(0.52, 0.9, 0.8)
