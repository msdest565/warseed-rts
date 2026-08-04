class_name EngineeringSystem
extends RefCounted

const WORK_RANGE := 96.0


func advance(
	units: Dictionary,
	buildings: Dictionary,
	building_catalog: BuildingDefinitionCatalog,
	events: Array[SimulationEvent],
	current_tick: int
) -> void:
	var unit_ids := units.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		var engineer := units[unit_id] as UnitState
		if not engineer.enabled or engineer.work_kind == UnitState.WorkKind.NONE:
			continue
		var building := buildings.get(engineer.work_target_building_id) as BuildingState
		if building == null or not building.enabled:
			_clear_work(engineer)
			continue
		if engineer.has_move_target or engineer.position.distance_to(building.position) > WORK_RANGE:
			continue
		var definition := building_catalog.get_building(building.definition_id)
		if definition == null:
			_clear_work(engineer)
			continue
		if engineer.work_kind == UnitState.WorkKind.CONSTRUCT:
			_advance_construction(engineer, building, events, current_tick)
		elif engineer.work_kind == UnitState.WorkKind.REPAIR:
			_advance_repair(engineer, building, definition, events, current_tick)


func _advance_construction(
	engineer: UnitState,
	building: BuildingState,
	events: Array[SimulationEvent],
	current_tick: int
) -> void:
	if not building.under_construction:
		_clear_work(engineer)
		return
	building.construction_ticks_remaining = maxi(0, building.construction_ticks_remaining - 1)
	var completed_ratio := 1.0 - float(building.construction_ticks_remaining) / maxf(1.0, building.construction_ticks_total)
	building.health = lerpf(building.max_health * 0.1, building.max_health, completed_ratio)
	if building.construction_ticks_remaining > 0:
		return
	building.health = building.max_health
	building.under_construction = false
	building.operational = true
	building.builder_entity_id = 0
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.CONSTRUCTION_COMPLETED, building.entity_id, "builder=%d" % engineer.entity_id))
	_clear_work(engineer)


func _advance_repair(
	engineer: UnitState,
	building: BuildingState,
	definition: BuildingDefinition,
	events: Array[SimulationEvent],
	current_tick: int
) -> void:
	if building.under_construction:
		_clear_work(engineer)
		return
	building.health = minf(building.max_health, building.health + definition.repair_per_tick)
	if building.health < building.max_health:
		return
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.BUILDING_REPAIRED, building.entity_id, "engineer=%d" % engineer.entity_id))
	_clear_work(engineer)


func _clear_work(engineer: UnitState) -> void:
	engineer.work_kind = UnitState.WorkKind.NONE
	engineer.work_target_building_id = 0
