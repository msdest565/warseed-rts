class_name SetRallyPointCommand
extends GameCommand

var rally_position: Vector2


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_building_entity_id: int,
	new_rally_position: Vector2
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_building_entity_id)
	rally_position = new_rally_position
