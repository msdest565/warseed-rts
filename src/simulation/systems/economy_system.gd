class_name EconomySystem
extends RefCounted

const HARVEST_AMOUNT := 20
const HARVEST_INTERVAL_TICKS := 10


func advance(
	units: Dictionary,
	buildings: Dictionary,
	ore_fields: Dictionary,
	factions: Dictionary,
	unit_catalog: UnitDefinitionCatalog,
	building_catalog: BuildingDefinitionCatalog,
	next_unit_id: int,
	events: Array[SimulationEvent],
	current_tick: int
) -> int:
	var unit_ids := units.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var unit := units[unit_id] as UnitState
		if not unit.enabled or unit.harvest_ore_field_entity_id == 0:
			continue
		if not ore_fields.has(unit.harvest_ore_field_entity_id) or not buildings.has(unit.harvest_refinery_entity_id):
			_clear_harvest(unit)
			continue
		var ore_field := ore_fields[unit.harvest_ore_field_entity_id] as OreFieldState
		var refinery := buildings[unit.harvest_refinery_entity_id] as BuildingState
		if ore_field.ore_remaining <= 0 or not refinery.enabled or refinery.faction_id != unit.faction_id:
			_clear_harvest(unit)
			continue
		unit.harvest_ticks_remaining -= 1
		if unit.harvest_ticks_remaining > 0:
			continue
		var amount := mini(HARVEST_AMOUNT, ore_field.ore_remaining)
		ore_field.ore_remaining -= amount
		(factions[unit.faction_id] as FactionState).ore += amount
		unit.harvest_ticks_remaining = HARVEST_INTERVAL_TICKS
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.ORE_DELIVERED, unit.entity_id, "amount=%d;field=%d" % [amount, ore_field.entity_id]))

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
		var unit := UnitState.new(allocated_id, building.rally_position, definition.move_speed, building.controller_id)
		unit.definition_id = definition.definition_id
		unit.faction_id = building.faction_id
		_apply_combat(unit, definition)
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


func _clear_harvest(unit: UnitState) -> void:
	unit.harvest_ore_field_entity_id = 0
	unit.harvest_refinery_entity_id = 0
	unit.harvest_ticks_remaining = 0
