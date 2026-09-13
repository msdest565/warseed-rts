class_name CommanderTaskGraphAgent
extends RefCounted

const Phase := CommanderTaskStageDefinition.Phase
const Life := CommanderTaskNodeSnapshot.Lifecycle
const Action := CommanderCardTaskCommand.Action


func propose(snapshot: WorldSnapshot, graph: CommanderTaskGraphSnapshot) -> Array[CommanderCardTaskCommand]:
	var commands: Array[CommanderCardTaskCommand] = []
	if snapshot == null or graph == null or snapshot.is_true_state or snapshot.observer_faction_id != graph.faction_id \
			or snapshot.knowledge == null or snapshot.knowledge.faction_id != graph.faction_id \
			or snapshot.outcome != null and snapshot.outcome.is_terminal():
		return commands
	var nodes := graph.nodes.duplicate()
	nodes.sort_custom(func(a: CommanderTaskNodeSnapshot, b: CommanderTaskNodeSnapshot) -> bool: return String(a.node_id) < String(b.node_id))
	for node in nodes:
		var action := expected_action(snapshot, graph, node)
		if action < 0:
			continue
		var commander := snapshot.get_commander(node.commander_id)
		if commander == null:
			continue
		var command := CommanderCardTaskCommand.new(0, graph.faction_id, GameCommand.IssuerKind.AGENT,
			snapshot.tick, graph.graph_id, node.node_id, action as CommanderCardTaskCommand.Action)
		command.agent_id = commander.agent_id
		command.task_id = node.task_id
		commands.append(command)
	return commands


func expected_action(snapshot: WorldSnapshot, graph: CommanderTaskGraphSnapshot, node: CommanderTaskNodeSnapshot) -> int:
	if node.lifecycle in [Life.COMPLETED, Life.SKIPPED, Life.FAILED, Life.CANCELLED]:
		return -1
	if node.phase == Phase.RETREAT and not graph.retreat_requested:
		return -1
	if node.phase != Phase.RETREAT and graph.retreat_requested:
		return Action.CANCEL
	if node.lifecycle == Life.BLOCKED:
		return -1
	var card := snapshot.get_unit_card(node.card_id)
	if card == null:
		return Action.FAIL
	var overridden := card.is_player_overridden or card.control_state in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.RETURNING]
	if overridden:
		return Action.PAUSE if node.lifecycle != Life.PAUSED else -1
	if node.lifecycle == Life.PAUSED:
		return Action.RESUME
	if card.deployment_state == UnitCardState.DeploymentState.WITHDRAWN:
		return Action.COMPLETE if node.phase == Phase.RETREAT else Action.FAIL
	if card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.current_strength == 0:
		return Action.FAIL
	if node.lifecycle == Life.WAITING:
		for id in node.prerequisite_ids:
			var prerequisite := graph.get_node(id)
			if prerequisite != null and prerequisite.lifecycle in [Life.FAILED, Life.CANCELLED]:
				return Action.CANCEL
			if prerequisite != null and prerequisite.lifecycle == Life.BLOCKED:
				return Action.BLOCK
		if snapshot.tick < node.earliest_tick or not graph.dependencies_satisfied(node):
			return -1
		if not node.is_required:
			return Action.SKIP
		if node.phase == Phase.RETREAT and card.deployment_state == UnitCardState.DeploymentState.RESERVE:
			return Action.SKIP
		return Action.START
	if node.started_tick >= 0 and snapshot.tick - node.started_tick - node.paused_duration_ticks >= node.timeout_ticks:
		return Action.FAIL
	if card.deployment_state == UnitCardState.DeploymentState.DEPLOYING:
		return -1
	if node.task_id == 0:
		return Action.START if card.deployment_state == UnitCardState.DeploymentState.DEPLOYED else -1
	var task := snapshot.get_task(node.task_id)
	if task == null or task.lifecycle in [TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
		return Action.CANCEL
	if task.lifecycle == TaskState.Lifecycle.BLOCKED:
		return Action.BLOCK
	if card.assigned_task_id != node.task_id and task.lifecycle != TaskState.Lifecycle.COMPLETED:
		return Action.CANCEL
	var formation := snapshot.get_formation(card.formation_id)
	var arrived := formation != null and formation.anchor_position.distance_to(task.target_position) <= node.arrival_radius
	var condition := arrived
	if node.phase in [Phase.ENGAGE, Phase.EXPLOIT]:
		var objective := snapshot.get_strategic_region(graph.approved_plan.objective_region_id)
		condition = arrived and objective != null and objective.controller_faction_id == graph.faction_id and not objective.contested
	if node.phase in [Phase.RECON, Phase.EXPLOIT, Phase.RETREAT]:
		for unit in snapshot.units:
			if unit.enabled and unit.faction_id != graph.faction_id and unit.is_visible_to_local_player \
					and unit.position.distance_to(node.target_position) <= node.arrival_radius:
				condition = false
	if not condition:
		return Action.RESET_PROGRESS if node.progress_ticks > 0 else -1
	return Action.COMPLETE if node.progress_ticks + 1 >= node.dwell_ticks else Action.PROGRESS


func transition_reason(snapshot: WorldSnapshot, graph: CommanderTaskGraphSnapshot, node: CommanderTaskNodeSnapshot, action: int) -> StringName:
	if graph.retreat_requested and node.phase != Phase.RETREAT:
		return &"COMMANDER_GRAPH_PLAYER_RETREAT"
	var card := snapshot.get_unit_card(node.card_id)
	if card == null or card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.current_strength == 0:
		return &"COMMANDER_GRAPH_CARD_LOST"
	if card.deployment_state == UnitCardState.DeploymentState.WITHDRAWN:
		return &"COMMANDER_GRAPH_CARD_WITHDRAWN"
	for id in node.prerequisite_ids:
		var prerequisite := graph.get_node(id)
		if prerequisite != null and prerequisite.lifecycle in [Life.BLOCKED, Life.FAILED, Life.CANCELLED]:
			return &"COMMANDER_GRAPH_DEPENDENCY_FAILED"
	if action == Action.FAIL and node.started_tick >= 0 and snapshot.tick - node.started_tick - node.paused_duration_ticks >= node.timeout_ticks:
		return &"COMMANDER_GRAPH_TIMEOUT"
	return &"COMMANDER_GRAPH_TASK_BLOCKED" if action == Action.BLOCK else &"COMMANDER_GRAPH_TASK_REPLACED"
