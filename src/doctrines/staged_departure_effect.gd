class_name StagedDepartureEffect
extends RefCounted


func build(snapshot: WorldSnapshot, commander: CommanderSnapshot, card: UnitCardSnapshot, doctrine: DoctrineDefinition, definition: DoctrineEffectDefinition) -> DoctrineTaskParameters:
	var result := DoctrineTaskParameters.new()
	var ordered_ids := commander.subordinate_unit_card_ids.duplicate()
	ordered_ids.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	var ordinal := 0
	for card_id in ordered_ids:
		var candidate := snapshot.get_unit_card(card_id)
		if candidate == null or candidate.faction_id != commander.faction_id or candidate.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		if candidate.definition_id == card.definition_id:
			result.applied = true
			result.activation_tick = snapshot.tick + definition.timing.base_delay_ticks + ordinal * definition.timing.interval_ticks
			result.trigger_tick = snapshot.tick
			result.doctrine_id = doctrine.definition_id
			result.effect_id = definition.effect_id
			result.waiting_reason_key = definition.reason.waiting_reason_key
			result.description_key = definition.reason.description_key
			result.cost_key = definition.cost.explanation_key
			result.counterplay_key = definition.counterplay.explanation_key
			result.exit_condition = definition.counterplay.exit_condition
			return result
		ordinal += 1
	result.rejection_reason = &"CARD_NOT_ELIGIBLE"
	return result
