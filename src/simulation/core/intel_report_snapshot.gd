class_name IntelReportSnapshot
extends RefCounted

var report_id: int
var source_key: StringName
var observed_tick: int
var target_category_key: StringName
var estimated_min: int
var estimated_max: int
var region_id: StringName
var direction_key: StringName
var confidence_key: StringName
var eta_min_ticks: int
var eta_max_ticks: int
var age_ticks: int
var freshness_key: StringName
var superseded: bool
var superseded_report_ids: Array[int]
var merged_report_count: int
var contradictory: bool
var has_estimate: bool


func _init(state: IntelReportState, current_tick: int) -> void:
	report_id = state.report_id
	source_key = state.source_key
	observed_tick = state.observed_tick
	target_category_key = state.target_category_key
	estimated_min = state.estimated_min
	estimated_max = state.estimated_max
	region_id = state.region_id
	direction_key = state.direction_key
	confidence_key = state.confidence_key
	age_ticks = maxi(0, current_tick - state.observed_tick)
	eta_min_ticks = maxi(0, state.eta_min_ticks - age_ticks) if state.eta_min_ticks >= 0 else -1
	eta_max_ticks = maxi(0, state.eta_max_ticks - age_ticks) if state.eta_max_ticks >= 0 else -1
	freshness_key = &"INTEL_FRESH_CURRENT" if age_ticks < 100 else (&"INTEL_FRESH_AGING" if age_ticks < 250 else &"INTEL_FRESH_STALE")
	superseded = state.superseded
	superseded_report_ids = state.superseded_report_ids.duplicate()
	merged_report_count = state.merged_report_count
	contradictory = state.contradictory
	has_estimate = state.has_estimate
