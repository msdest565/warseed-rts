class_name CombatSystem
extends RefCounted


func advance(
	units: Dictionary,
	projectiles: Dictionary,
	next_projectile_id: int,
	events: Array[SimulationEvent],
	current_tick: int
) -> int:
	var entity_ids := units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := units[entity_id] as UnitState
		if unit.enabled and unit.attack_cooldown_remaining_ticks > 0:
			unit.attack_cooldown_remaining_ticks -= 1

	var projectile_id := next_projectile_id
	for entity_id in entity_ids:
		var attacker := units[entity_id] as UnitState
		if not attacker.enabled or attacker.attack_target_entity_id == 0:
			continue
		if attacker.attack_damage <= 0.0 or attacker.attack_range <= 0.0:
			continue
		if not units.has(attacker.attack_target_entity_id):
			_clear_invalid_target(attacker, events, current_tick, "missing")
			continue
		var target := units[attacker.attack_target_entity_id] as UnitState
		if not target.enabled or target.faction_id == attacker.faction_id:
			_clear_invalid_target(attacker, events, current_tick, "invalid")
			continue
		if attacker.attack_cooldown_remaining_ticks > 0:
			continue
		if attacker.position.distance_squared_to(target.position) > attacker.attack_range * attacker.attack_range:
			continue
		var projectile := ProjectileState.new(
			projectile_id,
			attacker.entity_id,
			target.entity_id,
			attacker.faction_id,
			attacker.position,
			attacker.projectile_speed,
			attacker.attack_damage,
			current_tick
		)
		projectiles[projectile_id] = projectile
		projectile_id += 1
		attacker.attack_cooldown_remaining_ticks = attacker.attack_cooldown_ticks
		events.append(SimulationEvent.new(
			current_tick,
			SimulationEvent.Kind.PROJECTILE_FIRED,
			attacker.entity_id,
			"projectile=%d;target=%d" % [projectile.projectile_id, target.entity_id]
		))

	var impacted: Array[Dictionary] = []
	var projectile_ids := projectiles.keys()
	projectile_ids.sort()
	for id in projectile_ids:
		var projectile := projectiles[id] as ProjectileState
		if projectile.spawn_tick >= current_tick:
			continue
		if not units.has(projectile.target_entity_id) or not (units[projectile.target_entity_id] as UnitState).enabled:
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.PROJECTILE_EXPIRED, projectile.source_entity_id, "projectile=%d" % projectile.projectile_id))
			projectiles.erase(id)
			continue
		var target := units[projectile.target_entity_id] as UnitState
		var offset := target.position - projectile.position
		var travel := projectile.speed * SimulationWorld.TICK_SECONDS
		if offset.length() <= travel:
			projectile.position = target.position
			impacted.append({"projectile_id": projectile.projectile_id, "source_id": projectile.source_entity_id, "target_id": target.entity_id, "attack_power": projectile.attack_power})
		else:
			projectile.position += offset.normalized() * travel

	for impact in impacted:
		var impact_id := int(impact["projectile_id"])
		if not projectiles.has(impact_id):
			continue
		var target := units[int(impact["target_id"])] as UnitState
		if not target.enabled:
			projectiles.erase(impact_id)
			continue
		var health_before := target.health
		var amount := maxf(1.0, float(impact["attack_power"]) - target.armor)
		target.health = maxf(0.0, target.health - amount)
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.PROJECTILE_IMPACTED, int(impact["target_id"]), "projectile=%d" % impact_id))
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.DAMAGE_APPLIED, int(impact["source_id"]), "target=%d;amount=%.3f;remaining=%.3f" % [target.entity_id, amount, target.health]))
		projectiles.erase(impact_id)
		if health_before > 0.0 and is_zero_approx(target.health):
			_disable_destroyed_unit(target)
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.UNIT_DESTROYED, target.entity_id))
			for entity_id in entity_ids:
				var attacker := units[entity_id] as UnitState
				if attacker.attack_target_entity_id == target.entity_id:
					_clear_invalid_target(attacker, events, current_tick, "destroyed")
	return projectile_id


func _clear_invalid_target(unit: UnitState, events: Array[SimulationEvent], current_tick: int, reason: String) -> void:
	var target_id := unit.attack_target_entity_id
	if target_id == 0:
		return
	unit.attack_target_entity_id = 0
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.TARGET_LOST, unit.entity_id, "target=%d;reason=%s" % [target_id, reason]))


func _disable_destroyed_unit(unit: UnitState) -> void:
	unit.health = 0.0
	unit.enabled = false
	unit.has_move_target = false
	unit.path = PackedVector2Array()
	unit.path_index = 0
	unit.move_target = unit.position
	unit.desired_position = unit.position
	unit.following_formation = false
	unit.is_recovering = false
	unit.recovery_path = PackedVector2Array()
	unit.recovery_path_index = 0
	unit.is_attack_moving = false
	unit.attack_target_entity_id = 0
