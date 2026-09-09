extends SceneTree

const REPORT_PATH := "res://artifacts/release_balance_matrix.json"
const BALANCE_WINDOW_TICKS := 200
const STRATEGY_IDS: Array[StringName] = [
	&"recommended",
	&"conservative",
	&"intel_first",
	&"resource_greedy",
	&"no_intervention",
	&"deliberate_failure",
]
const SCENARIOS := [
	{"id": &"grey_ridge", "kind": SimulationWorld.ScenarioKind.GREY_RIDGE},
	{"id": &"broken_bridge", "kind": SimulationWorld.ScenarioKind.BROKEN_BRIDGE},
	{"id": &"fog_forest", "kind": SimulationWorld.ScenarioKind.FOG_FOREST},
	{"id": &"black_well", "kind": SimulationWorld.ScenarioKind.BLACK_WELL},
]


func _initialize() -> void:
	var failures: Array[String] = []
	var cases: Array[Dictionary] = []
	var freeze_manifest: Dictionary = {}
	for scenario in SCENARIOS:
		var scenario_id := scenario["id"] as StringName
		var kind := int(scenario["kind"]) as SimulationWorld.ScenarioKind
		var load_result := BattleContentLoader.load_battle(scenario_id)
		if not load_result.is_valid():
			failures.append("%s content failed validation" % scenario_id)
			continue
		var battle := load_result.battle
		freeze_manifest[String(scenario_id)] = _battle_contract(battle)
		for plan in battle.enemy_plans:
			for strategy_id in STRATEGY_IDS:
				cases.append(_run_case(kind, scenario_id, plan.plan_id, strategy_id, failures))

	var report := {
		"format_version": 1,
		"generated_unix_time": int(Time.get_unix_time_from_system()),
		"engine_version": String(Engine.get_version_info().get("string", "unknown")),
		"balance_window_ticks": BALANCE_WINDOW_TICKS,
		"scenario_count": SCENARIOS.size(),
		"strategy_count_per_plan": STRATEGY_IDS.size(),
		"case_count": cases.size(),
		"strategy_ids": _string_names(STRATEGY_IDS),
		"persistence_contract": {
			"army_roster_format": ArmyRosterStore.FORMAT_VERSION,
			"tutorial_progress_format": TutorialProgressStore.FORMAT_VERSION,
			"playtest_record_format": PlaytestSessionRecorder.FORMAT_VERSION,
		},
		"content_contract": freeze_manifest,
		"cases": cases,
		"passed": failures.is_empty(),
		"failures": failures,
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write release balance report: %s" % FileAccess.get_open_error())
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if failures.is_empty():
		print("WARSEED_RELEASE_BALANCE passed: %d scenarios x 3 plans x %d strategies = %d cases report=%s" % [SCENARIOS.size(), STRATEGY_IDS.size(), cases.size(), REPORT_PATH])
		quit(0)
		return
	for failure in failures:
		push_error("RELEASE BALANCE FAILED: %s" % failure)
	quit(1)


func _run_case(kind: SimulationWorld.ScenarioKind, scenario_id: StringName, plan_id: StringName, strategy_id: StringName, failures: Array[String]) -> Dictionary:
	var world := SimulationWorld.new(true, false, kind, {}, plan_id)
	var commands := {"accepted": 0, "rejected": 0, "reasons": []}
	_issue_strategy(world, scenario_id, strategy_id, commands)
	for tick in range(BALANCE_WINDOW_TICKS):
		_issue_followup(world, scenario_id, strategy_id, tick, commands)
		world.advance_tick()
		var player := world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
		if player.defeated or player.victorious:
			break
	var accelerated_timeout := false
	if strategy_id == &"deliberate_failure":
		var player := world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
		if not player.defeated and not player.victorious:
			world.current_tick = world.battle_definition.time_limit_ticks - 1
			world.advance_tick()
			accelerated_timeout = true

	if world.enemy_opening_plan_id != plan_id:
		failures.append("%s/%s/%s changed its locked enemy plan" % [scenario_id, plan_id, strategy_id])
	if strategy_id not in [&"no_intervention", &"deliberate_failure"] and int(commands["accepted"]) == 0:
		failures.append("%s/%s/%s produced no accepted player command" % [scenario_id, plan_id, strategy_id])
	if int(commands["rejected"]) > 0:
		failures.append("%s/%s/%s rejected %d audit commands: %s" % [scenario_id, plan_id, strategy_id, commands["rejected"], commands["reasons"]])
	if strategy_id == &"deliberate_failure" and not (world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).defeated:
		failures.append("%s/%s deliberate failure did not reach authoritative defeat" % [scenario_id, plan_id])
	for log_entry in world.enemy_reaction_log:
		if not log_entry.contains("source=LOCKED_OPENING_PLAN") \
				and not log_entry.contains("source=LOCKED_PLAN_TIMELINE") \
				and not log_entry.contains("source=LEGAL_FACTION_OBSERVATION"):
			failures.append("%s/%s/%s produced unaudited enemy logic: %s" % [scenario_id, plan_id, strategy_id, log_entry])
			break

	var metrics := _world_metrics(world)
	metrics["scenario_id"] = String(scenario_id)
	metrics["enemy_plan_id"] = String(plan_id)
	metrics["strategy_id"] = String(strategy_id)
	metrics["commands"] = commands
	metrics["accelerated_timeout"] = accelerated_timeout
	metrics["fingerprint"] = _fingerprint(world)
	return metrics


func _issue_strategy(world: SimulationWorld, scenario_id: StringName, strategy_id: StringName, commands: Dictionary) -> void:
	var regions := world.battle_definition.region_dictionary()
	var richest := _richest_region(regions)
	match strategy_id:
		&"recommended":
			_issue_recommended(world, scenario_id, regions, commands)
		&"conservative":
			var commander_id := _commander_id(world, &"di_tian")
			_submit(world, CommanderOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, commander_id, CommanderOrderCommand.OrderKind.SET_POSTURE, Vector2.ZERO, &"", CommanderState.Posture.HOLD), commands)
			_submit_objective(world, commander_id, _nearest_region(regions, world.battle_definition.player_headquarters_position), commands)
		&"intel_first":
			var pair := _adjacent_region_pair(regions)
			_submit(world, SupportOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, SupportOrderCommand.SupportKind.AIR_RECON, pair[0], pair[1]), commands)
			_submit_objective(world, _active_commander_id(world, &"bai_jiuyang"), regions[pair[0]] as BattleRegionDefinition, commands)
		&"resource_greedy":
			for commander_id_variant in _active_commander_ids(world):
				_submit_objective(world, commander_id_variant as StringName, richest, commands)
		&"no_intervention", &"deliberate_failure":
			pass


func _issue_recommended(world: SimulationWorld, scenario_id: StringName, regions: Dictionary, commands: Dictionary) -> void:
	match scenario_id:
		&"grey_ridge":
			_submit(world, _deploy_card(world, &"thunder_fire_group", Vector2(-192.0, -64.0)), commands)
			_submit_objective(world, _commander_id(world, &"di_tian"), regions[&"central_relay"], commands)
			_submit_objective(world, _commander_id(world, &"bai_jiuyang"), regions[&"west_mine"], commands)
		&"broken_bridge":
			_submit(world, SupportOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, SupportOrderCommand.SupportKind.ENGINEERING_ROUTE, &"east_engineering_ford", &"", &"bridge_engineer_group"), commands)
			world.advance_tick()
			_submit_objective(world, _commander_id(world, &"di_tian"), regions[&"east_supply"], commands)
		&"fog_forest":
			_submit_objective(world, _commander_id(world, &"di_tian"), regions[&"forward_supply_node"], commands)
		&"black_well":
			_submit_objective(world, _commander_id(world, &"lu_zheng"), regions[&"black_well_core"], commands)
			_submit_objective(world, _commander_id(world, &"gu_hanxing"), regions[&"slag_rail"], commands)


func _issue_followup(world: SimulationWorld, scenario_id: StringName, strategy_id: StringName, tick: int, commands: Dictionary) -> void:
	if scenario_id == &"grey_ridge" and strategy_id == &"recommended" and tick == 100:
		_submit_objective(world, _commander_id(world, &"lin_mo"), world.battle_definition.region_dictionary()[&"central_relay"], commands)


func _deploy_card(world: SimulationWorld, card_id: StringName, offset: Vector2) -> DeployUnitCardCommand:
	var headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	return DeployUnitCardCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, card_id, headquarters.position + offset)


func _submit_objective(world: SimulationWorld, commander_id: StringName, region: BattleRegionDefinition, commands: Dictionary) -> void:
	_submit(world, CommanderOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, commander_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, region.position, region.region_id), commands)


func _submit(world: SimulationWorld, command: GameCommand, commands: Dictionary) -> void:
	var result := world.submit_command(command)
	if result.is_accepted():
		commands["accepted"] = int(commands["accepted"]) + 1
	else:
		commands["rejected"] = int(commands["rejected"]) + 1
		(commands["reasons"] as Array).append(result.describe())


func _world_metrics(world: SimulationWorld) -> Dictionary:
	var local_alive := 0
	var enemy_alive := 0
	var local_health := 0.0
	var enemy_health := 0.0
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if not unit.enabled:
			continue
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			local_alive += 1
			local_health += unit.health
		else:
			enemy_alive += 1
			enemy_health += unit.health
	var local_faction := world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
	var enemy_faction := world.factions[SimulationWorld.ENEMY_PLAYER_ID] as FactionState
	var local_regions := 0
	var enemy_regions := 0
	for region_variant in world.strategic_regions.values():
		var region := region_variant as StrategicRegionState
		if region.controller_faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			local_regions += 1
		elif region.controller_faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			enemy_regions += 1
	return {
		"tick": world.current_tick,
		"player_outcome": "victory" if local_faction.victorious else ("defeat" if local_faction.defeated else "ongoing"),
		"player_supply": local_faction.supply,
		"enemy_supply": enemy_faction.supply,
		"player_alive": local_alive,
		"enemy_alive": enemy_alive,
		"player_unit_health": roundi(local_health),
		"enemy_unit_health": roundi(enemy_health),
		"player_headquarters_health": roundi((world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState).health),
		"enemy_headquarters_health": roundi((world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState).health),
		"player_regions": local_regions,
		"enemy_regions": enemy_regions,
		"event_count": world.events.size(),
		"enemy_reaction_count": world.enemy_reaction_log.size(),
	}


func _fingerprint(world: SimulationWorld) -> String:
	var metrics := _world_metrics(world)
	var parts: Array[String] = []
	var keys := metrics.keys()
	keys.sort_custom(func(left: Variant, right: Variant) -> bool: return String(left) < String(right))
	for key in keys:
		parts.append("%s=%s" % [key, metrics[key]])
	parts.append("plan=%s" % world.enemy_opening_plan_id)
	return "|".join(parts).sha256_text()


func _battle_contract(battle: BattleDefinition) -> Dictionary:
	return {
		"operation_number": battle.operation_number,
		"time_limit_ticks": battle.time_limit_ticks,
		"commanders": _resource_ids(battle.commander_definitions, &"definition_id"),
		"unit_cards": _resource_ids(battle.unit_card_definitions, &"definition_id"),
		"doctrines": _resource_ids(battle.doctrine_definitions, &"definition_id"),
		"supports": _resource_ids(battle.support_abilities, &"support_id"),
		"enemy_plans": _resource_ids(battle.enemy_plans, &"plan_id"),
		"enemy_reactions": _resource_ids(battle.enemy_reaction_rules, &"rule_id"),
	}


func _resource_ids(resources: Array, property_name: StringName) -> Array[String]:
	var ids: Array[String] = []
	for resource in resources:
		ids.append(String(resource.get(property_name)))
	ids.sort()
	return ids


func _commander_ids(world: SimulationWorld) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(world.commanders.keys())
	ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	return ids


func _commander_id(world: SimulationWorld, preferred: StringName) -> StringName:
	return preferred if world.commanders.has(preferred) else _commander_ids(world)[0]


func _active_commander_ids(world: SimulationWorld) -> Array[StringName]:
	var active: Dictionary = {}
	for card_variant in world.unit_cards.values():
		var card := card_variant as UnitCardState
		if card.faction_id == SimulationWorld.LOCAL_PLAYER_ID and card.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
			active[card.commander_definition_id] = true
	var ids: Array[StringName] = []
	ids.assign(active.keys())
	ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	return ids


func _active_commander_id(world: SimulationWorld, preferred: StringName) -> StringName:
	var ids := _active_commander_ids(world)
	return preferred if ids.has(preferred) else ids[0]


func _richest_region(regions: Dictionary) -> BattleRegionDefinition:
	var best: BattleRegionDefinition
	for region_variant in regions.values():
		var region := region_variant as BattleRegionDefinition
		if best == null or region.supply_per_settlement > best.supply_per_settlement or region.supply_per_settlement == best.supply_per_settlement and String(region.region_id) < String(best.region_id):
			best = region
	return best


func _nearest_region(regions: Dictionary, position: Vector2) -> BattleRegionDefinition:
	var best: BattleRegionDefinition
	for region_variant in regions.values():
		var region := region_variant as BattleRegionDefinition
		if best == null or region.position.distance_squared_to(position) < best.position.distance_squared_to(position):
			best = region
	return best


func _adjacent_region_pair(regions: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(regions.keys())
	ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for region_id in ids:
		var region := regions[region_id] as BattleRegionDefinition
		if not region.adjacent_region_ids.is_empty():
			return [region_id, region.adjacent_region_ids[0]]
	return [ids[0], ids[1]]


func _string_names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result
