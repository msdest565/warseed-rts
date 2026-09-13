class_name CommanderTaskNodeSnapshot
extends RefCounted

enum Lifecycle { WAITING, ACTIVE, PAUSED, BLOCKED, COMPLETED, SKIPPED, FAILED, CANCELLED }

var node_id: StringName
var card_id: StringName
var commander_id: StringName
var phase: CommanderTaskStageDefinition.Phase
var lifecycle: Lifecycle = Lifecycle.WAITING
var prerequisite_ids: Array[StringName] = []
var target_position: Vector2
var route_points: PackedVector2Array = PackedVector2Array()
var timeout_ticks: int
var dwell_ticks: int
var arrival_radius: float
var earliest_tick: int
var started_tick: int = -1
var paused_tick: int = -1
var paused_duration_ticks: int = 0
var changed_tick: int = -1
var progress_ticks: int = 0
var task_id: int = 0
var reason_key: StringName = &"COMMANDER_GRAPH_WAITING"
var requires_deployment: bool = false
var supply_cost: int = 0
var is_required: bool = true


func is_satisfied() -> bool:
	return lifecycle in [Lifecycle.COMPLETED, Lifecycle.SKIPPED]


func duplicate_value() -> CommanderTaskNodeSnapshot:
	var result := CommanderTaskNodeSnapshot.new()
	for property in get_property_list():
		var key := StringName(property.name)
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result.set(key, get(key))
	result.prerequisite_ids = prerequisite_ids.duplicate()
	result.route_points = route_points.duplicate()
	return result
