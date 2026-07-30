class_name MoveCommand
extends GameCommand

var target_position: Vector2


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_target_entity_id: int,
	new_target_position: Vector2
) -> void:
	super(
		new_command_id,
		new_issuer_id,
		new_issuer_kind,
		new_issued_tick,
		new_target_entity_id
	)
	target_position = new_target_position
