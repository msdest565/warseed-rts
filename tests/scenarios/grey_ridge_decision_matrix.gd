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
# R5-002: 8 assault + 2 probe + 4 held reserve; counterfactual restores all 18 R5-001 goldens.
const EXPECTED_FINGERPRINTS: Dictionary = {
	"a_central_fire/central_assault": "2251f107a8ae1994524994b61a6abc3343cb14d1f0004b27fd07732bc9b2e99f",
	"a_central_fire/western_hook": "5ed09ef85bfaaeda055c98a1db705d265657751907260fa33a09263321f46560",
	"a_central_fire/western_feint": "42b934c7e496676d1f88c4cfeb70087c59c6c55eeec69b61c367ba11cf4d73b8",
	"b_split_armor/central_assault": "e5d8de605552f16eb68947780f00b8207c978e30a9a54a0c390026be55da60b1",
	"b_split_armor/western_hook": "389e3bf4fdafa6427e5847a31f7f91552a6a58df751a9f093a210009cae77630",
	# Manual armor now fires in range while preserving its move order (maintenance 20260914).
	"b_split_armor/western_feint": "dd5ab20826e226e776ac309ef69c009580c2a025d384a36dff4c937a29ab0b54",
	"c_intel_first/central_assault": "95579ca68b638ef83034eaede9ac4c6119f08e48e1459db4bd7483161855cf32",
	"c_intel_first/western_hook": "7bcaf86844f8cbcfe399d14613f6708f51e6bb9941ac9285f24af102ede58581",
	"c_intel_first/western_feint": "bd5422ab450113b0270b38b06b6cb2aa46cfad9e5da9506bf15f2604e0566c56",
	"custom_western_breakthrough/central_assault": "3162e34ca449b9730c7eb4c682c04bd6c8aa3940e16a08098b5914fdb28b8b95",
	"custom_western_breakthrough/western_hook": "65b038f7567bbe74875955e432706bcd7f4ff66d18fb6573db00473a11bb58f7",
	"custom_western_breakthrough/western_feint": "ed3287f39c1771d0154c36b3ef9b883d80381591e1a214020e524c1a85751764",
	"custom_eastern_recon_fire/central_assault": "d15313846ff63f5aefcbf9db643d330bd4ee1f85e2348912034336dfa5390534",
	"custom_eastern_recon_fire/western_hook": "caca16bdc26bacd94aeddc8dfb6ccce0d11cda675daab81b4f68ac1c545e3bad",
	"custom_eastern_recon_fire/western_feint": "c15755380a3c70f33eda7044b87e30836812111f10aa38997e310a86b7013a6f",
	"custom_central_fortify/central_assault": "75d4a61be37186c78881a336cde307ef6aad9cbd99659e7129c28031ae981b45",
	"custom_central_fortify/western_hook": "bf2fb9a6ce0335472a8f598a102ec8979f2d23b63712a8bf54eef426b7f5e53e",
	"custom_central_fortify/western_feint": "05872e8f72dad44bc57941cb17dd3ffd38bc9730e289b1224369046fc308366e",
}


func _initialize() -> void:
	var failures: Array[String] = []
	for strategy_id in STRATEGY_IDS:
		for opening_plan_id in OPENING_PLAN_IDS:
			var key := "%s/%s" % [strategy_id, opening_plan_id]
			var fingerprint := _run_case(strategy_id, opening_plan_id, failures)
			if fingerprint != _run_case(strategy_id, opening_plan_id, failures):
				failures.append("repeat divergence: " + key)
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
