class_name TaskControlCommand
extends GameCommand

enum Action {
	PAUSE,
	RESUME,
	CANCEL,
}

var controlled_task_id: int
var action: Action


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issued_tick: int,
	new_task_id: int,
	new_action: Action
) -> void:
	super(new_command_id, new_issuer_id, IssuerKind.PLAYER, new_issued_tick, new_task_id)
	controlled_task_id = new_task_id
	action = new_action


func get_supersession_key() -> String:
	return "TASK_%d" % controlled_task_id
