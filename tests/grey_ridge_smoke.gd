extends SceneTree

const SLICE_TICKS := 1200


func _initialize() -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var opening_snapshot := world.create_true_state_snapshot()
	var enemy_probe := opening_snapshot.get_formation(SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID)
	var opening_plan_logged := (
		world.enemy_reaction_log.size() == 1
		and world.enemy_reaction_log[0].contains("source=LOCKED_OPENING_PLAN")
		and world.enemy_reaction_log[0].contains("formations=3,4")
	)
	var headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var thunder := world.unit_cards[&"thunder_fire_group"] as UnitCardState
	var armored := world.unit_cards[&"armored_spearhead"] as UnitCardState
	world.submit_command(CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"
	))
	world.submit_command(CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"bai_jiuyang", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		SimulationWorld.GREY_RIDGE_WEST_POSITION, &"west_mine"
	))
	world.submit_command(DeployUnitCardCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, world.current_tick,
		thunder.definition.definition_id, headquarters.position + Vector2(-192.0, -64.0)
	))
	world.submit_command(SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, world.current_tick,
		SupportOrderCommand.SupportKind.AIR_RECON,
		&"west_mine", &"central_relay"
	))
	var armored_submitted := false
	for tick in range(SLICE_TICKS):
		if tick == 800:
			var result := world.submit_command(DeployUnitCardCommand.new(
				world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
				GameCommand.IssuerKind.PLAYER, world.current_tick,
				armored.definition.definition_id, headquarters.position + Vector2(192.0, -64.0)
			))
			armored_submitted = result.is_accepted()
		world.advance_tick()
	var snapshot := world.create_true_state_snapshot()
	var player := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var active_entities := 0
	for unit in snapshot.units:
		if unit.enabled:
			active_entities += 1
	var deployed_reserve_entities := thunder.member_entity_ids.size() + armored.member_entity_ids.size()
	print("WARSEED Grey Ridge smoke: ticks=%d entities=%d supply=%d reports=%d reactions=%d probe=%d thunder=%d armored=%d player_defeated=%s" % [
		SLICE_TICKS, active_entities, player.supply, snapshot.intel_reports.size(),
		world.enemy_reaction_log.size(), enemy_probe.member_entity_ids.size() if enemy_probe != null else 0, thunder.deployment_state,
		armored.deployment_state, player.defeated,
	])
	var passed := (
		opening_snapshot.units.size() == 34
		and enemy_probe != null
		and enemy_probe.member_entity_ids.size() == 2
		and opening_plan_logged
		and armored_submitted
		and thunder.deployment_state == UnitCardState.DeploymentState.DEPLOYED
		and armored.deployment_state == UnitCardState.DeploymentState.DEPLOYED
		and deployed_reserve_entities == 14
		and active_entities > 0
		and active_entities <= 48
		and snapshot.intel_reports.size() >= 3
		and world.enemy_reaction_log.size() >= 1
		and not player.defeated
	)
	if not passed:
		push_error("Grey Ridge smoke failed its command, deployment, intelligence, or survival gates")
	quit(0 if passed else 1)
