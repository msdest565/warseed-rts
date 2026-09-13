class_name CommanderTaskGraphBuilder
extends RefCounted

const DEFAULT_DEFINITION: CommanderTaskGraphDefinition = preload("res://data/ai/commander_task_graph.tres")

var last_rejection_reason: StringName


func build(snapshot: WorldSnapshot, plan: StaffCourseOfAction, definition: CommanderTaskGraphDefinition = DEFAULT_DEFINITION) -> CommanderTaskGraphSnapshot:
	last_rejection_reason = &""
	if snapshot == null or snapshot.is_true_state or snapshot.knowledge == null or snapshot.knowledge.faction_id != snapshot.observer_faction_id:
		return _reject(&"FACTION_KNOWLEDGE_REQUIRED")
	if plan == null or definition == null or not definition.validate().is_valid():
		return _reject(&"INVALID_GRAPH_DEFINITION")
	if snapshot.outcome != null and snapshot.outcome.is_terminal():
		return _reject(&"BATTLE_ENDED")
	var is_approved := false
	for decision in snapshot.staff_plan_decisions:
		if decision.faction_id == snapshot.observer_faction_id and decision.approved_plan != null \
				and decision.approved_plan.fingerprint() == plan.fingerprint():
			is_approved = true
	if not is_approved:
		return _reject(&"APPROVED_PLAN_REQUIRED")
	var objective := snapshot.get_strategic_region(plan.objective_region_id)
	if objective == null or plan.assignments.is_empty():
		return _reject(&"INVALID_GRAPH_OBJECTIVE")
	var headquarters: BuildingSnapshot
	for building in snapshot.buildings:
		if building.faction_id == snapshot.observer_faction_id and building.enabled and building.definition_id == &"command_center" \
				and (headquarters == null or building.entity_id < headquarters.entity_id):
			headquarters = building
	if headquarters == null:
		return _reject(&"RETREAT_DESTINATION_REQUIRED")
	var assigned_ids: Array[StringName] = []
	for assignment in plan.assignments:
		var card := snapshot.get_unit_card(assignment.card_id)
		if card == null or card.faction_id != snapshot.observer_faction_id or card.commander_definition_id != assignment.commander_id \
				or assignment.route_points.is_empty() or assigned_ids.has(assignment.card_id) or plan.reserve_card_ids.has(assignment.card_id):
			return _reject(&"INVALID_GRAPH_ASSIGNMENT")
		for point in assignment.route_points:
			if not point.is_finite():
				return _reject(&"INVALID_GRAPH_ROUTE")
		assigned_ids.append(assignment.card_id)
	var graph := CommanderTaskGraphSnapshot.new()
	graph.graph_id = StringName("operation:%s" % plan.fingerprint())
	graph.faction_id = snapshot.observer_faction_id
	graph.approved_plan = plan.duplicate_value()
	graph.created_tick = snapshot.tick
	graph.reserve_card_ids.assign(plan.reserve_card_ids)
	graph.reserve_card_ids.sort()
	for assignment in plan.assignments:
		for stage in definition.stages:
			var node := CommanderTaskNodeSnapshot.new()
			node.node_id = _node_id(assignment.card_id, stage.stage_id)
			node.card_id = assignment.card_id
			node.commander_id = assignment.commander_id
			node.phase = stage.phase
			node.timeout_ticks = stage.timeout_ticks
			node.dwell_ticks = stage.dwell_ticks
			node.arrival_radius = stage.arrival_radius
			node.earliest_tick = snapshot.tick + (assignment.preparation_ticks if stage.phase == CommanderTaskStageDefinition.Phase.MUSTER else 0)
			node.changed_tick = snapshot.tick
			for prerequisite in stage.prerequisite_ids:
				node.prerequisite_ids.append(_node_id(assignment.card_id, prerequisite))
			var origin := assignment.route_points[0]
			node.target_position = objective.position
			match stage.phase:
				CommanderTaskStageDefinition.Phase.MUSTER:
					node.target_position = _muster_position(plan, assignment.commander_id)
					node.requires_deployment = assignment.requires_deployment
					node.supply_cost = assignment.supply_cost
				CommanderTaskStageDefinition.Phase.RECON:
					node.is_required = assignment.role == StaffPlanAssignment.Role.RECONNAISSANCE
					node.target_position = origin.lerp(objective.position, 0.75)
				CommanderTaskStageDefinition.Phase.DEPLOY:
					node.target_position = assignment.route_points[1] if assignment.route_points.size() > 2 else origin.lerp(objective.position, 0.85)
					# Main forces cannot deploy before every assigned advance scout reports.
					for scout in plan.assignments:
						if scout.card_id != assignment.card_id and scout.role == StaffPlanAssignment.Role.RECONNAISSANCE:
							node.prerequisite_ids.append(_node_id(scout.card_id, definition.get_phase(CommanderTaskStageDefinition.Phase.RECON).stage_id))
				CommanderTaskStageDefinition.Phase.RETREAT:
					node.target_position = headquarters.position + Vector2(0.0, -160.0)
			node.route_points.append(node.target_position)
			node.prerequisite_ids.sort()
			graph.nodes.append(node)
	graph.nodes.sort_custom(func(a: CommanderTaskNodeSnapshot, b: CommanderTaskNodeSnapshot) -> bool: return String(a.node_id) < String(b.node_id))
	return graph


func _node_id(card_id: StringName, stage_id: StringName) -> StringName:
	return StringName("%s/%s" % [card_id, stage_id])


func _muster_position(plan: StaffCourseOfAction, commander_id: StringName) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	# Use stable card order so resource ordering cannot change float summation.
	var assignments := plan.assignments.duplicate()
	assignments.sort_custom(func(a: StaffPlanAssignment, b: StaffPlanAssignment) -> bool: return String(a.card_id) < String(b.card_id))
	for assignment in assignments:
		if assignment.commander_id == commander_id:
			sum += assignment.route_points[0]
			count += 1
	return sum / maxi(1, count)


func _reject(reason: StringName) -> CommanderTaskGraphSnapshot:
	last_rejection_reason = reason
	return null
