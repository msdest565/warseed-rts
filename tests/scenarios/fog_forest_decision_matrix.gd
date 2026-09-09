extends SceneTree

const MATRIX_TICKS := 700
const STRATEGY_IDS: Array[StringName] = [&"no_intervention", &"recon_first", &"escorted_convoy", &"no_scout_fire_screen"]
const OPENING_PLAN_IDS: Array[StringName] = [&"road_ambush", &"counter_recon_screen", &"convoy_hunt_feint"]


func _initialize() -> void:
	var failures: Array[String] = []
	for strategy_id in STRATEGY_IDS:
		for opening_plan_id in OPENING_PLAN_IDS:
			var key := "%s/%s" % [strategy_id, opening_plan_id]
			var first := _run_case(strategy_id, opening_plan_id, failures)
			var second := _run_case(strategy_id, opening_plan_id, failures)
			if first != second:
				failures.append("%s is nondeterministic: %s != %s" % [key, first, second])
			print("WARSEED_FOG_FOREST_MATRIX %s %s" % [key, first])
	if failures.is_empty():
		print("WARSEED Fog Forest decision matrix passed: %d strategies x %d plans" % [STRATEGY_IDS.size(), OPENING_PLAN_IDS.size()])
		quit(0)
		return
	for failure in failures:
		push_error("FOG FOREST MATRIX FAILED: %s" % failure)
	quit(1)


func _run_case(strategy_id: StringName, opening_plan_id: StringName, failures: Array[String]) -> String:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.FOG_FOREST, {}, opening_plan_id, _army_plan(strategy_id))
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
	if strategy_id == &"escorted_convoy" and not world.escort_supply_node_active:
		failures.append("%s/%s did not deliver the convoy to the forward node" % [strategy_id, opening_plan_id])
	if strategy_id == &"recon_first":
		var reports := 0
		for event in world.events:
			if event.kind == SimulationEvent.Kind.SCOUT_CONTACT_REPORTED:
				reports += 1
		if reports == 0:
			failures.append("%s/%s produced no autonomous reconnaissance report" % [strategy_id, opening_plan_id])
	return _fingerprint(world)


func _army_plan(strategy_id: StringName) -> ArmyPlan:
	var battle := BattleContentLoader.load_battle(&"fog_forest").battle
	var plan := battle.create_default_army_plan()
	if strategy_id == &"no_scout_fire_screen":
		plan.starting_unit_card_ids.assign([&"ironwall_assault_group", &"frontline_logistics_column", &"thunder_fire_group"])
	return plan


func _issue_opening(world: SimulationWorld, strategy_id: StringName, failures: Array[String]) -> void:
	var node := world.battle_definition.region_dictionary()[&"forward_supply_node"] as BattleRegionDefinition
	var road := world.battle_definition.region_dictionary()[&"east_logging_road"] as BattleRegionDefinition
	match strategy_id:
		&"recon_first":
			_submit(world, _objective(world, &"bai_jiuyang", node), strategy_id, failures)
		&"escorted_convoy":
			_submit(world, _objective(world, &"di_tian", node), strategy_id, failures)
		&"no_scout_fire_screen":
			_submit(world, _objective(world, &"di_tian", node), strategy_id, failures)
			_submit(world, _objective(world, &"lin_mo", road), strategy_id, failures)


func _objective(world: SimulationWorld, commander_id: StringName, region: BattleRegionDefinition) -> CommanderOrderCommand:
	return CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, region.position, region.region_id
	)


func _submit(world: SimulationWorld, command: GameCommand, strategy_id: StringName, failures: Array[String]) -> void:
	var result := world.submit_command(command)
	if not result.is_accepted():
		failures.append("%s command rejected: %s" % [strategy_id, result.describe()])


func _fingerprint(world: SimulationWorld) -> String:
	var local_knowledge := world.faction_knowledge[SimulationWorld.LOCAL_PLAYER_ID] as FactionKnowledge
	var parts: Array[String] = [
		"tick=%d" % world.current_tick,
		"plan=%s" % world.enemy_opening_plan_id,
		"node=%d" % int(world.escort_supply_node_active),
		"contacts=%d" % local_knowledge.hostile_contacts.size(),
		"intercept=%d" % world.enemy_escort_intercept_target_id,
	]
	var unit_ids := world.units.keys()
	unit_ids.sort()
	for entity_id in unit_ids:
		var unit := world.units[entity_id] as UnitState
		parts.append("u%d:%d:%d:%d:%d" % [entity_id, int(unit.enabled), roundi(unit.position.x), roundi(unit.position.y), roundi(unit.health)])
	return "|".join(parts).sha256_text()
