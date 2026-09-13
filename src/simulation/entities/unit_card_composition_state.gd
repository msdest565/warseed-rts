class_name UnitCardCompositionState
extends RefCounted

var entry_id: StringName
var unit_definition_id: StringName
var authorized_strength: int
var available_strength: int
var withdrawn_strength: int = 0
var cumulative_losses: int = 0
var formation_role: StringName
var replacement_priority: int
var member_entity_ids: Array[int] = []


func _init(entry: UnitCardCompositionEntry) -> void:
	entry_id = entry.entry_id
	unit_definition_id = entry.unit_definition_id
	authorized_strength = entry.authorized_count
	available_strength = authorized_strength
	formation_role = entry.formation_role
	replacement_priority = entry.replacement_priority


func active_count(units: Dictionary) -> int:
	var count := 0
	for entity_id in member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			count += 1
	return count
