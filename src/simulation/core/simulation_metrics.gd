class_name SimulationMetrics
extends RefCounted

var commands_submitted_total: int = 0
var commands_applied_total: int = 0
var command_status_counts: Dictionary = {}
var path_requests_total: int = 0
var path_succeeded_total: int = 0
var path_failed_total: int = 0
var events_emitted_total: int = 0
var event_kind_counts: Dictionary = {}


func record_command_result(result: CommandValidationResult) -> void:
	commands_submitted_total += 1
	command_status_counts[result.status] = int(command_status_counts.get(result.status, 0)) + 1


func record_commands_applied(count: int) -> void:
	commands_applied_total += count


func record_path_result(succeeded: bool) -> void:
	path_requests_total += 1
	if succeeded:
		path_succeeded_total += 1
	else:
		path_failed_total += 1


func record_events(events: Array[SimulationEvent], start_index: int) -> void:
	for index in range(start_index, events.size()):
		var event := events[index]
		events_emitted_total += 1
		event_kind_counts[event.kind] = int(event_kind_counts.get(event.kind, 0)) + 1


func create_snapshot() -> SimulationMetricsSnapshot:
	return SimulationMetricsSnapshot.new(self)
