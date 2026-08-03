class_name FactionState
extends RefCounted

var faction_id: int
var controller_id: int
var ore: int
var defeated: bool = false
var victorious: bool = false


func _init(new_faction_id: int, new_controller_id: int, initial_ore: int) -> void:
	faction_id = new_faction_id
	controller_id = new_controller_id
	ore = initial_ore
