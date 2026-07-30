class_name Battlefield
extends Node2D

const BOUNDS := SimulationWorld.BATTLEFIELD_BOUNDS
const GRID_SIZE := 48.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280.0, 720.0)), Color("11181b"))
	draw_rect(BOUNDS, Color("182328"), true)

	var grid_color := Color(0.22, 0.32, 0.34, 0.32)
	var x := BOUNDS.position.x
	while x <= BOUNDS.end.x:
		draw_line(Vector2(x, BOUNDS.position.y), Vector2(x, BOUNDS.end.y), grid_color, 1.0)
		x += GRID_SIZE
	var y := BOUNDS.position.y
	while y <= BOUNDS.end.y:
		draw_line(Vector2(BOUNDS.position.x, y), Vector2(BOUNDS.end.x, y), grid_color, 1.0)
		y += GRID_SIZE

	draw_rect(BOUNDS, Color("789097"), false, 2.0)
