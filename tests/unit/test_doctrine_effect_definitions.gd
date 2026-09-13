class_name TestDoctrineEffectDefinitions
extends RefCounted

const FIXTURE_PATH := "res://tests/fixtures/doctrine_staged_departure.tres"
const PARTS: Array[StringName] = [&"trigger", &"selector", &"effect", &"cost", &"timing", &"counterplay", &"reason"]


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_resource_round_trip(failures)
	_test_required_parts_and_unknown_kinds(failures)
	_test_ids_keys_and_timing(failures)
	_test_doctrine_and_loader_validation(failures)
	_test_localized_explanations(failures)
	return failures


func _fixture() -> DoctrineEffectDefinition:
	return (load(FIXTURE_PATH) as DoctrineEffectDefinition).duplicate(true) as DoctrineEffectDefinition


func _doctrine() -> DoctrineDefinition:
	var definition := (load("res://data/army/alternating_cover.tres") as DoctrineDefinition).duplicate(true) as DoctrineDefinition
	definition.effects.clear()
	return definition


func _test_resource_round_trip(failures: Array[String]) -> void:
	var definition := _fixture()
	_expect(definition.validate().is_valid(), "typed staged departure fixture must validate", failures)
	var path := "user://r3_doctrine_round_trip_%d.tres" % OS.get_process_id()
	definition.timing.interval_ticks = 37
	_expect(ResourceSaver.save(definition, path) == OK, "typed doctrine fixture must save", failures)
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as DoctrineEffectDefinition
	_expect(restored != null and restored.validate().is_valid(), "saved grammar must load as a valid typed effect", failures)
	if restored != null:
		_expect(restored.trigger is DoctrineTriggerDefinition and restored.selector is DoctrineSelectorDefinition and restored.effect is DoctrineActionDefinition and restored.cost is DoctrineCostDefinition and restored.timing is DoctrineTimingDefinition and restored.counterplay is DoctrineCounterplayDefinition and restored.reason is DoctrineReasonDefinition, "all seven typed subresources must survive serialization", failures)
		_expect(restored.timing.interval_ticks == 37, "serialized timing must preserve authored values", failures)
		restored.timing.interval_ticks = 81
		_expect(definition.timing.interval_ticks == 37 and _fixture().timing.interval_ticks == 20, "round trip and deep copies must not mutate shared source resources", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_required_parts_and_unknown_kinds(failures: Array[String]) -> void:
	for part_name in PARTS:
		var absent := _fixture()
		absent.set(part_name, null)
		var missing_result := absent.validate("fixture")
		_expect(_has_issue(missing_result, DataValidationResult.Reason.NULL_REFERENCE, "fixture.%s" % part_name), "missing %s must identify its field path" % part_name, failures)
		for invalid_kind in [-1, 99]:
			var unsupported := _fixture()
			(unsupported.get(part_name) as Resource).set("kind", invalid_kind)
			_expect(_has_issue(unsupported.validate("fixture"), DataValidationResult.Reason.INVALID_VALUE, "fixture.%s.kind" % part_name), "unknown %s kind must fail before execution" % part_name, failures)
	var unsupported_exit := _fixture()
	unsupported_exit.counterplay.set("exit_condition", 99)
	_expect(_has_issue(unsupported_exit.validate(), DataValidationResult.Reason.INVALID_VALUE, "counterplay.exit_condition"), "unknown effect exit conditions must fail", failures)
	var unsupported_schema := _fixture()
	unsupported_schema.schema_version = 2
	_expect(_has_issue(unsupported_schema.validate(), DataValidationResult.Reason.INVALID_VALUE, "schema_version"), "unknown grammar versions must fail", failures)


func _test_ids_keys_and_timing(failures: Array[String]) -> void:
	for bad_id in ["", "Uppercase", "bad id", "../script", "a".repeat(65)]:
		var definition := _fixture()
		definition.effect_id = StringName(bad_id)
		_expect(not definition.validate().is_valid(), "invalid stable effect ID must fail: %s" % bad_id, failures)
	for values in [[0, 1, true], [3600, 3600, true], [-1, 20, false], [3601, 20, false], [0, 0, false], [0, -1, false], [0, 3601, false]]:
		var definition := _fixture()
		definition.timing.base_delay_ticks = values[0]
		definition.timing.interval_ticks = values[1]
		var first := definition.validate()
		var second := definition.validate()
		_expect(first.is_valid() == values[2] and first.issues == second.issues, "timing bounds must be deterministic: %s" % [values], failures)
		_expect(definition.timing.base_delay_ticks == values[0] and definition.timing.interval_ticks == values[1], "validation must not normalize invalid authoring into success", failures)
	for field in [[&"cost", &"explanation_key"], [&"counterplay", &"explanation_key"], [&"reason", &"waiting_reason_key"], [&"reason", &"description_key"]]:
		for bad_key in [&"", &"arbitrary(expression)"]:
			var definition := _fixture()
			(definition.get(field[0]) as Resource).set(field[1], bad_key)
			_expect(not definition.validate().is_valid(), "empty or executable-looking explanation must not be valid: %s" % [field], failures)


func _test_doctrine_and_loader_validation(failures: Array[String]) -> void:
	var old := _doctrine()
	_expect(old.validate().is_valid(), "legacy doctrines with no effects must stay compatible", failures)
	old.effects.append(null)
	_expect(old.validate().has_reason(DataValidationResult.Reason.NULL_REFERENCE), "null effect list entries must fail", failures)
	old.effects.clear()
	old.effects.append(_fixture())
	old.effects.append(_fixture())
	_expect(old.validate().has_reason(DataValidationResult.Reason.DUPLICATE_ID), "duplicate stable effect IDs must fail", failures)
	old.effects[1].effect_id = &"second_departure"
	_expect(old.validate().has_reason(DataValidationResult.Reason.INVALID_VALUE), "duplicate action kinds must not silently stack", failures)
	var catalog_result := BattleContentLoader.load_battle(&"grey_ridge")
	_expect(catalog_result.is_valid(), "committed catalog must remain compatible", failures)
	if not catalog_result.is_valid():
		return
	var seen: Dictionary = {}
	for battle in catalog_result.catalog.battles:
		for definition in battle.doctrine_definitions:
			seen[definition.definition_id] = true
			_expect(definition.validate().is_valid(), "old doctrine must remain loadable: %s" % definition.definition_id, failures)
	_expect(seen.size() == 12, "all twelve legacy doctrine IDs must remain available", failures)
	var invalid_catalog := catalog_result.catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as BattleContentCatalog
	var invalid_effect := _fixture()
	invalid_effect.timing.interval_ticks = -5
	invalid_catalog.battles[0].doctrine_definitions[0].effects.clear()
	invalid_catalog.battles[0].doctrine_definitions[0].effects.append(invalid_effect)
	var path := "user://r3_invalid_doctrine_catalog_%d.tres" % OS.get_process_id()
	_expect(ResourceSaver.save(invalid_catalog, path) == OK, "invalid content test fixture must save for loader rejection", failures)
	var invalid_load := BattleContentLoader.load_battle(invalid_catalog.battles[0].scenario_id, path)
	_expect(not invalid_load.is_valid() and _has_issue(invalid_load.validation, DataValidationResult.Reason.INVALID_VALUE, ".effects[0].timing.interval_ticks"), "loader must reject invalid doctrine timing with the nested field path", failures)
	_expect(BattleContentLoader.load_battle(&"grey_ridge").is_valid(), "invalid fixture must not pollute cached committed content", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_localized_explanations(failures: Array[String]) -> void:
	var definition := _fixture()
	var previous_locale := TranslationServer.get_locale()
	for locale in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for key in [definition.cost.explanation_key, definition.counterplay.explanation_key, definition.reason.waiting_reason_key, definition.reason.description_key]:
			_expect(GameText.t(key) != String(key) and not GameText.t(key).is_empty(), "effect explanation must exist in %s: %s" % [locale, key], failures)
	TranslationServer.set_locale(previous_locale)


func _has_issue(result: DataValidationResult, reason: DataValidationResult.Reason, path: String) -> bool:
	for issue in result.issues:
		if issue["reason"] == reason and String(issue["detail"]).contains(path):
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
