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


func _init(new_faction_id: int, new_grid_size: Vector2i) -> void:
	faction_id = new_faction_id
	grid_size = new_grid_size
	cells.resize(grid_size.x * grid_size.y)
	cells.fill(CellState.UNEXPLORED)


func begin_update() -> void:
	for index in range(cells.size()):
		if cells[index] == CellState.VISIBLE:
			cells[index] = CellState.EXPLORED


func reveal(center: Vector2i, radius_cells: int) -> void:
	var radius_squared := radius_cells * radius_cells
	for y in range(maxi(0, center.y - radius_cells), mini(grid_size.y, center.y + radius_cells + 1)):
		for x in range(maxi(0, center.x - radius_cells), mini(grid_size.x, center.x + radius_cells + 1)):
			var offset := Vector2i(x, y) - center
			if offset.length_squared() <= radius_squared:
				cells[_index(Vector2i(x, y))] = CellState.VISIBLE


func get_cell_state(cell: Vector2i) -> CellState:
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
		return CellState.UNEXPLORED
	return cells[_index(cell)] as CellState


func is_visible(cell: Vector2i) -> bool:
	return get_cell_state(cell) == CellState.VISIBLE


func _index(cell: Vector2i) -> int:
	return cell.y * grid_size.x + cell.x
