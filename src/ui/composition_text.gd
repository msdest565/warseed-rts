class_name CompositionText
extends RefCounted


static func from_snapshot(card: UnitCardSnapshot) -> String:
	var lines := PackedStringArray()
	for entry in card.composition:
		var strength := entry.available_strength if card.deployment_state in [UnitCardState.DeploymentState.RESERVE, UnitCardState.DeploymentState.DEPLOYING] else entry.current_strength
		lines.append("%s · %d/%d" % [GameText.unit_name(entry.unit_definition_id), strength, entry.authorized_strength])
	if not card.tactical_ability_id.is_empty():
		lines.append(GameText.t(card.tactical_name_key) + " · " + GameText.t(card.tactical_status_key))
		lines.append(GameText.t(card.tactical_help_key))
	if card.ammunition_capacity > 0:
		lines.append(GameText.t(&"TACTICAL_AMMUNITION") % [card.ammunition, card.ammunition_capacity])
	return GameText.t(&"CARD_COMPOSITION") + "\n" + "\n".join(lines)


static func from_definition(card: UnitCardDefinition, record: Dictionary) -> String:
	var lines := PackedStringArray()
	var saved: Dictionary = record.get("composition", {})
	for entry in UnitCardCompositionCompiler.compile(card):
		var item: Dictionary = saved.get(String(entry.entry_id), {})
		lines.append("%s · %d/%d" % [GameText.unit_name(entry.unit_definition_id), int(item.get("available_strength", entry.authorized_count)), entry.authorized_count])
	if card.tactical_ability != null:
		lines.append(GameText.t(card.tactical_ability.name_key))
		lines.append(GameText.t(card.tactical_ability.help_key))
	return GameText.t(&"CARD_COMPOSITION") + "\n" + "\n".join(lines)
