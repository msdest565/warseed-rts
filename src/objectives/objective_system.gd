class_name ObjectiveSystem
extends RefCounted

var definition: BattleObjectiveSetDefinition
var states: Dictionary = {}
var outcome := BattleOutcome.new()


func configure(new_definition: BattleObjectiveSetDefinition) -> void:
	definition = new_definition
	states.clear()
	outcome = BattleOutcome.new()
	if definition == null:
		return
	for objective in definition.objectives:
		if objective != null:
			states[objective.objective_id] = ObjectiveState.new(objective)


func advance(world, target_events: Array[SimulationEvent], tick: int) -> BattleOutcome:
	if definition == null or outcome.is_terminal():
		return outcome
	var objective_ids := states.keys()
	objective_ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for objective_id in objective_ids:
		var state := states[objective_id] as ObjectiveState
		if state.status == ObjectiveState.Status.ACTIVE and _is_completed(state.definition, world, tick):
			state.complete(tick)
	var candidates: Array[ObjectiveGroupDefinition] = []
	for group in definition.conclusion_groups:
		if group != null and _group_is_completed(group):
			candidates.append(group)
	if candidates.is_empty():
		return outcome
	candidates.sort_custom(func(left: ObjectiveGroupDefinition, right: ObjectiveGroupDefinition) -> bool:
		if left.priority != right.priority:
			return left.priority > right.priority
		return String(left.group_id) < String(right.group_id)
	)
	var selected := candidates[0]
	var reasons: Array[StringName] = []
	reasons.assign(selected.objective_ids)
	outcome = BattleOutcome.new(selected.outcome_result, selected.outcome_grade, tick, selected.group_id, reasons)
	_finalize_objective_states(tick)
	_apply_compatibility_faction_result(world, target_events, tick)
	target_events.append(BattleConclusionEvent.new(tick, outcome))
	return outcome


func create_snapshots() -> Array[ObjectiveSnapshot]:
	var snapshots: Array[ObjectiveSnapshot] = []
	var objective_ids := states.keys()
	objective_ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	for objective_id in objective_ids:
		snapshots.append(ObjectiveSnapshot.new(states[objective_id] as ObjectiveState))
	return snapshots


func _is_completed(objective: BattleObjectiveDefinition, world, tick: int) -> bool:
	match objective.kind:
		BattleObjectiveDefinition.Kind.DESTROY_ENTITY:
			var building = world.buildings.get(objective.target_entity_id)
			if building != null:
				return not building.enabled or building.health <= 0.0
			var unit = world.units.get(objective.target_entity_id)
			return unit != null and (not unit.enabled or unit.health <= 0.0)
		BattleObjectiveDefinition.Kind.TIME_LIMIT_REACHED:
			var target_tick := objective.target_tick
			if target_tick <= 0 and world.battle_definition != null:
				target_tick = world.battle_definition.time_limit_ticks
			return target_tick > 0 and tick >= target_tick
		BattleObjectiveDefinition.Kind.ESCORT_UNIT_CARD_TO_REGION:
			var card = world.unit_cards.get(objective.unit_card_id)
			var region = world.strategic_regions.get(objective.region_id)
			if card == null or region == null:
				return false
			var arrived := 0
			for entity_id in card.member_entity_ids:
				var member = world.units.get(entity_id)
				if member != null and member.enabled and member.position.distance_to(region.position) <= objective.arrival_radius:
					arrived += 1
			return arrived >= objective.minimum_strength
		BattleObjectiveDefinition.Kind.WITHDRAW_UNIT_CARD:
			var card = world.unit_cards.get(objective.unit_card_id)
			return card != null and card.deployment_state == UnitCardState.DeploymentState.WITHDRAWN and card.withdrawn_strength >= objective.minimum_strength
	return false


func _group_is_completed(group: ObjectiveGroupDefinition) -> bool:
	if group.rule == ObjectiveGroupDefinition.Rule.ANY:
		for objective_id in group.objective_ids:
			var state := states.get(objective_id) as ObjectiveState
			if state != null and state.status == ObjectiveState.Status.COMPLETED:
				return true
		return false
	for objective_id in group.objective_ids:
		var state := states.get(objective_id) as ObjectiveState
		if state == null or state.status != ObjectiveState.Status.COMPLETED:
			return false
	return true


func _finalize_objective_states(tick: int) -> void:
	for state_value in states.values():
		var state := state_value as ObjectiveState
		if state != null:
			state.fail(tick)


func _apply_compatibility_faction_result(world, target_events: Array[SimulationEvent], tick: int) -> void:
	var local_faction := world.factions.get(SimulationWorld.LOCAL_PLAYER_ID) as FactionState
	var enemy_faction := world.factions.get(SimulationWorld.ENEMY_PLAYER_ID) as FactionState
	if outcome.result == BattleOutcome.Result.VICTORY:
		if local_faction != null and not local_faction.victorious:
			local_faction.victorious = true
			target_events.append(SimulationEvent.new(tick, SimulationEvent.Kind.FACTION_VICTORIOUS, SimulationWorld.LOCAL_PLAYER_ID, String(outcome.conclusion_group_id)))
	elif outcome.result == BattleOutcome.Result.DEFEAT:
		if local_faction != null and not local_faction.defeated:
			local_faction.defeated = true
			target_events.append(SimulationEvent.new(tick, SimulationEvent.Kind.FACTION_DEFEATED, SimulationWorld.LOCAL_PLAYER_ID, String(outcome.conclusion_group_id)))
		if enemy_faction != null and not enemy_faction.victorious:
			enemy_faction.victorious = true
			target_events.append(SimulationEvent.new(tick, SimulationEvent.Kind.FACTION_VICTORIOUS, SimulationWorld.ENEMY_PLAYER_ID, String(outcome.conclusion_group_id)))
