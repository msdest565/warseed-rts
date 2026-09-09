class_name HighLevelIntentSnapshot
extends RefCounted

var intent_id: StringName
var commander_id: StringName
var commander_name_key: StringName
var objective_region_id: StringName
var axis_region_id: StringName
var posture: CommanderState.Posture
var reserve_policy: CommanderState.ReservePolicy
var accepted_tick: int
var task_ids: Array[int]


func _init(commander: CommanderSnapshot) -> void:
	intent_id = commander.active_intent_id
	commander_id = commander.definition_id
	commander_name_key = commander.display_name_key
	objective_region_id = commander.intent_objective_region_id
	axis_region_id = commander.intent_axis_region_id
	posture = commander.posture
	reserve_policy = commander.intent_reserve_policy
	accepted_tick = commander.intent_accepted_tick
	task_ids = commander.current_task_ids.duplicate()


func to_dictionary() -> Dictionary:
	return {
		"intent_id": String(intent_id),
		"commander_id": String(commander_id),
		"commander_name_key": String(commander_name_key),
		"objective_region_id": String(objective_region_id),
		"axis_region_id": String(axis_region_id),
		"posture": posture,
		"reserve_policy": reserve_policy,
		"accepted_tick": accepted_tick,
		"task_ids": task_ids.duplicate(),
	}
