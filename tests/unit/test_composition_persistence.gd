class_name TestCompositionPersistence
extends RefCounted

const MIXED_ID := &"fixture_mixed_card"
const FIXTURE = preload("res://tests/fixtures/mixed_composition_card.tres")

class FailedOperations extends RosterFileOperations:
	var stage: String
	func write_text(path: String, value: String) -> Error:
		return ERR_FILE_CANT_WRITE if stage == "write" else super.write_text(path, value)
	func copy_file(source: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if stage == "backup" else super.copy_file(source, destination)
	func replace_file(source: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if stage == "replace" else super.replace_file(source, destination)

class FailingHost extends SimulationHost:
	var fail_writes := true
	var saved_record: Dictionary = {}
	func _write_campaign_record(record: Dictionary) -> bool:
		if fail_writes:
			_set_campaign_error(&"ROSTER_SAVE_FAILED", "SIMULATED write failure")
			return false
		saved_record = record.duplicate(true)
		_set_campaign_error(&"", "")
		return true


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_definitions(failures)
	_test_mixed_lifecycle(failures)
	_test_safe_files(failures)
	_test_host_retry(failures)
	return failures


static func mixed_world(deployed: bool = true, reverse_entries: bool = false) -> SimulationWorld:
	var world := SimulationWorld.new(false, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	world.battle_definition = world.battle_definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as BattleDefinition
	var battle := world.battle_definition
	battle.support_for_kind(SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT).strength = 1
	var mixed := FIXTURE.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as UnitCardDefinition
	if reverse_entries:
		mixed.composition.reverse()
	for index in range(battle.unit_card_definitions.size()):
		if battle.unit_card_definitions[index].definition_id == &"ironwall_assault_group":
			mixed.command_cost = battle.unit_card_definitions[index].command_cost
			battle.unit_card_definitions[index] = mixed
			break
	battle.default_commander_by_unit_card[MIXED_ID] = battle.default_commander_by_unit_card[&"ironwall_assault_group"]
	battle.default_commander_by_unit_card.erase(&"ironwall_assault_group")
	var starters := battle.default_starting_unit_card_ids
	var replaced := starters.find(&"ironwall_assault_group")
	if replaced >= 0:
		starters[replaced] = MIXED_ID
	if deployed and not starters.has(MIXED_ID):
		starters[0] = MIXED_ID
	elif not deployed and starters.has(MIXED_ID):
		for card in battle.unit_card_definitions:
			if card.definition_id != MIXED_ID and not starters.has(card.definition_id):
				starters[starters.find(MIXED_ID)] = card.definition_id
				break
	world.grey_ridge_army_plan = battle.create_default_army_plan()
	world.doctrine_definitions = battle.doctrine_dictionary()
	world._setup_grey_ridge_scenario()
	world._update_faction_knowledge()
	return world


func _test_definitions(failures: Array[String]) -> void:
	var card := FIXTURE.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as UnitCardDefinition
	_expect(UnitCardCompositionCompiler.validate(card, SimulationWorld.UNIT_CATALOG).is_valid(), "typed mixed fixture validates", failures)
	var compiled := UnitCardCompositionCompiler.compile(card)
	card.composition[0].authorized_count = 99
	_expect(compiled[0].authorized_count == 8, "compiled entries own values", failures)
	_expect(not UnitCardCompositionCompiler.validate(card, SimulationWorld.UNIT_CATALOG).is_valid(), "mismatched total refused", failures)
	card.composition[0].authorized_count = 8
	card.composition[1].entry_id = card.composition[0].entry_id
	_expect(not UnitCardCompositionCompiler.validate(card, SimulationWorld.UNIT_CATALOG).is_valid(), "duplicate entry identity refused", failures)
	card.composition[1].entry_id = &"engineers"
	card.composition[1].unit_definition_id = &"unknown"
	_expect(not UnitCardCompositionCompiler.validate(card, SimulationWorld.UNIT_CATALOG).is_valid(), "unknown unit refused", failures)


func _test_mixed_lifecycle(failures: Array[String]) -> void:
	var world := mixed_world()
	var card := world.unit_cards[MIXED_ID] as UnitCardState
	var initial := world.create_snapshot().get_unit_card(MIXED_ID)
	_expect(initial.get_composition_entry(&"assault").current_strength == 8 and initial.get_composition_entry(&"engineers").current_strength == 4, "initial deployment preserves both unit types", failures)
	var engineers := card.get_composition_entry(&"engineers")
	var assault := card.get_composition_entry(&"assault")
	(world.units[engineers.member_entity_ids[0]] as UnitState).enabled = false
	(world.units[assault.member_entity_ids[0]] as UnitState).enabled = false
	_expect(initial.get_composition_entry(&"engineers").current_strength == 4, "old composition snapshot remains unchanged", failures)
	var takeover := UnitCardControlCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, MIXED_ID, UnitCardControlCommand.Action.TAKEOVER)
	_expect(world.submit_command(takeover).is_accepted(), "mixed whole-card takeover accepted", failures)
	world.advance_tick()
	world._refresh_battle_population()
	var reinforcement := SupportOrderCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"", &"", MIXED_ID)
	_expect(world.submit_command(reinforcement).is_accepted(), "mixed reinforcement passes shared validation", failures)
	world.advance_tick()
	_expect(engineers.active_count(world.units) == 4 and assault.active_count(world.units) == 7, "single field replacement follows entry priority and unit type (engineers=%d assault=%d)" % [engineers.active_count(world.units), assault.active_count(world.units)], failures)
	var handoff := UnitCardControlCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, MIXED_ID, UnitCardControlCommand.Action.RETURN_TO_COMMANDER)
	_expect(world.submit_command(handoff).is_accepted(), "mixed whole-card return accepted", failures)
	world.advance_tick()
	var departure := world.strategic_regions[world.battle_definition.withdrawal_region_id] as StrategicRegionState
	var withdraw := CommanderOrderCommand.new(world.allocate_command_id(), 1, world.current_tick, card.commander_definition_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, departure.position, departure.region_id)
	_expect(world.submit_command(withdraw).is_accepted(), "mixed withdrawal objective passes shared validation", failures)
	for entity_id in card.member_entity_ids:
		var unit := world.units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			unit.position = departure.position
	world.advance_tick()
	_expect(card.deployment_state == UnitCardState.DeploymentState.WITHDRAWN, "mixed card withdraws through normal arrival processing", failures)
	var record := ArmyRosterStore.build_battle_record(world.create_snapshot(), {}, &"black_well")
	_expect(ArmyRosterMigration.normalize(record).is_success(), "mixed withdrawal creates valid v4 record", failures)
	var restored := mixed_world(true, true)
	_expect(ArmyRosterStore.apply_to_world(restored, record), "reordered definition restores by entry identity", failures)
	var restored_card := restored.create_snapshot().get_unit_card(MIXED_ID)
	_expect(restored_card.get_composition_entry(&"assault").current_strength == 7 and restored_card.get_composition_entry(&"engineers").current_strength == 4, "withdrawal and restoration retain per-type survivors", failures)
	var reserve_world := mixed_world(false)
	_expect(ArmyRosterStore.apply_to_world(reserve_world, record), "reserve mixed record accepted", failures)
	var reserve_card := reserve_world.unit_cards[MIXED_ID] as UnitCardState
	var deploy := DeployUnitCardCommand.new(reserve_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, reserve_world.current_tick, MIXED_ID, reserve_world.battle_definition.player_headquarters_position + Vector2(128, 0))
	var deploy_result := reserve_world.submit_command(deploy)
	_expect(deploy_result.is_accepted(), "mixed reserve deployment passes shared validation (reason=%s)" % CommandValidationResult.Reason.keys()[deploy_result.reason], failures)
	for _tick in range(reserve_card.definition.deployment_ticks + 2):
		reserve_world.advance_tick()
	var deployed := reserve_world.create_snapshot().get_unit_card(MIXED_ID)
	_expect(deployed.get_composition_entry(&"assault").current_strength == 7 and deployed.get_composition_entry(&"engineers").current_strength == 4, "reserve deployment uses entry availability", failures)
	record["replacement_points"] = 100
	_expect(ArmyRosterStore.replenish_card(record, MIXED_ID), "campaign replenishment accepted", failures)
	_expect(int(record.cards[String(MIXED_ID)].composition.assault.available_strength) == 8, "campaign replacement fills actual assault gap", failures)
	var capability_world := mixed_world()
	var capability_card := capability_world.unit_cards[MIXED_ID] as UnitCardState
	_expect(capability_world.create_snapshot().get_unit_card(MIXED_ID).has_active_unit_type(&"engineer_vehicle"), "mixed card exposes live engineer capability", failures)
	for entity_id in capability_card.get_composition_entry(&"engineers").member_entity_ids:
		(capability_world.units[entity_id] as UnitState).enabled = false
	_expect(not capability_card.has_active_unit_type(&"engineer_vehicle", capability_world.units) and not capability_world.create_snapshot().get_unit_card(MIXED_ID).has_active_unit_type(&"engineer_vehicle"), "losing all engineers removes capability from authority and UI snapshot", failures)


func _test_safe_files(failures: Array[String]) -> void:
	var directory := "user://warseed_composition_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/roster.json"
	var baseline := ArmyRosterStore.build_battle_record(SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE).create_snapshot())
	var loss_card: Dictionary = baseline.cards.ironwall_assault_group
	loss_card["available_strength"] = 9
	loss_card["cumulative_losses"] = 17
	loss_card["last_battle_losses"] = 3
	loss_card["honor_id"] = "collective_commendation"
	loss_card["equipment_id"] = "reinforced_side_skirts"
	loss_card["organization"] = 43.25
	loss_card.composition.main["available_strength"] = 9
	loss_card.composition.main["cumulative_losses"] = 17
	loss_card.composition.main["last_battle_losses"] = 3
	for version in [1, 2, 3]:
		var legacy := baseline.duplicate(true)
		legacy["format_version"] = version
		legacy.erase("content_version")
		for card in legacy.cards.values():
			card.erase("composition")
		_write(path, JSON.stringify(legacy))
		var original := FileAccess.get_sha256(path)
		var migrated := ArmyRosterStore.load_record_result(path)
		_expect(migrated.status == ArmyRosterResult.Status.MIGRATED and FileAccess.get_sha256(migrated.backup_path) == original, "v%d migration preserves exact backup" % version, failures)
		var migrated_card: Dictionary = migrated.record.cards.ironwall_assault_group
		_expect(migrated_card.composition.main.available_strength == 9 and migrated_card.composition.main.cumulative_losses == 17, "v%d migration does not gift troops or reset losses" % version, failures)
		_expect(migrated_card.honor_id == loss_card.honor_id and migrated_card.equipment_id == loss_card.equipment_id and migrated_card.organization == loss_card.organization, "v%d migration retains attachments and organization" % version, failures)
		_expect(ArmyRosterStore.load_record_result(path).status == ArmyRosterResult.Status.LOADED, "v4 reload does not repeat migration", failures)
	for malformed in ["{", '{"format_version":99,"cards":{}}', '{"format_version":3,"cards":{"x":{"authorized_strength":-1,"available_strength":0}}}']:
		_write(path, malformed)
		var original := FileAccess.get_sha256(path)
		_expect(ArmyRosterStore.load_record_result(path).status == ArmyRosterResult.Status.FAILED, "invalid file fails explicitly", failures)
		_expect(not ArmyRosterStore.save_record_result(baseline, path).is_success() and FileAccess.get_sha256(path) == original, "invalid original cannot be overwritten with a fresh roster", failures)
	var host := SimulationHost.new()
	host.scenario_kind = SimulationWorld.ScenarioKind.GREY_RIDGE
	host.world = SimulationWorld.new(true, false, host.scenario_kind)
	host.current_snapshot = host.world.create_snapshot()
	host._grey_ridge_battle_started = false
	var original_hash := FileAccess.get_sha256(path)
	_expect(not host._load_campaign_roster(path) and host.has_campaign_error(), "host distinguishes invalid roster from a new army", failures)
	_expect(not host.start_grey_ridge(host.world.grey_ridge_army_plan) and not host.retry_campaign_save(), "invalid roster prevents starting and cannot be overwritten by retry", failures)
	var status := RosterStatusPanel.new()
	status.configure(host)
	_expect(status.visible and not status.retry_button.visible and status.message.text == GameText.t(&"ROSTER_LOAD_FAILED"), "load failure is visible and cannot masquerade as a save retry", failures)
	_expect(FileAccess.get_sha256(path) == original_hash, "blocked host preserves original bytes", failures)
	status.free()
	host.free()
	_write(path, JSON.stringify(baseline))
	for stage in ["write", "backup", "replace"]:
		var operations := FailedOperations.new()
		operations.stage = stage
		var original := FileAccess.get_sha256(path)
		_expect(not ArmyRosterStore.save_record_result(baseline, path, operations).is_success() and FileAccess.get_sha256(path) == original, "%s failure leaves original bytes intact" % stage, failures)
	var mixed_record := ArmyRosterStore.build_battle_record(mixed_world().create_snapshot())
	_expect(ArmyRosterStore.save_record_result(mixed_record, path).is_success(), "mixed v4 saves atomically over valid existing roster", failures)
	var reloaded := ArmyRosterStore.load_record_result(path)
	_expect(reloaded.record == mixed_record, "mixed v4 round-trips", failures)
	for malformed_field in ["available_strength", "unit_definition_id", "replacement_priority"]:
		var invalid := baseline.duplicate(true)
		invalid.cards.ironwall_assault_group.composition.main[malformed_field] = "invalid"
		_expect(not ArmyRosterMigration.normalize(invalid).is_success(), "invalid entry field type is rejected: " + malformed_field, failures)
	var mismatch := baseline.duplicate(true)
	mismatch.cards.ironwall_assault_group.composition.main.unit_definition_id = "engineer_vehicle"
	_expect(not ArmyRosterMigration.normalize(mismatch).is_success(), "known card cannot silently change unit type", failures)
	var future := ArmyRosterMigration.normalize({"format_version": 99, "cards": {}})
	_expect(not future.is_success() and future.source_version == 99, "future format error retains source version", failures)
	var files := DirAccess.open(directory)
	for filename in files.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


func _test_host_retry(failures: Array[String]) -> void:
	var host := FailingHost.new()
	host.scenario_kind = SimulationWorld.ScenarioKind.GREY_RIDGE
	host.world = SimulationWorld.new(true, false, host.scenario_kind)
	host.current_snapshot = host.world.create_snapshot()
	host._campaign_record = ArmyRosterStore.build_battle_record(host.current_snapshot)
	host._campaign_record.replacement_points = 100
	host._campaign_record.merit = 100
	var original := host.get_campaign_record()
	_expect(not host.apply_unit_card_growth(&"ironwall_assault_group", &"collective_commendation") and host.get_campaign_record() == original, "failed growth purchase rolls back both reward and cost", failures)
	host.fail_writes = false
	_expect(host.retry_campaign_save() and not host.has_campaign_error() and host.saved_record == original, "purchase retry restores persistence without granting the rejected purchase", failures)
	var damaged: Dictionary = host._campaign_record.cards.ironwall_assault_group
	damaged.available_strength = 10
	damaged.composition.main.available_strength = 10
	original = host.get_campaign_record()
	host.fail_writes = true
	_expect(host.replenish_unit_card_as_much_as_possible(&"ironwall_assault_group") == 0 and host.get_campaign_record() == original, "failed replenishment rolls back all troops and spending", failures)
	host.fail_writes = false
	_expect(host.retry_campaign_save() and host.get_campaign_record() == original, "replenishment retry does not replay the failed purchase", failures)
	host._campaign_record = {}
	host._start_playtest_session()
	host.fail_writes = true
	(host.world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState).health = 0.0
	host.world.advance_tick()
	host.current_snapshot = host.world.create_snapshot()
	host._save_campaign_result_if_finished()
	original = host.get_campaign_record()
	_expect(host._campaign_save_pending and original.get("battle_count", 0) == 1, "terminal battle retains exactly one unsaved result", failures)
	host._save_campaign_result_if_finished()
	_expect(not host.retry_campaign_save() and host.get_campaign_record() == original, "repeated save failure does not duplicate the result", failures)
	host.fail_writes = false
	_expect(host.retry_campaign_save() and not host._campaign_save_pending and host.saved_record == original, "successful retry saves exactly the retained reward", failures)
	host._save_campaign_result_if_finished()
	_expect(host.get_campaign_record() == original, "retry success does not conclude the battle twice", failures)
	host.free()


func _write(path: String, payload: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(payload)
	file.close()


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("composition/persistence: " + message)
