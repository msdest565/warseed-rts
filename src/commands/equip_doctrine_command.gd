class_name EquipDoctrineCommand
extends GameCommand

var commander_id: StringName
var doctrine_id: StringName
var slot_index: int


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issued_tick: int,
	new_commander_id: StringName,
	new_doctrine_id: StringName,
	new_slot_index: int = 0
) -> void:
	super(new_command_id, new_issuer_id, IssuerKind.PLAYER, new_issued_tick, 0)
	commander_id = new_commander_id
	doctrine_id = new_doctrine_id
	slot_index = new_slot_index


func get_supersession_key() -> String:
	return "COMMANDER_%s_DOCTRINE_%d" % [commander_id, slot_index]
