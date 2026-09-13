class_name CommanderTaskGraphSnapshot
extends RefCounted

var graph_id: StringName
var faction_id: int
var approved_plan: StaffCourseOfAction
var created_tick: int
var retreat_requested: bool = false
var nodes: Array[CommanderTaskNodeSnapshot] = []
var reserve_card_ids: Array[StringName] = []


func get_node(id: StringName) -> CommanderTaskNodeSnapshot:
	for node in nodes:
		if node.node_id == id:
			return node
	return null


func dependencies_satisfied(node: CommanderTaskNodeSnapshot) -> bool:
	for id in node.prerequisite_ids:
		var prerequisite := get_node(id)
		if prerequisite == null or not prerequisite.is_satisfied():
			return false
	return true


func duplicate_value() -> CommanderTaskGraphSnapshot:
	var result := CommanderTaskGraphSnapshot.new()
	result.graph_id = graph_id
	result.faction_id = faction_id
	result.approved_plan = approved_plan.duplicate_value() if approved_plan != null else null
	result.created_tick = created_tick
	result.retreat_requested = retreat_requested
	result.reserve_card_ids = reserve_card_ids.duplicate()
	for node in nodes:
		result.nodes.append(node.duplicate_value())
	return result
