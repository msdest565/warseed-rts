class_name CommandQueue
extends RefCounted

var _commands: Array[GameCommand] = []


func enqueue(command: GameCommand) -> void:
	_commands.append(command)


func drain() -> Array[GameCommand]:
	_commands.sort_custom(_comes_before)
	var drained := _commands.duplicate()
	_commands.clear()
	return drained


func size() -> int:
	return _commands.size()


func _comes_before(left: GameCommand, right: GameCommand) -> bool:
	if left.issued_tick == right.issued_tick:
		return left.command_id < right.command_id
	return left.issued_tick < right.issued_tick
