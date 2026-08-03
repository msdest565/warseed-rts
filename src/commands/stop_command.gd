class_name StopCommand
extends GameCommand

var formation_id: int


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_target_entity_id: int,
	new_formation_id: int = 0
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_target_entity_id)
	formation_id = new_formation_id


func get_supersession_key() -> String:
	return "F%d" % formation_id if formation_id != 0 else super()
