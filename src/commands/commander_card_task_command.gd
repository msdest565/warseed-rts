class_name CommanderCardTaskCommand
extends GameCommand

enum Action { START, PROGRESS, RESET_PROGRESS, COMPLETE, SKIP, PAUSE, RESUME, BLOCK, FAIL, CANCEL, RETREAT, AUTO_RETREAT, REINFORCE, COMMIT_RESERVE, REPLAN }

var graph_id: StringName
var node_id: StringName
var action: Action
var target_card_id: StringName
var graph_revision: int = 0


func _init(id: int, faction: int, issuer: IssuerKind, tick: int, graph: StringName, node: StringName, requested_action: Action) -> void:
	super(id, faction, issuer, tick, 0)
	graph_id = graph
	node_id = node
	action = requested_action


func duplicate_value() -> CommanderCardTaskCommand:
	var result := CommanderCardTaskCommand.new(command_id, issuer_id, issuer_kind, issued_tick, graph_id, node_id, action)
	result.agent_id = agent_id
	result.task_id = task_id
	result.target_card_id = target_card_id
	result.graph_revision = graph_revision
	return result


func get_supersession_key() -> String:
	return "COMMANDER_GRAPH:%s:%s" % [graph_id, node_id]
