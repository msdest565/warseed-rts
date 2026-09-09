class_name BattleObjectiveSetDefinition
extends Resource

@export var objective_set_id: StringName
@export var objectives: Array[BattleObjectiveDefinition] = []
@export var conclusion_groups: Array[ObjectiveGroupDefinition] = []


func validate(battle: BattleDefinition = null) -> DataValidationResult:
	var result := DataValidationResult.new()
	if objective_set_id.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "battle objective set requires objective_set_id")
	var objective_ids: Dictionary = {}
	for objective in objectives:
		if objective == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "objective set '%s' contains a null objective" % objective_set_id)
			continue
		for issue in objective.validate().issues:
			result.issues.append(issue.duplicate(true))
		if objective_ids.has(objective.objective_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "duplicate objective_id '%s'" % objective.objective_id)
		objective_ids[objective.objective_id] = true
		if battle != null and objective.kind in [BattleObjectiveDefinition.Kind.ESCORT_UNIT_CARD_TO_REGION, BattleObjectiveDefinition.Kind.WITHDRAW_UNIT_CARD]:
			if not battle.unit_card_dictionary().has(objective.unit_card_id):
				result.add(DataValidationResult.Reason.INVALID_REFERENCE, "objective '%s' references missing card '%s'" % [objective.objective_id, objective.unit_card_id])
			if not battle.region_dictionary().has(objective.region_id):
				result.add(DataValidationResult.Reason.INVALID_REFERENCE, "objective '%s' references missing region '%s'" % [objective.objective_id, objective.region_id])
	if objectives.is_empty():
		result.add(DataValidationResult.Reason.INVALID_VALUE, "objective set '%s' requires objectives" % objective_set_id)
	var group_ids: Dictionary = {}
	for group in conclusion_groups:
		if group == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "objective set '%s' contains a null conclusion group" % objective_set_id)
			continue
		for issue in group.validate().issues:
			result.issues.append(issue.duplicate(true))
		if group_ids.has(group.group_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "duplicate objective group '%s'" % group.group_id)
		group_ids[group.group_id] = true
		for objective_id in group.objective_ids:
			if not objective_ids.has(objective_id):
				result.add(DataValidationResult.Reason.INVALID_REFERENCE, "group '%s' references missing objective '%s'" % [group.group_id, objective_id])
	if conclusion_groups.is_empty():
		result.add(DataValidationResult.Reason.INVALID_VALUE, "objective set '%s' requires conclusion groups" % objective_set_id)
	return result


func objective_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for objective in objectives:
		if objective != null:
			result[objective.objective_id] = objective
	return result
