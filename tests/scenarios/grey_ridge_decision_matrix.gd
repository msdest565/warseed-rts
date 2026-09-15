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
# R5-001: doctrine withdrawal and typed phase receipts; counterfactual recovers all 18 old goldens.
const EXPECTED_FINGERPRINTS: Dictionary = {
	"a_central_fire/central_assault": "a6e11c8ae5b10e5823e5c4840b93e7fdbb61af7107971550fd860ffad37606b6",
	"a_central_fire/western_hook": "ba37173a3f1c368365d8359dd45621bd85cf98d1b407d544e1896e0e7dfeb916",
	"a_central_fire/western_feint": "7bae769e7e68de9326932d96e64620ce0063b2cbc16def34517a5ce9b4e4f253",
	"b_split_armor/central_assault": "ba9ab6afe4f439ff5b0cb235594a122e09585f3a3be97ba15a34517c8ce07980",
	"b_split_armor/western_hook": "5e98a13f057a242dcfaa57a5c5d7125310ae266bd99e1579bf54faae97c30e10",
	# Manual armor now fires in range while preserving its move order (maintenance 20260914).
	"b_split_armor/western_feint": "58765e5a43c4e0422e23914b58381e133eebd5b41e66a2d80724f6f66b39d623",
	"c_intel_first/central_assault": "dbfc245bd459a1d89e8d4347789c3f01aee55d7d5efd8e73c77e78b635d289ea",
	"c_intel_first/western_hook": "9c796cebb47532089c88ae73630ee9ae98ae4ac0b45ea389f738595bc8a258ed",
	"c_intel_first/western_feint": "1aa7f370711ede7652c94c5e4253a388741677b8b7220f5bf812c0414b8d9a0b",
	"custom_western_breakthrough/central_assault": "40ab556ef41752a597e010db1702cb81d09f4d4c4b462a57e3a8fa129e5e180c",
	"custom_western_breakthrough/western_hook": "b0dfbe1d14bccf14df90f114bad3064f45fcb75ef0c59b70140319a677ee7feb",
	"custom_western_breakthrough/western_feint": "e8dbbf0e9bbea73337e0d55c6bc60c8149d03eb63bcc6a7acf65c2ae072132ef",
	"custom_eastern_recon_fire/central_assault": "1b8e7a17f46c5915aeb6fd4a87c033bdab070ab1fbb0b15a2a1f3ed9c2805f08",
	"custom_eastern_recon_fire/western_hook": "579f3e06fcf0507739d67346df9a03c5dcb7c8871e2eb697de22dd77428fedcb",
	"custom_eastern_recon_fire/western_feint": "faca2d07502e9b26593b28583f7dbee85452e8cd2e776c98a7b76fe10ba345aa",
	"custom_central_fortify/central_assault": "a80b8578ea798642628cf692ead898ad1511cbed6e9c68ce3f58a9afc3eabea4",
	"custom_central_fortify/western_hook": "06edcbc386daa6abfa2504f75f9fc04eda73bead180487cb9de0c799ac6487e3",
	"custom_central_fortify/western_feint": "7d459aeabebaaadaaf687ca16ad0a505665c6af711927664ed994263e090715d",
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
