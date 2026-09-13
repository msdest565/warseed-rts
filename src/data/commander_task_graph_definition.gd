class_name CommanderTaskGraphDefinition
extends Resource

@export var graph_id: StringName
@export var stages: Array[CommanderTaskStageDefinition] = []


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if graph_id.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "commander graph requires a stable ID")
	if stages.size() != CommanderTaskStageDefinition.Phase.size():
		result.add(DataValidationResult.Reason.INVALID_VALUE, "commander graph requires all six phases")
	var ids: Array[StringName] = []
	var phases: Array[int] = []
	for stage in stages:
		if stage == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "missing commander stage")
			continue
		result.issues.append_array(stage.validate().issues)
		if ids.has(stage.stage_id) or phases.has(stage.phase):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "stage IDs and phases must be distinct")
		ids.append(stage.stage_id)
		phases.append(stage.phase)
	for stage in stages:
		if stage == null:
			continue
		for prerequisite in stage.prerequisite_ids:
			if not ids.has(prerequisite):
				result.add(DataValidationResult.Reason.INVALID_REFERENCE, "unknown stage prerequisite: %s" % prerequisite)
	if not result.is_valid():
		return result
	# Stable topological validation; references are IDs, never array positions.
	var resolved: Array[StringName] = []
	for _pass in range(stages.size()):
		for stage in stages:
			if resolved.has(stage.stage_id):
				continue
			var ready := true
			for prerequisite in stage.prerequisite_ids:
				ready = ready and resolved.has(prerequisite)
			if ready:
				resolved.append(stage.stage_id)
	if resolved.size() != stages.size():
		result.add(DataValidationResult.Reason.INVALID_REFERENCE, "commander stage dependencies contain a cycle")
	var muster := get_phase(CommanderTaskStageDefinition.Phase.MUSTER)
	var retreat := get_phase(CommanderTaskStageDefinition.Phase.RETREAT)
	if not muster.prerequisite_ids.is_empty() or not retreat.prerequisite_ids.is_empty():
		result.add(DataValidationResult.Reason.INVALID_REFERENCE, "muster and explicit retreat must be independent roots")
	for phase in range(CommanderTaskStageDefinition.Phase.RECON, CommanderTaskStageDefinition.Phase.EXPLOIT + 1):
		var stage := get_phase(phase)
		var previous := get_phase(phase - 1)
		if not stage.prerequisite_ids.has(previous.stage_id):
			result.add(DataValidationResult.Reason.INVALID_REFERENCE, "normal phases must depend on their preceding phase")
		if stage.prerequisite_ids.has(retreat.stage_id):
			result.add(DataValidationResult.Reason.INVALID_REFERENCE, "normal execution cannot depend on retreat")
	return result


func get_phase(phase: int) -> CommanderTaskStageDefinition:
	for stage in stages:
		if stage != null and stage.phase == phase:
			return stage
	return null
