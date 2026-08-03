class_name HarvestCommand
extends GameCommand

var ore_field_entity_id: int
var refinery_building_entity_id: int


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_harvester_entity_id: int,
	new_ore_field_entity_id: int,
	new_refinery_building_entity_id: int
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_harvester_entity_id)
	ore_field_entity_id = new_ore_field_entity_id
	refinery_building_entity_id = new_refinery_building_entity_id
