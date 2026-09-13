class_name DeployUnitCardCommand
extends GameCommand

var unit_card_id: StringName
var deployment_position: Vector2
var commander_id: StringName
var source_graph_id: StringName


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_unit_card_id: StringName,
	new_deployment_position: Vector2,
	new_commander_id: StringName = &""
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, 0)
	unit_card_id = new_unit_card_id
	deployment_position = new_deployment_position
	commander_id = new_commander_id


func get_supersession_key() -> String:
	return "C:%s" % unit_card_id
