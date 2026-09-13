class_name SimulationHost
extends Node

signal command_evaluated(result: CommandValidationResult)
signal player_action_recorded(descriptor: Dictionary)
signal campaign_record_changed(record: Dictionary)
signal campaign_concluded(record: Dictionary)
signal scenario_restarted(snapshot: WorldSnapshot)
signal grey_ridge_prebattle_opened(plan: ArmyPlan)
signal grey_ridge_battle_started(snapshot: WorldSnapshot)
signal tactical_pause_changed(paused: bool)
signal campaign_persistence_changed

const TICK_SECONDS := SimulationWorld.TICK_SECONDS

@export_enum("Legacy RTS", "Grey Ridge", "Broken Bridge", "Fog Forest", "Black Well") var scenario_kind: int = SimulationWorld.ScenarioKind.LEGACY_RTS

var world := SimulationWorld.new()
var previous_snapshot: WorldSnapshot
var current_snapshot: WorldSnapshot
var _accumulator: float = 0.0
var _tactical_paused: bool = false
var _timed_tick_count: int = 0
var _last_tick_usec: int = 0
var _total_tick_usec: int = 0
var _max_tick_usec: int = 0
var _campaign_record: Dictionary = {}
var campaign_error_key: StringName
var campaign_error_detail: String = ""
var _campaign_load_failed := false
var _campaign_save_pending := false
var _campaign_saved: bool = false
var _playtest_recorder := PlaytestSessionRecorder.new()
var _gameplay_report: GameplayObservabilityReport
var _gameplay_event_cursor: int = 0
var _gameplay_situation_projector := BattlefieldSituationProjector.new()
var _gameplay_command_situation_projector := CommandSituationProjector.new()
var _playtest_record_path := ""
var _playtest_session_id := ""
var _campaign_record_path := ArmyRosterStore.DEFAULT_PATH
var _playtest_record_directory := PlaytestSessionRecorder.DEFAULT_DIRECTORY
var _grey_ridge_battle_started: bool = true
var _grey_ridge_army_plan: ArmyPlan = ArmyPlan.grey_ridge_default()


func _ready() -> void:
	_playtest_session_id = ArmyRosterStore.active_playtest_session_id()
	_campaign_record_path = ArmyRosterStore.campaign_record_path_for_session(_playtest_session_id, get_scenario_id())
	_playtest_record_directory = ArmyRosterStore.playtest_record_directory_for_session(_playtest_session_id)
	if world.scenario_kind != scenario_kind:
		_campaign_record = {}
		if _is_card_battle() and ArmyRosterStore.runtime_persistence_allowed():
			_load_campaign_roster(_campaign_record_path)
		world = SimulationWorld.new(true, false, scenario_kind, _campaign_record, &"", _grey_ridge_army_plan)
	if _is_card_battle():
		_grey_ridge_army_plan = world.grey_ridge_army_plan.duplicate_plan()
	_grey_ridge_battle_started = not _is_card_battle()
	current_snapshot = world.create_snapshot()
	previous_snapshot = current_snapshot
	if _grey_ridge_battle_started:
		_start_playtest_session()


func _process(delta: float) -> void:
	if _tactical_paused:
		return
	if _is_card_battle() and not _grey_ridge_battle_started:
		return
	_accumulator += delta
	while _accumulator >= TICK_SECONDS:
		_accumulator -= TICK_SECONDS
		advance_tick()


func get_staff_assessment() -> StaffSituationSnapshot:
	# Use the same published, faction-filtered input as the HUD. No world access.
	return StaffSituationAssessor.new().assess(current_snapshot, SimulationWorld.LOCAL_PLAYER_ID)


func is_tactical_paused() -> bool:
	return _tactical_paused


func set_tactical_paused(paused: bool) -> void:
	if paused and (not _grey_ridge_battle_started or current_snapshot == null or (current_snapshot.outcome != null and current_snapshot.outcome.is_terminal())):
		return
	if _tactical_paused == paused:
		return
	_tactical_paused = paused
	tactical_pause_changed.emit(paused)


func submit_command(command: GameCommand) -> CommandValidationResult:
	if _is_card_battle() and not _grey_ridge_battle_started:
		var prebattle_result := CommandValidationResult.new(
			CommandValidationResult.Status.REJECTED,
			CommandValidationResult.Reason.SCENARIO_NOT_STARTED
		)
		command_evaluated.emit(prebattle_result)
		return prebattle_result
	var playtest_descriptor := _playtest_command_descriptor(command)
	var result := world.submit_command(command)
	if _is_card_battle():
		_playtest_recorder.record_command(command, result, playtest_descriptor)
		if _gameplay_report != null:
			_gameplay_report.record_command(command, result, _gameplay_command_descriptor(command, playtest_descriptor))
		if result.is_accepted() and not playtest_descriptor.is_empty():
			player_action_recorded.emit(playtest_descriptor.duplicate(true))
	command_evaluated.emit(result)
	return result


func create_deploy_unit_card_command(
	unit_card_id: StringName,
	deployment_position: Vector2,
	commander_id: StringName = &""
) -> DeployUnitCardCommand:
	return DeployUnitCardCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		unit_card_id,
		deployment_position,
		commander_id
	)


func create_support_order_command(
	support_kind: SupportOrderCommand.SupportKind,
	primary_region_id: StringName = &"",
	secondary_region_id: StringName = &"",
	unit_card_id: StringName = &""
) -> SupportOrderCommand:
	return SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, world.current_tick, support_kind,
		primary_region_id, secondary_region_id, unit_card_id
	)


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


func create_unit_card_control_command(
	unit_card_id: StringName,
	action: UnitCardControlCommand.Action
) -> UnitCardControlCommand:
	return UnitCardControlCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		world.current_tick,
		unit_card_id,
		action
	)


func create_commander_objective_command(
	commander_id: StringName,
	target_position: Vector2,
	route_points: PackedVector2Array = PackedVector2Array()
) -> CommanderOrderCommand:
	var target_region_id := _strategic_region_at(target_position)
	var command := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, target_position,
		target_region_id, CommanderState.Posture.BALANCED, route_points
	)
	command.hand_back_control = true
	return command


func _strategic_region_at(world_position: Vector2) -> StringName:
	var best_region_id: StringName = &""
	var best_distance_squared := INF
	for region_variant in world.strategic_regions.values():
		var region := region_variant as StrategicRegionState
		if region == null:
			continue
		var distance_squared := world_position.distance_squared_to(region.position)
		if distance_squared > region.radius * region.radius:
			continue
		if distance_squared < best_distance_squared or (is_equal_approx(distance_squared, best_distance_squared) \
				and (best_region_id.is_empty() or String(region.region_id) < String(best_region_id))):
			best_region_id = region.region_id
			best_distance_squared = distance_squared
	return best_region_id


func create_commander_posture_command(
	commander_id: StringName,
	posture: CommanderState.Posture
) -> CommanderOrderCommand:
	var command := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, CommanderOrderCommand.OrderKind.SET_POSTURE, Vector2.ZERO, &"", posture
	)
	command.hand_back_control = true
	return command


func create_high_level_intent_command(
	commander_id: StringName,
	objective_region_id: StringName,
	axis_region_id: StringName,
	posture: CommanderState.Posture,
	reserve_policy: CommanderState.ReservePolicy
) -> CommanderOrderCommand:
	var objective := world.strategic_regions.get(objective_region_id) as StrategicRegionState
	var axis := world.strategic_regions.get(axis_region_id) as StrategicRegionState
	var target_position := objective.position if objective != null else Vector2.INF
	var route := PackedVector2Array()
	if axis != null and objective != null and axis.region_id != objective.region_id:
		route.append(axis.position)
	var command_id := world.allocate_command_id()
	return CommanderOrderCommand.new(
		command_id, SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, CommanderOrderCommand.OrderKind.ASSIGN_INTENT,
		target_position, objective_region_id, posture, route,
		StringName("intent:%s:%08d" % [commander_id, command_id]), axis_region_id, reserve_policy
	)


func create_cancel_high_level_intent_command(commander_id: StringName) -> CommanderOrderCommand:
	return CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, CommanderOrderCommand.OrderKind.CANCEL_INTENT
	)


func create_equip_doctrine_command(
	commander_id: StringName,
	doctrine_id: StringName,
	slot_index: int = 0
) -> EquipDoctrineCommand:
	return EquipDoctrineCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander_id, doctrine_id, slot_index
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
	issuer_kind: GameCommand.IssuerKind = GameCommand.IssuerKind.PLAYER,
	route_points: PackedVector2Array = PackedVector2Array(),
	deployment_line_start: Vector2 = Vector2.ZERO,
	deployment_line_end: Vector2 = Vector2.ZERO,
	has_deployment_line: bool = false
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
		target_position,
		route_points,
		deployment_line_start,
		deployment_line_end,
		has_deployment_line
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
	if _tactical_paused:
		return current_snapshot
	if _is_card_battle() and not _grey_ridge_battle_started:
		return current_snapshot
	previous_snapshot = current_snapshot
	var started_usec := Time.get_ticks_usec()
	current_snapshot = world.advance_tick()
	if _is_card_battle():
		_playtest_recorder.observe_snapshot(current_snapshot)
		_observe_gameplay_report(current_snapshot)
	_last_tick_usec = Time.get_ticks_usec() - started_usec
	_timed_tick_count += 1
	_total_tick_usec += _last_tick_usec
	_max_tick_usec = maxi(_max_tick_usec, _last_tick_usec)
	_save_campaign_result_if_finished()
	return current_snapshot


func _save_campaign_result_if_finished() -> void:
	if _campaign_saved or not _is_card_battle() or current_snapshot == null:
		return
	if current_snapshot.outcome == null or not current_snapshot.outcome.is_terminal():
		return
	_campaign_record = ArmyRosterStore.build_battle_record(current_snapshot, _campaign_record, get_scenario_id())
	_campaign_saved = true
	if _gameplay_report != null:
		_observe_gameplay_report(current_snapshot, true)
		_gameplay_report.finish(current_snapshot)
	_playtest_recorder.finish(current_snapshot, _campaign_record, world.events)
	_persist_playtest_summary()
	_persist_campaign_record()
	ArmyRosterStore.apply_to_world(world, _campaign_record)
	current_snapshot = world.create_snapshot()
	campaign_record_changed.emit(get_campaign_record())
	campaign_concluded.emit(get_campaign_record())


func get_campaign_record() -> Dictionary:
	return _campaign_record.duplicate(true)


func get_playtest_summary() -> Dictionary:
	return _playtest_recorder.create_summary()


func get_gameplay_observability_report() -> Dictionary:
	return {} if _gameplay_report == null else _gameplay_report.create_report().duplicate(true)


func get_playtest_record_path() -> String:
	return _playtest_record_path


func record_playtest_ui_event(event_type: String, subject: StringName = &"") -> void:
	if _is_card_battle():
		_playtest_recorder.record_ui_event(event_type, subject, world.current_tick)


func record_gameplay_exception_action(exception_id: StringName, action: String, accepted: bool) -> void:
	if _is_card_battle() and _gameplay_report != null:
		_gameplay_report.record_exception_action(exception_id, action, world.current_tick, accepted)


func replenish_unit_card(unit_card_id: StringName) -> bool:
	if has_campaign_error():
		return false
	var next_record := _campaign_record.duplicate(true)
	if not ArmyRosterStore.replenish_card(next_record, unit_card_id):
		return false
	if not _write_campaign_record(next_record):
		return false
	_campaign_record = next_record
	_campaign_record_updated()
	return true


func replenish_unit_card_as_much_as_possible(unit_card_id: StringName) -> int:
	if has_campaign_error():
		return 0
	var next_record := _campaign_record.duplicate(true)
	var restored := ArmyRosterStore.replenish_card_as_much_as_possible(next_record, unit_card_id)
	if restored > 0:
		if not _write_campaign_record(next_record):
			return 0
		_campaign_record = next_record
		_campaign_record_updated()
	return restored


func reset_grey_ridge_campaign_record() -> bool:
	if not _is_card_battle() or _grey_ridge_battle_started:
		return false
	if ArmyRosterStore.runtime_persistence_allowed() and FileAccess.file_exists(_campaign_record_path):
		if ArmyRosterStore.archive_record(_campaign_record_path).is_empty():
			return false
	_campaign_record = {}
	_campaign_load_failed = false
	_campaign_save_pending = false
	_set_campaign_error(&"", "")
	world = SimulationWorld.new(true, false, scenario_kind, {}, &"", _grey_ridge_army_plan)
	current_snapshot = world.create_snapshot()
	previous_snapshot = current_snapshot
	_campaign_saved = false
	_gameplay_report = null
	_gameplay_event_cursor = 0
	campaign_record_changed.emit(get_campaign_record())
	scenario_restarted.emit(current_snapshot)
	return true


func award_collective_commendation(unit_card_id: StringName) -> bool:
	return apply_unit_card_growth(unit_card_id, ArmyRosterStore.HONOR_COLLECTIVE_COMMENDATION)


func install_reinforced_side_skirts(unit_card_id: StringName) -> bool:
	return apply_unit_card_growth(unit_card_id, ArmyRosterStore.EQUIPMENT_REINFORCED_SIDE_SKIRTS)


func apply_unit_card_growth(unit_card_id: StringName, growth_id: StringName) -> bool:
	if has_campaign_error():
		return false
	var next_record := _campaign_record.duplicate(true)
	if not ArmyRosterStore.apply_growth(next_record, unit_card_id, growth_id):
		return false
	if not _write_campaign_record(next_record):
		return false
	_campaign_record = next_record
	_campaign_record_updated()
	var descriptor := {
		"category": "growth",
		"action": "apply",
		"subject": String(unit_card_id),
		"growth_id": String(growth_id),
	}
	player_action_recorded.emit(descriptor)
	record_playtest_ui_event("growth_applied", growth_id)
	return true


func restart_grey_ridge() -> bool:
	if not _is_card_battle() or has_campaign_error():
		return false
	set_tactical_paused(false)
	_playtest_recorder.mark_second_battle_requested(world.current_tick)
	_persist_playtest_summary()
	_grey_ridge_battle_started = false
	world = SimulationWorld.new(true, false, scenario_kind, _campaign_record, &"", _grey_ridge_army_plan)
	current_snapshot = world.create_snapshot()
	previous_snapshot = current_snapshot
	_accumulator = 0.0
	_timed_tick_count = 0
	_last_tick_usec = 0
	_total_tick_usec = 0
	_max_tick_usec = 0
	_campaign_saved = false
	_gameplay_report = null
	_gameplay_event_cursor = 0
	scenario_restarted.emit(current_snapshot)
	grey_ridge_prebattle_opened.emit(_grey_ridge_army_plan.duplicate_plan())
	return true


func start_grey_ridge(plan: ArmyPlan, prebattle_metrics: Dictionary = {}) -> bool:
	if not _is_card_battle() or plan == null:
		return false
	if not get_grey_ridge_army_plan_errors(plan).is_empty():
		return false
	set_tactical_paused(false)
	_grey_ridge_army_plan = plan.duplicate_plan()
	world = SimulationWorld.new(true, false, scenario_kind, _campaign_record, &"", _grey_ridge_army_plan)
	current_snapshot = world.create_snapshot()
	previous_snapshot = current_snapshot
	_accumulator = 0.0
	_timed_tick_count = 0
	_last_tick_usec = 0
	_total_tick_usec = 0
	_max_tick_usec = 0
	_campaign_saved = false
	_grey_ridge_battle_started = true
	_start_playtest_session(prebattle_metrics)
	scenario_restarted.emit(current_snapshot)
	grey_ridge_battle_started.emit(current_snapshot)
	return true


func is_grey_ridge_battle_started() -> bool:
	return _grey_ridge_battle_started


func get_grey_ridge_army_plan() -> ArmyPlan:
	return _grey_ridge_army_plan.duplicate_plan()


func get_grey_ridge_army_plan_errors(plan: ArmyPlan) -> Array[StringName]:
	if has_campaign_error():
		return [campaign_error_key]
	if not _is_card_battle() or plan == null:
		return [&"ARMY_PLAN_ERROR_UNAVAILABLE"]
	return world.get_grey_ridge_army_plan_errors(plan)


func _campaign_record_updated() -> void:
	ArmyRosterStore.apply_to_world(world, _campaign_record)
	current_snapshot = world.create_snapshot()
	previous_snapshot = current_snapshot
	campaign_record_changed.emit(get_campaign_record())


func _persist_campaign_record() -> void:
	_campaign_save_pending = not _write_campaign_record(_campaign_record)


func _write_campaign_record(record: Dictionary) -> bool:
	if _campaign_load_failed:
		return false
	if ArmyRosterStore.runtime_persistence_allowed():
		var saved := ArmyRosterStore.save_record_result(record, _campaign_record_path)
		if not saved.is_success():
			_set_campaign_error(&"ROSTER_SAVE_FAILED", "; ".join(saved.errors))
			return false
	_set_campaign_error(&"", "")
	return true


func has_campaign_error() -> bool:
	return not campaign_error_key.is_empty()


func _load_campaign_roster(path: String) -> bool:
	var loaded := ArmyRosterStore.load_record_result(path, ArmyRosterStore.runtime_persistence_allowed())
	if loaded.status == ArmyRosterResult.Status.FAILED:
		_campaign_load_failed = true
		_set_campaign_error(&"ROSTER_LOAD_FAILED", "; ".join(loaded.errors))
		return false
	_campaign_load_failed = false
	_campaign_record = loaded.record
	_set_campaign_error(&"", "")
	return true


func retry_campaign_save() -> bool:
	if _campaign_load_failed:
		return false
	if _campaign_save_pending:
		_persist_campaign_record()
		return not _campaign_save_pending
	# A failed prebattle purchase left both memory and disk unchanged.
	return _write_campaign_record(_campaign_record)


func _set_campaign_error(key: StringName, detail: String) -> void:
	campaign_error_key = key
	campaign_error_detail = detail
	campaign_persistence_changed.emit()


func _start_playtest_session(prebattle_metrics: Dictionary = {}) -> void:
	if not _is_card_battle():
		return
	_playtest_recorder = PlaytestSessionRecorder.new()
	_playtest_record_path = ""
	_playtest_recorder.start(
		current_snapshot,
		int(_campaign_record.get("battle_count", 0)) + 1,
		world.enemy_opening_plan_id,
		prebattle_metrics,
		_playtest_session_id,
		_playtest_record_directory,
		get_scenario_id()
	)
	_start_gameplay_report()


func _start_gameplay_report() -> void:
	_gameplay_report = GameplayObservabilityReport.new(
		get_scenario_id(), world.enemy_opening_plan_id, &"live_player", 0,
		SimulationWorld.LOCAL_PLAYER_ID,
		world.battle_definition.time_limit_ticks if world.battle_definition != null else 0
	)
	_gameplay_event_cursor = 0
	_gameplay_report.start(current_snapshot)
	_observe_gameplay_report(current_snapshot, true)


func _observe_gameplay_report(snapshot: WorldSnapshot, force_situation: bool = false) -> void:
	if _gameplay_report == null or snapshot == null:
		return
	var new_events: Array[SimulationEvent] = []
	for index in range(_gameplay_event_cursor, world.events.size()):
		new_events.append(world.events[index])
	_gameplay_report.observe(snapshot, new_events)
	_gameplay_event_cursor = world.events.size()
	if not force_situation and snapshot.tick % 10 != 0 and not snapshot.outcome.is_terminal():
		return
	var battle := world.battle_definition
	var bounds := battle.battlefield_bounds if battle != null else SimulationWorld.BATTLEFIELD_BOUNDS
	var base_interval := battle.base_supply_interval_ticks if battle != null else BattlefieldSituationProjector.DEFAULT_BASE_SUPPLY_INTERVAL_TICKS
	var region_interval := battle.region_settlement_interval_ticks if battle != null else BattlefieldSituationProjector.DEFAULT_REGION_SETTLEMENT_INTERVAL_TICKS
	var support_costs := {}
	if battle != null:
		for support in battle.support_abilities:
			support_costs[String(support.support_id)] = support.supply_cost
	var situation := _gameplay_situation_projector.project(
		snapshot, SimulationWorld.LOCAL_PLAYER_ID, bounds,
		base_interval, region_interval, support_costs
	)
	if situation == null:
		return
	var command_situation := _gameplay_command_situation_projector.project(
		snapshot, situation, SimulationWorld.LOCAL_PLAYER_ID
	)
	if command_situation != null:
		_gameplay_report.observe_command_situation(command_situation)


func _is_card_battle() -> bool:
	return SimulationWorld.is_card_battle_kind(scenario_kind)


func get_scenario_id() -> StringName:
	return world.get_scenario_id() if world != null and world.scenario_kind == scenario_kind else SimulationWorld.scenario_id_for_kind(scenario_kind)


func _persist_playtest_summary() -> void:
	if not ArmyRosterStore.runtime_persistence_allowed():
		return
	if _playtest_record_path.is_empty():
		_playtest_record_path = _playtest_recorder.default_archive_path()
	_playtest_recorder.save_to_path(_playtest_record_path)
	_playtest_recorder.save_to_path(_playtest_recorder.latest_record_path())


func _playtest_command_descriptor(command: GameCommand) -> Dictionary:
	if command == null or command.issuer_kind != GameCommand.IssuerKind.PLAYER:
		return {}
	if command is CommanderOrderCommand:
		var commander_command := command as CommanderOrderCommand
		var action := "objective"
		if commander_command.order_kind == CommanderOrderCommand.OrderKind.SET_POSTURE:
			action = "posture"
		elif commander_command.order_kind == CommanderOrderCommand.OrderKind.ASSIGN_INTENT:
			action = "intent"
		elif commander_command.order_kind == CommanderOrderCommand.OrderKind.CANCEL_INTENT:
			action = "cancel_intent"
		return {
			"category": "commander", "subject": String(commander_command.commander_id),
			"action": action,
			"target_region_id": String(commander_command.target_region_id),
			"axis_region_id": String(commander_command.main_axis_region_id),
			"reserve_policy": CommanderState.ReservePolicy.keys()[commander_command.reserve_policy],
			"counts_as_replan": commander_command.order_kind in [CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, CommanderOrderCommand.OrderKind.ASSIGN_INTENT],
			"uses_intel": commander_command.order_kind in [CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, CommanderOrderCommand.OrderKind.ASSIGN_INTENT],
		}
	if command is EquipDoctrineCommand:
		return {"category": "commander", "subject": String((command as EquipDoctrineCommand).commander_id), "action": "doctrine"}
	if command is DeployUnitCardCommand:
		return {"category": "unit_card", "subject": String((command as DeployUnitCardCommand).unit_card_id), "action": "deploy", "uses_intel": true}
	if command is UnitCardControlCommand:
		var control := command as UnitCardControlCommand
		var action := "takeover"
		if control.action == UnitCardControlCommand.Action.RETURN_TO_COMMANDER:
			action = "return_to_commander"
		elif control.action == UnitCardControlCommand.Action.STAY_MANUAL:
			action = "stay_manual"
		return {"category": "unit_card", "subject": String(control.unit_card_id), "action": action}
	if command is SupportOrderCommand:
		var support := command as SupportOrderCommand
		var action := ""
		match support.support_kind:
			SupportOrderCommand.SupportKind.AIR_RECON:
				action = "air_recon"
			SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY:
				action = "fortify"
			SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
				action = "field_reinforcement"
		return {"category": "support", "subject": String(support.unit_card_id), "action": action, "uses_intel": true}
	var formation_id := 0
	if command is FormationMoveCommand:
		formation_id = (command as FormationMoveCommand).formation_id
	elif command is StopCommand:
		formation_id = (command as StopCommand).formation_id
	elif command is AttackCommand:
		formation_id = (command as AttackCommand).formation_id
	if formation_id == 0:
		return {}
	var unit_card := world._unit_card_for_formation(formation_id)
	if unit_card == null:
		return {}
	var starts_takeover := unit_card.control_state not in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.PLAYER_CONTROLLED]
	var descriptor := {
		"category": "unit_card", "subject": String(unit_card.definition.definition_id),
		"action": "direct_order_takeover" if starts_takeover else "direct_order",
		"counts_as_replan": true, "uses_intel": true,
	}
	if command is FormationMoveCommand:
		var route_command := command as FormationMoveCommand
		descriptor["route_planned"] = not route_command.route_points.is_empty() or route_command.has_deployment_line
	return descriptor


func _gameplay_command_descriptor(command: GameCommand, playtest_descriptor: Dictionary) -> Dictionary:
	var descriptor := playtest_descriptor.duplicate(true)
	var category := String(descriptor.get("category", "other"))
	var subject := String(descriptor.get("subject", ""))
	descriptor["reason_key"] = "player_%s" % String(descriptor.get("action", command.get_class())).to_lower()
	descriptor["actor_id"] = subject if category == "commander" else "player"
	if category == "unit_card" or category == "support":
		descriptor["card_id"] = subject
	descriptor["is_correction"] = bool(descriptor.get("counts_as_replan", false))
	if command is UnitCardControlCommand:
		var control := command as UnitCardControlCommand
		descriptor["action"] = "card_control"
		descriptor["control_action"] = control.action
	return descriptor


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


func set_headquarters_directive(directive: StrategicHeadquarters.Directive) -> bool:
	return world.set_headquarters_directive(directive)


func get_headquarters_directive() -> StrategicHeadquarters.Directive:
	return world.get_headquarters_directive()


func get_headquarters_directive_key() -> StringName:
	return world.get_headquarters_directive_key()


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
