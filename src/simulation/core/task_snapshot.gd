class_name TaskSnapshot
extends RefCounted

var task_id: int
var agent_id: int
var parent_task_id: int
var kind: TaskState.Kind
var phase: TaskState.Phase
var lifecycle: TaskState.Lifecycle
var blocked_reason: TaskState.BlockedReason
var blocked_detail: String
var priority: int
var target_position: Vector2
var target_entity_id: int
var target_radius: float
var formation_id: int
var participant_entity_ids: Array[int]
var original_participant_entity_ids: Array[int]
var route: PackedVector2Array
var accepted_tick: int
var last_transition_tick: int
var progress_current: int
var progress_target: int
var last_detail: String

func _init(task: TaskState) -> void:
	task_id = task.task_id
	agent_id = task.agent_id
	parent_task_id = task.parent_task_id
	kind = task.kind
	phase = task.phase
	lifecycle = task.lifecycle
	blocked_reason = task.blocked_reason
	blocked_detail = task.blocked_detail
	priority = task.priority
	target_position = task.target_position
	target_entity_id = task.target_entity_id
	target_radius = task.target_radius
	formation_id = task.formation_id
	participant_entity_ids = task.participant_entity_ids.duplicate()
	original_participant_entity_ids = task.original_participant_entity_ids.duplicate()
	route = task.route.duplicate()
	accepted_tick = task.accepted_tick
	last_transition_tick = task.last_transition_tick
	progress_current = task.progress_current
	progress_target = task.progress_target
	last_detail = task.last_detail

func get_participant_count() -> int:
	return participant_entity_ids.size()
