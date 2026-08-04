class_name FormationMoveCommand
extends GameCommand

var formation_id: int
var target_position: Vector2


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_leader_entity_id: int,
	new_formation_id: int,
	new_target_position: Vector2
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_leader_entity_id)
	formation_id = new_formation_id
	target_position = new_target_position


func get_supersession_key() -> String:
	if formation_id == 0:
		return super()
	return "F%d" % formation_id
