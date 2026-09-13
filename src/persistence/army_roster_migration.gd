class_name ArmyRosterMigration
extends RefCounted

const FORMAT_VERSION := 4
const CONTENT_VERSION := 1
const UNIT_CATALOG: UnitDefinitionCatalog = preload("res://data/units/unit_catalog.tres")
const COUNTERS := ["battle_count", "replacement_points", "merit", "campaign_days", "last_replacement_award", "last_merit_award"]
const CARD_COUNTERS := ["last_battle_losses", "cumulative_losses", "battles_survived", "last_refit_days"]


static func normalize(source: Dictionary, require_version: bool = true) -> ArmyRosterResult:
	var result := ArmyRosterResult.new()
	if source.is_empty():
		return result.fail("empty roster")
	var record := source.duplicate(true)
	var version: Variant = record.get("format_version", 0 if require_version else 3)
	if integer_in_range(version, 0):
		result.source_version = int(version)
	if not integer_in_range(version, 1, FORMAT_VERSION):
		return result.fail("format_version: unsupported or invalid (%s)" % str(version))
	result.source_version = int(version)
	if int(version) == FORMAT_VERSION and not integer_in_range(record.get("content_version"), CONTENT_VERSION, CONTENT_VERSION):
		return result.fail("content_version: unsupported or invalid")
	for field in ["scenario_id", "last_scenario_id", "last_result", "last_outcome_grade", "last_outcome_reason"]:
		if record.has(field) and not record[field] is String:
			return result.fail(field + ": expected text")
	if record.has("migrated_from_version"):
		if not integer_in_range(record.migrated_from_version, 1, FORMAT_VERSION):
			return result.fail("migrated_from_version: unsupported or invalid")
		record["migrated_from_version"] = int(record.migrated_from_version)
	for field in COUNTERS:
		if not integer_in_range(record.get(field, 0)):
			return result.fail(field + ": expected nonnegative integer")
		record[field] = int(record.get(field, 0))
	if not record.get("cards") is Dictionary:
		return result.fail("cards: expected object")
	var definitions := card_definitions()
	var cards: Dictionary = record.cards
	for card_id in cards:
		if not card_id is String or String(card_id).is_empty() or not cards[card_id] is Dictionary:
			return result.fail("cards: invalid card identity or object")
		var card: Dictionary = cards[card_id]
		var path := "cards." + String(card_id)
		if not _strength_valid(card):
			return result.fail(path + ": invalid authorized/available strength")
		card["authorized_strength"] = int(card.authorized_strength)
		card["available_strength"] = int(card.available_strength)
		for field in CARD_COUNTERS:
			if not integer_in_range(card.get(field, 0)):
				return result.fail(path + "." + field + ": expected nonnegative integer")
			card[field] = int(card.get(field, 0))
		for field in ["honor_id", "equipment_id", "last_status", "last_scenario_id"]:
			if card.has(field) and not card[field] is String:
				return result.fail(path + "." + field + ": expected text")
		card["honor_id"] = card.get("honor_id", "")
		card["equipment_id"] = card.get("equipment_id", "")
		card["last_status"] = card.get("last_status", "unknown")
		card["last_scenario_id"] = card.get("last_scenario_id", record.get("scenario_id", ""))
		var organization: Variant = card.get("organization", 100.0)
		if not (organization is int or organization is float) or not is_finite(float(organization)) or float(organization) < 0.0 or float(organization) > 100.0:
			return result.fail(path + ".organization: expected finite value in 0..100")
		card["organization"] = float(organization)
		if int(version) < FORMAT_VERSION:
			var definition := definitions.get(StringName(card_id)) as UnitCardDefinition
			if definition == null or not definition.composition.is_empty() or definition.authorized_strength != int(card.authorized_strength):
				return result.fail(path + ": no compatible legacy main definition")
			card["composition"] = {"main": {
				"unit_definition_id": String(definition.unit_definition_id),
				"authorized_strength": int(card.authorized_strength),
				"available_strength": int(card.available_strength),
				"cumulative_losses": int(card.cumulative_losses),
				"last_battle_losses": int(card.last_battle_losses),
				"replacement_priority": 0,
			}}
		if not card.get("composition") is Dictionary or (card.composition as Dictionary).is_empty():
			return result.fail(path + ".composition: expected entries")
		var authorized := 0
		var available := 0
		var cumulative := 0
		var recent_losses := 0
		for entry_id in card.composition:
			var entry_path := path + ".composition." + String(entry_id)
			if not entry_id is String or String(entry_id).is_empty() or not card.composition[entry_id] is Dictionary:
				return result.fail(entry_path + ": invalid entry identity or object")
			var entry: Dictionary = card.composition[entry_id]
			if not _strength_valid(entry) or not entry.get("unit_definition_id") is String or UNIT_CATALOG.get_unit(StringName(entry.unit_definition_id)) == null:
				return result.fail(entry_path + ": invalid strength or unit definition")
			entry["authorized_strength"] = int(entry.authorized_strength)
			entry["available_strength"] = int(entry.available_strength)
			for field in ["cumulative_losses", "last_battle_losses", "replacement_priority"]:
				if not integer_in_range(entry.get(field, 0)):
					return result.fail(entry_path + "." + field + ": expected nonnegative integer")
				entry[field] = int(entry.get(field, 0))
			authorized += int(entry.authorized_strength)
			available += int(entry.available_strength)
			cumulative += int(entry.cumulative_losses)
			recent_losses += int(entry.last_battle_losses)
		if authorized != int(card.authorized_strength) or available != int(card.available_strength) or cumulative != int(card.cumulative_losses) or recent_losses != int(card.last_battle_losses):
			return result.fail(path + ": composition totals disagree with card")
		var definition := definitions.get(StringName(card_id)) as UnitCardDefinition
		if definition != null:
			var mismatch := definition_mismatch(card, definition)
			if not mismatch.is_empty():
				return result.fail(path + ": " + mismatch)
	record["format_version"] = FORMAT_VERSION
	record["content_version"] = CONTENT_VERSION
	if int(version) < FORMAT_VERSION:
		record["migrated_from_version"] = int(version)
	result.record = record
	result.status = ArmyRosterResult.Status.MIGRATED if int(version) < FORMAT_VERSION else ArmyRosterResult.Status.LOADED
	return result


static func definition_mismatch(card: Dictionary, definition: UnitCardDefinition) -> String:
	var entries := UnitCardCompositionCompiler.compile(definition)
	var saved: Dictionary = card.get("composition", {})
	if saved.size() != entries.size():
		return "composition entry set changed without a content migration"
	for entry in entries:
		var item: Dictionary = saved.get(String(entry.entry_id), {})
		if item.is_empty() or item.get("unit_definition_id") != String(entry.unit_definition_id) or int(item.get("authorized_strength", -1)) != entry.authorized_count or int(item.get("replacement_priority", 0)) != entry.replacement_priority:
			return "composition.%s does not match current content" % entry.entry_id
	return ""


static func integer_in_range(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum


static func _strength_valid(value: Dictionary) -> bool:
	return integer_in_range(value.get("authorized_strength"), 1, 10000) and integer_in_range(value.get("available_strength"), 0, int(value.get("authorized_strength", 0)))


static func card_definitions() -> Dictionary:
	var definitions: Dictionary = {}
	var catalog := load(BattleContentLoader.DEFAULT_CATALOG_PATH) as BattleContentCatalog
	if catalog != null:
		for battle in catalog.battles:
			for card in battle.unit_card_definitions:
				definitions[card.definition_id] = card
	return definitions
