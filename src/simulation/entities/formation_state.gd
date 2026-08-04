class_name FormationState
extends RefCounted

enum MovementMode {
	WIDE,
	COLUMN,
}

enum OrderKind {
	IDLE,
	MOVE,
	ATTACK_TARGET,
	ATTACK_MOVE,
}

enum EngagementState {
	NONE,
	PURSUING,
	ENGAGING,
}

const SLOT_OFFSETS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(-48.0, -44.0),
	Vector2(-48.0, 44.0),
	Vector2(-96.0, -44.0),
	Vector2(-96.0, 44.0),
]

var formation_id: int
var leader_entity_id: int
var member_entity_ids: Array[int]
var slot_by_entity_id: Dictionary = {}
var anchor_position: Vector2
var target_position: Vector2
var path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var is_moving: bool = false
var mode: MovementMode = MovementMode.WIDE
var clear_corridor_ticks: int = 0
var forced_column_ticks: int = 0
var anchor_history: PackedVector2Array = PackedVector2Array()
var initial_path_direction: Vector2 = Vector2.RIGHT
var order_kind: OrderKind = OrderKind.IDLE
var engagement_state: EngagementState = EngagementState.NONE
var order_destination: Vector2
var order_target_entity_id: int = 0
var pursuit_target_cell: Vector2i = Vector2i(-1, -1)


func _init(new_formation_id: int, new_member_entity_ids: Array[int], new_anchor_position: Vector2) -> void:
	formation_id = new_formation_id
	member_entity_ids = new_member_entity_ids.duplicate()
	member_entity_ids.sort()
	leader_entity_id = member_entity_ids[0]
	anchor_position = new_anchor_position
	target_position = new_anchor_position
	order_destination = new_anchor_position
	for slot_id in range(member_entity_ids.size()):
		slot_by_entity_id[member_entity_ids[slot_id]] = slot_id


func remove_member(entity_id: int) -> void:
	member_entity_ids.erase(entity_id)
	rebuild_slots()


func add_member(entity_id: int) -> int:
	if not member_entity_ids.has(entity_id):
		member_entity_ids.append(entity_id)
	rebuild_slots()
	return get_slot_id(entity_id)


func rebuild_slots() -> void:
	member_entity_ids.sort()
	slot_by_entity_id.clear()
	for slot_id in range(member_entity_ids.size()):
		slot_by_entity_id[member_entity_ids[slot_id]] = slot_id
	leader_entity_id = member_entity_ids[0] if not member_entity_ids.is_empty() else 0


func get_slot_id(entity_id: int) -> int:
	return int(slot_by_entity_id.get(entity_id, -1))


func get_wide_offset(slot_id: int) -> Vector2:
	if slot_id < 0:
		return Vector2.ZERO
	if slot_id < SLOT_OFFSETS.size():
		return SLOT_OFFSETS[slot_id]
	var reinforcement_index := slot_id - SLOT_OFFSETS.size()
	var rank := reinforcement_index / 2 + 3
	var side := -1.0 if reinforcement_index % 2 == 0 else 1.0
	return Vector2(-48.0 * rank, 44.0 * side)


func reset_anchor_history(path_direction: Vector2) -> void:
	anchor_history = PackedVector2Array([anchor_position])
	if not path_direction.is_zero_approx():
		initial_path_direction = path_direction.normalized()


func append_anchor_history(position: Vector2, retained_distance: float) -> void:
	if anchor_history.is_empty():
		anchor_history.append(position)
	elif not anchor_history[-1].is_equal_approx(position):
		anchor_history.append(position)
	_prune_anchor_history(retained_distance)


func sample_anchor_history(distance_behind: float) -> Vector2:
	if anchor_history.is_empty():
		return anchor_position - initial_path_direction * distance_behind
	var remaining := distance_behind
	for index in range(anchor_history.size() - 1, 0, -1):
		var newer := anchor_history[index]
		var older := anchor_history[index - 1]
		var segment_length := newer.distance_to(older)
		if segment_length >= remaining:
			return newer.lerp(older, remaining / segment_length) if segment_length > 0.0 else newer
		remaining -= segment_length
	return anchor_history[0] - initial_path_direction * remaining


func _prune_anchor_history(retained_distance: float) -> void:
	while anchor_history.size() > 2:
		var total_distance := 0.0
		for index in range(anchor_history.size() - 1, 0, -1):
			total_distance += anchor_history[index].distance_to(anchor_history[index - 1])
		if total_distance <= retained_distance:
			return
		var first_segment := anchor_history[0].distance_to(anchor_history[1])
		if total_distance - first_segment < retained_distance:
			return
		anchor_history.remove_at(0)
