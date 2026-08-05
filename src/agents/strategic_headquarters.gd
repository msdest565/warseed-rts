class_name StrategicHeadquarters
extends RefCounted

const DECISION_INTERVAL_TICKS := 10
const EMERGENCY_ORE_RESERVE := 400
const TARGET_HARVESTER_COUNT := 2
const TARGET_SCOUT_COUNT := 1
const TARGET_ASSAULT_COUNT := 3
const TARGET_MISSILE_COUNT := 2

var last_decision_tick: int = -DECISION_INTERVAL_TICKS
var last_decision_key: StringName = &"HQ_DECISION_STABLE"


func advance(world: SimulationWorld) -> void:
	if world.current_tick - last_decision_tick < DECISION_INTERVAL_TICKS:
		return
	last_decision_tick = world.current_tick
	var industrial_policy := world.agent_policies.get(StrategicTaskSystem.INDUSTRIAL_AGENT_ID) as AgentPolicy
	var battlefield_policy := world.agent_policies.get(StrategicTaskSystem.BATTLEFIELD_AGENT_ID) as AgentPolicy
	if industrial_policy != null and industrial_policy.allows_proactive_tasks():
		var harvester_commitments := _committed_unit_count(world, &"harvester")
		if harvester_commitments == 0 and _queue_production(world, &"harvester", StrategicTaskSystem.INDUSTRIAL_AGENT_ID, false):
			last_decision_key = &"HQ_DECISION_ECONOMY_RECOVERY"
			return
		if harvester_commitments < TARGET_HARVESTER_COUNT:
			last_decision_key = &"HQ_DECISION_ECONOMY_DEVELOPMENT"
			return
	if battlefield_policy != null and battlefield_policy.allows_proactive_tasks():
		for definition_id in _combat_production_priority(world):
			if _queue_production(world, definition_id, StrategicTaskSystem.BATTLEFIELD_AGENT_ID, true):
				last_decision_key = &"HQ_DECISION_COMBAT_PRODUCTION"
				return
			if _production_building(world, definition_id) != null:
				last_decision_key = &"HQ_DECISION_RESERVE"
				return
	last_decision_key = &"HQ_DECISION_STABLE"


func should_start_industrial_development(world: SimulationWorld) -> bool:
	var committed := _committed_unit_count(world, &"harvester")
	return _enabled_unit_count(world, &"harvester") > 0 and committed < TARGET_HARVESTER_COUNT


func _combat_production_priority(world: SimulationWorld) -> Array[StringName]:
	var result: Array[StringName] = []
	if _committed_unit_count(world, &"scout_vehicle") < TARGET_SCOUT_COUNT:
		result.append(&"scout_vehicle")
	if _committed_unit_count(world, &"assault_vehicle") < TARGET_ASSAULT_COUNT:
		result.append(&"assault_vehicle")
	if _committed_unit_count(world, &"missile_vehicle") < TARGET_MISSILE_COUNT:
		result.append(&"missile_vehicle")
	return result


func _queue_production(world: SimulationWorld, definition_id: StringName, agent_id: int, keep_reserve: bool) -> bool:
	var factory := _production_building(world, definition_id)
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(definition_id)
	var faction := world.factions.get(SimulationWorld.LOCAL_PLAYER_ID) as FactionState
	if factory == null or definition == null or faction == null:
		return false
	if factory.production_count() >= BuildingState.MAX_PRODUCTION_QUEUE_SIZE - 1:
		return false
	if keep_reserve and faction.ore - definition.production_cost < EMERGENCY_ORE_RESERVE:
		return false
	var command := ProduceUnitCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, factory.entity_id, definition_id
	)
	command.agent_id = agent_id
	return world.submit_command(command).is_accepted()


func _production_building(world: SimulationWorld, definition_id: StringName) -> BuildingState:
	var building_ids := world.buildings.keys()
	building_ids.sort()
	for building_id in building_ids:
		var building := world.buildings[building_id] as BuildingState
		if not building.enabled or not building.operational or building.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			continue
		var definition := SimulationWorld.BUILDING_CATALOG.get_building(building.definition_id)
		if definition != null and definition.can_produce(definition_id):
			return building
	return null


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
		if queued_command is ProduceUnitCommand and (queued_command as ProduceUnitCommand).unit_definition_id == definition_id:
			count += 1
	return count


func _enabled_unit_count(world: SimulationWorld, definition_id: StringName) -> int:
	var count := 0
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID and unit.definition_id == definition_id:
			count += 1
	return count
