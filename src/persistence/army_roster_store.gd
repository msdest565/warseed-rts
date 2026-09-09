class_name ArmyRosterStore
extends RefCounted

const FORMAT_VERSION := 3
const GROWTH_CATALOG = preload("res://data/army/growth_catalog.tres")
const GROWTH_KIND_HONOR := 0
const GROWTH_KIND_EQUIPMENT := 1
const DEFAULT_PATH := "user://grey_ridge_roster.json"
const DEFAULT_PLAYTEST_DIRECTORY := "user://playtests"
const ISOLATED_PLAYTEST_ROOT := "user://playtest_runs"
const PLAYTEST_SESSION_ARGUMENT := "--playtest-session"
const ALLOW_TEST_CAMPAIGN_PERSISTENCE_ARGUMENT := "--allow-test-campaign-persistence"
const MAX_PLAYTEST_SESSION_ID_LENGTH := 40
const VICTORY_REPLACEMENT_AWARD := 12
const DEFEAT_REPLACEMENT_AWARD := 8
const VICTORY_MERIT_AWARD := 3
const DEFEAT_MERIT_AWARD := 1
const ORDERED_WITHDRAWAL_REPLACEMENT_AWARD := 10
const ORDERED_WITHDRAWAL_MERIT_AWARD := 2
const BASE_REPLACEMENT_COST := 2
const HONORED_REPLACEMENT_COST_MODIFIER := 1
const COLLECTIVE_COMMENDATION_MERIT_COST := 3
const REINFORCED_SKIRTS_REPLACEMENT_COST := 6
const REINFORCED_SKIRTS_REFIT_DAYS := 2
const HONOR_COLLECTIVE_COMMENDATION := "collective_commendation"
const EQUIPMENT_REINFORCED_SIDE_SKIRTS := "reinforced_side_skirts"


static func build_battle_record(snapshot: WorldSnapshot, previous_record: Dictionary = {}, scenario_id: StringName = &"grey_ridge") -> Dictionary:
	previous_record = _normalize_record(previous_record)
	var previous_cards := previous_record.get("cards", {}) as Dictionary
	var cards: Dictionary = previous_cards.duplicate(true)
	for card in snapshot.unit_cards:
		if card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			continue
		var previous := previous_cards.get(String(card.definition_id), {}) as Dictionary
		var starting_strength := int(previous.get("available_strength", card.authorized_strength))
		var available_strength := card.current_strength
		if card.deployment_state in [UnitCardState.DeploymentState.RESERVE, UnitCardState.DeploymentState.DEPLOYING]:
			available_strength = starting_strength
		var battle_losses := maxi(0, starting_strength - available_strength)
		cards[String(card.definition_id)] = {
			"authorized_strength": card.authorized_strength,
			"available_strength": available_strength,
			"last_battle_losses": battle_losses,
			"cumulative_losses": int(previous.get("cumulative_losses", 0)) + battle_losses,
			"battles_survived": int(previous.get("battles_survived", 0)) + 1,
			"honor_id": String(previous.get("honor_id", "")),
			"equipment_id": String(previous.get("equipment_id", "")),
			"last_refit_days": 0,
			"organization": card.organization if card.organization_enabled else float(previous.get("organization", 100.0)),
			"last_status": _card_battle_status(card),
			"last_scenario_id": String(scenario_id),
		}
	var player := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var result_key := "victory" if player != null and player.victorious else "defeat"
	var outcome_grade := "none"
	var outcome_reason := ""
	if snapshot.outcome != null and snapshot.outcome.is_terminal():
		result_key = String(snapshot.outcome.result_key())
		outcome_grade = String(snapshot.outcome.grade_key())
		outcome_reason = String(snapshot.outcome.conclusion_group_id)
	var replacement_award := DEFEAT_REPLACEMENT_AWARD
	var merit_award := DEFEAT_MERIT_AWARD
	if result_key == "victory":
		replacement_award = VICTORY_REPLACEMENT_AWARD
		merit_award = VICTORY_MERIT_AWARD
	elif result_key == "ordered_withdrawal":
		replacement_award = ORDERED_WITHDRAWAL_REPLACEMENT_AWARD
		merit_award = ORDERED_WITHDRAWAL_MERIT_AWARD
	return {
		"format_version": FORMAT_VERSION,
		"scenario_id": String(scenario_id),
		"last_scenario_id": String(scenario_id),
		"battle_count": int(previous_record.get("battle_count", 0)) + 1,
		"last_result": result_key,
		"last_outcome_grade": outcome_grade,
		"last_outcome_reason": outcome_reason,
		"replacement_points": int(previous_record.get("replacement_points", 0)) + replacement_award,
		"merit": int(previous_record.get("merit", 0)) + merit_award,
		"campaign_days": int(previous_record.get("campaign_days", 0)),
		"last_replacement_award": replacement_award,
		"last_merit_award": merit_award,
		"cards": cards,
	}


static func apply_to_world(world: SimulationWorld, record: Dictionary) -> void:
	if record.is_empty():
		return
	var records := record.get("cards", {}) as Dictionary
	for unit_card_id in world.unit_cards:
		var card := world.unit_cards[unit_card_id] as UnitCardState
		if card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			continue
		var card_record := records.get(String(unit_card_id), {}) as Dictionary
		if card_record.is_empty():
			continue
		card.cumulative_losses = maxi(0, int(card_record.get("cumulative_losses", 0)))
		card.battles_survived = maxi(0, int(card_record.get("battles_survived", 0)))
		card.honor_id = StringName(card_record.get("honor_id", ""))
		card.equipment_id = StringName(card_record.get("equipment_id", ""))
		if card.organization_enabled and world.battle_definition != null:
			card.organization = clampf(float(card_record.get("organization", world.battle_definition.organization_max)), 0.0, world.battle_definition.organization_max)
		var available_strength := clampi(
			int(card_record.get("available_strength", card.definition.authorized_strength)),
			0,
			card.definition.authorized_strength
		)
		card.available_strength = available_strength
		_prune_card_to_strength(world, card, available_strength)
		world.apply_unit_card_persistent_modifiers(card)
		world.refresh_unit_card_organization_baseline(card)


static func replacement_cost(record: Dictionary, unit_card_id: StringName) -> int:
	var card := _get_card_record(record, unit_card_id)
	if card.is_empty():
		return 0
	var modifier := 0
	for growth_id in [StringName(card.get("honor_id", "")), StringName(card.get("equipment_id", ""))]:
		var growth: Variant = GROWTH_CATALOG.get_growth(growth_id)
		if growth != null:
			modifier += growth.replacement_cost_modifier
	return maxi(1, BASE_REPLACEMENT_COST + modifier)


static func replenish_card(record: Dictionary, unit_card_id: StringName) -> bool:
	var card := _get_card_record(record, unit_card_id)
	if card.is_empty():
		return false
	var available := int(card.get("available_strength", 0))
	var authorized := int(card.get("authorized_strength", 0))
	var cost := replacement_cost(record, unit_card_id)
	if available >= authorized or cost <= 0 or int(record.get("replacement_points", 0)) < cost:
		return false
	card["available_strength"] = available + 1
	card["last_refit_days"] = int(card.get("last_refit_days", 0)) + 1
	record["replacement_points"] = int(record.get("replacement_points", 0)) - cost
	record["campaign_days"] = int(record.get("campaign_days", 0)) + 1
	return true


static func replenish_card_as_much_as_possible(record: Dictionary, unit_card_id: StringName) -> int:
	var restored := 0
	while replenish_card(record, unit_card_id):
		restored += 1
	return restored


static func affordable_replacements(record: Dictionary, unit_card_id: StringName) -> int:
	var card := _get_card_record(record, unit_card_id)
	if card.is_empty():
		return 0
	var cost := replacement_cost(record, unit_card_id)
	if cost <= 0:
		return 0
	var missing := maxi(0, int(card.get("authorized_strength", 0)) - int(card.get("available_strength", 0)))
	return mini(missing, int(record.get("replacement_points", 0)) / cost)


static func archive_record(path: String = DEFAULT_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var absolute_path := ProjectSettings.globalize_path(path)
	var archive_path := "%s.backup-%d.json" % [absolute_path.trim_suffix(".json"), Time.get_unix_time_from_system()]
	if DirAccess.rename_absolute(absolute_path, archive_path) != OK:
		return ""
	return archive_path


static func award_collective_commendation(record: Dictionary, unit_card_id: StringName) -> bool:
	return apply_growth(record, unit_card_id, HONOR_COLLECTIVE_COMMENDATION)


static func install_reinforced_side_skirts(record: Dictionary, unit_card_id: StringName) -> bool:
	return apply_growth(record, unit_card_id, EQUIPMENT_REINFORCED_SIDE_SKIRTS)


static func apply_growth(record: Dictionary, unit_card_id: StringName, growth_id: StringName) -> bool:
	var card := _get_card_record(record, unit_card_id)
	var growth: Variant = GROWTH_CATALOG.get_growth(growth_id)
	if card.is_empty() or growth == null:
		return false
	var slot_key := "honor_id" if growth.kind == GROWTH_KIND_HONOR else "equipment_id"
	if not String(card.get(slot_key, "")).is_empty():
		return false
	if growth.kind == GROWTH_KIND_HONOR and int(card.get("battles_survived", 0)) < 1:
		return false
	if int(record.get("merit", 0)) < growth.merit_cost or int(record.get("replacement_points", 0)) < growth.replacement_cost:
		return false
	card[slot_key] = String(growth.definition_id)
	card["last_refit_days"] = int(card.get("last_refit_days", 0)) + growth.refit_days
	record["merit"] = int(record.get("merit", 0)) - growth.merit_cost
	record["replacement_points"] = int(record.get("replacement_points", 0)) - growth.replacement_cost
	record["campaign_days"] = int(record.get("campaign_days", 0)) + growth.refit_days
	return true


static func can_apply_growth(record: Dictionary, unit_card_id: StringName, growth_id: StringName) -> bool:
	var copy := record.duplicate(true)
	return apply_growth(copy, unit_card_id, growth_id)


static func _get_card_record(record: Dictionary, unit_card_id: StringName) -> Dictionary:
	var cards := record.get("cards", {}) as Dictionary
	return cards.get(String(unit_card_id), {}) as Dictionary


static func _prune_card_to_strength(world: SimulationWorld, card: UnitCardState, available_strength: int) -> void:
	var surviving_ids: Array[int] = []
	for entity_id in card.member_entity_ids:
		var unit := world.units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			surviving_ids.append(entity_id)
	surviving_ids.sort()
	while surviving_ids.size() > available_strength:
		surviving_ids.pop_back()
	for entity_id in card.member_entity_ids:
		if surviving_ids.has(entity_id):
			continue
		world.units.erase(entity_id)
		if world.formations.has(card.formation_id):
			(world.formations[card.formation_id] as FormationState).remove_member(entity_id)
	if world.formations.has(card.formation_id):
		var formation := world.formations[card.formation_id] as FormationState
		if formation.member_entity_ids.is_empty():
			world.formations.erase(card.formation_id)
			card.formation_id = 0


static func save_record(record: Dictionary, path: String = DEFAULT_PATH) -> bool:
	record = _normalize_record(record)
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record, "\t"))
	return file.get_error() == OK


static func load_record(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var record := parsed as Dictionary
	if int(record.get("format_version", 0)) not in [1, 2, FORMAT_VERSION]:
		return {}
	return _normalize_record(record)


static func _normalize_record(source: Dictionary) -> Dictionary:
	var record := source.duplicate(true)
	if record.is_empty():
		return record
	record["format_version"] = FORMAT_VERSION
	record["replacement_points"] = maxi(0, int(record.get("replacement_points", 0)))
	record["merit"] = maxi(0, int(record.get("merit", 0)))
	record["campaign_days"] = maxi(0, int(record.get("campaign_days", 0)))
	record["last_replacement_award"] = maxi(0, int(record.get("last_replacement_award", 0)))
	record["last_merit_award"] = maxi(0, int(record.get("last_merit_award", 0)))
	var cards := record.get("cards", {}) as Dictionary
	for key in cards:
		var card := cards[key] as Dictionary
		card["honor_id"] = String(card.get("honor_id", ""))
		card["equipment_id"] = String(card.get("equipment_id", ""))
		card["last_refit_days"] = maxi(0, int(card.get("last_refit_days", 0)))
		card["organization"] = clampf(float(card.get("organization", 100.0)), 0.0, 100.0)
		card["last_status"] = String(card.get("last_status", "unknown"))
		card["last_scenario_id"] = String(card.get("last_scenario_id", record.get("scenario_id", "")))
	return record


static func runtime_persistence_allowed() -> bool:
	return runtime_persistence_allowed_for_arguments(
		OS.get_cmdline_args(),
		OS.get_cmdline_user_args()
	)


static func runtime_persistence_allowed_for_arguments(
	engine_arguments: PackedStringArray,
	user_arguments: PackedStringArray
) -> bool:
	var runs_test_script := false
	for argument in engine_arguments:
		if String(argument).contains("res://tests/"):
			runs_test_script = true
			break
	if not runs_test_script:
		return true
	if not user_arguments.has(ALLOW_TEST_CAMPAIGN_PERSISTENCE_ARGUMENT):
		return false
	return not playtest_session_id_from_arguments(user_arguments).is_empty()


static func active_playtest_session_id() -> String:
	return playtest_session_id_from_arguments(OS.get_cmdline_user_args())


static func playtest_session_id_from_arguments(arguments: PackedStringArray) -> String:
	for argument in arguments:
		var value := String(argument)
		if value == PLAYTEST_SESSION_ARGUMENT:
			return "unnamed"
		if value.begins_with(PLAYTEST_SESSION_ARGUMENT + "="):
			return normalize_playtest_session_id(value.trim_prefix(PLAYTEST_SESSION_ARGUMENT + "="))
	return ""


static func normalize_playtest_session_id(value: String) -> String:
	var normalized := ""
	var previous_was_separator := false
	for index in range(value.length()):
		var character := value.substr(index, 1).to_lower()
		var accepted := (character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["_", "-"]
		if accepted:
			normalized += character
			previous_was_separator = character == "_"
		elif not normalized.is_empty() and not previous_was_separator:
			normalized += "_"
			previous_was_separator = true
	while normalized.begins_with("_") or normalized.begins_with("-"):
		normalized = normalized.substr(1)
	while normalized.ends_with("_") or normalized.ends_with("-"):
		normalized = normalized.left(-1)
	if normalized.is_empty():
		return "unnamed"
	normalized = normalized.left(MAX_PLAYTEST_SESSION_ID_LENGTH)
	while normalized.ends_with("_") or normalized.ends_with("-"):
		normalized = normalized.left(-1)
	return normalized if not normalized.is_empty() else "unnamed"


static func campaign_record_path_for_session(session_id: String, scenario_id: StringName = &"grey_ridge") -> String:
	var filename := "grey_ridge_roster.json"
	if session_id.is_empty():
		return "user://%s" % filename
	return "%s/%s/%s" % [ISOLATED_PLAYTEST_ROOT, normalize_playtest_session_id(session_id), filename]


static func _card_battle_status(card: UnitCardSnapshot) -> String:
	match card.deployment_state:
		UnitCardState.DeploymentState.WITHDRAWN:
			return "withdrawn"
		UnitCardState.DeploymentState.RESERVE, UnitCardState.DeploymentState.DEPLOYING:
			return "reserve"
		UnitCardState.DeploymentState.DEPLOYED:
			return "survived" if card.current_strength > 0 else "destroyed"
	return "disabled"


static func playtest_record_directory_for_session(session_id: String) -> String:
	if session_id.is_empty():
		return DEFAULT_PLAYTEST_DIRECTORY
	return "%s/%s/playtests" % [ISOLATED_PLAYTEST_ROOT, normalize_playtest_session_id(session_id)]
