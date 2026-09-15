class_name EnemyOperationDefinition
extends Resource

@export var operation_id: StringName
@export var doctrine: EnemyOperationDoctrine
@export var phases: Array[EnemyOperationPhaseDefinition] = []
@export var retreat_position: Vector2
@export var reserve_policy: EnemyReservePolicy = preload("res://data/ai/enemy_reserve_policy.tres")

func validate(battle: BattleDefinition) -> DataValidationResult:
	var result := DataValidationResult.new()
	if operation_id.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "enemy operation ID required")
	if doctrine == null:
		result.add(DataValidationResult.Reason.NULL_REFERENCE, "enemy doctrine required")
	else:
		result.issues.append_array(doctrine.validate().issues)
	if phases.is_empty() or not retreat_position.is_finite() or not battle.battlefield_bounds.has_point(retreat_position):
		result.add(DataValidationResult.Reason.INVALID_VALUE, "enemy operation phases or retreat invalid")
	var ids: Array[StringName] = []
	var opening_roles: Array[StringName] = []
	var reserve_roles: Array[StringName] = []
	var initial_strength := 0
	for phase in phases:
		if phase == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "enemy phase missing")
			continue
		result.issues.append_array(phase.validate(battle).issues)
		if ids.has(phase.phase_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "duplicate enemy phase")
		ids.append(phase.phase_id)
		if phase.kind == EnemyOperationPhaseDefinition.Kind.RESERVE:
			if reserve_roles.has(phase.formation_role_id): result.add(DataValidationResult.Reason.DUPLICATE_ID, "duplicate reserve allocation")
			reserve_roles.append(phase.formation_role_id)
		if phase.kind == EnemyOperationPhaseDefinition.Kind.OPENING:
			if opening_roles.has(phase.formation_role_id):
				result.add(DataValidationResult.Reason.DUPLICATE_ID, "duplicate opening allocation")
			opening_roles.append(phase.formation_role_id)
			var formation := battle.enemy_formation_by_role(phase.formation_role_id)
			if formation != null: initial_strength += formation.strength
	if opening_roles.is_empty() or doctrine != null and initial_strength > doctrine.max_committed_strength:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "enemy opening exceeds doctrine commitment")
	if not reserve_roles.is_empty():
		if reserve_policy == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "reserve policy required")
		else:
			result.issues.append_array(reserve_policy.validate().issues)
			if reserve_policy.release_on_objective_reached and not ids.has(reserve_policy.release_phase_id): result.add(DataValidationResult.Reason.INVALID_REFERENCE, "reserve release phase missing")
		for role in reserve_roles:
			if opening_roles.has(role): result.add(DataValidationResult.Reason.DUPLICATE_ID, "reserve already committed at opening")
			var formation := battle.enemy_formation_by_role(role)
			if formation != null and reserve_policy != null and formation.strength > reserve_policy.max_release_strength: result.add(DataValidationResult.Reason.INVALID_VALUE, "reserve exceeds release limit")
	return result

static func compile_legacy(battle: BattleDefinition, plan: BattleEnemyPlanDefinition) -> EnemyOperationDefinition:
	if plan.operation != null:
		return plan.operation.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyOperationDefinition
	var result := EnemyOperationDefinition.new()
	result.operation_id = plan.plan_id
	result.doctrine = plan.operation_doctrine.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EnemyOperationDoctrine if plan.operation_doctrine != null else null
	if result.doctrine != null:
		result.doctrine.minimum_commitment_ticks = maxi(result.doctrine.minimum_commitment_ticks, plan.commitment_ticks)
	result.retreat_position = battle.enemy_headquarters_position + Vector2(0, 160)
	var assault := _phase(&"opening_assault", EnemyOperationPhaseDefinition.Kind.OPENING, plan.assault_formation_role_id, plan.assault_target_region_id, plan.assault_target_position, 0)
	for id in plan.assault_route_region_ids:
		var region := battle.region_dictionary().get(id) as BattleRegionDefinition
		if region != null: assault.route_points.append(region.position)
	result.phases.append(assault)
	result.phases.append(_phase(&"opening_probe", EnemyOperationPhaseDefinition.Kind.OPENING, plan.probe_formation_role_id, plan.probe_target_region_id, plan.probe_target_position, 0))
	if not plan.reserve_formation_role_id.is_empty():
		var reserve := _phase(&"reserve_commit", EnemyOperationPhaseDefinition.Kind.RESERVE, plan.reserve_formation_role_id, plan.assault_target_region_id, plan.assault_target_position, 0)
		reserve.route_points = assault.route_points.duplicate()
		result.phases.append(reserve)
	if plan.followup_tick >= 0:
		result.phases.append(_phase(&"feint_redirect", EnemyOperationPhaseDefinition.Kind.REDIRECT, plan.followup_formation_role_id, plan.followup_target_region_id, plan.followup_target_position, plan.followup_tick))
	# This position is authored before the match. No live headquarters lookup.
	result.phases.append(_phase(&"exploit", EnemyOperationPhaseDefinition.Kind.EXPLOIT, plan.assault_formation_role_id, &"", battle.player_headquarters_position + Vector2(0, -128), battle.enemy_offensive_followup_tick))
	return result

static func _phase(id: StringName, kind: EnemyOperationPhaseDefinition.Kind, role: StringName, region: StringName, position: Vector2, tick: int) -> EnemyOperationPhaseDefinition:
	var phase := EnemyOperationPhaseDefinition.new()
	phase.phase_id = id
	phase.kind = kind
	phase.formation_role_id = role
	phase.target_region_id = region
	phase.target_position = position
	phase.earliest_tick = tick
	return phase
