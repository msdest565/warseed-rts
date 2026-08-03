class_name CommandQueue
extends RefCounted

var _commands: Array[GameCommand] = []


func enqueue(command: GameCommand) -> void:
	if _is_unit_order(command):
		var supersession_key := command.get_supersession_key()
		for index in range(_commands.size() - 1, -1, -1):
			var queued := _commands[index]
			if not _is_unit_order(queued) or queued.get_supersession_key() != supersession_key:
				continue
			if queued.get_priority() > command.get_priority():
				return
			_commands.remove_at(index)
			break
	_commands.append(command)


func drain() -> Array[GameCommand]:
	_commands.sort_custom(_comes_before)
	var drained := _commands.duplicate()
	_commands.clear()
	return drained


func size() -> int:
	return _commands.size()


func _is_unit_order(command: GameCommand) -> bool:
	return command is MoveCommand or command is FormationMoveCommand or command is StopCommand or command is AttackCommand or command is HarvestCommand or command is ProduceUnitCommand or command is UnitDispositionCommand or command is StrategicOrderCommand or command is TaskControlCommand


func _comes_before(left: GameCommand, right: GameCommand) -> bool:
	if left.issued_tick == right.issued_tick:
		if left.get_priority() == right.get_priority():
			return left.command_id < right.command_id
		return left.get_priority() < right.get_priority()
	return left.issued_tick < right.issued_tick
