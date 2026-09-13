class_name UnitCardCompositionCompiler
extends RefCounted

const ROLES: Array[StringName] = [&"none", &"scout", &"assault", &"armor", &"firepower"]


static func compile(card: UnitCardDefinition) -> Array[UnitCardCompositionEntry]:
	var entries: Array[UnitCardCompositionEntry] = []
	if card.composition.is_empty():
		var main := UnitCardCompositionEntry.new()
		main.entry_id = &"main"
		main.unit_definition_id = card.unit_definition_id
		main.authorized_count = card.authorized_strength
		match card.role_key:
			&"UNIT_CARD_ROLE_RECON": main.formation_role = &"scout"
			&"UNIT_CARD_ROLE_ASSAULT": main.formation_role = &"assault"
			&"UNIT_CARD_ROLE_ARMOR": main.formation_role = &"armor"
			&"UNIT_CARD_ROLE_FIREPOWER": main.formation_role = &"firepower"
		entries.append(main)
	else:
		for entry in card.composition:
			if entry != null:
				entries.append(entry.duplicate() as UnitCardCompositionEntry)
	entries.sort_custom(func(a: UnitCardCompositionEntry, b: UnitCardCompositionEntry) -> bool: return String(a.entry_id) < String(b.entry_id))
	return entries


static func validate(card: UnitCardDefinition, catalog: UnitDefinitionCatalog) -> DataValidationResult:
	var result := DataValidationResult.new()
	var ids: Array[StringName] = []
	var total := 0
	if card.composition.has(null):
		result.add(DataValidationResult.Reason.NULL_REFERENCE, "card '%s'.composition" % card.definition_id)
	for entry in compile(card):
		var path := "card '%s'.composition.%s" % [card.definition_id, entry.entry_id]
		if entry.entry_id.is_empty():
			result.add(DataValidationResult.Reason.EMPTY_ID, path)
		if entry.entry_id in ids:
			result.add(DataValidationResult.Reason.DUPLICATE_ID, path)
		ids.append(entry.entry_id)
		if entry.authorized_count <= 0 or entry.authorized_count > 10000 or entry.replacement_priority < 0 or entry.replacement_priority > 10000 or entry.formation_role not in ROLES:
			result.add(DataValidationResult.Reason.INVALID_VALUE, path)
		if catalog != null and catalog.get_unit(entry.unit_definition_id) == null:
			result.add(DataValidationResult.Reason.INVALID_REFERENCE, path + ".unit_definition_id")
		total += entry.authorized_count
	if total != card.authorized_strength:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "card '%s'.composition total differs from authorized_strength" % card.definition_id)
	return result


static func expand(card: UnitCardDefinition, state: UnitCardState = null) -> Array[UnitCardCompositionEntry]:
	var members: Array[UnitCardCompositionEntry] = []
	for entry in compile(card):
		var count := entry.authorized_count
		if state != null:
			count = state.available_strength if card.composition.is_empty() else state.get_composition_entry(entry.entry_id).available_strength
		for _index in range(count):
			members.append(entry)
	return members
