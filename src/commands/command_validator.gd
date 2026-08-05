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
	tasks: Dictionary = {}
) -> CommandValidationResult:
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
		if not attacker.can_attack or not attacker.can_accept_attack_orders:
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
	if not formations.has(command.formation_id):
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	var formation := formations[command.formation_id] as FormationState
	if formation.leader_entity_id != command.target_entity_id:
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	for entity_id in formation.member_entity_ids:
		if not units.has(entity_id):
			return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
		var member := units[entity_id] as UnitState
		var member_result := _validate_unit(member, command.issuer_id)
		if not member_result.is_accepted():
			return member_result
		if command.issuer_kind == GameCommand.IssuerKind.AGENT and not _agent_can_control(member, command):
			return _rejected(CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED)
	if not _is_valid_position(command.target_position, battlefield_bounds):
		return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
	if pathfinder == null:
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
	var path := pathfinder.find_path(formation.anchor_position, command.target_position)
	if path.is_empty():
		return _rejected(CommandValidationResult.Reason.PATH_UNAVAILABLE)
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
	if not building.enabled or not building.operational or building_definition == null or not building_definition.provides_factory or unit_definition == null:
		return _rejected(CommandValidationResult.Reason.INVALID_DEFINITION)
	if building.controller_id != command.issuer_id:
		return _rejected(CommandValidationResult.Reason.NOT_CONTROLLER)
	if not building.production_definition_id.is_empty():
		return _rejected(CommandValidationResult.Reason.PRODUCTION_BUSY)
	if not factions.has(building.faction_id) or (factions[building.faction_id] as FactionState).ore < unit_definition.production_cost:
		return _rejected(CommandValidationResult.Reason.INSUFFICIENT_ORE)
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
	for task_variant in tasks.values():
		var task := task_variant as TaskState
		var task_industrial := task.kind == TaskState.Kind.DEVELOP_RESOURCE
		if task.kind != TaskState.Kind.FORMATION_MOVE_TEST and task.faction_id in [0, command.issuer_id] and task_industrial == requested_industrial and task.lifecycle in [TaskState.Lifecycle.WAITING, TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING, TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]:
			return _rejected(CommandValidationResult.Reason.TASK_CONFLICT)
	match command.order_kind:
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE:
			if not ore_fields.has(command.objective_entity_id) or not buildings.has(SimulationWorld.PLAYER_FACTORY_ID) or not buildings.has(SimulationWorld.PLAYER_COMMAND_CENTER_ID):
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
				return _validate_strategic_participants(command, units, battlefield_bounds, pathfinder, false)
			if not formations.has(command.formation_id):
				return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
			var formation := formations[command.formation_id] as FormationState
			var probe := FormationMoveCommand.new(command.command_id, command.issuer_id, command.issuer_kind, command.issued_tick, formation.leader_entity_id, formation.formation_id, command.target_position)
			return _validate_formation_move(probe, units, formations, battlefield_bounds, pathfinder)
		StrategicOrderCommand.OrderKind.ATTACK_TARGET:
			if command.formation_id == 0:
				var participant_result := _validate_strategic_participants(command, units, battlefield_bounds, pathfinder, false)
				if not participant_result.is_accepted():
					return participant_result
				for entity_id in command.participant_entity_ids:
					var probe := AttackCommand.new(command.command_id, command.issuer_id, command.issuer_kind, command.issued_tick, entity_id, command.objective_entity_id)
					var attack_result := _validate_attack(probe, units, formations, buildings, faction_knowledge, logic_grid)
					if not attack_result.is_accepted():
						return attack_result
				return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)
			if not formations.has(command.formation_id):
				return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
			var formation := formations[command.formation_id] as FormationState
			var probe := AttackCommand.new(command.command_id, command.issuer_id, command.issuer_kind, command.issued_tick, formation.leader_entity_id, command.objective_entity_id, formation.formation_id)
			return _validate_attack(probe, units, formations, buildings, faction_knowledge, logic_grid)
		StrategicOrderCommand.OrderKind.SCOUT_AREA:
			if command.target_radius <= 0.0 or not _is_valid_position(command.target_position, battlefield_bounds):
				return _rejected(CommandValidationResult.Reason.INVALID_POSITION)
			return _validate_strategic_participants(command, units, battlefield_bounds, pathfinder, true)
	return _rejected(CommandValidationResult.Reason.INVALID_TARGET)


func _validate_strategic_participants(
	command: StrategicOrderCommand,
	units: Dictionary,
	battlefield_bounds: Rect2,
	pathfinder: GridPathfinder,
	require_scout: bool
) -> CommandValidationResult:
	if command.participant_entity_ids.is_empty():
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	for entity_id in command.participant_entity_ids:
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
