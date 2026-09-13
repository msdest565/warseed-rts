class_name CommanderTaskStageDefinition
extends Resource

enum Phase { MUSTER, RECON, DEPLOY, ENGAGE, EXPLOIT, RETREAT }

@export var stage_id: StringName
@export var phase: Phase
@export var prerequisite_ids: Array[StringName] = []
@export var timeout_ticks: int = 1200
@export var dwell_ticks: int = 10
@export var arrival_radius: float = 128.0


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if stage_id.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "commander stage requires a stable ID")
	if phase < Phase.MUSTER or phase > Phase.RETREAT:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "unsupported commander phase")
	if timeout_ticks < 1 or timeout_ticks > 4800 or dwell_ticks < 1 or dwell_ticks > timeout_ticks:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "commander stage timing is out of range")
	if not is_finite(arrival_radius) or arrival_radius < 32.0 or arrival_radius > 512.0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "commander arrival radius is out of range")
	var seen: Array[StringName] = []
	for id in prerequisite_ids:
		if id.is_empty() or id == stage_id:
			result.add(DataValidationResult.Reason.INVALID_REFERENCE, "invalid stage prerequisite")
		if seen.has(id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "duplicate stage prerequisite")
		seen.append(id)
	return result
