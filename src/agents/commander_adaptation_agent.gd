class_name CommanderAdaptationAgent
extends RefCounted

const Action := CommanderCardTaskCommand.Action
const Phase := CommanderTaskStageDefinition.Phase
const Life := CommanderTaskNodeSnapshot.Lifecycle


func propose(snapshot: WorldSnapshot, graph: CommanderTaskGraphSnapshot) -> Array[CommanderCardTaskCommand]:
	var result: Array[CommanderCardTaskCommand] = []
	if snapshot == null or graph == null or snapshot.is_true_state or snapshot.observer_faction_id != graph.faction_id or snapshot.knowledge == null or snapshot.knowledge.faction_id != graph.faction_id:
		return result
	if snapshot.outcome != null and snapshot.outcome.is_terminal() or snapshot.tick < graph.next_adaptation_tick or not graph.adaptation_policy.validate().is_valid():
		return result
	var faction := snapshot.get_faction(graph.faction_id)
	if faction == null:
		return result
	var nodes := graph.nodes.duplicate()
	nodes.sort_custom(func(a: CommanderTaskNodeSnapshot, b: CommanderTaskNodeSnapshot) -> bool: return String(a.node_id) < String(b.node_id))
	var cards: Array[UnitCardSnapshot] = []
	var ids: Array[StringName] = []
	for node in nodes:
		if node.phase == Phase.RETREAT or node.lifecycle in [Life.COMPLETED, Life.SKIPPED, Life.FAILED, Life.CANCELLED] or ids.has(node.card_id):
			continue
		var card := snapshot.get_unit_card(node.card_id)
		if not _controllable(snapshot, card):
			continue
		ids.append(node.card_id)
		cards.append(card)
	var baseline := 0
	var strength := 0
	var first_survivor: UnitCardSnapshot
	var damaged: Array[UnitCardSnapshot] = []
	for card in cards:
		if card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		var original := _baseline(nodes, card.definition_id)
		baseline += original
		strength += card.current_strength
		if card.current_strength > 0:
			if first_survivor == null:
				first_survivor = card
			if card.current_strength < original and float(card.current_strength) <= original * graph.adaptation_policy.reinforce_ratio:
				damaged.append(card)
	if not graph.retreat_requested and first_survivor != null and baseline > 0 and float(strength) <= baseline * graph.adaptation_policy.retreat_ratio:
		result.append(_command(snapshot, graph, first_survivor, Action.AUTO_RETREAT))
		return result
	if not graph.retreat_requested and graph.reinforcement_requests < graph.adaptation_policy.max_reinforcements and faction.reinforcement_cooldown_until_tick <= snapshot.tick and int(faction.support_cooldown_until_by_kind.get(SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, 0)) <= snapshot.tick:
		for card in damaged:
			if card.current_strength < card.authorized_strength and graph.reinforcement_supply_cost <= mini(graph.adaptation_budget_remaining, faction.supply):
				result.append(_command(snapshot, graph, card, Action.REINFORCE))
	var reconnaissance_contact := false
	var reconnaissance_complete := false
	for node in nodes:
		if node.phase == Phase.RECON and node.is_required and node.lifecycle == Life.COMPLETED:
			reconnaissance_complete = true
		if node.phase != Phase.RECON or node.lifecycle not in [Life.ACTIVE, Life.BLOCKED]:
			continue
		for hostile in snapshot.units:
			if hostile.faction_id != graph.faction_id and hostile.enabled and hostile.is_visible_to_local_player and hostile.position.distance_to(node.target_position) <= node.arrival_radius * 2.0:
				reconnaissance_contact = true
	if not graph.retreat_requested and (strength < baseline or reconnaissance_contact or reconnaissance_complete) and graph.reserve_commits < graph.adaptation_policy.max_reserve_commits:
		var reserve_ids := graph.reserve_card_ids.duplicate()
		reserve_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		for id in reserve_ids:
			var card := snapshot.get_unit_card(id)
			if not _controllable(snapshot, card):
				continue
			var deployed := card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.current_strength > 0
			var fresh := card.deployment_state == UnitCardState.DeploymentState.RESERVE and card.available_strength > 0 and card.supply_cost <= mini(graph.adaptation_budget_remaining, faction.supply)
			if deployed or fresh:
				result.append(_command(snapshot, graph, card, Action.COMMIT_RESERVE))
	var replans_used := graph.retreat_replan_count if graph.retreat_requested else graph.replan_count
	if replans_used < graph.adaptation_policy.max_replans:
		for node in nodes:
			if node.lifecycle != Life.BLOCKED or (node.phase == Phase.RETREAT) != graph.retreat_requested or snapshot.tick - node.changed_tick < graph.adaptation_policy.interval_ticks or not graph.dependencies_satisfied(node):
				continue
			var card := snapshot.get_unit_card(node.card_id)
			if _controllable(snapshot, card) and card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.current_strength > 0:
				var command := _command(snapshot, graph, card, Action.REPLAN)
				command.node_id = node.node_id
				result.append(command)
	return result


func _controllable(snapshot: WorldSnapshot, card: UnitCardSnapshot) -> bool:
	return card != null and card.faction_id == snapshot.observer_faction_id and not card.is_player_overridden and card.control_state not in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.RETURNING] and card.deployment_state != UnitCardState.DeploymentState.WITHDRAWN and snapshot.get_commander(card.commander_definition_id) != null


func _baseline(nodes: Array[CommanderTaskNodeSnapshot], id: StringName) -> int:
	for node in nodes:
		if node.card_id == id and node.phase == Phase.MUSTER:
			return node.baseline_strength
	return 0


func _command(snapshot: WorldSnapshot, graph: CommanderTaskGraphSnapshot, card: UnitCardSnapshot, action: CommanderCardTaskCommand.Action) -> CommanderCardTaskCommand:
	var command := CommanderCardTaskCommand.new(0, graph.faction_id, GameCommand.IssuerKind.AGENT, snapshot.tick, graph.graph_id, &"adaptation", action)
	command.graph_revision = graph.revision
	command.target_card_id = card.definition_id
	command.agent_id = snapshot.get_commander(card.commander_definition_id).agent_id
	return command
