class_name TestFactionKnowledge
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_faction_snapshot_filters_true_state(failures)
	_test_last_seen_contact_and_snapshot_copy(failures)
	_test_hidden_attack_target_is_rejected(failures)
	_test_enemy_raid_uses_last_seen_position(failures)
	_test_enemy_harvester_mines_and_defends_itself(failures)
	_test_enemy_combat_parity_and_tactical_reactions(failures)
	_test_enemy_strategy_phase_machine(failures)
	_test_enemy_replaces_economy_losses(failures)
	return failures


func _test_faction_snapshot_filters_true_state(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var public_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var true_snapshot := world.create_true_state_snapshot()
	_expect(public_snapshot.observer_faction_id == SimulationWorld.LOCAL_PLAYER_ID, "faction snapshot should identify its observer", failures)
	_expect(not public_snapshot.is_true_state, "faction snapshot must not be marked as true state", failures)
	_expect(true_snapshot.is_true_state, "diagnostic snapshot should be marked as true state", failures)
	_expect(true_snapshot.get_building(SimulationWorld.ENEMY_COMMAND_CENTER_ID) != null, "true state should include hidden enemy building", failures)
	_expect(public_snapshot.get_building(SimulationWorld.ENEMY_COMMAND_CENTER_ID) == null, "unexplored enemy building must be absent from faction snapshot", failures)
	_expect(public_snapshot.get_faction(SimulationWorld.ENEMY_PLAYER_ID).ore == 0, "enemy private economy must be redacted", failures)


func _test_last_seen_contact_and_snapshot_copy(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = (world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState).anchor_position + Vector2(128.0, 0.0)
	world._update_faction_knowledge()
	var visible_snapshot := world.create_snapshot()
	var visible_contact := visible_snapshot.get_unit(enemy.entity_id)
	_expect(visible_contact != null and visible_contact.is_visible_to_local_player, "visible hostile should enter faction snapshot", failures)
	var last_seen_position := visible_contact.position
	var old_knowledge_cell := world.logic_grid.world_to_cell(last_seen_position)
	var old_knowledge_state := visible_snapshot.knowledge.get_cell_state(old_knowledge_cell)

	enemy.position = world.logic_grid.cell_to_world(Vector2i(70, 50))
	world.advance_tick()
	var hidden_snapshot := world.create_snapshot()
	var stale_contact := hidden_snapshot.get_unit(enemy.entity_id)
	_expect(stale_contact != null, "previously observed hostile should remain as last-seen contact", failures)
	_expect(not stale_contact.is_visible_to_local_player, "last-seen contact must not masquerade as current visibility", failures)
	_expect(stale_contact.enabled and stale_contact.death_tick < 0, "losing the observer must not mark a surviving hostile contact as destroyed", failures)
	_expect(stale_contact.position == last_seen_position, "hidden hostile contact must retain last known position", failures)
	_expect(stale_contact.last_seen_tick < hidden_snapshot.tick, "hidden contact should expose an older last-seen tick", failures)
	_expect(visible_snapshot.knowledge.get_cell_state(old_knowledge_cell) == old_knowledge_state, "old knowledge snapshot must remain immutable", failures)


func _test_hidden_attack_target_is_rejected(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = world.logic_grid.cell_to_world(Vector2i(70, 50))
	world.advance_tick()
	var attack := AttackCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		1,
		enemy.entity_id,
		SimulationWorld.DEFAULT_FORMATION_ID
	)
	_expect(world.submit_command(attack).reason == CommandValidationResult.Reason.HIDDEN_TARGET, "commands must not target hidden true-state entities", failures)


func _test_enemy_raid_uses_last_seen_position(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var raider := world.spawn_enemy_raid_unit(EnemyRaidAgent.RAID_UNIT_ID, EnemyRaidAgent.AGENT_ID, EnemyRaidAgent.TASK_ID)
	world.spawn_enemy_raid_unit(EnemyRaidAgent.RAID_UNIT_ID - 1, EnemyRaidAgent.AGENT_ID, EnemyRaidAgent.TASK_ID)
	world.enemy_raid_agent.spawned = true
	world.enemy_raid_agent.phase = EnemyRaidAgent.Phase.RAIDING
	world.current_tick = EnemyRaidAgent.STRATEGY_START_TICK
	world.enemy_raid_agent.phase_started_tick = world.current_tick
	raider.position = (world.units[1] as UnitState).position + Vector2(48.0, 0.0)
	world._update_faction_knowledge()
	world.enemy_raid_agent.last_order_tick = -world.enemy_raid_agent.difficulty_profile.tactical_decision_interval_ticks
	world.enemy_raid_agent.advance(world)
	world.advance_tick()
	_expect(raider.attack_target_entity_id != 0, "enemy raid should attack a currently visible target", failures)
	var attacked_id := raider.attack_target_entity_id
	var health_before := (world.units[attacked_id] as UnitState).health
	for _tick in range(4):
		world.advance_tick()
	_expect((world.units[attacked_id] as UnitState).health < health_before, "enemy raid projectiles should apply real damage", failures)
	var old_positions: Dictionary = {}
	for entity_id in range(1, 6):
		var friendly := world.units[entity_id] as UnitState
		old_positions[entity_id] = friendly.position
		friendly.position = world.logic_grid.cell_to_world(Vector2i(40 + entity_id, 50))
	var enemy_base := (world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState).rally_position
	raider.position = enemy_base
	(world.units[EnemyRaidAgent.RAID_UNIT_ID - 1] as UnitState).position = enemy_base + Vector2(-32.0, 0.0)
	world._update_faction_knowledge()
	raider.attack_target_entity_id = 0
	raider.has_move_target = false
	raider.path = PackedVector2Array()
	world.enemy_raid_agent.last_order_tick = world.current_tick - world.enemy_raid_agent.difficulty_profile.tactical_decision_interval_ticks
	world.enemy_raid_agent.last_unit_order_tick[raider.entity_id] = world.current_tick - world.enemy_raid_agent.difficulty_profile.tactical_decision_interval_ticks
	world.enemy_raid_agent.advance(world)
	world.advance_tick()
	_expect(old_positions.values().has(raider.move_target), "enemy raid should investigate a recorded last-seen contact", failures)
	var tracks_hidden_truth := false
	for entity_id in range(1, 6):
		if raider.move_target.is_equal_approx((world.units[entity_id] as UnitState).position):
			tracks_hidden_truth = true
	_expect(not tracks_hidden_truth, "enemy raid must not track any hidden unit's true position", failures)


func _test_enemy_strategy_phase_machine(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var reached_raid := false
	for _tick in range(1500):
		world.advance_tick()
		if world.enemy_raid_agent.phase == EnemyRaidAgent.Phase.RAIDING:
			reached_raid = true
			break
	var history := world.enemy_raid_agent.phase_history
	for expected_phase in [
		EnemyRaidAgent.Phase.ECONOMY,
		EnemyRaidAgent.Phase.EXPANSION,
		EnemyRaidAgent.Phase.SCOUTING,
		EnemyRaidAgent.Phase.CONTESTING,
		EnemyRaidAgent.Phase.MUSTERING,
		EnemyRaidAgent.Phase.RAIDING,
	]:
		_expect(history.has(expected_phase), "enemy strategy should reach phase %s through authoritative play" % EnemyRaidAgent.Phase.keys()[expected_phase], failures)
	_expect(reached_raid, "enemy strategy should build a raid force within deterministic slice timing", failures)
	var enemy_factory: BuildingState
	var enemy_support: BuildingState
	for building_variant in world.buildings.values():
		var building := building_variant as BuildingState
		if building.faction_id == SimulationWorld.ENEMY_PLAYER_ID and building.definition_id == &"automated_factory":
			enemy_factory = building
		elif building.faction_id == SimulationWorld.ENEMY_PLAYER_ID and building.definition_id == &"forward_support_station":
			enemy_support = building
	_expect(enemy_factory != null and enemy_factory.operational, "enemy expansion should construct an operational factory", failures)
	_expect(enemy_support != null and enemy_support.operational, "enemy expansion should construct an operational support station through shared building rules", failures)
	_expect((world.units[SimulationWorld.ENEMY_HARVESTER_ID] as UnitState).harvest_ore_field_entity_id == SimulationWorld.ENEMY_ORE_FIELD_ID, "enemy economy should use its own real harvester round trip", failures)
	_expect((world.ore_fields[SimulationWorld.ENEMY_ORE_FIELD_ID] as OreFieldState).ore_remaining < SimulationWorld.PRIMARY_ORE_CAPACITY, "enemy economy should extract from the enemy-side ore field", failures)
	_expect((world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState).ore_remaining == SimulationWorld.PRIMARY_ORE_CAPACITY, "enemy harvester must not consume the player-side ore field", failures)
	world.enemy_raid_agent.phase_started_tick = world.current_tick - EnemyRaidAgent.RAID_DURATION_TICKS
	world.advance_tick()
	_expect(world.enemy_raid_agent.phase == EnemyRaidAgent.Phase.RETREATING, "expired raid should transition to retreat", failures)
	var base_position := (world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState).rally_position
	for unit in world.enemy_raid_agent._combat_units(world):
		unit.position = base_position
		unit.has_move_target = false
	world.advance_tick()
	_expect(world.enemy_raid_agent.phase == EnemyRaidAgent.Phase.DEFENDING, "returned raid force should transition to base defense", failures)


func _test_enemy_harvester_mines_and_defends_itself(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	world.current_tick = EnemyRaidAgent.STRATEGY_START_TICK
	var harvester := world.units[SimulationWorld.ENEMY_HARVESTER_ID] as UnitState
	var local_scout := world.units[3] as UnitState
	local_scout.position = harvester.position + Vector2(-48.0, 0.0)
	local_scout.following_formation = false
	world._update_faction_knowledge()
	var attack := AttackCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, local_scout.entity_id, harvester.entity_id)
	_expect(world.submit_command(attack).is_accepted(), "enemy harvester self-defense fixture should begin with a legal player attack", failures)
	var health_before := local_scout.health
	world.enemy_raid_agent.advance(world)
	for _tick in range(6):
		world.advance_tick()
	_expect(harvester.can_attack, "enemy harvester should have a defensive weapon", failures)
	_expect(harvester.harvest_ore_field_entity_id == SimulationWorld.ENEMY_ORE_FIELD_ID, "enemy harvester should keep its own ore assignment while defending", failures)
	_expect(local_scout.health < health_before and harvester.attack_is_retaliation, "enemy harvester should apply real projectile damage only while retaliating", failures)
	_expect(not world.enemy_raid_agent._combat_units(world).has(harvester), "enemy harvester should not abandon mining to join raid forces", failures)
	_expect(not harvester.can_accept_attack_orders and not (world.units[1] as UnitState).can_accept_attack_orders, "both factions should share defensive-only harvester responsibilities", failures)


func _test_enemy_replaces_economy_losses(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	world._add_building(2190, &"automated_factory", SimulationWorld.ENEMY_PLAYER_ID, world.logic_grid.cell_to_world(Vector2i(76, 54)))
	var lost_harvester := world.units[SimulationWorld.ENEMY_HARVESTER_ID] as UnitState
	lost_harvester.enabled = false
	lost_harvester.health = 0.0
	lost_harvester.death_tick = world.current_tick
	(world.factions[SimulationWorld.ENEMY_PLAYER_ID] as FactionState).ore = 1000
	world.current_tick = EnemyRaidAgent.STRATEGY_START_TICK
	world.enemy_raid_agent.phase = EnemyRaidAgent.Phase.MUSTERING
	world.enemy_raid_agent.phase_started_tick = world.current_tick
	for _tick in range(40):
		world.advance_tick()
	var replacement: UnitState
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.entity_id != SimulationWorld.ENEMY_HARVESTER_ID and unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID and unit.can_harvest:
			replacement = unit
			break
	_expect(replacement != null, "enemy economy should replace a destroyed harvester through normal paid production", failures)
	if replacement != null:
		_expect(replacement.harvest_ore_field_entity_id == SimulationWorld.ENEMY_ORE_FIELD_ID, "replacement harvester should automatically claim the enemy ore route", failures)


func _test_enemy_combat_parity_and_tactical_reactions(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(&"scout_vehicle")
	var enemy_scout := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	_expect(enemy_scout.can_attack and enemy_scout.move_speed == definition.move_speed and enemy_scout.attack_damage == definition.combat.attack_power and enemy_scout.max_health == definition.combat.max_health, "enemy scout should use the same unit definition and combat rules as the player scout", failures)
	var enemy_base := (world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState).rally_position
	var intruder := world.units[4] as UnitState
	intruder.position = enemy_base + Vector2(-64.0, 0.0)
	intruder.following_formation = false
	world.current_tick = EnemyRaidAgent.STRATEGY_START_TICK
	world.enemy_raid_agent.phase = EnemyRaidAgent.Phase.RAIDING
	world.enemy_raid_agent.phase_started_tick = world.current_tick
	world._update_faction_knowledge()
	for _tick in range(world.enemy_raid_agent.difficulty_profile.reaction_delay_ticks + 2):
		world.advance_tick()
	_expect(world.enemy_raid_agent.phase == EnemyRaidAgent.Phase.DEFENDING, "visible threats near the enemy base should trigger defense within the configured reaction window", failures)
	world.advance_tick()
	_expect(enemy_scout.attack_target_entity_id == intruder.entity_id, "enemy defenders should attack through the same authoritative attack command", failures)

	var retreat_world := SimulationWorld.new()
	retreat_world.current_tick = EnemyRaidAgent.STRATEGY_START_TICK
	retreat_world.enemy_raid_agent.phase = EnemyRaidAgent.Phase.RAIDING
	retreat_world.enemy_raid_agent.phase_started_tick = retreat_world.current_tick
	for unit in retreat_world.enemy_raid_agent._combat_units(retreat_world):
		unit.health = unit.max_health * 0.2
	retreat_world.enemy_raid_agent.advance(retreat_world)
	_expect(retreat_world.enemy_raid_agent.phase == EnemyRaidAgent.Phase.RETREATING, "badly damaged enemy forces should withdraw before the fixed raid timeout", failures)
	_expect(retreat_world.enemy_raid_agent._next_combat_definition(retreat_world) == &"assault_vehicle", "enemy production should fill missing combat roles instead of repeating one unit type", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
