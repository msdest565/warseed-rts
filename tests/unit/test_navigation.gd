class_name TestNavigation
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_grid_conversion_and_static_obstacles(failures)
	_test_path_routes_through_wall_gap(failures)
	_test_blocked_destination_is_rejected(failures)
	_test_world_follows_path_without_crossing_wall(failures)
	_test_formation_degrades_through_gap(failures)
	_test_column_history_follows_turn(failures)
	_test_formation_routes_around_block_both_directions(failures)
	_test_path_cache_reuses_and_invalidates(failures)
	return failures


func _test_grid_conversion_and_static_obstacles(failures: Array[String]) -> void:
	var grid := LogicGrid.create_test_map()
	var cell := Vector2i(7, 5)
	_expect(grid.world_to_cell(grid.cell_to_world(cell)) == cell, "logic grid world conversion should round trip", failures)
	_expect(grid.is_blocked(Vector2i(11, 4)), "test map wall should block navigation cell", failures)
	_expect(not grid.is_blocked(Vector2i(11, 5)), "test map should retain narrow wall gap", failures)


func _test_path_routes_through_wall_gap(failures: Array[String]) -> void:
	var grid := LogicGrid.create_test_map()
	var pathfinder := GridPathfinder.new(grid)
	var start := grid.cell_to_world(Vector2i(5, 2))
	var destination := grid.cell_to_world(Vector2i(16, 2))
	var path := pathfinder.find_path(start, destination)
	_expect(not path.is_empty(), "pathfinder should find route across test map", failures)
	var uses_gap := false
	for point in path:
		if grid.world_to_cell(point) == Vector2i(11, 5):
			uses_gap = true
		_expect(not grid.is_blocked(grid.world_to_cell(point)), "path must not enter blocked cell", failures)
	_expect(uses_gap, "path should route through the only wall gap", failures)


func _test_blocked_destination_is_rejected(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var blocked_target := world.logic_grid.cell_to_world(Vector2i(11, 4))
	var command := MoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, blocked_target)
	var result := world.submit_command(command)
	_expect(result.reason == CommandValidationResult.Reason.PATH_UNAVAILABLE, "blocked destination should return PathUnavailable", failures)
	_expect(world.command_queue.size() == 0, "unavailable path must not enter command queue", failures)


func _test_world_follows_path_without_crossing_wall(failures: Array[String]) -> void:
	var world := SimulationWorld.new(false)
	var start := world.logic_grid.cell_to_world(Vector2i(5, 2))
	var destination := world.logic_grid.cell_to_world(Vector2i(16, 2))
	world.units[1] = UnitState.new(1, start, 180.0, 1)
	var command := MoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, destination)
	_expect(world.submit_command(command).is_accepted(), "reachable navigation command should be accepted", failures)
	for tick in range(100):
		var unit := world.advance_tick().get_unit(1)
		_expect(not world.logic_grid.is_blocked(world.logic_grid.world_to_cell(unit.position)), "moving unit should remain in walkable cells at tick %d" % tick, failures)
		if not unit.is_moving:
			break
	var final_unit := world.create_snapshot().get_unit(1)
	_expect(final_unit.position.is_equal_approx(destination), "unit should arrive after following grid path", failures)


func _test_formation_degrades_through_gap(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var blocked_before := world.logic_grid.get_blocked_cells()
	var slot_ids: Dictionary = {}
	for unit in world.create_snapshot().units:
		slot_ids[unit.entity_id] = unit.formation_slot_id
	var command := FormationMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, Vector2(800.0, 336.0))
	_expect(world.submit_command(command).is_accepted(), "formation route through gap should be accepted", failures)
	var saw_column := false
	var saw_wide_after_column := false
	var completed := false
	for tick in range(300):
		var snapshot := world.advance_tick()
		var formation := snapshot.get_formation(1)
		if formation.mode == FormationState.MovementMode.COLUMN:
			saw_column = true
		elif saw_column:
			saw_wide_after_column = true
		for unit in snapshot.units:
			_expect(world.logic_grid.is_world_position_walkable(unit.position), "formation member should remain walkable at tick %d" % tick, failures)
			_expect(unit.formation_slot_id == slot_ids[unit.entity_id], "formation slot should remain stable", failures)
		if not formation.is_moving:
			completed = true
			break
	_expect(saw_column, "formation should degrade to column before narrow gap", failures)
	_expect(saw_wide_after_column, "formation should restore wide mode after gap", failures)
	_expect(completed, "all formation members should arrive", failures)
	_expect(world.logic_grid.get_blocked_cells() == blocked_before, "dynamic units must not mutate static grid", failures)


func _test_column_history_follows_turn(failures: Array[String]) -> void:
	var formation := FormationState.new(1, [1, 2, 3, 4, 5], Vector2(100.0, 100.0))
	formation.reset_anchor_history(Vector2.RIGHT)
	formation.append_anchor_history(Vector2(200.0, 100.0), 300.0)
	formation.append_anchor_history(Vector2(200.0, 200.0), 300.0)
	_expect(formation.sample_anchor_history(50.0).is_equal_approx(Vector2(200.0, 150.0)), "column history should sample current turn leg", failures)
	_expect(formation.sample_anchor_history(150.0).is_equal_approx(Vector2(150.0, 100.0)), "column history should follow prior leg instead of cutting corner", failures)


func _test_formation_routes_around_block_both_directions(failures: Array[String]) -> void:
	_run_block_route(Vector2i(24, 6), Vector2i(14, 6), "right-to-left", failures)


func _run_block_route(
	start_cell: Vector2i,
	target_cell: Vector2i,
	label: String,
	failures: Array[String]
) -> void:
	var world := SimulationWorld.new()
	var formation := world.formations[1] as FormationState
	formation.anchor_position = world.logic_grid.cell_to_world(start_cell)
	formation.target_position = formation.anchor_position
	for entity_id in formation.member_entity_ids:
		var unit := world.units[entity_id] as UnitState
		unit.position = formation.anchor_position + formation.get_wide_offset(unit.formation_slot_id)
		unit.desired_position = unit.position
	var target := world.logic_grid.cell_to_world(target_cell)
	var command := FormationMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, target)
	_expect(world.submit_command(command).is_accepted(), "%s obstacle route should be accepted" % label, failures)
	var completed := false
	for tick in range(500):
		var snapshot := world.advance_tick()
		var formation_snapshot := snapshot.get_formation(1)
		for unit in snapshot.units:
			_expect(world.logic_grid.is_world_position_walkable(unit.position), "%s unit position should remain walkable at tick %d" % [label, tick], failures)
			if formation_snapshot.mode == FormationState.MovementMode.COLUMN:
				_expect(world.logic_grid.is_world_position_walkable(unit.desired_position), "%s column desired position should remain walkable at tick %d" % [label, tick], failures)
		if not formation_snapshot.is_moving:
			completed = true
			break
	_expect(completed, "%s formation should not deadlock around 2x2 obstacle" % label, failures)


func _test_path_cache_reuses_and_invalidates(failures: Array[String]) -> void:
	var grid := LogicGrid.create_test_map()
	var pathfinder := GridPathfinder.new(grid)
	var start := grid.cell_to_world(Vector2i(5, 5))
	var target := grid.cell_to_world(Vector2i(8, 5))
	var first := pathfinder.find_path(start, target)
	var second := pathfinder.find_path(start + Vector2(2.0, 2.0), target + Vector2(2.0, 2.0))
	_expect(not first.is_empty() and not second.is_empty(), "path cache should preserve reachable routes", failures)
	grid.set_blocked(Vector2i(6, 5), true)
	var invalidated := pathfinder.find_path(start, grid.cell_to_world(Vector2i(7, 5)))
	var avoids_new_block := true
	for point in invalidated:
		if grid.world_to_cell(point) == Vector2i(6, 5):
			avoids_new_block = false
	_expect(avoids_new_block, "path cache should invalidate after grid revision", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
