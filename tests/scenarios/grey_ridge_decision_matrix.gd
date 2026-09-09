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
	"a_central_fire/central_assault": "49b609ce25fb8f8e9b796af689ef4517c5df0ab6d3e6ee9ff1ea5454c3e190f0",
	"a_central_fire/western_hook": "15476d07eaf4a1b970bd458d7c3349407ef8e36790c411ea0b7cc3c72b2f88fe",
	"a_central_fire/western_feint": "9ee777b7b5d0f4b05de73183966162f89a37ce0504aee1218034727fefc69911",
	"b_split_armor/central_assault": "fbb5b7faa44a1560d418dfdf0262b16ff4bab096c0c68ce503a817848bf20fa5",
	"b_split_armor/western_hook": "33229a096c1326308b2a2a5504a7a46f157fc36d0f33932e9e1f32c6ee9ab0b6",
	"b_split_armor/western_feint": "f7614b68f2bdc117f92bdeda8eacd86771cb0d6d98f90eac0caaa6d656dacb66",
	"c_intel_first/central_assault": "86b0ea249ce686be21ab5d59ffcc1a40d5b1c924f6957f4d27a74f23757aab0f",
	"c_intel_first/western_hook": "c83706188054f21e75cd42665acea9426b2f92af814ab2c051420ebd66399aa3",
	"c_intel_first/western_feint": "e9d8920be5eeab685d2517500437450560cedb1f7958dee99b356829d69518e2",
	"custom_western_breakthrough/central_assault": "4f27f480e49c321f793c5b75f867642caa1d50166b3436382da23d1eac0956f0",
	"custom_western_breakthrough/western_hook": "dbaeb1e8b3705c2cd3f6a05de262abd8fb109aa581aff51f9e780740d0babba4",
	"custom_western_breakthrough/western_feint": "cd980babe758d5855d1605f12da61df305991a935e042da0826f8d1839f79287",
	"custom_eastern_recon_fire/central_assault": "b423bef01c3cf10745e244ac2cc286476acdf010e30e87a1680384682cb46c62",
	"custom_eastern_recon_fire/western_hook": "55a6a9b9801770c789dda760f143c54f58f286a786b0978e4c96014266cec590",
	"custom_eastern_recon_fire/western_feint": "5f8d449aa1c63a25396206d14ee792f335677e35c711af45c6e99eb099849fac",
	"custom_central_fortify/central_assault": "4b899f90993e7451694fc719bcf149b2c3ec5e5f21a3b10ce2439f4043e08b8f",
	"custom_central_fortify/western_hook": "4c028b02f0b38171d7a222913686fd537b8bd7ab77caf89d184bc85b6f019479",
	"custom_central_fortify/western_feint": "78faecccf5f13d868356dc27303a4e964452245dc3709fa0b28d772f028450af",
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
