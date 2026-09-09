extends SceneTree

const MATRIX_TICKS := 650
const STRATEGY_IDS: Array[StringName] = [
	&"no_intervention", &"two_axis_counterattack", &"concentrated_core", &"preserve_and_screen",
]
const OPENING_PLAN_IDS: Array[StringName] = [&"center_crush", &"rail_envelopment", &"pump_pincer"]


func _initialize() -> void:
	var failures: Array[String] = []
	for strategy_id in STRATEGY_IDS:
		for opening_plan_id in OPENING_PLAN_IDS:
			var key := "%s/%s" % [strategy_id, opening_plan_id]
			var first := _run_case(strategy_id, opening_plan_id, failures)
			var second := _run_case(strategy_id, opening_plan_id, failures)
			if first != second:
				failures.append("%s is nondeterministic: %s" % [key, _signature_differences(first, second)])
			print("WARSEED_BLACK_WELL_MATRIX %s %s" % [key, first.sha256_text()])
	_test_failure_paths(failures)
	if failures.is_empty():
		print("WARSEED Black Well decision matrix passed: %d strategies x %d plans" % [STRATEGY_IDS.size(), OPENING_PLAN_IDS.size()])
		quit(0)
		return
	for failure in failures:
		push_error("BLACK WELL MATRIX FAILED: %s" % failure)
	quit(1)


func _run_case(strategy_id: StringName, opening_plan_id: StringName, failures: Array[String]) -> String:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL, {}, opening_plan_id)
	if world.enemy_opening_plan_id != opening_plan_id:
		failures.append("%s did not lock opening plan %s" % [strategy_id, opening_plan_id])
	_issue_opening(world, strategy_id, failures)
	for _tick in range(MATRIX_TICKS):
		world.advance_tick()
	if world.enemy_opening_plan_id != opening_plan_id:
		failures.append("%s changed locked plan after observing player commands" % strategy_id)
	for log_entry in world.enemy_reaction_log:
		if not log_entry.contains("source=LOCKED_OPENING_PLAN") \
				and not log_entry.contains("source=LOCKED_PLAN_TIMELINE") \
				and not log_entry.contains("source=LEGAL_FACTION_OBSERVATION"):
			failures.append("%s produced an unaudited hostile decision: %s" % [strategy_id, log_entry])
	return _fingerprint(world)


func _issue_opening(world: SimulationWorld, strategy_id: StringName, failures: Array[String]) -> void:
	var regions := world.battle_definition.region_dictionary()
	match strategy_id:
		&"two_axis_counterattack":
			_submit(world, _objective(world, &"lu_zheng", regions[&"black_well_core"]), strategy_id, failures)
			_submit(world, _objective(world, &"gu_hanxing", regions[&"slag_rail"]), strategy_id, failures)
		&"concentrated_core":
			for commander_id in [&"lu_zheng", &"di_tian", &"lin_mo"]:
				_submit(world, _objective(world, commander_id, regions[&"black_well_core"]), strategy_id, failures)
		&"preserve_and_screen":
			_submit(world, _objective(world, &"lu_zheng", regions[&"withdrawal_corridor"]), strategy_id, failures)
			_submit(world, _objective(world, &"bai_jiuyang", regions[&"pump_heights"]), strategy_id, failures)
			_submit(world, _objective(world, &"gu_hanxing", regions[&"black_well_core"]), strategy_id, failures)
			_submit(world, SupportOrderCommand.new(
				world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
				GameCommand.IssuerKind.PLAYER, world.current_tick,
				SupportOrderCommand.SupportKind.AIR_RECON, &"black_well_core", &"pump_heights"
			), strategy_id, failures)


func _test_failure_paths(failures: Array[String]) -> void:
	var withdrawal_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	var corridor := withdrawal_world.strategic_regions[&"withdrawal_corridor"] as StrategicRegionState
	var withdrawn_card_id: StringName
	for commander in withdrawal_world.commanders.values():
		withdrawal_world._assign_commander_objective(commander as CommanderState, corridor.position, corridor.region_id)
	for card_variant in withdrawal_world.unit_cards.values():
		var card := card_variant as UnitCardState
		if card.faction_id != SimulationWorld.LOCAL_PLAYER_ID or card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		if withdrawn_card_id.is_empty():
			withdrawn_card_id = card.definition.definition_id
		for entity_id in card.member_entity_ids:
			var unit := withdrawal_world.units.get(entity_id) as UnitState
			if unit != null and unit.enabled:
				unit.position = corridor.position
	withdrawal_world._advance_limited_withdrawals()
	var withdrawn := withdrawal_world.unit_cards[withdrawn_card_id] as UnitCardState
	if withdrawn.deployment_state != UnitCardState.DeploymentState.WITHDRAWN:
		failures.append("complete friendly cards did not enter the authoritative withdrawn state")
	else:
		var redeploy := DeployUnitCardCommand.new(
			withdrawal_world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
			GameCommand.IssuerKind.PLAYER, withdrawal_world.current_tick,
			withdrawn_card_id, withdrawal_world.battle_definition.player_headquarters_position
		)
		if withdrawal_world.submit_command(redeploy).is_accepted():
			failures.append("a withdrawn unit card was allowed to redeploy in the same battle")
	withdrawal_world.current_tick = withdrawal_world.battle_definition.time_limit_ticks - 1
	var timeout_snapshot := withdrawal_world.advance_tick()
	var timeout_player := timeout_snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	if timeout_player == null or not timeout_player.defeated or timeout_player.victorious:
		failures.append("withdrawing all main forces must still lose when the battle timer expires")

	var hidden_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	var local_knowledge := hidden_world.faction_knowledge[SimulationWorld.LOCAL_PLAYER_ID] as FactionKnowledge
	local_knowledge.hostile_contacts.clear()
	hidden_world._update_commander_combat_coordination()
	for task_variant in hidden_world.tasks.values():
		var task := task_variant as TaskState
		if task.faction_id == SimulationWorld.LOCAL_PLAYER_ID and task.reinforcement_committed:
			failures.append("hidden enemy state triggered a commander reinforcement judgment")
			break

	var recovery_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	var guard := recovery_world.unit_cards[&"blackwell_guard_battalion"] as UnitCardState
	var core := recovery_world.strategic_regions[&"black_well_core"] as StrategicRegionState
	for entity_id in guard.member_entity_ids:
		var member := recovery_world.units.get(entity_id) as UnitState
		if member != null and member.enabled:
			member.position = core.position
	guard.organization = recovery_world.battle_definition.organization_max - 0.01
	guard.last_damage_tick = recovery_world.current_tick - recovery_world.battle_definition.organization_recovery_delay_ticks
	recovery_world.refresh_unit_card_organization_baseline(guard)
	recovery_world._advance_unit_card_organization()
	if guard.organization > recovery_world.battle_definition.organization_max or not is_equal_approx(guard.organization, recovery_world.battle_definition.organization_max):
		failures.append("organization recovery did not clamp exactly to the configured maximum")


func _objective(world: SimulationWorld, commander_id: StringName, region: BattleRegionDefinition) -> CommanderOrderCommand:
	return CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		region.position, region.region_id
	)


func _submit(world: SimulationWorld, command: GameCommand, strategy_id: StringName, failures: Array[String]) -> void:
	var result := world.submit_command(command)
	if not result.is_accepted():
		failures.append("%s command rejected: %s" % [strategy_id, result.describe()])


func _fingerprint(world: SimulationWorld) -> String:
	var parts: Array[String] = [
		"tick=%d" % world.current_tick,
		"plan=%s" % world.enemy_opening_plan_id,
		"events=%d" % world.events.size(),
		"reactions=%d" % world.enemy_reaction_log.size(),
	]
	var card_ids := world.unit_cards.keys()
	card_ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for card_id in card_ids:
		var card := world.unit_cards[card_id] as UnitCardState
		var task := world._task_for_unit_card(card.definition.definition_id)
		var formation := world.formations.get(card.formation_id) as FormationState
		parts.append("c%s:%d:%d:%d:ctrl%d:task%d:%d:%d,%d:order%d:%d,%d" % [
			card_id, card.deployment_state, roundi(card.organization * 10.0), card.withdrawn_strength,
			card.control_state, task.task_id if task != null else -1, task.phase if task != null else -1,
			roundi(task.target_position.x) if task != null else -1, roundi(task.target_position.y) if task != null else -1,
			formation.order_kind if formation != null else -1,
			roundi(formation.order_destination.x) if formation != null else -1,
			roundi(formation.order_destination.y) if formation != null else -1,
		])
	var unit_ids := world.units.keys()
	unit_ids.sort()
	for entity_id in unit_ids:
		var unit := world.units[entity_id] as UnitState
		parts.append("u%d:%d:%d:%d:%d" % [entity_id, int(unit.enabled), roundi(unit.position.x), roundi(unit.position.y), roundi(unit.health)])
	return "|".join(parts)


func _signature_differences(first: String, second: String) -> String:
	var first_parts := first.split("|")
	var second_parts := second.split("|")
	var differences: Array[String] = []
	for index in range(mini(first_parts.size(), second_parts.size())):
		if first_parts[index] != second_parts[index]:
			differences.append("part %d: %s != %s" % [index, first_parts[index], second_parts[index]])
			if differences.size() >= 8:
				break
	if first_parts.size() != second_parts.size():
		differences.append("part count %d != %d" % [first_parts.size(), second_parts.size()])
	return "; ".join(differences)
