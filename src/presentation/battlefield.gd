class_name Battlefield
extends Node2D

const BOUNDS := SimulationWorld.BATTLEFIELD_BOUNDS
const GRID_SIZE := LogicGrid.CELL_SIZE

var logic_grid := LogicGrid.create_test_map()


func _draw() -> void:
	draw_rect(BOUNDS, Color("11181b"), true)
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

	for cell in logic_grid.get_blocked_cells():
		var cell_rect := Rect2(logic_grid.cell_to_world(cell) - Vector2.ONE * GRID_SIZE * 0.5, Vector2.ONE * GRID_SIZE)
		draw_rect(cell_rect.grow(-3.0), Color("3f5155"), true)
		draw_rect(cell_rect.grow(-3.0), Color("779096"), false, 2.0)

	draw_rect(BOUNDS, Color("789097"), false, 2.0)
