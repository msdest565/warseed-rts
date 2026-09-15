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
var baseline_strength: int = 0


func is_satisfied() -> bool:
	return lifecycle in [Lifecycle.COMPLETED, Lifecycle.SKIPPED]


func duplicate_value() -> CommanderTaskNodeSnapshot:
	var result := CommanderTaskNodeSnapshot.new()
	result.node_id = node_id
	result.card_id = card_id
	result.commander_id = commander_id
	result.phase = phase
	result.lifecycle = lifecycle
	result.target_position = target_position
	result.timeout_ticks = timeout_ticks
	result.dwell_ticks = dwell_ticks
	result.arrival_radius = arrival_radius
	result.earliest_tick = earliest_tick
	result.started_tick = started_tick
	result.paused_tick = paused_tick
	result.paused_duration_ticks = paused_duration_ticks
	result.changed_tick = changed_tick
	result.progress_ticks = progress_ticks
	result.task_id = task_id
	result.reason_key = reason_key
	result.requires_deployment = requires_deployment
	result.supply_cost = supply_cost
	result.is_required = is_required
	result.baseline_strength = baseline_strength
	result.prerequisite_ids = prerequisite_ids.duplicate()
	result.route_points = route_points.duplicate()
	return result
