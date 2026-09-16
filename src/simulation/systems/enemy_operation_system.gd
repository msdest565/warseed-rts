class_name EnemyOperationSystem
extends RefCounted

const Kind := EnemyOperationPhaseDefinition.Kind
const Status := EnemyOperationPhaseSnapshot.Status
var _state: EnemyOperationSnapshot

func lock_plan(battle: BattleDefinition, plan_id: StringName) -> void:
	var plan := battle.enemy_plan_dictionary().get(plan_id) as BattleEnemyPlanDefinition
	if plan == null: return
	var definition := EnemyOperationDefinition.compile_legacy(battle, plan)
	if not definition.validate(battle).is_valid(): return
	_state = EnemyOperationSnapshot.new()
	_state.operation_id = plan_id
	_state.doctrine = definition.doctrine
	_state.retreat_position = definition.retreat_position
	_state.reserve_policy = definition.reserve_policy.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyReservePolicy if definition.reserve_policy != null else null
	var roles: Array[StringName] = []
	for phase in definition.phases:
		var node := EnemyOperationPhaseSnapshot.new()
		node.definition = phase
		var formation := battle.enemy_formation_by_role(phase.formation_role_id)
		node.formation_id = formation.formation_id
		_state.phases.append(node)
		if phase.kind == Kind.OPENING: _state.initial_committed_strength += formation.strength
		if not roles.has(phase.formation_role_id):
			roles.append(phase.formation_role_id)
			_state.initial_strength += formation.strength

func snapshot_for(observer: int, terminal: bool = false) -> EnemyOperationSnapshot:
	return _state.duplicate_value() if _state != null and (observer in [0, SimulationWorld.ENEMY_PLAYER_ID] or terminal) else null

func is_withdrawing() -> bool:
	return _state != null and _state.withdrawing

func start(world: SimulationWorld) -> void:
	if _state == null: return
	world.enemy_reaction_committed_until_tick = _state.doctrine.minimum_commitment_ticks
	for node in _state.phases:
		if node.definition.kind == Kind.OPENING:
			_issue(world, node, true)
	var plan := world.battle_definition.enemy_plan_dictionary()[_state.operation_id] as BattleEnemyPlanDefinition
	world.enemy_reaction_log.append("tick=0;source=LOCKED_OPENING_PLAN;plan=%s;action=%s;formations=%d,%d;commit_until=%d" % [
		_state.operation_id, plan.action_key, world._enemy_formation_state(plan.assault_formation_role_id).formation_id,
		world._enemy_formation_state(plan.probe_formation_role_id).formation_id, world.enemy_reaction_committed_until_tick])

func advance(world: SimulationWorld) -> void:
	if _state == null: return
	var snapshot := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	var alive := 0
	var formation_ids: Array[int] = []
	for node in _state.phases:
		if not formation_ids.has(node.formation_id): formation_ids.append(node.formation_id)
	for formation_id in formation_ids:
		var formation := snapshot.get_formation(formation_id)
		if formation != null:
			for id in formation.member_entity_ids:
				var unit := snapshot.get_unit(id)
				if unit != null and unit.enabled: alive += 1
	if world.current_tick >= _state.doctrine.minimum_commitment_ticks and alive > 0 and alive <= _state.initial_strength * _state.doctrine.retreat_strength_ratio:
		_state.withdrawing = true
	if _state.withdrawing:
		_withdraw(world, formation_ids)
		return
	for node in _state.phases:
		var formation := snapshot.get_formation(node.formation_id)
		var active_members := 0
		if formation != null:
			for id in formation.member_entity_ids:
				var unit := snapshot.get_unit(id)
				if unit != null and unit.enabled: active_members += 1
		if active_members == 0 and node.status in [Status.WAITING, Status.ACTIVE]:
			node.status = Status.FAILED
			node.reason = &"OWN_FORMATION_LOST"
			node.changed_tick = world.current_tick
			if node.definition.kind == Kind.REDIRECT: world.enemy_opening_followup_executed = true
			continue
		if node.status == Status.ACTIVE and not formation.is_moving and formation.anchor_position.distance_to(node.definition.target_position) <= 256.0:
			node.status = Status.COMPLETED
			node.changed_tick = world.current_tick
			node.reason = &"OBJECTIVE_AREA_REACHED"
		if node.status != Status.WAITING or world.current_tick < node.definition.earliest_tick: continue
		if node.definition.kind not in [Kind.OPENING, Kind.RESERVE] and not _state.committed_formation_ids.has(node.formation_id):
			var held_reserve := false
			for other in _state.phases:
				if other.formation_id == node.formation_id and other.definition.kind == Kind.RESERVE: held_reserve = true
			if held_reserve: continue
		if node.definition.kind == Kind.RESERVE:
			var release_reason := EnemyReserveEvaluator.release_reason(snapshot, _state, node, _state.reserve_policy)
			if release_reason.is_empty(): continue
			node.reason = release_reason
		if node.definition.kind == Kind.EXPLOIT and world.current_tick < world.enemy_reaction_committed_until_tick: continue
		if node.definition.requires_idle and (formation.is_moving or formation.order_target_entity_id != 0): continue
		_issue(world, node, false)

func _issue(world: SimulationWorld, node: EnemyOperationPhaseSnapshot, immediate: bool) -> void:
	var formation := world.formations.get(node.formation_id) as FormationState
	if formation == null: return
	world._prune_disabled_formation_members(formation)
	if formation.member_entity_ids.is_empty(): return
	if not _state.committed_formation_ids.has(node.formation_id):
		var committed_strength := formation.member_entity_ids.size()
		for id in _state.committed_formation_ids:
			var existing := world.formations.get(id) as FormationState
			if existing == null: continue
			for entity_id in existing.member_entity_ids:
				var unit := world.units.get(entity_id) as UnitState
				if unit != null and unit.enabled: committed_strength += 1
		if committed_strength > _state.doctrine.max_committed_strength:
			node.reason = &"COMMITMENT_LIMIT"
			return
	var target := node.definition.target_position
	var command: GameCommand
	if node.definition.kind in [Kind.EXPLOIT, Kind.RESERVE]:
		if node.definition.kind == Kind.RESERVE and _state.reserve_committed_strength + formation.member_entity_ids.size() > _state.reserve_policy.max_release_strength: return
		target = world.find_formation_deployment_position(formation, target, world.battle_definition.deployment_radius)
		if not target.is_finite(): return
		command = AttackMoveCommand.new(world.allocate_command_id(), 2, GameCommand.IssuerKind.AGENT, world.current_tick, formation.leader_entity_id, formation.formation_id, target, node.definition.route_points)
	else:
		command = FormationMoveCommand.new(world.allocate_command_id(), 2, GameCommand.IssuerKind.AGENT, world.current_tick, formation.leader_entity_id, formation.formation_id, target, node.definition.route_points)
	command.agent_id = world.battle_definition.enemy_agent_id
	command.task_id = world.battle_definition.enemy_task_id
	var receipt := world.validate_command(command) if immediate else world.submit_command(command)
	if not receipt.is_accepted():
		node.reason = &"COMMAND_REJECTED"
		return
	world.enemy_action_audit.annotate(world,command,node.definition.phase_id,&"LEGAL_FACTION_OBSERVATION" if node.definition.kind == Kind.RESERVE else &"LOCKED_PLAN_TIMELINE",String(node.reason) if node.definition.kind == Kind.RESERVE else "operation=%s;phase=%s" % [_state.operation_id,node.definition.phase_id],world.current_tick if node.definition.kind == Kind.RESERVE else 0,0,world.enemy_reaction_committed_until_tick)
	if immediate: world._apply_command(command)
	if not _state.committed_formation_ids.has(node.formation_id): _state.committed_formation_ids.append(node.formation_id)
	node.command_id = command.command_id
	node.status = Status.ACTIVE
	node.started_tick = world.current_tick
	node.changed_tick = world.current_tick
	if node.definition.kind == Kind.REDIRECT:
		world.enemy_opening_followup_executed = true
		world.enemy_reaction_log.append("tick=%d;source=LOCKED_PLAN_TIMELINE;plan=%s;action=FEINT_REDIRECT_CENTRAL;formation=%d;phase=%s;command=%d" % [world.current_tick, _state.operation_id, formation.formation_id, node.definition.phase_id, command.command_id])
	elif node.definition.kind == Kind.EXPLOIT:
		world.enemy_offensive_followup_executed = true
		world.enemy_reaction_log.append("tick=%d;source=LOCKED_PLAN_TIMELINE;plan=%s;action=EXPLOIT_PLAYER_HEADQUARTERS;formation=%d;phase=%s;command=%d;target_source=AUTHORED_MAP_OBJECTIVE" % [world.current_tick, _state.operation_id, formation.formation_id, node.definition.phase_id, command.command_id])
	elif node.definition.kind == Kind.RESERVE:
		_state.reserve_committed_strength += formation.member_entity_ids.size()
		world.enemy_reaction_log.append("tick=%d;source=LEGAL_FACTION_OBSERVATION;rule=%s;action=RESERVE_COMMITTED;reason=%s;formation=%d;strength=%d;cost=0;command=%d" % [world.current_tick, _state.reserve_policy.policy_id, node.reason, node.formation_id, formation.member_entity_ids.size(), command.command_id])

func _withdraw(world: SimulationWorld, formation_ids: Array[int]) -> void:
	for node in _state.phases:
		if node.status in [Status.WAITING, Status.ACTIVE]:
			node.status = Status.CANCELLED
			node.reason = &"DOCTRINE_WITHDRAWAL"
			node.changed_tick = world.current_tick
	for id in formation_ids:
		if _state.withdrawn_formation_ids.has(id): continue
		var formation := world.formations.get(id) as FormationState
		if formation == null: continue
		world._prune_disabled_formation_members(formation)
		if formation.member_entity_ids.is_empty(): continue
		var command := FormationMoveCommand.new(world.allocate_command_id(), 2, GameCommand.IssuerKind.AGENT, world.current_tick, formation.leader_entity_id, id, _state.retreat_position)
		command.agent_id = world.battle_definition.enemy_agent_id
		command.task_id = world.battle_definition.enemy_task_id
		if world.submit_command(command).is_accepted():
			world.enemy_action_audit.annotate(world,command,&"doctrine_withdrawal",&"LEGAL_FACTION_OBSERVATION","own_strength_at_or_below_doctrine_threshold",world.current_tick,0,world.current_tick)
			_state.withdrawn_formation_ids.append(id)
			world.enemy_reaction_log.append("tick=%d;source=LEGAL_FACTION_OBSERVATION;rule=doctrine_withdrawal;formation=%d;command=%d;reason=OWN_STRENGTH_BELOW_LIMIT" % [world.current_tick, id, command.command_id])
