class_name TestCommandPipeline
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_valid_command_waits_for_tick(failures)
	_test_rejections(failures)
	_test_player_and_agent_share_pipeline(failures)
	return failures


func _test_valid_command_waits_for_tick(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var before := world.create_snapshot().get_unit(1).position
	var command := MoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, Vector2(500.0, 360.0))
	var result := world.submit_command(command)
	_expect(result.is_accepted(), "valid move command should be accepted", failures)
	_expect(world.create_snapshot().get_unit(1).position == before, "command must wait for tick boundary", failures)
	world.advance_tick()
	_expect(world.create_snapshot().get_unit(1).position.x > before.x, "unit should move on next tick", failures)


func _test_rejections(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var unknown := MoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 99, Vector2(500.0, 360.0))
	_expect(
		world.submit_command(unknown).reason == CommandValidationResult.Reason.INVALID_TARGET,
		"unknown entity should be rejected",
		failures
	)
	var wrong_controller := MoveCommand.new(2, 9, GameCommand.IssuerKind.PLAYER, 0, 1, Vector2(500.0, 360.0))
	_expect(
		world.submit_command(wrong_controller).reason == CommandValidationResult.Reason.NOT_CONTROLLER,
		"wrong controller should be rejected",
		failures
	)
	var outside := MoveCommand.new(3, 1, GameCommand.IssuerKind.PLAYER, 0, 1, Vector2(-10.0, -10.0))
	_expect(
		world.submit_command(outside).reason == CommandValidationResult.Reason.INVALID_POSITION,
		"out-of-bounds target should be rejected",
		failures
	)
	(world.units[1] as UnitState).enabled = false
	var disabled := MoveCommand.new(4, 1, GameCommand.IssuerKind.PLAYER, 0, 1, Vector2(500.0, 360.0))
	_expect(
		world.submit_command(disabled).reason == CommandValidationResult.Reason.ENTITY_DISABLED,
		"disabled entity should be rejected",
		failures
	)


func _test_player_and_agent_share_pipeline(failures: Array[String]) -> void:
	for issuer_kind in [GameCommand.IssuerKind.PLAYER, GameCommand.IssuerKind.AGENT]:
		var world := SimulationWorld.new()
		var command := MoveCommand.new(1, 1, issuer_kind, 0, 1, Vector2(500.0, 360.0))
		_expect(world.submit_command(command).is_accepted(), "player and agent commands should share validation", failures)
		_expect(world.command_queue.size() == 1, "accepted commands should share queue", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
