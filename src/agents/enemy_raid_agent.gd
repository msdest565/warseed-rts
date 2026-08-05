class_name EnemyRaidAgent
extends RefCounted

enum Phase {
	ECONOMY,
	EXPANSION,
	SCOUTING,
	CONTESTING,
	MUSTERING,
	RAIDING,
	RETREATING,
	DEFENDING,
}

const AGENT_ID := 301
const TASK_ID := 9001
const RAID_UNIT_ID := 1099
const STRATEGY_START_TICK := 300
const SCOUT_TIMEOUT_TICKS := 140
const CONTEST_TIMEOUT_TICKS := 140
const RAID_DURATION_TICKS := 400
const RETREAT_TIMEOUT_TICKS := 240
const DEFEND_DURATION_TICKS := 220
const RAID_FORCE_SIZE := 3
const ENEMY_FACTORY_POSITION := Vector2i(79, 51)
const ENEMY_SUPPORT_POSITION := Vector2i(84, 48)
const SCOUT_POSITION := Vector2i(53, 32)
const DEFAULT_DIFFICULTY: EnemyDifficultyProfile = preload("res://data/ai/enemy_normal.tres")

var phase: Phase = Phase.ECONOMY
var phase_started_tick: int = 0
var phase_history: Array[Phase] = [Phase.ECONOMY]
var last_order_tick: int = -1000
var last_unit_order_tick: Dictionary = {}
var production_reserved_tick: int = -1
var engineering_reserved_tick: int = -1
var completed_cycles: int = 0
var spawned: bool = false
var difficulty_profile: EnemyDifficultyProfile
var last_strategy_tick: int = -1000
var base_threat_detected_tick: int = -1
var next_attack_allowed_tick: int = 0
var engagement_origin_by_unit: Dictionary = {}
var engagement_started_tick_by_unit: Dictionary = {}
var last_decision_reason: String = "Initializing economy"
var last_target_score: float = 0.0
var last_route_risk: float = 0.0
var last_observed_composition: String = "scout=0 assault=0 missile=0"


func _init(profile: EnemyDifficultyProfile = null) -> void:
	difficulty_profile = (profile if profile != null else DEFAULT_DIFFICULTY).duplicate(true) as EnemyDifficultyProfile


func set_difficulty_profile(profile: EnemyDifficultyProfile) -> void:
	if profile == null:
		return
	difficulty_profile = profile
	base_threat_detected_tick = -1
	last_strategy_tick = -1000
	last_decision_reason = "Difficulty changed to %s" % difficulty_profile.difficulty_name()


func advance(world: SimulationWorld) -> void:
	if world.current_tick < STRATEGY_START_TICK:
		return
	_claim_enemy_units(world)
	_ensure_harvest(world)
	_maintain_economy_units(world)
	_maintain_engineering(world)
	var base_threat := _base_threat_score(world)
	if base_threat > 0.0 and phase not in [Phase.DEFENDING, Phase.RETREATING]:
		if base_threat_detected_tick < 0:
			base_threat_detected_tick = world.current_tick
		if world.current_tick - base_threat_detected_tick < difficulty_profile.reaction_delay_ticks:
			last_decision_reason = "Base threat %.2f detected; reacting in %d ticks" % [base_threat, difficulty_profile.reaction_delay_ticks - (world.current_tick - base_threat_detected_tick)]
			return
		_change_phase(Phase.DEFENDING, world, "Base threat %.2f exceeded response threshold" % base_threat)
	else:
		base_threat_detected_tick = -1
	if phase == Phase.RAIDING:
		var combat_units := _combat_units(world)
		var health_ratio := _average_health_ratio(combat_units)
		if combat_units.size() <= 1 or health_ratio <= difficulty_profile.retreat_enter_ratio or _phase_elapsed(world) >= RAID_DURATION_TICKS:
			next_attack_allowed_tick = world.current_tick + difficulty_profile.strategic_decision_interval_ticks
			_change_phase(Phase.RETREATING, world, "Withdrawal: units=%d health=%.2f" % [combat_units.size(), health_ratio])
			return
	if phase == Phase.RETREATING:
		_advance_retreating(world)
		return
	var decision_interval := difficulty_profile.tactical_decision_interval_ticks if phase in [Phase.RAIDING, Phase.RETREATING, Phase.DEFENDING] else difficulty_profile.strategic_decision_interval_ticks
	if world.current_tick - last_strategy_tick < decision_interval:
		return
	last_strategy_tick = world.current_tick
	match phase:
		Phase.ECONOMY:
			if world.current_tick >= STRATEGY_START_TICK:
				_change_phase(Phase.EXPANSION, world, "Opening economy established")
		Phase.EXPANSION:
			_advance_expansion(world)
		Phase.SCOUTING:
			_advance_scouting(world)
		Phase.CONTESTING:
			_advance_contesting(world)
		Phase.MUSTERING:
			_advance_mustering(world)
		Phase.RAIDING:
			_advance_raiding(world)
		Phase.RETREATING:
			_advance_retreating(world)
		Phase.DEFENDING:
			_advance_defending(world)


func phase_name() -> String:
	return Phase.keys()[phase]


func difficulty_name() -> String:
	return difficulty_profile.difficulty_name()


func decision_summary() -> String:
	return "%s | score %.2f | route %.2f | %s" % [last_decision_reason, last_target_score, last_route_risk, last_observed_composition]


func _advance_expansion(world: SimulationWorld) -> void:
	if engineering_reserved_tick == world.current_tick:
		return
	var factory := _enemy_factory(world)
	if factory != null:
		if factory.operational:
			_change_phase(Phase.SCOUTING, world, "Factory operational; scouting next")
		return
	var engineer := world.units.get(SimulationWorld.ENEMY_ENGINEER_ID) as UnitState
	if engineer == null or not engineer.enabled or engineer.work_kind != UnitState.WorkKind.NONE:
		return
	var build_position := _find_factory_position(engineer, world)
	if build_position == Vector2.ZERO:
		return
	var command := BuildBuildingCommand.new(
		world.allocate_command_id(),
		SimulationWorld.ENEMY_PLAYER_ID,
		GameCommand.IssuerKind.AGENT,
		world.current_tick,
		engineer.entity_id,
		&"automated_factory",
		build_position
	)
	if _submit(command, world):
		engineering_reserved_tick = world.current_tick


func _advance_scouting(world: SimulationWorld) -> void:
	var scout := _first_combat_unit(world, &"scout_vehicle")
	if scout == null:
		_submit_production(&"scout_vehicle", world)
		return
	var destination := world.logic_grid.cell_to_world(SCOUT_POSITION)
	_submit_move(scout, destination, world)
	if scout.position.distance_to(destination) <= 72.0 or _phase_elapsed(world) >= SCOUT_TIMEOUT_TICKS:
		_change_phase(Phase.CONTESTING, world, "Scout reached central observation route")


func _advance_contesting(world: SimulationWorld) -> void:
	var scout := _first_combat_unit(world, &"scout_vehicle")
	var ore_field := world.ore_fields.get(SimulationWorld.DEFAULT_ORE_FIELD_ID) as OreFieldState
	if scout != null and ore_field != null:
		_submit_move(scout, ore_field.position, world)
	if scout == null or ore_field == null or scout.position.distance_to(ore_field.position) <= 96.0 or _phase_elapsed(world) >= CONTEST_TIMEOUT_TICKS:
		_change_phase(Phase.MUSTERING, world, "Player-side resource approach checked")


func _advance_mustering(world: SimulationWorld) -> void:
	var combat_units := _combat_units(world)
	var knowledge := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	var own_power := _combat_power(combat_units)
	var known_enemy_power := _visible_enemy_power(knowledge)
	if combat_units.size() >= RAID_FORCE_SIZE and (known_enemy_power <= 0.0 or own_power >= known_enemy_power * difficulty_profile.required_attack_power_ratio) and world.current_tick >= next_attack_allowed_tick:
		_change_phase(Phase.RAIDING, world, "Raid ready: own %.1f vs known %.1f" % [own_power, known_enemy_power])
		spawned = true
		return
	last_decision_reason = "Mustering: %d/%d units, power %.1f/%.1f" % [combat_units.size(), RAID_FORCE_SIZE, own_power, known_enemy_power * difficulty_profile.required_attack_power_ratio]
	_submit_production(_next_combat_definition(world), world)


func _advance_raiding(world: SimulationWorld) -> void:
	var combat_units := _combat_units(world)
	var knowledge := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	for unit in combat_units:
		if _chase_limit_exceeded(unit, world):
			var return_position: Vector2 = engagement_origin_by_unit.get(unit.entity_id, _base_rally_position(world))
			last_decision_reason = "E%d ended pursuit at configured leash" % unit.entity_id
			engagement_origin_by_unit.erase(unit.entity_id)
			engagement_started_tick_by_unit.erase(unit.entity_id)
			_submit_move(unit, return_position, world)
			continue
		var target_id := _choose_raid_target(knowledge, unit, world)
		if target_id != 0:
			_submit_attack(unit, target_id, world)
		else:
			var stale_position := _best_stale_position(knowledge, unit.position)
			if stale_position != Vector2.ZERO:
				last_decision_reason = "Investigating a decaying last-known contact"
				_submit_move(unit, stale_position, world)
			else:
				var ore_field := world.ore_fields.get(SimulationWorld.DEFAULT_ORE_FIELD_ID) as OreFieldState
				if ore_field != null:
					last_decision_reason = "No contact; pressuring the known player resource lane"
					_submit_move(unit, ore_field.position, world)


func _advance_retreating(world: SimulationWorld) -> void:
	var base_position := _base_rally_position(world)
	var all_home := true
	for unit in _combat_units(world):
		if unit.position.distance_to(base_position) > 160.0:
			all_home = false
			_submit_move(unit, base_position, world)
	if all_home or _phase_elapsed(world) >= RETREAT_TIMEOUT_TICKS:
		_change_phase(Phase.DEFENDING, world, "Raid force returned to base")


func _advance_defending(world: SimulationWorld) -> void:
	var base_position := _base_rally_position(world)
	var knowledge := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	var threat_present := false
	for unit in _combat_units(world):
		var target_id := _best_visible_target(knowledge, base_position, difficulty_profile.base_defense_radius, world)
		if target_id != 0:
			threat_present = true
			_submit_attack(unit, target_id, world)
		elif unit.position.distance_to(base_position) > 180.0:
			_submit_move(unit, base_position, world)
	var recovered := _average_health_ratio(_combat_units(world)) >= difficulty_profile.retreat_exit_ratio
	if not threat_present and _phase_elapsed(world) >= DEFEND_DURATION_TICKS and (recovered or _phase_elapsed(world) >= DEFEND_DURATION_TICKS * 2):
		completed_cycles += 1
		_change_phase(Phase.MUSTERING, world, "Defense stable; rebuilding raid force")


func _ensure_harvest(world: SimulationWorld) -> void:
	var ore_field := world.ore_fields.get(SimulationWorld.ENEMY_ORE_FIELD_ID) as OreFieldState
	var refinery := world.buildings.get(SimulationWorld.ENEMY_COMMAND_CENTER_ID) as BuildingState
	if ore_field == null or ore_field.ore_remaining <= 0 or refinery == null or not refinery.enabled:
		return
	for unit_variant in world.units.values():
		var harvester := unit_variant as UnitState
		if not harvester.enabled or harvester.faction_id != SimulationWorld.ENEMY_PLAYER_ID or not harvester.can_harvest or harvester.harvest_ore_field_entity_id != 0:
			continue
		var command := HarvestCommand.new(
			world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
			world.current_tick, harvester.entity_id, ore_field.entity_id, refinery.entity_id
		)
		_submit(command, world)


func _maintain_economy_units(world: SimulationWorld) -> void:
	var harvester_count := 0
	var engineer_count := 0
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if not unit.enabled or unit.faction_id != SimulationWorld.ENEMY_PLAYER_ID:
			continue
		if unit.can_harvest:
			harvester_count += 1
		if unit.can_construct:
			engineer_count += 1
	if harvester_count == 0:
		_submit_production(&"harvester", world)
	elif engineer_count == 0:
		_submit_production(&"engineer_vehicle", world)


func _maintain_engineering(world: SimulationWorld) -> void:
	var engineer := _idle_engineer(world)
	if engineer == null:
		return
	var repair_target := _most_damaged_building(world)
	if repair_target != null:
		var repair := RepairBuildingCommand.new(
			world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
			world.current_tick, engineer.entity_id, repair_target.entity_id
		)
		if _submit(repair, world):
			engineering_reserved_tick = world.current_tick
		return
	if _enemy_factory(world) == null or _enemy_support(world) != null:
		return
	var support_definition := SimulationWorld.BUILDING_CATALOG.get_building(&"forward_support_station")
	var faction := world.factions.get(SimulationWorld.ENEMY_PLAYER_ID) as FactionState
	if support_definition == null or faction == null or faction.ore < support_definition.build_cost:
		return
	var build_position := _find_building_position(engineer, &"forward_support_station", ENEMY_SUPPORT_POSITION, world)
	if build_position == Vector2.ZERO:
		return
	var build := BuildBuildingCommand.new(
		world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, engineer.entity_id, &"forward_support_station", build_position
	)
	if _submit(build, world):
		engineering_reserved_tick = world.current_tick


func _submit_production(definition_id: StringName, world: SimulationWorld) -> void:
	if production_reserved_tick == world.current_tick:
		return
	var factory := _enemy_factory(world)
	if factory == null or not factory.operational or not factory.production_definition_id.is_empty():
		return
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(definition_id)
	var faction := world.factions.get(SimulationWorld.ENEMY_PLAYER_ID) as FactionState
	if definition == null or faction == null or faction.ore < definition.production_cost:
		return
	var command := ProduceUnitCommand.new(
		world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, factory.entity_id, definition_id
	)
	if _submit(command, world):
		production_reserved_tick = world.current_tick


func _submit_attack(unit: UnitState, target_entity_id: int, world: SimulationWorld) -> void:
	if unit.attack_target_entity_id == target_entity_id:
		return
	var command := AttackCommand.new(
		world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, unit.entity_id, target_entity_id
	)
	if _submit(command, world):
		engagement_origin_by_unit[unit.entity_id] = unit.position
		engagement_started_tick_by_unit[unit.entity_id] = world.current_tick
		last_decision_reason = "E%d attacks E%d at score %.2f" % [unit.entity_id, target_entity_id, last_target_score]


func _submit_move(unit: UnitState, destination: Vector2, world: SimulationWorld) -> void:
	if unit.has_move_target and unit.move_target.is_equal_approx(destination):
		return
	if world.current_tick - int(last_unit_order_tick.get(unit.entity_id, -difficulty_profile.tactical_decision_interval_ticks)) < difficulty_profile.tactical_decision_interval_ticks:
		return
	var command := MoveCommand.new(
		world.allocate_command_id(), SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, unit.entity_id, destination
	)
	_submit(command, world)


func _submit(command: GameCommand, world: SimulationWorld) -> bool:
	_set_context(command)
	var accepted := world.submit_command(command).is_accepted()
	if accepted:
		last_order_tick = world.current_tick
		if world.units.has(command.target_entity_id):
			last_unit_order_tick[command.target_entity_id] = world.current_tick
	return accepted


func _set_context(command: GameCommand) -> void:
	command.agent_id = AGENT_ID
	command.task_id = TASK_ID


func _enemy_factory(world: SimulationWorld) -> BuildingState:
	for building_variant in world.buildings.values():
		var building := building_variant as BuildingState
		if building.faction_id == SimulationWorld.ENEMY_PLAYER_ID and building.definition_id == &"automated_factory" and building.enabled:
			return building
	return null


func _enemy_support(world: SimulationWorld) -> BuildingState:
	for building_variant in world.buildings.values():
		var building := building_variant as BuildingState
		if building.faction_id == SimulationWorld.ENEMY_PLAYER_ID and building.definition_id == &"forward_support_station" and building.enabled:
			return building
	return null


func _idle_engineer(world: SimulationWorld) -> UnitState:
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID and unit.can_construct and unit.work_kind == UnitState.WorkKind.NONE:
			return unit
	return null


func _most_damaged_building(world: SimulationWorld) -> BuildingState:
	var result: BuildingState
	var lowest_ratio := 1.0
	for building_variant in world.buildings.values():
		var building := building_variant as BuildingState
		if not building.enabled or not building.operational or building.under_construction or building.faction_id != SimulationWorld.ENEMY_PLAYER_ID or building.health >= building.max_health:
			continue
		var ratio := building.health / building.max_health
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			result = building
	return result


func _base_rally_position(world: SimulationWorld) -> Vector2:
	var command_center := world.buildings.get(SimulationWorld.ENEMY_COMMAND_CENTER_ID) as BuildingState
	return command_center.rally_position if command_center != null and command_center.enabled else world.logic_grid.cell_to_world(LogicGrid.MAP_DEFINITION.enemy_spawn_cell + Vector2i(-4, 0))


func _first_combat_unit(world: SimulationWorld, definition_id: StringName = &"") -> UnitState:
	for unit in _combat_units(world):
		if definition_id.is_empty() or unit.definition_id == definition_id:
			return unit
	return null


func _combat_units(world: SimulationWorld) -> Array[UnitState]:
	var result: Array[UnitState] = []
	var entity_ids := world.units.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		var unit := world.units[entity_id] as UnitState
		if unit.enabled and unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID and unit.can_attack and not unit.can_harvest and not unit.can_construct:
			result.append(unit)
	return result


func _best_visible_target(snapshot: WorldSnapshot, origin: Vector2, max_distance: float = INF, world: SimulationWorld = null) -> int:
	var best_id := 0
	var best_score := -INF
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID or not contact.enabled or not contact.is_visible_to_local_player:
			continue
		if origin.distance_squared_to(contact.position) > max_distance * max_distance:
			continue
		var score := _unit_target_score(contact, snapshot, origin, world)
		if score > best_score or (is_equal_approx(score, best_score) and (best_id == 0 or contact.entity_id < best_id)):
			best_id = contact.entity_id
			best_score = score
	for building in snapshot.buildings:
		if building.faction_id == SimulationWorld.ENEMY_PLAYER_ID or not building.enabled or not building.is_visible:
			continue
		if origin.distance_squared_to(building.position) > max_distance * max_distance:
			continue
		var score := _building_target_score(building, snapshot, origin, world)
		if score > best_score or (is_equal_approx(score, best_score) and (best_id == 0 or building.entity_id < best_id)):
			best_id = building.entity_id
			best_score = score
	last_target_score = best_score if best_id != 0 else 0.0
	if best_id != 0 and world != null:
		var selected_unit := snapshot.get_unit(best_id)
		var selected_building := snapshot.get_building(best_id)
		var selected_position := selected_unit.position if selected_unit != null else selected_building.position
		last_route_risk = _route_risk_score(snapshot, origin, selected_position, world, best_id)
	else:
		last_route_risk = 0.0
	return best_id


func _choose_raid_target(snapshot: WorldSnapshot, unit: UnitState, world: SimulationWorld) -> int:
	var best_id := _best_visible_target(snapshot, unit.position, INF, world)
	if unit.attack_target_entity_id == 0 or best_id == 0 or unit.attack_target_entity_id == best_id:
		return best_id
	var current_contact := snapshot.get_unit(unit.attack_target_entity_id)
	var current_building := snapshot.get_building(unit.attack_target_entity_id)
	var current_score := -INF
	if current_contact != null and current_contact.is_visible_to_local_player:
		current_score = _unit_target_score(current_contact, snapshot, unit.position, world)
	elif current_building != null and current_building.is_visible:
		current_score = _building_target_score(current_building, snapshot, unit.position, world)
	if last_target_score <= current_score + difficulty_profile.target_switch_margin:
		last_target_score = current_score
		var current_position := current_contact.position if current_contact != null else current_building.position
		last_route_risk = _route_risk_score(snapshot, unit.position, current_position, world, unit.attack_target_entity_id)
		return unit.attack_target_entity_id
	return best_id


func _best_stale_position(snapshot: WorldSnapshot, origin: Vector2) -> Vector2:
	var best_score := 0.0
	var best_id := 0
	var result := Vector2.ZERO
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID or contact.is_visible_to_local_player:
			continue
		var age := maxi(0, snapshot.tick - contact.last_seen_tick)
		var confidence := pow(0.5, float(age) / difficulty_profile.memory_half_life_ticks)
		if confidence < 0.15:
			continue
		var score := confidence * _definition_strategic_value(contact.definition_id) - clampf(origin.distance_to(contact.last_seen_position) / 3072.0, 0.0, 1.0) * 0.35
		if score > best_score or (is_equal_approx(score, best_score) and (best_id == 0 or contact.entity_id < best_id)):
			best_score = score
			best_id = contact.entity_id
			result = contact.last_seen_position
	return result


func _claim_enemy_units(world: SimulationWorld) -> void:
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id != SimulationWorld.ENEMY_PLAYER_ID:
			continue
		unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
		unit.assigned_agent_id = AGENT_ID
		unit.assigned_task_id = TASK_ID


func _base_under_threat(world: SimulationWorld) -> bool:
	return _base_threat_score(world) > 0.0


func _base_threat_score(world: SimulationWorld) -> float:
	var snapshot := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	var base_position := _base_rally_position(world)
	var threat := 0.0
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID or not contact.enabled or not contact.is_visible_to_local_player:
			continue
		var distance := base_position.distance_to(contact.position)
		if distance > difficulty_profile.base_defense_radius:
			continue
		var combat_value := maxf(0.35, contact.attack_damage / 25.0) if contact.can_attack else 0.2
		threat += combat_value * (1.0 - distance / difficulty_profile.base_defense_radius * 0.5)
	return threat


func _average_health_ratio(units: Array[UnitState]) -> float:
	if units.is_empty():
		return 0.0
	var total := 0.0
	for unit in units:
		total += unit.health / unit.max_health if unit.max_health > 0.0 else 0.0
	return total / units.size()


func _unit_target_score(contact: UnitSnapshot, snapshot: WorldSnapshot, origin: Vector2, world: SimulationWorld) -> float:
	var health_ratio := contact.health / contact.max_health if contact.max_health > 0.0 else 0.0
	var strategic_value := _definition_strategic_value(contact.definition_id)
	var threat_reduction := 0.35 if contact.attack_target_entity_id != 0 else 0.0
	if contact.can_attack:
		threat_reduction += clampf(contact.attack_damage / 100.0, 0.0, 0.35)
	var economic_damage := 0.45 if contact.definition_id == &"harvester" else (0.28 if contact.definition_id == &"engineer_vehicle" else 0.0)
	var opportunity := (1.0 - health_ratio) * 0.45
	var travel_cost := clampf(origin.distance_to(contact.position) / 2048.0, 0.0, 1.0) * 0.55
	var route_risk := _route_risk_score(snapshot, origin, contact.position, world, contact.entity_id)
	var focus_bonus := _focus_fire_bonus(contact.entity_id, snapshot) * difficulty_profile.focus_fire_quality
	return strategic_value + threat_reduction + economic_damage + opportunity + focus_bonus - travel_cost - route_risk * difficulty_profile.route_threat_weight + _deterministic_noise(contact.entity_id, snapshot.tick)


func _building_target_score(building: BuildingSnapshot, snapshot: WorldSnapshot, origin: Vector2, world: SimulationWorld) -> float:
	var strategic_value := 0.7
	match building.definition_id:
		&"command_center":
			strategic_value = 1.6
		&"automated_factory":
			strategic_value = 1.2
		&"forward_support_station":
			strategic_value = 0.85
	var health_ratio := building.health / building.max_health if building.max_health > 0.0 else 0.0
	var opportunity := (1.0 - health_ratio) * 0.55
	var travel_cost := clampf(origin.distance_to(building.position) / 2048.0, 0.0, 1.0) * 0.55
	var route_risk := _route_risk_score(snapshot, origin, building.position, world, building.entity_id)
	return strategic_value + opportunity - travel_cost - route_risk * difficulty_profile.route_threat_weight + _deterministic_noise(building.entity_id, snapshot.tick)


func _definition_strategic_value(definition_id: StringName) -> float:
	match definition_id:
		&"missile_vehicle":
			return 1.05
		&"assault_vehicle":
			return 0.9
		&"harvester":
			return 0.82
		&"engineer_vehicle":
			return 0.62
		&"scout_vehicle":
			return 0.5
		&"command_center":
			return 1.6
		&"automated_factory":
			return 1.2
		&"forward_support_station":
			return 0.85
	return 0.4


func _route_risk_score(snapshot: WorldSnapshot, origin: Vector2, destination: Vector2, world: SimulationWorld, excluded_target_id: int = 0) -> float:
	if world == null:
		return 0.0
	var path := world.pathfinder.find_path(origin, destination)
	if path.is_empty():
		return 1.0
	var risk := 0.0
	for contact in snapshot.units:
		if contact.entity_id == excluded_target_id or contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID or not contact.enabled or not contact.is_visible_to_local_player or not contact.can_attack:
			continue
		var proximity := _distance_to_path(contact.position, path)
		var influence_range := maxf(192.0, contact.attack_range + 96.0)
		if proximity < influence_range:
			risk += (1.0 - proximity / influence_range) * clampf(contact.attack_damage / 40.0, 0.25, 1.0)
	return clampf(risk / 3.0, 0.0, 1.0)


func _distance_to_path(position: Vector2, path: PackedVector2Array) -> float:
	var best := INF
	if path.size() == 1:
		return position.distance_to(path[0])
	for index in range(path.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(position, path[index], path[index + 1])
		best = minf(best, position.distance_to(closest))
	return best


func _focus_fire_bonus(target_id: int, snapshot: WorldSnapshot) -> float:
	var attackers := 0
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID and contact.enabled and contact.attack_target_entity_id == target_id:
			attackers += 1
	return minf(0.24, attackers * 0.08)


func _deterministic_noise(entity_id: int, tick: int) -> float:
	if difficulty_profile.target_score_noise <= 0.0:
		return 0.0
	var stable_tick := tick / maxi(1, difficulty_profile.strategic_decision_interval_ticks)
	var value := posmod(entity_id * 1103515245 + stable_tick * 12345 + completed_cycles * 97, 2001)
	return (float(value) / 1000.0 - 1.0) * difficulty_profile.target_score_noise


func _chase_limit_exceeded(unit: UnitState, world: SimulationWorld) -> bool:
	if unit.attack_target_entity_id == 0 or not engagement_origin_by_unit.has(unit.entity_id):
		return false
	var origin := engagement_origin_by_unit[unit.entity_id] as Vector2
	var started_tick := int(engagement_started_tick_by_unit.get(unit.entity_id, world.current_tick))
	return unit.position.distance_to(origin) > difficulty_profile.chase_distance or world.current_tick - started_tick > difficulty_profile.chase_duration_ticks


func _combat_power(units: Array[UnitState]) -> float:
	var power := 0.0
	for unit in units:
		var health_ratio := unit.health / unit.max_health if unit.max_health > 0.0 else 0.0
		power += (unit.attack_damage * unit.attacks_per_second + unit.max_health * 0.08) * health_ratio
	return power


func _visible_enemy_power(snapshot: WorldSnapshot) -> float:
	var power := 0.0
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID or not contact.enabled or not contact.is_visible_to_local_player or not contact.can_attack:
			continue
		var health_ratio := contact.health / contact.max_health if contact.max_health > 0.0 else 0.0
		power += (contact.attack_damage * contact.attacks_per_second + contact.max_health * 0.08) * health_ratio
	return power


func _next_combat_definition(world: SimulationWorld) -> StringName:
	var scouts := 0
	var assaults := 0
	var missiles := 0
	for unit in _combat_units(world):
		match unit.definition_id:
			&"scout_vehicle": scouts += 1
			&"assault_vehicle": assaults += 1
			&"missile_vehicle": missiles += 1
	if scouts == 0:
		return &"scout_vehicle"
	if assaults == 0:
		return &"assault_vehicle"
	if missiles == 0:
		return &"missile_vehicle"
	var snapshot := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	var observed_scouts := 0.0
	var observed_assaults := 0.0
	var observed_missiles := 0.0
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID or not contact.enabled:
			continue
		var confidence := 1.0 if contact.is_visible_to_local_player else pow(0.5, float(maxi(0, snapshot.tick - contact.last_seen_tick)) / difficulty_profile.memory_half_life_ticks)
		match contact.definition_id:
			&"scout_vehicle": observed_scouts += confidence
			&"assault_vehicle": observed_assaults += confidence
			&"missile_vehicle": observed_missiles += confidence
	last_observed_composition = "scout=%.1f assault=%.1f missile=%.1f" % [observed_scouts, observed_assaults, observed_missiles]
	var reaction := difficulty_profile.composition_reaction_weight
	if (observed_missiles - observed_assaults) * reaction > 0.6:
		last_decision_reason = "Producing assault counter for observed missile concentration"
		return &"assault_vehicle"
	if (observed_assaults - observed_missiles) * reaction > 0.6:
		last_decision_reason = "Producing missile counter for observed assault concentration"
		return &"missile_vehicle"
	return &"assault_vehicle" if assaults <= missiles else &"missile_vehicle"


func _find_factory_position(engineer: UnitState, world: SimulationWorld) -> Vector2:
	return _find_building_position(engineer, &"automated_factory", ENEMY_FACTORY_POSITION, world)


func _find_building_position(engineer: UnitState, definition_id: StringName, preferred_cell: Vector2i, world: SimulationWorld) -> Vector2:
	var offsets: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i(-4, 0), Vector2i(0, -4), Vector2i(-4, -4),
		Vector2i(4, 0), Vector2i(0, 4), Vector2i(-8, 0), Vector2i(0, -8),
	]
	for offset in offsets:
		var position := world.logic_grid.cell_to_world(preferred_cell + offset)
		var probe := BuildBuildingCommand.new(
			0, SimulationWorld.ENEMY_PLAYER_ID, GameCommand.IssuerKind.AGENT,
			world.current_tick, engineer.entity_id, definition_id, position
		)
		_set_context(probe)
		if world.validate_command(probe).is_accepted():
			return position
	return Vector2.ZERO


func _change_phase(next_phase: Phase, world: SimulationWorld, reason: String = "") -> void:
	if phase == next_phase:
		return
	phase = next_phase
	phase_started_tick = world.current_tick
	phase_history.append(next_phase)
	if not reason.is_empty():
		last_decision_reason = reason
	world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.ENEMY_PHASE_CHANGED, SimulationWorld.ENEMY_PLAYER_ID, phase_name()))


func _phase_elapsed(world: SimulationWorld) -> int:
	return world.current_tick - phase_started_tick
