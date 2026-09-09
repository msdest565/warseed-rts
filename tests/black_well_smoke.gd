extends SceneTree

const SLICE_TICKS := 2000


func _initialize() -> void:
	var failures: Array[String] = []
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL, {}, &"center_crush")
	var battle := world.battle_definition
	if battle == null or world.get_scenario_id() != &"black_well":
		failures.append("Black Well content did not initialize")
		_finish(failures)
		return
	if battle.battlefield_bounds.size != Vector2(7168.0, 4608.0):
		failures.append("Black Well did not retain its expanded 7168x4608 battlefield")
	if world.commanders.size() != 5 or world.unit_cards.size() != 12:
		failures.append("Black Well must expose five commanders and twelve persistent unit cards")
	if battle.support_abilities.size() != 6 or battle.enemy_plans.size() != 3:
		failures.append("Black Well must expose six supports and three locked enemy plans")

	var regions := battle.region_dictionary()
	_submit(world, _objective(world, &"lu_zheng", regions[&"black_well_core"]), failures)
	_submit(world, _objective(world, &"gu_hanxing", regions[&"slag_rail"]), failures)
	_submit(world, _objective(world, &"di_tian", regions[&"black_well_core"]), failures)
	_submit(world, _objective(world, &"lin_mo", regions[&"pump_heights"]), failures)
	_submit(world, _objective(world, &"bai_jiuyang", regions[&"pump_heights"]), failures)
	_submit(world, SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, world.current_tick,
		SupportOrderCommand.SupportKind.AIR_RECON, &"slag_rail", &"black_well_core"
	), failures)

	for _tick in range(SLICE_TICKS):
		world.advance_tick()
	var snapshot := world.create_true_state_snapshot()
	var damage_events := _event_count(world, SimulationEvent.Kind.DAMAGE_APPLIED)
	var scout_events := _event_count(world, SimulationEvent.Kind.SCOUT_CONTACT_REPORTED)
	var organization_events := _event_count(world, SimulationEvent.Kind.UNIT_CARD_ORGANIZATION_CHANGED)
	var local_entities := 0
	for unit in snapshot.units:
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			local_entities += 1
	var scout_card := world.unit_cards[&"falcon_recon_group"] as UnitCardState
	var scout_task := world._task_for_unit_card(&"falcon_recon_group")
	var scout_formation := world.formations.get(scout_card.formation_id) as FormationState
	var local_knowledge := world.faction_knowledge[SimulationWorld.LOCAL_PLAYER_ID] as FactionKnowledge
	print("WARSEED Black Well scout: state=%d task=%s lifecycle=%s phase=%s anchor=%s target=%s discovered=%s contacts=%d visible=%d detail=%s" % [
		scout_card.deployment_state, scout_task.task_id if scout_task != null else -1,
		scout_task.lifecycle if scout_task != null else -1,
		scout_task.phase if scout_task != null else -1,
		scout_formation.anchor_position if scout_formation != null else Vector2.ZERO,
		scout_task.target_position if scout_task != null else Vector2.ZERO,
		scout_task.discovered_contact_count if scout_task != null else -1,
		local_knowledge.hostile_contacts.size(), local_knowledge.visible_hostile_unit_ids.size(),
		scout_task.last_detail if scout_task != null else "missing",
	])
	if damage_events <= 0:
		failures.append("Black Well produced no autonomous combat damage")
	if scout_events <= 0:
		failures.append("Black Well reconnaissance produced no autonomous contact warning")
	if organization_events <= 0:
		failures.append("Black Well combat never changed unit-card organization")
	if local_entities <= 0:
		failures.append("Black Well has no surviving visible friendly battlefield entities")
	print("WARSEED Black Well smoke: ticks=%d local=%d damage=%d scout=%d organization=%d reactions=%d" % [
		SLICE_TICKS, local_entities, damage_events, scout_events, organization_events,
		world.enemy_reaction_log.size(),
	])
	_finish(failures)


func _objective(world: SimulationWorld, commander_id: StringName, region: BattleRegionDefinition) -> CommanderOrderCommand:
	return CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		region.position, region.region_id
	)


func _submit(world: SimulationWorld, command: GameCommand, failures: Array[String]) -> void:
	var result := world.submit_command(command)
	if not result.is_accepted():
		failures.append("command rejected: %s" % result.describe())


func _event_count(world: SimulationWorld, kind: SimulationEvent.Kind) -> int:
	var count := 0
	for event in world.events:
		if event.kind == kind:
			count += 1
	return count


func _finish(failures: Array[String]) -> void:
	for failure in failures:
		push_error("BLACK WELL SMOKE FAILED: %s" % failure)
	quit(0 if failures.is_empty() else 1)
