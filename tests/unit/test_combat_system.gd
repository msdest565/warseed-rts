class_name TestCombatSystem
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_projectile_delays_and_applies_armored_damage(failures)
	_test_projectile_snapshot_is_immutable(failures)
	_test_simultaneous_projectiles_are_deterministic(failures)
	_test_distant_target_is_pursued_and_repathed(failures)
	_test_formation_attack_responds_on_first_authoritative_tick(failures)
	_test_defensive_weapon_requires_real_aggressor(failures)
	_test_harvester_self_defense_does_not_enable_attack_orders(failures)
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


func _test_distant_target_is_pursued_and_repathed(failures: Array[String]) -> void:
	var world := SimulationWorld.new(false)
	var attacker := UnitState.new(1, Vector2(320.0, 360.0), 180.0, 1)
	attacker.attack_range = 160.0
	attacker.attack_damage = 20.0
	attacker.sight_range = 1200.0
	var target := UnitState.new(2, Vector2(960.0, 360.0), 90.0, 2)
	target.can_attack = false
	world.units[1] = attacker
	world.units[2] = target
	var attack := AttackCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 2)
	_expect(world.submit_command(attack).is_accepted(), "visible distant target should accept an explicit attack order", failures)
	world.advance_tick()
	var first_position := attacker.position
	var first_pursuit_cell := attacker.pursuit_target_cell
	_expect(attacker.has_move_target and first_position.x > 320.0, "standalone attacker should pursue a target outside weapon range", failures)
	var target_move := MoveCommand.new(2, 2, GameCommand.IssuerKind.PLAYER, world.current_tick, 2, Vector2(1120.0, 328.0))
	_expect(world.submit_command(target_move).is_accepted(), "moving target fixture should accept relocation", failures)
	for _tick in range(6):
		world.advance_tick()
	_expect(attacker.pursuit_target_cell != first_pursuit_cell, "pursuit should repath when the target changes logic cells", failures)
	var health_before := target.health
	for _tick in range(80):
		world.advance_tick()
		if target.health < health_before:
			break
	_expect(target.health < health_before, "pursuer should enter range and deal authoritative projectile damage", failures)
	_expect(attacker.position.distance_to(target.position) <= attacker.attack_range + attacker.move_speed * SimulationWorld.TICK_SECONDS, "pursuer should stop at weapon range instead of requiring overlap", failures)


func _test_formation_attack_responds_on_first_authoritative_tick(failures: Array[String]) -> void:
	var world := SimulationWorld.new(false)
	var long_range := UnitState.new(1, Vector2(320.0, 360.0), 160.0, 1)
	long_range.attack_range = 720.0
	long_range.attack_damage = 20.0
	long_range.sight_range = 1200.0
	var short_range := UnitState.new(2, Vector2(272.0, 316.0), 160.0, 1)
	short_range.attack_range = 128.0
	short_range.attack_damage = 20.0
	short_range.sight_range = 1200.0
	var target := UnitState.new(3, Vector2(880.0, 360.0), 0.0, 2)
	target.can_attack = false
	world.units[1] = long_range
	world.units[2] = short_range
	world.units[3] = target
	var formation := FormationState.new(1, [1, 2], long_range.position)
	world.formations[formation.formation_id] = formation
	for unit in [long_range, short_range]:
		unit.formation_id = formation.formation_id
		unit.formation_slot_id = formation.get_slot_id(unit.entity_id)
		unit.following_formation = true
	var attack := AttackCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, formation.leader_entity_id, target.entity_id, formation.formation_id)
	_expect(world.submit_command(attack).is_accepted(), "mixed-range formation attack should validate", failures)
	world.advance_tick()
	_expect(long_range.attack_target_entity_id == target.entity_id and short_range.attack_target_entity_id == target.entity_id, "every formation member should receive the target on the first authoritative tick", failures)
	_expect(formation.is_moving and short_range.position.distance_to(target.position) < Vector2(272.0, 316.0).distance_to(target.position), "short-range members should begin pursuing immediately", failures)
	_expect(not world.projectiles.is_empty(), "a long-range member already in range should fire without waiting for the frontline", failures)


func _test_harvester_self_defense_does_not_enable_attack_orders(failures: Array[String]) -> void:
	var world := SimulationWorld.new(false)
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(&"harvester")
	var harvester := UnitState.new(1, Vector2(320.0, 360.0), definition.move_speed, 1)
	world._apply_unit_definition(harvester, definition)
	harvester.harvest_ore_field_entity_id = 99
	harvester.harvest_refinery_entity_id = 10
	harvester.harvest_phase = UnitState.HarvestPhase.LOADING
	harvester.harvest_ticks_remaining = 100
	var attacker := UnitState.new(2, Vector2(368.0, 360.0), 0.0, 2)
	world.factions[1] = FactionState.new(1, 1, 0)
	world.ore_fields[99] = OreFieldState.new(99, harvester.position, 1000)
	world.buildings[10] = BuildingState.new(10, &"command_center", 1, 1, harvester.position - Vector2(64.0, 0.0), 1000.0)
	world.units[1] = harvester
	world.units[2] = attacker
	var explicit_attack := AttackCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 2)
	_expect(world.submit_command(explicit_attack).reason == CommandValidationResult.Reason.INVALID_DEFINITION, "harvester should reject active attack orders", failures)
	var health_before := attacker.health
	world.advance_tick()
	_expect(harvester.attack_target_entity_id == 0, "nearby enemies that are not attacking the harvester must not trigger self-defense", failures)
	_expect(is_equal_approx(attacker.health, health_before), "passive nearby enemies must not take harvester damage", failures)
	attacker.attack_target_entity_id = harvester.entity_id
	for _tick in range(6):
		world.advance_tick()
	_expect(harvester.attack_target_entity_id == attacker.entity_id and harvester.attack_is_retaliation, "working harvester should retaliate only against an active aggressor", failures)
	_expect(attacker.health < health_before, "harvester retaliation should use the shared projectile and damage systems", failures)
	_expect(harvester.harvest_ore_field_entity_id == 99, "self-defense should preserve the harvester work assignment", failures)


func _test_defensive_weapon_requires_real_aggressor(failures: Array[String]) -> void:
	var harvester := UnitState.new(1, Vector2(100.0, 100.0), 0.0, 1)
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(&"harvester")
	var world := SimulationWorld.new(false)
	world._apply_unit_definition(harvester, definition)
	var passive_enemy := UnitState.new(2, Vector2(120.0, 100.0), 0.0, 2)
	var units := {1: harvester, 2: passive_enemy}
	var buildings: Dictionary = {}
	var projectiles: Dictionary = {}
	var combat_events: Array[SimulationEvent] = []
	harvester.attack_target_entity_id = passive_enemy.entity_id
	harvester.attack_is_retaliation = false
	CombatSystem.new().advance(units, buildings, projectiles, 1, combat_events, 1)
	_expect(projectiles.is_empty() and harvester.attack_target_entity_id == 0, "combat system must clear an injected active target from a defensive-only unit", failures)
	harvester.attack_target_entity_id = passive_enemy.entity_id
	harvester.attack_is_retaliation = true
	CombatSystem.new().advance(units, buildings, projectiles, 1, combat_events, 2)
	_expect(projectiles.is_empty() and harvester.attack_target_entity_id == 0, "a retaliation flag alone must not permit firing at a passive enemy", failures)
	passive_enemy.attack_target_entity_id = harvester.entity_id
	harvester.attack_target_entity_id = passive_enemy.entity_id
	harvester.attack_is_retaliation = true
	CombatSystem.new().advance(units, buildings, projectiles, 1, combat_events, 3)
	var harvester_fired := false
	for projectile_variant in projectiles.values():
		var projectile := projectile_variant as ProjectileState
		harvester_fired = harvester_fired or projectile.source_entity_id == harvester.entity_id
	_expect(harvester_fired, "a defensive weapon should fire once the target is an actual aggressor", failures)


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
