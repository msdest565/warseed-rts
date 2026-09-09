class_name FormationMoveCommand
extends GameCommand

var formation_id: int
var target_position: Vector2
var route_points: PackedVector2Array = PackedVector2Array()
var deployment_line_start: Vector2
var deployment_line_end: Vector2
var has_deployment_line: bool = false


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_leader_entity_id: int,
	new_formation_id: int,
	new_target_position: Vector2,
	new_route_points: PackedVector2Array = PackedVector2Array(),
	new_deployment_line_start: Vector2 = Vector2.ZERO,
	new_deployment_line_end: Vector2 = Vector2.ZERO,
	new_has_deployment_line: bool = false
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_leader_entity_id)
	formation_id = new_formation_id
	target_position = new_target_position
	route_points = new_route_points.duplicate()
	deployment_line_start = new_deployment_line_start
	deployment_line_end = new_deployment_line_end
	has_deployment_line = new_has_deployment_line


func get_supersession_key() -> String:
	if formation_id == 0:
		return super()
	return "F%d" % formation_id
