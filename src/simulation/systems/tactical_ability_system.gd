class_name TacticalAbilitySystem
extends RefCounted

const IDENTIFICATION_TICKS := 10
const IDENTIFICATION_LIFETIME := 15
var observation_started: Dictionary = {}


func validate(world: SimulationWorld, command: TacticalAbilityCommand, pending: bool = true, completing: bool = false) -> CommandValidationResult:
	var card := world.unit_cards.get(command.unit_card_id) as UnitCardState
	if card == null or card.faction_id != command.issuer_id:
		return _reject(CommandValidationResult.Reason.NOT_CONTROLLER)
	var ability := card.definition.tactical_ability
	if ability == null:
		return _reject(CommandValidationResult.Reason.INVALID_DEFINITION)
	if card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or not world.formations.has(card.formation_id):
		return _reject(CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
	if command.issuer_kind == GameCommand.IssuerKind.AGENT and (command.agent_id != card.assigned_agent_id or command.agent_id == 0 or card.control_state != UnitCardState.ControlState.AGENT_ASSIGNED):
		return _reject(CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED)
	if command.issuer_kind == GameCommand.IssuerKind.AGENT:
		var task := world.tasks.get(command.task_id) as TaskState
		if task == null or task.task_id != card.assigned_task_id or task.agent_id != command.agent_id or task.lifecycle not in [TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING]:
			return _reject(CommandValidationResult.Reason.INVALID_TASK)
	if not card.has_active_unit_type(ability.required_unit_id, world.units):
		return _reject(CommandValidationResult.Reason.CAPABILITY_LOST)
	if not completing and (card.tactical_command != null or card.tactical_ready_tick > world.current_tick):
		return _reject(CommandValidationResult.Reason.TACTICAL_BUSY)
	var faction := world.factions.get(command.issuer_id) as FactionState
	var committed := 0
	if pending:
		for queued in world.command_queue.snapshot():
			if queued.issuer_id != command.issuer_id:
				continue
			if queued is TacticalAbilityCommand:
				var other := world.unit_cards.get(queued.unit_card_id) as UnitCardState
				if other != null and other.definition.tactical_ability != null:
					if other == card:
						return _reject(CommandValidationResult.Reason.TACTICAL_BUSY)
					committed += other.definition.tactical_ability.supply_cost
			elif queued is SupportOrderCommand:
				committed += world.get_support_cost(queued.support_kind)
			elif queued is DeployUnitCardCommand:
				var reserve := world.unit_cards.get(queued.unit_card_id) as UnitCardState
				if reserve != null:
					committed += reserve.effective_supply_cost()
	if not completing and (faction == null or faction.supply - committed < ability.supply_cost):
		return _reject(CommandValidationResult.Reason.INSUFFICIENT_SUPPLY)
	if ability.kind in [TacticalAbilityDefinition.Kind.BREAKTHROUGH, TacticalAbilityDefinition.Kind.SUPPRESS] and (not card.organization_enabled or card.organization < maxf(30.0, ability.organization_cost)):
		return _reject(CommandValidationResult.Reason.LOW_ORGANIZATION)
	var center := UnitCardSnapshot.new(card, world.units).center_position
	match ability.kind:
		TacticalAbilityDefinition.Kind.OPEN_ROUTE:
			var route := world.battle_definition.engineering_route_dictionary().get(command.route_id) as BattleEngineeringRouteDefinition
			if route == null or world.opened_engineering_routes.has(command.route_id):
				return _reject(CommandValidationResult.Reason.INVALID_TARGET)
			if center.distance_to(world._engineering_route_center(route)) > ability.range:
				return _reject(CommandValidationResult.Reason.OUT_OF_RANGE)
			if _in_contact(world, card):
				return _reject(CommandValidationResult.Reason.TACTICAL_UNSAFE)
		TacticalAbilityDefinition.Kind.SUPPRESS:
			if not world.units.has(command.target_entity_id):
				return _reject(CommandValidationResult.Reason.INVALID_TARGET)
			if not world.is_entity_visible_to_faction(command.target_entity_id, card.faction_id):
				return _reject(CommandValidationResult.Reason.HIDDEN_TARGET)
			if not world.is_entity_enabled(command.target_entity_id) or world.get_entity_faction_id(command.target_entity_id) == card.faction_id:
				return _reject(CommandValidationResult.Reason.INVALID_TARGET)
			var knowledge := world.faction_knowledge.get(card.faction_id) as FactionKnowledge
			if knowledge == null or int(knowledge.identification_until_by_entity.get(command.target_entity_id, 0)) <= world.current_tick:
				return _reject(CommandValidationResult.Reason.TARGET_UNIDENTIFIED)
			if center.distance_to(world.get_entity_position(command.target_entity_id)) > ability.range:
				return _reject(CommandValidationResult.Reason.OUT_OF_RANGE)
			var has_round := false
			for id in card.member_entity_ids:
				var unit := world.units.get(id) as UnitState
				if unit != null and unit.enabled and unit.ammunition > 0 and center.distance_to(world.get_entity_position(command.target_entity_id)) >= unit.minimum_attack_range:
					has_round = true
			if not has_round:
				return _reject(CommandValidationResult.Reason.CAPABILITY_LOST)
		TacticalAbilityDefinition.Kind.BREAKTHROUGH:
			if not command.position.is_finite() or not world._battlefield_bounds().has_point(command.position) or center.distance_to(command.position) > ability.range:
				return _reject(CommandValidationResult.Reason.OUT_OF_RANGE)
			if world.pathfinder.find_path(center, command.position).is_empty():
				return _reject(CommandValidationResult.Reason.PATH_UNAVAILABLE)
		TacticalAbilityDefinition.Kind.RESUPPLY:
			var target := world.unit_cards.get(command.target_card_id) as UnitCardState
			if target == null or target.faction_id != card.faction_id or target.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
				return _reject(CommandValidationResult.Reason.INVALID_TARGET)
			var target_snapshot := UnitCardSnapshot.new(target, world.units)
			if center.distance_to(target_snapshot.center_position) > ability.range:
				return _reject(CommandValidationResult.Reason.OUT_OF_RANGE)
			if _in_contact(world, card) or _in_contact(world, target):
				return _reject(CommandValidationResult.Reason.TACTICAL_UNSAFE)
			if target_snapshot.ammunition >= target_snapshot.ammunition_capacity and (not target.organization_enabled or target.organization >= world.battle_definition.organization_max):
				return _reject(CommandValidationResult.Reason.RESUPPLY_NOT_NEEDED)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func start(world: SimulationWorld, command: TacticalAbilityCommand) -> void:
	# Revalidate against the state after earlier commands in this same tick.
	var validation := validate(world, command, false)
	if not validation.is_accepted():
		world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.COMMAND_REJECTED, command.target_entity_id, "card=%s;%s" % [command.unit_card_id, validation.describe()]))
		return
	var card := world.unit_cards[command.unit_card_id] as UnitCardState
	var ability := card.definition.tactical_ability
	var faction := world.factions[command.issuer_id] as FactionState
	faction.supply -= ability.supply_cost
	card.tactical_started_tick = world.current_tick
	card.tactical_complete_tick = world.current_tick + ability.preparation_ticks * (2 if card.organization_enabled and card.organization < 60.0 else 1)
	card.tactical_until_tick = card.tactical_complete_tick + ability.duration_ticks
	card.tactical_ready_tick = card.tactical_until_tick + ability.cooldown_ticks
	card.tactical_origin = UnitCardSnapshot.new(card, world.units).center_position
	# A new observation must earn continuous contact again after its cooldown.
	observation_started.erase(card.definition.definition_id)
	var saved := TacticalAbilityCommand.new(command.command_id, command.issuer_id, command.issuer_kind, command.issued_tick, command.unit_card_id, command.position, command.target_entity_id, command.target_card_id, command.route_id)
	saved.agent_id = command.agent_id
	saved.task_id = command.task_id
	card.tactical_command = saved
	card.tactical_status_key = &"TACTICAL_PREPARING"
	_event(world, card, SimulationEvent.Kind.TACTICAL_ACTION_STARTED, &"TACTICAL_PREPARING")
	world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.SUPPLY_CHANGED, card.faction_id, "supply=%d;delta=-%d;source=tactical;card=%s" % [faction.supply, ability.supply_cost, card.definition.definition_id]))


func advance(world: SimulationWorld) -> void:
	var ids := world.unit_cards.keys()
	ids.sort()
	for id in ids:
		var card := world.unit_cards[id] as UnitCardState
		if card.tactical_command == null:
			if card.definition.tactical_ability != null and world.current_tick >= card.tactical_ready_tick:
				card.tactical_status_key = &"TACTICAL_READY"
			continue
		var ability := card.definition.tactical_ability
		var command := card.tactical_command
		var snapshot := UnitCardSnapshot.new(card, world.units)
		var displaced := snapshot.center_position.distance_to(card.tactical_origin) > 8.0
		var invalid := validate(world, command, false, true)
		if displaced or not invalid.is_accepted():
			interrupt(world, card, StringName("REASON_%s" % CommandValidationResult.Reason.keys()[invalid.reason]) if not invalid.is_accepted() else &"TACTICAL_MOVED")
			continue
		if world.current_tick < card.tactical_complete_tick:
			continue
		if card.tactical_status_key == &"TACTICAL_PREPARING":
			card.organization = maxf(0.0, card.organization - ability.organization_cost)
			if not _execute(world, card):
				interrupt(world, card, &"TACTICAL_TARGET_CHANGED")
				continue
			card.tactical_status_key = &"TACTICAL_ACTIVE"
			_event(world, card, SimulationEvent.Kind.TACTICAL_ACTION_COMPLETED, &"TACTICAL_ACTIVE")
			if ability.kind not in [TacticalAbilityDefinition.Kind.OBSERVE, TacticalAbilityDefinition.Kind.SUPPRESS]:
				card.tactical_command = null
				card.tactical_status_key = &"TACTICAL_COMPLETE"
		if world.current_tick >= card.tactical_until_tick and card.tactical_command != null:
			card.tactical_command = null
			card.tactical_status_key = &"TACTICAL_COMPLETE"
			observation_started.erase(card.definition.definition_id)


func _execute(world: SimulationWorld, card: UnitCardState) -> bool:
	var command := card.tactical_command
	match card.definition.tactical_ability.kind:
		TacticalAbilityDefinition.Kind.OPEN_ROUTE:
			var route := world.battle_definition.engineering_route_dictionary()[command.route_id] as BattleEngineeringRouteDefinition
			for rect in route.cleared_rects:
				for x in range(rect.position.x, rect.end.x):
					for y in range(rect.position.y, rect.end.y):
						world.logic_grid.set_blocked(Vector2i(x, y), false)
			world.opened_engineering_routes[route.route_id] = world.current_tick
			(world.factions[card.faction_id] as FactionState).opened_engineering_route_ids.append(route.route_id)
			var position := world._engineering_route_center(route)
			world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.ENGINEERING_ROUTE_OPENED, card.faction_id, "route=%s;region=%s;engineer_card=%s;source=tactical;position=%.1f,%.1f" % [route.route_id, route.linked_region_id, card.definition.definition_id, position.x, position.y]))
		TacticalAbilityDefinition.Kind.SUPPRESS:
			for id in card.member_entity_ids:
				var unit := world.units.get(id) as UnitState
				if unit != null and unit.enabled and unit.can_attack:
					unit.attack_target_entity_id = command.target_entity_id
					unit.attack_is_retaliation = false
		TacticalAbilityDefinition.Kind.BREAKTHROUGH:
			var formation := world.formations[card.formation_id] as FormationState
			var move := AttackMoveCommand.new(world.allocate_command_id(), card.faction_id, command.issuer_kind, world.current_tick, formation.leader_entity_id, card.formation_id, command.position)
			move.agent_id = command.agent_id
			move.task_id = card.assigned_task_id
			if not world.submit_command(move).is_accepted():
				return false
		TacticalAbilityDefinition.Kind.RESUPPLY:
			var target := world.unit_cards[command.target_card_id] as UnitCardState
			var rounds := 0
			for id in target.member_entity_ids:
				var unit := world.units.get(id) as UnitState
				if unit != null and unit.enabled:
					rounds += unit.ammunition_capacity - unit.ammunition
					unit.ammunition = unit.ammunition_capacity
			var organization_before := target.organization
			if target.organization_enabled:
				target.organization = minf(world.battle_definition.organization_max, target.organization + 20.0)
			world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.AMMUNITION_RESTORED, card.faction_id, "card=%s;target_card=%s;rounds=%d;organization_restored=%.3f;reason=TACTICAL_RESUPPLY" % [card.definition.definition_id, target.definition.definition_id, rounds, target.organization - organization_before]))
	return true


func interrupt(world: SimulationWorld, card: UnitCardState, reason: StringName) -> void:
	card.tactical_command = null
	card.tactical_status_key = reason
	card.tactical_until_tick = world.current_tick
	observation_started.erase(card.definition.definition_id)
	_event(world, card, SimulationEvent.Kind.TACTICAL_ACTION_INTERRUPTED, reason)


func cancel_for_order(world: SimulationWorld, command: GameCommand) -> void:
	var ids := world.unit_cards.keys()
	ids.sort()
	for id in ids:
		var card := world.unit_cards[id] as UnitCardState
		if card.tactical_command == null:
			continue
		var targets_card: bool = command is UnitCardControlCommand and command.unit_card_id == id
		targets_card = targets_card or command is CommanderOrderCommand and command.commander_id == card.commander_definition_id
		targets_card = targets_card or card.member_entity_ids.has(command.target_entity_id)
		if targets_card:
			interrupt(world, card, &"TACTICAL_MOVED")


func observation_range(card: UnitCardState, tick: int) -> float:
	var ability := card.definition.tactical_ability
	if ability != null and ability.kind == TacticalAbilityDefinition.Kind.OBSERVE and card.tactical_command != null and tick >= card.tactical_complete_tick and tick < card.tactical_until_tick:
		return ability.range
	return 0.0


func update_identification(world: SimulationWorld, knowledge: FactionKnowledge) -> void:
	var visible_ids: Array[int] = []
	visible_ids.assign(knowledge.visible_hostile_unit_ids)
	for building_id in knowledge.visible_hostile_building_ids:
		visible_ids.append(building_id)
	for entity_id in knowledge.identification_until_by_entity.keys():
		if int(knowledge.identification_until_by_entity[entity_id]) <= world.current_tick or not visible_ids.has(int(entity_id)):
			knowledge.identification_until_by_entity.erase(entity_id)
	var ids := world.unit_cards.keys()
	ids.sort()
	for id in ids:
		var card := world.unit_cards[id] as UnitCardState
		if card.faction_id != knowledge.faction_id or observation_range(card, world.current_tick) <= 0.0:
			continue
		var started: Dictionary = observation_started.get(id, {})
		var center := UnitCardSnapshot.new(card, world.units).center_position
		var tracked: Array[int] = []
		for entity_id in visible_ids:
			var contact := knowledge.hostile_contacts.get(entity_id) as KnowledgeContact
			if contact == null or not contact.enabled or center.distance_to(contact.position) > observation_range(card, world.current_tick):
				continue
			tracked.append(entity_id)
			if not started.has(entity_id):
				started[entity_id] = world.current_tick
			if world.current_tick - int(started[entity_id]) >= IDENTIFICATION_TICKS:
				if not knowledge.identification_until_by_entity.has(entity_id):
					world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.TACTICAL_IDENTIFIED, entity_id, "faction=%d;card=%s;source=optical;reason=TACTICAL_IDENTIFIED" % [card.faction_id, id]))
				knowledge.identification_until_by_entity[entity_id] = world.current_tick + IDENTIFICATION_LIFETIME
		for entity_id in started.keys():
			if not tracked.has(int(entity_id)):
				started.erase(entity_id)
		observation_started[id] = started


func prepare_weapons(world: SimulationWorld) -> void:
	for value in world.units.values():
		var unit := value as UnitState
		var card := world.unit_cards.get(unit.unit_card_id) as UnitCardState
		unit.organization_attack_restricted = card != null and card.uses_tactical_organization() and card.organization <= 0.0 \
			and card.control_state not in [UnitCardState.ControlState.PLAYER_CONTROLLED, UnitCardState.ControlState.PLAYER_OVERRIDDEN]
		if unit.enabled and unit.organization_attack_restricted:
			# Broken formations retain legal self-defense, never proactive fire.
			unit.attack_target_entity_id = world._find_worker_aggressor(unit) if unit.auto_retaliate else 0
			unit.attack_is_retaliation = unit.attack_target_entity_id != 0
		if not unit.enabled or not unit.identification_required:
			continue
		var knowledge := world.faction_knowledge.get(unit.faction_id) as FactionKnowledge
		unit.target_identified = knowledge != null and int(knowledge.identification_until_by_entity.get(unit.attack_target_entity_id, 0)) > world.current_tick and (knowledge.visible_hostile_unit_ids.has(unit.attack_target_entity_id) or knowledge.visible_hostile_building_ids.has(unit.attack_target_entity_id))
		unit.weapon_action_ready = card == null or card.definition.tactical_ability == null or card.definition.tactical_ability.kind != TacticalAbilityDefinition.Kind.SUPPRESS or card.tactical_command != null and card.tactical_status_key == &"TACTICAL_ACTIVE"


func propose_commands(world: SimulationWorld) -> void:
	if world.current_tick % 10 != 0:
		return
	var active_factions: Dictionary = {}
	for value in world.unit_cards.values():
		var card := value as UnitCardState
		if card.definition.tactical_ability != null and card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.control_state == UnitCardState.ControlState.AGENT_ASSIGNED:
			active_factions[card.faction_id] = true
	var ids := active_factions.keys()
	ids.sort()
	for faction_id in ids:
		for command in TacticalCardAgent.new().propose(world.create_faction_snapshot(faction_id), world.battle_definition):
			command.command_id = world.allocate_command_id()
			world.submit_command(command)


func _in_contact(world: SimulationWorld, card: UnitCardState) -> bool:
	var knowledge := world.faction_knowledge.get(card.faction_id) as FactionKnowledge
	if knowledge == null:
		return false
	var center := UnitCardSnapshot.new(card, world.units).center_position
	for id in knowledge.visible_hostile_unit_ids:
		var contact := knowledge.hostile_contacts.get(id) as KnowledgeContact
		if contact != null and contact.enabled and center.distance_to(contact.position) < 260.0:
			return true
	return world.current_tick - card.last_damage_tick < 20


func _event(world: SimulationWorld, card: UnitCardState, kind: SimulationEvent.Kind, reason: StringName) -> void:
	world.events.append(SimulationEvent.new(world.current_tick, kind, card.faction_id, "card=%s;ability=%s;reason=%s" % [card.definition.definition_id, card.definition.tactical_ability.ability_id, reason]))


func _reject(reason: CommandValidationResult.Reason) -> CommandValidationResult:
	return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, reason)
