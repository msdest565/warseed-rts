class_name AttackMoveCommand
extends FormationMoveCommand


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_leader_entity_id: int,
	new_formation_id: int,
	new_target_position: Vector2
) -> void:
	super(
		new_command_id,
		new_issuer_id,
		new_issuer_kind,
		new_issued_tick,
		new_leader_entity_id,
		new_formation_id,
		new_target_position
	)
