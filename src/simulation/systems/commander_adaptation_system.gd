class_name CommanderAdaptationSystem
extends RefCounted

const Action := CommanderCardTaskCommand.Action
const Phase := CommanderTaskStageDefinition.Phase
const Life := CommanderTaskNodeSnapshot.Lifecycle
var agent := CommanderAdaptationAgent.new()


func validate(world: SimulationWorld, graph: CommanderTaskGraphSnapshot, command: CommanderCardTaskCommand) -> CommandValidationResult:
	if command.issuer_kind != GameCommand.IssuerKind.AGENT or not world._agent_authorization_allows(command):
		return _reject(CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED)
	if command.graph_revision != graph.revision:
		return _reject(CommandValidationResult.Reason.TASK_CONFLICT)
	var matches := false
	for candidate in agent.propose(world.create_commander_task_snapshot(graph.faction_id), graph):
		if candidate.action == command.action and candidate.node_id == command.node_id and candidate.target_card_id == command.target_card_id and candidate.agent_id == command.agent_id:
			matches = true
			break
	if not matches:
		return _reject(CommandValidationResult.Reason.TASK_CONFLICT)
	if command.action == Action.REINFORCE:
		return world.validate_command(_support(world, command))
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func apply(world: SimulationWorld, owner: CommanderTaskGraphSystem, graph: CommanderTaskGraphSnapshot, command: CommanderCardTaskCommand) -> void:
	var reason: StringName
	var cost := 0
	match command.action:
		Action.AUTO_RETREAT:
			graph.retreat_requested = true
			graph.retreat_reason_key = &"COMMANDER_ADAPT_LOSS_RETREAT"
			reason = graph.retreat_reason_key
		Action.REINFORCE:
			cost = graph.reinforcement_supply_cost
			# The parent command already passed ordinary support validation again at apply.
			# Dispatch atomically so takeover cannot occur between validation and replenishment.
			world._apply_command(_support(world, command))
			graph.reinforcement_requests += 1
			reason = &"COMMANDER_ADAPT_REINFORCED"
		Action.COMMIT_RESERVE:
			var card := world.create_commander_task_snapshot(graph.faction_id).get_unit_card(command.target_card_id)
			cost = card.supply_cost if card.deployment_state == UnitCardState.DeploymentState.RESERVE else 0
			_append_reserve(world, graph, card)
			graph.reserve_card_ids.erase(card.definition_id)
			graph.reserve_commits += 1
			reason = &"COMMANDER_ADAPT_RESERVE_COMMITTED"
		Action.REPLAN:
			var node := graph.get_node(command.node_id)
			var card := world.unit_cards[node.card_id] as UnitCardState
			var formation := world.formations.get(card.formation_id) as FormationState
			var destination := world.find_formation_deployment_position(formation, node.target_position, node.arrival_radius) if formation != null else Vector2(INF, INF)
			if graph.retreat_requested:
				graph.retreat_replan_count += 1
			else:
				graph.replan_count += 1
			reason = &"COMMANDER_ADAPT_REPLANNED"
			if not destination.is_finite():
				var used := graph.retreat_replan_count if graph.retreat_requested else graph.replan_count
				reason = &"COMMANDER_ADAPT_REPLAN_EXHAUSTED" if used >= graph.adaptation_policy.max_replans else &"COMMANDER_ADAPT_REPLAN_BLOCKED"
				owner._set_state(world, node, Life.BLOCKED, reason)
				_record(world, graph, command, reason, cost)
				return
			owner._finish_task(world, node, false)
			node.target_position = destination
			node.route_points = PackedVector2Array([node.target_position])
			node.task_id = 0
			node.started_tick = -1
			node.paused_tick = -1
			node.paused_duration_ticks = 0
			node.progress_ticks = 0
			owner._set_state(world, node, Life.WAITING, reason)
	_record(world, graph, command, reason, cost)


func _record(world: SimulationWorld, graph: CommanderTaskGraphSnapshot, command: CommanderCardTaskCommand, reason: StringName, cost: int) -> void:
	graph.adaptation_budget_remaining -= cost
	graph.revision += 1
	graph.next_adaptation_tick = world.current_tick + graph.adaptation_policy.interval_ticks
	graph.last_adaptation_reason = reason
	world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.COMMANDER_GRAPH_CHANGED, 0,
		"graph=%s;state=adapted;revision=%d;action=%d;card=%s;node=%s;reason=%s;cost=%d;budget=%d;command=%d" % [graph.graph_id, graph.revision, command.action, command.target_card_id, command.node_id, reason, cost, graph.adaptation_budget_remaining, command.command_id]))


func _support(world: SimulationWorld, command: CommanderCardTaskCommand) -> SupportOrderCommand:
	var support := SupportOrderCommand.new(command.command_id, command.issuer_id, GameCommand.IssuerKind.AGENT,
		world.current_tick, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"", &"", command.target_card_id)
	support.agent_id = command.agent_id
	return support


func _append_reserve(world: SimulationWorld, graph: CommanderTaskGraphSnapshot, card: UnitCardSnapshot) -> void:
	var safe_position := Vector2.ZERO
	for node in graph.nodes:
		if node.phase == Phase.RETREAT:
			safe_position = node.target_position
			break
	var objective := world.create_commander_task_snapshot(graph.faction_id).get_strategic_region(graph.approved_plan.objective_region_id)
	for stage in CommanderTaskGraphBuilder.DEFAULT_DEFINITION.stages:
		var node := CommanderTaskNodeSnapshot.new()
		node.node_id = StringName("%s/%s" % [card.definition_id, stage.stage_id])
		node.card_id = card.definition_id
		node.commander_id = card.commander_definition_id
		node.phase = stage.phase
		node.baseline_strength = card.available_strength if card.deployment_state == UnitCardState.DeploymentState.RESERVE else card.current_strength
		node.timeout_ticks = stage.timeout_ticks
		node.dwell_ticks = stage.dwell_ticks
		node.arrival_radius = stage.arrival_radius
		node.earliest_tick = world.current_tick
		node.changed_tick = world.current_tick
		node.target_position = safe_position if stage.phase in [Phase.MUSTER, Phase.RETREAT] else objective.position
		if stage.phase == Phase.MUSTER and card.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
			node.target_position = card.center_position
		node.route_points = PackedVector2Array([node.target_position])
		node.requires_deployment = stage.phase == Phase.MUSTER and card.deployment_state == UnitCardState.DeploymentState.RESERVE
		node.supply_cost = card.supply_cost if node.requires_deployment else 0
		node.is_required = stage.phase != Phase.RECON
		for prerequisite in stage.prerequisite_ids:
			node.prerequisite_ids.append(StringName("%s/%s" % [card.definition_id, prerequisite]))
		graph.nodes.append(node)
	graph.nodes.sort_custom(func(a: CommanderTaskNodeSnapshot, b: CommanderTaskNodeSnapshot) -> bool: return String(a.node_id) < String(b.node_id))


func _reject(reason: CommandValidationResult.Reason) -> CommandValidationResult:
	return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, reason)
