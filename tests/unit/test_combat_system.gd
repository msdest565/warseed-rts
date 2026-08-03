class_name TestCombatSystem
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_projectile_delays_and_applies_armored_damage(failures)
	_test_projectile_snapshot_is_immutable(failures)
	_test_simultaneous_projectiles_are_deterministic(failures)
	return failures


func _test_projectile_delays_and_applies_armored_damage(failures: Array[String]) -> void:
	var world := SimulationWorld.new(false)
	var attacker := UnitState.new(1, Vector2(100.0, 100.0), 0.0, 1)
	attacker.attack_damage = 20.0
	attacker.attack_range = 200.0
	attacker.projectile_speed = 100.0
	var target := UnitState.new(2, Vector2(120.0, 100.0), 0.0, 2)
	target.armor = 5.0
	world.units[1] = attacker
	world.units[2] = target
	world.submit_command(AttackCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 2))
	world.advance_tick()
	_expect(world.projectiles.size() == 1, "firing tick should create authoritative projectile", failures)
	_expect(is_equal_approx(target.health, 100.0), "firing tick should not deal hitscan damage", failures)
	world.advance_tick()
	_expect(world.projectiles.size() == 1 and is_equal_approx(target.health, 100.0), "projectile should travel before impact", failures)
	world.advance_tick()
	_expect(world.projectiles.is_empty(), "projectile should be removed after impact", failures)
	_expect(is_equal_approx(target.health, 85.0), "impact should apply attack power minus armor", failures)


func _test_projectile_snapshot_is_immutable(failures: Array[String]) -> void:
	var world := SimulationWorld.new(false)
	var attacker := UnitState.new(1, Vector2(100.0, 100.0), 0.0, 1)
	attacker.projectile_speed = 100.0
	var target := UnitState.new(2, Vector2(150.0, 100.0), 0.0, 2)
	world.units[1] = attacker
	world.units[2] = target
	world.submit_command(AttackCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 2))
	var fired := world.advance_tick()
	var old_position := fired.projectiles[0].position
	world.advance_tick()
	_expect(fired.projectiles[0].position == old_position, "old projectile snapshot must remain immutable", failures)
	_expect(world.create_snapshot().projectiles[0].position != old_position, "live projectile should advance on later tick", failures)


func _test_simultaneous_projectiles_are_deterministic(failures: Array[String]) -> void:
	var first := _create_duel_world()
	var second := _create_duel_world()
	for world in [first, second]:
		world.submit_command(AttackCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 2))
		world.submit_command(AttackCommand.new(2, 2, GameCommand.IssuerKind.PLAYER, 0, 2, 1))
		for _tick in range(3):
			world.advance_tick()
	_expect(not (first.units[1] as UnitState).enabled and not (first.units[2] as UnitState).enabled, "simultaneous lethal projectiles should destroy both units", failures)
	_expect(_combat_summary(first) == _combat_summary(second), "same projectile inputs should produce deterministic state and events", failures)


func _create_duel_world() -> SimulationWorld:
	var world := SimulationWorld.new(false)
	var first := UnitState.new(1, Vector2(100.0, 100.0), 0.0, 1)
	var second := UnitState.new(2, Vector2(120.0, 100.0), 0.0, 2)
	for unit in [first, second]:
		unit.health = 20.0
		unit.max_health = 20.0
		unit.attack_damage = 20.0
		unit.projectile_speed = 100.0
	world.units[1] = first
	world.units[2] = second
	return world


func _combat_summary(world: SimulationWorld) -> Array[String]:
	var summary: Array[String] = []
	for entity_id in [1, 2]:
		var unit := world.units[entity_id] as UnitState
		summary.append("%d:%s:%.1f:%d" % [entity_id, unit.enabled, unit.health, unit.attack_target_entity_id])
	for event in world.events:
		if event.kind >= SimulationEvent.Kind.ATTACK_STARTED:
			summary.append("E:%d:%d:%d:%s" % [event.tick, event.kind, event.entity_id, event.detail])
	return summary


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
