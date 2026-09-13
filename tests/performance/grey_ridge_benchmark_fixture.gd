class_name GreyRidgeBenchmarkFixture
extends RefCounted

const FIRST_BENCHMARK_ENTITY_ID := 5000
const FIRST_BENCHMARK_FORMATION_ID := 100
const FIRST_BENCHMARK_PROJECTILE_ID := 900000


static func create_world(
	entity_count: int,
	chokepoint_stress: bool = false,
	projectile_count: int = 0
) -> SimulationWorld:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var remaining := maxi(0, entity_count - active_entity_count(world))
	var next_entity_id := FIRST_BENCHMARK_ENTITY_ID
	var next_formation_id := FIRST_BENCHMARK_FORMATION_ID
	var group_index := 0
	while remaining > 0:
		var group_size := mini(12, remaining)
		var faction_id := SimulationWorld.LOCAL_PLAYER_ID if group_index % 2 == 0 else SimulationWorld.ENEMY_PLAYER_ID
		var anchor := _formation_anchor(world, group_index, chokepoint_stress)
		var forward := Vector2.RIGHT if faction_id == SimulationWorld.LOCAL_PLAYER_ID else Vector2.LEFT
		var ids := world._create_scenario_formation(
			next_formation_id, faction_id, &"assault_vehicle", group_size,
			anchor, next_entity_id, forward
		)
		var formation := world.formations[next_formation_id] as FormationState
		_place_walkable_formation(world, formation, anchor)
		var destination := _formation_destination(world, anchor, group_index, chokepoint_stress)
		world._apply_command(FormationMoveCommand.new(
			world.allocate_command_id(), faction_id, GameCommand.IssuerKind.PLAYER,
			world.current_tick, formation.leader_entity_id, formation.formation_id, destination
		))
		next_entity_id += ids.size()
		next_formation_id += 1
		remaining -= group_size
		group_index += 1
	world._update_faction_knowledge()
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		unit.attack_damage = 1.0
		unit.base_attack_damage = 1.0
		if chokepoint_stress:
			unit.can_attack = false
			unit.health = maxf(unit.health, 10000.0)
			unit.max_health = maxf(unit.max_health, 10000.0)
	if projectile_count > 0:
		_seed_projectiles(world, projectile_count)
	return world


static func _place_walkable_formation(world: SimulationWorld, formation: FormationState, preferred: Vector2) -> void:
	# A spawn has no route origin yet; deployment validation cannot recover an
	# anchor inside an obstacle. Choose a complete walkable footprint first.
	var center := _walkable_spawn(world, formation, preferred)
	assert(center.is_finite(), "benchmark requires a walkable complete formation")
	formation.anchor_position = center
	formation.target_position = center
	formation.order_destination = center
	formation.reset_anchor_history(formation.initial_path_direction)
	var forward := formation.initial_path_direction
	var lateral := Vector2(-forward.y, forward.x)
	for id in formation.member_entity_ids:
		var unit := world.units[id] as UnitState
		var offset := formation.get_wide_offset(formation.get_slot_id(id))
		unit.position = center + forward * offset.x + lateral * offset.y
		assert(world.logic_grid.is_world_position_walkable(unit.position), "benchmark member spawned in an obstacle")
		unit.desired_position = unit.position
		unit.move_target = unit.position
		unit.has_move_target = false
		unit.following_formation = true


static func _walkable_spawn(world: SimulationWorld, formation: FormationState, preferred: Vector2) -> Vector2:
	var origin := world.logic_grid.world_to_cell(preferred)
	var forward := formation.initial_path_direction
	var lateral := Vector2(-forward.y, forward.x)
	for radius in range(25):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var center := preferred if radius == 0 else world.logic_grid.cell_to_world(origin + Vector2i(x, y))
				var fits := true
				for slot in range(formation.member_entity_ids.size()):
					var offset := formation.get_wide_offset(slot)
					if not world.logic_grid.is_world_position_walkable(center + forward * offset.x + lateral * offset.y):
						fits = false
						break
				if fits:
					return center
	return Vector2(INF, INF)


static func active_entity_count(world: SimulationWorld) -> int:
	var count := 0
	for unit_variant in world.units.values():
		if (unit_variant as UnitState).enabled:
			count += 1
	return count


static func benchmark_formation(world: SimulationWorld) -> FormationState:
	return world.formations.get(FIRST_BENCHMARK_FORMATION_ID) as FormationState


static func command_destination(world: SimulationWorld, eastbound: bool) -> Vector2:
	var preferred := world.logic_grid.cell_to_world(Vector2i(80 if eastbound else 15, 36))
	var formation := benchmark_formation(world)
	if formation == null:
		return world.battle_definition.player_headquarters_position
	var resolved := world.find_formation_deployment_position(formation, preferred, 768.0)
	return resolved if is_finite(resolved.x) and is_finite(resolved.y) else formation.anchor_position


static func _formation_anchor(world: SimulationWorld, group_index: int, chokepoint_stress: bool) -> Vector2:
	if not chokepoint_stress:
		var column := group_index % 6
		var row := group_index / 6
		return world.logic_grid.cell_to_world(Vector2i(8 + column * 12, 26 + row * 8))
	var starts_west := group_index % 2 == 0
	var lane := group_index / 2
	var x := 22 if starts_west else 72
	var y := 20 + lane * 5
	return world.logic_grid.cell_to_world(Vector2i(x, clampi(y, 16, 47)))


static func _formation_destination(
	world: SimulationWorld,
	anchor: Vector2,
	group_index: int,
	chokepoint_stress: bool
) -> Vector2:
	if not chokepoint_stress:
		return anchor + Vector2(0.0, 160.0 if group_index % 2 == 0 else -160.0)
	return command_destination(world, group_index % 2 == 0)


static func _seed_projectiles(world: SimulationWorld, projectile_count: int) -> void:
	var friendly_ids: Array[int] = []
	var hostile_ids: Array[int] = []
	for entity_id_variant in world.units.keys():
		var entity_id := int(entity_id_variant)
		var unit := world.units[entity_id] as UnitState
		if not unit.enabled:
			continue
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			friendly_ids.append(entity_id)
		else:
			hostile_ids.append(entity_id)
	friendly_ids.sort()
	hostile_ids.sort()
	var benchmark_friendly_ids := friendly_ids.filter(func(entity_id: int) -> bool: return entity_id >= FIRST_BENCHMARK_ENTITY_ID)
	var benchmark_hostile_ids := hostile_ids.filter(func(entity_id: int) -> bool: return entity_id >= FIRST_BENCHMARK_ENTITY_ID)
	if not benchmark_friendly_ids.is_empty() and not benchmark_hostile_ids.is_empty():
		friendly_ids.assign(benchmark_friendly_ids)
		hostile_ids.assign(benchmark_hostile_ids)
	if friendly_ids.is_empty() or hostile_ids.is_empty():
		return
	for index in range(projectile_count):
		var friendly_source := index % 2 == 0
		var source_ids := friendly_ids if friendly_source else hostile_ids
		var target_ids := hostile_ids if friendly_source else friendly_ids
		var source_id := source_ids[index % source_ids.size()]
		var target_id := target_ids[(index * 7) % target_ids.size()]
		var source := world.units[source_id] as UnitState
		var target := world.units[target_id] as UnitState
		var ratio := 0.15 + float(index % 8) * 0.1
		var projectile_id := FIRST_BENCHMARK_PROJECTILE_ID + index
		world.projectiles[projectile_id] = ProjectileState.new(
			projectile_id, source_id, target_id, source.faction_id,
			source.position.lerp(target.position, ratio), 0.0, 1.0, -1
		)
	world._next_projectile_id = FIRST_BENCHMARK_PROJECTILE_ID + projectile_count
