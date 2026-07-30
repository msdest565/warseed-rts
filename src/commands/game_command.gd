class_name GameCommand
extends RefCounted

enum IssuerKind {
	PLAYER,
	AGENT,
}

var command_id: int
var issuer_id: int
var issuer_kind: IssuerKind
var issued_tick: int
var target_entity_id: int


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_target_entity_id: int
) -> void:
	command_id = new_command_id
	issuer_id = new_issuer_id
	issuer_kind = new_issuer_kind
	issued_tick = new_issued_tick
	target_entity_id = new_target_entity_id
