class_name CommanderTaskGraphSnapshot
extends RefCounted

var graph_id: StringName
var faction_id: int
var approved_plan: StaffCourseOfAction
var created_tick: int
var retreat_requested: bool = false
var nodes: Array[CommanderTaskNodeSnapshot] = []
var reserve_card_ids: Array[StringName] = []
var adaptation_policy: CommanderAdaptationPolicy = CommanderAdaptationPolicy.new()
var adaptation_budget_remaining: int = 0
var revision: int = 0
var next_adaptation_tick: int = 0
var reserve_commits: int = 0
var reinforcement_requests: int = 0
var replan_count: int = 0
var retreat_replan_count: int = 0
var reinforcement_supply_cost: int = 0
var last_adaptation_reason: StringName
var retreat_reason_key: StringName = &"COMMANDER_GRAPH_PLAYER_RETREAT"


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
	result.adaptation_policy = adaptation_policy.duplicate(true) as CommanderAdaptationPolicy
	result.adaptation_budget_remaining = adaptation_budget_remaining
	result.revision = revision
	result.next_adaptation_tick = next_adaptation_tick
	result.reserve_commits = reserve_commits
	result.reinforcement_requests = reinforcement_requests
	result.replan_count = replan_count
	result.retreat_replan_count = retreat_replan_count
	result.reinforcement_supply_cost = reinforcement_supply_cost
	result.last_adaptation_reason = last_adaptation_reason
	result.retreat_reason_key = retreat_reason_key
	for node in nodes:
		result.nodes.append(node.duplicate_value())
	return result
