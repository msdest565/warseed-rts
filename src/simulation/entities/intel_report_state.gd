class_name IntelReportState
extends RefCounted

var report_id: int
var faction_id: int
var source_key: StringName
var observed_tick: int
var target_category_key: StringName
var estimated_min: int
var estimated_max: int
var region_id: StringName
var direction_key: StringName
var confidence_key: StringName
var eta_min_ticks: int = -1
var eta_max_ticks: int = -1
var superseded: bool = false
var superseded_report_ids: Array[int] = []
var merged_report_count: int = 1
var contradictory: bool = false
var has_estimate: bool = true


func _init(
	new_report_id: int,
	new_faction_id: int,
	new_source_key: StringName,
	new_observed_tick: int,
	new_target_category_key: StringName,
	new_estimated_min: int,
	new_estimated_max: int,
	new_region_id: StringName,
	new_direction_key: StringName,
	new_confidence_key: StringName,
	new_eta_min_ticks: int = -1,
	new_eta_max_ticks: int = -1,
	new_has_estimate: bool = true
) -> void:
	report_id = new_report_id
	faction_id = new_faction_id
	source_key = new_source_key
	observed_tick = new_observed_tick
	target_category_key = new_target_category_key
	estimated_min = new_estimated_min
	estimated_max = new_estimated_max
	region_id = new_region_id
	direction_key = new_direction_key
	confidence_key = new_confidence_key
	eta_min_ticks = new_eta_min_ticks
	eta_max_ticks = new_eta_max_ticks
	has_estimate = new_has_estimate
