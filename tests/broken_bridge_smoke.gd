extends SceneTree

const SLICE_TICKS := 1200


func _initialize() -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BROKEN_BRIDGE)
	var failures: Array[String] = []
	if world.battle_definition == null or world.get_scenario_id() != &"broken_bridge":
		failures.append("Broken Bridge content did not initialize")
	var bridge := world.strategic_regions.get(&"central_relay") as StrategicRegionState
	var heights := world.strategic_regions.get(&"west_mine") as StrategicRegionState
	_submit(world, CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		bridge.position, bridge.region_id
	), failures)
	_submit(world, CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"lin_mo", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		heights.position, heights.region_id
	), failures)
	_submit(world, SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, SupportOrderCommand.SupportKind.ENGINEERING_ROUTE,
		&"east_engineering_ford", &"", &"bridge_engineer_group"
	), failures)
	for _tick in range(SLICE_TICKS):
		world.advance_tick()
	var snapshot := world.create_true_state_snapshot()
	var player := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var damage_events := 0
	var route_events := 0
	for event in world.events:
		if event.kind == SimulationEvent.Kind.DAMAGE_APPLIED:
			damage_events += 1
		elif event.kind == SimulationEvent.Kind.ENGINEERING_ROUTE_OPENED:
			route_events += 1
	if world.logic_grid.is_blocked(Vector2i(146, 63)):
		failures.append("engineering side route remained blocked")
	if route_events != 1:
		failures.append("engineering side route should emit exactly one authoritative event")
	if damage_events <= 0:
		failures.append("Broken Bridge produced no autonomous combat")
	if player == null or player.defeated:
		failures.append("the directed opening should remain viable through the smoke window")
	print("WARSEED Broken Bridge smoke: ticks=%d damage=%d route_events=%d reports=%d reactions=%d defeated=%s" % [
		SLICE_TICKS, damage_events, route_events, snapshot.intel_reports.size(), world.enemy_reaction_log.size(), player.defeated if player != null else true,
	])
	for failure in failures:
		push_error("BROKEN BRIDGE SMOKE FAILED: %s" % failure)
	quit(0 if failures.is_empty() else 1)


func _submit(world: SimulationWorld, command: GameCommand, failures: Array[String]) -> void:
	var result := world.submit_command(command)
	if not result.is_accepted():
		failures.append("command rejected: %s" % result.describe())
