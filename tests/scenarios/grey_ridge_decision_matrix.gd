extends SceneTree

const MATRIX_TICKS := 300
const STRATEGY_IDS: Array[StringName] = [
	&"a_central_fire",
	&"b_split_armor",
	&"c_intel_first",
	&"custom_western_breakthrough",
	&"custom_eastern_recon_fire",
	&"custom_central_fortify",
]
const OPENING_PLAN_IDS: Array[StringName] = [
	SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT,
	SimulationWorld.ENEMY_PLAN_WESTERN_HOOK,
	SimulationWorld.ENEMY_PLAN_WESTERN_FEINT,
]
const EXPECTED_FINGERPRINTS: Dictionary = {
	"a_central_fire/central_assault": "3a9c98ea161894c7fd76b294c2b533724e83c47967bc3351d3ceea6446add6ee",
	"a_central_fire/western_hook": "1c470142993a2ff70ba77855dbb8c20de470113d9dc8b34621f16251360146e1",
	"a_central_fire/western_feint": "662ed69248679fa9bc9969dd44eacde4b47a8e88433fe7f1c69a6dac858a94e8",
	"b_split_armor/central_assault": "6a2ba51fa4b493e07b004fc641253ba99ea88c91539ba35bf94b806810bfc4c4",
	"b_split_armor/western_hook": "5e98a13f057a242dcfaa57a5c5d7125310ae266bd99e1579bf54faae97c30e10",
	# Manual armor now fires in range while preserving its move order (maintenance 20260914).
	"b_split_armor/western_feint": "368fa11c096912e3ae8ec3a425fc22b3a558023697fbca5fa1f8abd7ea4e4e67",
	"c_intel_first/central_assault": "019c7072bf5c104cf29c638ad471bb26df7b4c88b02d42e79e996c4b104d3072",
	"c_intel_first/western_hook": "280cf205f564ef1b340aded7d733b3b96a4433578c1ecaaef5bb85600d5bebd4",
	"c_intel_first/western_feint": "2e0a0a5223162a0eba859035ef0fc20f16890c8e4122096c20bd2dd6b6d4c409",
	"custom_western_breakthrough/central_assault": "a6b47b9cd3c39aeae275de5f571153f18aa1187b53521593ee98900009a6deee",
	"custom_western_breakthrough/western_hook": "00ff4e31fbd6c1e261c378244c17e901787d223baf859f580d9e679054e04a42",
	"custom_western_breakthrough/western_feint": "afa855c91d8b98d08eb849b2852e9b37c50fa4c2944c78b72c4c0bc90acb46f1",
	"custom_eastern_recon_fire/central_assault": "b686bae3c0cc29b8f4e355cbe3d378e6b6a49d020e15ef3844dae9194bd2e8ac",
	"custom_eastern_recon_fire/western_hook": "579f3e06fcf0507739d67346df9a03c5dcb7c8871e2eb697de22dd77428fedcb",
	"custom_eastern_recon_fire/western_feint": "7f7da9f16a8458ba50726ed056096b8899a402967a135e7a2423b40325234993",
	"custom_central_fortify/central_assault": "8aa08bfc0b09b1ad637b85961ef73c7049befa063b750ad7463bfa49585c621c",
	"custom_central_fortify/western_hook": "51cc1f61b9dc312442bf214849961bb3d6a1e214d84931ca638e54151228c0dd",
	"custom_central_fortify/western_feint": "fcb429200e31d78ad698a20742003db492cbf559e2567240aa765e21406c2194",
}


func _initialize() -> void:
	var failures: Array[String] = []
	for strategy_id in STRATEGY_IDS:
		for opening_plan_id in OPENING_PLAN_IDS:
			var key := "%s/%s" % [strategy_id, opening_plan_id]
			var fingerprint := _run_case(strategy_id, opening_plan_id, failures)
			print("WARSEED_MATRIX %s %s" % [key, fingerprint])
			if not EXPECTED_FINGERPRINTS.has(key):
				failures.append("missing golden fingerprint for %s" % key)
			elif EXPECTED_FINGERPRINTS[key] != fingerprint:
				failures.append("matrix drift for %s\nexpected: %s\nactual:   %s" % [key, EXPECTED_FINGERPRINTS[key], fingerprint])
	if failures.is_empty():
		print("WARSEED Grey Ridge decision matrix passed: %d strategies x %d plans" % [STRATEGY_IDS.size(), OPENING_PLAN_IDS.size()])
		quit(0)
		return
	for failure in failures:
		push_error("MATRIX FAILED: %s" % failure)
	quit(1)


func _run_case(strategy_id: StringName, opening_plan_id: StringName, failures: Array[String]) -> String:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, opening_plan_id)
	var opening_log := world.enemy_reaction_log[0]
	if world.enemy_opening_plan_id != opening_plan_id or not opening_log.contains("source=LOCKED_OPENING_PLAN") or not opening_log.contains("plan=%s" % opening_plan_id):
		failures.append("%s did not lock %s before player commands" % [strategy_id, opening_plan_id])
	_issue_opening(world, strategy_id, failures)
	for tick in range(MATRIX_TICKS):
		_issue_followup(world, strategy_id, tick, failures)
		world.advance_tick()
	if world.enemy_opening_plan_id != opening_plan_id:
		failures.append("%s changed locked plan %s after observing player commands" % [strategy_id, opening_plan_id])
	for log_entry in world.enemy_reaction_log:
		if not log_entry.contains("source=LOCKED_OPENING_PLAN") and not log_entry.contains("source=LOCKED_PLAN_TIMELINE") and not log_entry.contains("source=LEGAL_FACTION_OBSERVATION"):
			failures.append("%s/%s produced an unaudited hostile decision: %s" % [strategy_id, opening_plan_id, log_entry])
	return _fingerprint(world)


func _issue_opening(world: SimulationWorld, strategy_id: StringName, failures: Array[String]) -> void:
	match strategy_id:
		&"a_central_fire":
			_submit(world, _deploy(world, &"thunder_fire_group", Vector2(-192.0, -64.0)), strategy_id, failures)
			_submit(world, _objective(world, &"di_tian", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"), strategy_id, failures)
			_submit(world, _objective(world, &"bai_jiuyang", SimulationWorld.GREY_RIDGE_WEST_POSITION, &"west_mine"), strategy_id, failures)
		&"b_split_armor":
			_submit(world, _deploy(world, &"armored_spearhead", Vector2(192.0, -64.0)), strategy_id, failures)
			_submit(world, _objective(world, &"di_tian", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"), strategy_id, failures)
			_submit(world, _objective(world, &"bai_jiuyang", SimulationWorld.GREY_RIDGE_EAST_POSITION, &"east_supply"), strategy_id, failures)
		&"c_intel_first":
			_submit(world, _air_recon(world, &"west_mine", &"central_relay"), strategy_id, failures)
			_submit(world, _posture(world, &"di_tian", CommanderState.Posture.CAUTIOUS), strategy_id, failures)
			_submit(world, _objective(world, &"di_tian", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"), strategy_id, failures)
			_submit(world, _objective(world, &"bai_jiuyang", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"), strategy_id, failures)
		&"custom_western_breakthrough":
			_submit(world, _deploy(world, &"armored_spearhead", Vector2(192.0, -64.0)), strategy_id, failures)
			_submit(world, _posture(world, &"di_tian", CommanderState.Posture.AGGRESSIVE), strategy_id, failures)
			_submit(world, _objective(world, &"di_tian", SimulationWorld.GREY_RIDGE_WEST_POSITION, &"west_mine"), strategy_id, failures)
			_submit(world, _objective(world, &"bai_jiuyang", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"), strategy_id, failures)
		&"custom_eastern_recon_fire":
			_submit(world, _deploy(world, &"thunder_fire_group", Vector2(-192.0, -64.0)), strategy_id, failures)
			_submit(world, _air_recon(world, &"central_relay", &"east_supply"), strategy_id, failures)
			_submit(world, _objective(world, &"bai_jiuyang", SimulationWorld.GREY_RIDGE_EAST_POSITION, &"east_supply"), strategy_id, failures)
			_submit(world, _objective(world, &"di_tian", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"), strategy_id, failures)
		&"custom_central_fortify":
			_submit(world, _objective(world, &"di_tian", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"), strategy_id, failures)
			_submit(world, _objective(world, &"bai_jiuyang", SimulationWorld.GREY_RIDGE_WEST_POSITION, &"west_mine"), strategy_id, failures)


func _issue_followup(world: SimulationWorld, strategy_id: StringName, tick: int, failures: Array[String]) -> void:
	if strategy_id in [&"a_central_fire", &"custom_eastern_recon_fire"] and tick == 100:
		_submit(world, _objective(world, &"lin_mo", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"), strategy_id, failures)
	elif strategy_id == &"b_split_armor" and tick == 110:
		_submit(world, UnitCardControlCommand.new(
			world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
			&"armored_spearhead", UnitCardControlCommand.Action.TAKEOVER
		), strategy_id, failures)
	elif strategy_id == &"b_split_armor" and tick == 111:
		var armor := world.unit_cards[&"armored_spearhead"] as UnitCardState
		var formation := world.formations.get(armor.formation_id) as FormationState
		if formation == null:
			failures.append("%s did not deploy armor before its split maneuver" % strategy_id)
			return
		_submit(world, FormationMoveCommand.new(
			world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
			GameCommand.IssuerKind.PLAYER, world.current_tick,
			formation.leader_entity_id, formation.formation_id, SimulationWorld.GREY_RIDGE_WEST_POSITION
		), strategy_id, failures)
	elif strategy_id == &"custom_central_fortify" and tick == 100:
		_submit(world, _posture(world, &"di_tian", CommanderState.Posture.HOLD), strategy_id, failures)
		_submit(world, SupportOrderCommand.new(
			world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
			GameCommand.IssuerKind.PLAYER, world.current_tick,
			SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY, &"", &"", &"ironwall_assault_group"
		), strategy_id, failures)


func _deploy(world: SimulationWorld, card_id: StringName, offset: Vector2) -> DeployUnitCardCommand:
	var headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	return DeployUnitCardCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, world.current_tick, card_id,
		headquarters.position + offset
	)


func _objective(world: SimulationWorld, commander_id: StringName, position: Vector2, region_id: StringName) -> CommanderOrderCommand:
	return CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, position, region_id
	)


func _posture(world: SimulationWorld, commander_id: StringName, posture: CommanderState.Posture) -> CommanderOrderCommand:
	return CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, CommanderOrderCommand.OrderKind.SET_POSTURE, Vector2.ZERO, &"", posture
	)


func _air_recon(world: SimulationWorld, first_region_id: StringName, second_region_id: StringName) -> SupportOrderCommand:
	return SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, world.current_tick,
		SupportOrderCommand.SupportKind.AIR_RECON, first_region_id, second_region_id
	)


func _submit(world: SimulationWorld, command: GameCommand, strategy_id: StringName, failures: Array[String]) -> void:
	var result := world.submit_command(command)
	if not result.is_accepted():
		failures.append("%s command %s rejected: %s" % [strategy_id, command.get_class(), result.describe()])


func _fingerprint(world: SimulationWorld) -> String:
	var local_alive := 0
	var enemy_alive := 0
	var local_health := 0
	var enemy_health := 0
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if not unit.enabled:
			continue
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			local_alive += 1
			local_health += roundi(unit.health)
		else:
			enemy_alive += 1
			enemy_health += roundi(unit.health)
	var local_faction := world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
	var enemy_faction := world.factions[SimulationWorld.ENEMY_PLAYER_ID] as FactionState
	var region_parts: Array[String] = []
	var region_ids := world.strategic_regions.keys()
	region_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for region_id in region_ids:
		var region := world.strategic_regions[region_id] as StrategicRegionState
		region_parts.append("%s:%d:%d" % [region_id, region.controller_faction_id, int(region.contested)])
	var formation_parts: Array[String] = []
	var formation_ids := world.formations.keys()
	formation_ids.sort()
	for formation_id in formation_ids:
		var formation := world.formations[formation_id] as FormationState
		formation_parts.append("%d:%d,%d:%d:%d:%d" % [
			formation_id, roundi(formation.anchor_position.x), roundi(formation.anchor_position.y),
			formation.order_kind, int(formation.is_moving), formation.member_entity_ids.size(),
		])
	var card_parts: Array[String] = []
	var card_ids := world.unit_cards.keys()
	card_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for card_id in card_ids:
		var card := world.unit_cards[card_id] as UnitCardState
		card_parts.append("%s:%d:%d:%d" % [card_id, card.deployment_state, _active_card_strength(card, world.units), card.control_state])
	var local_headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var enemy_headquarters := world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState
	var canonical_state := "t=%d;s=%d,%d;%d,%d,%d,%d;hq=%d,%d;r=%s;f=%s;c=%s;logs=%s" % [
		world.current_tick, local_faction.supply, enemy_faction.supply,
		local_alive, local_health, enemy_alive, enemy_health,
		roundi(local_headquarters.health), roundi(enemy_headquarters.health),
		",".join(region_parts), ",".join(formation_parts), ",".join(card_parts),
		"~".join(world.enemy_reaction_log),
	]
	return canonical_state.sha256_text()


func _active_card_strength(card: UnitCardState, units: Dictionary) -> int:
	var active := 0
	for entity_id in card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			active += 1
	return active
