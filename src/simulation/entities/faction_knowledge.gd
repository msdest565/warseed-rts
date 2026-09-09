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


func _init(new_faction_id: int, new_grid_size: Vector2i) -> void:
	faction_id = new_faction_id
	grid_size = new_grid_size
	cells.resize(grid_size.x * grid_size.y)
	cells.fill(CellState.UNEXPLORED)


func begin_update() -> void:
	for index in _visible_indices:
		if cells[index] == CellState.VISIBLE:
			cells[index] = CellState.EXPLORED
	_visible_indices.clear()
	visible_hostile_unit_ids.clear()
	visible_hostile_building_ids.clear()


func reveal(center: Vector2i, radius_cells: int) -> void:
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


func _index(cell: Vector2i) -> int:
	return cell.y * grid_size.x + cell.x
