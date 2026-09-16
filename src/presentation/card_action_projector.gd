class_name CardActionProjector
extends RefCounted


func project(snapshot: WorldSnapshot, battle: BattleDefinition) -> Array[CardActionSnapshot]:
	var result: Array[CardActionSnapshot] = []
	if snapshot == null or battle == null or snapshot.is_true_state or snapshot.knowledge == null:
		return result
	if snapshot.observer_faction_id != snapshot.knowledge.faction_id:
		return result
	var faction := snapshot.get_faction(snapshot.observer_faction_id)
	if faction == null:
		return result
	result.append_array(TacticalActionProjector.new().project(snapshot, battle))
	var headquarters := _headquarters_actions(snapshot)
	result.append_array(headquarters)
	if headquarters.is_empty():
		result.append_array(_recon_actions(snapshot, battle))
	for card in snapshot.unit_cards:
		if card.faction_id != snapshot.observer_faction_id:
			continue
		if card.deployment_state == UnitCardState.DeploymentState.RESERVE and card.available_strength > 0:
			result.append(_make(snapshot, battle, faction, card, CardActionSnapshot.DEPLOY))
		if card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		for kind in [SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY, SupportOrderCommand.SupportKind.RAPID_MOBILITY, SupportOrderCommand.SupportKind.FRONTLINE_LOGISTICS, SupportOrderCommand.SupportKind.ENGINEERING_ROUTE]:
			if battle.support_for_kind(kind) == null:
				continue
			if kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT and card.current_strength >= card.authorized_strength:
				continue
			if kind == SupportOrderCommand.SupportKind.FRONTLINE_LOGISTICS and not _needs_logistics(snapshot, card, battle.organization_max):
				continue
			if kind == SupportOrderCommand.SupportKind.ENGINEERING_ROUTE:
				if not card.has_active_unit_type(&"engineer_vehicle"):
					continue
				for engineering_route in battle.engineering_routes:
					if not faction.opened_engineering_route_ids.has(engineering_route.route_id):
						result.append(_make(snapshot, battle, faction, card, kind, engineering_route))
			else:
				result.append(_make(snapshot, battle, faction, card, kind))
	result.sort_custom(func(a: CardActionSnapshot, b: CardActionSnapshot) -> bool:
		if (a.action_kind == CardActionSnapshot.ATTACK_HEADQUARTERS) != (b.action_kind == CardActionSnapshot.ATTACK_HEADQUARTERS):
			return a.action_kind == CardActionSnapshot.ATTACK_HEADQUARTERS
		var a_priority := 0 if a.action_kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT else (1 if a.action_kind == CardActionSnapshot.DEPLOY else 2)
		var b_priority := 0 if b.action_kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT else (1 if b.action_kind == CardActionSnapshot.DEPLOY else 2)
		return a_priority < b_priority if a_priority != b_priority else String(a.decision_id) < String(b.decision_id)
	)
	return result


func _recon_actions(snapshot: WorldSnapshot, battle: BattleDefinition) -> Array[CardActionSnapshot]:
	var result: Array[CardActionSnapshot] = []
	var held := 0
	for region in snapshot.strategic_regions:
		if not region.capturable:
			continue
		if region.controller_faction_id != snapshot.observer_faction_id:
			return result
		held += 1
	if held == 0 or snapshot.outcome != null and snapshot.outcome.is_terminal():
		return result
	# Building snapshots contain only legally known buildings. Never consult battle HQ coordinates.
	for building in snapshot.buildings:
		if building.enabled and building.faction_id != snapshot.observer_faction_id and building.definition_id == &"command_center":
			return result
	# Terrain is public authored data; apply only our published route openings.
	var grid := LogicGrid.create_for_battle(battle)
	var faction := snapshot.get_faction(snapshot.observer_faction_id)
	for route in battle.engineering_routes:
		if faction.opened_engineering_route_ids.has(route.route_id):
			for rect in route.cleared_rects:
				for x in range(rect.position.x, rect.end.x):
					for y in range(rect.position.y, rect.end.y):
						grid.set_blocked(Vector2i(x, y), false)
	var pathfinder := GridPathfinder.new(grid)
	for card in snapshot.unit_cards:
		if card.faction_id != snapshot.observer_faction_id or card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or not card.has_active_unit_type(&"scout_vehicle"):
			continue
		var commander := snapshot.get_commander(card.commander_definition_id)
		if commander == null:
			continue
		var formation := snapshot.get_formation(card.formation_id)
		var origin := formation.anchor_position if formation != null else card.center_position
		var point := _frontier(snapshot.knowledge, origin, grid, pathfinder)
		if not point.is_finite():
			continue
		var decision := CardActionSnapshot.new()
		decision.action_kind = CardActionSnapshot.CONTINUE_RECON
		decision.decision_id = StringName("continue_recon:%s" % card.definition_id)
		decision.unit_card_id = card.definition_id
		decision.card_name_key = card.display_name_key
		decision.commander_id = commander.definition_id
		decision.commander_name_key = commander.display_name_key
		decision.target_name_key = &"CARD_UNEXPLORED_FRONTIER"
		decision.position = point
		decision.route = PackedVector2Array([card.center_position, point])
		result.append(decision)
	return result


func _frontier(knowledge: FactionKnowledgeSnapshot, origin: Vector2, grid: LogicGrid, pathfinder: GridPathfinder) -> Vector2:
	var candidates: Array[Vector2] = []
	# Stable row-major scan of legal fog boundaries and public terrain.
	for y in range(1, knowledge.grid_size.y - 1):
		for x in range(1, knowledge.grid_size.x - 1):
			var cell := Vector2i(x, y)
			if grid.is_blocked(cell) or knowledge.get_cell_state(cell) != FactionKnowledge.CellState.UNEXPLORED:
				continue
			var frontier := false
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if knowledge.get_cell_state(cell + offset) != FactionKnowledge.CellState.UNEXPLORED:
					frontier = true
			if not frontier:
				continue
			candidates.append(grid.cell_to_world(cell))
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var ad := origin.distance_squared_to(a)
		var bd := origin.distance_squared_to(b)
		return ad < bd if ad != bd else (a.y < b.y if a.y != b.y else a.x < b.x))
	for point in candidates:
		if not pathfinder.find_path(origin, point).is_empty():
			return point
	return Vector2.INF


func _headquarters_actions(snapshot: WorldSnapshot) -> Array[CardActionSnapshot]:
	var result: Array[CardActionSnapshot] = []
	var commanders: Array[StringName] = []
	for building in snapshot.buildings:
		if not building.enabled or building.faction_id == snapshot.observer_faction_id or building.definition_id != &"command_center":
			continue
		for card in snapshot.unit_cards:
			if card.faction_id != snapshot.observer_faction_id or card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or card.current_strength <= 0 or commanders.has(card.commander_definition_id):
				continue
			var armed := false
			for id in card.active_member_entity_ids:
				var unit := snapshot.get_unit(id)
				armed = armed or unit != null and unit.can_attack and unit.can_accept_attack_orders and unit.tactical_role != UnitState.TacticalRole.SCOUT
			if not armed:
				continue
			var commander := snapshot.get_commander(card.commander_definition_id)
			if commander == null:
				continue
			commanders.append(card.commander_definition_id)
			var decision := CardActionSnapshot.new()
			decision.action_kind = CardActionSnapshot.ATTACK_HEADQUARTERS
			decision.decision_id = StringName("headquarters:%s:%d" % [commander.definition_id, building.entity_id])
			decision.commander_id = card.commander_definition_id
			decision.commander_name_key = commander.display_name_key
			decision.unit_card_id = card.definition_id
			decision.card_name_key = card.display_name_key
			decision.target_name_key = &"CARD_ENEMY_HEADQUARTERS"
			decision.target_entity_id = building.entity_id
			decision.position = building.position + building.position.direction_to(card.center_position) * 320.0
			decision.route = PackedVector2Array([card.center_position, decision.position])
			if snapshot.outcome != null and snapshot.outcome.is_terminal():
				decision.reason = CommandValidationResult.Reason.BATTLE_CONCLUDED
			result.append(decision)
	return result


static func headquarters_command(decision: CardActionSnapshot, command_id: int, faction_id: int, tick: int) -> CommanderOrderCommand:
	var command := CommanderOrderCommand.new(command_id, faction_id, tick, decision.commander_id,
		CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, decision.position)
	command.hand_back_control = true
	command.apply_requested_posture = true
	command.posture = CommanderState.Posture.CAUTIOUS if decision.action_kind == CardActionSnapshot.CONTINUE_RECON else CommanderState.Posture.AGGRESSIVE
	return command


func _make(snapshot: WorldSnapshot, battle: BattleDefinition, faction: FactionSnapshot, card: UnitCardSnapshot, kind: int, engineering_route: BattleEngineeringRouteDefinition = null) -> CardActionSnapshot:
	var decision := CardActionSnapshot.new()
	decision.unit_card_id = card.definition_id
	decision.commander_id = card.commander_definition_id
	decision.card_name_key = card.display_name_key
	var commander := snapshot.get_commander(card.commander_definition_id)
	decision.commander_name_key = commander.display_name_key if commander != null else &"COMMAND_DESK_FORCE_WIDE"
	decision.action_kind = kind
	decision.target_id = engineering_route.route_id if engineering_route != null else &""
	decision.decision_id = StringName("card:%s:%d:%s" % [card.definition_id, kind, decision.target_id])
	decision.current_strength = card.available_strength if kind == CardActionSnapshot.DEPLOY else card.current_strength
	decision.authorized_strength = card.authorized_strength
	decision.position = card.center_position
	decision.available_supply = faction.supply
	decision.population = faction.population
	decision.population_capacity = faction.population_capacity
	if commander != null:
		var target := snapshot.get_strategic_region(commander.target_region_id)
		decision.target_name_key = target.display_name_key if target != null else &"COMMAND_DESK_NO_INTENT"
	var task := snapshot.get_task(card.assigned_task_id)
	if task != null:
		decision.route = task.route.duplicate() if not task.route.is_empty() else task.planned_route.duplicate()
	if kind == CardActionSnapshot.DEPLOY:
		decision.supply_cost = card.supply_cost
		decision.population_required = card.available_strength
		decision.radius = battle.deployment_radius
		var headquarters := _headquarters(snapshot)
		if headquarters != null:
			decision.position = headquarters.position
		else:
			decision.reason = CommandValidationResult.Reason.INVALID_TARGET
	else:
		var definition := battle.support_for_kind(kind)
		decision.supply_cost = definition.supply_cost
		decision.cooldown_ticks = maxi(0, cooldown_until(faction, kind) - snapshot.tick)
		if card.formation_id == 0:
			decision.reason = CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE
		if kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
			decision.population_required = mini(definition.strength, mini(card.authorized_strength - card.current_strength, maxi(0, faction.population_capacity - faction.population)))
			if decision.population_required <= 0:
				decision.reason = CommandValidationResult.Reason.POPULATION_FULL
		if kind == SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY and card.fortified_ticks_remaining > 0 or kind == SupportOrderCommand.SupportKind.RAPID_MOBILITY and (card.rapid_mobility_ticks_remaining > 0 or card.fortified_ticks_remaining > 0):
			decision.reason = CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE
		if engineering_route != null:
			decision.target_name_key = engineering_route.display_name_key
			if not engineering_route.cleared_rects.is_empty():
				decision.position = Vector2(engineering_route.cleared_rects[0].get_center()) * LogicGrid.CELL_SIZE
			decision.route = PackedVector2Array([card.center_position, decision.position])
	if decision.population + decision.population_required > decision.population_capacity:
		decision.reason = CommandValidationResult.Reason.POPULATION_FULL
	if decision.cooldown_ticks > 0:
		decision.reason = CommandValidationResult.Reason.SUPPORT_COOLDOWN
	if decision.available_supply < decision.supply_cost:
		decision.reason = CommandValidationResult.Reason.INSUFFICIENT_SUPPLY
	if snapshot.outcome != null and snapshot.outcome.is_terminal():
		decision.reason = CommandValidationResult.Reason.BATTLE_CONCLUDED
	return decision


static func cooldown_until(faction: FactionSnapshot, kind: int) -> int:
	if faction.support_cooldown_until_by_kind.has(kind):
		return int(faction.support_cooldown_until_by_kind[kind])
	match kind:
		SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT: return faction.reinforcement_cooldown_until_tick
		SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY: return faction.fortify_cooldown_until_tick
	return 0


func _headquarters(snapshot: WorldSnapshot) -> BuildingSnapshot:
	for building in snapshot.buildings:
		if building.faction_id == snapshot.observer_faction_id and building.definition_id == &"command_center" and building.enabled:
			return building
	return null


func _needs_logistics(snapshot: WorldSnapshot, card: UnitCardSnapshot, maximum_organization: float) -> bool:
	if card.organization_enabled and card.organization < maximum_organization:
		return true
	for entity_id in card.active_member_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit != null and unit.health < unit.max_health:
			return true
	return false
