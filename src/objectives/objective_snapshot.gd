class_name ObjectiveSnapshot
extends RefCounted

var objective_id: StringName
var display_name_key: StringName
var kind: BattleObjectiveDefinition.Kind
var status: ObjectiveState.Status
var progress: float
var changed_tick: int


func _init(state: ObjectiveState) -> void:
	objective_id = state.definition.objective_id
	display_name_key = state.definition.display_name_key
	kind = state.definition.kind
	status = state.status
	progress = state.progress
	changed_tick = state.changed_tick
