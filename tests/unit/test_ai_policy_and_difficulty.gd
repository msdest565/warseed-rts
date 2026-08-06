class_name TestAiPolicyAndDifficulty
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_friendly_agent_authorization(failures)
	_test_autonomous_reconnaissance_and_defense_run_in_parallel(failures)
	_test_autonomous_counterattack_preempts_routine_defense(failures)
	_test_autonomous_base_threat_triggers_emergency_defense(failures)
	_test_long_autonomous_run_reclaims_temporary_formations(failures)
	_test_autonomous_scout_evades_contact(failures)
	_test_headquarters_balances_economy_and_combat(failures)
	_test_headquarters_preserves_emergency_reserve(failures)
	_test_full_takeover_arbitrates_low_resources(failures)
	_test_headquarters_reserves_player_queue_capacity(failures)
	_test_emergency_defense_can_use_reserved_ore(failures)
	_test_friendly_composition_responds_to_observed_threat(failures)
	_test_difficulty_profiles_and_reaction_windows(failures)
	_test_target_scoring_prefers_combat_threat(failures)
	_test_observed_composition_changes_production(failures)
	_test_enemy_production_commitments(failures)
	_test_chase_limit(failures)
	return failures


func _test_autonomous_reconnaissance_and_defense_run_in_parallel(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	world.advance_tick()
	world.advance_tick()
	var defense: TaskState
	var scout_task: TaskState
	for task_variant in world.tasks.values():
		var task := task_variant as TaskState
		if task.agent_id != StrategicTaskSystem.BATTLEFIELD_AGENT_ID:
			continue
		if task.kind == TaskState.Kind.DEFEND_AREA:
			defense = task
		elif task.kind == TaskState.Kind.SCOUT_AREA:
			scout_task = task
	_expect(defense != null and scout_task != null, "autonomous battlefield AI should run routine defense and reconnaissance in parallel", failures)
	if defense == null or scout_task == null:
		return
	_expect(not _ids_overlap(defense.participant_entity_ids, scout_task.participant_entity_ids), "parallel autonomous tasks must not assign one unit to conflicting work", failures)
	_expect(not world.pathfinder.find_path((world.units[3] as UnitState).position, scout_task.target_position).is_empty(), "autonomous reconnaissance should choose a reachable frontier", failures)
	var initial_position := (world.units[3] as UnitState).position
	var furthest_distance := 0.0
	for _tick in range(80):
		world.advance_tick()
		furthest_distance = maxf(furthest_distance, (world.units[3] as UnitState).position.distance_to(initial_position))
	_expect(furthest_distance >= 96.0, "autonomous scout should make visible progress toward its reconnaissance area", failures)
	_expect(scout_task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.EXECUTING], "reachable reconnaissance should not become permanently blocked", failures)


func _test_autonomous_counterattack_preempts_routine_defense(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	world.advance_tick()
	world.advance_tick()
	var routine_defense: TaskState
	var scout_task: TaskState
	for task_variant in world.tasks.values():
		var task := task_variant as TaskState
		if task.kind == TaskState.Kind.DEFEND_AREA:
			routine_defense = task
		elif task.kind == TaskState.Kind.SCOUT_AREA:
			scout_task = task
	if routine_defense == null or scout_task == null:
		_expect(false, "counterattack fixture requires autonomous defense and scout tasks", failures)
		return
	var scout := world.units[scout_task.participant_entity_ids[0]] as UnitState
	var scout_formation := world.formations[scout_task.formation_id] as FormationState
	scout.position = world.logic_grid.cell_to_world(Vector2i(38, 28))
	scout_formation.anchor_position = scout.position
	scout_formation.is_moving = false
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = scout.position + Vector2(64.0, 0.0)
	world._update_faction_knowledge()
	var attack_task: TaskState
	for _tick in range(12):
		world.advance_tick()
		for task_variant in world.tasks.values():
			var task := task_variant as TaskState
			if task.kind == TaskState.Kind.ATTACK_TARGET and task.target_entity_id == enemy.entity_id and task.lifecycle == TaskState.Lifecycle.EXECUTING:
				attack_task = task
		if attack_task != null:
			break
	_expect(attack_task != null, "autonomous AI should create a counterattack shortly after a scout reveals a distant hostile", failures)
	_expect(routine_defense.lifecycle == TaskState.Lifecycle.CANCELLED, "counterattack should legally preempt lower-priority routine defense", failures)
	if attack_task != null:
		for _tick in range(3):
			world.advance_tick()
		var responding := false
		for entity_id in attack_task.participant_entity_ids:
			var unit := world.units[entity_id] as UnitState
			responding = responding or unit.attack_target_entity_id == enemy.entity_id or unit.has_move_target or (world.formations[attack_task.formation_id] as FormationState).is_moving
		_expect(responding, "counterattack participants should pursue or engage through the authoritative command chain", failures)


func _test_autonomous_base_threat_triggers_emergency_defense(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var base := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = base.position + Vector2(96.0, 0.0)
	world._update_faction_knowledge()
	world.set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	for _tick in range(4):
		world.advance_tick()
	var emergency_defense: TaskState
	for task_variant in world.tasks.values():
		var task := task_variant as TaskState
		if task.kind == TaskState.Kind.DEFEND_AREA and task.priority == SimulationWorld.AUTONOMY_PRIORITY_BASE_THREAT:
			emergency_defense = task
			break
	_expect(emergency_defense != null, "visible hostiles near the command center should trigger emergency defense", failures)
	if emergency_defense != null:
		var has_response := false
		for entity_id in emergency_defense.participant_entity_ids:
			var unit := world.units[entity_id] as UnitState
			has_response = has_response or unit.attack_target_entity_id == enemy.entity_id
		_expect(has_response, "emergency defenders should issue the same authoritative attack effect as player units", failures)
		var scout_task: TaskState
		for task_variant in world.tasks.values():
			var task := task_variant as TaskState
			if task.kind == TaskState.Kind.SCOUT_AREA and task.lifecycle == TaskState.Lifecycle.EXECUTING:
				scout_task = task
				break
		if scout_task != null:
			var scout := world.units[scout_task.participant_entity_ids[0]] as UnitState
			var scout_formation := world.formations[scout_task.formation_id] as FormationState
			scout.position = world.logic_grid.cell_to_world(Vector2i(40, 28))
			scout_formation.anchor_position = scout.position
			scout_formation.is_moving = false
			enemy.position = scout.position + Vector2(64.0, 0.0)
			world._update_faction_knowledge()
			var redeployed := false
			for _tick in range(12):
				world.advance_tick()
				for task_variant in world.tasks.values():
					var task := task_variant as TaskState
					if task.kind == TaskState.Kind.ATTACK_TARGET and task.target_entity_id == enemy.entity_id and task.lifecycle == TaskState.Lifecycle.EXECUTING:
						redeployed = true
				if redeployed:
					break
			_expect(redeployed, "AI should leave emergency defense promptly after the base threat moves to a distant observed area", failures)


func _test_long_autonomous_run_reclaims_temporary_formations(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	for _tick in range(600):
		world.advance_tick()
	_expect(world.formations.size() <= 6, "completed autonomous task formations should be reclaimed instead of accumulating every decision cycle", failures)
	var active_participants: Dictionary = {}
	for task_variant in world.tasks.values():
		var task := task_variant as TaskState
		if task.lifecycle not in [TaskState.Lifecycle.WAITING, TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING, TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED]:
			continue
		for entity_id in task.participant_entity_ids:
			_expect(not active_participants.has(entity_id), "long autonomous run must preserve exclusive ownership per unit", failures)
			active_participants[entity_id] = task.task_id


func _test_autonomous_scout_evades_contact(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	for _tick in range(3):
		world.advance_tick()
	var scout_task: TaskState
	for task_variant in world.tasks.values():
		var candidate := task_variant as TaskState
		if candidate.kind == TaskState.Kind.SCOUT_AREA and candidate.lifecycle == TaskState.Lifecycle.EXECUTING:
			scout_task = candidate
			break
	_expect(scout_task != null, "autonomous battlefield AI should establish a reconnaissance task", failures)
	if scout_task == null:
		return
	var scout := world.units[scout_task.participant_entity_ids[0]] as UnitState
	var formation := world.formations[scout_task.formation_id] as FormationState
	scout.position = world.logic_grid.cell_to_world(Vector2i(32, 26))
	formation.anchor_position = scout.position
	formation.is_moving = false
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = scout.position + Vector2(128.0, 0.0)
	enemy.attack_target_entity_id = 0
	world._update_faction_knowledge()
	var initial_distance := scout.position.distance_to(enemy.position)
	for _tick in range(4):
		world.advance_tick()
	_expect(scout_task.phase == TaskState.Phase.EVADING, "an autonomous scout should enter evasion after detecting a nearby hostile", failures)
	_expect(scout.attack_target_entity_id == 0, "reconnaissance evasion must not turn into an attack order", failures)
	_expect(scout.position.distance_to(enemy.position) > initial_distance, "evasion should move the scout farther away from the contact", failures)


func _test_headquarters_balances_economy_and_combat(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	(world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore = 5000
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			unit.enabled = false
	world.set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	for _tick in range(360):
		world.advance_tick()
	var harvesters := world.strategic_headquarters._committed_unit_count(world, &"harvester")
	var assault := world.strategic_headquarters._committed_unit_count(world, &"assault_vehicle")
	var missiles := world.strategic_headquarters._committed_unit_count(world, &"missile_vehicle")
	_expect(harvesters <= StrategicHeadquarters.TARGET_HARVESTER_COUNT, "general staff should cap autonomous harvester commitments instead of spending indefinitely", failures)
	_expect(assault >= StrategicHeadquarters.TARGET_ASSAULT_COUNT and missiles >= StrategicHeadquarters.TARGET_MISSILE_COUNT, "battlefield autonomy should produce a combined-arms tank reserve", failures)


func _test_headquarters_preserves_emergency_reserve(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	(world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore = StrategicHeadquarters.EMERGENCY_ORE_RESERVE + 200
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	world.advance_tick()
	world.advance_tick()
	var factory := world.buildings[SimulationWorld.PLAYER_FACTORY_ID] as BuildingState
	_expect(factory.production_count() == 0, "general staff should not spend below its emergency reserve on optional combat production", failures)
	_expect(world.get_headquarters_decision_key() == &"HQ_DECISION_RESERVE", "reserve hold should be visible in the general-staff decision summary", failures)


func _test_full_takeover_arbitrates_low_resources(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	(world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore = 250
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			unit.enabled = false
	world.set_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	for _tick in range(14):
		world.advance_tick()
	var center := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var factory := world.buildings[SimulationWorld.PLAYER_FACTORY_ID] as BuildingState
	var develop_tasks := 0
	for task_variant in world.tasks.values():
		var task := task_variant as TaskState
		if task.agent_id == StrategicTaskSystem.INDUSTRIAL_AGENT_ID and task.kind == TaskState.Kind.DEVELOP_RESOURCE:
			develop_tasks += 1
	_expect(world.strategic_headquarters._committed_unit_count(world, &"harvester") == StrategicHeadquarters.TARGET_HARVESTER_COUNT, "full takeover should create exactly one coordinated harvester commitment", failures)
	_expect(center.production_count() == 1 and develop_tasks == 1, "Strategic Headquarters and the development task must not enqueue duplicate harvesters", failures)
	_expect(factory.production_count() == 0, "combat production must wait while low-resource economic recovery is unfunded", failures)
	var budget := world.get_headquarters_budget_snapshot()
	_expect(int(budget["reserved"]) == StrategicHeadquarters.EMERGENCY_ORE_RESERVE and world.get_headquarters_decision_key() == &"HQ_DECISION_RESERVE", "the visible budget ledger should explain why combat production is waiting", failures)


func _test_headquarters_reserves_player_queue_capacity(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	(world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore = 5000
	var factory := world.buildings[SimulationWorld.PLAYER_FACTORY_ID] as BuildingState
	factory.production_definition_id = &"assault_vehicle"
	factory.production_ticks_remaining = 1000
	factory.production_queue.assign([&"assault_vehicle", &"assault_vehicle", &"assault_vehicle"])
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	world.advance_tick()
	world.advance_tick()
	_expect(factory.production_count() == BuildingState.MAX_PRODUCTION_QUEUE_SIZE - StrategicHeadquarters.PLAYER_RESERVED_QUEUE_SLOTS, "autonomous production should preserve one factory queue slot for the player", failures)
	_expect(world.get_headquarters_decision_key() == &"HQ_DECISION_QUEUE_WAIT", "queue-capacity arbitration should be visible in the headquarters decision", failures)
	var player_order := ProduceUnitCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, factory.entity_id, &"missile_vehicle"
	)
	_expect(world.submit_command(player_order).is_accepted(), "the queue slot reserved by the AI should remain usable by a direct player production order", failures)


func _test_emergency_defense_can_use_reserved_ore(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	(world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore = 300
	var base := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = base.position + Vector2(96.0, 0.0)
	world._update_faction_knowledge()
	world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.AUTONOMOUS)
	world.advance_tick()
	world.advance_tick()
	var factory := world.buildings[SimulationWorld.PLAYER_FACTORY_ID] as BuildingState
	_expect(factory.production_definition_id == &"assault_vehicle", "a visible base emergency should outrank noncritical development and permit frontline production from the reserve", failures)
	_expect(world.strategic_headquarters.last_posture == StrategicHeadquarters.Posture.BASE_DEFENSE and world.get_headquarters_decision_key() == &"HQ_DECISION_EMERGENCY_DEFENSE", "emergency reserve use should publish the base-defense posture", failures)


func _test_friendly_composition_responds_to_observed_threat(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var observer := world.units[3] as UnitState
	var enemy_origin := observer.position + Vector2(64.0, 0.0)
	for entity_id in [1090, 1091]:
		var definition := SimulationWorld.UNIT_CATALOG.get_unit(&"missile_vehicle")
		var missile := UnitState.new(entity_id, enemy_origin + Vector2(0.0, float(entity_id - 1090) * 32.0), definition.move_speed, SimulationWorld.ENEMY_PLAYER_ID)
		world._apply_unit_definition(missile, definition)
		world.units[entity_id] = missile
	world._update_faction_knowledge()
	var targets := world.strategic_headquarters._combat_targets(world, false)
	_expect(int(targets[&"assault_vehicle"]) == StrategicHeadquarters.TARGET_ASSAULT_COUNT + StrategicHeadquarters.MAX_DYNAMIC_TARGET_BONUS, "observed missile-heavy opposition should increase the friendly frontline target", failures)


func _ids_overlap(first: Array[int], second: Array[int]) -> bool:
	for entity_id in first:
		if second.has(entity_id):
			return true
	return false


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

	var management_world := SimulationWorld.new()
	var formation := management_world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState
	var defend := StrategicOrderCommand.new(
		management_world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, management_world.current_tick,
		StrategicOrderCommand.OrderKind.DEFEND_AREA, formation.formation_id, 0, formation.anchor_position, 160.0
	)
	_expect(management_world.submit_command(defend).is_accepted(), "assisted mode should accept an explicit defense assignment", failures)
	management_world.advance_tick()
	var assault_definition := SimulationWorld.UNIT_CATALOG.get_unit(&"assault_vehicle")
	var reinforcement := UnitState.new(1190, formation.anchor_position + Vector2(-160.0, 0.0), assault_definition.move_speed, SimulationWorld.LOCAL_PLAYER_ID)
	management_world._apply_unit_definition(reinforcement, assault_definition)
	management_world.units[reinforcement.entity_id] = reinforcement
	management_world.advance_tick()
	_expect(not (management_world.tasks[1] as TaskState).has_participant(reinforcement.entity_id), "assisted mode should not expand an assignment beyond the player's explicit participants", failures)
	management_world.set_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID, AgentPolicy.Authorization.DELEGATED)
	management_world.advance_tick()
	_expect((management_world.tasks[1] as TaskState).has_participant(reinforcement.entity_id), "delegated mode should automatically enroll a compatible reinforcement", failures)
	_expect(management_world.get_agent_recommendation_key(StrategicTaskSystem.BATTLEFIELD_AGENT_ID) == &"AI_RECOMMENDATION_ACTIVE", "friendly AI should publish a testable recommendation/status key", failures)


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
	var expert_world := SimulationWorld.new()
	expert_world.set_enemy_difficulty(EnemyDifficultyProfile.Difficulty.EXPERT)
	_expect(easy_world.enemy_raid_agent.difficulty_profile.target_score_noise > hard_world.enemy_raid_agent.difficulty_profile.target_score_noise, "easy difficulty should use more target-selection noise than hard", failures)
	_expect(easy_world.enemy_raid_agent.difficulty_profile.tactical_decision_interval_ticks > hard_world.enemy_raid_agent.difficulty_profile.tactical_decision_interval_ticks, "hard difficulty should make tactical decisions more frequently", failures)
	_expect(easy_world.enemy_raid_agent.difficulty_profile.opening_delay_ticks > hard_world.enemy_raid_agent.difficulty_profile.opening_delay_ticks and hard_world.enemy_raid_agent.difficulty_profile.opening_delay_ticks > expert_world.enemy_raid_agent.difficulty_profile.opening_delay_ticks, "difficulty should shorten the opening before applying pressure", failures)
	_expect(easy_world.enemy_raid_agent.difficulty_profile.raid_force_size < expert_world.enemy_raid_agent.difficulty_profile.raid_force_size, "higher difficulty should assemble larger raids", failures)
	_expect(easy_world.enemy_raid_agent.difficulty_profile.combat_reserve_size < expert_world.enemy_raid_agent.difficulty_profile.combat_reserve_size, "higher difficulty should maintain a larger combat reserve", failures)
	_expect(easy_world.enemy_raid_agent.difficulty_profile.target_harvester_count < expert_world.enemy_raid_agent.difficulty_profile.target_harvester_count, "expert AI should sustain a stronger economy than easy AI", failures)
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


func _test_enemy_production_commitments(failures: Array[String]) -> void:
	var economy_world := SimulationWorld.new()
	(economy_world.factions[SimulationWorld.ENEMY_PLAYER_ID] as FactionState).ore = 5000
	economy_world.current_tick = economy_world.enemy_raid_agent.difficulty_profile.opening_delay_ticks
	for _tick in range(8):
		economy_world.advance_tick()
	var enemy_center := economy_world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState
	_expect(enemy_center.production_count() == 1 and enemy_center.production_definition_id == &"harvester", "enemy economy should count committed harvesters instead of filling the command-center queue", failures)

	var combat_world := SimulationWorld.new()
	(combat_world.factions[SimulationWorld.ENEMY_PLAYER_ID] as FactionState).ore = 5000
	combat_world._add_building(2190, &"automated_factory", SimulationWorld.ENEMY_PLAYER_ID, combat_world.logic_grid.cell_to_world(Vector2i(76, 54)))
	combat_world.current_tick = combat_world.enemy_raid_agent.difficulty_profile.opening_delay_ticks
	combat_world.enemy_raid_agent.phase = EnemyRaidAgent.Phase.MUSTERING
	combat_world.enemy_raid_agent.phase_started_tick = combat_world.current_tick
	for _tick in range(10):
		combat_world.advance_tick()
	var committed_combat := combat_world.enemy_raid_agent._combat_units(combat_world).size()
	for definition_id in EnemyRaidAgent.COMBAT_DEFINITION_IDS:
		committed_combat += combat_world.enemy_raid_agent._queued_definition_count(definition_id, combat_world)
	_expect(committed_combat == combat_world.enemy_raid_agent.difficulty_profile.combat_reserve_size, "enemy AI should reserve exactly its configured combat force across completed and queued units", failures)


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
