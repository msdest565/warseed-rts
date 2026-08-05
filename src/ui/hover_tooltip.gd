class_name HoverTooltip
extends CanvasLayer

const HOVER_DELAY_SECONDS := 1.0
const CURSOR_OFFSET := Vector2(18.0, 22.0)

@onready var panel: PanelContainer = $Panel
@onready var label: Label = $Panel/Margin/Text

var _candidate_key: String = ""
var _candidate_text: String = ""
var _hover_seconds: float = 0.0


func _ready() -> void:
	panel.hide()


func update_candidate(key: String, text: String, mouse_position: Vector2, delta: float) -> void:
	if key.is_empty() or text.is_empty():
		clear()
		return
	if key != _candidate_key:
		_candidate_key = key
		_candidate_text = text
		_hover_seconds = 0.0
		panel.hide()
	elif text != _candidate_text:
		_candidate_text = text
	_hover_seconds += delta
	if _hover_seconds < HOVER_DELAY_SECONDS:
		return
	label.text = _candidate_text
	panel.show()
	_place_near_cursor(mouse_position)


func clear() -> void:
	_candidate_key = ""
	_candidate_text = ""
	_hover_seconds = 0.0
	panel.hide()


func _place_near_cursor(mouse_position: Vector2) -> void:
	if not panel.is_inside_tree():
		return
	var viewport_size := panel.get_viewport_rect().size
	var desired := mouse_position + CURSOR_OFFSET
	desired.x = clampf(desired.x, 8.0, maxf(8.0, viewport_size.x - panel.size.x - 8.0))
	desired.y = clampf(desired.y, 8.0, maxf(8.0, viewport_size.y - panel.size.y - 8.0))
	panel.position = desired
