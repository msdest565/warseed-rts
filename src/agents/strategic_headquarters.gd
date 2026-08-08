class_name StrategicHeadquarters
extends RefCounted

enum Posture {
	DORMANT,
	ECONOMY_RECOVERY,
	BASE_DEFENSE,
	DEVELOPMENT,
	FORCE_BUILDUP,
	STABLE,
}

enum Directive {
	NONE,
	BALANCED,
	ECONOMY_FIRST,
	DEFENSIVE,
	OFFENSIVE,
}

const DECISION_INTERVAL_TICKS := 10
const EMERGENCY_ORE_RESERVE := 400
const PLAYER_RESERVED_QUEUE_SLOTS := 1
const TARGET_HARVESTER_COUNT := 2
const ECONOMY_TARGET_HARVESTER_COUNT := 3
const TARGET_SCOUT_COUNT := 1
const TARGET_ASSAULT_COUNT := 3
const TARGET_MISSILE_COUNT := 2
const BASE_THREAT_RADIUS := 640.0
const MAX_DYNAMIC_TARGET_BONUS := 1

var last_decision_tick: int = -DECISION_INTERVAL_TICKS
var last_decision_key: StringName = &"HQ_DECISION_STABLE"
var last_posture: Posture = Posture.DORMANT
var last_pending_ore: int = 0
var last_reserved_ore: int = 0
var last_available_ore: int = 0
var last_production_definition_id: StringName = &""
var directive: Directive = Directive.NONE


func advance(world: SimulationWorld) -> void:
	var industrial_policy := world.agent_policies.get(StrategicTaskSystem.INDUSTRIAL_AGENT_ID) as AgentPolicy
	var battlefield_policy := world.agent_policies.get(StrategicTaskSystem.BATTLEFIELD_AGENT_ID) as AgentPolicy
	var industrial_active := industrial_policy != null and industrial_policy.allows_proactive_tasks()
	var battlefield_active := battlefield_policy != null and battlefield_policy.allows_proactive_tasks()
	var base_threat := battlefield_active and _has_visible_base_threat(world)
	_refresh_budget_ledger(world, battlefield_active and not base_threat)
	if world.current_tick - last_decision_tick < DECISION_INTERVAL_TICKS:
		return
	last_decision_tick = world.current_tick
	last_production_definition_id = &""
	if not industrial_active and not battlefield_active:
		_set_decision(Posture.DORMANT, &"HQ_DECISION_STABLE")
		return

	var harvester_commitments := _committed_unit_count(world, &"harvester")
	if industrial_active and harvester_commitments == 0:
		_set_decision(Posture.ECONOMY_RECOVERY, &"HQ_DECISION_ECONOMY_RECOVERY")
		_queue_production(world, &"harvester", StrategicTaskSystem.INDUSTRIAL_AGENT_ID, 0)
		return
	if battlefield_active and base_threat and _advance_combat_production(world, true):
		return
	if industrial_active and harvester_commitments < _target_harvester_count():
		_set_decision(Posture.DEVELOPMENT, &"HQ_DECISION_ECONOMY_DEVELOPMENT")
		_queue_production(world, &"harvester", StrategicTaskSystem.INDUSTRIAL_AGENT_ID, 0)
		return
	if battlefield_active and _advance_combat_production(world, false):
		return

	_set_decision(Posture.STABLE, &"HQ_DECISION_STABLE")


func should_start_industrial_development(world: SimulationWorld) -> bool:
	var enabled := _enabled_unit_count(world, &"harvester")
	return enabled > 0 and enabled < _target_harvester_count()


func set_directive(new_directive: Directive) -> void:
	directive = new_directive
	last_decision_tick = -DECISION_INTERVAL_TICKS


func directive_key() -> StringName:
	return StringName("HQ_DIRECTIVE_%s" % Directive.keys()[directive])


func budget_snapshot() -> Dictionary:
	return {
		"pending": last_pending_ore,
		"reserved": last_reserved_ore,
		"available": last_available_ore,
	}


func _set_decision(posture: Posture, decision_key: StringName) -> void:
	last_posture = posture
	last_decision_key = decision_key


func _advance_combat_production(world: SimulationWorld, base_threat: bool) -> bool:
	var priority := _combat_production_priority(world, base_threat)
	if priority.is_empty():
		return false
	var definition_id := priority[0]
	var reserve_floor := 0 if base_threat else EMERGENCY_ORE_RESERVE
	var posture := Posture.BASE_DEFENSE if base_threat else Posture.FORCE_BUILDUP
	if _queue_production(world, definition_id, StrategicTaskSystem.BATTLEFIELD_AGENT_ID, reserve_floor):
		_set_decision(posture, &"HQ_DECISION_EMERGENCY_DEFENSE" if base_threat else &"HQ_DECISION_COMBAT_PRODUCTION")
		return true
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(definition_id)
	if _production_building(world, definition_id, false) == null:
		_set_decision(posture, &"HQ_DECISION_QUEUE_WAIT")
	elif definition != null and not _can_afford(world, definition.production_cost, reserve_floor):
		_set_decision(posture, &"HQ_DECISION_RESERVE")
	else:
		_set_decision(posture, &"HQ_DECISION_QUEUE_WAIT")
	return true


func _refresh_budget_ledger(world: SimulationWorld, keep_emergency_reserve: bool) -> void:
	last_pending_ore = _pending_production_cost(world, SimulationWorld.LOCAL_PLAYER_ID)
	last_reserved_ore = EMERGENCY_ORE_RESERVE if keep_emergency_reserve else 0
	var faction := world.factions.get(SimulationWorld.LOCAL_PLAYER_ID) as FactionState
	last_available_ore = maxi(0, (faction.ore if faction != null else 0) - last_pending_ore - last_reserved_ore)


func _combat_production_priority(world: SimulationWorld, base_threat: bool = false) -> Array[StringName]:
	var targets := _combat_targets(world, base_threat)
	var assault_count := _committed_unit_count(world, &"assault_vehicle")
	var scout_count := _committed_unit_count(world, &"scout_vehicle")
	var missile_count := _committed_unit_count(world, &"missile_vehicle")
	var result: Array[StringName] = []
	var frontline_floor := mini(2, int(targets[&"assault_vehicle"]))
	if assault_count < frontline_floor:
		result.append(&"assault_vehicle")
	if scout_count < int(targets[&"scout_vehicle"]):
		result.append(&"scout_vehicle")
	if missile_count < int(targets[&"missile_vehicle"]):
		result.append(&"missile_vehicle")
	if assault_count < int(targets[&"assault_vehicle"]):
		result.append(&"assault_vehicle")
	return result


func _combat_targets(world: SimulationWorld, base_threat: bool) -> Dictionary:
	var targets := {
		&"scout_vehicle": TARGET_SCOUT_COUNT,
		&"assault_vehicle": TARGET_ASSAULT_COUNT,
		&"missile_vehicle": TARGET_MISSILE_COUNT,
	}
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var observed_assault := 0
	var observed_missile := 0
	if directive == Directive.DEFENSIVE:
		targets[&"assault_vehicle"] += 1
		targets[&"missile_vehicle"] += 1
	elif directive == Directive.OFFENSIVE:
		targets[&"assault_vehicle"] += 2
		targets[&"missile_vehicle"] += 1
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.LOCAL_PLAYER_ID or not contact.enabled:
			continue
		if contact.definition_id == &"assault_vehicle":
			observed_assault += 1
		elif contact.definition_id == &"missile_vehicle":
			observed_missile += 1
	if observed_assault > observed_missile:
		targets[&"missile_vehicle"] += MAX_DYNAMIC_TARGET_BONUS
	elif observed_missile > observed_assault:
		targets[&"assault_vehicle"] += MAX_DYNAMIC_TARGET_BONUS
	if base_threat:
		targets[&"assault_vehicle"] += MAX_DYNAMIC_TARGET_BONUS
	return targets


func _target_harvester_count() -> int:
	return ECONOMY_TARGET_HARVESTER_COUNT if directive == Directive.ECONOMY_FIRST else TARGET_HARVESTER_COUNT


func _has_visible_base_threat(world: SimulationWorld) -> bool:
	var base_position := world._faction_base_position(SimulationWorld.LOCAL_PLAYER_ID)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	for contact in snapshot.units:
		if contact.enabled and contact.is_visible_to_local_player and contact.faction_id != SimulationWorld.LOCAL_PLAYER_ID and contact.position.distance_to(base_position) <= BASE_THREAT_RADIUS:
			return true
	return false


func _queue_production(world: SimulationWorld, definition_id: StringName, agent_id: int, reserve_floor: int) -> bool:
	var factory := _production_building(world, definition_id, true)
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(definition_id)
	if factory == null or definition == null or not _can_afford(world, definition.production_cost, reserve_floor):
		return false
	var command := ProduceUnitCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, factory.entity_id, definition_id
	)
	command.agent_id = agent_id
	if not world.submit_command(command).is_accepted():
		return false
	last_production_definition_id = definition_id
	last_pending_ore += definition.production_cost
	last_available_ore = maxi(0, last_available_ore - definition.production_cost)
	return true


func _can_afford(world: SimulationWorld, cost: int, reserve_floor: int) -> bool:
	var faction := world.factions.get(SimulationWorld.LOCAL_PLAYER_ID) as FactionState
	return faction != null and faction.ore - _pending_production_cost(world, faction.faction_id) - cost >= reserve_floor


func _production_building(world: SimulationWorld, definition_id: StringName, require_agent_capacity: bool = false) -> BuildingState:
	var building_ids := world.buildings.keys()
	building_ids.sort()
	for building_id in building_ids:
		var building := world.buildings[building_id] as BuildingState
		if not building.enabled or not building.operational or building.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			continue
		var definition := SimulationWorld.BUILDING_CATALOG.get_building(building.definition_id)
		if definition == null or not definition.can_produce(definition_id):
			continue
		if require_agent_capacity and _committed_queue_count(world, building.entity_id) >= BuildingState.MAX_PRODUCTION_QUEUE_SIZE - PLAYER_RESERVED_QUEUE_SLOTS:
			continue
		return building
	return null


func _committed_queue_count(world: SimulationWorld, building_id: int) -> int:
	var building := world.buildings.get(building_id) as BuildingState
	var count := building.production_count() if building != null else 0
	for queued_command in world.command_queue.snapshot():
		if queued_command is ProduceUnitCommand and (queued_command as ProduceUnitCommand).target_entity_id == building_id:
			count += 1
	return count


func _pending_production_cost(world: SimulationWorld, faction_id: int) -> int:
	var result := 0
	for queued_command in world.command_queue.snapshot():
		if not queued_command is ProduceUnitCommand:
			continue
		var production := queued_command as ProduceUnitCommand
		var building := world.buildings.get(production.target_entity_id) as BuildingState
		var definition := SimulationWorld.UNIT_CATALOG.get_unit(production.unit_definition_id)
		if building != null and building.faction_id == faction_id and definition != null:
			result += definition.production_cost
	return result


func _committed_unit_count(world: SimulationWorld, definition_id: StringName) -> int:
	var count := _enabled_unit_count(world, definition_id)
	for building_variant in world.buildings.values():
		var building := building_variant as BuildingState
		if building.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			continue
		if building.production_definition_id == definition_id:
			count += 1
		for queued_definition_id in building.production_queue:
			if queued_definition_id == definition_id:
				count += 1
	for queued_command in world.command_queue.snapshot():
		if queued_command is ProduceUnitCommand:
			var production := queued_command as ProduceUnitCommand
			var building := world.buildings.get(production.target_entity_id) as BuildingState
			if production.unit_definition_id == definition_id and building != null and building.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
				count += 1
	return count


func _enabled_unit_count(world: SimulationWorld, definition_id: StringName) -> int:
	var count := 0
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID and unit.definition_id == definition_id:
			count += 1
	return count
