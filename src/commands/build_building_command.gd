class_name BuildBuildingCommand
extends GameCommand

var building_definition_id: StringName
var build_position: Vector2


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_engineer_entity_id: int,
	new_building_definition_id: StringName,
	new_build_position: Vector2
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, new_engineer_entity_id)
	building_definition_id = new_building_definition_id
	build_position = new_build_position

