class_name ProduceUnitCommand
extends GameCommand

var unit_definition_id: StringName


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_factory_entity_id: int,
	new_unit_definition_id: StringName
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_factory_entity_id)
	unit_definition_id = new_unit_definition_id
