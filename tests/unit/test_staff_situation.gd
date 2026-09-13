class_name TestStaffSituation
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_rejections(failures)
	_test_hidden_state_and_observers(failures)
	_test_contact_memory(failures)
	_test_reports_and_unknown_regions(failures)
	_test_cards_and_value_copy(failures)
	_test_host_is_read_only(failures)
	return failures


func _test_rejections(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var assessor := StaffSituationAssessor.new()
	_expect(assessor.assess(null, 1) == null and assessor.last_rejection_reason == &"SNAPSHOT_REQUIRED", "null input is rejected", failures)
	_expect(assessor.assess(world.create_true_state_snapshot(), 1) == null and assessor.last_rejection_reason == &"TRUE_STATE_FORBIDDEN", "true state is rejected", failures)
	var snapshot := world.create_faction_snapshot(1)
	_expect(assessor.assess(snapshot, 2) == null and assessor.last_rejection_reason == &"WRONG_OBSERVER_FACTION", "wrong observer is rejected", failures)
	snapshot.knowledge = null
	_expect(assessor.assess(snapshot, 1) == null and assessor.last_rejection_reason == &"FACTION_KNOWLEDGE_REQUIRED", "missing knowledge is rejected", failures)
	snapshot = world.create_faction_snapshot(1)
	snapshot.knowledge.faction_id = 2
	_expect(assessor.assess(snapshot, 1) == null and assessor.last_rejection_reason == &"FACTION_KNOWLEDGE_REQUIRED", "wrong knowledge is rejected", failures)
	snapshot = world.create_faction_snapshot(1)
	snapshot.factions.clear()
	_expect(assessor.assess(snapshot, 1) == null and assessor.last_rejection_reason == &"OBSERVER_FACTION_REQUIRED", "missing economy is rejected", failures)
	_expect(assessor.assess(world.create_snapshot(), 1) != null and assessor.last_rejection_reason == &"", "a successful assessment clears prior error", failures)


func _test_hidden_state_and_observers(failures: Array[String]) -> void:
	for observer in [1, 2]:
		var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
		var assessor := StaffSituationAssessor.new()
		var before := assessor.assess(world.create_faction_snapshot(observer), observer).canonical_json()
		var hidden: UnitState
		for value in world.units.values():
			var candidate := value as UnitState
			if candidate.faction_id != observer and world.create_faction_snapshot(observer).get_unit(candidate.entity_id) == null:
				hidden = candidate
				break
		_expect(hidden != null, "pollution needs an unseen hostile for each observer", failures)
		if hidden == null:
			continue
		var original := hidden.position
		hidden.position += Vector2(2, 0)
		hidden.health = 1.0
		hidden.attack_target_entity_id = 888888
		hidden.assigned_task_id = 999999
		hidden.ammunition = 777
		(world.factions[hidden.faction_id] as FactionState).supply = 999
		(world.factions[hidden.faction_id] as FactionState).ore = 999999
		world._update_faction_knowledge()
		var fresh := world.create_faction_snapshot(observer)
		_expect(fresh.get_unit(hidden.entity_id) == null, "polluted hostile stays unseen", failures)
		_expect(assessor.assess(fresh, observer).canonical_json() == before, "fresh filtered assessment ignores hidden position/health/task/ammo/economy", failures)
		_expect(hidden.position != original, "pollution fixture changed the actual world", failures)


func _test_contact_memory(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = (world.units[1] as UnitState).position + Vector2(96, 0)
	world._update_faction_knowledge()
	var assessor := StaffSituationAssessor.new()
	var visible := assessor.assess(world.create_snapshot(), 1)
	var seen := _find(visible, StaffSituationFact.Kind.VISIBLE_CONTACT, enemy.entity_id)
	_expect(seen != null and seen.confidence_percent == 100 and seen.estimated_min == 1, "current visible contact is confirmed", failures)
	if seen == null:
		return
	var frozen := visible.canonical_json()
	var observed_position := seen.position
	enemy.position = world.logic_grid.cell_to_world(Vector2i(70, 50))
	world.current_tick = 125
	world._update_faction_knowledge()
	var remembered := _find(assessor.assess(world.create_snapshot(), 1), StaffSituationFact.Kind.REMEMBERED_CONTACT, enemy.entity_id)
	_expect(remembered != null and remembered.position == observed_position and remembered.last_observed_tick == 0, "loss of sight only preserves the old position and tick", failures)
	_expect(remembered != null and remembered.confidence_percent == 50 and remembered.estimated_min == 0, "125 ticks of memory is uncertain, never current presence", failures)
	world.current_tick = 250
	var expired := _find(assessor.assess(world.create_snapshot(), 1), StaffSituationFact.Kind.REMEMBERED_CONTACT, enemy.entity_id)
	_expect(expired != null and expired.confidence_percent == 0, "250-tick memory has no current confidence", failures)
	_expect(visible.canonical_json() == frozen, "new world and assessments do not mutate old results", failures)


func _test_reports_and_unknown_regions(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_snapshot()
	snapshot.tick = 100
	snapshot.intel_reports.clear()
	var region := snapshot.strategic_regions[0]
	region.controller_faction_id = 0
	region.capturable = true
	var assessor := StaffSituationAssessor.new()
	var unknown := assessor.assess(snapshot, 1)
	_expect(_find_region(unknown, StaffSituationFact.Kind.UNKNOWN_REGION, region.region_id) != null, "unknown target remains an information gap", failures)
	var report := IntelReportState.new(7001, 1, &"INTEL_SOURCE_AIR_RECON", 100, &"INTEL_TARGET_CONTACT", 2, 8,
		region.region_id, &"INTEL_DIRECTION_CURRENT", &"INTEL_CONFIDENCE_HIGH")
	report.contradictory = true
	snapshot.intel_reports.append(IntelReportSnapshot.new(report, 100))
	var output := assessor.assess(snapshot, 1)
	var fact := _find_report(output, 7001)
	_expect(fact != null and fact.contradictory and fact.confidence_percent == 25 and fact.estimated_min == 2 and fact.estimated_max == 8, "contradiction preserves range but lowers confidence", failures)
	_expect(fact != null and fact.source_key == report.source_key, "report source is auditable", failures)
	_expect(output.visible_hostile_count == unknown.visible_hostile_count, "report estimates are not added to contact counts", failures)
	snapshot.intel_reports[0].superseded = true
	_expect(_find_report(assessor.assess(snapshot, 1), 7001) == null, "superseded report no longer drives the board", failures)
	snapshot.intel_reports[0].superseded = false
	snapshot.intel_reports[0].has_estimate = false
	var empty := _find_report(assessor.assess(snapshot, 1), 7001)
	_expect(empty != null and not empty.has_estimate and empty.confidence_percent == 0 and empty.estimated_max == 0, "no estimate is not a zero-enemy guarantee", failures)
	# Equal confidence reports use the latest observation independently of array order.
	snapshot.intel_reports.clear()
	for id in [7002, 7003]:
		var state := IntelReportState.new(id, 1, &"INTEL_SOURCE_CONTACT", 40 + (id - 7002) * 10, &"INTEL_TARGET_CONTACT", 1, 2,
			region.region_id, &"INTEL_DIRECTION_CURRENT", &"INTEL_CONFIDENCE_MEDIUM")
		snapshot.intel_reports.append(IntelReportSnapshot.new(state, 100))
	var canonical := assessor.assess(snapshot, 1).canonical_json()
	snapshot.intel_reports.reverse()
	snapshot.units.reverse()
	snapshot.strategic_regions.reverse()
	snapshot.unit_cards.reverse()
	_expect(assessor.assess(snapshot, 1).canonical_json() == canonical, "input order never changes facts or confidence timestamps", failures)


func _test_cards_and_value_copy(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_snapshot()
	var card := snapshot.unit_cards[0]
	card.deployment_state = UnitCardState.DeploymentState.DEPLOYED
	card.control_state = UnitCardState.ControlState.AGENT_ASSIGNED
	card.is_player_overridden = false
	card.current_strength = 3
	card.authorized_strength = 10
	card.organization_enabled = true
	card.organization = 20.0
	card.ammunition = 1
	card.ammunition_capacity = 10
	var task := TaskState.new(7001, 1)
	task.task_id = 7001
	task.faction_id = 1
	task.lifecycle = TaskState.Lifecycle.BLOCKED
	task.blocked_reason = TaskState.BlockedReason.PATH_UNAVAILABLE
	task.last_transition_tick = 0
	card.assigned_task_id = task.task_id
	snapshot.tasks.append(TaskSnapshot.new(task))
	var assessor := StaffSituationAssessor.new()
	var board := assessor.assess(snapshot, 1)
	_expect(board.get_card(card.definition_id).can_allocate, "deployed agent card is available for planning", failures)
	for kind in [StaffSituationFact.Kind.STRENGTH_SHORTFALL, StaffSituationFact.Kind.LOW_ORGANIZATION, StaffSituationFact.Kind.LOW_AMMUNITION, StaffSituationFact.Kind.BLOCKED_TASK]:
		_expect(_find_card(board, kind, card.definition_id) != null, "card shortage and blocked work are represented", failures)
	var blocked := _find_card(board, StaffSituationFact.Kind.BLOCKED_TASK, card.definition_id)
	_expect(blocked != null and blocked.task_id == 7001 and blocked.blocked_reason == TaskState.BlockedReason.PATH_UNAVAILABLE, "blocked task links the actual reason and identity", failures)
	var before := board.canonical_json()
	var clone := board.duplicate_value()
	clone.cards[0].current_strength = 999
	clone.facts[0].position = Vector2(999, 999)
	clone.to_dictionary()["facts"].clear()
	_expect(board.canonical_json() == before, "nested DTO and serialization copies cannot modify the source", failures)
	for state in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.PLAYER_CONTROLLED, UnitCardState.ControlState.RETURNING]:
		card.control_state = state
		_expect(not assessor.assess(snapshot, 1).get_card(card.definition_id).can_allocate, "player and returning controls exclude allocation", failures)
	card.control_state = UnitCardState.ControlState.AGENT_ASSIGNED
	card.is_player_overridden = true
	_expect(not assessor.assess(snapshot, 1).get_card(card.definition_id).can_allocate, "member takeover also excludes whole-card allocation", failures)
	card.is_player_overridden = false
	card.organization = 0
	_expect(not assessor.assess(snapshot, 1).get_card(card.definition_id).can_allocate, "broken organization excludes allocation", failures)
	card.deployment_state = UnitCardState.DeploymentState.RESERVE
	card.available_strength = 5
	card.supply_cost = 7
	snapshot.get_faction(1).supply = 2
	var reserve := assessor.assess(snapshot, 1)
	_expect(reserve.get_card(card.definition_id).is_reserve and not reserve.get_card(card.definition_id).can_allocate, "reserve remains distinct from deployed force", failures)
	_expect(_find_card(reserve, StaffSituationFact.Kind.INSUFFICIENT_SUPPLY, card.definition_id) != null, "unaffordable reserve explains the supply shortfall", failures)
	_expect(board.canonical_json() == before, "mutating input cards never changes an old assessment", failures)


func _test_host_is_read_only(failures: Array[String]) -> void:
	var host := SimulationHost.new()
	host.world = SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	host.current_snapshot = host.world.create_snapshot()
	var before_queue := host.world.command_queue.snapshot().size()
	var before_tick := host.world.current_tick
	var before_supply := (host.world.factions[1] as FactionState).supply
	var board := host.get_staff_assessment()
	_expect(board != null and board.cards.size() == host.current_snapshot.unit_cards.size(), "real host exposes its published faction card assessment", failures)
	var frozen := board.canonical_json()
	board.facts.clear()
	_expect(host.get_staff_assessment().canonical_json() == frozen, "caller edits cannot poison the next host query", failures)
	_expect(host.world.current_tick == before_tick and host.world.command_queue.snapshot().size() == before_queue and (host.world.factions[1] as FactionState).supply == before_supply, "host query neither advances authority, queues orders nor spends", failures)
	host.world = SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	host.current_snapshot = host.world.create_snapshot()
	var restarted := host.get_staff_assessment()
	_expect(restarted.get_card(&"forward_observers") == null and restarted.fingerprint() != frozen.sha256_text(), "host assessment has no stale state across battle replacement", failures)
	host.free()


func _find(board: StaffSituationSnapshot, kind: int, entity_id: int) -> StaffSituationFact:
	for fact in board.facts:
		if fact.kind == kind and fact.entity_id == entity_id:
			return fact
	return null


func _find_card(board: StaffSituationSnapshot, kind: int, card_id: StringName) -> StaffSituationFact:
	for fact in board.facts:
		if fact.kind == kind and fact.card_id == card_id:
			return fact
	return null


func _find_region(board: StaffSituationSnapshot, kind: int, region_id: StringName) -> StaffSituationFact:
	for fact in board.facts:
		if fact.kind == kind and fact.region_id == region_id:
			return fact
	return null


func _find_report(board: StaffSituationSnapshot, report_id: int) -> StaffSituationFact:
	for fact in board.facts:
		if fact.report_id == report_id:
			return fact
	return null


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("Staff situation: " + message)
