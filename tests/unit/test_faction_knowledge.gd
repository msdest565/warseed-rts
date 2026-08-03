class_name TestFactionKnowledge
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_faction_snapshot_filters_true_state(failures)
	_test_last_seen_contact_and_snapshot_copy(failures)
	_test_hidden_attack_target_is_rejected(failures)
	_test_enemy_raid_uses_last_seen_position(failures)
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
	world.enemy_raid_agent.spawned = true
	raider.position = (world.units[1] as UnitState).position + Vector2(48.0, 0.0)
	world._update_faction_knowledge()
	world.enemy_raid_agent.last_order_tick = -EnemyRaidAgent.ORDER_INTERVAL_TICKS
	world.enemy_raid_agent.advance(world)
	world.advance_tick()
	_expect(raider.attack_target_entity_id != 0, "enemy raid should attack a currently visible target", failures)
	var old_positions: Dictionary = {}
	for entity_id in range(1, 6):
		var friendly := world.units[entity_id] as UnitState
		old_positions[entity_id] = friendly.position
		friendly.position = world.logic_grid.cell_to_world(Vector2i(40 + entity_id, 50))
	world._update_faction_knowledge()
	world.enemy_raid_agent.last_order_tick = world.current_tick - EnemyRaidAgent.ORDER_INTERVAL_TICKS
	world.advance_tick()
	world.advance_tick()
	var expected_last_seen := old_positions[1] as Vector2
	_expect(raider.move_target.is_equal_approx(expected_last_seen), "enemy raid should investigate the newest deterministic last-seen contact", failures)
	_expect(not raider.move_target.is_equal_approx((world.units[1] as UnitState).position), "enemy raid must not track the hidden unit's true position", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
