class_name SimulationHost
extends Node

signal command_evaluated(result: CommandValidationResult)

const TICK_SECONDS := SimulationWorld.TICK_SECONDS

var world := SimulationWorld.new()
var previous_snapshot: WorldSnapshot
var current_snapshot: WorldSnapshot
var _accumulator: float = 0.0


func _ready() -> void:
	current_snapshot = world.create_snapshot()
	previous_snapshot = current_snapshot


func _process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= TICK_SECONDS:
		_accumulator -= TICK_SECONDS
		advance_tick()


func submit_command(command: GameCommand) -> CommandValidationResult:
	var result := world.submit_command(command)
	command_evaluated.emit(result)
	return result


func create_move_command(
	entity_id: int,
	target_position: Vector2,
	issuer_kind: GameCommand.IssuerKind = GameCommand.IssuerKind.PLAYER
) -> MoveCommand:
	return MoveCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		issuer_kind,
		world.current_tick,
		entity_id,
		target_position
	)


func advance_tick() -> WorldSnapshot:
	previous_snapshot = current_snapshot
	current_snapshot = world.advance_tick()
	return current_snapshot


func get_interpolation_alpha() -> float:
	return clampf(_accumulator / TICK_SECONDS, 0.0, 1.0)


func get_queue_size() -> int:
	return world.command_queue.size()
