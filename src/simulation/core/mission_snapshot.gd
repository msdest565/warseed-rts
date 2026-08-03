class_name MissionSnapshot
extends RefCounted

var developed_resource: bool
var defended_area: bool
var attacked_target: bool
var missile_taken_over: bool
var missile_returned: bool
var completed: bool
var completed_tick: int


func _init(state: MissionState) -> void:
	developed_resource = state.developed_resource
	defended_area = state.defended_area
	attacked_target = state.attacked_target
	missile_taken_over = state.missile_taken_over
	missile_returned = state.missile_returned
	completed = state.completed
	completed_tick = state.completed_tick
