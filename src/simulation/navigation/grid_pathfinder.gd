class_name GridPathfinder
extends RefCounted

var logic_grid: LogicGrid
var metrics: SimulationMetrics
var _astar := AStarGrid2D.new()
var _cache: Dictionary = {}
var _cache_revision: int = -1


func _init(new_logic_grid: LogicGrid, new_metrics: SimulationMetrics = null) -> void:
	logic_grid = new_logic_grid
	metrics = new_metrics
	_astar.region = Rect2i(Vector2i.ZERO, LogicGrid.GRID_SIZE)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for cell in logic_grid.get_blocked_cells():
		_astar.set_point_solid(cell, true)


func find_path(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	if _cache_revision != logic_grid.revision:
		_cache.clear()
		_cache_revision = logic_grid.revision
		_astar.update()
		for cell in logic_grid.get_blocked_cells():
			_astar.set_point_solid(cell, true)
	var key := "%s:%s:%d" % [logic_grid.world_to_cell(from_position), logic_grid.world_to_cell(to_position), logic_grid.revision]
	if _cache.has(key):
		var cached := _cache[key] as PackedVector2Array
		var cached_copy := cached.duplicate()
		if cached_copy.size() > 0:
			cached_copy[0] = from_position
			cached_copy[cached_copy.size() - 1] = to_position
		if metrics != null:
			metrics.record_path_result(not cached_copy.is_empty())
		return cached_copy
	var path := _find_path_internal(from_position, to_position)
	_cache[key] = path.duplicate()
	if metrics != null:
		metrics.record_path_result(not path.is_empty())
	return path


func _find_path_internal(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var start_cell := logic_grid.world_to_cell(from_position)
	var end_cell := logic_grid.world_to_cell(to_position)
	if not logic_grid.is_in_bounds(start_cell) or not logic_grid.is_in_bounds(end_cell):
		return PackedVector2Array()
	if logic_grid.is_blocked(start_cell) or logic_grid.is_blocked(end_cell):
		return PackedVector2Array()
	if start_cell == end_cell:
		return PackedVector2Array([from_position, to_position]) if not from_position.is_equal_approx(to_position) else PackedVector2Array([from_position])
	var cell_path := _astar.get_id_path(start_cell, end_cell)
	if cell_path.is_empty():
		return PackedVector2Array()
	var world_path := PackedVector2Array()
	for cell in cell_path:
		world_path.append(logic_grid.cell_to_world(cell))
	world_path[0] = from_position
	world_path[world_path.size() - 1] = to_position
	return _simplify_path(world_path)


func _simplify_path(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() <= 2:
		return path
	var simplified := PackedVector2Array([path[0]])
	var anchor_index := 0
	while anchor_index < path.size() - 1:
		var next_index := path.size() - 1
		while next_index > anchor_index + 1 and not logic_grid.is_segment_walkable(path[anchor_index], path[next_index]):
			next_index -= 1
		simplified.append(path[next_index])
		anchor_index = next_index
	return simplified


func find_path_to_first_reachable(
	from_position: Vector2,
	preferred_position: Vector2,
	fallback_positions: PackedVector2Array
) -> PackedVector2Array:
	var candidates := PackedVector2Array([preferred_position])
	candidates.append_array(fallback_positions)
	for candidate in candidates:
		if not logic_grid.is_world_position_walkable(candidate):
			continue
		var candidate_path := find_path(from_position, candidate)
		if not candidate_path.is_empty():
			return candidate_path
	return PackedVector2Array()
