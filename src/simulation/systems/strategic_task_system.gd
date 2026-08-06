class_name StrategicTaskSystem
extends RefCounted

const INDUSTRIAL_AGENT_ID := 201
const BATTLEFIELD_AGENT_ID := 202
const DEVELOP_DELIVERY_TARGET := EconomySystem.HARVEST_AMOUNT
const DEFEND_HOLD_TICKS := 60
const SCOUT_OBSERVE_TICKS := 30
const SCOUT_STALLED_REPLAN_TICKS := 30
const SCOUT_PROGRESS_DISTANCE := 8.0
const SCOUT_MAX_REPLAN_ATTEMPTS := 3
const SCOUT_DANGER_RADIUS := 384.0
const SCOUT_EVADE_DISTANCE := 448.0
const SCOUT_EVADE_REPLAN_TICKS := 15
const SCOUT_THREAT_BUFFER := 96.0
const RETREAT_SURVIVOR_RATIO := 0.5


func advance(world: SimulationWorld) -> void:
	var task_ids := world.tasks.keys()
	task_ids.sort()
	for task_id in task_ids:
		var task := world.tasks[task_id] as TaskState
		if task.kind != TaskState.Kind.FORMATION_MOVE_TEST and task.lifecycle in [TaskState.Lifecycle.WAITING, TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING, TaskState.Lifecycle.PAUSED, TaskState.Lifecycle.BLOCKED] and _allows_reinforcement_enrollment(task, world):
			var enrolled := _enroll_compatible_units(task, world)
			if enrolled > 0 and task.lifecycle == TaskState.Lifecycle.BLOCKED and task.blocked_reason in [TaskState.BlockedReason.NO_AVAILABLE_UNITS, TaskState.BlockedReason.INSUFFICIENT_PARTICIPANTS, TaskState.BlockedReason.PARTICIPANT_OVERRIDDEN]:
				task.set_lifecycle(TaskState.Lifecycle.EXECUTING, world.current_tick)
				task.set_phase(TaskState.Phase.PREPARING, world.current_tick, "Reinforcements assigned; task resumed")
				_emit_task_event(task, world)
		if task.lifecycle == TaskState.Lifecycle.BLOCKED:
			_try_resume_blocked_development(task, world)
		if task.lifecycle != TaskState.Lifecycle.EXECUTING:
			continue
		match task.kind:
			TaskState.Kind.DEVELOP_RESOURCE:
				_advance_develop_resource(task, world)
			TaskState.Kind.DEFEND_AREA:
				_advance_defend_area(task, world)
			TaskState.Kind.ATTACK_TARGET:
				_advance_attack_target(task, world)
			TaskState.Kind.SCOUT_AREA:
				_advance_scout_area(task, world)


func _advance_develop_resource(task: TaskState, world: SimulationWorld) -> void:
	if not world.ore_fields.has(task.target_entity_id):
		_block(task, world, TaskState.BlockedReason.INVALID_TARGET, "Ore field is no longer available")
		return
	var ore_field := world.ore_fields[task.target_entity_id] as OreFieldState
	var harvester := _first_enabled_participant(task, world, &"harvester")
	if harvester == null:
		_block(task, world, TaskState.BlockedReason.NO_AVAILABLE_UNITS, "No assigned harvester is available")
		return
	var refinery := _find_faction_building(world, task.faction_id, &"command_center", true)
	if refinery == null:
		_block(task, world, TaskState.BlockedReason.PRODUCTION_UNAVAILABLE, "No operational refinery is available")
		return
	_ensure_harvest_orders(task, refinery, world)
	if task.phase == TaskState.Phase.PREPARING:
		var factory := refinery
		if factory == null:
			_block(task, world, TaskState.BlockedReason.PRODUCTION_UNAVAILABLE, "No operational command center is available")
			return
		var production_is_committed := _count_committed_definition(world, task.faction_id, &"harvester") > task.expected_unit_count
		if not task.requires_proactive_authorization and not production_is_committed:
			if factory.production_count() >= BuildingState.MAX_PRODUCTION_QUEUE_SIZE:
				_block(task, world, TaskState.BlockedReason.PRODUCTION_UNAVAILABLE, "Command-center production queue is full")
				return
			var production := ProduceUnitCommand.new(
				world.allocate_command_id(),
				task.faction_id,
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
		var detail := "Harvester cycling; production coordinated by Strategic Headquarters" if task.requires_proactive_authorization else "Harvester cycling; second harvester queued"
		task.set_phase(TaskState.Phase.HARVESTING, world.current_tick, detail)
		_emit_task_event(task, world)
		return

	var delivered := task.baseline_value - ore_field.ore_remaining >= DEVELOP_DELIVERY_TARGET
	var produced := _count_definition(world, task.faction_id, &"harvester") > task.expected_unit_count
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

	var target_id := _nearest_visible_hostile(task.target_position, task.target_radius, world, task.faction_id)
	if formation.order_target_entity_id != 0:
		var current_target := world.units.get(formation.order_target_entity_id) as UnitState
		if current_target == null or current_target.position.distance_to(task.target_position) > task.target_radius:
			_submit_formation_move(task, formation, task.target_position, world)
			task.set_phase(TaskState.Phase.RETURNING, world.current_tick, "Target crossed defense leash; returning")
			return
	if target_id != 0 and formation.order_target_entity_id == 0:
		var attack := AttackCommand.new(
			world.allocate_command_id(),
			task.faction_id,
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
		var retreat_building := _find_faction_building(world, task.faction_id, &"forward_support_station", true)
		if retreat_building == null:
			retreat_building = _find_faction_building(world, task.faction_id, &"command_center", true)
		if retreat_building == null:
			_fail(task, world, "No surviving retreat destination")
			return
		var retreat_position := retreat_building.position
		if _submit_formation_move(task, formation, retreat_position, world):
			task.set_phase(TaskState.Phase.RETREATING, world.current_tick, "Loss threshold reached; withdrawing")
			task.route = world.pathfinder.find_path(formation.anchor_position, retreat_position)
			_emit_task_event(task, world)
		return
	if task.phase == TaskState.Phase.RETREATING:
		if not formation.is_moving:
			_fail(task, world, "Formation withdrew after reaching the loss threshold")
		return
	var faction_snapshot := world.create_faction_snapshot(task.faction_id)
	var known_unit := faction_snapshot.get_unit(task.target_entity_id)
	var known_building := faction_snapshot.get_building(task.target_entity_id)
	if known_unit == null and known_building == null:
		_block(task, world, TaskState.BlockedReason.INVALID_TARGET, "Target is not present in faction knowledge")
		return
	var target_enabled := known_unit.enabled if known_unit != null else known_building.enabled
	if not target_enabled:
		_complete(task, world, "Assigned hostile target destroyed")
		return
	if task.phase == TaskState.Phase.PREPARING:
		var attack := AttackCommand.new(
			world.allocate_command_id(),
			task.faction_id,
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


func _advance_scout_area(task: TaskState, world: SimulationWorld) -> void:
	if not world.formations.has(task.formation_id):
		_block(task, world, TaskState.BlockedReason.INVALID_TARGET, "Assigned scout formation is unavailable")
		return
	var formation := world.formations[task.formation_id] as FormationState
	var scout := _first_enabled_participant(task, world, &"scout_vehicle")
	if scout == null:
		_block(task, world, TaskState.BlockedReason.INSUFFICIENT_PARTICIPANTS, "No scout units remain")
		return
	_update_scout_intelligence(task, world)
	var threat := _nearest_visible_hostile_contact(scout.position, world, task.faction_id)
	if task.requires_proactive_authorization and threat != null and scout.position.distance_to(threat.position) <= maxf(SCOUT_DANGER_RADIUS, threat.attack_range + SCOUT_THREAT_BUFFER):
		if task.phase != TaskState.Phase.EVADING or not formation.is_moving or world.current_tick - task.last_evasion_tick >= SCOUT_EVADE_REPLAN_TICKS:
			var safe_target := _find_scout_evasion_target(scout.position, threat.position, task.faction_id, world)
			if not safe_target.is_equal_approx(scout.position):
				_submit_scout_evasion(task, formation, safe_target, world)
				task.last_evasion_tick = world.current_tick
				task.set_phase(TaskState.Phase.EVADING, world.current_tick, "Enemy contact detected; evading toward a reachable safe area")
				task.route = world.pathfinder.find_path(scout.position, safe_target)
		return
	if task.phase == TaskState.Phase.EVADING:
		if formation.is_moving:
			return
		var resumed_target := world.find_reachable_scout_target(task.faction_id, scout.position, task.target_position)
		if resumed_target.is_equal_approx(scout.position):
			_complete(task, world, "Reconnaissance ended after safely withdrawing from enemy contact")
			return
		task.target_position = resumed_target
		task.last_progress_position = scout.position
		task.ticks_without_progress = 0
		task.replan_attempts = 0
		task.set_phase(TaskState.Phase.PREPARING, world.current_tick, "Threat cleared; resuming reconnaissance on a new frontier")
	if formation.anchor_position.distance_to(task.target_position) > task.target_radius:
		if formation.is_moving:
			if scout.position.distance_to(task.last_progress_position) >= SCOUT_PROGRESS_DISTANCE:
				task.last_progress_position = scout.position
				task.ticks_without_progress = 0
			else:
				task.ticks_without_progress += 1
		if task.ticks_without_progress >= SCOUT_STALLED_REPLAN_TICKS:
			task.replan_attempts += 1
			task.ticks_without_progress = 0
			var replacement := world.find_reachable_scout_target(task.faction_id, scout.position, task.target_position)
			if replacement.is_equal_approx(scout.position) or task.replan_attempts > SCOUT_MAX_REPLAN_ATTEMPTS:
				_block(task, world, TaskState.BlockedReason.PATH_UNAVAILABLE, "Scout could not make progress toward a reachable observation area")
				return
			task.target_position = replacement
			task.last_progress_position = scout.position
			task.set_phase(TaskState.Phase.PREPARING, world.current_tick, "Scout route stalled; selecting a new observation area")
		if task.phase != TaskState.Phase.MUSTERING or not formation.is_moving:
			if not _submit_formation_move(task, formation, task.target_position, world):
				return
		task.set_phase(TaskState.Phase.MUSTERING, world.current_tick, "Scout formation moving to observation area")
		task.route = formation.path.duplicate()
		return
	if formation.is_moving:
		world._apply_stop(StopCommand.new(world.allocate_command_id(), task.faction_id, GameCommand.IssuerKind.AGENT, world.current_tick, formation.leader_entity_id, formation.formation_id))
	task.set_phase(TaskState.Phase.SCOUTING, world.current_tick, "Observing area; %d hostile contacts identified" % task.discovered_contact_count)
	task.progress_current += 1
	task.progress_target = SCOUT_OBSERVE_TICKS
	if task.progress_current >= SCOUT_OBSERVE_TICKS:
		_complete(task, world, "Reconnaissance complete; %d hostile contacts identified" % task.discovered_contact_count)


func _update_scout_intelligence(task: TaskState, world: SimulationWorld) -> void:
	var snapshot := world.create_faction_snapshot(task.faction_id)
	var contacts := 0
	for unit in snapshot.units:
		if unit.enabled and unit.faction_id != task.faction_id and unit.is_visible_to_local_player:
			contacts += 1
	for building in snapshot.buildings:
		if building.enabled and building.faction_id != task.faction_id and building.is_visible:
			contacts += 1
	task.discovered_contact_count = maxi(task.discovered_contact_count, contacts)


func _nearest_visible_hostile_contact(origin: Vector2, world: SimulationWorld, faction_id: int) -> UnitSnapshot:
	var best: UnitSnapshot
	var best_distance := INF
	for contact in world.create_faction_snapshot(faction_id).units:
		if contact.faction_id == faction_id or not contact.enabled or not contact.is_visible_to_local_player:
			continue
		var distance := origin.distance_squared_to(contact.position)
		if distance < best_distance or is_equal_approx(distance, best_distance) and (best == null or contact.entity_id < best.entity_id):
			best = contact
			best_distance = distance
	return best


func _find_scout_evasion_target(scout_position: Vector2, threat_position: Vector2, faction_id: int, world: SimulationWorld) -> Vector2:
	var away := (scout_position - threat_position).normalized()
	var toward_base := (world._faction_base_position(faction_id) - scout_position).normalized()
	if away.is_zero_approx():
		away = toward_base if not toward_base.is_zero_approx() else Vector2.LEFT
	var headings: Array[Vector2] = [away, (away + toward_base).normalized(), away.rotated(PI * 0.25), away.rotated(-PI * 0.25), toward_base]
	var bounds := SimulationWorld.BATTLEFIELD_BOUNDS.grow(-LogicGrid.CELL_SIZE)
	var best_target := scout_position
	var best_score := -INF
	for heading in headings:
		if heading.is_zero_approx():
			continue
		var raw_target := scout_position + heading * SCOUT_EVADE_DISTANCE
		var target := raw_target.clamp(bounds.position, bounds.end)
		var path := world.pathfinder.find_path(scout_position, target)
		if path.is_empty():
			continue
		var endpoint := path[-1]
		var score := endpoint.distance_to(threat_position) - endpoint.distance_to(world._faction_base_position(faction_id)) * 0.15 - path.size()
		if score > best_score:
			best_target = endpoint
			best_score = score
	return best_target


func _submit_scout_evasion(task: TaskState, formation: FormationState, destination: Vector2, world: SimulationWorld) -> void:
	var stop := StopCommand.new(
		world.allocate_command_id(), task.faction_id, GameCommand.IssuerKind.AGENT,
		world.current_tick, formation.leader_entity_id, formation.formation_id
	)
	_set_agent_context(stop, task)
	world.submit_command(stop)
	_submit_formation_move(task, formation, destination, world)


func _submit_formation_move(task: TaskState, formation: FormationState, destination: Vector2, world: SimulationWorld) -> bool:
	var move := FormationMoveCommand.new(
		world.allocate_command_id(),
		task.faction_id,
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


func _nearest_visible_hostile(origin: Vector2, radius: float, world: SimulationWorld, faction_id: int = SimulationWorld.LOCAL_PLAYER_ID) -> int:
	var snapshot := world.create_faction_snapshot(faction_id)
	var best_id := 0
	var best_distance := INF
	for contact in snapshot.units:
		if contact.faction_id == faction_id or not contact.enabled or not contact.is_visible_to_local_player:
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


func _count_definition(world: SimulationWorld, faction_id: int, definition_id: StringName) -> int:
	var count := 0
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.faction_id == faction_id and unit.definition_id == definition_id:
			count += 1
	return count


func _count_committed_definition(world: SimulationWorld, faction_id: int, definition_id: StringName) -> int:
	var count := _count_definition(world, faction_id, definition_id)
	for building_variant in world.buildings.values():
		var building := building_variant as BuildingState
		if building.faction_id != faction_id:
			continue
		if building.production_definition_id == definition_id:
			count += 1
		for queued_definition_id in building.production_queue:
			if queued_definition_id == definition_id:
				count += 1
	for queued_command in world.command_queue.snapshot():
		if not queued_command is ProduceUnitCommand:
			continue
		var production := queued_command as ProduceUnitCommand
		var building := world.buildings.get(production.target_entity_id) as BuildingState
		if building != null and building.faction_id == faction_id and production.unit_definition_id == definition_id:
			count += 1
	return count


func _try_resume_blocked_development(task: TaskState, world: SimulationWorld) -> void:
	if task.kind != TaskState.Kind.DEVELOP_RESOURCE or task.blocked_reason not in [TaskState.BlockedReason.INSUFFICIENT_RESOURCES, TaskState.BlockedReason.PRODUCTION_UNAVAILABLE]:
		return
	if not world.ore_fields.has(task.target_entity_id) or _first_enabled_participant(task, world, &"harvester") == null:
		return
	var refinery := _find_faction_building(world, task.faction_id, &"command_center", true)
	if refinery == null or refinery.production_count() >= BuildingState.MAX_PRODUCTION_QUEUE_SIZE:
		return
	if not task.requires_proactive_authorization and _count_committed_definition(world, task.faction_id, &"harvester") <= task.expected_unit_count:
		var faction := world.factions.get(task.faction_id) as FactionState
		var definition := SimulationWorld.UNIT_CATALOG.get_unit(&"harvester")
		if faction == null or definition == null or faction.ore < definition.production_cost:
			return
	task.set_lifecycle(TaskState.Lifecycle.EXECUTING, world.current_tick)
	task.set_phase(TaskState.Phase.PREPARING, world.current_tick, "Development prerequisites recovered; task resumed")
	_emit_task_event(task, world)


func _enroll_compatible_units(task: TaskState, world: SimulationWorld) -> int:
	var enrolled := 0
	var unit_ids := world.units.keys()
	unit_ids.sort()
	for entity_id in unit_ids:
		var unit := world.units[entity_id] as UnitState
		if not unit.enabled or unit.faction_id != task.faction_id or unit.assigned_task_id != 0 or unit.last_command_id != 0:
			continue
		var compatible := false
		if task.kind == TaskState.Kind.DEVELOP_RESOURCE:
			compatible = unit.can_harvest
		elif task.kind == TaskState.Kind.SCOUT_AREA:
			compatible = unit.definition_id == &"scout_vehicle"
		else:
			compatible = unit.can_attack and unit.can_accept_attack_orders and not unit.can_harvest and not unit.can_construct
			if task.requires_proactive_authorization and unit.definition_id == &"scout_vehicle":
				compatible = false
		if not compatible:
			continue
		if task.formation_id != 0:
			if unit.formation_id != 0 and unit.formation_id != task.formation_id:
				continue
			var formation := world.formations.get(task.formation_id) as FormationState
			if formation == null:
				continue
			var slot_id := formation.add_member(unit.entity_id)
			unit.formation_id = formation.formation_id
			unit.formation_slot_id = slot_id
			unit.following_formation = true
			unit.desired_position = formation.anchor_position + formation.get_wide_offset(slot_id)
		task.add_participant(unit.entity_id)
		if not task.original_participant_entity_ids.has(unit.entity_id):
			task.original_participant_entity_ids.append(unit.entity_id)
			task.original_participant_entity_ids.sort()
		unit.control_state = UnitState.ControlState.AGENT_ASSIGNED
		unit.assigned_agent_id = task.agent_id
		unit.assigned_task_id = task.task_id
		unit.original_formation_id = unit.formation_id
		enrolled += 1
		world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.UNIT_CONTROL_CHANGED, unit.entity_id, "AGENT_ASSIGNED;task=%d;reinforcement=true" % task.task_id))
	return enrolled


func _allows_reinforcement_enrollment(task: TaskState, world: SimulationWorld) -> bool:
	var policy := world.agent_policies.get(task.agent_id) as AgentPolicy
	return policy != null and policy.allows_domain_management()


func _ensure_harvest_orders(task: TaskState, refinery: BuildingState, world: SimulationWorld) -> void:
	for entity_id in task.participant_entity_ids:
		var unit := world.units.get(entity_id) as UnitState
		if unit == null or not unit.enabled or not unit.can_harvest or unit.harvest_ore_field_entity_id != 0:
			continue
		var harvest := HarvestCommand.new(
			world.allocate_command_id(), task.faction_id, GameCommand.IssuerKind.AGENT,
			world.current_tick, unit.entity_id, task.target_entity_id, refinery.entity_id
		)
		_set_agent_context(harvest, task)
		world.submit_command(harvest)


func _find_faction_building(world: SimulationWorld, faction_id: int, definition_id: StringName, require_operational: bool) -> BuildingState:
	var building_ids := world.buildings.keys()
	building_ids.sort()
	for building_id in building_ids:
		var building := world.buildings[building_id] as BuildingState
		if building.enabled and building.faction_id == faction_id and building.definition_id == definition_id and (not require_operational or building.operational):
			return building
	return null


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
