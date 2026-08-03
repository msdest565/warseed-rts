class_name FactionKnowledgeSnapshot
extends RefCounted

var faction_id: int
var grid_size: Vector2i
var cells: PackedByteArray


func _init(knowledge: FactionKnowledge) -> void:
	faction_id = knowledge.faction_id
	grid_size = knowledge.grid_size
	cells = knowledge.cells.duplicate()


func get_cell_state(cell: Vector2i) -> FactionKnowledge.CellState:
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
		return FactionKnowledge.CellState.UNEXPLORED
	return cells[cell.y * grid_size.x + cell.x] as FactionKnowledge.CellState


func is_visible(cell: Vector2i) -> bool:
	return get_cell_state(cell) == FactionKnowledge.CellState.VISIBLE
