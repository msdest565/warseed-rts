class_name CommanderOrderCommand
extends GameCommand

enum OrderKind {
	ASSIGN_OBJECTIVE,
	SET_POSTURE,
	ASSIGN_INTENT,
	CANCEL_INTENT,
}

var commander_id: StringName
var order_kind: OrderKind
var target_position: Vector2
var target_region_id: StringName
var posture: CommanderState.Posture
var route_points: PackedVector2Array = PackedVector2Array()
var intent_id: StringName
var main_axis_region_id: StringName
var reserve_policy: CommanderState.ReservePolicy = CommanderState.ReservePolicy.HOLD


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issued_tick: int,
	new_commander_id: StringName,
	new_order_kind: OrderKind,
	new_target_position: Vector2 = Vector2.ZERO,
	new_target_region_id: StringName = &"",
	new_posture: CommanderState.Posture = CommanderState.Posture.BALANCED,
	new_route_points: PackedVector2Array = PackedVector2Array(),
	new_intent_id: StringName = &"",
	new_main_axis_region_id: StringName = &"",
	new_reserve_policy: CommanderState.ReservePolicy = CommanderState.ReservePolicy.HOLD
) -> void:
	super(new_command_id, new_issuer_id, IssuerKind.PLAYER, new_issued_tick, 0)
	commander_id = new_commander_id
	order_kind = new_order_kind
	target_position = new_target_position
	target_region_id = new_target_region_id
	posture = new_posture
	route_points = new_route_points.duplicate()
	intent_id = new_intent_id
	main_axis_region_id = new_main_axis_region_id
	reserve_policy = new_reserve_policy


func get_supersession_key() -> String:
	if order_kind in [OrderKind.ASSIGN_INTENT, OrderKind.CANCEL_INTENT]:
		return "COMMANDER_%s_INTENT" % commander_id
	return "COMMANDER_%s_%d" % [commander_id, order_kind]
