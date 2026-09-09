class_name CommandValidator
extends RefCounted


func validate(
	command: GameCommand,
	units: Dictionary,
	battlefield_bounds: Rect2,
	pathfinder: GridPathfinder = null,
	formations: Dictionary = {},
	buildings: Dictionary = {},
	ore_fields: Dictionary = {},
	factions: Dictionary = {},
	unit_catalog: UnitDefinitionCatalog = null,
	building_catalog: BuildingDefinitionCatalog = null,
	faction_knowledge: Dictionary = {},
	logic_grid: LogicGrid = null,
	tasks: Dictionary = {},
	unit_cards: Dictionary = {},
	strategic_regions: Dictionary = {},
	commanders: Dictionary = {},
	doctrines: Dictionary = {},
	battle_definition: BattleDefinition = null
) -> CommandValidationResult:
	if command is EquipDoctrineCommand:
		return _validate_equip_doctrine(command as EquipDoctrineCommand, commanders, doctrines)
	if command is CommanderOrderCommand:
		return _validate_commander_order(command as CommanderOrderCommand, commanders, unit_cards, formations, strategic_regions, battlefield_bounds, pathfinder)
	if command is UnitCardControlCommand:
		return _validate_unit_card_control(command as UnitCardControlCommand, unit_cards, units, formations)
	if command is SupportOrderCommand:
		return _validate_support_order(command as SupportOrderCommand, unit_cards, strategic_regions, factions, units, battle_definition)
	if command is DeployUnitCardCommand:
		return _validate_unit_card_deployment(command as DeployUnitCardCommand, unit_cards, factions, buildings, battlefield_bounds, battle_definition)
	if command is StrategicOrderCommand:
		return _validate_strategic_order(command as StrategicOrderCommand, units, formations, buildings, ore_fields, factions, faction_knowledge, logic_grid, battlefield_bounds, pathfinder, tasks)
	if command is TaskControlCommand:
		return _validate_task_control(command as TaskControlCommand, tasks)
	if command is BuildBuildingCommand:
		return _validate_build(command as BuildBuildingCommand, units, buildings, factions, building_catalog, logic_grid, battlefield_bounds, pathfinder)
	if command is RepairBuildingCommand:
		return _validate_repair(command as RepairBuildingCommand, units, buildings, logic_grid, pathfinder)
	if command is HarvestCommand:
		return _validate_harvest(command as HarvestCommand, units, buildings, ore_fields)
	if command is ProduceUnitCommand:
		return _validate_production(command as ProduceUnitCommand, buildings, factions, unit_catalog, building_catalog)
	if command is CancelProductionCommand:
		return _validate_cancel_production(command as CancelProductionCommand, buildings)
	if command is SetRallyPointCommand:
		return _validate_rally_point(command as SetRallyPointCommand, buildings, building_catalog, battlefield_bounds, pathfinder)
	if command is StopCommand:
		return _validate_stop(command as StopCommand, units, formations)
	if command is AttackCommand:
		return _validate_attack(command as AttackCommand, units, formations, buildings, faction_knowledge, logic_grid)
	if command is AttackMoveCommand:
		return _validate_attack_move(command as AttackMoveCommand, units, formations, battlefield_bounds, pathfinder)
	if command is FormationMoveCommand:
		return _validate_formation_move(command as FormationMoveCommand, units, formations, battlefield_bounds, pathfinder)
	if command is UnitDispositionCommand:
		return _validate_disposition(command as UnitDispositionCommand, units, formations)
	if not units.has(command.target_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)

	var unit: UnitState = units[command.target_entity_id]
	var unit_result := _validate_unit(unit, command.issuer_id)
	if not unit_result.is_accepted():
		return unit_result
	if command.issuer_kind == GameCommand.IssuerKind.AGENT and not _agent_can_control(unit, command):
		return _rejected(CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED)

	if command is MoveCommand:
		var move_command := command as MoveCommand
		if not _is_valid_position(move_command.target_position, battlefield_bounds):
			return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
		if pathfinder != null and pathfinder.find_path(unit.position, move_command.target_position).is_empty():
			return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)

	return _rejected(CommandValidationResult.Reason.INVALID_TARGET)


func _validate_equip_doctrine(
	command: EquipDoctrineCommand,
	commanders: Dictionary,
	doctrines: Dictionary
) -> CommandValidationResult:
	var commander := commanders.get(command.commander_id) as CommanderState
	if commander == null or not doctrines.has(command.doctrine_id):
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if commander.faction_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	if command.slot_index < 0 or command.slot_index >= commander.doctrine_slot_count or not commander.available_doctrine_ids.has(command.doctrine_id):
		return _rejected(CommandValidationResult.Reason.INVALID_DISPOSITION)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_commander_order(
	command: CommanderOrderCommand,
	commanders: Dictionary,
	unit_cards: Dictionary,
	formations: Dictionary,
	strategic_regions: Dictionary,
	battlefield_bounds: Rect2,
	pathfinder: GridPathfinder
) -> CommandValidationResult:
	const MAX_COMMANDER_ROUTE_POINTS := 8
	var commander := commanders.get(command.commander_id) as CommanderState
	if commander == null:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	if commander.faction_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	if command.posture < CommanderState.Posture.CAUTIOUS or command.posture > CommanderState.Posture.DISENGAGE:
		return _rejected(CommandValidationResult.Reason.INVALID_DISPOSITION)
	if command.order_kind == CommanderOrderCommand.OrderKind.SET_POSTURE:
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	if command.order_kind == CommanderOrderCommand.OrderKind.CANCEL_INTENT:
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	if command.order_kind == CommanderOrderCommand.OrderKind.ASSIGN_INTENT:
		if command.intent_id.is_empty() or command.target_region_id.is_empty() or command.main_axis_region_id.is_empty():
			return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
		if not strategic_regions.has(command.target_region_id) or not strategic_regions.has(command.main_axis_region_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		if command.reserve_policy < CommanderState.ReservePolicy.HOLD or command.reserve_policy > CommanderState.ReservePolicy.COMMIT_AVAILABLE:
			return _rejected(CommandValidationResult.Reason.INVALID_DISPOSITION)
	if not _is_valid_position(command.target_position, battlefield_bounds):
		return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	if command.route_points.size() > MAX_COMMANDER_ROUTE_POINTS:
		return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	for route_point in command.route_points:
		if not _is_valid_position(route_point, battlefield_bounds):
			return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	var available_cards := 0
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := unit_cards.get(unit_card_id) as UnitCardState
		if unit_card == null or unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		if not formations.has(unit_card.formation_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		var formation := formations[unit_card.formation_id] as FormationState
		if pathfinder != null:
			var segment_start := formation.anchor_position
			for route_point in command.route_points:
				if pathfinder.find_path(segment_start, route_point).is_empty():
					return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
				segment_start = route_point
			if pathfinder.find_path(segment_start, command.target_position).is_empty():
				return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
		available_cards += 1
	if available_cards == 0:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_unit_card_control(
	command: UnitCardControlCommand,
	unit_cards: Dictionary,
	units: Dictionary,
	formations: Dictionary
) -> CommandValidationResult:
	var unit_card := unit_cards.get(command.unit_card_id) as UnitCardState
	if unit_card == null:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	if unit_card.faction_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	if unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
		return _rejected(CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
	var active_count := 0
	for entity_id in unit_card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit == null or not unit.enabled:
			continue
		if unit.controller_id != command.issuer_id:
			return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
		active_count += 1
	if active_count == 0:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	match command.action:
		UnitCardControlCommand.Action.TAKEOVER:
			if unit_card.control_state == UnitCardState.ControlState.RETURNING:
				return _rejected(CommandValidationResult.Reason.INVALID_DISPOSITION)
		UnitCardControlCommand.Action.RETURN_TO_COMMANDER:
			if unit_card.return_formation_id == 0 or not formations.has(unit_card.return_formation_id):
				return _rejected(CommandValidationResult.Reason.INVALID_DISPOSITION)
			if unit_card.control_state not in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.RETURNING]:
				return _rejected(CommandValidationResult.Reason.INVALID_DISPOSITION)
		UnitCardControlCommand.Action.STAY_MANUAL:
			if unit_card.control_state == UnitCardState.ControlState.RETURNING:
				return _rejected(CommandValidationResult.Reason.INVALID_DISPOSITION)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_support_order(
	command: SupportOrderCommand,
	unit_cards: Dictionary,
	strategic_regions: Dictionary,
	factions: Dictionary,
	units: Dictionary,
	battle_definition: BattleDefinition = null
) -> CommandValidationResult:
	var faction := factions.get(command.issuer_id) as FactionState
	if faction == null:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	var support_definition := battle_definition.support_for_kind(command.support_kind) if battle_definition != null else null
	if battle_definition != null and support_definition == null:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var supply_cost := support_definition.supply_cost if support_definition != null else 2
	if faction.supply < supply_cost:
		return _rejected(CommandValidationResult.Reason.INSUFFICIENT_SUPPLY)
	if command.support_kind == SupportOrderCommand.SupportKind.AIR_RECON:
		if not strategic_regions.has(command.primary_region_id) or not strategic_regions.has(command.secondary_region_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		var primary := strategic_regions[command.primary_region_id] as StrategicRegionState
		var secondary := strategic_regions[command.secondary_region_id] as StrategicRegionState
		var adjacent := primary.adjacent_region_ids.has(secondary.region_id) or secondary.adjacent_region_ids.has(primary.region_id)
		if battle_definition == null and primary.adjacent_region_ids.is_empty() and secondary.adjacent_region_ids.is_empty():
			var pair := [command.primary_region_id, command.secondary_region_id]
			adjacent = pair.has(&"central_relay") and (pair.has(&"west_mine") or pair.has(&"east_supply"))
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED) if adjacent else _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	if command.support_kind == SupportOrderCommand.SupportKind.ENGINEERING_ROUTE:
		if battle_definition == null or not battle_definition.engineering_route_dictionary().has(command.primary_region_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		var engineering_card := unit_cards.get(command.unit_card_id) as UnitCardState
		if engineering_card == null or engineering_card.faction_id != command.issuer_id:
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		if engineering_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or engineering_card.formation_id == 0:
			return _rejected(CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
		if engineering_card.definition.unit_definition_id != &"engineer_vehicle":
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	if command.support_kind == SupportOrderCommand.SupportKind.FIRE_SUPPORT:
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED) if strategic_regions.has(command.primary_region_id) else _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var unit_card := unit_cards.get(command.unit_card_id) as UnitCardState
	if unit_card == null or unit_card.faction_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	if unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or unit_card.formation_id == 0:
		return _rejected(CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
	if command.support_kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
		var active_strength := _active_unit_card_strength(unit_card, units)
		if active_strength >= unit_card.definition.authorized_strength:
			return _rejected(CommandValidationResult.Reason.UNIT_CARD_FULL_STRENGTH)
		var population_room := maxi(0, faction.population_capacity - faction.population)
		var configured_strength := support_definition.strength if support_definition != null else 2
		var restored_strength := mini(configured_strength, mini(unit_card.definition.authorized_strength - active_strength, population_room))
		if restored_strength <= 0:
			return _rejected(CommandValidationResult.Reason.POPULATION_FULL)
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	if command.support_kind == SupportOrderCommand.SupportKind.RAPID_MOBILITY and unit_card.rapid_mobility_ticks_remaining > 0:
		return _rejected(CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
	if command.support_kind == SupportOrderCommand.SupportKind.FRONTLINE_LOGISTICS:
		var needs_support := unit_card.organization_enabled and battle_definition != null and unit_card.organization < battle_definition.organization_max
		for entity_id in unit_card.member_entity_ids:
			var member := units.get(entity_id) as UnitState
			needs_support = needs_support or (member != null and member.enabled and member.health < member.max_health)
		if not needs_support:
			return _rejected(CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	if unit_card.fortified_ticks_remaining > 0:
		return _rejected(CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _active_unit_card_strength(unit_card: UnitCardState, units: Dictionary) -> int:
	var strength := 0
	for entity_id in unit_card.member_entity_ids:
		var unit := units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			strength += 1
	return strength


func _validate_unit_card_deployment(
	command: DeployUnitCardCommand,
	unit_cards: Dictionary,
	factions: Dictionary,
	buildings: Dictionary,
	battlefield_bounds: Rect2,
	battle_definition: BattleDefinition = null
) -> CommandValidationResult:
	var unit_card := unit_cards.get(command.unit_card_id) as UnitCardState
	if unit_card == null or unit_card.faction_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	if not command.commander_id.is_empty() and command.commander_id != unit_card.commander_definition_id:
		return _rejected(CommandValidationResult.Reason.COMMANDER_MISMATCH)
	if unit_card.deployment_state != UnitCardState.DeploymentState.RESERVE:
		return _rejected(CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE)
	var faction := factions.get(unit_card.faction_id) as FactionState
	if faction == null:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	if faction.supply < unit_card.effective_supply_cost():
		return _rejected(CommandValidationResult.Reason.INSUFFICIENT_SUPPLY)
	if faction.population + unit_card.available_strength > faction.population_capacity:
		return _rejected(CommandValidationResult.Reason.POPULATION_FULL)
	if not battlefield_bounds.has_point(command.deployment_position):
		return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	var headquarters_position := Vector2(-INF, -INF)
	for building_variant in buildings.values():
		var building := building_variant as BuildingState
		if building.enabled and building.faction_id == unit_card.faction_id and building.definition_id == &"command_center":
			headquarters_position = building.position
			break
	var deployment_radius := battle_definition.deployment_radius if battle_definition != null else 384.0
	if not is_finite(headquarters_position.x) or headquarters_position.distance_to(command.deployment_position) > deployment_radius:
		return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_attack(command: AttackCommand, units: Dictionary, formations: Dictionary, buildings: Dictionary, faction_knowledge: Dictionary, logic_grid: LogicGrid) -> CommandValidationResult:
	var attacker_ids: Array[int] = []
	if command.formation_id != 0:
		if not formations.has(command.formation_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		var formation := formations[command.formation_id] as FormationState
		if formation.leader_entity_id != command.target_entity_id:
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		attacker_ids.assign(formation.member_entity_ids)
	else:
		attacker_ids.append(command.target_entity_id)
	var combat_attacker_ids: Array[int] = []
	for entity_id in attacker_ids:
		if not units.has(entity_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		var attacker := units[entity_id] as UnitState
		if not attacker.enabled or not attacker.can_attack or not attacker.can_accept_attack_orders:
			continue
		combat_attacker_ids.append(entity_id)
		var attacker_result := _validate_unit(attacker, command.issuer_id)
		if not attacker_result.is_accepted():
			return attacker_result
		if command.issuer_kind == GameCommand.IssuerKind.AGENT and not _agent_can_control(attacker, command):
			return _rejected(CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED)
	if combat_attacker_ids.is_empty():
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if not units.has(command.attack_target_entity_id) and not buildings.has(command.attack_target_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var target_enabled := false
	var target_faction_id := 0
	var target_position := Vector2.ZERO
	if units.has(command.attack_target_entity_id):
		var target_unit := units[command.attack_target_entity_id] as UnitState
		target_enabled = target_unit.enabled
		target_faction_id = target_unit.faction_id
		target_position = target_unit.position
	else:
		var target_building := buildings[command.attack_target_entity_id] as BuildingState
		target_enabled = target_building.enabled
		target_faction_id = target_building.faction_id
		target_position = target_building.position
	if not target_enabled:
		return _rejected(CommandValidationResult.Reason.ENTITY_DISABLED)
	if faction_knowledge.has(command.issuer_id) and logic_grid != null:
		var knowledge := faction_knowledge[command.issuer_id] as FactionKnowledge
		if target_faction_id != command.issuer_id and not knowledge.is_visible(logic_grid.world_to_cell(target_position)):
			return _rejected(CommandValidationResult.Reason.HIDDEN_TARGET)
	for entity_id in combat_attacker_ids:
		var attacker := units[entity_id] as UnitState
		if attacker.entity_id == command.attack_target_entity_id:
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		if attacker.faction_id == target_faction_id:
			return _rejected(CommandValidationResult.Reason.FRIENDLY_TARGET)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_attack_move(
	command: AttackMoveCommand,
	units: Dictionary,
	formations: Dictionary,
	battlefield_bounds: Rect2,
	pathfinder: GridPathfinder
) -> CommandValidationResult:
	if command.formation_id != 0:
		var result := _validate_formation_move(command, units, formations, battlefield_bounds, pathfinder)
		if not result.is_accepted():
			return result
		for entity_id in (formations[command.formation_id] as FormationState).member_entity_ids:
			var member := units[entity_id] as UnitState
			if member.enabled and member.can_attack and member.can_accept_attack_orders:
				return result
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if not units.has(command.target_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var unit := units[command.target_entity_id] as UnitState
	var unit_result := _validate_unit(unit, command.issuer_id)
	if not unit_result.is_accepted():
		return unit_result
	if not unit.can_attack or not unit.can_accept_attack_orders:
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if command.issuer_kind == GameCommand.IssuerKind.AGENT and not _agent_can_control(unit, command):
		return _rejected(CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED)
	if not _is_valid_position(command.target_position, battlefield_bounds):
		return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	if pathfinder != null and pathfinder.find_path(unit.position, command.target_position).is_empty():
		return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_build(
	command: BuildBuildingCommand,
	units: Dictionary,
	buildings: Dictionary,
	factions: Dictionary,
	building_catalog: BuildingDefinitionCatalog,
	logic_grid: LogicGrid,
	battlefield_bounds: Rect2,
	pathfinder: GridPathfinder
) -> CommandValidationResult:
	if not units.has(command.target_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var engineer := units[command.target_entity_id] as UnitState
	var unit_result := _validate_unit(engineer, command.issuer_id)
	if not unit_result.is_accepted():
		return unit_result
	if engineer.definition_id != &"engineer_vehicle":
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if engineer.work_kind != UnitState.WorkKind.NONE:
		return _rejected(CommandValidationResult.Reason.CONSTRUCTION_BUSY)
	var definition := building_catalog.get_building(command.building_definition_id) if building_catalog != null else null
	if definition == null:
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if not factions.has(engineer.faction_id) or (factions[engineer.faction_id] as FactionState).ore < definition.build_cost:
		return _rejected(CommandValidationResult.Reason.INSUFFICIENT_ORE)
	if logic_grid == null or not _is_valid_position(command.build_position, battlefield_bounds):
		return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	var footprint := logic_grid.get_footprint_cells(command.build_position, definition.footprint_size)
	for cell in footprint:
		if not logic_grid.is_in_bounds(cell) or logic_grid.is_blocked(cell):
			return _rejected(CommandValidationResult.Reason.BUILDING_OCCUPIED)
	for unit_variant in units.values():
		var occupying_unit := unit_variant as UnitState
		if occupying_unit.enabled and footprint.has(logic_grid.world_to_cell(occupying_unit.position)):
			return _rejected(CommandValidationResult.Reason.BUILDING_OCCUPIED)
	var work_cells := logic_grid.get_footprint_work_cells(footprint)
	if work_cells.is_empty():
		return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
	if pathfinder != null:
		var reachable := false
		for work_cell in work_cells:
			if not pathfinder.find_path(engineer.position, logic_grid.cell_to_world(work_cell)).is_empty():
				reachable = true
				break
		if not reachable:
			return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_repair(
	command: RepairBuildingCommand,
	units: Dictionary,
	buildings: Dictionary,
	logic_grid: LogicGrid,
	pathfinder: GridPathfinder
) -> CommandValidationResult:
	if not units.has(command.target_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var engineer := units[command.target_entity_id] as UnitState
	var unit_result := _validate_unit(engineer, command.issuer_id)
	if not unit_result.is_accepted():
		return unit_result
	if engineer.definition_id != &"engineer_vehicle":
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if engineer.work_kind != UnitState.WorkKind.NONE:
		return _rejected(CommandValidationResult.Reason.CONSTRUCTION_BUSY)
	if not buildings.has(command.building_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_BUILDING)
	var building := buildings[command.building_entity_id] as BuildingState
	if not building.enabled or building.faction_id != engineer.faction_id or building.under_construction:
		return _rejected(CommandValidationResult.Reason.INVALID_BUILDING)
	if building.health >= building.max_health:
		return _rejected(CommandValidationResult.Reason.BUILDING_FULL_HEALTH)
	if logic_grid != null and pathfinder != null:
		var reachable := false
		for work_cell in logic_grid.get_footprint_work_cells(building.footprint_cells):
			if not pathfinder.find_path(engineer.position, logic_grid.cell_to_world(work_cell)).is_empty():
				reachable = true
				break
		if not reachable:
			return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_stop(command: StopCommand, units: Dictionary, formations: Dictionary) -> CommandValidationResult:
	if command.formation_id != 0:
		if not formations.has(command.formation_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		var formation := formations[command.formation_id] as FormationState
		for entity_id in formation.member_entity_ids:
			if not units.has(entity_id):
				return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
			var member := units[entity_id] as UnitState
			var result := _validate_unit(member, command.issuer_id)
			if not result.is_accepted():
				return result
			if command.issuer_kind == GameCommand.IssuerKind.AGENT and not _agent_can_control(member, command):
				return _rejected(CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED)
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	if not units.has(command.target_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	return _validate_unit(units[command.target_entity_id] as UnitState, command.issuer_id)


func _validate_formation_move(
	command: FormationMoveCommand,
	units: Dictionary,
	formations: Dictionary,
	battlefield_bounds: Rect2,
	pathfinder: GridPathfinder
) -> CommandValidationResult:
	const MAX_ROUTE_POINTS := 8
	const MIN_DEPLOYMENT_LINE_LENGTH := 48.0
	const MAX_DEPLOYMENT_LINE_LENGTH := 520.0
	if not formations.has(command.formation_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var formation := formations[command.formation_id] as FormationState
	if formation.leader_entity_id != command.target_entity_id:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var active_member_count := 0
	for entity_id in formation.member_entity_ids:
		if not units.has(entity_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		var member := units[entity_id] as UnitState
		if not member.enabled:
			continue
		active_member_count += 1
		var member_result := _validate_unit(member, command.issuer_id)
		if not member_result.is_accepted():
			return member_result
		if command.issuer_kind == GameCommand.IssuerKind.AGENT and not _agent_can_control(member, command):
			return _rejected(CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED)
	if active_member_count == 0:
		return _rejected(CommandValidationResult.Reason.ENTITY_DISABLED)
	if command.route_points.size() > MAX_ROUTE_POINTS or not _is_valid_position(command.target_position, battlefield_bounds):
		return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	for waypoint in command.route_points:
		if not _is_valid_position(waypoint, battlefield_bounds):
			return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	if command.has_deployment_line:
		var line_length := command.deployment_line_start.distance_to(command.deployment_line_end)
		if line_length < MIN_DEPLOYMENT_LINE_LENGTH or line_length > MAX_DEPLOYMENT_LINE_LENGTH:
			return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
		if not _is_valid_position(command.deployment_line_start, battlefield_bounds) or not _is_valid_position(command.deployment_line_end, battlefield_bounds):
			return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	if pathfinder == null:
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	var destinations := command.route_points.duplicate()
	if destinations.is_empty() or not destinations[-1].is_equal_approx(command.target_position):
		destinations.append(command.target_position)
	var segment_start := formation.anchor_position
	var path := PackedVector2Array()
	for destination in destinations:
		path = pathfinder.find_path(segment_start, destination)
		if path.is_empty():
			return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
		segment_start = destination
	if command.has_deployment_line:
		for slot_id in range(formation.member_entity_ids.size()):
			var ratio := 0.5 if formation.member_entity_ids.size() <= 1 else float(slot_id) / float(formation.member_entity_ids.size() - 1)
			var slot_position := command.deployment_line_start.lerp(command.deployment_line_end, ratio)
			if not _is_valid_position(slot_position, battlefield_bounds) or not pathfinder.logic_grid.is_world_position_walkable(slot_position):
				return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	var tangent := Vector2.RIGHT
	if path.size() >= 2:
		tangent = (path[-1] - path[-2]).normalized()
	var lateral := Vector2(-tangent.y, tangent.x)
	for slot_id in range(formation.member_entity_ids.size()):
		var offset := formation.get_wide_offset(slot_id)
		var slot_position := command.target_position + tangent * offset.x + lateral * offset.y
		if not _is_valid_position(slot_position, battlefield_bounds) or not pathfinder.logic_grid.is_world_position_walkable(slot_position):
			return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_harvest(command: HarvestCommand, units: Dictionary, buildings: Dictionary, ore_fields: Dictionary) -> CommandValidationResult:
	if not units.has(command.target_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var harvester := units[command.target_entity_id] as UnitState
	if not harvester.can_harvest:
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	var unit_result := _validate_unit(harvester, command.issuer_id)
	if not unit_result.is_accepted():
		return unit_result
	if command.issuer_kind == GameCommand.IssuerKind.AGENT and not _agent_can_control(units[command.target_entity_id] as UnitState, command):
		return _rejected(CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED)
	if not ore_fields.has(command.ore_field_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_RESOURCE)
	if not buildings.has(command.refinery_building_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_BUILDING)
	var refinery := buildings[command.refinery_building_entity_id] as BuildingState
	if not refinery.enabled or not refinery.operational or refinery.faction_id != (units[command.target_entity_id] as UnitState).faction_id:
		return _rejected(CommandValidationResult.Reason.INVALID_BUILDING)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_production(command: ProduceUnitCommand, buildings: Dictionary, factions: Dictionary, unit_catalog: UnitDefinitionCatalog, building_catalog: BuildingDefinitionCatalog) -> CommandValidationResult:
	if not buildings.has(command.target_entity_id) or unit_catalog == null or building_catalog == null:
		return _rejected(CommandValidationResult.Reason.INVALID_BUILDING)
	var building := buildings[command.target_entity_id] as BuildingState
	var building_definition := building_catalog.get_building(building.definition_id)
	var unit_definition := unit_catalog.get_unit(command.unit_definition_id)
	if not building.enabled or not building.operational or building_definition == null or unit_definition == null or not building_definition.can_produce(command.unit_definition_id):
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if building.controller_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	if building.production_count() >= BuildingState.MAX_PRODUCTION_QUEUE_SIZE:
		return _rejected(CommandValidationResult.Reason.PRODUCTION_QUEUE_FULL)
	if not factions.has(building.faction_id) or (factions[building.faction_id] as FactionState).ore < unit_definition.production_cost:
		return _rejected(CommandValidationResult.Reason.INSUFFICIENT_ORE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_cancel_production(command: CancelProductionCommand, buildings: Dictionary) -> CommandValidationResult:
	if not buildings.has(command.target_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_BUILDING)
	var building := buildings[command.target_entity_id] as BuildingState
	if not building.enabled or building.controller_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	if command.queue_index < 0 or command.queue_index >= building.production_count():
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_rally_point(
	command: SetRallyPointCommand,
	buildings: Dictionary,
	building_catalog: BuildingDefinitionCatalog,
	battlefield_bounds: Rect2,
	pathfinder: GridPathfinder
) -> CommandValidationResult:
	if not buildings.has(command.target_entity_id) or building_catalog == null:
		return _rejected(CommandValidationResult.Reason.INVALID_BUILDING)
	var building := buildings[command.target_entity_id] as BuildingState
	var definition := building_catalog.get_building(building.definition_id)
	if not building.enabled or not building.operational or building.controller_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	if definition == null or definition.production_catalog.is_empty():
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if not _is_valid_position(command.rally_position, battlefield_bounds):
		return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	if pathfinder != null and pathfinder.find_path(building.rally_position, command.rally_position).is_empty():
		return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _agent_can_control(unit: UnitState, command: GameCommand) -> bool:
	return unit.control_state == UnitState.ControlState.AGENT_ASSIGNED and unit.assigned_agent_id == command.agent_id and unit.assigned_task_id == command.task_id


func _validate_disposition(command: UnitDispositionCommand, units: Dictionary, formations: Dictionary) -> CommandValidationResult:
	if not units.has(command.target_entity_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var unit := units[command.target_entity_id] as UnitState
	if not unit.enabled or unit.controller_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	if command.disposition == UnitDispositionCommand.Disposition.JOIN and not formations.has(command.destination_formation_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_strategic_order(
	command: StrategicOrderCommand,
	units: Dictionary,
	formations: Dictionary,
	buildings: Dictionary,
	ore_fields: Dictionary,
	factions: Dictionary,
	faction_knowledge: Dictionary,
	logic_grid: LogicGrid,
	battlefield_bounds: Rect2,
	pathfinder: GridPathfinder,
	tasks: Dictionary
) -> CommandValidationResult:
	var requested_industrial := command.order_kind == StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE
	var requested_participants := _strategic_participant_ids(command, units, formations)
	for task_variant in tasks.values():
		var task := task_variant as TaskState
		var task_industrial := task.kind == TaskState.Kind.DEVELOP_RESOURCE
		if task.kind == TaskState.Kind.FORMATION_MOVE_TEST or task.faction_id not in [0, command.issuer_id] or task.lifecycle not in [TaskState.Lifecycle.WAITING, TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING, TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]:
			continue
		if requested_industrial and task_industrial:
			return _rejected(CommandValidationResult.Reason.TASK_CONFLICT)
		if requested_industrial or task_industrial or not _participant_sets_overlap(requested_participants, task.participant_entity_ids):
			continue
		var may_preempt := (
			command.issuer_kind == GameCommand.IssuerKind.AGENT
			and command.agent_id == task.agent_id
			and task.requires_proactive_authorization
			and (command.strategic_priority > task.priority or command.replaces_task_id == task.task_id)
		)
		if not may_preempt:
			return _rejected(CommandValidationResult.Reason.TASK_CONFLICT)
	match command.order_kind:
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE:
			if not ore_fields.has(command.objective_entity_id) or not buildings.has(SimulationWorld.PLAYER_COMMAND_CENTER_ID):
				return _rejected(CommandValidationResult.Reason.INVALID_RESOURCE)
			if not factions.has(command.issuer_id):
				return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
			for unit_variant in units.values():
				var unit := unit_variant as UnitState
				if unit.enabled and unit.controller_id == command.issuer_id and unit.definition_id == &"harvester":
					return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
			return _rejected(CommandValidationResult.Reason.INVALID_RESOURCE)
		StrategicOrderCommand.OrderKind.DEFEND_AREA:
			if command.target_radius <= 0.0 or not _is_valid_position(command.target_position, battlefield_bounds):
				return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
			if command.formation_id == 0:
				return _validate_strategic_participants(command, units, formations, battlefield_bounds, pathfinder, false)
			if not formations.has(command.formation_id):
				return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
			var formation := formations[command.formation_id] as FormationState
			# A strategic order claims units before its subordinate Agent commands exist.
			# This probe validates ownership, capability and path only.
			var probe := FormationMoveCommand.new(command.command_id, command.issuer_id, GameCommand.IssuerKind.PLAYER, command.issued_tick, formation.leader_entity_id, formation.formation_id, command.target_position)
			return _validate_formation_move(probe, units, formations, battlefield_bounds, pathfinder)
		StrategicOrderCommand.OrderKind.ATTACK_TARGET:
			if command.formation_id == 0:
				var participant_result := _validate_strategic_participants(command, units, formations, battlefield_bounds, pathfinder, false)
				if not participant_result.is_accepted():
					return participant_result
				for entity_id in command.participant_entity_ids:
					var probe := AttackCommand.new(command.command_id, command.issuer_id, GameCommand.IssuerKind.PLAYER, command.issued_tick, entity_id, command.objective_entity_id)
					var attack_result := _validate_attack(probe, units, formations, buildings, faction_knowledge, logic_grid)
					if not attack_result.is_accepted():
						return attack_result
				return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
			if not formations.has(command.formation_id):
				return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
			var formation := formations[command.formation_id] as FormationState
			var probe := AttackCommand.new(command.command_id, command.issuer_id, GameCommand.IssuerKind.PLAYER, command.issued_tick, formation.leader_entity_id, command.objective_entity_id, formation.formation_id)
			return _validate_attack(probe, units, formations, buildings, faction_knowledge, logic_grid)
		StrategicOrderCommand.OrderKind.SCOUT_AREA:
			if command.target_radius <= 0.0 or not _is_valid_position(command.target_position, battlefield_bounds):
				return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
			return _validate_strategic_participants(command, units, formations, battlefield_bounds, pathfinder, true)
	return _rejected(CommandValidationResult.Reason.INVALID_TARGET)


func _strategic_participant_ids(command: StrategicOrderCommand, units: Dictionary, formations: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if command.order_kind == StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE:
		return result
	var candidates: Array[int] = []
	if command.formation_id != 0 and formations.has(command.formation_id):
		candidates.assign((formations[command.formation_id] as FormationState).member_entity_ids)
	else:
		candidates.assign(command.participant_entity_ids)
	for entity_id in candidates:
		var unit := units.get(entity_id) as UnitState
		if unit == null or not unit.enabled:
			continue
		if command.order_kind == StrategicOrderCommand.OrderKind.SCOUT_AREA:
			if unit.definition_id == &"scout_vehicle":
				result.append(entity_id)
		elif unit.can_attack and unit.can_accept_attack_orders and not unit.can_harvest and not unit.can_construct:
			result.append(entity_id)
	result.sort()
	return result


func _participant_sets_overlap(first: Array[int], second: Array[int]) -> bool:
	for entity_id in first:
		if second.has(entity_id):
			return true
	return false


func _validate_strategic_participants(
	command: StrategicOrderCommand,
	units: Dictionary,
	formations: Dictionary,
	battlefield_bounds: Rect2,
	pathfinder: GridPathfinder,
	require_scout: bool
) -> CommandValidationResult:
	var participant_entity_ids := _strategic_participant_ids(command, units, formations)
	if participant_entity_ids.is_empty():
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	for entity_id in participant_entity_ids:
		if not units.has(entity_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		var unit := units[entity_id] as UnitState
		var unit_result := _validate_unit(unit, command.issuer_id)
		if not unit_result.is_accepted():
			return unit_result
		if require_scout:
			if unit.definition_id != &"scout_vehicle":
				return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
		elif not unit.can_attack or not unit.can_accept_attack_orders or unit.can_harvest or unit.can_construct:
			return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
		if pathfinder != null and pathfinder.find_path(unit.position, command.target_position).is_empty():
			return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_task_control(command: TaskControlCommand, tasks: Dictionary) -> CommandValidationResult:
	if not tasks.has(command.controlled_task_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TASK)
	var task := tasks[command.controlled_task_id] as TaskState
	match command.action:
		TaskControlCommand.Action.PAUSE:
			if task.lifecycle != TaskState.Lifecycle.EXECUTING:
				return _rejected(CommandValidationResult.Reason.INVALID_TASK)
		TaskControlCommand.Action.RESUME:
			if task.lifecycle not in [TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]:
				return _rejected(CommandValidationResult.Reason.INVALID_TASK)
		TaskControlCommand.Action.CANCEL:
			if task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
				return _rejected(CommandValidationResult.Reason.INVALID_TASK)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _validate_unit(unit: UnitState, issuer_id: int) -> CommandValidationResult:
	if not unit.enabled:
		return _rejected(CommandValidationResult.Reason.ENTITY_DISABLED)
	if unit.controller_id != issuer_id:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func _is_valid_position(position: Vector2, battlefield_bounds: Rect2) -> bool:
	return position.is_finite() and battlefield_bounds.has_point(position)


func _rejected(reason: CommandValidationResult.Reason) -> CommandValidationResult:
	return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, reason)
