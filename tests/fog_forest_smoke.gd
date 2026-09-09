extends SceneTree

const SLICE_TICKS := 1400


func _initialize() -> void:
	var failures: Array[String] = []
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.FOG_FOREST, {}, &"road_ambush")
	if world.battle_definition == null or world.get_scenario_id() != &"fog_forest":
		failures.append("Fog Forest content did not initialize")
	var node := world.strategic_regions.get(&"forward_supply_node") as StrategicRegionState
	_submit(world, CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		node.position, node.region_id
	), failures)
	_submit(world, CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"bai_jiuyang", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		Vector2(4384.0, 2176.0), &"east_logging_road"
	), failures)
	for _tick in range(SLICE_TICKS):
		world.advance_tick()
	var damage_events := 0
	var scout_reports := 0
	var node_events := 0
	for event in world.events:
		match event.kind:
			SimulationEvent.Kind.DAMAGE_APPLIED:
				damage_events += 1
			SimulationEvent.Kind.SCOUT_CONTACT_REPORTED:
				scout_reports += 1
			SimulationEvent.Kind.SUPPLY_NODE_ACTIVATED:
				node_events += 1
	if node_events != 1 or not world.escort_supply_node_active:
		failures.append("directed escort did not activate the forward node exactly once")
	if scout_reports <= 0:
		failures.append("autonomous recon produced no contact report")
	if damage_events <= 0:
		failures.append("Fog Forest produced no autonomous combat")
	print("WARSEED Fog Forest smoke: ticks=%d damage=%d scout_reports=%d node_events=%d intercept_target=%d reactions=%d" % [
		SLICE_TICKS, damage_events, scout_reports, node_events,
		world.enemy_escort_intercept_target_id, world.enemy_reaction_log.size(),
	])
	for failure in failures:
		push_error("FOG FOREST SMOKE FAILED: %s" % failure)
	quit(0 if failures.is_empty() else 1)


func _submit(world: SimulationWorld, command: GameCommand, failures: Array[String]) -> void:
	var result := world.submit_command(command)
	if not result.is_accepted():
		failures.append("command rejected: %s" % result.describe())
