class_name EconomySystem
extends RefCounted

const HARVEST_AMOUNT := 20
const HARVEST_INTERVAL_TICKS := 10
const UNLOAD_TICKS := 5


func advance(
	units: Dictionary,
	buildings: Dictionary,
	ore_fields: Dictionary,
	factions: Dictionary,
	unit_catalog: UnitDefinitionCatalog,
	building_catalog: BuildingDefinitionCatalog,
	pathfinder: GridPathfinder,
	next_unit_id: int,
	events: Array[SimulationEvent],
	current_tick: int
) -> int:
	var unit_ids := units.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var unit := units[unit_id] as UnitState
		if not unit.enabled or not unit.can_harvest or unit.harvest_ore_field_entity_id == 0:
			continue
		if not ore_fields.has(unit.harvest_ore_field_entity_id) or not buildings.has(unit.harvest_refinery_entity_id):
			_clear_harvest(unit)
			continue
		var ore_field := ore_fields[unit.harvest_ore_field_entity_id] as OreFieldState
		var refinery := buildings[unit.harvest_refinery_entity_id] as BuildingState
		if ore_field.ore_remaining <= 0 or not refinery.enabled or refinery.faction_id != unit.faction_id:
			_clear_harvest(unit)
			continue
		match unit.harvest_phase:
			UnitState.HarvestPhase.TO_FIELD:
				if not unit.has_move_target:
					unit.harvest_phase = UnitState.HarvestPhase.LOADING
					unit.harvest_ticks_remaining = HARVEST_INTERVAL_TICKS
			UnitState.HarvestPhase.LOADING:
				unit.harvest_ticks_remaining -= 1
				if unit.harvest_ticks_remaining <= 0:
					var capacity := UNIT_CARGO_CAPACITY_FALLBACK
					var unit_definition := unit_catalog.get_unit(unit.definition_id)
					if unit_definition != null and unit_definition.cargo_capacity > 0:
						capacity = unit_definition.cargo_capacity
					var amount := mini(capacity, ore_field.ore_remaining)
					ore_field.ore_remaining -= amount
					unit.cargo_ore = amount
					unit.harvest_phase = UnitState.HarvestPhase.TO_REFINERY
					_start_path(unit, refinery.rally_position, pathfinder)
					events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.HARVEST_CARGO_LOADED, unit.entity_id, "amount=%d;field=%d" % [amount, ore_field.entity_id]))
			UnitState.HarvestPhase.TO_REFINERY:
				if not unit.has_move_target:
					unit.harvest_phase = UnitState.HarvestPhase.UNLOADING
					unit.harvest_ticks_remaining = UNLOAD_TICKS
			UnitState.HarvestPhase.UNLOADING:
				unit.harvest_ticks_remaining -= 1
				if unit.harvest_ticks_remaining <= 0:
					var delivered := unit.cargo_ore
					(factions[unit.faction_id] as FactionState).ore += delivered
					unit.cargo_ore = 0
					events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ORE_DELIVERED, unit.entity_id, "amount=%d;field=%d" % [delivered, ore_field.entity_id]))
					if ore_field.ore_remaining > 0:
						unit.harvest_phase = UnitState.HarvestPhase.TO_FIELD
						_start_path(unit, ore_field.position, pathfinder)
					else:
						_clear_harvest(unit)
			_:
				unit.harvest_phase = UnitState.HarvestPhase.TO_FIELD
				_start_path(unit, ore_field.position, pathfinder)

	var building_ids := buildings.keys()
	building_ids.sort()
	var allocated_id := next_unit_id
	for building_id in building_ids:
		var building := buildings[building_id] as BuildingState
		if not building.enabled or building.production_definition_id.is_empty():
			continue
		building.production_ticks_remaining -= 1
		if building.production_ticks_remaining > 0:
			continue
		var definition := unit_catalog.get_unit(building.production_definition_id)
		var deployment_position := _find_deployment_position(building, units, pathfinder)
		var unit := UnitState.new(allocated_id, deployment_position, definition.move_speed, building.controller_id)
		unit.definition_id = definition.definition_id
		unit.faction_id = building.faction_id
		_apply_combat(unit, definition)
		if building.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
			unit.assigned_agent_id = EnemyRaidAgent.AGENT_ID
			unit.assigned_task_id = EnemyRaidAgent.TASK_ID
		units[allocated_id] = unit
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_PRODUCED, allocated_id, "factory=%d;definition=%s" % [building.entity_id, definition.definition_id]))
		allocated_id += 1
		building.production_definition_id = &""
		building.production_ticks_remaining = 0
		building.production_cost_paid = 0
	return allocated_id


func _apply_combat(unit: UnitState, definition: UnitDefinition) -> void:
	unit.max_health = definition.combat.max_health
	unit.health = unit.max_health
	unit.armor = definition.combat.armor
	unit.attack_damage = definition.combat.attack_power
	unit.attack_range = definition.combat.attack_range
	unit.attacks_per_second = definition.combat.attacks_per_second
	unit.attack_cooldown_ticks = maxi(1, ceili(10.0 / unit.attacks_per_second))
	unit.projectile_speed = definition.combat.projectile_speed
	unit.sight_range = definition.sight_range
	unit.can_attack = definition.can_attack
	unit.can_accept_attack_orders = definition.can_accept_attack_orders
	unit.auto_retaliate = definition.auto_retaliate
	unit.can_harvest = definition.can_harvest
	unit.can_construct = definition.can_construct
	unit.can_repair = definition.can_repair


func _clear_harvest(unit: UnitState) -> void:
	unit.harvest_ore_field_entity_id = 0
	unit.harvest_refinery_entity_id = 0
	unit.harvest_ticks_remaining = 0
	unit.harvest_phase = UnitState.HarvestPhase.IDLE
	unit.cargo_ore = 0


const UNIT_CARGO_CAPACITY_FALLBACK := HARVEST_AMOUNT


func _start_path(unit: UnitState, destination: Vector2, pathfinder: GridPathfinder) -> void:
	unit.move_target = destination
	unit.path = pathfinder.find_path(unit.position, destination)
	unit.path_index = 1
	unit.has_move_target = unit.path.size() > 1


func _find_deployment_position(building: BuildingState, units: Dictionary, pathfinder: GridPathfinder) -> Vector2:
	var grid := pathfinder.logic_grid
	var building_cell := grid.world_to_cell(building.position)
	var outward_x := 1 if building_cell.x < LogicGrid.GRID_SIZE.x / 2 else -1
	var offsets: Array[Vector2i] = []
	for distance in range(4, 8):
		for y_offset in [0, -1, 1, -2, 2]:
			offsets.append(Vector2i(outward_x * distance, y_offset))
	for offset in offsets:
		var candidate := grid.cell_to_world(building_cell + offset)
		if not grid.is_world_position_walkable(candidate):
			continue
		var occupied := false
		for unit_variant in units.values():
			var existing := unit_variant as UnitState
			if existing.enabled and existing.position.distance_to(candidate) < LogicGrid.CELL_SIZE * 0.75:
				occupied = true
				break
		if not occupied:
			return candidate
	return building.rally_position
