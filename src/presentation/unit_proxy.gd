class_name UnitProxy
extends Node2D

const BODY_COLOR := Color("3aa7a3")
const ACCENT_COLOR := Color("d7e3bb")
const TRACK_COLOR := Color("172126")
const SELECT_COLOR := Color("f2c94c")

var entity_id: int
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()


func configure(new_entity_id: int) -> void:
	entity_id = new_entity_id
	queue_redraw()


func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 48, SELECT_COLOR, 3.0)

	draw_rect(Rect2(-24.0, -18.0, 48.0, 8.0), TRACK_COLOR, true)
	draw_rect(Rect2(-24.0, 10.0, 48.0, 8.0), TRACK_COLOR, true)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-20.0, -13.0),
			Vector2(14.0, -13.0),
			Vector2(23.0, 0.0),
			Vector2(14.0, 13.0),
			Vector2(-20.0, 13.0),
		]),
		BODY_COLOR
	)
	draw_circle(Vector2(0.0, 0.0), 8.0, ACCENT_COLOR)
	draw_line(Vector2.ZERO, Vector2(23.0, 0.0), ACCENT_COLOR, 4.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-10.0, 42.0),
		"E%d" % entity_id,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		14,
		Color("dce8e8")
	)
