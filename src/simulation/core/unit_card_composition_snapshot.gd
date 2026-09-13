class_name UnitCardCompositionSnapshot
extends RefCounted

var entry_id: StringName
var unit_definition_id: StringName
var authorized_strength: int
var available_strength: int
var current_strength: int
var withdrawn_strength: int
var cumulative_losses: int
var replacement_priority: int
var member_entity_ids: Array[int]
var active_member_entity_ids: Array[int] = []


func _init(state: UnitCardCompositionState, units: Dictionary, withdrawn: bool) -> void:
	entry_id = state.entry_id
	unit_definition_id = state.unit_definition_id
	authorized_strength = state.authorized_strength
	available_strength = state.available_strength
	withdrawn_strength = state.withdrawn_strength
	cumulative_losses = state.cumulative_losses
	replacement_priority = state.replacement_priority
	member_entity_ids = state.member_entity_ids.duplicate()
	for entity_id in member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			active_member_entity_ids.append(entity_id)
	current_strength = withdrawn_strength if withdrawn else active_member_entity_ids.size()
