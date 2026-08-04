class_name RepairBuildingCommand
extends GameCommand

var building_entity_id: int


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_engineer_entity_id: int,
	new_building_entity_id: int
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_engineer_entity_id)
	building_entity_id = new_building_entity_id

