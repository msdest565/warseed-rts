class_name TestMapDefinition
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	var map: MapDefinition = load("res://data/maps/test_arena.tres")
	_expect(map != null, "expanded map definition should load", failures)
	if map == null:
		return failures
	_expect(map.grid_size == Vector2i(96, 64), "expanded map should be 96x64 cells", failures)
	_expect(map.get_world_rect() == Rect2(Vector2.ZERO, Vector2(3072.0, 2048.0)), "expanded world should be 3072x2048", failures)
	_expect(SimulationWorld.BATTLEFIELD_BOUNDS == map.get_world_rect(), "simulation bounds should match map definition", failures)
	var grid := LogicGrid.create_test_map()
	_expect(grid.is_in_bounds(map.player_spawn_cell) and not grid.is_blocked(map.player_spawn_cell), "player spawn should be valid and walkable", failures)
	_expect(grid.is_in_bounds(map.enemy_spawn_cell) and not grid.is_blocked(map.enemy_spawn_cell), "enemy spawn should be valid and walkable", failures)
	return failures


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
