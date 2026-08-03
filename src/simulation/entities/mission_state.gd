class_name MissionState
extends RefCounted

var developed_resource: bool = false
var defended_area: bool = false
var attacked_target: bool = false
var missile_taken_over: bool = false
var missile_returned: bool = false
var completed: bool = false
var completed_tick: int = -1


func update_completed(current_tick: int) -> void:
	if completed:
		return
	completed = developed_resource and defended_area and attacked_target and missile_taken_over and missile_returned
	if completed:
		completed_tick = current_tick
