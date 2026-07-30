class_name SimulationWorld
extends RefCounted

const TICK_SECONDS := 0.1
const BATTLEFIELD_BOUNDS := Rect2(48.0, 72.0, 1184.0, 600.0)
const INITIAL_UNIT_ID := 1
const LOCAL_PLAYER_ID := 1

var current_tick: int = 0
var units: Dictionary = {}
var command_queue := CommandQueue.new()
var command_validator := CommandValidator.new()
var events: Array[SimulationEvent] = []
var _next_command_id: int = 1


func _init(create_default_unit: bool = true) -> void:
	if create_default_unit:
		units[INITIAL_UNIT_ID] = UnitState.new(
			INITIAL_UNIT_ID,
			Vector2(320.0, 360.0),
			180.0,
			LOCAL_PLAYER_ID
		)


func allocate_command_id() -> int:
	var allocated := _next_command_id
	_next_command_id += 1
	return allocated


func submit_command(command: GameCommand) -> CommandValidationResult:
	var result := command_validator.validate(command, units, BATTLEFIELD_BOUNDS)
	var event_kind := SimulationEvent.Kind.COMMAND_REJECTED
	if result.is_accepted():
		command_queue.enqueue(command)
		event_kind = SimulationEvent.Kind.COMMAND_ACCEPTED
	events.append(SimulationEvent.new(current_tick, event_kind, command.target_entity_id, result.describe()))
	return result


func advance_tick() -> WorldSnapshot:
	for command in command_queue.drain():
		_apply_command(command)
	for unit_variant in units.values():
		_advance_unit(unit_variant as UnitState)
	current_tick += 1
	return create_snapshot()


func create_snapshot() -> WorldSnapshot:
	var snapshots: Array[UnitSnapshot] = []
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		snapshots.append(UnitSnapshot.new(units[entity_id] as UnitState))
	return WorldSnapshot.new(current_tick, snapshots)


func _apply_command(command: GameCommand) -> void:
	if command is MoveCommand:
		var unit: UnitState = units[command.target_entity_id]
		unit.move_target = (command as MoveCommand).target_position
		unit.has_move_target = not unit.position.is_equal_approx(unit.move_target)


func _advance_unit(unit: UnitState) -> void:
	if not unit.enabled or not unit.has_move_target:
		return
	var offset := unit.move_target - unit.position
	var travel := unit.move_speed * TICK_SECONDS
	if offset.length() <= travel:
		unit.position = unit.move_target
		unit.has_move_target = false
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_ARRIVED, unit.entity_id))
		return
	unit.position += offset.normalized() * travel
