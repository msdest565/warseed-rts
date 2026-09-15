class_name TestCommanderAdaptation
extends RefCounted

const Action := CommanderCardTaskCommand.Action
const Life := CommanderTaskNodeSnapshot.Lifecycle

func run() -> Array[String]:
	var failures: Array[String] = []
	_test_reinforcement(failures)
	_test_reserve(failures)
	_test_replan(failures)
	_test_retreat(failures)
	_test_boundaries(failures)
	_test_dependencies_and_policy(failures)
	return failures

func _world() -> SimulationWorld:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var request := TestStaffPlans.request()
	request.max_supply_cost = 10
	var plans := StaffPlanGenerator.new().generate(world.create_snapshot(), 1, request)
	for plan in plans.plans:
		if plan.profile_id == &"flanking_advance":
			world.submit_command(StaffPlanApprovalCommand.new(world.allocate_command_id(), 1, 0, request, plan.profile_id, plan.fingerprint()))
	for _tick in range(35):
		world.advance_tick()
	return world

func _damage(world: SimulationWorld, id: StringName, survivors: int) -> void:
	var card := world.create_snapshot().get_unit_card(id)
	for index in range(card.active_member_entity_ids.size()):
		if index >= survivors:
			var unit := world.units[card.active_member_entity_ids[index]] as UnitState
			unit.health = 0
			unit.enabled = false
	world._refresh_battle_population()

func _proposal(world: SimulationWorld, action: CommanderCardTaskCommand.Action) -> CommanderCardTaskCommand:
	var snapshot := world.create_snapshot()
	for command in CommanderAdaptationAgent.new().propose(snapshot, snapshot.commander_task_graphs[0]):
		if command.action == action:
			command.command_id = world.allocate_command_id()
			return command
	return null

func _test_reinforcement(failures: Array[String]) -> void:
	var world := _world()
	_damage(world, &"falcon_recon_group", 5)
	var before := world.create_snapshot()
	var command := _proposal(world, Action.REINFORCE)
	_expect(command != null, "loss creates reinforcement proposal", failures)
	if command == null: return
	_expect(world.submit_command(command).is_accepted(), "reinforcement enters ordinary queue", failures)
	_expect(not world.submit_command(command).is_accepted(), "same-tick duplicate rejected", failures)
	world.advance_tick()
	var after := world.create_snapshot()
	_expect(after.get_unit_card(command.target_card_id).current_strength > before.get_unit_card(command.target_card_id).current_strength, "reinforcement actually restores soldiers", failures)
	_expect(after.get_faction(1).supply == before.get_faction(1).supply - before.commander_task_graphs[0].reinforcement_supply_cost, "ordinary supply charged once", failures)
	_expect(after.get_faction(1).reinforcement_cooldown_until_tick > after.tick, "shared cooldown started", failures)
	_expect(after.commander_task_graphs[0].reinforcement_requests == 1 and before.commander_task_graphs[0].reinforcement_requests == 0, "application and old snapshot isolated", failures)
	_expect(_proposal(world, Action.REINFORCE) == null, "cooldown forbids another refill", failures)
	var copy := after.commander_task_graphs[0].duplicate_value()
	copy.adaptation_policy.max_replans = 99
	_expect(after.commander_task_graphs[0].adaptation_policy.max_replans == 2, "policy resource copied deeply", failures)

func _test_reserve(failures: Array[String]) -> void:
	var world := _world()
	_damage(world, &"falcon_recon_group", 5)
	var faction := world.factions[1] as FactionState
	faction.reinforcement_cooldown_until_tick = 1000
	var command := _proposal(world, Action.COMMIT_RESERVE)
	_expect(command != null, "loss can commit approved reserve", failures)
	if command == null: return
	var before := world.create_snapshot()
	_expect(world.submit_command(command).is_accepted(), "reserve commitment accepted", failures)
	world.advance_tick()
	var graph := world.create_snapshot().commander_task_graphs[0]
	_expect(graph.reserve_commits == 1 and not graph.reserve_card_ids.has(command.target_card_id), "reserve assigned once", failures)
	_expect(graph.adaptation_budget_remaining == before.commander_task_graphs[0].adaptation_budget_remaining - before.get_unit_card(command.target_card_id).supply_cost, "reserve commitment charged to approved budget", failures)
	for _tick in range(120): world.advance_tick()
	var card := world.create_snapshot().get_unit_card(command.target_card_id)
	_expect(card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.current_strength > 0 and card.assigned_task_id != 0, "reserve really deployed and executing a task", failures)
	_expect(world.commander_task_graph_system._graph.reserve_commits == 1, "reserve count bounded", failures)
	_expect(CommanderTaskGraphPresenter.describe(world.create_snapshot(), world.commander_task_graph_system._graph).contains(GameText.t(card.display_name_key)), "new reserve visible in task presentation", failures)

func _block(world: SimulationWorld, impossible: bool) -> CommanderTaskNodeSnapshot:
	var node := world.commander_task_graph_system._graph.get_node(&"falcon_recon_group/muster")
	world.commander_task_graph_system._finish_task(world, node, false)
	node.lifecycle = Life.BLOCKED
	node.changed_tick = world.current_tick - 30
	node.reason_key = &"REASON_PATH_UNAVAILABLE"
	node.route_points = PackedVector2Array([Vector2(-999, -999)])
	if impossible: node.target_position = Vector2(-9999, -9999)
	return node

func _test_replan(failures: Array[String]) -> void:
	var world := _world()
	var node := _block(world, false)
	var command := _proposal(world, Action.REPLAN)
	_expect(command != null and world.submit_command(command).is_accepted(), "blocked route queues replan", failures)
	world.advance_tick()
	_expect(node.lifecycle == Life.WAITING and node.route_points[0] == node.target_position, "replan replaces invalid route to original target", failures)
	world.advance_tick()
	_expect(node.task_id != 0 and node.lifecycle == Life.ACTIVE, "replanned node receives actual task", failures)
	world = _world()
	node = _block(world, true)
	for _tick in range(75): world.advance_tick()
	_expect(world.commander_task_graph_system._graph.replan_count == 2 and node.lifecycle == Life.BLOCKED and node.reason_key == &"COMMANDER_ADAPT_REPLAN_EXHAUSTED", "unreachable replan stops at limit with reason", failures)

func _test_retreat(failures: Array[String]) -> void:
	var world := _world()
	_damage(world, &"falcon_recon_group", 2)
	_damage(world, &"ironwall_assault_group", 3)
	var command := _proposal(world, Action.AUTO_RETREAT)
	_expect(command != null and world.submit_command(command).is_accepted(), "severe loss requests retreat", failures)
	world.advance_tick()
	for _tick in range(600): world.advance_tick()
	var graph := world.create_snapshot().commander_task_graphs[0]
	_expect(graph.retreat_requested and graph.retreat_reason_key == &"COMMANDER_ADAPT_LOSS_RETREAT", "retreat stays latched", failures)
	for node in graph.nodes:
		if node.phase == CommanderTaskStageDefinition.Phase.RETREAT:
			_expect(node.lifecycle == Life.COMPLETED, "automatic retreat reaches safety: %s" % node.node_id, failures)

func _test_boundaries(failures: Array[String]) -> void:
	var world := _world()
	_damage(world, &"falcon_recon_group", 5)
	var command := _proposal(world, Action.REINFORCE)
	if command == null:
		_expect(false, "boundary fixture has proposal", failures)
		return
	var forged := command.duplicate_value()
	forged.graph_revision += 1
	_expect(not world.submit_command(forged).is_accepted(), "stale revision rejected", failures)
	forged = command.duplicate_value()
	forged.issuer_kind = GameCommand.IssuerKind.PLAYER
	_expect(not world.submit_command(forged).is_accepted(), "cannot forge automatic player adjustment", failures)
	world.commander_task_graph_system._graph.adaptation_budget_remaining = 0
	_expect(not world.submit_command(command).is_accepted(), "budget exhausted rejects adjustment", failures)
	world.commander_task_graph_system._graph.adaptation_budget_remaining = 10
	_expect(world.submit_command(command).is_accepted(), "restored fixture can queue", failures)
	world.submit_command(UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick, command.target_card_id, UnitCardControlCommand.Action.TAKEOVER))
	world.advance_tick()
	_expect(world.create_snapshot().get_unit_card(command.target_card_id).is_player_overridden and world.commander_task_graph_system._graph.reinforcement_requests == 0, "same tick player takeover wins", failures)
	world = _world()
	_damage(world, &"falcon_recon_group", 5)
	var snapshot := world.create_snapshot()
	var original := CommanderAdaptationAgent.new().propose(snapshot, snapshot.commander_task_graphs[0])
	for unit in snapshot.units:
		if unit.faction_id != 1:
			unit.position = Vector2(-5000, 1234)
	var polluted := CommanderAdaptationAgent.new().propose(snapshot, snapshot.commander_task_graphs[0])
	_expect(_signature(original) == _signature(polluted), "enemy position pollution cannot alter own adjustment", failures)
	snapshot.is_true_state = true
	_expect(CommanderAdaptationAgent.new().propose(snapshot, snapshot.commander_task_graphs[0]).is_empty(), "true-state proposals forbidden", failures)

func _signature(commands: Array[CommanderCardTaskCommand]) -> String:
	var rows: PackedStringArray = []
	for command in commands: rows.append("%d:%s:%s" % [command.action,command.node_id,command.target_card_id])
	return "|".join(rows)

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append("Commander adaptation: " + message)

func _test_dependencies_and_policy(failures: Array[String]) -> void:
	var policy := CommanderAdaptationPolicy.new()
	_expect(policy.validate().is_valid(), "default typed policy validates", failures)
	policy.interval_ticks = 0
	_expect(not policy.validate().is_valid(), "zero interval rejected", failures)
	policy.interval_ticks = 30
	policy.retreat_ratio = NAN
	_expect(not policy.validate().is_valid(), "nonfinite threshold rejected", failures)
	var world := _world()
	var graph := world.commander_task_graph_system._graph
	var recon := graph.get_node(&"falcon_recon_group/recon")
	var muster := graph.get_node(&"falcon_recon_group/muster")
	world.commander_task_graph_system._finish_task(world, muster, true)
	muster.lifecycle = Life.COMPLETED
	recon.lifecycle = Life.BLOCKED
	recon.reason_key = &"COMMANDER_GRAPH_DEPENDENCY_FAILED"
	recon.started_tick = -1
	graph.replan_count = graph.adaptation_policy.max_replans
	var snapshot := world.create_snapshot()
	_expect(CommanderTaskGraphAgent.new().expected_action(snapshot, graph, recon) == Action.RESUME, "restored dependency resumes without new replan quota", failures)
	world.advance_tick()
	world.advance_tick()
	_expect(recon.lifecycle != Life.BLOCKED and graph.replan_count == graph.adaptation_policy.max_replans, "dependency recovery actually applied without resetting quota", failures)
