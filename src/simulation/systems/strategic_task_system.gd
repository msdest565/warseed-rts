class_name StrategicTaskSystem
extends RefCounted

const INDUSTRIAL_AGENT_ID := 201
const BATTLEFIELD_AGENT_ID := 202
const DEVELOP_DELIVERY_TARGET := EconomySystem.HARVEST_AMOUNT
const DEFEND_HOLD_TICKS := 60
const RETREAT_SURVIVOR_RATIO := 0.5


func advance(world: SimulationWorld) -> void:
	var task_ids := world.tasks.keys()
	task_ids.sort()
	for task_id in task_ids:
		var task := world.tasks[task_id] as TaskState
		if task.lifecycle != TaskState.Lifecycle.EXECUTING:
			continue
		match task.kind:
			TaskState.Kind.DEVELOP_RESOURCE:
				_advance_develop_resource(task, world)
			TaskState.Kind.DEFEND_AREA:
				_advance_defend_area(task, world)
			TaskState.Kind.ATTACK_TARGET:
				_advance_attack_target(task, world)


func _advance_develop_resource(task: TaskState, world: SimulationWorld) -> void:
	if not world.ore_fields.has(task.target_entity_id):
		_block(task, world, TaskState.BlockedReason.INVALID_TARGET, "Ore field is no longer available")
		return
	var ore_field := world.ore_fields[task.target_entity_id] as OreFieldState
	var harvester := _first_enabled_participant(task, world, &"harvester")
	if harvester == null:
		_block(task, world, TaskState.BlockedReason.NO_AVAILABLE_UNITS, "No assigned harvester is available")
		return
	if task.phase == TaskState.Phase.PREPARING:
		var harvest := HarvestCommand.new(
			world.allocate_command_id(),
			SimulationWorld.LOCAL_PLAYER_ID,
			GameCommand.IssuerKind.AGENT,
			world.current_tick,
			harvester.entity_id,
			task.target_entity_id,
			SimulationWorld.PLAYER_COMMAND_CENTER_ID
		)
		_set_agent_context(harvest, task)
		var harvest_result := world.submit_command(harvest)
		if not harvest_result.is_accepted():
			_block(task, world, TaskState.BlockedReason.INVALID_TARGET, harvest_result.describe())
			return
		var factory := world.buildings[SimulationWorld.PLAYER_FACTORY_ID] as BuildingState
		if factory.production_definition_id.is_empty() and _count_definition(world, &"harvester") <= task.expected_unit_count:
			var production := ProduceUnitCommand.new(
				world.allocate_command_id(),
				SimulationWorld.LOCAL_PLAYER_ID,
				GameCommand.IssuerKind.AGENT,
				world.current_tick,
				factory.entity_id,
				&"harvester"
			)
			_set_agent_context(production, task)
			var production_result := world.submit_command(production)
			if not production_result.is_accepted():
				var reason := TaskState.BlockedReason.INSUFFICIENT_RESOURCES if production_result.reason == CommandValidationResult.Reason.INSUFFICIENT_ORE else TaskState.BlockedReason.PRODUCTION_UNAVAILABLE
				_block(task, world, reason, production_result.describe())
				return
		task.set_phase(TaskState.Phase.HARVESTING, world.current_tick, "Harvester cycling; second harvester queued")
		_emit_task_event(task, world)
		return

	var delivered := task.baseline_value - ore_field.ore_remaining >= DEVELOP_DELIVERY_TARGET
	var produced := _count_definition(world, &"harvester") > task.expected_unit_count
	task.progress_current = int(delivered) + int(produced)
	if delivered and not produced:
		task.set_phase(TaskState.Phase.PRODUCING, world.current_tick, "Ore delivered; waiting for second harvester")
	if delivered and produced:
		_complete(task, world, "Ore delivered and second harvester produced")


func _advance_defend_area(task: TaskState, world: SimulationWorld) -> void:
	if not world.formations.has(task.formation_id):
		_block(task, world, TaskState.BlockedReason.INVALID_TARGET, "Assigned formation is unavailable")
		return
	var formation := world.formations[task.formation_id] as FormationState
	var survivor_count := _enabled_participant_count(task, world)
	if survivor_count == 0:
		_block(task, world, TaskState.BlockedReason.INSUFFICIENT_PARTICIPANTS, "No defending units remain")
		return
	if formation.anchor_position.distance_to(task.target_position) > task.target_radius:
		if task.phase != TaskState.Phase.MUSTERING or not formation.is_moving:
			if not _submit_formation_move(task, formation, task.target_position, world):
				return
		task.set_phase(TaskState.Phase.MUSTERING, world.current_tick, "Moving inside defense radius")
		task.route = formation.path.duplicate()
		return

	var target_id := _nearest_visible_hostile(task.target_position, task.target_radius, world)
	if formation.order_target_entity_id != 0:
		var current_target := world.units.get(formation.order_target_entity_id) as UnitState
		if current_target == null or current_target.position.distance_to(task.target_position) > task.target_radius:
			_submit_formation_move(task, formation, task.target_position, world)
			task.set_phase(TaskState.Phase.RETURNING, world.current_tick, "Target crossed defense leash; returning")
			return
	if target_id != 0 and formation.order_target_entity_id == 0:
		var attack := AttackCommand.new(
			world.allocate_command_id(),
			SimulationWorld.LOCAL_PLAYER_ID,
			GameCommand.IssuerKind.AGENT,
			world.current_tick,
			formation.leader_entity_id,
			target_id,
			formation.formation_id
		)
		_set_agent_context(attack, task)
		world.submit_command(attack)
		task.set_phase(TaskState.Phase.ENGAGING, world.current_tick, "Engaging hostile inside defense radius")
	else:
		task.set_phase(TaskState.Phase.HOLDING, world.current_tick, "Holding position inside defense radius")
	task.progress_current += 1
	task.progress_target = DEFEND_HOLD_TICKS
	if task.progress_current >= DEFEND_HOLD_TICKS:
		_complete(task, world, "Defense interval completed without crossing leash")


func _advance_attack_target(task: TaskState, world: SimulationWorld) -> void:
	if not world.formations.has(task.formation_id):
		_block(task, world, TaskState.BlockedReason.INVALID_TARGET, "Assigned formation is unavailable")
		return
	var formation := world.formations[task.formation_id] as FormationState
	var survivors := _enabled_participant_count(task, world)
	var retreat_threshold := maxi(1, ceili(task.original_participant_entity_ids.size() * RETREAT_SURVIVOR_RATIO))
	if survivors < retreat_threshold and task.phase != TaskState.Phase.RETREATING:
		var retreat_position := (world.buildings[SimulationWorld.PLAYER_SUPPORT_ID] as BuildingState).position
		if _submit_formation_move(task, formation, retreat_position, world):
			task.set_phase(TaskState.Phase.RETREATING, world.current_tick, "Loss threshold reached; withdrawing")
			task.route = world.pathfinder.find_path(formation.anchor_position, retreat_position)
			_emit_task_event(task, world)
		return
	if task.phase == TaskState.Phase.RETREATING:
		if not formation.is_moving:
			_fail(task, world, "Formation withdrew after reaching the loss threshold")
		return
	var known_target := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID).get_unit(task.target_entity_id)
	if known_target == null:
		_block(task, world, TaskState.BlockedReason.INVALID_TARGET, "Target is not present in faction knowledge")
		return
	if not known_target.enabled:
		_complete(task, world, "Assigned hostile target destroyed")
		return
	if task.phase == TaskState.Phase.PREPARING:
		var attack := AttackCommand.new(
			world.allocate_command_id(),
			SimulationWorld.LOCAL_PLAYER_ID,
			GameCommand.IssuerKind.AGENT,
			world.current_tick,
			formation.leader_entity_id,
			task.target_entity_id,
			formation.formation_id
		)
		_set_agent_context(attack, task)
		var result := world.submit_command(attack)
		if not result.is_accepted():
			_block(task, world, TaskState.BlockedReason.INVALID_TARGET, result.describe())
			return
		task.set_phase(TaskState.Phase.ADVANCING, world.current_tick, "Mustered; advancing toward visible target")
		_emit_task_event(task, world)
		return
	task.route = formation.path.duplicate()
	task.set_phase(
		TaskState.Phase.ENGAGING if formation.engagement_state == FormationState.EngagementState.ENGAGING else TaskState.Phase.ADVANCING,
		world.current_tick,
		"Engaging target" if formation.engagement_state == FormationState.EngagementState.ENGAGING else "Advancing along assigned route"
	)


func _submit_formation_move(task: TaskState, formation: FormationState, destination: Vector2, world: SimulationWorld) -> bool:
	var move := FormationMoveCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.AGENT,
		world.current_tick,
		formation.leader_entity_id,
		formation.formation_id,
		destination
	)
	_set_agent_context(move, task)
	var result := world.submit_command(move)
	if not result.is_accepted():
		_block(task, world, TaskState.BlockedReason.PATH_UNAVAILABLE, result.describe())
		return false
	return true


func _nearest_visible_hostile(origin: Vector2, radius: float, world: SimulationWorld) -> int:
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var best_id := 0
	var best_distance := INF
	for contact in snapshot.units:
		if contact.faction_id == SimulationWorld.LOCAL_PLAYER_ID or not contact.enabled or not contact.is_visible_to_local_player:
			continue
		var distance := contact.position.distance_squared_to(origin)
		if distance <= radius * radius and (distance < best_distance or (is_equal_approx(distance, best_distance) and contact.entity_id < best_id)):
			best_id = contact.entity_id
			best_distance = distance
	return best_id


func _first_enabled_participant(task: TaskState, world: SimulationWorld, definition_id: StringName) -> UnitState:
	for entity_id in task.participant_entity_ids:
		var unit := world.units.get(entity_id) as UnitState
		if unit != null and unit.enabled and unit.definition_id == definition_id:
			return unit
	return null


func _enabled_participant_count(task: TaskState, world: SimulationWorld) -> int:
	var count := 0
	for entity_id in task.participant_entity_ids:
		var unit := world.units.get(entity_id) as UnitState
		if unit != null and unit.enabled:
			count += 1
	return count


func _count_definition(world: SimulationWorld, definition_id: StringName) -> int:
	var count := 0
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID and unit.definition_id == definition_id:
			count += 1
	return count


func _set_agent_context(command: GameCommand, task: TaskState) -> void:
	command.agent_id = task.agent_id
	command.task_id = task.task_id


func _block(task: TaskState, world: SimulationWorld, reason: TaskState.BlockedReason, detail: String) -> void:
	task.set_lifecycle(TaskState.Lifecycle.BLOCKED, world.current_tick, reason, detail)
	_emit_task_event(task, world)


func _fail(task: TaskState, world: SimulationWorld, detail: String) -> void:
	task.set_lifecycle(TaskState.Lifecycle.FAILED, world.current_tick, TaskState.BlockedReason.NONE, detail)
	task.set_phase(TaskState.Phase.DONE, world.current_tick, detail)
	world.release_task_participants(task)
	_emit_task_event(task, world)


func _complete(task: TaskState, world: SimulationWorld, detail: String) -> void:
	task.progress_current = task.progress_target
	task.set_lifecycle(TaskState.Lifecycle.COMPLETED, world.current_tick, TaskState.BlockedReason.NONE, detail)
	task.set_phase(TaskState.Phase.DONE, world.current_tick, detail)
	world.release_task_participants(task)
	match task.kind:
		TaskState.Kind.DEVELOP_RESOURCE:
			world.mission_state.developed_resource = true
		TaskState.Kind.DEFEND_AREA:
			world.mission_state.defended_area = true
		TaskState.Kind.ATTACK_TARGET:
			world.mission_state.attacked_target = true
	world.mission_state.update_completed(world.current_tick)
	_emit_task_event(task, world)


func _emit_task_event(task: TaskState, world: SimulationWorld) -> void:
	world.events.append(SimulationEvent.new(
		world.current_tick,
		SimulationEvent.Kind.TASK_STATE_CHANGED,
		task.task_id,
		"%s:%s:%s" % [TaskState.Lifecycle.keys()[task.lifecycle], TaskState.Phase.keys()[task.phase], task.last_detail]
	))
