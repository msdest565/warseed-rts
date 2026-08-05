class_name StrategicOrderCommand
extends GameCommand

enum OrderKind {
	DEVELOP_RESOURCE,
	DEFEND_AREA,
	ATTACK_TARGET,
	SCOUT_AREA,
}

var order_kind: OrderKind
var formation_id: int
var objective_entity_id: int
var target_position: Vector2
var target_radius: float
var participant_entity_ids: Array[int] = []


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issued_tick: int,
	new_order_kind: OrderKind,
	new_formation_id: int,
	new_objective_entity_id: int,
	new_target_position: Vector2,
	new_target_radius: float = 0.0,
	new_issuer_kind: IssuerKind = IssuerKind.PLAYER
) -> void:
	var command_target := new_objective_entity_id
	if new_formation_id != 0:
		command_target = new_formation_id
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, command_target)
	order_kind = new_order_kind
	formation_id = new_formation_id
	objective_entity_id = new_objective_entity_id
	target_position = new_target_position
	target_radius = new_target_radius


func get_supersession_key() -> String:
	return "STRATEGIC_%d" % order_kind
