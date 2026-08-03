class_name TaskState
extends RefCounted

## Shared lifecycle for strategic and agent-owned work.
enum Lifecycle {
	WAITING,
	PREPARING,
	EXECUTING,
	PAUSED,
	BLOCKED,
	COMPLETED,
	FAILED,
	CANCELLED,
}

enum BlockedReason {
	NONE,
	INSUFFICIENT_RESOURCES,
	NO_AVAILABLE_UNITS,
	PATH_UNAVAILABLE,
	INSUFFICIENT_PARTICIPANTS,
	PARTICIPANT_OVERRIDDEN,
	INVALID_TARGET,
	PRODUCTION_UNAVAILABLE,
}

enum Kind {
	FORMATION_MOVE_TEST,
	DEVELOP_RESOURCE,
	DEFEND_AREA,
	ATTACK_TARGET,
}

enum Phase {
	PREPARING,
	HARVESTING,
	PRODUCING,
	MUSTERING,
	ADVANCING,
	HOLDING,
	ENGAGING,
	RETREATING,
	RETURNING,
	DONE,
}

var task_id: int
var agent_id: int
var parent_task_id: int = 0
var kind: Kind = Kind.FORMATION_MOVE_TEST
var phase: Phase = Phase.PREPARING
var lifecycle: Lifecycle = Lifecycle.WAITING
var blocked_reason: BlockedReason = BlockedReason.NONE
var blocked_detail: String = ""
var priority: int = 0
var target_position: Vector2
var target_entity_id: int = 0
var target_radius: float = 0.0
var formation_id: int = 0
var participant_entity_ids: Array[int] = []
var original_participant_entity_ids: Array[int] = []
var route: PackedVector2Array = PackedVector2Array()
var accepted_tick: int = -1
var last_transition_tick: int = 0
var progress_current: int = 0
var progress_target: int = 0
var baseline_value: int = 0
var expected_unit_count: int = 0
var last_detail: String = ""

func _init(new_task_id: int, new_agent_id: int, new_participants: Array[int] = []) -> void:
	task_id = new_task_id
	agent_id = new_agent_id
	participant_entity_ids.assign(new_participants)
	participant_entity_ids.sort()
	original_participant_entity_ids = participant_entity_ids.duplicate()

func set_lifecycle(new_lifecycle: Lifecycle, tick: int, reason: BlockedReason = BlockedReason.NONE, detail: String = "") -> void:
	lifecycle = new_lifecycle
	last_transition_tick = tick
	blocked_reason = reason
	blocked_detail = detail
	last_detail = detail

func set_phase(new_phase: Phase, tick: int, detail: String = "") -> void:
	phase = new_phase
	last_transition_tick = tick
	if not detail.is_empty():
		last_detail = detail

func has_participant(entity_id: int) -> bool:
	return participant_entity_ids.has(entity_id)

func remove_participant(entity_id: int) -> void:
	participant_entity_ids.erase(entity_id)

func add_participant(entity_id: int) -> void:
	if not participant_entity_ids.has(entity_id):
		participant_entity_ids.append(entity_id)
		participant_entity_ids.sort()
