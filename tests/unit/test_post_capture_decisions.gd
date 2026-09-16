class_name TestPostCaptureDecisions
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_capture_chain(failures)
	_test_engineering(failures)
	return failures


func _test_capture_chain(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var projector := CardActionProjector.new()
	var battle := world.battle_definition
	_expect(_find(projector.project(world.create_snapshot(), battle), CardActionSnapshot.CONTINUE_RECON) == null, "recon continuation waits for captured regions", failures)
	for region in world.strategic_regions.values():
		if region.capturable:
			region.controller_faction_id = 1
	var snapshot := world.create_snapshot()
	var decision := _find(projector.project(snapshot, battle), CardActionSnapshot.CONTINUE_RECON)
	_expect(decision != null, "all held and hidden HQ offers a scout decision", failures)
	if decision == null:
		return
	var original := decision.position
	var enemy := world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState
	var original_hq := enemy.position
	enemy.position += Vector2(800, 0)
	var polluted := _find(projector.project(world.create_snapshot(), battle), CardActionSnapshot.CONTINUE_RECON)
	_expect(polluted != null and polluted.position == original, "hidden HQ relocation cannot change scout destination", failures)
	enemy.position = original_hq
	var commander := world.commanders[decision.commander_id] as CommanderState
	commander.posture = CommanderState.Posture.HOLD
	var command := CardActionProjector.headquarters_command(decision, world.allocate_command_id(), 1, world.current_tick)
	_expect(world.submit_command(command).is_accepted(), "continued scouting uses the shared command pipeline", failures)
	world.advance_tick()
	var scout := world.unit_cards[decision.unit_card_id] as UnitCardState
	var task := world.tasks.get(scout.assigned_task_id) as TaskState
	_expect(task != null and task.kind == TaskState.Kind.SCOUT_AREA and task.persistent_order and commander.posture == CommanderState.Posture.CAUTIOUS, "continue scouting creates a persistent scout task and releases hold", failures)
	# Reveal through actual friendly sight; no forged building snapshot.
	TestTacticalCards._place(world, scout, original_hq + Vector2(0, 240))
	world.advance_tick()
	snapshot = world.create_snapshot()
	var actions := projector.project(snapshot, battle)
	var attack := _find(actions, CardActionSnapshot.ATTACK_HEADQUARTERS)
	_expect(attack != null and _find(actions, CardActionSnapshot.CONTINUE_RECON) == null, "legally discovered HQ replaces exploration with attack decisions", failures)
	if attack != null:
		_expect(world.submit_command(CardActionProjector.headquarters_command(attack, world.allocate_command_id(), 1, world.current_tick)).is_accepted(), "HQ attack is executable", failures)
		world.advance_tick()
		var attacker := world.commanders[attack.commander_id] as CommanderState
		_expect(attacker.posture == CommanderState.Posture.AGGRESSIVE and attacker.target_position == attack.position, "HQ execution applies its target and offensive posture", failures)
	_expect(_find(projector.project(world.create_true_state_snapshot(), battle), CardActionSnapshot.CONTINUE_RECON) == null, "true-state exploration rejected", failures)


func _test_engineering(failures: Array[String]) -> void:
	for tactical in [false, true]:
		var world := TestGreyRidgeTacticalContent.new()._formal_world([&"bridge_engineer_group", &"ironwall_assault_group"])
		if not tactical:
			var battle := load("res://data/battles/broken_bridge.tres") as BattleDefinition
			var plan := battle.create_default_army_plan()
			plan.starting_unit_card_ids.assign([&"bridge_engineer_group", &"ironwall_assault_group"])
			world = SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BROKEN_BRIDGE, {}, &"", plan)
			TestTacticalCards._quiet(world)
		(world.factions[1] as FactionState).supply = 10
		var route := world.battle_definition.engineering_routes[0]
		var rect := route.cleared_rects[0]
		for region in world.strategic_regions.values():
			if region.capturable:
				_expect(world.logic_grid.is_world_position_walkable(region.position), "engineering obstacle must not cover a capture destination", failures)
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				_expect(world.logic_grid.is_blocked(Vector2i(x,y)), "every marked engineering cell starts blocked", failures)
		var start := Vector2(rect.position + Vector2i(rect.size.x / 2, -2)) * LogicGrid.CELL_SIZE
		var finish := Vector2(rect.end + Vector2i(-rect.size.x / 2, 2)) * LogicGrid.CELL_SIZE
		var before := world.pathfinder.find_path(start, finish)
		for point in before:
			_expect(not rect.has_point(world.logic_grid.world_to_cell(point)), "closed route cannot be crossed by navigation", failures)
		var engineer := world.unit_cards[&"bridge_engineer_group"] as UnitCardState
		TestTacticalCards._place(world, engineer, world._engineering_route_center(route) + Vector2(0, 180))
		var command: GameCommand
		if tactical:
			command = TacticalAbilityCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, engineer.definition.definition_id, Vector2.ZERO, 0, &"", route.route_id)
		else:
			command = SupportOrderCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, SupportOrderCommand.SupportKind.ENGINEERING_ROUTE, route.route_id, &"", engineer.definition.definition_id)
		var accepted := world.submit_command(command)
		_expect(accepted.is_accepted(), "engineering entry %s rejected: %s" % [tactical, accepted.describe()], failures)
		if not accepted.is_accepted():
			continue
		var opening_feedback := false
		for tick in range(35):
			world.advance_tick()
			for event in world.events:
				if event.kind == SimulationEvent.Kind.ENGINEERING_ROUTE_OPENED:
					opening_feedback = event.detail.contains("region=%s" % route.linked_region_id) and event.detail.contains("position=")
		_expect(opening_feedback, "engineering completion identifies its region and map location", failures)
		_expect(world.opened_engineering_routes.has(route.route_id), "engineering entry must actually open the route", failures)
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				_expect(not world.logic_grid.is_blocked(Vector2i(x,y)), "opening removes the full marked obstacle", failures)
		var after := world.pathfinder.find_path(start, finish)
		_expect(not after.is_empty() and world.logic_grid.is_segment_walkable(start, finish), "new path crosses the opened route", failures)
		var inside := world.logic_grid.cell_to_world(rect.position + rect.size / 2)
		_expect(not world.pathfinder.find_path(start, inside).is_empty(), "AStar clears formerly solid cells after opening", failures)


func _find(actions: Array[CardActionSnapshot], kind: int) -> CardActionSnapshot:
	for action in actions:
		if action.action_kind == kind:
			return action
	return null


func _expect(value: bool, message: String, failures: Array[String]) -> void:
	if not value:
		failures.append(message)
