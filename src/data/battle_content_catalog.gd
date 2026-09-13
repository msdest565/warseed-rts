class_name BattleContentCatalog
extends Resource

@export var battles: Array[BattleDefinition] = []


func validate(unit_catalog: UnitDefinitionCatalog = null) -> DataValidationResult:
	var result := DataValidationResult.new()
	var scenario_ids: Dictionary = {}
	var persistent_compositions: Dictionary = {}
	for index in range(battles.size()):
		var battle := battles[index]
		if battle == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "battles[%d]" % index)
			continue
		if battle.scenario_id.is_empty():
			result.add(DataValidationResult.Reason.EMPTY_ID, "battles[%d].scenario_id" % index)
		elif scenario_ids.has(battle.scenario_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "battle '%s'" % battle.scenario_id)
		scenario_ids[battle.scenario_id] = true
		for issue in battle.validate(unit_catalog).issues:
			result.issues.append(issue)
		for card in battle.unit_card_definitions:
			if card == null:
				continue
			var signature: Array = []
			for entry in UnitCardCompositionCompiler.compile(card):
				signature.append([entry.entry_id, entry.unit_definition_id, entry.authorized_count, entry.replacement_priority])
			if persistent_compositions.has(card.definition_id) and persistent_compositions[card.definition_id] != signature:
				result.add(DataValidationResult.Reason.INVALID_VALUE, "card '%s' changes persistent composition between battles" % card.definition_id)
			persistent_compositions[card.definition_id] = signature
	return result


func get_battle(scenario_id: StringName) -> BattleDefinition:
	for battle in battles:
		if battle != null and battle.scenario_id == scenario_id:
			return battle
	return null


func get_selectable_battles() -> Array[BattleDefinition]:
	var selectable: Array[BattleDefinition] = []
	for battle in battles:
		if battle != null and battle.available_in_selector:
			selectable.append(battle)
	selectable.sort_custom(func(left: BattleDefinition, right: BattleDefinition) -> bool:
		return left.operation_number < right.operation_number
	)
	return selectable
