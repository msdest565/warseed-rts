class_name HostTickTimingSnapshot
extends RefCounted

var sample_count: int
var last_usec: int
var average_usec: float
var max_usec: int


func _init(new_sample_count: int, new_last_usec: int, total_usec: int, new_max_usec: int) -> void:
	sample_count = new_sample_count
	last_usec = new_last_usec
	average_usec = float(total_usec) / sample_count if sample_count > 0 else 0.0
	max_usec = new_max_usec
