class_name TestCommanderTaskGraphs
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_definitions(failures)
	_test_compilation(failures)
	_test_execution(failures)
	_test_retreat_completion(failures)
	_test_command_boundaries(failures)
	_test_pause_and_fairness(failures)
	_test_deployment_and_failures(failures)
	_test_mixed_card(failures)
	return failures


func _test_definitions(failures: Array[String]) -> void:
	var template := CommanderTaskGraphBuilder.DEFAULT_DEFINITION
	_expect(template.validate().is_valid(), "default six-stage graph validates", failures)
	var broken := template.duplicate(true) as CommanderTaskGraphDefinition
	broken.stages[1].prerequisite_ids.append(&"missing")
	_expect(not broken.validate().is_valid(), "missing prerequisites cannot load", failures)
	broken = template.duplicate(true)
	broken.stages[0].prerequisite_ids.append(broken.stages[4].stage_id)
	_expect(not broken.validate().is_valid(), "cycles cannot load", failures)
	broken = template.duplicate(true)
	broken.stages[2].phase = broken.stages[1].phase
	_expect(not broken.validate().is_valid(), "duplicate phases cannot load", failures)
	broken = template.duplicate(true)
	broken.stages[2].dwell_ticks = broken.stages[2].timeout_ticks + 1
	_expect(not broken.validate().is_valid(), "impossible completion windows cannot load", failures)
	broken = template.duplicate(true)
	broken.stages[2].arrival_radius = NAN
	_expect(not broken.validate().is_valid(), "nonfinite geometry cannot load", failures)
	broken = template.duplicate(true)
	broken.stages[4].prerequisite_ids.clear()
	_expect(not broken.validate().is_valid(), "exploitation cannot bypass engagement", failures)
	broken = template.duplicate(true)
	broken.stages.reverse()
	_expect(broken.validate().is_valid(), "resource ordering is independent of graph dependencies", failures)


func _test_compilation(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var request := TestStaffPlans.request()
	var plans := StaffPlanGenerator.new().generate(world.create_snapshot(), 1, request)
	var plan := plans.plans[0]
	var builder := CommanderTaskGraphBuilder.new()
	_expect(builder.build(world.create_snapshot(), plan) == null, "unapproved suggestions cannot create execution graphs", failures)
	var command := StaffPlanApprovalCommand.new(world.allocate_command_id(), 1, world.current_tick, request, plan.profile_id, plan.fingerprint())
	_expect(world.submit_command(command).is_accepted(), "fixture approval accepted through command pipeline", failures)
	world.advance_tick()
	var snapshot := world.create_snapshot()
	plan = snapshot.staff_plan_decisions[0].approved_plan
	var graph := builder.build(snapshot, plan)
	_expect(graph != null, "approved plan compiles", failures)
	if graph == null:
		return
	_expect(graph.nodes.size() == plan.assignments.size() * 6, "each committed card has all six explicit stages", failures)
	_expect(graph.reserve_card_ids == plan.reserve_card_ids, "uncommitted reserve cards stay outside the graph", failures)
	for node in graph.nodes:
		_expect(not graph.reserve_card_ids.has(node.card_id), "reserve card is not silently committed", failures)
		if node.phase == CommanderTaskStageDefinition.Phase.MUSTER:
			_expect(graph.dependencies_satisfied(node), "muster is a root stage", failures)
		elif node.phase != CommanderTaskStageDefinition.Phase.RETREAT:
			_expect(not graph.dependencies_satisfied(node), "unapplied phases do not satisfy later dependencies", failures)
		for id in node.prerequisite_ids:
			_expect(graph.get_node(id) != null, "compiled prerequisite names a real node", failures)
	var reordered := CommanderTaskGraphBuilder.DEFAULT_DEFINITION.duplicate(true) as CommanderTaskGraphDefinition
	reordered.stages.reverse()
	var same := builder.build(snapshot, plan, reordered)
	_expect(_signature(graph) == _signature(same), "template order cannot change compiled graph", failures)
	var copy := graph.duplicate_value()
	copy.approved_plan.assignments.clear()
	copy.nodes[0].prerequisite_ids.clear()
	copy.nodes[0].target_position = Vector2(-999, -999)
	copy.nodes[0].lifecycle = CommanderTaskNodeSnapshot.Lifecycle.COMPLETED
	_expect(not graph.approved_plan.assignments.is_empty() and graph.nodes[0].lifecycle == CommanderTaskNodeSnapshot.Lifecycle.WAITING \
		and graph.nodes[0].target_position != copy.nodes[0].target_position, "graph snapshots are deep value copies", failures)
	_expect(builder.build(world.create_true_state_snapshot(), plan) == null, "true-state compilation is forbidden", failures)
	_expect(builder.build(world.create_faction_snapshot(2), plan) == null, "opponent cannot compile the player's private plan", failures)
	# A typed compilation fixture with both recon and main force isolates cross-card edges.
	plan.assignments[0].role = StaffPlanAssignment.Role.RECONNAISSANCE
	graph = builder.build(snapshot, plan)
	if plan.assignments.size() > 1 and graph != null:
		var recon_id := StringName("%s/recon" % plan.assignments[0].card_id)
		var deploy := graph.get_node(StringName("%s/deploy" % plan.assignments[1].card_id))
		_expect(deploy.prerequisite_ids.has(recon_id), "main deployment waits for advance reconnaissance", failures)
		for id in deploy.prerequisite_ids:
			if id != recon_id:
				graph.get_node(id).lifecycle = CommanderTaskNodeSnapshot.Lifecycle.COMPLETED
		_expect(not graph.dependencies_satisfied(deploy), "other completed prerequisites cannot bypass the scout", failures)
		graph.get_node(recon_id).lifecycle = CommanderTaskNodeSnapshot.Lifecycle.COMPLETED
		_expect(graph.dependencies_satisfied(deploy), "completed scout unlocks the main force", failures)
	_expect(world.create_snapshot().staff_plan_decisions[0].approved_plan.fingerprint() != plan.fingerprint(), "fixture snapshot edits do not alter authority approval", failures)


func _signature(graph: CommanderTaskGraphSnapshot) -> String:
	var lines: PackedStringArray = []
	for node in graph.nodes:
		lines.append("%s:%s:%s:%d" % [node.node_id, node.prerequisite_ids, node.target_position, node.earliest_tick])
	return "|".join(lines)


func _test_execution(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var request := TestStaffPlans.request()
	var plan := StaffPlanGenerator.new().generate(world.create_snapshot(), 1, request).plans[0]
	world.submit_command(StaffPlanApprovalCommand.new(world.allocate_command_id(), 1, world.current_tick, request, plan.profile_id, plan.fingerprint()))
	for _tick in range(70):
		world.advance_tick()
	var snapshot := world.create_snapshot()
	_expect(snapshot.commander_task_graphs.size() == 1, "approval installs an authoritative graph", failures)
	if snapshot.commander_task_graphs.is_empty():
		return
	var graph := snapshot.commander_task_graphs[0]
	var completed_musters := 0
	var real_tasks := 0
	for node in graph.nodes:
		if node.phase == CommanderTaskStageDefinition.Phase.MUSTER and node.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.COMPLETED:
			completed_musters += 1
		if node.task_id != 0:
			real_tasks += 1
	_expect(completed_musters > 0 and real_tasks > 0, "approved cards actually muster and receive staged tasks", failures)
	_expect(world.create_faction_snapshot(2).commander_task_graphs.is_empty(), "opponent cannot read graph execution", failures)
	var card_id := plan.assignments[0].card_id
	world.submit_command(UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick, card_id, UnitCardControlCommand.Action.TAKEOVER))
	for _tick in range(5):
		world.advance_tick()
	_expect(world.create_snapshot().get_unit_card(card_id).is_player_overridden, "graph cannot steal manual control", failures)
	var paused := false
	for node in world.create_snapshot().commander_task_graphs[0].nodes:
		if node.card_id == card_id and node.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.PAUSED:
			paused = true
	_expect(paused, "manual control pauses the associated graph nodes", failures)
	var retreat := CommanderCardTaskCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER,
		world.current_tick, graph.graph_id, &"", CommanderCardTaskCommand.Action.RETREAT)
	_expect(world.submit_command(retreat).is_accepted(), "explicit retreat uses the command pipeline", failures)
	world.advance_tick()
	_expect(world.create_snapshot().commander_task_graphs[0].retreat_requested, "retreat request becomes authoritative on apply", failures)
	_expect(not graph.retreat_requested, "old graph snapshot stays unchanged", failures)
	_expect(world.create_snapshot().get_unit_card(card_id).is_player_overridden, "retreat preserves separately controlled cards", failures)


func _test_retreat_completion(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var request := TestStaffPlans.request()
	var plan := StaffPlanGenerator.new().generate(world.create_snapshot(), 1, request).plans[0]
	world.submit_command(StaffPlanApprovalCommand.new(world.allocate_command_id(), 1, 0, request, plan.profile_id, plan.fingerprint()))
	for _tick in range(320):
		world.advance_tick()
	var graph := world.create_snapshot().commander_task_graphs[0]
	for node in graph.nodes:
		if node.phase == CommanderTaskStageDefinition.Phase.EXPLOIT:
			_expect(node.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.COMPLETED, "concentrated plan reaches real objective exploitation", failures)
	for card_id in graph.reserve_card_ids:
		_expect(world.commander_task_graph_system.owns_card(card_id), "finished plan keeps reserves held", failures)
	var completions := 0
	for event in world.events:
		if event.kind == SimulationEvent.Kind.TASK_STATE_CHANGED and event.detail.begins_with("COMPLETED:") and event.detail.contains("COMMANDER_GRAPH"):
			completions += 1
	_expect(completions > 0, "real stage completion enters task metrics events", failures)
	_expect(CommanderTaskGraphPresenter.describe(world.create_snapshot(), graph).contains(GameText.t(&"COMMANDER_GRAPH_PHASE_4")), "finished UI shows final exploitation stage", failures)
	var command := CommanderCardTaskCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER,
		world.current_tick, graph.graph_id, &"", CommanderCardTaskCommand.Action.RETREAT)
	_expect(world.submit_command(command).is_accepted(), "completed operation may explicitly return to safety", failures)
	for _tick in range(600):
		world.advance_tick()
	for node in world.create_snapshot().commander_task_graphs[0].nodes:
		if node.phase == CommanderTaskStageDefinition.Phase.RETREAT:
			_expect(node.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.COMPLETED, "retreat completes only after actual safe arrival: %s state=%d" % [node.card_id, node.lifecycle], failures)


func _expect(value: bool, message: String, failures: Array[String]) -> void:
	if not value:
		failures.append("Commander task graph: " + message)


func _approved_world(budget: int = 0, profile: StringName = &"direct_commitment") -> SimulationWorld:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var request := TestStaffPlans.request()
	request.max_supply_cost = budget
	var plans := StaffPlanGenerator.new().generate(world.create_snapshot(), 1, request)
	for plan in plans.plans:
		if plan.profile_id == profile:
			world.submit_command(StaffPlanApprovalCommand.new(world.allocate_command_id(), 1, 0, request, plan.profile_id, plan.fingerprint()))
			break
	world.advance_tick()
	return world


func _test_command_boundaries(failures: Array[String]) -> void:
	var world := _approved_world()
	var graph := world.create_snapshot().commander_task_graphs[0]
	# The first tick queues real roots; they must neither duplicate nor accept caller mutation.
	var queued := world.command_queue.snapshot()[0] as CommanderCardTaskCommand
	_expect(queued != null, "graph queues real stage commands", failures)
	if queued == null:
		return
	var duplicate := queued.duplicate_value()
	duplicate.command_id = world.allocate_command_id()
	_expect(world.submit_command(duplicate).reason == CommandValidationResult.Reason.TASK_CONFLICT, "same node cannot queue twice", failures)
	world.command_queue.drain()
	duplicate.graph_id = &"forged"
	_expect(world.submit_command(duplicate).reason == CommandValidationResult.Reason.INVALID_TASK, "forged graph rejected", failures)
	duplicate.graph_id = graph.graph_id
	duplicate.node_id = &"forged"
	_expect(world.submit_command(duplicate).reason == CommandValidationResult.Reason.INVALID_TASK, "forged node rejected", failures)
	duplicate.node_id = queued.node_id
	duplicate.issuer_id = 2
	_expect(world.submit_command(duplicate).reason == CommandValidationResult.Reason.NOT_CONTROLLER, "opponent cannot command graph", failures)
	duplicate.issuer_id = 1
	duplicate.agent_id = 99999
	_expect(world.submit_command(duplicate).reason == CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED, "wrong agent rejected", failures)
	duplicate.agent_id = queued.agent_id
	var policy := world.agent_policies[duplicate.agent_id] as AgentPolicy
	policy.authorization = AgentPolicy.Authorization.ADVISORY
	_expect(world.submit_command(duplicate).reason == CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED, "advisory cannot execute graph", failures)
	policy.authorization = AgentPolicy.Authorization.ASSISTED
	_expect(world.submit_command(duplicate).is_accepted(), "authorized node accepted", failures)
	duplicate.action = CommanderCardTaskCommand.Action.COMPLETE
	world.advance_tick()
	_expect(world.create_snapshot().commander_task_graphs[0].get_node(queued.node_id).lifecycle == CommanderTaskNodeSnapshot.Lifecycle.ACTIVE, "queued command was copied and cannot forge completion", failures)
	var node := graph.get_node(queued.node_id)
	world.submit_command(UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick, node.card_id, UnitCardControlCommand.Action.TAKEOVER))
	world.advance_tick()
	_expect(world.create_snapshot().get_unit_card(node.card_id).is_player_overridden, "same-tick graph command never overrides takeover", failures)
	world.submit_command(CommanderOrderCommand.new(world.allocate_command_id(), 1, world.current_tick, node.commander_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, Vector2(800, 2400)))
	world.advance_tick()
	for cancelled in world.create_snapshot().commander_task_graphs[0].nodes:
		if cancelled.commander_id == node.commander_id:
			_expect(cancelled.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.CANCELLED, "player commander order cancels every old node", failures)
	# Installing an identical approved value still invalidates queued IDs from the previous installation.
	world = _approved_world()
	graph = world.create_snapshot().commander_task_graphs[0]
	var old_command := world.command_queue.snapshot()[0] as CommanderCardTaskCommand
	world.commander_task_graph_system.install(world, graph.approved_plan)
	_expect(world.commander_task_graph_system.validate(world, old_command).reason == CommandValidationResult.Reason.INVALID_TASK, "replacement invalidates old queued graph IDs", failures)
	# Approval must cancel initial tasks even while a flank waits for preparation.
	world = _approved_world(0, &"flanking_advance")
	graph = world.create_snapshot().commander_task_graphs[0]
	for assignment in graph.approved_plan.assignments:
		var card := world.unit_cards[assignment.card_id] as UnitCardState
		_expect(card.assigned_task_id == 0, "approved preparation does not continue previous objective", failures)


func _test_pause_and_fairness(failures: Array[String]) -> void:
	var world := _approved_world()
	for _tick in range(4):
		world.advance_tick()
	var graph := world.create_snapshot().commander_task_graphs[0]
	var card_id := graph.approved_plan.assignments[0].card_id
	world.submit_command(UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick, card_id, UnitCardControlCommand.Action.TAKEOVER))
	for _tick in range(3):
		world.advance_tick()
	var paused_node: CommanderTaskNodeSnapshot
	for node in world.create_snapshot().commander_task_graphs[0].nodes:
		if node.card_id == card_id and node.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.PAUSED and node.started_tick >= 0:
			paused_node = node
	_expect(paused_node != null, "long-pause fixture has an active paused stage", failures)
	if paused_node == null:
		return
	# Keep the battle alive while more than a complete stage timeout passes in real ticks.
	for value in world.units.values():
		(value as UnitState).can_attack = false
	for _tick in range(1250):
		world.advance_tick()
	_expect(world.create_snapshot().get_unit_card(card_id).is_player_overridden, "125 seconds of manual control remain protected", failures)
	world.submit_command(UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick, card_id, UnitCardControlCommand.Action.RETURN_TO_COMMANDER))
	for _tick in range(40):
		world.advance_tick()
	var resumed := world.create_snapshot().commander_task_graphs[0].get_node(paused_node.node_id)
	_expect(resumed.lifecycle != CommanderTaskNodeSnapshot.Lifecycle.PAUSED and resumed.lifecycle != CommanderTaskNodeSnapshot.Lifecycle.FAILED, "return resumes without counting manual time as stage timeout", failures)
	_expect(resumed.started_tick == paused_node.started_tick and resumed.paused_duration_ticks > 1200, "authority excludes manual interval while preserving actual start time", failures)
	world = _approved_world()
	var agent := CommanderTaskGraphAgent.new()
	var before := world.create_snapshot()
	graph = before.commander_task_graphs[0]
	var signature := _command_signature(agent.propose(before, graph))
	_expect(_command_signature(agent.propose(world.create_commander_task_snapshot(1), graph)) == signature, "focused stage snapshot matches full faction commands", failures)
	var hidden: UnitState
	for value in world.units.values():
		var unit := value as UnitState
		if unit.faction_id != 1 and before.get_unit(unit.entity_id) == null:
			hidden = unit
			break
	_expect(hidden != null, "fairness fixture contains hidden hostile", failures)
	if hidden != null:
		hidden.position += Vector2(2, 0)
		hidden.health = 1
		hidden.ammunition = 999
		hidden.assigned_task_id = 999999
		(world.factions[2] as FactionState).supply = 99999
		world._update_faction_knowledge()
		var fresh := world.create_snapshot()
		_expect(_command_signature(agent.propose(world.create_commander_task_snapshot(1), graph)) == signature, "focused stage snapshot excludes hidden-state pollution", failures)
		_expect(fresh.get_unit(hidden.entity_id) == null and _command_signature(agent.propose(fresh, graph)) == signature, "fresh hidden-state pollution cannot change graph commands", failures)
		fresh.units.reverse()
		graph.nodes.reverse()
		_expect(_command_signature(agent.propose(fresh, graph)) == signature, "snapshot order cannot change command order", failures)
	_expect(agent.propose(world.create_true_state_snapshot(), graph).is_empty(), "agent rejects true state", failures)
	_expect(agent.propose(world.create_faction_snapshot(2), graph).is_empty(), "agent rejects wrong faction knowledge", failures)


func _command_signature(commands: Array[CommanderCardTaskCommand]) -> String:
	var rows: PackedStringArray = []
	for command in commands:
		rows.append("%s:%d:%d" % [command.node_id, command.action, command.agent_id])
	return "|".join(rows)


func _test_deployment_and_failures(failures: Array[String]) -> void:
	var world := _approved_world(30)
	var graph := world.create_snapshot().commander_task_graphs[0]
	var deployment_node: CommanderTaskNodeSnapshot
	for node in graph.nodes:
		if node.requires_deployment:
			deployment_node = node
			break
	_expect(deployment_node != null, "budgeted approval actually commits a reserve", failures)
	if deployment_node != null:
		for _tick in range(120):
			world.advance_tick()
		var card := world.create_snapshot().get_unit_card(deployment_node.card_id)
		_expect(card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.current_strength > 0, "graph waits for real deployed members", failures)
		var active := world.create_snapshot().commander_task_graphs[0].get_node(deployment_node.node_id)
		_expect(active.task_id > 0, "deployed reserve receives a real whole-card task", failures)
	world = _approved_world(30)
	graph = world.commander_task_graph_system._graph
	(world.factions[1] as FactionState).supply = 0
	for _tick in range(6):
		world.advance_tick()
	var budget_blocked := false
	for node in graph.nodes:
		if node.requires_deployment and node.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.BLOCKED:
			budget_blocked = node.reason_key == &"REASON_INSUFFICIENT_SUPPLY"
	_expect(budget_blocked and (world.factions[1] as FactionState).supply >= 0, "lost deployment budget blocks without overspending", failures)
	world = _approved_world()
	graph = world.commander_task_graph_system._graph
	var muster := graph.get_node(StringName("%s/muster" % graph.approved_plan.assignments[0].card_id))
	world.command_queue.drain()
	muster.target_position = Vector2(-99999, -99999)
	muster.route_points = PackedVector2Array([muster.target_position])
	for _tick in range(4):
		world.advance_tick()
	_expect(muster.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.BLOCKED and muster.reason_key == &"REASON_PATH_UNAVAILABLE", "invalid route blocks with explicit authority reason", failures)
	var blocked := graph.get_node(StringName("%s/recon" % muster.card_id))
	_expect(blocked.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.BLOCKED, "failed route blocks dependent stages", failures)
	var retreat := CommanderCardTaskCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, graph.graph_id, &"", CommanderCardTaskCommand.Action.RETREAT)
	world.submit_command(retreat)
	for _tick in range(5):
		world.advance_tick()
	_expect(muster.lifecycle == CommanderTaskNodeSnapshot.Lifecycle.CANCELLED, "retreat cancels previously blocked stages", failures)
	_expect(world.submit_command(retreat).reason == CommandValidationResult.Reason.TASK_CONFLICT, "duplicate applied retreat is rejected", failures)
	var retreat_events := 0
	for event in world.events:
		if event.kind == SimulationEvent.Kind.COMMANDER_GRAPH_CHANGED and event.detail.contains("state=retreat_requested"):
			retreat_events += 1
	_expect(retreat_events == 1, "one explicit retreat has one auditable request event", failures)
	# Isolated snapshot predicates cover loss and timeout without using elapsed time as success.
	var snapshot := world.create_snapshot()
	var node := snapshot.commander_task_graphs[0].get_node(StringName("%s/retreat" % muster.card_id))
	node.lifecycle = CommanderTaskNodeSnapshot.Lifecycle.ACTIVE
	snapshot.tick += node.timeout_ticks
	node.started_tick = snapshot.tick - node.timeout_ticks
	var agent := CommanderTaskGraphAgent.new()
	_expect(agent.expected_action(snapshot, graph, node) == CommanderCardTaskCommand.Action.FAIL, "elapsed timeout fails instead of completing", failures)
	_expect(agent.transition_reason(snapshot, graph, node, CommanderCardTaskCommand.Action.FAIL) == &"COMMANDER_GRAPH_TIMEOUT", "timeout has an explicit cause", failures)
	snapshot.get_unit_card(muster.card_id).current_strength = 0
	_expect(agent.expected_action(snapshot, graph, node) == CommanderCardTaskCommand.Action.FAIL and agent.transition_reason(snapshot, graph, node, CommanderCardTaskCommand.Action.FAIL) == &"COMMANDER_GRAPH_CARD_LOST", "destroyed card fails with a distinct cause", failures)


func _test_mixed_card(failures: Array[String]) -> void:
	var world := TestTacticalCards.sample_world()
	var request := StaffPlanRequest.new()
	for region in world.create_snapshot().strategic_regions:
		if region.controller_faction_id != 1:
			request.objective_region_id = region.region_id
			break
	var plans := StaffPlanGenerator.new().generate(world.create_snapshot(), 1, request)
	_expect(plans != null, "mixed-card world has feasible plans", failures)
	if plans == null:
		return
	var chosen: StaffCourseOfAction
	for plan in plans.plans:
		for assignment in plan.assignments:
			if assignment.card_id == &"combined_assault":
				chosen = plan
	_expect(chosen != null, "normal planner commits a mixed card", failures)
	if chosen == null:
		return
	world.submit_command(StaffPlanApprovalCommand.new(world.allocate_command_id(), 1, 0, request, chosen.profile_id, chosen.fingerprint()))
	for _tick in range(60):
		world.advance_tick()
	var card := world.unit_cards[&"combined_assault"] as UnitCardState
	var task := world.tasks.get(card.assigned_task_id) as TaskState
	_expect(task != null, "mixed card receives a graph task", failures)
	if task != null:
		for id in card.member_entity_ids:
			if (world.units[id] as UnitState).enabled:
				_expect(task.participant_entity_ids.has(id), "graph keeps every live mixed entry member, including support roles", failures)
