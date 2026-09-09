extends SceneTree

const MATRIX_TICKS := 600
const STRATEGY_IDS: Array[StringName] = [&"no_intervention", &"frontal_assault", &"engineering_side_route", &"long_range_firepower"]
const OPENING_PLAN_IDS: Array[StringName] = [&"bridge_rush", &"height_screen", &"ford_feint"]


func _initialize() -> void:
	var failures: Array[String] = []
	var fingerprints: Dictionary = {}
	for strategy_id in STRATEGY_IDS:
		for opening_plan_id in OPENING_PLAN_IDS:
			var key := "%s/%s" % [strategy_id, opening_plan_id]
			var first := _run_case(strategy_id, opening_plan_id, failures)
			var second := _run_case(strategy_id, opening_plan_id, failures)
			fingerprints[key] = first
			if first != second:
				failures.append("%s is nondeterministic: %s != %s" % [key, first, second])
			print("WARSEED_BROKEN_BRIDGE_MATRIX %s %s" % [key, first])
	if failures.is_empty():
		print("WARSEED Broken Bridge decision matrix passed: %d strategies x %d plans" % [STRATEGY_IDS.size(), OPENING_PLAN_IDS.size()])
		quit(0)
		return
	for failure in failures:
		push_error("BROKEN BRIDGE MATRIX FAILED: %s" % failure)
	quit(1)


func _run_case(strategy_id: StringName, opening_plan_id: StringName, failures: Array[String]) -> String:
	var plan := _army_plan(strategy_id)
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BROKEN_BRIDGE, {}, opening_plan_id, plan)
	if world.enemy_opening_plan_id != opening_plan_id:
		failures.append("%s did not lock opening plan %s" % [strategy_id, opening_plan_id])
	_issue_opening(world, strategy_id, failures)
	for _tick in range(MATRIX_TICKS):
		world.advance_tick()
	if world.enemy_opening_plan_id != opening_plan_id:
		failures.append("%s changed its locked plan after observing player commands" % strategy_id)
	var player := world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
	if player.defeated:
		failures.append("%s/%s was not viable through the matrix window" % [strategy_id, opening_plan_id])
	return _fingerprint(world)


func _army_plan(strategy_id: StringName) -> ArmyPlan:
	var battle := BattleContentLoader.load_battle(&"broken_bridge").battle
	var plan := battle.create_default_army_plan()
	match strategy_id:
		&"frontal_assault":
			plan.starting_unit_card_ids.assign([&"falcon_recon_group", &"ironwall_assault_group", &"armored_spearhead"])
		&"long_range_firepower":
			plan.starting_unit_card_ids.assign([&"ironwall_assault_group", &"thunder_fire_group", &"highland_fire_group"])
	return plan


func _issue_opening(world: SimulationWorld, strategy_id: StringName, failures: Array[String]) -> void:
	var battle := world.battle_definition
	var bridge := battle.region_dictionary()[&"central_relay"] as BattleRegionDefinition
	var heights := battle.region_dictionary()[&"west_mine"] as BattleRegionDefinition
	var ford := battle.region_dictionary()[&"east_supply"] as BattleRegionDefinition
	match strategy_id:
		&"frontal_assault":
			_submit(world, _objective(world, &"di_tian", bridge), strategy_id, failures)
		&"engineering_side_route":
			_submit(world, SupportOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, SupportOrderCommand.SupportKind.ENGINEERING_ROUTE, &"east_engineering_ford", &"", &"bridge_engineer_group"), strategy_id, failures)
			world.advance_tick()
			_submit(world, _objective(world, &"di_tian", ford), strategy_id, failures)
		&"long_range_firepower":
			_submit(world, _objective(world, &"lin_mo", heights), strategy_id, failures)
			_submit(world, _objective(world, &"di_tian", bridge), strategy_id, failures)


func _objective(world: SimulationWorld, commander_id: StringName, region: BattleRegionDefinition) -> CommanderOrderCommand:
	return CommanderOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, commander_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, region.position, region.region_id)


func _submit(world: SimulationWorld, command: GameCommand, strategy_id: StringName, failures: Array[String]) -> void:
	var result := world.submit_command(command)
	if not result.is_accepted():
		failures.append("%s command rejected: %s" % [strategy_id, result.describe()])


func _fingerprint(world: SimulationWorld) -> String:
	var parts: Array[String] = ["tick=%d" % world.current_tick, "plan=%s" % world.enemy_opening_plan_id, "grid=%d" % world.logic_grid.revision]
	var unit_ids := world.units.keys()
	unit_ids.sort()
	for entity_id in unit_ids:
		var unit := world.units[entity_id] as UnitState
		parts.append("u%d:%d:%d:%d:%d" % [entity_id, int(unit.enabled), roundi(unit.position.x), roundi(unit.position.y), roundi(unit.health)])
	var card_ids := world.unit_cards.keys()
	card_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for card_id in card_ids:
		var card := world.unit_cards[card_id] as UnitCardState
		parts.append("c%s:%d:%d" % [card_id, card.deployment_state, card.member_entity_ids.size()])
	return "|".join(parts).sha256_text()
