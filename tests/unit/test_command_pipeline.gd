class_name TestCommandPipeline
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_valid_command_waits_for_tick(failures)
	_test_rejections(failures)
	_test_player_and_agent_share_pipeline(failures)
	_test_formation_command_is_atomic(failures)
	_test_rapid_movement_commands_keep_latest_intent(failures)
	_test_stop_and_attack_move_commands(failures)
	_test_attack_command_validation_and_supersession(failures)
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
		var world := SimulationWorld.new(true, issuer_kind == GameCommand.IssuerKind.AGENT)
		_reveal_default_enemy(world)
		var command := MoveCommand.new(1, 1, issuer_kind, 0, 1, Vector2(500.0, 360.0))
		if issuer_kind == GameCommand.IssuerKind.AGENT:
			command.agent_id = SimulationWorld.TEST_AGENT_ID
			command.task_id = SimulationWorld.TEST_TASK_ID
		_expect(world.submit_command(command).is_accepted(), "player and agent commands should share validation", failures)
		_expect(world.command_queue.size() == 1, "accepted commands should share queue", failures)


func _test_formation_command_is_atomic(failures: Array[String]) -> void:
	for issuer_kind in [GameCommand.IssuerKind.PLAYER, GameCommand.IssuerKind.AGENT]:
		var world := SimulationWorld.new(true, issuer_kind == GameCommand.IssuerKind.AGENT)
		var command := FormationMoveCommand.new(1, 1, issuer_kind, 0, 1, 1, Vector2(800.0, 336.0))
		if issuer_kind == GameCommand.IssuerKind.AGENT:
			command.agent_id = SimulationWorld.TEST_AGENT_ID
			command.task_id = SimulationWorld.TEST_TASK_ID
		_expect(world.submit_command(command).is_accepted(), "player and agent formation commands should share validation", failures)
		_expect(world.command_queue.size() == 1, "formation movement should queue atomically", failures)
		_expect(world.create_snapshot().get_formation(1).is_moving == false, "formation command should wait for tick", failures)

	var controlled_world := SimulationWorld.new()
	(controlled_world.units[5] as UnitState).controller_id = 9
	var rejected := FormationMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, Vector2(800.0, 336.0))
	_expect(controlled_world.submit_command(rejected).reason == CommandValidationResult.Reason.NOT_CONTROLLER, "one uncontrolled member should reject whole formation", failures)
	_expect(controlled_world.command_queue.size() == 0, "rejected formation must not partially queue", failures)


func _test_rapid_movement_commands_keep_latest_intent(failures: Array[String]) -> void:
	var world := SimulationWorld.new(false)
	world.units[1] = UnitState.new(1, Vector2(320.0, 360.0), 180.0, 1)
	var first := MoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, Vector2(500.0, 360.0))
	var second := MoveCommand.new(2, 1, GameCommand.IssuerKind.PLAYER, 0, 1, Vector2(700.0, 360.0))
	_expect(world.submit_command(first).is_accepted(), "first rapid move should be accepted", failures)
	_expect(world.submit_command(second).is_accepted(), "second rapid move should be accepted", failures)
	_expect(world.command_queue.size() == 1, "rapid movement should coalesce before tick", failures)
	world.advance_tick()
	_expect((world.units[1] as UnitState).move_target == Vector2(700.0, 360.0), "latest rapid target should win", failures)


func _test_stop_and_attack_move_commands(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var attack_move := AttackMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, Vector2(800.0, 336.0))
	_expect(world.submit_command(attack_move).is_accepted(), "attack-move should share formation path validation", failures)
	world.advance_tick()
	_expect((world.units[3] as UnitState).is_attack_moving, "attack-move intent should enter authoritative combat unit state", failures)
	_expect(not (world.units[1] as UnitState).is_attack_moving, "attack-move should not interrupt the harvester role", failures)
	var stop := StopCommand.new(2, 1, GameCommand.IssuerKind.PLAYER, world.current_tick, 1, 1)
	_expect(world.submit_command(stop).is_accepted(), "formation stop should be accepted", failures)
	var before := (world.units[1] as UnitState).position
	world.advance_tick()
	_expect(not (world.formations[1] as FormationState).is_moving, "stop should cancel formation route atomically", failures)
	_expect(not (world.units[1] as UnitState).has_move_target, "stop should clear member movement", failures)
	_expect(not (world.units[1] as UnitState).is_attack_moving, "stop should clear attack-move intent", failures)
	_expect((world.units[1] as UnitState).position == before, "stop should take effect before movement phase", failures)


func _test_attack_command_validation_and_supersession(failures: Array[String]) -> void:
	for issuer_kind in [GameCommand.IssuerKind.PLAYER, GameCommand.IssuerKind.AGENT]:
		var world := SimulationWorld.new(true, issuer_kind == GameCommand.IssuerKind.AGENT)
		_reveal_default_enemy(world)
		var attack := AttackCommand.new(1, 1, issuer_kind, 0, 1, SimulationWorld.DEFAULT_ENEMY_UNIT_ID, 1)
		if issuer_kind == GameCommand.IssuerKind.AGENT:
			attack.agent_id = SimulationWorld.TEST_AGENT_ID
			attack.task_id = SimulationWorld.TEST_TASK_ID
		_expect(world.submit_command(attack).is_accepted(), "player and agent attack should share validation", failures)
		_expect(world.command_queue.size() == 1, "formation attack should queue atomically", failures)

	var friendly_world := SimulationWorld.new()
	var friendly := AttackCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 2, 1)
	_expect(friendly_world.submit_command(friendly).reason == CommandValidationResult.Reason.FRIENDLY_TARGET, "friendly attack target should be rejected structurally", failures)
	(friendly_world.units[5] as UnitState).controller_id = 9
	_reveal_default_enemy(friendly_world)
	var uncontrolled := AttackCommand.new(2, 1, GameCommand.IssuerKind.PLAYER, 0, 1, SimulationWorld.DEFAULT_ENEMY_UNIT_ID, 1)
	_expect(friendly_world.submit_command(uncontrolled).reason == CommandValidationResult.Reason.NOT_CONTROLLER, "one uncontrolled member should reject whole attack", failures)

	var supersession_world := SimulationWorld.new()
	_reveal_default_enemy(supersession_world)
	var attack := AttackCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, SimulationWorld.DEFAULT_ENEMY_UNIT_ID, 1)
	var stop := StopCommand.new(2, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1)
	_expect(supersession_world.submit_command(attack).is_accepted(), "attack before stop should be accepted", failures)
	_expect(supersession_world.submit_command(stop).is_accepted(), "stop after attack should be accepted", failures)
	_expect(supersession_world.command_queue.size() == 1, "stop should supersede pending attack for formation", failures)
	supersession_world.advance_tick()
	_expect((supersession_world.units[1] as UnitState).attack_target_entity_id == 0, "superseded attack must not apply", failures)


func _reveal_default_enemy(world: SimulationWorld) -> void:
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = (world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState).anchor_position + Vector2(128.0, 0.0)
	world._update_faction_knowledge()


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
