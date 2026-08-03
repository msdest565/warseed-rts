class_name FormationSnapshot
extends RefCounted

var formation_id: int
var leader_entity_id: int
var member_entity_ids: Array[int]
var anchor_position: Vector2
var target_position: Vector2
var path: PackedVector2Array
var is_moving: bool
var mode: FormationState.MovementMode
var order_kind: FormationState.OrderKind
var engagement_state: FormationState.EngagementState
var order_destination: Vector2
var order_target_entity_id: int


func _init(formation: FormationState) -> void:
	formation_id = formation.formation_id
	leader_entity_id = formation.leader_entity_id
	member_entity_ids = formation.member_entity_ids.duplicate()
	anchor_position = formation.anchor_position
	target_position = formation.target_position
	path = formation.path.duplicate()
	if formation.is_moving and formation.path_index > 0:
		path = path.slice(formation.path_index - 1)
		path[0] = formation.anchor_position
	is_moving = formation.is_moving
	mode = formation.mode
	order_kind = formation.order_kind
	engagement_state = formation.engagement_state
	order_destination = formation.order_destination
	order_target_entity_id = formation.order_target_entity_id
