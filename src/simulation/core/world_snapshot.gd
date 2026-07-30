class_name WorldSnapshot
extends RefCounted

var tick: int
var units: Array[UnitSnapshot]


func _init(new_tick: int, new_units: Array[UnitSnapshot]) -> void:
	tick = new_tick
	units = new_units


func get_unit(entity_id: int) -> UnitSnapshot:
	for unit in units:
		if unit.entity_id == entity_id:
			return unit
	return null
