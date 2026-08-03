class_name SelectionOverlay
extends Control

var drag_active: bool = false
var drag_start: Vector2
var drag_current: Vector2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func begin_drag(screen_position: Vector2) -> void:
	drag_active = true
	drag_start = screen_position
	drag_current = screen_position
	queue_redraw()


func update_drag(screen_position: Vector2) -> void:
	if not drag_active:
		return
	drag_current = screen_position
	queue_redraw()


func end_drag() -> void:
	drag_active = false
	queue_redraw()


func _draw() -> void:
	if not drag_active:
		return
	var selection_rect := Rect2(drag_start, drag_current - drag_start).abs()
	draw_rect(selection_rect, Color(0.28, 0.72, 0.77, 0.14), true)
	draw_rect(selection_rect, Color(0.41, 0.82, 0.86, 0.9), false, 1.5)
