class_name CommanderTaskGraphSystem
extends RefCounted

const Phase := CommanderTaskStageDefinition.Phase
const Life := CommanderTaskNodeSnapshot.Lifecycle
const Action := CommanderCardTaskCommand.Action

var _graph: CommanderTaskGraphSnapshot
var _agent := CommanderTaskGraphAgent.new()
var _installation_sequence: int = 0
var _proposal_snapshot: WorldSnapshot


func install(world: SimulationWorld, plan: StaffCourseOfAction) -> void:
	var graph := CommanderTaskGraphBuilder.new().build(world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID), plan)
	if graph == null:
		return
	_installation_sequence += 1
	graph.graph_id = StringName("%s:%d" % [graph.graph_id, _installation_sequence])
	if _graph != null:
		for node in _graph.nodes:
			_finish_task(world, node, false)
	_graph = graph
	var held_ids := _graph.reserve_card_ids.duplicate()
	for assignment in _graph.approved_plan.assignments:
		held_ids.append(assignment.card_id)
	for card_id in held_ids:
		var task := world._task_for_unit_card(card_id)
		if task != null:
			var hold := CommanderTaskNodeSnapshot.new()
			hold.card_id = card_id
			hold.commander_id = (world.unit_cards[card_id] as UnitCardState).commander_definition_id
			hold.task_id = task.task_id
			_finish_task(world, hold, false)
	world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.COMMANDER_GRAPH_CHANGED, 0,
		"graph=%s;state=installed;plan=%s" % [_graph.graph_id, plan.plan_id]))


func create_snapshots(observer: int) -> Array[CommanderTaskGraphSnapshot]:
	var result: Array[CommanderTaskGraphSnapshot] = []
	if _graph != null and observer in [0, _graph.faction_id]:
		result.append(_graph.duplicate_value())
	return result


func owns_card(card_id: StringName) -> bool:
	if _graph == null:
		return false
	if _graph.reserve_card_ids.has(card_id):
		return true
	for node in _graph.nodes:
		if node.phase == Phase.RETREAT and not _graph.retreat_requested:
			continue
		if node.card_id == card_id and node.lifecycle not in [Life.CANCELLED, Life.FAILED, Life.COMPLETED, Life.SKIPPED]:
			return true
	return false


func is_running() -> bool:
	if _graph == null:
		return false
	for node in _graph.nodes:
		if node.phase == Phase.RETREAT and not _graph.retreat_requested:
			continue
		if node.lifecycle not in [Life.COMPLETED, Life.SKIPPED, Life.FAILED, Life.CANCELLED]:
			return true
	return false


func allows_coordination(card_id: StringName) -> bool:
	if not owns_card(card_id):
		return true
	for node in _graph.nodes:
		if node.card_id == card_id and node.lifecycle == Life.ACTIVE and node.phase in [Phase.ENGAGE, Phase.EXPLOIT]:
			return true
	return false


func owns_commander(commander: CommanderState) -> bool:
	if commander == null:
		return false
	for card_id in commander.subordinate_unit_card_ids:
		if owns_card(card_id):
			return true
	return false


func cancel_commander(world: SimulationWorld, commander_id: StringName) -> void:
	if _graph == null:
		return
	for node in _graph.nodes:
		if node.commander_id == commander_id:
			_finish_task(world, node, false)
			_set_state(world, node, Life.CANCELLED, &"COMMANDER_GRAPH_PLAYER_ORDER")
	var commander := world.commanders.get(commander_id) as CommanderState
	if commander != null:
		for card_id in commander.subordinate_unit_card_ids:
			_graph.reserve_card_ids.erase(card_id)


func propose_commands(world: SimulationWorld) -> void:
	if _graph == null or not is_running():
		return
	var snapshot := world.create_commander_task_snapshot(_graph.faction_id)
	# Submission only enqueues commands; all proposals observe the same world state.
	_proposal_snapshot = snapshot
	for command in _agent.propose(snapshot, _graph.duplicate_value()):
		command.command_id = world.allocate_command_id()
		var result := world.submit_command(command)
		if not result.is_accepted() and command.action == Action.START and result.reason not in [CommandValidationResult.Reason.TASK_CONFLICT, CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED]:
			command.command_id = world.allocate_command_id()
			command.action = Action.BLOCK
			world.submit_command(command)
	_proposal_snapshot = null


func validate(world: SimulationWorld, command: CommanderCardTaskCommand) -> CommandValidationResult:
	if _graph == null or command.graph_id != _graph.graph_id:
		return _reject(CommandValidationResult.Reason.INVALID_TASK)
	if command.issuer_id != _graph.faction_id or command.issuer_id != SimulationWorld.LOCAL_PLAYER_ID:
		return _reject(CommandValidationResult.Reason.NOT_CONTROLLER)
	if command.action == Action.RETREAT:
		if _graph.retreat_requested:
			return _reject(CommandValidationResult.Reason.TASK_CONFLICT)
		return _reject(CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED) if command.issuer_kind != GameCommand.IssuerKind.PLAYER else CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	var node := _graph.get_node(command.node_id)
	if node == null:
		return _reject(CommandValidationResult.Reason.INVALID_TASK)
	var commander := world.commanders.get(node.commander_id) as CommanderState
	if commander == null or command.issuer_kind == GameCommand.IssuerKind.AGENT and command.agent_id != commander.agent_id:
		return _reject(CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED)
	if not world._agent_authorization_allows(command):
		return _reject(CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED)
	var snapshot := _proposal_snapshot if _proposal_snapshot != null else world.create_commander_task_snapshot(command.issuer_id)
	var expected := _agent.expected_action(snapshot, _graph, node)
	if command.action == Action.BLOCK and expected == Action.START and not _validate_start(world, node).is_accepted():
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	if expected != command.action:
		return _reject(CommandValidationResult.Reason.TASK_CONFLICT)
	if command.action == Action.START:
		return _validate_start(world, node)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_start(world: SimulationWorld, node: CommanderTaskNodeSnapshot) -> CommandValidationResult:
	var card := world.unit_cards.get(node.card_id) as UnitCardState
	if card == null:
		return _reject(CommandValidationResult.Reason.INVALID_TARGET)
	if node.requires_deployment and card.deployment_state == UnitCardState.DeploymentState.RESERVE:
		return world.validate_command(_deployment(world, node))
	var formation := world.formations.get(card.formation_id) as FormationState
	if formation == null or card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
		return _reject(CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
	if not world.find_formation_deployment_position(formation, node.target_position, node.arrival_radius, node.route_points).is_finite():
		return _reject(CommandValidationResult.Reason.PATH_UNAVAILABLE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func apply(world: SimulationWorld, command: CommanderCardTaskCommand) -> void:
	var validation := validate(world, command)
	if not validation.is_accepted():
		world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.COMMANDER_GRAPH_CHANGED, 0,
			"graph=%s;node=%s;state=rejected;reason=%s" % [command.graph_id, command.node_id, validation.describe()]))
		return
	if command.action == Action.RETREAT:
		_graph.retreat_requested = true
		world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.COMMANDER_GRAPH_CHANGED, 0,
			"graph=%s;state=retreat_requested;reason=COMMANDER_GRAPH_PLAYER_RETREAT;command=%d" % [_graph.graph_id, command.command_id]))
		return
	var node := _graph.get_node(command.node_id)
	match command.action:
		Action.START:
			var card := world.unit_cards[node.card_id] as UnitCardState
			if node.started_tick < 0:
				node.started_tick = world.current_tick
			if node.requires_deployment and card.deployment_state == UnitCardState.DeploymentState.RESERVE:
				var deploy := _deployment(world, node)
				deploy.command_id = world.allocate_command_id()
				var result := world.submit_command(deploy)
				if not result.is_accepted():
					_set_state(world, node, Life.BLOCKED, StringName("REASON_%s" % CommandValidationResult.Reason.keys()[result.reason]))
					return
			else:
				var commander := world.commanders[node.commander_id] as CommanderState
				var task := world._assign_unit_card_task(commander, card, node.target_position, node.route_points, TaskState.Kind.DEFEND_AREA)
				if task == null:
					_set_state(world, node, Life.BLOCKED, &"COMMANDER_GRAPH_NO_TASK")
					return
				task.target_radius = node.arrival_radius
				task.has_staged_target = false
				task.activation_tick = world.current_tick
				task.requires_observed_contact = false
				node.task_id = task.task_id
				if not commander.current_task_ids.has(task.task_id):
					commander.current_task_ids.append(task.task_id)
			_set_state(world, node, Life.ACTIVE, &"COMMANDER_GRAPH_EXECUTING")
		Action.PROGRESS:
			node.progress_ticks += 1
		Action.RESET_PROGRESS:
			node.progress_ticks = 0
		Action.COMPLETE, Action.SKIP:
			_finish_task(world, node, true)
			_set_state(world, node, Life.COMPLETED if command.action == Action.COMPLETE else Life.SKIPPED,
				&"COMMANDER_GRAPH_COMPLETED" if command.action == Action.COMPLETE else &"COMMANDER_GRAPH_NOT_REQUIRED")
		Action.PAUSE:
			node.progress_ticks = 0
			node.paused_tick = world.current_tick
			_set_state(world, node, Life.PAUSED, &"COMMANDER_GRAPH_PLAYER_CONTROL")
		Action.RESUME:
			if node.started_tick >= 0 and node.paused_tick >= 0:
				node.paused_duration_ticks += world.current_tick - node.paused_tick
			node.paused_tick = -1
			_set_state(world, node, Life.ACTIVE if node.started_tick >= 0 else Life.WAITING, &"COMMANDER_GRAPH_CONTROL_RETURNED")
		Action.BLOCK, Action.FAIL, Action.CANCEL:
			var snapshot := world.create_commander_task_snapshot(_graph.faction_id)
			var reason := _agent.transition_reason(snapshot, _graph, node, command.action)
			if command.action == Action.BLOCK and _agent.expected_action(snapshot, _graph, node) == Action.START:
				reason = StringName("REASON_%s" % CommandValidationResult.Reason.keys()[_validate_start(world, node).reason])
			_finish_task(world, node, false)
			_set_state(world, node, Life.BLOCKED if command.action == Action.BLOCK else (Life.FAILED if command.action == Action.FAIL else Life.CANCELLED),
				reason)


func _deployment(world: SimulationWorld, node: CommanderTaskNodeSnapshot) -> DeployUnitCardCommand:
	var retreat: CommanderTaskNodeSnapshot
	for candidate in _graph.nodes:
		if candidate.card_id == node.card_id and candidate.phase == Phase.RETREAT:
			retreat = candidate
	var deploy := DeployUnitCardCommand.new(0, _graph.faction_id, GameCommand.IssuerKind.AGENT, world.current_tick,
		node.card_id, retreat.target_position, node.commander_id)
	deploy.agent_id = (world.commanders[node.commander_id] as CommanderState).agent_id
	deploy.source_graph_id = _graph.graph_id
	return deploy


func validate_deployment(world: SimulationWorld, command: DeployUnitCardCommand) -> CommandValidationResult:
	if _graph == null or command.source_graph_id != _graph.graph_id or _graph.retreat_requested:
		return _reject(CommandValidationResult.Reason.INVALID_TASK)
	for node in _graph.nodes:
		if node.card_id == command.unit_card_id and node.phase == Phase.MUSTER and node.requires_deployment and node.lifecycle in [Life.WAITING, Life.ACTIVE]:
			var card := world.unit_cards.get(node.card_id) as UnitCardState
			if card == null or card.effective_supply_cost() > node.supply_cost:
				return _reject(CommandValidationResult.Reason.INSUFFICIENT_SUPPLY)
			return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	return _reject(CommandValidationResult.Reason.TASK_CONFLICT)


func reject_deployment(world: SimulationWorld, command: DeployUnitCardCommand, reason: CommandValidationResult.Reason) -> void:
	if _graph == null or _graph.graph_id != command.source_graph_id:
		return
	for node in _graph.nodes:
		if node.card_id == command.unit_card_id and node.phase == Phase.MUSTER and node.lifecycle == Life.ACTIVE:
			_set_state(world, node, Life.BLOCKED, StringName("REASON_%s" % CommandValidationResult.Reason.keys()[reason]))


func _finish_task(world: SimulationWorld, node: CommanderTaskNodeSnapshot, completed: bool) -> void:
	var task := world.tasks.get(node.task_id) as TaskState
	if task == null or task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.CANCELLED, TaskState.Lifecycle.FAILED]:
		return
	var card := world.unit_cards.get(node.card_id) as UnitCardState
	if card == null or card.assigned_task_id != node.task_id and card.return_task_id != node.task_id:
		return
	var manually_controlled := card.control_state in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.RETURNING]
	if not manually_controlled:
		world._stop_task_formation(task)
	task.set_lifecycle(TaskState.Lifecycle.COMPLETED if completed else TaskState.Lifecycle.CANCELLED, world.current_tick)
	task.set_phase(TaskState.Phase.DONE, world.current_tick, "Commander graph stage finished")
	if completed:
		task.progress_current = task.progress_target
	world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.TASK_STATE_CHANGED, task.task_id,
		"%s:DONE:COMMANDER_GRAPH" % TaskState.Lifecycle.keys()[task.lifecycle]))
	var commander := world.commanders.get(node.commander_id) as CommanderState
	if commander != null:
		commander.current_task_ids.erase(task.task_id)
	if manually_controlled:
		return
	world.release_task_participants(task)
	card.assigned_task_id = 0
	card.assigned_agent_id = 0
	card.control_state = UnitCardState.ControlState.UNASSIGNED


func _set_state(world: SimulationWorld, node: CommanderTaskNodeSnapshot, lifecycle: CommanderTaskNodeSnapshot.Lifecycle, reason: StringName) -> void:
	if node.lifecycle == lifecycle and node.reason_key == reason:
		return
	node.lifecycle = lifecycle
	node.reason_key = reason
	node.changed_tick = world.current_tick
	world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.COMMANDER_GRAPH_CHANGED, node.task_id,
		"graph=%s;node=%s;phase=%s;state=%s;reason=%s" % [_graph.graph_id, node.node_id, Phase.keys()[node.phase], Life.keys()[lifecycle], reason]))


func _reject(reason: CommandValidationResult.Reason) -> CommandValidationResult:
	return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, reason)
