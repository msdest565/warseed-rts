class_name TestSimulationWorld
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_fixed_tick_movement(failures)
	_test_arrival_without_overshoot(failures)
	_test_snapshot_is_value_copy(failures)
	_test_deterministic_replay(failures)
	return failures


func _test_fixed_tick_movement(failures: Array[String]) -> void:
	var world := _moving_world(Vector2(700.0, 360.0))
	var before := world.create_snapshot().get_unit(1).position
	var after := world.advance_tick().get_unit(1).position
	_expect(is_equal_approx(after.distance_to(before), 18.0), "10 Hz tick should move exactly 18 pixels", failures)


func _test_arrival_without_overshoot(failures: Array[String]) -> void:
	var target := Vector2(325.0, 360.0)
	var world := _moving_world(target)
	var unit := world.advance_tick().get_unit(1)
	_expect(unit.position == target, "unit should stop exactly at close target", failures)
	_expect(not unit.is_moving, "unit should become idle on arrival", failures)


func _test_snapshot_is_value_copy(failures: Array[String]) -> void:
	var world := _moving_world(Vector2(700.0, 360.0))
	var old_snapshot := world.create_snapshot()
	var old_position := old_snapshot.get_unit(1).position
	world.advance_tick()
	_expect(old_snapshot.get_unit(1).position == old_position, "old snapshot must not mutate", failures)


func _test_deterministic_replay(failures: Array[String]) -> void:
	var first := _moving_world(Vector2(700.0, 500.0))
	var second := _moving_world(Vector2(700.0, 500.0))
	for index in range(20):
		var first_unit := first.advance_tick().get_unit(1)
		var second_unit := second.advance_tick().get_unit(1)
		_expect(first_unit.position == second_unit.position, "replay diverged at tick %d" % index, failures)


func _moving_world(target: Vector2) -> SimulationWorld:
	var world := SimulationWorld.new()
	var command := MoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, target)
	world.submit_command(command)
	return world


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
