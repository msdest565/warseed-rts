class_name TestMapDefinition
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	var map: MapDefinition = load("res://data/maps/test_arena.tres")
	_expect(map != null, "expanded map definition should load", failures)
	if map == null:
		return failures
	_expect(map.grid_size == Vector2i(192, 128), "large theater should be 192x128 cells", failures)
	_expect(map.get_world_rect() == Rect2(Vector2.ZERO, Vector2(6144.0, 4096.0)), "large theater should be 6144x4096", failures)
	_expect(map.get_world_rect().get_area() >= 3072.0 * 2048.0 * 4.0, "large theater should provide at least four times the previous playable area", failures)
	_expect(SimulationWorld.BATTLEFIELD_BOUNDS == map.get_world_rect(), "simulation bounds should match map definition", failures)
	_expect(CameraController.WORLD_RECT == map.get_world_rect() and MinimapControl.WORLD_RECT == map.get_world_rect(), "camera and minimap should use the authoritative expanded bounds", failures)
	var grid := LogicGrid.create_test_map()
	_expect(grid.is_in_bounds(map.player_spawn_cell) and not grid.is_blocked(map.player_spawn_cell), "player spawn should be valid and walkable", failures)
	_expect(grid.is_in_bounds(map.enemy_spawn_cell) and not grid.is_blocked(map.enemy_spawn_cell), "enemy spawn should be valid and walkable", failures)
	var pathfinder := GridPathfinder.new(grid)
	var headquarters_route := pathfinder.find_path(Vector2(3072.0, 3536.0), Vector2(3072.0, 272.0))
	_expect(not headquarters_route.is_empty(), "expanded north-south headquarters corridor should remain connected", failures)
	var theater_route := pathfinder.find_path(SimulationWorld.GREY_RIDGE_WEST_POSITION, SimulationWorld.GREY_RIDGE_EAST_POSITION)
	_expect(not theater_route.is_empty(), "expanded east-west theater should remain connected through its central choke", failures)
	for region_position in [SimulationWorld.GREY_RIDGE_WEST_POSITION, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, SimulationWorld.GREY_RIDGE_EAST_POSITION]:
		_expect(map.get_world_rect().has_point(region_position) and grid.is_world_position_walkable(region_position), "every expanded Grey Ridge strategic region should be in bounds and walkable", failures)
	return failures


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
