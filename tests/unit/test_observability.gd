class_name TestObservability
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_deterministic_metrics_and_snapshot_copy(failures)
	_test_host_timing_is_separate(failures)
	return failures


func _test_deterministic_metrics_and_snapshot_copy(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var initial := world.create_snapshot().metrics
	var accepted := FormationMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, Vector2(800.0, 336.0))
	var rejected := MoveCommand.new(2, 1, GameCommand.IssuerKind.PLAYER, 0, 99, Vector2(500.0, 360.0))
	world.submit_command(accepted)
	world.submit_command(rejected)
	var before_tick := world.create_snapshot().metrics
	_expect(before_tick.commands_submitted_total == 2, "metrics should count all submitted commands", failures)
	_expect(before_tick.get_command_count(CommandValidationResult.Status.ACCEPTED) == 1, "metrics should count accepted commands", failures)
	_expect(before_tick.get_command_count(CommandValidationResult.Status.REJECTED) == 1, "metrics should count rejected commands", failures)
	_expect(before_tick.commands_applied_total == 0, "commands should count applied only at tick boundary", failures)
	world.advance_tick()
	var after_tick := world.create_snapshot().metrics
	_expect(after_tick.commands_applied_total == 1, "accepted command should count as applied after drain", failures)
	_expect(after_tick.path_requests_total >= 2, "validation and application path calls should be observable", failures)
	_expect(after_tick.events_emitted_total == 2, "accepted and rejected command events should count once", failures)
	_expect(initial.commands_submitted_total == 0, "old metrics snapshot must remain immutable", failures)

	var replay := SimulationWorld.new()
	replay.submit_command(FormationMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, Vector2(800.0, 336.0)))
	replay.submit_command(MoveCommand.new(2, 1, GameCommand.IssuerKind.PLAYER, 0, 99, Vector2(500.0, 360.0)))
	replay.advance_tick()
	var replay_metrics := replay.create_snapshot().metrics
	_expect(replay_metrics.commands_submitted_total == after_tick.commands_submitted_total, "metric replay should preserve command totals", failures)
	_expect(replay_metrics.path_requests_total == after_tick.path_requests_total, "metric replay should preserve path totals", failures)
	_expect(replay_metrics.events_emitted_total == after_tick.events_emitted_total, "metric replay should preserve event totals", failures)


func _test_host_timing_is_separate(failures: Array[String]) -> void:
	var host := SimulationHost.new()
	Engine.get_main_loop().root.add_child(host)
	host._ready()
	host._process(0.25)
	var timing := host.get_tick_timing_snapshot()
	_expect(timing.sample_count == 2, "host should record one timing sample per fixed tick", failures)
	_expect(timing.last_usec >= 0 and timing.average_usec >= 0.0, "host timing should be non-negative", failures)
	_expect(timing.max_usec >= timing.last_usec, "host max timing should include last sample", failures)
	_expect(not "last_tick_usec" in host.current_snapshot, "wall-clock timing must not enter authoritative snapshot", failures)
	host.free()


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
