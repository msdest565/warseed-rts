class_name UnitDispositionCommand
extends GameCommand

enum Disposition {
	RETURN,
	STAY,
	JOIN,
	MANUAL,
}

var disposition: Disposition
var destination_formation_id: int

func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_target_entity_id: int,
	new_disposition: Disposition,
	new_destination_formation_id: int = 0
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_target_entity_id)
	disposition = new_disposition
	destination_formation_id = new_destination_formation_id

func get_supersession_key() -> String:
	return "U%d" % target_entity_id
