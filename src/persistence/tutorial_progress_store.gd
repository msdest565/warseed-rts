class_name TutorialProgressStore
extends RefCounted

const FORMAT_VERSION := 2
const LEGACY_FORMAT_VERSION := 1
const DEFAULT_PATH := "user://warseed_tutorial_progress.json"
const SCENARIO_IDS := [&"grey_ridge", &"broken_bridge", &"fog_forest", &"black_well"]
const STATUS_NOT_STARTED := "not_started"
const STATUS_IN_PROGRESS := "in_progress"
const STATUS_COMPLETED := "completed"
const STATUS_SKIPPED := "skipped"


static func default_state() -> Dictionary:
	return _normalize_state({})


static func load_state(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return default_state()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return default_state()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return default_state()
	var state := parsed as Dictionary
	var version := int(state.get("format_version", 0))
	if version == LEGACY_FORMAT_VERSION:
		return _migrate_legacy_state(state)
	if version != FORMAT_VERSION:
		return default_state()
	return _normalize_state(state)


static func save_state(state: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var normalized := _normalize_state(state)
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(normalized, "\t"))
	return file.get_error() == OK


static func get_scenario_state(scenario_id: StringName, path: String = DEFAULT_PATH) -> Dictionary:
	var state := load_state(path)
	var scenarios := state.get("scenarios", {}) as Dictionary
	return (scenarios.get(String(scenario_id), _default_scenario_state()) as Dictionary).duplicate(true)


static func get_scenario_status(scenario_id: StringName, path: String = DEFAULT_PATH) -> String:
	return String(get_scenario_state(scenario_id, path).get("status", STATUS_NOT_STARTED))


static func is_scenario_enabled(scenario_id: StringName, path: String = DEFAULT_PATH) -> bool:
	return bool(get_scenario_state(scenario_id, path).get("enabled", true))


static func set_scenario_enabled(
	scenario_id: StringName,
	enabled: bool,
	path: String = DEFAULT_PATH
) -> bool:
	var state := load_state(path)
	var scenario := _scenario_entry(state, scenario_id)
	scenario["enabled"] = enabled
	var status := String(scenario.get("status", STATUS_NOT_STARTED))
	if enabled and status in [STATUS_COMPLETED, STATUS_SKIPPED]:
		scenario["status"] = STATUS_NOT_STARTED
	elif not enabled and status != STATUS_COMPLETED:
		scenario["status"] = STATUS_SKIPPED
	return save_state(state, path)


static func begin_scenario(scenario_id: StringName, path: String = DEFAULT_PATH) -> bool:
	var state := load_state(path)
	var scenario := _scenario_entry(state, scenario_id)
	if not bool(scenario.get("enabled", true)):
		return false
	scenario["status"] = STATUS_IN_PROGRESS
	return save_state(state, path)


static func mark_scenario_completed(scenario_id: StringName, path: String = DEFAULT_PATH) -> bool:
	var state := load_state(path)
	var scenario := _scenario_entry(state, scenario_id)
	scenario["enabled"] = false
	scenario["status"] = STATUS_COMPLETED
	return save_state(state, path)


static func mark_scenario_skipped(scenario_id: StringName, path: String = DEFAULT_PATH) -> bool:
	var state := load_state(path)
	var scenario := _scenario_entry(state, scenario_id)
	scenario["enabled"] = false
	scenario["status"] = STATUS_SKIPPED
	return save_state(state, path)


static func reset_scenario(scenario_id: StringName, path: String = DEFAULT_PATH) -> bool:
	var state := load_state(path)
	var scenario := _scenario_entry(state, scenario_id)
	scenario["enabled"] = true
	scenario["status"] = STATUS_NOT_STARTED
	return save_state(state, path)


# Compatibility wrappers for callers and v1 tests that only knew the first tutorial.
static func set_enabled(enabled: bool, path: String = DEFAULT_PATH) -> bool:
	return set_scenario_enabled(&"grey_ridge", enabled, path)


static func mark_completed(path: String = DEFAULT_PATH) -> bool:
	return mark_scenario_completed(&"grey_ridge", path)


static func mark_black_well_growth_pending(
	unit_card_id: StringName,
	growth_id: StringName,
	path: String = DEFAULT_PATH
) -> bool:
	if unit_card_id.is_empty() or growth_id.is_empty():
		return false
	var state := load_state(path)
	state["black_well_pending_card_id"] = String(unit_card_id)
	state["black_well_pending_growth_id"] = String(growth_id)
	return save_state(state, path)


static func confirm_black_well_continuity(record: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var state := load_state(path)
	var card_id := String(state.get("black_well_pending_card_id", ""))
	var growth_id := String(state.get("black_well_pending_growth_id", ""))
	if card_id.is_empty() or growth_id.is_empty():
		return false
	var cards := record.get("cards", {}) as Dictionary
	var card := cards.get(card_id, {}) as Dictionary
	if card.is_empty() or growth_id not in [String(card.get("honor_id", "")), String(card.get("equipment_id", ""))]:
		return false
	state["black_well_pending_card_id"] = ""
	state["black_well_pending_growth_id"] = ""
	var scenario := _scenario_entry(state, &"black_well")
	scenario["enabled"] = false
	scenario["status"] = STATUS_COMPLETED
	return save_state(state, path)


static func _normalize_state(source: Dictionary) -> Dictionary:
	var scenarios := {}
	var source_scenarios := source.get("scenarios", {}) as Dictionary
	for scenario_id in SCENARIO_IDS:
		var raw := source_scenarios.get(String(scenario_id), {}) as Dictionary
		scenarios[String(scenario_id)] = {
			"enabled": bool(raw.get("enabled", true)),
			"status": _normalize_status(String(raw.get("status", STATUS_NOT_STARTED))),
		}
	var grey_ridge := scenarios["grey_ridge"] as Dictionary
	return {
		"format_version": FORMAT_VERSION,
		"scenarios": scenarios,
		# Deprecated aliases keep older tools readable during the v1 -> v2 transition.
		"enabled": bool(grey_ridge.get("enabled", true)),
		"completed": String(grey_ridge.get("status", STATUS_NOT_STARTED)) == STATUS_COMPLETED,
		"black_well_pending_card_id": String(source.get("black_well_pending_card_id", "")),
		"black_well_pending_growth_id": String(source.get("black_well_pending_growth_id", "")),
	}


static func _migrate_legacy_state(legacy: Dictionary) -> Dictionary:
	var enabled := bool(legacy.get("enabled", true))
	var completed := bool(legacy.get("completed", false))
	var status := STATUS_NOT_STARTED
	if completed:
		status = STATUS_COMPLETED
	elif not enabled:
		status = STATUS_SKIPPED
	var scenarios := {}
	for scenario_id in SCENARIO_IDS:
		scenarios[String(scenario_id)] = {"enabled": enabled, "status": status}
	return _normalize_state({
		"scenarios": scenarios,
		"black_well_pending_card_id": String(legacy.get("black_well_pending_card_id", "")),
		"black_well_pending_growth_id": String(legacy.get("black_well_pending_growth_id", "")),
	})


static func _scenario_entry(state: Dictionary, scenario_id: StringName) -> Dictionary:
	var scenarios := state.get("scenarios", {}) as Dictionary
	var key := String(scenario_id)
	if not scenarios.has(key):
		scenarios[key] = _default_scenario_state()
	state["scenarios"] = scenarios
	return scenarios[key] as Dictionary


static func _default_scenario_state() -> Dictionary:
	return {"enabled": true, "status": STATUS_NOT_STARTED}


static func _normalize_status(status: String) -> String:
	if status in [STATUS_NOT_STARTED, STATUS_IN_PROGRESS, STATUS_COMPLETED, STATUS_SKIPPED]:
		return status
	return STATUS_NOT_STARTED
