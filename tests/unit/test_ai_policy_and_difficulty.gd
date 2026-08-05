class_name TestAiPolicyAndDifficulty
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_friendly_agent_authorization(failures)
	_test_difficulty_profiles_and_reaction_windows(failures)
	_test_target_scoring_prefers_combat_threat(failures)
	_test_observed_composition_changes_production(failures)
	_test_chase_limit(failures)
	return failures


func _test_friendly_agent_authorization(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	_expect(world.set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, AgentPolicy.Authorization.ADVISORY), "industrial authorization should be configurable", failures)
	var ore_field := world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState
	var advisory_order := StrategicOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE, 0, ore_field.entity_id, ore_field.position
	)
	_expect(world.submit_command(advisory_order).reason == CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED, "advisory mode must reject execution rather than only changing the UI", failures)
	var queued_world := SimulationWorld.new()
	var queued_order := StrategicOrderCommand.new(
		queued_world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, queued_world.current_tick,
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE, 0, SimulationWorld.DEFAULT_ORE_FIELD_ID,
		(queued_world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState).position
	)
	queued_world.submit_command(queued_order)
	queued_world.set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, AgentPolicy.Authorization.ADVISORY)
	_expect(queued_world.command_queue.size() == 0, "authorization revocation should remove a not-yet-applied Agent delegation", failures)

	world.set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, AgentPolicy.Authorization.ASSISTED)
	var assisted_order := StrategicOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE, 0, ore_field.entity_id, ore_field.position
	)
	_expect(world.submit_command(assisted_order).is_accepted(), "assisted mode should execute an explicit player delegation", failures)
	world.advance_tick()
	var active_task: TaskState
	for task_variant in world.tasks.values():
		var task := task_variant as TaskState
		if task.agent_id == StrategicTaskSystem.INDUSTRIAL_AGENT_ID:
			active_task = task
			break
	world.set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, AgentPolicy.Authorization.ADVISORY)
	_expect(active_task != null and active_task.lifecycle == TaskState.Lifecycle.PAUSED, "lowering authorization to advisory should pause an executing Agent task", failures)

	var autonomous_world := SimulationWorld.new()
	autonomous_world.set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	autonomous_world.advance_tick()
	autonomous_world.advance_tick()
	var autonomous_task: TaskState
	for task_variant in autonomous_world.tasks.values():
		var task := task_variant as TaskState
		if task.agent_id == StrategicTaskSystem.INDUSTRIAL_AGENT_ID:
			autonomous_task = task
			break
	_expect(autonomous_task != null and autonomous_task.requires_proactive_authorization, "autonomous industrial AI should create a marked development task without a player order", failures)
	autonomous_world.set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, AgentPolicy.Authorization.DELEGATED)
	_expect(autonomous_task != null and autonomous_task.lifecycle == TaskState.Lifecycle.PAUSED, "dropping below autonomous should pause a proactively created task", failures)


func _test_difficulty_profiles_and_reaction_windows(failures: Array[String]) -> void:
	for profile in [
		SimulationWorld.ENEMY_DIFFICULTY_EASY,
		SimulationWorld.ENEMY_DIFFICULTY_NORMAL,
		SimulationWorld.ENEMY_DIFFICULTY_HARD,
		SimulationWorld.ENEMY_DIFFICULTY_EXPERT,
	]:
		_expect((profile as EnemyDifficultyProfile).validation_errors().is_empty(), "%s difficulty profile should satisfy AI configuration invariants" % (profile as EnemyDifficultyProfile).difficulty_name(), failures)
	var easy_world := SimulationWorld.new()
	easy_world.set_enemy_difficulty(EnemyDifficultyProfile.Difficulty.EASY)
	var hard_world := SimulationWorld.new()
	hard_world.set_enemy_difficulty(EnemyDifficultyProfile.Difficulty.HARD)
	_expect(easy_world.enemy_raid_agent.difficulty_profile.target_score_noise > hard_world.enemy_raid_agent.difficulty_profile.target_score_noise, "easy difficulty should use more target-selection noise than hard", failures)
	_expect(easy_world.enemy_raid_agent.difficulty_profile.tactical_decision_interval_ticks > hard_world.enemy_raid_agent.difficulty_profile.tactical_decision_interval_ticks, "hard difficulty should make tactical decisions more frequently", failures)
	var easy_reaction := _ticks_until_defense(easy_world)
	var hard_reaction := _ticks_until_defense(hard_world)
	_expect(hard_reaction < easy_reaction, "hard difficulty should react to the same visible base threat sooner than easy", failures)
	_expect(easy_reaction <= easy_world.enemy_raid_agent.difficulty_profile.reaction_delay_ticks + 1, "easy AI should still react within its configured response window", failures)


func _ticks_until_defense(world: SimulationWorld) -> int:
	world.spawn_enemy_raid_unit(1097, EnemyRaidAgent.AGENT_ID, EnemyRaidAgent.TASK_ID)
	world.spawn_enemy_raid_unit(1098, EnemyRaidAgent.AGENT_ID, EnemyRaidAgent.TASK_ID)
	var enemy_base := (world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState).rally_position
	var intruder := world.units[4] as UnitState
	intruder.position = enemy_base + Vector2(-64.0, 0.0)
	intruder.following_formation = false
	world.current_tick = EnemyRaidAgent.STRATEGY_START_TICK
	world.enemy_raid_agent.phase = EnemyRaidAgent.Phase.RAIDING
	world.enemy_raid_agent.phase_started_tick = world.current_tick
	world._update_faction_knowledge()
	for elapsed in range(100):
		world.enemy_raid_agent.advance(world)
		if world.enemy_raid_agent.phase == EnemyRaidAgent.Phase.DEFENDING:
			return elapsed
		world.current_tick += 1
	return 100


func _test_target_scoring_prefers_combat_threat(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	world.set_enemy_difficulty(EnemyDifficultyProfile.Difficulty.EXPERT)
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	var player_harvester := world.units[1] as UnitState
	var player_missile := world.units[5] as UnitState
	enemy.position = world.logic_grid.cell_to_world(Vector2i(30, 30))
	player_harvester.position = enemy.position + Vector2(-64.0, 0.0)
	player_missile.position = enemy.position + Vector2(64.0, 0.0)
	for entity_id in [2, 3, 4]:
		(world.units[entity_id] as UnitState).position = world.logic_grid.cell_to_world(Vector2i(4, 4 + entity_id))
	world._update_faction_knowledge()
	var snapshot := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	var target_id := world.enemy_raid_agent._best_visible_target(snapshot, enemy.position, INF, world)
	_expect(target_id == player_missile.entity_id, "target scoring should prefer an equally distant high-threat missile unit over a worker", failures)


func _test_observed_composition_changes_production(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	world.set_enemy_difficulty(EnemyDifficultyProfile.Difficulty.HARD)
	var observer := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	observer.position = world.logic_grid.cell_to_world(Vector2i(30, 30))
	world.spawn_enemy_raid_unit(1097, EnemyRaidAgent.AGENT_ID, EnemyRaidAgent.TASK_ID, &"assault_vehicle")
	world.spawn_enemy_raid_unit(1098, EnemyRaidAgent.AGENT_ID, EnemyRaidAgent.TASK_ID, &"missile_vehicle")
	for entity_id in [1, 2, 3, 4]:
		(world.units[entity_id] as UnitState).position = world.logic_grid.cell_to_world(Vector2i(4, 4 + entity_id))
	var first_missile := world.units[5] as UnitState
	first_missile.position = observer.position + Vector2(64.0, 0.0)
	for entity_id in [20, 21]:
		var definition := SimulationWorld.UNIT_CATALOG.get_unit(&"missile_vehicle")
		var missile := UnitState.new(entity_id, observer.position + Vector2(64.0, (entity_id - 20) * 32.0 + 32.0), definition.move_speed, SimulationWorld.LOCAL_PLAYER_ID)
		world._apply_unit_definition(missile, definition)
		world.units[entity_id] = missile
	world._update_faction_knowledge()
	_expect(world.enemy_raid_agent._next_combat_definition(world) == &"assault_vehicle", "hard AI should produce frontline assault units after observing a missile-heavy force", failures)
	_expect(world.enemy_raid_agent.last_observed_composition.contains("missile=3.0"), "counter planning should report only the composition present in faction knowledge", failures)


func _test_chase_limit(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	world.set_enemy_difficulty(EnemyDifficultyProfile.Difficulty.NORMAL)
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.attack_target_entity_id = 4
	world.enemy_raid_agent.engagement_origin_by_unit[enemy.entity_id] = enemy.position
	world.enemy_raid_agent.engagement_started_tick_by_unit[enemy.entity_id] = world.current_tick
	enemy.position += Vector2(world.enemy_raid_agent.difficulty_profile.chase_distance + 32.0, 0.0)
	_expect(world.enemy_raid_agent._chase_limit_exceeded(enemy, world), "an Agent pursuit should end after exceeding the configured distance leash", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
