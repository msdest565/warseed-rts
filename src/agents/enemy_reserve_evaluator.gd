class_name EnemyReserveEvaluator
extends RefCounted

static func release_reason(
	snapshot: WorldSnapshot,
	state: EnemyOperationSnapshot,
	node: EnemyOperationPhaseSnapshot,
	policy: EnemyReservePolicy
) -> StringName:
	if snapshot == null or state == null or node == null or policy == null:
		return &""
	if not policy.validate().is_valid():
		return &""
	if node.definition == null:
		return &""
	if snapshot.is_true_state:
		return &""
	if snapshot.observer_faction_id != 2:
		return &""
	if snapshot.knowledge == null or snapshot.knowledge.faction_id != 2:
		return &""
	if state.withdrawing:
		return &""
	if snapshot.tick < policy.minimum_hold_ticks:
		return &""
	if node.status != EnemyOperationPhaseSnapshot.Status.WAITING:
		return &""

	var alive := 0
	for formation_id in state.committed_formation_ids:
		var formation = snapshot.get_formation(formation_id)
		if formation == null:
			continue
		for unit_id in formation.member_entity_ids:
			var unit = snapshot.get_unit(unit_id)
			if unit != null and unit.enabled and unit.faction_id == 2:
				alive += 1

	if state.initial_committed_strength > 0:
		if float(alive) <= float(state.initial_committed_strength) * policy.release_loss_ratio:
			return &"OWN_LOSSES"

	var radius_squared := policy.visible_contact_radius * policy.visible_contact_radius
	for unit in snapshot.units:
		if (
			unit != null
			and unit.enabled
			and unit.faction_id != 2
			and unit.is_visible_to_local_player
			and unit.position.distance_squared_to(node.definition.target_position) <= radius_squared
		):
			return &"VISIBLE_CONTACT"

	if policy.release_on_objective_reached:
		for phase in state.phases:
			if (
				phase != null
				and phase.definition != null
				and phase.definition.phase_id == policy.release_phase_id
				and phase.status == EnemyOperationPhaseSnapshot.Status.COMPLETED
			):
				return &"OBJECTIVE_REACHED"

	return &""
