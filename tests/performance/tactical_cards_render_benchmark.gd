extends "res://tests/performance/grey_ridge_windows_render_benchmark.gd"


func _create_benchmark_world(entity_count: int, projectile_count: int) -> SimulationWorld:
	var world := TestTacticalCards.sample_world()
	TestTacticalCards._quiet(world)
	var index := 0
	for value in world.unit_cards.values():
		var card := value as UnitCardState
		_place_formation(world, world.formations[card.formation_id], SimulationWorld.GREY_RIDGE_CENTRAL_POSITION + Vector2((index % 3) * 240 - 500, (index / 3) * 200))
		index += 1
	var remaining := entity_count - GreyRidgeBenchmarkFixture.active_entity_count(world)
	var entity_id := GreyRidgeBenchmarkFixture.FIRST_BENCHMARK_ENTITY_ID
	var formation_id := GreyRidgeBenchmarkFixture.FIRST_BENCHMARK_FORMATION_ID
	while remaining > 0:
		var count := mini(10, remaining)
		var faction := 1 if formation_id == GreyRidgeBenchmarkFixture.FIRST_BENCHMARK_FORMATION_ID else 2
		var anchor := SimulationWorld.GREY_RIDGE_CENTRAL_POSITION + Vector2(160, 120 * (formation_id - 100))
		var members := world._create_scenario_formation(formation_id, faction, &"assault_vehicle", count, anchor, entity_id, Vector2.RIGHT)
		_place_formation(world, world.formations[formation_id], anchor)
		entity_id += members.size()
		formation_id += 1
		remaining -= count
	for value in world.units.values():
		var unit := value as UnitState
		if unit.suppression_power <= 0.0:
			unit.can_attack = false
		unit.health = 10000.0
		unit.max_health = 10000.0
	world._update_faction_knowledge()
	var observe := TacticalAbilityCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, &"forward_observers")
	world.submit_command(observe)
	if projectile_count > 0:
		GreyRidgeBenchmarkFixture._seed_projectiles(world, projectile_count)
	return world


func _configure_benchmark_game(game: GameRoot, snapshot: WorldSnapshot) -> void:
	game.simulation_host._grey_ridge_army_plan = game.simulation_host.world.grey_ridge_army_plan.duplicate_plan()
	game.simulation_host._grey_ridge_battle_started = true
	game._on_scenario_restarted(snapshot)


func _place_formation(world: SimulationWorld, formation: FormationState, preferred: Vector2) -> void:
	var center := world.find_formation_deployment_position(formation, preferred, 768.0)
	assert(center.is_finite(), "benchmark requires a walkable complete formation")
	formation.anchor_position = center
	formation.target_position = center
	formation.order_destination = center
	formation.is_moving = false
	formation.path = PackedVector2Array()
	formation.reset_anchor_history(Vector2.RIGHT)
	for id in formation.member_entity_ids:
		var unit := world.units[id] as UnitState
		unit.position = center + formation.get_wide_offset(formation.get_slot_id(id))
		assert(world.logic_grid.is_world_position_walkable(unit.position), "benchmark member spawned in an obstacle")
		unit.desired_position = unit.position
		unit.move_target = unit.position
		unit.has_move_target = false
		unit.following_formation = true
		unit.assigned_task_id = 0
