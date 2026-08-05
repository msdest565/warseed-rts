class_name CancelProductionCommand
extends GameCommand

var queue_index: int


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_building_entity_id: int,
	new_queue_index: int = 0
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_building_entity_id)
	queue_index = new_queue_index
