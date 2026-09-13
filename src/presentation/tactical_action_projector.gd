class_name TacticalActionProjector
extends RefCounted


func project(snapshot: WorldSnapshot, battle: BattleDefinition) -> Array[CardActionSnapshot]:
	var result: Array[CardActionSnapshot] = []
	if snapshot == null or snapshot.is_true_state or snapshot.knowledge == null or snapshot.knowledge.faction_id != snapshot.observer_faction_id or battle == null:
		return result
	var faction := snapshot.get_faction(snapshot.observer_faction_id)
	if faction == null:
		return result
	for card in snapshot.unit_cards:
		if card.faction_id != snapshot.observer_faction_id or card.tactical_kind < 0 or card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		var definition: UnitCardDefinition
		for candidate in battle.unit_card_definitions:
			if candidate.definition_id == card.definition_id:
				definition = candidate
				break
		if definition == null or definition.tactical_ability == null:
			continue
		var ability := definition.tactical_ability
		match ability.kind:
			TacticalAbilityDefinition.Kind.OBSERVE:
				result.append(_make(snapshot, faction, card, ability, card.center_position))
			TacticalAbilityDefinition.Kind.OPEN_ROUTE:
				for route in battle.engineering_routes:
					if not faction.opened_engineering_route_ids.has(route.route_id) and not route.cleared_rects.is_empty():
						var point := Vector2(route.cleared_rects[0].position) * LogicGrid.CELL_SIZE + Vector2(route.cleared_rects[0].size) * LogicGrid.CELL_SIZE * 0.5
						var decision := _make(snapshot, faction, card, ability, point, route.route_id)
						decision.target_name_key = route.display_name_key
						result.append(decision)
			TacticalAbilityDefinition.Kind.SUPPRESS:
				var targets: Dictionary = {}
				for unit in snapshot.units:
					if unit.faction_id != card.faction_id and unit.enabled and unit.is_visible_to_local_player:
						# One decision per visible formation, using only observed members.
						var group := "formation:%d" % unit.formation_id if unit.formation_id != 0 else "entity:%d" % unit.entity_id
						var previous := targets.get(group) as UnitSnapshot
						if previous == null or _prefer_target(snapshot, card, ability, unit, previous):
							targets[group] = unit
				for group in targets:
					var unit := targets[group] as UnitSnapshot
					var decision := _make(snapshot, faction, card, ability, unit.position, &"", unit.entity_id)
					decision.decision_id = StringName("tactical:%s:%s" % [card.definition_id, group])
					decision.target_name_key = StringName("UNIT_%s" % String(unit.definition_id).to_upper())
					decision.identification_ticks = maxi(0, int(snapshot.knowledge.identification_until_by_entity.get(unit.entity_id, 0)) - snapshot.tick)
					if decision.identification_ticks <= 0:
						decision.reason = CommandValidationResult.Reason.TARGET_UNIDENTIFIED
					if not _has_firing_member(snapshot, card, unit.position):
						decision.reason = CommandValidationResult.Reason.CAPABILITY_LOST
					result.append(decision)
			TacticalAbilityDefinition.Kind.BREAKTHROUGH:
				var commander := snapshot.get_commander(card.commander_definition_id)
				var target := snapshot.get_strategic_region(commander.target_region_id) if commander != null else null
				if target != null:
					var decision := _make(snapshot, faction, card, ability, target.position, target.region_id)
					decision.target_name_key = target.display_name_key
					result.append(decision)
			TacticalAbilityDefinition.Kind.RESUPPLY:
				for target in snapshot.unit_cards:
					if target.faction_id == card.faction_id and target.deployment_state == UnitCardState.DeploymentState.DEPLOYED and (target.ammunition < target.ammunition_capacity or target.organization_enabled and target.organization < battle.organization_max):
						var decision := _make(snapshot, faction, card, ability, target.center_position, target.definition_id)
						decision.target_name_key = target.display_name_key
						result.append(decision)
	result.sort_custom(func(a: CardActionSnapshot, b: CardActionSnapshot) -> bool: return String(a.decision_id) < String(b.decision_id))
	return result


func _prefer_target(snapshot: WorldSnapshot, card: UnitCardSnapshot, ability: TacticalAbilityDefinition, candidate: UnitSnapshot, previous: UnitSnapshot) -> bool:
	var candidate_ready := _target_ready(snapshot, card, ability, candidate)
	var previous_ready := _target_ready(snapshot, card, ability, previous)
	if candidate_ready != previous_ready:
		return candidate_ready
	var candidate_distance := card.center_position.distance_squared_to(candidate.position)
	var previous_distance := card.center_position.distance_squared_to(previous.position)
	return candidate_distance < previous_distance if candidate_distance != previous_distance else candidate.entity_id < previous.entity_id


func _target_ready(snapshot: WorldSnapshot, card: UnitCardSnapshot, ability: TacticalAbilityDefinition, unit: UnitSnapshot) -> bool:
	return int(snapshot.knowledge.identification_until_by_entity.get(unit.entity_id, 0)) > snapshot.tick and card.center_position.distance_to(unit.position) <= ability.range and _has_firing_member(snapshot, card, unit.position)


func _has_firing_member(snapshot: WorldSnapshot, card: UnitCardSnapshot, point: Vector2) -> bool:
	for id in card.active_member_entity_ids:
		var member := snapshot.get_unit(id)
		if member != null and member.ammunition > 0 and card.center_position.distance_to(point) >= member.minimum_attack_range:
			return true
	return false


func _make(snapshot: WorldSnapshot, faction: FactionSnapshot, card: UnitCardSnapshot, ability: TacticalAbilityDefinition, point: Vector2, target: StringName = &"", entity: int = 0) -> CardActionSnapshot:
	var decision := CardActionSnapshot.new()
	decision.unit_card_id = card.definition_id
	decision.commander_id = card.commander_definition_id
	decision.card_name_key = card.display_name_key
	var commander := snapshot.get_commander(card.commander_definition_id)
	decision.commander_name_key = commander.display_name_key if commander != null else &"COMMAND_DESK_FORCE_WIDE"
	decision.action_kind = CardActionSnapshot.TACTICAL + ability.kind
	decision.tactical_name_key = ability.name_key
	decision.tactical_help_key = ability.help_key
	decision.position = point
	decision.route = PackedVector2Array([card.center_position, point])
	decision.target_id = target
	decision.target_entity_id = entity
	decision.target_name_key = card.display_name_key
	decision.decision_id = StringName("tactical:%s:%s:%d" % [card.definition_id, target, entity])
	decision.current_strength = card.current_strength
	decision.authorized_strength = card.authorized_strength
	decision.supply_cost = ability.supply_cost
	decision.available_supply = faction.supply
	decision.population = faction.population
	decision.population_capacity = faction.population_capacity
	decision.cooldown_ticks = maxi(0, card.tactical_ready_tick - snapshot.tick)
	if card.center_position.distance_to(point) > ability.range:
		decision.reason = CommandValidationResult.Reason.OUT_OF_RANGE
	if not card.has_active_unit_type(ability.required_unit_id):
		decision.reason = CommandValidationResult.Reason.CAPABILITY_LOST
	if ability.kind in [TacticalAbilityDefinition.Kind.SUPPRESS, TacticalAbilityDefinition.Kind.BREAKTHROUGH] and card.organization < maxf(30.0, ability.organization_cost):
		decision.reason = CommandValidationResult.Reason.LOW_ORGANIZATION
	if decision.cooldown_ticks > 0:
		decision.reason = CommandValidationResult.Reason.TACTICAL_BUSY
	if faction.supply < ability.supply_cost:
		decision.reason = CommandValidationResult.Reason.INSUFFICIENT_SUPPLY
	return decision


static func command_for(decision: CardActionSnapshot, id: int, faction: int, tick: int, issuer: GameCommand.IssuerKind = GameCommand.IssuerKind.PLAYER) -> TacticalAbilityCommand:
	var kind := decision.action_kind - CardActionSnapshot.TACTICAL
	return TacticalAbilityCommand.new(id, faction, issuer, tick, decision.unit_card_id, decision.position, decision.target_entity_id, decision.target_id if kind == TacticalAbilityDefinition.Kind.RESUPPLY else &"", decision.target_id if kind == TacticalAbilityDefinition.Kind.OPEN_ROUTE else &"")
