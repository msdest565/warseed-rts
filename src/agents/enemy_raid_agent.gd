class_name EnemyRaidAgent
extends RefCounted

enum Phase {
	ECONOMY,
	EXPANSION,
	SCOUTING,
	CONTESTING,
	MUSTERING,
	RAIDING,
	RETREATING,
	DEFENDING,
}

const AGENT_ID := 301
const TASK_ID := 9001
const RAID_UNIT_ID := 1099
const STRATEGY_START_TICK := 300
const ORDER_INTERVAL_TICKS := 10
const SCOUT_TIMEOUT_TICKS := 140
const CONTEST_TIMEOUT_TICKS := 140
const RAID_DURATION_TICKS := 400
const RETREAT_TIMEOUT_TICKS := 240
const DEFEND_DURATION_TICKS := 220
const RAID_FORCE_SIZE := 3
const ENEMY_FACTORY_POSITION := Vector2i(79, 51)
const SCOUT_POSITION := Vector2i(53, 32)

var phase: Phase = Phase.ECONOMY
var phase_started_tick: int = 0
var phase_history: Array[Phase] = [Phase.ECONOMY]
var last_order_tick: int = -ORDER_INTERVAL_TICKS
var last_unit_order_tick: Dictionary = {}
var completed_cycles: int = 0
var spawned: bool = false


func advance(world: SimulationWorld) -> void:
	if world.current_tick < STRATEGY_START_TICK:
		return
	_claim_enemy_units(world)
	_ensure_harvest(world)
	_defend_harvester(world)
	match phase:
		Phase.ECONOMY:
			if world.current_tick >= STRATEGY_START_TICK:
				_change_phase(Phase.EXPANSION, world)
		Phase.EXPANSION:
			_advance_expansion(world)
		Phase.SCOUTING:
			_advance_scouting(world)
		Phase.CONTESTING:
			_advance_contesting(world)
		Phase.MUSTERING:
			_advance_mustering(world)
		Phase.RAIDING:
			_advance_raiding(world)
		Phase.RETREATING:
			_advance_retreating(world)
		Phase.DEFENDING:
			_advance_defending(world)


func phase_name() -> String:
	return Phase.keys()[phase]


func _advance_expansion(world: SimulationWorld) -> void:
	var factory := _enemy_factory(world)
	if factory != null:
		if factory.operational:
			_change_phase(Phase.SCOUTING, world)
		return
	var engineer := world.units.get(SimulationWorld.ENEMY_ENGINEER_ID) as UnitState
	if engineer == null or not engineer.enabled or engineer.work_kind != UnitState.WorkKind.NONE:
		return
	var command := BuildBuildingCommand.new(
		world.allocate_command_id(),
		SimulationWorld.ENEMY_PLAYER_ID,
		GameCommand.IssuerKind.AGENT,
		world.current_tick,
		engineer.entity_id,
		&"automated_factory",
		world.logic_grid.cell_to_world(ENEMY_FACTORY_POSITION)
	)
	_submit(command, world)


func _advance_scouting(world: SimulationWorld) -> void:
	var scout := _first_combat_unit(world, &"scout_vehicle")
	if scout == null:
		_submit_production(&"scout_vehicle", world)
		return
	var destination := world.logic_grid.cell_to_world(SCOUT_POSITION)
	_submit_move(scout, destination, world)
	if scout.position.distance_to(destination) <= 72.0 or _phase_elapsed(world) >= SCOUT_TIMEOUT_TICKS:
		_change_phase(Phase.CONTESTING, world)


func _advance_contesting(world: SimulationWorld) -> void:
	var scout := _first_combat_unit(world, &"scout_vehicle")
	var ore_field := world.ore_fields.get(SimulationWorld.DEFAULT_ORE_FIELD_ID) as OreFieldState
	if scout != null and ore_field != null:
		_submit_move(scout, ore_field.position, world)
	if scout == null or ore_field == null or scout.position.distance_to(ore_field.position) <= 96.0 or _phase_elapsed(world) >= CONTEST_TIMEOUT_TICKS:
		_change_phase(Phase.MUSTERING, world)


func _advance_mustering(world: SimulationWorld) -> void:
	var combat_units := _combat_units(world)
	if combat_units.size() >= RAID_FORCE_SIZE:
		_change_phase(Phase.RAIDING, world)
		spawned = true
		return
	_submit_production(&"assault_vehicle", world)


func _advance_raiding(world: SimulationWorld) -> void:
	var combat_units := _combat_units(world)
	if combat_units.size() <= 1 or _phase_elapsed(world) >= RAID_DURATION_TICKS:
		_change_phase(Phase.RETREATING, world)
		return
	var knowledge := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	for unit in combat_units:
		var target_id := _best_visible_target(knowledge, unit.position)
		if target_id != 0:
			_submit_attack(unit, target_id, world)
		else:
			var stale_position := _newest_stale_position(knowledge)
			if stale_position != Vector2.ZERO:
				_submit_move(unit, stale_position, world)
			else:
				var ore_field := world.ore_fields.get(SimulationWorld.DEFAULT_ORE_FIELD_ID) as OreFieldState
				if ore_field != null:
					_submit_move(unit, ore_field.position, world)


func _advance_retreating(world: SimulationWorld) -> void:
	var base_position := _base_rally_position(world)
	var all_home := true
	for unit in _combat_units(world):
		if unit.position.distance_to(base_position) > 160.0:
			all_home = false
			_submit_move(unit, base_position, world)
	if all_home or _phase_elapsed(world) >= RETREAT_TIMEOUT_TICKS:
		_change_phase(Phase.DEFENDING, world)


func _advance_defending(world: SimulationWorld) -> void:
	var base_position := _base_rally_position(world)
	var knowledge := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	for unit in _combat_units(world):
		var target_id := _best_visible_target(knowledge, base_position, 520.0)
		if target_id != 0:
			_submit_attack(unit, target_id, world)
		elif unit.position.distance_to(base_position) > 180.0:
			_submit_move(unit, base_position, world)
	if _phase_elapsed(world) >= DEFEND_DURATION_TICKS:
		completed_cycles += 1
		_change_phase(Phase.MUSTERING, world)


func _ensure_harvest(world: SimulationWorld) -> void:
	var harvester := world.units.get(SimulationWorld.ENEMY_HARVESTER_ID) as UnitState
	if harvester == null or not harvester.enabled or harvester.harvest_ore_field_entity_id != 0:
		return
	var ore_field := world.ore_fields.get(SimulationWorld.ENEMY_ORE_FIELD_ID) as OreFieldState
	var refinery := world.buildings.get(SimulationWorld.ENEMY_COMMAND_CENTER_ID) as BuildingState
	if ore_field == null or ore_field.ore_remaining <= 0 or refinery == null or not refinery.enabled:
		return
	var command := HarvestCommand.new(
		world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, harvester.entity_id, ore_field.entity_id, refinery.entity_id
	)
	_submit(command, world)


func _defend_harvester(world: SimulationWorld) -> void:
	var harvester := world.units.get(SimulationWorld.ENEMY_HARVESTER_ID) as UnitState
	if harvester == null or not harvester.enabled or not harvester.can_attack or harvester.harvest_ore_field_entity_id == 0:
		return
	var snapshot := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	var target_id := _best_visible_target(snapshot, harvester.position, harvester.attack_range)
	if target_id != 0:
		_submit_attack(harvester, target_id, world)


func _submit_production(definition_id: StringName, world: SimulationWorld) -> void:
	var factory := _enemy_factory(world)
	if factory == null or not factory.operational or not factory.production_definition_id.is_empty():
		return
	var command := ProduceUnitCommand.new(
		world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, factory.entity_id, definition_id
	)
	_submit(command, world)


func _submit_attack(unit: UnitState, target_entity_id: int, world: SimulationWorld) -> void:
	if unit.attack_target_entity_id == target_entity_id:
		return
	var command := AttackCommand.new(
		world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, unit.entity_id, target_entity_id
	)
	_submit(command, world)


func _submit_move(unit: UnitState, destination: Vector2, world: SimulationWorld) -> void:
	if unit.has_move_target and unit.move_target.is_equal_approx(destination):
		return
	if world.current_tick - int(last_unit_order_tick.get(unit.entity_id, -ORDER_INTERVAL_TICKS)) < ORDER_INTERVAL_TICKS:
		return
	var command := MoveCommand.new(
		world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, unit.entity_id, destination
	)
	_submit(command, world)


func _submit(command: GameCommand, world: SimulationWorld) -> bool:
	_set_context(command)
	var accepted := world.submit_command(command).is_accepted()
	if accepted:
		last_order_tick = world.current_tick
		if world.units.has(command.target_entity_id):
			last_unit_order_tick[command.target_entity_id] = world.current_tick
	return accepted


func _set_context(command: GameCommand) -> void:
	command.agent_id = AGENT_ID
	command.task_id = TASK_ID


func _enemy_factory(world: SimulationWorld) -> BuildingState:
	for building_variant in world.buildings.values():
		var building := building_variant as BuildingState
		if building.faction_id == SimulationWorld.ENEMY_PLAYER_ID and building.definition_id == &"automated_factory" and building.enabled:
			return building
	return null


func _base_rally_position(world: SimulationWorld) -> Vector2:
	var command_center := world.buildings.get(SimulationWorld.ENEMY_COMMAND_CENTER_ID) as BuildingState
	return command_center.rally_position if command_center != null and command_center.enabled else world.logic_grid.cell_to_world(LogicGrid.MAP_DEFINITION.enemy_spawn_cell + Vector2i(-4, 0))


func _first_combat_unit(world: SimulationWorld, definition_id: StringName = &"") -> UnitState:
	for unit in _combat_units(world):
		if definition_id.is_empty() or unit.definition_id == definition_id:
			return unit
	return null


func _combat_units(world: SimulationWorld) -> Array[UnitState]:
	var result: Array[UnitState] = []
	var entity_ids := world.units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := world.units[entity_id] as UnitState
		if unit.enabled and unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID and unit.entity_id != SimulationWorld.DEFAULT_ENEMY_UNIT_ID and unit.can_attack and not unit.can_harvest and not unit.can_construct:
			result.append(unit)
	return result


func _best_visible_target(snapshot: WorldSnapshot, origin: Vector2, max_distance: float = INF) -> int:
	var best_id := 0
	var best_priority := 99
	var best_distance := INF
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID or not contact.enabled or not contact.is_visible_to_local_player:
			continue
		var distance := origin.distance_squared_to(contact.position)
		if distance > max_distance * max_distance:
			continue
		var priority := 0 if contact.definition_id == &"harvester" else 1
		if priority < best_priority or (priority == best_priority and (distance < best_distance or (is_equal_approx(distance, best_distance) and contact.entity_id < best_id))):
			best_id = contact.entity_id
			best_priority = priority
			best_distance = distance
	if best_id != 0:
		return best_id
	for building in snapshot.buildings:
		if building.faction_id == SimulationWorld.ENEMY_PLAYER_ID or not building.enabled or not building.is_visible:
			continue
		var distance := origin.distance_squared_to(building.position)
		if distance <= max_distance * max_distance and (distance < best_distance or (is_equal_approx(distance, best_distance) and building.entity_id < best_id)):
			best_id = building.entity_id
			best_distance = distance
	return best_id


func _newest_stale_position(snapshot: WorldSnapshot) -> Vector2:
	var newest_tick := -1
	var newest_id := 0
	var result := Vector2.ZERO
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID or contact.is_visible_to_local_player:
			continue
		if contact.last_seen_tick > newest_tick or (contact.last_seen_tick == newest_tick and contact.entity_id < newest_id):
			newest_tick = contact.last_seen_tick
			newest_id = contact.entity_id
			result = contact.last_seen_position
	return result


func _claim_enemy_units(world: SimulationWorld) -> void:
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id != SimulationWorld.ENEMY_PLAYER_ID or unit.entity_id == SimulationWorld.DEFAULT_ENEMY_UNIT_ID:
			continue
		unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
		unit.assigned_agent_id = AGENT_ID
		unit.assigned_task_id = TASK_ID


func _change_phase(next_phase: Phase, world: SimulationWorld) -> void:
	if phase == next_phase:
		return
	phase = next_phase
	phase_started_tick = world.current_tick
	phase_history.append(next_phase)
	world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.ENEMY_PHASE_CHANGED, SimulationWorld.ENEMY_PLAYER_ID, phase_name()))


func _phase_elapsed(world: SimulationWorld) -> int:
	return world.current_tick - phase_started_tick
