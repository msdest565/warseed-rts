class_name TestStaffPlans
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_stable_id_order(failures)
	_test_definitions_and_rejections(failures)
	_test_alternatives_and_copy(failures)
	_test_budget_and_control(failures)
	_test_fairness_and_scoring(failures)
	_test_host_and_behavior(failures)
	return failures


static func request() -> StaffPlanRequest:
	var result := StaffPlanRequest.new()
	result.objective_region_id = &"central_relay"
	return result


func _world() -> SimulationWorld:
	return SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)


func _test_definitions_and_rejections(failures: Array[String]) -> void:
	var catalog := load("res://data/ai/staff_plans.tres") as StaffPlanCatalog
	_expect(catalog != null and catalog.validate().is_valid(), "committed typed catalog validates", failures)
	var broken := catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as StaffPlanCatalog
	broken.profiles[0].force_percent = 0
	_expect(not broken.validate().is_valid() and catalog.validate().is_valid(), "invalid force rejected without mutating shared catalog", failures)
	broken = catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as StaffPlanCatalog
	broken.profiles[1].profile_id = broken.profiles[0].profile_id
	_expect(broken.validate().has_reason(DataValidationResult.Reason.DUPLICATE_ID), "duplicate profiles rejected", failures)
	broken.profiles[1] = null
	_expect(broken.validate().has_reason(DataValidationResult.Reason.NULL_REFERENCE), "missing profile rejected", failures)
	var world := _world()
	var snapshot := world.create_snapshot()
	var generator := StaffPlanGenerator.new()
	_expect(generator.generate(snapshot, 1, request(), broken) == null and generator.last_rejection_reason == &"INVALID_PROFILES", "invalid catalog cannot generate", failures)
	_expect(generator.generate(world.create_true_state_snapshot(), 1, request()) == null and generator.last_rejection_reason == &"TRUE_STATE_FORBIDDEN", "true state rejected", failures)
	_expect(generator.generate(snapshot, 2, request()) == null and generator.last_rejection_reason == &"WRONG_OBSERVER_FACTION", "wrong observer rejected", failures)
	snapshot.outcome = BattleOutcome.new(BattleOutcome.Result.DEFEAT)
	_expect(generator.generate(snapshot, 1, request()) == null and generator.last_rejection_reason == &"BATTLE_ENDED", "terminal battle does not offer new plans", failures)
	snapshot = world.create_snapshot()
	var invalid := request()
	invalid.max_supply_cost = -1
	_expect(generator.generate(snapshot, 1, invalid) == null and generator.last_rejection_reason == &"INVALID_REQUEST", "negative budget rejected", failures)
	invalid = request()
	invalid.objective_region_id = &"missing"
	_expect(generator.generate(snapshot, 1, invalid) == null and generator.last_rejection_reason == &"UNKNOWN_OBJECTIVE", "unknown objective rejected", failures)
	invalid = request()
	invalid.allowed_card_ids.assign([&"missing"])
	_expect(generator.generate(snapshot, 1, invalid) == null and generator.last_rejection_reason == &"INVALID_REQUEST", "missing allowed card rejected", failures)
	snapshot.get_strategic_region(&"central_relay").controller_faction_id = 1
	_expect(generator.generate(snapshot, 1, request()) == null and generator.last_rejection_reason == &"OBJECTIVE_ALREADY_HELD", "owned objective rejected", failures)
	snapshot = world.create_snapshot()
	for card in snapshot.unit_cards:
		card.control_state = UnitCardState.ControlState.PLAYER_OVERRIDDEN
	_expect(generator.generate(snapshot, 1, request()) == null and generator.last_rejection_reason == &"INSUFFICIENT_ALTERNATIVES", "no authorized force yields an explicit refusal, not empty plans", failures)


func _test_alternatives_and_copy(failures: Array[String]) -> void:
	var world := _world()
	var snapshot := world.create_snapshot()
	var generator := StaffPlanGenerator.new()
	var intent := request()
	var plans := generator.generate(snapshot, 1, intent)
	_expect(plans != null and plans.plans.size() == 3, "grey ridge opening produces three real alternatives", failures)
	if plans == null:
		return
	var direct := _kind(plans, StaffPlanProfile.Kind.DIRECT)
	var recon := _kind(plans, StaffPlanProfile.Kind.RECON_FIRST)
	var flank := _kind(plans, StaffPlanProfile.Kind.FLANK)
	_expect(direct.committed_strength > recon.committed_strength and recon.reserve_strength > direct.reserve_strength, "recon holds more force than concentration", failures)
	_expect(flank.assignments[0].route_points.size() == 5 and direct.assignments[0].route_points.size() == 2, "flanking uses a different strategic axis", failures)
	var scouts := 0
	for assignment in recon.assignments:
		if assignment.role == StaffPlanAssignment.Role.RECONNAISSANCE:
			scouts += 1
			_expect(assignment.preparation_ticks == 0, "recon element starts before the main commitment", failures)
		else:
			_expect(assignment.preparation_ticks == recon.preparation_ticks, "main elements honor the reconnaissance delay", failures)
	_expect(scouts == 1, "recon assigns one actual sensor card", failures)
	for plan in plans.plans:
		_expect(not plan.route_is_navigation_path and plan.reason_keys.has(&"STAFF_STRATEGIC_ROUTE_ONLY"), "plans never claim navigation validation", failures)
		var ids: Array[StringName] = []
		for assignment in plan.assignments:
			_expect(not ids.has(assignment.card_id) and not plan.reserve_card_ids.has(assignment.card_id), "card is allocated once and cannot also be held", failures)
			ids.append(assignment.card_id)
		_expect(plan.supply_cost == 0 and plan.route_distance > 0, "zero budget offers existing forces and explains route commitment", failures)
	var frozen := plans.canonical_json()
	var copied := plans.duplicate_value()
	_expect(copied.canonical_json() == frozen, "copy preserves all plan facts", failures)
	copied.plans[0].assignments[0].route_points[0] = Vector2(999, 999)
	copied.plans[1].reserve_card_ids.clear()
	copied.request.objective_region_id = &"changed"
	plans.to_dictionary()["plans"].clear()
	intent.max_supply_cost = 999
	_expect(plans.canonical_json() == frozen, "deep copy, serializer and caller request do not change old plans", failures)
	snapshot.units.reverse()
	snapshot.unit_cards.reverse()
	snapshot.strategic_regions.reverse()
	snapshot.intel_reports.reverse()
	var reverse_catalog := StaffPlanGenerator.DEFAULT_CATALOG.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as StaffPlanCatalog
	reverse_catalog.profiles.reverse()
	_expect(generator.generate(snapshot, 1, request(), reverse_catalog).canonical_json() == frozen, "input and catalog order do not change plan order or scoring", failures)


func _test_budget_and_control(failures: Array[String]) -> void:
	var snapshot := _world().create_snapshot()
	var reserves: Array[UnitCardSnapshot] = []
	for card in snapshot.unit_cards:
		if card.deployment_state == UnitCardState.DeploymentState.RESERVE:
			reserves.append(card)
	_expect(not reserves.is_empty(), "fixture has reserves", failures)
	if reserves.is_empty():
		return
	var reserve := reserves[0]
	reserve.control_state = UnitCardState.ControlState.UNASSIGNED
	reserve.organization_enabled = false
	reserve.available_strength = 3
	reserve.supply_cost = 2
	var faction := snapshot.get_faction(1)
	faction.supply = 2
	faction.population_capacity = faction.population + 3
	var generator := StaffPlanGenerator.new()
	var intent := request()
	intent.max_supply_cost = 2
	var plans := generator.generate(snapshot, 1, intent)
	_expect(plans != null, "budget fixture remains feasible", failures)
	if plans == null:
		return
	var direct := _kind(plans, StaffPlanProfile.Kind.DIRECT)
	_expect(direct.supply_cost == 2 and _assigned(direct, reserve.definition_id), "concentration may commit an affordable reserve", failures)
	reserve.is_player_overridden = true
	_expect(not _assigned(_kind(generator.generate(snapshot, 1, intent), StaffPlanProfile.Kind.DIRECT), reserve.definition_id), "member override also protects reserve deployment", failures)
	reserve.is_player_overridden = false
	faction.population_capacity = faction.population
	var capped := generator.generate(snapshot, 1, intent)
	_expect(_kind(capped, StaffPlanProfile.Kind.DIRECT).supply_cost == 0, "population limit excludes reserve deployment", failures)
	faction.population_capacity += 100
	faction.supply = 0
	_expect(_kind(generator.generate(snapshot, 1, intent), StaffPlanProfile.Kind.DIRECT).supply_cost == 0, "actual supply bounds the requested budget", failures)
	var deployed: UnitCardSnapshot
	for card in snapshot.unit_cards:
		if card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.tactical_kind != TacticalAbilityDefinition.Kind.OBSERVE:
			deployed = card
			break
	deployed.control_state = UnitCardState.ControlState.RETURNING
	var protected := generator.generate(snapshot, 1, intent)
	_expect(protected != null, "other cards can still form alternatives", failures)
	if protected != null:
		for plan in protected.plans:
			_expect(not _assigned(plan, deployed.definition_id) and not plan.reserve_card_ids.has(deployed.definition_id), "returning card is never appropriated", failures)
	var restricted := request()
	for card in snapshot.unit_cards:
		if card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.control_state != UnitCardState.ControlState.RETURNING:
			restricted.allowed_card_ids.append(card.definition_id)
	var selected := generator.generate(snapshot, 1, restricted)
	if selected != null:
		for plan in selected.plans:
			for assignment in plan.assignments:
				_expect(restricted.allowed_card_ids.has(assignment.card_id), "allow-list limits assignments", failures)


func _test_fairness_and_scoring(failures: Array[String]) -> void:
	var world := _world()
	var generator := StaffPlanGenerator.new()
	var intent := request()
	var snapshot := world.create_snapshot()
	var before := generator.generate(snapshot, 1, intent)
	var hidden_id := 0
	for value in world.units.values():
		var unit := value as UnitState
		if unit.faction_id == 2 and snapshot.get_unit(unit.entity_id) == null:
			hidden_id = unit.entity_id
			unit.position += Vector2(1, 0)
			unit.health = 1
			unit.attack_target_entity_id = 99999
			break
	(world.factions[2] as FactionState).supply = 999
	world._update_faction_knowledge()
	_expect(hidden_id != 0 and world.create_snapshot().get_unit(hidden_id) == null, "pollution uses a genuinely unseen unit", failures)
	_expect(generator.generate(world.create_snapshot(), 1, intent).canonical_json() == before.canonical_json(), "fresh plans ignore hidden actual state", failures)
	# Inject only a visible contact into an otherwise equal legal input.
	var observed := UnitState.new(999999, Vector2(2000, 2300), 100.0, 2)
	var contact := UnitSnapshot.new(observed)
	contact.is_visible_to_local_player = true
	contact.last_seen_tick = snapshot.tick
	contact.position = snapshot.get_strategic_region(intent.objective_region_id).position
	snapshot.intel_reports.clear()
	var empty := generator.generate(snapshot, 1, intent)
	snapshot.units.append(contact)
	var threatened := generator.generate(snapshot, 1, intent)
	_expect(_kind(threatened, StaffPlanProfile.Kind.DIRECT).known_threat_score > _kind(empty, StaffPlanProfile.Kind.DIRECT).known_threat_score, "observed enemy changes threat score", failures)
	intent.risk_aversion = 3
	var cautious := _kind(generator.generate(snapshot, 1, intent), StaffPlanProfile.Kind.DIRECT)
	intent.risk_aversion = 1
	var accepting := _kind(generator.generate(snapshot, 1, intent), StaffPlanProfile.Kind.DIRECT)
	_expect(cautious.utility_score < accepting.utility_score and cautious.risk_score == accepting.risk_score, "player risk preference changes utility, not observed facts", failures)
	_expect(_kind(empty, StaffPlanProfile.Kind.DIRECT).uncertainty_score > 0, "no information is charged as uncertainty", failures)


func _test_host_and_behavior(failures: Array[String]) -> void:
	var host := SimulationHost.new()
	host.world = _world()
	host.current_snapshot = host.world.create_snapshot()
	var before_queue := host.world.command_queue.snapshot().size()
	var before_supply := (host.world.factions[1] as FactionState).supply
	var plans := host.get_staff_plans(request())
	_expect(plans != null and plans.source_tick == host.current_snapshot.tick, "host exposes current plan set", failures)
	_expect(host.world.command_queue.snapshot().size() == before_queue and (host.world.factions[1] as FactionState).supply == before_supply, "plan query never queues or spends", failures)
	var untouched := _world()
	for index in range(40):
		host.current_snapshot = host.world.advance_tick()
		host.get_staff_plans(request())
		var expected := untouched.advance_tick()
		var actual := host.world.create_snapshot()
		_expect(StaffSituationAssessor.new().assess(actual, 1).fingerprint() == StaffSituationAssessor.new().assess(expected, 1).fingerprint(), "repeated planning cannot change simulation behavior", failures)
	host.free()


func _kind(plans: StaffPlanSet, kind: int) -> StaffCourseOfAction:
	for plan in plans.plans:
		if plan.kind == kind:
			return plan
	return null


func _assigned(plan: StaffCourseOfAction, card_id: StringName) -> bool:
	for assignment in plan.assignments:
		if assignment.card_id == card_id:
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("Staff plans: " + message)


func _test_stable_id_order(failures: Array[String]) -> void:
	var intent := request()
	intent.allowed_card_ids.assign([&"z_last", &"a_first", &"m_middle"])
	_expect(intent.to_dictionary().allowed_card_ids == [&"a_first", &"m_middle", &"z_last"], "request IDs use lexical order independent of StringName allocation", failures)
	for plan in StaffPlanGenerator.new().generate(_world().create_snapshot(), 1, request()).plans:
		for ids in [plan.reserve_card_ids, plan.evidence_fact_ids]:
			for index in range(1, ids.size()):
				_expect(String(ids[index-1]) <= String(ids[index]), "plan IDs use deterministic lexical order", failures)
