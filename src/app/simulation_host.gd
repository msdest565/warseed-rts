class_name SimulationHost
extends Node

signal command_evaluated(result: CommandValidationResult)

const TICK_SECONDS := SimulationWorld.TICK_SECONDS

var world := SimulationWorld.new()
var previous_snapshot: WorldSnapshot
var current_snapshot: WorldSnapshot
var _accumulator: float = 0.0
var _timed_tick_count: int = 0
var _last_tick_usec: int = 0
var _total_tick_usec: int = 0
var _max_tick_usec: int = 0


func _ready() -> void:
	current_snapshot = world.create_snapshot()
	previous_snapshot = current_snapshot


func _process(delta: float) -> void:
	_accumulator += delta
	while _accumulator >= TICK_SECONDS:
		_accumulator -= TICK_SECONDS
		advance_tick()


func submit_command(command: GameCommand) -> CommandValidationResult:
	var result := world.submit_command(command)
	command_evaluated.emit(result)
	return result


func create_unit_disposition_command(
	entity_id: int,
	disposition: UnitDispositionCommand.Disposition,
	destination_formation_id: int = 0
) -> UnitDispositionCommand:
	return UnitDispositionCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		entity_id,
		disposition,
		destination_formation_id
	)


func create_move_command(
	entity_id: int,
	target_position: Vector2,
	issuer_kind: GameCommand.IssuerKind = GameCommand.IssuerKind.PLAYER
) -> MoveCommand:
	return MoveCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		issuer_kind,
		world.current_tick,
		entity_id,
		target_position
	)


func create_formation_move_command(
	formation_id: int,
	target_position: Vector2,
	issuer_kind: GameCommand.IssuerKind = GameCommand.IssuerKind.PLAYER
) -> FormationMoveCommand:
	var formation := world.formations.get(formation_id) as FormationState
	var leader_entity_id := formation.leader_entity_id if formation != null else 0
	return FormationMoveCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		issuer_kind,
		world.current_tick,
		leader_entity_id,
		formation_id,
		target_position
	)


func create_stop_command(entity_id: int, formation_id: int = 0) -> StopCommand:
	var leader_id := entity_id
	if formation_id != 0:
		var formation := world.formations.get(formation_id) as FormationState
		leader_id = formation.leader_entity_id if formation != null else entity_id
	return StopCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		leader_id,
		formation_id
	)


func create_attack_move_command(formation_id: int, target_position: Vector2, entity_id: int = 0) -> AttackMoveCommand:
	var formation := world.formations.get(formation_id) as FormationState
	var leader_entity_id := formation.leader_entity_id if formation != null else entity_id
	return AttackMoveCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		leader_entity_id,
		formation_id,
		target_position
	)


func create_attack_command(
	entity_id: int,
	attack_target_entity_id: int,
	formation_id: int = 0
) -> AttackCommand:
	var attacker_id := entity_id
	if formation_id != 0:
		var formation := world.formations.get(formation_id) as FormationState
		attacker_id = formation.leader_entity_id if formation != null else entity_id
	return AttackCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		attacker_id,
		attack_target_entity_id,
		formation_id
	)


func create_harvest_command(harvester_entity_id: int, ore_field_entity_id: int, refinery_entity_id: int) -> HarvestCommand:
	return HarvestCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		harvester_entity_id,
		ore_field_entity_id,
		refinery_entity_id
	)


func create_produce_unit_command(factory_entity_id: int, unit_definition_id: StringName) -> ProduceUnitCommand:
	return ProduceUnitCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		factory_entity_id,
		unit_definition_id
	)


func create_cancel_production_command(building_entity_id: int, queue_index: int = 0) -> CancelProductionCommand:
	return CancelProductionCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		building_entity_id,
		queue_index
	)


func create_set_rally_point_command(building_entity_id: int, rally_position: Vector2) -> SetRallyPointCommand:
	return SetRallyPointCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		building_entity_id,
		rally_position
	)


func create_build_building_command(engineer_entity_id: int, building_definition_id: StringName, build_position: Vector2) -> BuildBuildingCommand:
	return BuildBuildingCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		engineer_entity_id,
		building_definition_id,
		snap_build_position(build_position)
	)


func snap_build_position(world_position: Vector2) -> Vector2:
	return world.logic_grid.cell_to_world(world.logic_grid.world_to_cell(world_position))


func get_build_placement_preview(engineer_entity_id: int, building_definition_id: StringName, world_position: Vector2) -> Dictionary:
	var snapped_position := snap_build_position(world_position)
	var definition := SimulationWorld.BUILDING_CATALOG.get_building(building_definition_id)
	if definition == null:
		return {"position": snapped_position, "footprint_size": Vector2i.ONE, "valid": false, "reason": CommandValidationResult.Reason.INVALID_DEFINITION, "engineer_position": snapped_position}
	var command := BuildBuildingCommand.new(
		0, SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick,
		engineer_entity_id, building_definition_id, snapped_position
	)
	var result := world.validate_command(command)
	var engineer := world.units.get(engineer_entity_id) as UnitState
	return {
		"position": snapped_position,
		"footprint_size": definition.footprint_size,
		"valid": result.is_accepted(),
		"reason": result.reason,
		"engineer_position": engineer.position if engineer != null else snapped_position,
	}


func create_repair_building_command(engineer_entity_id: int, building_entity_id: int) -> RepairBuildingCommand:
	return RepairBuildingCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		engineer_entity_id,
		building_entity_id
	)


func create_strategic_order_command(
	order_kind: StrategicOrderCommand.OrderKind,
	formation_id: int,
	objective_entity_id: int,
	target_position: Vector2,
	target_radius: float = 0.0,
	participant_entity_ids: Array[int] = []
) -> StrategicOrderCommand:
	var command := StrategicOrderCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		world.current_tick,
		order_kind,
		formation_id,
		objective_entity_id,
		target_position,
		target_radius
	)
	command.participant_entity_ids.assign(participant_entity_ids)
	command.participant_entity_ids.sort()
	return command


func create_task_control_command(task_id: int, action: TaskControlCommand.Action) -> TaskControlCommand:
	return TaskControlCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		world.current_tick,
		task_id,
		action
	)


func advance_tick() -> WorldSnapshot:
	previous_snapshot = current_snapshot
	var started_usec := Time.get_ticks_usec()
	current_snapshot = world.advance_tick()
	_last_tick_usec = Time.get_ticks_usec() - started_usec
	_timed_tick_count += 1
	_total_tick_usec += _last_tick_usec
	_max_tick_usec = maxi(_max_tick_usec, _last_tick_usec)
	return current_snapshot


func get_true_state_snapshot_for_debug() -> WorldSnapshot:
	return world.create_true_state_snapshot()


func get_faction_snapshot(faction_id: int) -> WorldSnapshot:
	return world.create_faction_snapshot(faction_id)


func get_tick_timing_snapshot() -> HostTickTimingSnapshot:
	return HostTickTimingSnapshot.new(
		_timed_tick_count,
		_last_tick_usec,
		_total_tick_usec,
		_max_tick_usec
	)


func get_interpolation_alpha() -> float:
	return clampf(_accumulator / TICK_SECONDS, 0.0, 1.0)


func get_queue_size() -> int:
	return world.command_queue.size()


func get_enemy_phase_name() -> String:
	return world.enemy_raid_agent.phase_name()


func get_enemy_difficulty_name() -> String:
	return world.enemy_raid_agent.difficulty_name()


func get_enemy_decision_summary() -> String:
	return world.enemy_raid_agent.decision_summary()


func get_headquarters_decision_key() -> StringName:
	return world.get_headquarters_decision_key()


func get_headquarters_budget_snapshot() -> Dictionary:
	return world.get_headquarters_budget_snapshot()


func set_enemy_difficulty(difficulty: EnemyDifficultyProfile.Difficulty) -> void:
	world.set_enemy_difficulty(difficulty)


func get_enemy_difficulty() -> EnemyDifficultyProfile.Difficulty:
	return world.get_enemy_difficulty()


func set_agent_authorization(agent_id: int, authorization: AgentPolicy.Authorization) -> bool:
	return world.set_agent_authorization(agent_id, authorization)


func get_agent_authorization(agent_id: int) -> AgentPolicy.Authorization:
	return world.get_agent_authorization(agent_id)


func get_agent_recommendation_key(agent_id: int) -> StringName:
	return world.get_agent_recommendation_key(agent_id)
