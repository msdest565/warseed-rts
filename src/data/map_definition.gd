class_name MapDefinition
extends Resource

@export var definition_id: StringName = &"test_arena"
@export var cell_size: float = 32.0
@export var grid_size: Vector2i = Vector2i(96, 64)
@export var world_origin: Vector2 = Vector2.ZERO
@export var player_spawn_cell: Vector2i = Vector2i(10, 10)
@export var enemy_spawn_cell: Vector2i = Vector2i(86, 32)
@export var camera_start_cell: Vector2i = Vector2i(12, 10)


func get_world_rect() -> Rect2:
	return Rect2(world_origin, Vector2(grid_size) * cell_size)


func cell_to_world(cell: Vector2i) -> Vector2:
	return world_origin + Vector2(cell) * cell_size + Vector2.ONE * cell_size * 0.5
