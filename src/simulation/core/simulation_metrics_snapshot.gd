class_name SimulationMetricsSnapshot
extends RefCounted

var commands_submitted_total: int
var commands_applied_total: int
var command_status_counts: Dictionary
var path_requests_total: int
var path_succeeded_total: int
var path_failed_total: int
var events_emitted_total: int
var event_kind_counts: Dictionary


func _init(metrics: SimulationMetrics) -> void:
	commands_submitted_total = metrics.commands_submitted_total
	commands_applied_total = metrics.commands_applied_total
	command_status_counts = metrics.command_status_counts.duplicate()
	path_requests_total = metrics.path_requests_total
	path_succeeded_total = metrics.path_succeeded_total
	path_failed_total = metrics.path_failed_total
	events_emitted_total = metrics.events_emitted_total
	event_kind_counts = metrics.event_kind_counts.duplicate()


func get_command_count(status: CommandValidationResult.Status) -> int:
	return int(command_status_counts.get(status, 0))


func get_event_count(kind: SimulationEvent.Kind) -> int:
	return int(event_kind_counts.get(kind, 0))
