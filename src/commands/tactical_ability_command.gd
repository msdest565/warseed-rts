class_name TacticalAbilityCommand
extends GameCommand

var unit_card_id: StringName
var target_card_id: StringName
var route_id: StringName
var position: Vector2


func _init(id: int, faction: int, issuer: IssuerKind, tick: int, card_id: StringName, point: Vector2 = Vector2.ZERO, target_id: int = 0, friendly_card: StringName = &"", engineering_route: StringName = &"") -> void:
	super(id, faction, issuer, tick, target_id)
	unit_card_id = card_id
	position = point
	target_card_id = friendly_card
	route_id = engineering_route
