class_name TestSimulationWorld
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_fixed_tick_movement(failures)
	_test_arrival_without_overshoot(failures)
	_test_snapshot_is_value_copy(failures)
	_test_deterministic_replay(failures)
	_test_default_formation_and_snapshot_copy(failures)
	_test_formation_member_snapshot_without_unit_path(failures)
	_test_stuck_detection_and_recovery(failures)
	_test_destroyed_unit_wreck_expires(failures)
	return failures


func _test_destroyed_unit_wreck_expires(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.enabled = false
	enemy.health = 0.0
	enemy.death_tick = world.current_tick
	for _tick in range(SimulationWorld.WRECK_LIFETIME_TICKS):
		world.advance_tick()
	_expect(world.units.has(enemy.entity_id), "destroyed unit should remain briefly as a wreck", failures)
	world.advance_tick()
	_expect(not world.units.has(enemy.entity_id), "expired unit wreck should be removed from authoritative state", failures)


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


func _test_default_formation_and_snapshot_copy(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var snapshot := world.create_snapshot()
	_expect(snapshot.units.size() == 5, "local snapshot should hide the distant enemy at match start", failures)
	_expect(world.create_true_state_snapshot().units.size() == 8, "true state should contain player formation plus enemy garrison, harvester, and engineer", failures)
	var old_mode := snapshot.get_formation(1).mode
	var old_slot := snapshot.get_unit(5).formation_slot_id
	var command := FormationMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, Vector2(800.0, 336.0))
	world.submit_command(command)
	for tick in range(20):
		world.advance_tick()
	_expect(snapshot.get_formation(1).mode == old_mode, "old formation snapshot must not mutate", failures)
	_expect(snapshot.get_unit(5).formation_slot_id == old_slot, "old unit slot snapshot must not mutate", failures)


func _test_stuck_detection_and_recovery(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var formation := world.formations[1] as FormationState
	formation.target_position = Vector2(800.0, 336.0)
	formation.path = world.pathfinder.find_path(formation.anchor_position, formation.target_position)
	formation.path_index = 1
	formation.is_moving = true
	var unit := world.units[5] as UnitState
	unit.position = Vector2(600.0, 90.0)
	unit.following_formation = true
	unit.has_move_target = true
	var system := world.formation_movement
	for tick in range(FormationMovementSystem.STUCK_TICK_LIMIT):
		system._update_stuck_state(unit, formation, unit.position, world.events, tick)
	var saw_stuck := false
	for event in world.events:
		if event.kind == SimulationEvent.Kind.UNIT_STUCK and event.entity_id == 5:
			saw_stuck = true
	_expect(saw_stuck, "no-progress unit should emit UNIT_STUCK at threshold", failures)
	_expect(unit.recovery_attempts == 1, "stuck unit should perform one bounded recovery attempt", failures)


func _test_formation_member_snapshot_without_unit_path(failures: Array[String]) -> void:
	var unit := UnitState.new(77, Vector2(320.0, 240.0), 180.0, SimulationWorld.LOCAL_PLAYER_ID)
	unit.formation_id = SimulationWorld.DEFAULT_FORMATION_ID
	unit.following_formation = true
	unit.has_move_target = true
	unit.path_index = 1
	unit.path = PackedVector2Array()
	var snapshot := UnitSnapshot.new(unit)
	_expect(snapshot.is_moving, "formation member should remain marked moving when its route is owned by the formation", failures)
	_expect(snapshot.path.is_empty(), "formation-owned movement should allow an empty per-unit snapshot path", failures)


func _moving_world(target: Vector2) -> SimulationWorld:
	var world := SimulationWorld.new(false)
	world.units[1] = UnitState.new(1, Vector2(320.0, 360.0), 180.0, 1)
	var command := MoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, target)
	world.submit_command(command)
	return world


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
