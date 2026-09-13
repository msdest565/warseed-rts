extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var evidence: Array[Dictionary] = []
	for path in TestTacticalCards.CARD_PATHS:
		var definition := load(path) as UnitCardDefinition
		var world := TestTacticalCards.sample_world()
		TestTacticalCards._quiet(world)
		var card := world.unit_cards[definition.definition_id] as UnitCardState
		var original := world.create_snapshot().get_unit_card(definition.definition_id)
		var take := UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick, definition.definition_id, UnitCardControlCommand.Action.TAKEOVER)
		_expect(world.submit_command(take).is_accepted(), "whole-card takeover: " + String(definition.definition_id))
		world.advance_tick()
		var back := UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick, definition.definition_id, UnitCardControlCommand.Action.RETURN_TO_COMMANDER)
		_expect(world.submit_command(back).is_accepted(), "whole-card handback: " + String(definition.definition_id))
		world.advance_tick()
		var casualty := world.units[card.member_entity_ids.back()] as UnitState
		casualty.enabled = false
		var region := world.strategic_regions[world.battle_definition.withdrawal_region_id] as StrategicRegionState
		var withdraw := CommanderOrderCommand.new(world.allocate_command_id(), 1, world.current_tick, card.commander_definition_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, region.position, region.region_id)
		_expect(world.submit_command(withdraw).is_accepted(), "withdrawal objective: " + String(definition.definition_id))
		for id in card.member_entity_ids:
			var unit := world.units[id] as UnitState
			if unit.enabled:
				unit.position = region.position
		world.advance_tick()
		_expect(card.deployment_state == UnitCardState.DeploymentState.WITHDRAWN, "all survivors withdraw: " + String(definition.definition_id))
		var record := ArmyRosterStore.build_battle_record(world.create_snapshot(), {}, &"black_well")
		var save_path := "res://artifacts/tactical-roster-%s.json" % definition.definition_id
		_expect(ArmyRosterStore.save_record_result(record, save_path).is_success(), "v4 atomic save: " + String(definition.definition_id))
		var loaded := ArmyRosterStore.load_record_result(save_path)
		_expect(loaded.is_success(), "v4 load: " + String(definition.definition_id))
		var restored := TestTacticalCards.sample_world()
		restored.battle_definition.default_starting_unit_card_ids.erase(definition.definition_id)
		restored.battle_definition.starting_card_count = 4
		restored.grey_ridge_army_plan = restored.battle_definition.create_default_army_plan()
		restored._setup_grey_ridge_scenario()
		TestTacticalCards._quiet(restored)
		_expect(ArmyRosterStore.apply_to_world(restored, loaded.record), "restore new card by stable composition identity")
		var reserve := restored.unit_cards[definition.definition_id] as UnitCardState
		_expect(reserve.deployment_state == UnitCardState.DeploymentState.RESERVE and reserve.available_strength == definition.authorized_strength - 1, "reserve retains losses")
		var deploy := DeployUnitCardCommand.new(restored.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, restored.current_tick, definition.definition_id, restored.battle_definition.player_headquarters_position + Vector2(128, 0))
		var accepted := restored.submit_command(deploy)
		_expect(accepted.is_accepted(), "normal reserve deployment: %s %s" % [definition.definition_id, accepted.describe()])
		for tick in range(definition.deployment_ticks + 2):
			restored.advance_tick()
		var deployed := restored.create_snapshot().get_unit_card(definition.definition_id)
		_expect(deployed.current_strength == definition.authorized_strength - 1 and deployed.tactical_ability_id == original.tactical_ability_id, "restored survivors retain intrinsic action")
		_expect(original.current_strength == definition.authorized_strength, "initial card snapshot remains unchanged")
		evidence.append({"card": String(definition.definition_id), "initial": original.current_strength, "restored": deployed.current_strength, "format": loaded.record.get("format_version", 0), "save": save_path})
	var report := {"evidence_source": "SIMULATED", "cards": evidence, "failures": failures}
	var file := FileAccess.open("res://artifacts/r3-004-lifecycle.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for failure in failures:
		push_error(failure)
	print("WARSEED_TACTICAL_LIFECYCLE cards=%d failures=%d" % [evidence.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
