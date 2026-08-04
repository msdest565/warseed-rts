class_name CombatSystem
extends RefCounted


func advance(
	units: Dictionary,
	buildings: Dictionary,
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
		if not attacker.enabled or not attacker.can_attack or attacker.attack_target_entity_id == 0:
			continue
		if attacker.attack_damage <= 0.0 or attacker.attack_range <= 0.0:
			continue
		var target_id := attacker.attack_target_entity_id
		if not _entity_exists(target_id, units, buildings):
			_clear_invalid_target(attacker, events, current_tick, "missing")
			continue
		if not _entity_enabled(target_id, units, buildings) or _entity_faction(target_id, units, buildings) == attacker.faction_id:
			_clear_invalid_target(attacker, events, current_tick, "invalid")
			continue
		if attacker.attack_cooldown_remaining_ticks > 0:
			continue
		var target_position := _entity_position(target_id, units, buildings)
		if attacker.position.distance_squared_to(target_position) > attacker.attack_range * attacker.attack_range:
			continue
		var projectile := ProjectileState.new(
			projectile_id,
			attacker.entity_id,
			target_id,
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
			"projectile=%d;target=%d" % [projectile.projectile_id, target_id]
		))

	var impacted: Array[Dictionary] = []
	var projectile_ids := projectiles.keys()
	projectile_ids.sort()
	for id in projectile_ids:
		var projectile := projectiles[id] as ProjectileState
		if projectile.spawn_tick >= current_tick:
			continue
		if not _entity_exists(projectile.target_entity_id, units, buildings) or not _entity_enabled(projectile.target_entity_id, units, buildings):
			events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.PROJECTILE_EXPIRED, projectile.source_entity_id, "projectile=%d" % projectile.projectile_id))
			projectiles.erase(id)
			continue
		var target_position := _entity_position(projectile.target_entity_id, units, buildings)
		var offset := target_position - projectile.position
		var travel := projectile.speed * SimulationWorld.TICK_SECONDS
		if offset.length() <= travel:
			projectile.position = target_position
			impacted.append({"projectile_id": projectile.projectile_id, "source_id": projectile.source_entity_id, "target_id": projectile.target_entity_id, "attack_power": projectile.attack_power})
		else:
			projectile.position += offset.normalized() * travel

	for impact in impacted:
		var impact_id := int(impact["projectile_id"])
		var target_id := int(impact["target_id"])
		if not projectiles.has(impact_id):
			continue
		if not _entity_enabled(target_id, units, buildings):
			projectiles.erase(impact_id)
			continue
		var health_before := _entity_health(target_id, units, buildings)
		var amount := maxf(1.0, float(impact["attack_power"]) - _entity_armor(target_id, units, buildings))
		_apply_damage(target_id, amount, units, buildings)
		var health_after := _entity_health(target_id, units, buildings)
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.PROJECTILE_IMPACTED, target_id, "projectile=%d" % impact_id))
		events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.DAMAGE_APPLIED, int(impact["source_id"]), "target=%d;amount=%.3f;remaining=%.3f" % [target_id, amount, health_after]))
		projectiles.erase(impact_id)
		if health_before > 0.0 and is_zero_approx(health_after):
			_disable_destroyed_target(target_id, units, buildings, current_tick)
			var event_kind := SimulationEvent.Kind.UNIT_DESTROYED if units.has(target_id) else SimulationEvent.Kind.BUILDING_DESTROYED
			events.append(SimulationEvent.new(current_tick, event_kind, target_id))
			for entity_id in entity_ids:
				var attacker := units[entity_id] as UnitState
				if attacker.attack_target_entity_id == target_id:
					_clear_invalid_target(attacker, events, current_tick, "destroyed")
	return projectile_id


func _entity_exists(entity_id: int, units: Dictionary, buildings: Dictionary) -> bool:
	return units.has(entity_id) or buildings.has(entity_id)


func _entity_enabled(entity_id: int, units: Dictionary, buildings: Dictionary) -> bool:
	if units.has(entity_id):
		return (units[entity_id] as UnitState).enabled
	if buildings.has(entity_id):
		return (buildings[entity_id] as BuildingState).enabled
	return false


func _entity_position(entity_id: int, units: Dictionary, buildings: Dictionary) -> Vector2:
	if units.has(entity_id):
		return (units[entity_id] as UnitState).position
	return (buildings[entity_id] as BuildingState).position


func _entity_faction(entity_id: int, units: Dictionary, buildings: Dictionary) -> int:
	if units.has(entity_id):
		return (units[entity_id] as UnitState).faction_id
	return (buildings[entity_id] as BuildingState).faction_id


func _entity_health(entity_id: int, units: Dictionary, buildings: Dictionary) -> float:
	if units.has(entity_id):
		return (units[entity_id] as UnitState).health
	return (buildings[entity_id] as BuildingState).health


func _entity_armor(entity_id: int, units: Dictionary, buildings: Dictionary) -> float:
	if units.has(entity_id):
		return (units[entity_id] as UnitState).armor
	return (buildings[entity_id] as BuildingState).armor


func _apply_damage(entity_id: int, amount: float, units: Dictionary, buildings: Dictionary) -> void:
	if units.has(entity_id):
		var unit := units[entity_id] as UnitState
		unit.health = maxf(0.0, unit.health - amount)
	else:
		var building := buildings[entity_id] as BuildingState
		building.health = maxf(0.0, building.health - amount)


func _clear_invalid_target(unit: UnitState, events: Array[SimulationEvent], current_tick: int, reason: String) -> void:
	var target_id := unit.attack_target_entity_id
	if target_id == 0:
		return
	unit.attack_target_entity_id = 0
	unit.pursuit_target_cell = Vector2i(-1, -1)
	events.append(SimulationEvent.new(current_tick, SimulationEvent.Kind.TARGET_LOST, unit.entity_id, "target=%d;reason=%s" % [target_id, reason]))


func _disable_destroyed_target(entity_id: int, units: Dictionary, buildings: Dictionary, current_tick: int) -> void:
	if buildings.has(entity_id):
		var building := buildings[entity_id] as BuildingState
		building.health = 0.0
		building.enabled = false
		building.operational = false
		building.under_construction = false
		building.production_definition_id = &""
		building.production_ticks_remaining = 0
		return
	var unit := units[entity_id] as UnitState
	unit.health = 0.0
	unit.enabled = false
	unit.death_tick = current_tick
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
	unit.attack_move_destination = unit.position
	unit.pursuit_target_cell = Vector2i(-1, -1)
	unit.attack_target_entity_id = 0
	unit.work_kind = UnitState.WorkKind.NONE
	unit.work_target_building_id = 0
