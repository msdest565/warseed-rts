class_name FactionKnowledge
extends RefCounted

enum CellState {
	UNEXPLORED,
	EXPLORED,
	VISIBLE,
}

var faction_id: int
var grid_size: Vector2i
var cells: PackedByteArray
var hostile_contacts: Dictionary = {}
var visible_hostile_unit_ids: PackedInt32Array = PackedInt32Array()
var visible_hostile_building_ids: PackedInt32Array = PackedInt32Array()
var _visible_indices: PackedInt32Array = PackedInt32Array()
var identification_until_by_entity: Dictionary = {}
var _reveal_offsets_by_radius: Dictionary = {}
var _revealed_circles: Dictionary = {}


func _init(new_faction_id: int, new_grid_size: Vector2i) -> void:
	faction_id = new_faction_id
	grid_size = new_grid_size
	cells.resize(grid_size.x * grid_size.y)
	cells.fill(CellState.UNEXPLORED)


func begin_update() -> void:
	_revealed_circles.clear()
	for index in _visible_indices:
		if cells[index] == CellState.VISIBLE:
			cells[index] = CellState.EXPLORED
	_visible_indices.clear()
	visible_hostile_unit_ids.clear()
	visible_hostile_building_ids.clear()


func reveal(center: Vector2i, radius_cells: int) -> void:
	var circle := Vector3i(center.x, center.y, radius_cells)
	if _revealed_circles.has(circle):
		return
	_revealed_circles[circle] = true
	if center.x >= radius_cells and center.y >= radius_cells and center.x + radius_cells < grid_size.x and center.y + radius_cells < grid_size.y:
		if not _reveal_offsets_by_radius.has(radius_cells):
			var offsets := PackedInt32Array()
			for y in range(-radius_cells, radius_cells + 1):
				for x in range(-radius_cells, radius_cells + 1):
					if x * x + y * y <= radius_cells * radius_cells:
						offsets.append(y * grid_size.x + x)
			_reveal_offsets_by_radius[radius_cells] = offsets
		var center_index := center.y * grid_size.x + center.x
		for offset in _reveal_offsets_by_radius[radius_cells]:
			var index: int = center_index + offset
			if cells[index] != CellState.VISIBLE:
				cells[index] = CellState.VISIBLE
				_visible_indices.append(index)
		return
	var radius_squared := radius_cells * radius_cells
	for y in range(maxi(0, center.y - radius_cells), mini(grid_size.y, center.y + radius_cells + 1)):
		for x in range(maxi(0, center.x - radius_cells), mini(grid_size.x, center.x + radius_cells + 1)):
			var offset_x := x - center.x
			var offset_y := y - center.y
			if offset_x * offset_x + offset_y * offset_y > radius_squared:
				continue
			var index := y * grid_size.x + x
			if cells[index] != CellState.VISIBLE:
				cells[index] = CellState.VISIBLE
				_visible_indices.append(index)


func get_cell_state(cell: Vector2i) -> CellState:
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
		return CellState.UNEXPLORED
	return cells[_index(cell)] as CellState


func is_visible(cell: Vector2i) -> bool:
	return get_cell_state(cell) == CellState.VISIBLE


func unexplored_frontier_cells() -> Array[Vector2i]:
	# Read the faction's packed knowledge once per cell. Calling get_cell_state
	# for every neighbor of every map cell made scout retargeting stall a tick.
	var frontier: Array[Vector2i] = []
	var width := grid_size.x
	for index in range(cells.size()):
		if cells[index] != CellState.UNEXPLORED:
			continue
		var x := index % width
		if (x > 0 and cells[index - 1] != CellState.UNEXPLORED) \
			or (x + 1 < width and cells[index + 1] != CellState.UNEXPLORED) \
			or (index >= width and cells[index - width] != CellState.UNEXPLORED) \
			or (index + width < cells.size() and cells[index + width] != CellState.UNEXPLORED):
			frontier.append(Vector2i(x, index / width))
	return frontier


func _index(cell: Vector2i) -> int:
	return cell.y * grid_size.x + cell.x
