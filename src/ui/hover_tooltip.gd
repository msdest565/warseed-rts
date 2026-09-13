class_name HoverTooltip
extends CanvasLayer

const HOVER_DELAY_SECONDS := 1.0
const PROGRESS_START_SECONDS := 0.5
const CURSOR_OFFSET := Vector2(18.0, 22.0)

@onready var panel: PanelContainer = $Panel
@onready var label: Label = $Panel/Margin/Text

var _candidate_key: String = ""
var _candidate_text: String = ""
var _hover_seconds: float = 0.0
var progress: ProgressBar


func _ready() -> void:
	panel.hide()
	_ignore_mouse(panel)
	if progress == null:
		progress = ProgressBar.new()
		progress.name = "HoverProgress"
		progress.size = Vector2(100.0, 8.0)
		progress.show_percentage = false
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(progress)
	progress.hide()


func update_candidate(key: String, text: String, mouse_position: Vector2, delta: float, avoid_rect: Rect2 = Rect2()) -> void:
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
		if progress != null:
			progress.visible = _hover_seconds >= PROGRESS_START_SECONDS
			progress.value = 100.0 * (_hover_seconds - PROGRESS_START_SECONDS) / (HOVER_DELAY_SECONDS - PROGRESS_START_SECONDS)
			_place_control(progress, mouse_position, avoid_rect)
		return
	if progress != null:
		progress.hide()
	label.text = _candidate_text
	panel.show()
	_place_control(panel, mouse_position, avoid_rect)


func clear() -> void:
	_candidate_key = ""
	_candidate_text = ""
	_hover_seconds = 0.0
	panel.hide()
	if progress != null:
		progress.hide()


func _place_control(control: Control, mouse_position: Vector2, avoid_rect: Rect2) -> void:
	if not panel.is_inside_tree():
		return
	var viewport_size := panel.get_viewport_rect().size
	var maximum := (viewport_size - control.size - Vector2(8, 8)).max(Vector2(8, 8))
	var desired := (mouse_position + CURSOR_OFFSET).clamp(Vector2(8, 8), maximum)
	if avoid_rect.has_area() and Rect2(desired, control.size).intersects(avoid_rect.grow(8.0)):
		var above := avoid_rect.position.y - control.size.y - 8.0
		if above >= 8.0:
			desired.y = above
		elif avoid_rect.end.y + 8.0 + control.size.y <= viewport_size.y - 8.0:
			desired.y = avoid_rect.end.y + 8.0
		elif avoid_rect.position.x - control.size.x - 8.0 >= 8.0:
			desired.x = avoid_rect.position.x - control.size.x - 8.0
		else:
			desired.x = avoid_rect.end.x + 8.0
	control.position = desired.clamp(Vector2(8, 8), maximum)


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
