class_name LogicGrid
extends RefCounted

const MAP_DEFINITION: MapDefinition = preload("res://data/maps/test_arena.tres")
const CELL_SIZE := 32.0
const GRID_SIZE := Vector2i(96, 64)
const WORLD_ORIGIN := Vector2.ZERO

var blocked_cells: Dictionary = {}
var revision: int = 0


static func create_test_map() -> LogicGrid:
	var grid := LogicGrid.new()
	# Legacy near-base wall keeps the compact navigation regression playable.
	for y in range(12):
		if y != 5 and y != 10:
			grid.set_blocked(Vector2i(11, y), true)
	grid._block_rect(Rect2i(18, 4, 2, 2))
	# Central divider with a two-cell choke.
	for y in range(12, 52):
		if y < 31 or y > 32:
			grid.set_blocked(Vector2i(47, y), true)
	# Northern and southern obstacle islands create route choices.
	grid._block_rect(Rect2i(30, 12, 8, 6))
	grid._block_rect(Rect2i(58, 46, 10, 6))
	grid._block_rect(Rect2i(67, 24, 4, 8))
	# Four-cell choke gates.
	for y in range(5, 25):
		if y < 14 or y > 17:
			grid.set_blocked(Vector2i(60, y), true)
	# Preserve a second compact 2x2 corner obstacle in the expanded arena.
	grid._block_rect(Rect2i(72, 30, 2, 2))
	return grid


func _block_rect(rect: Rect2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			set_blocked(Vector2i(x, y), true)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIZE.x and cell.y < GRID_SIZE.y


func set_blocked(cell: Vector2i, blocked: bool) -> void:
	if not is_in_bounds(cell):
		return
	if blocked:
		if not blocked_cells.has(cell):
			blocked_cells[cell] = true
			revision += 1
	elif blocked_cells.has(cell):
		blocked_cells.erase(cell)
		revision += 1


func is_blocked(cell: Vector2i) -> bool:
	return not is_in_bounds(cell) or blocked_cells.has(cell)


func is_world_position_walkable(world_position: Vector2) -> bool:
	return not is_blocked(world_to_cell(world_position))


func is_segment_walkable(from_position: Vector2, to_position: Vector2) -> bool:
	var distance := from_position.distance_to(to_position)
	var sample_count := maxi(1, ceili(distance / 8.0))
	for index in range(sample_count + 1):
		if not is_world_position_walkable(from_position.lerp(to_position, float(index) / sample_count)):
			return false
	return true


func get_corridor_width(cell: Vector2i, direction: Vector2i) -> int:
	if is_blocked(cell):
		return 0
	var perpendicular := Vector2i(-direction.y, direction.x)
	var width := 1
	var cursor := cell + perpendicular
	while not is_blocked(cursor):
		width += 1
		cursor += perpendicular
	cursor = cell - perpendicular
	while not is_blocked(cursor):
		width += 1
		cursor -= perpendicular
	return width


func world_to_cell(world_position: Vector2) -> Vector2i:
	var local := world_position - WORLD_ORIGIN
	return Vector2i(floori(local.x / CELL_SIZE), floori(local.y / CELL_SIZE))


func cell_to_world(cell: Vector2i) -> Vector2:
	return WORLD_ORIGIN + Vector2(cell) * CELL_SIZE + Vector2.ONE * CELL_SIZE * 0.5


func get_footprint_cells(world_position: Vector2, footprint_size: Vector2i) -> Array[Vector2i]:
	var center := world_to_cell(world_position)
	var first := center - Vector2i((footprint_size.x - 1) / 2, (footprint_size.y - 1) / 2)
	var cells: Array[Vector2i] = []
	for x in range(first.x, first.x + footprint_size.x):
		for y in range(first.y, first.y + footprint_size.y):
			cells.append(Vector2i(x, y))
	return cells


func get_footprint_work_cells(footprint_cells: Array[Vector2i]) -> Array[Vector2i]:
	var footprint_lookup: Dictionary = {}
	var cardinal_offsets: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for cell in footprint_cells:
		footprint_lookup[cell] = true
	var candidates: Array[Vector2i] = []
	for cell in footprint_cells:
		for offset in cardinal_offsets:
			var candidate: Vector2i = cell + offset
			if not footprint_lookup.has(candidate) and not candidates.has(candidate) and not is_blocked(candidate):
				candidates.append(candidate)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return candidates


func get_blocked_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell_variant in blocked_cells.keys():
		cells.append(cell_variant as Vector2i)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return cells
