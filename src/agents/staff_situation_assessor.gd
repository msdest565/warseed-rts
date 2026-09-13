class_name StaffSituationAssessor
extends RefCounted

const MEMORY_EXPIRY_TICKS := 250
const LOW_ORGANIZATION := 30.0
const LOW_AMMUNITION_RATIO := 0.25

var last_rejection_reason: StringName


func assess(snapshot: WorldSnapshot, observer_faction_id: int) -> StaffSituationSnapshot:
	last_rejection_reason = &""
	if snapshot == null:
		return _reject(&"SNAPSHOT_REQUIRED")
	if snapshot.is_true_state:
		return _reject(&"TRUE_STATE_FORBIDDEN")
	if snapshot.observer_faction_id != observer_faction_id:
		return _reject(&"WRONG_OBSERVER_FACTION")
	if snapshot.knowledge == null or snapshot.knowledge.faction_id != observer_faction_id:
		return _reject(&"FACTION_KNOWLEDGE_REQUIRED")
	var faction := snapshot.get_faction(observer_faction_id)
	if faction == null:
		return _reject(&"OBSERVER_FACTION_REQUIRED")
	var result := StaffSituationSnapshot.new()
	result.source_tick = snapshot.tick
	result.observer_faction_id = observer_faction_id
	result.supply = faction.supply
	result.population = faction.population
	result.population_capacity = faction.population_capacity
	result.unexplored_cell_count = snapshot.knowledge.cells.count(FactionKnowledge.CellState.UNEXPLORED)
	result.known_cell_count = snapshot.knowledge.cells.size() - result.unexplored_cell_count
	_assess_contacts(snapshot, result)
	_assess_regions(snapshot, result)
	_assess_cards(snapshot, result)
	result.facts.sort_custom(func(a: StaffSituationFact, b: StaffSituationFact) -> bool: return String(a.fact_id) < String(b.fact_id))
	result.cards.sort_custom(func(a: StaffCardAssessment, b: StaffCardAssessment) -> bool: return String(a.card_id) < String(b.card_id))
	return result


func _reject(reason: StringName) -> StaffSituationSnapshot:
	last_rejection_reason = reason
	return null


func _fact(result: StaffSituationSnapshot, id: String, category: StaffSituationFact.Category, kind: StaffSituationFact.Kind, reason: StringName) -> StaffSituationFact:
	var fact := StaffSituationFact.new()
	fact.fact_id = StringName(id)
	fact.category = category
	fact.kind = kind
	fact.reason_key = reason
	fact.source_tick = result.source_tick
	fact.last_observed_tick = result.source_tick
	fact.confidence_percent = 100
	result.facts.append(fact)
	return fact


func _memory_confidence(source_tick: int, observed_tick: int) -> int:
	return clampi(100 - ceili(100.0 * maxi(0, source_tick - observed_tick) / MEMORY_EXPIRY_TICKS), 0, 100)


func _assess_contacts(snapshot: WorldSnapshot, result: StaffSituationSnapshot) -> void:
	for unit in snapshot.units:
		if unit.faction_id == result.observer_faction_id or not unit.enabled:
			continue
		var visible := unit.is_visible_to_local_player
		var fact := _fact(result, "contact:%08d" % unit.entity_id, StaffSituationFact.Category.THREAT,
			StaffSituationFact.Kind.VISIBLE_CONTACT if visible else StaffSituationFact.Kind.REMEMBERED_CONTACT,
			&"STAFF_VISIBLE_CONTACT" if visible else &"STAFF_LAST_KNOWN_CONTACT")
		fact.entity_id = unit.entity_id
		fact.position = unit.position if visible else unit.last_seen_position
		fact.last_observed_tick = snapshot.tick if visible else unit.last_seen_tick
		fact.confidence_percent = 100 if visible else _memory_confidence(snapshot.tick, unit.last_seen_tick)
		fact.has_estimate = true
		fact.estimated_min = 1 if visible else 0
		fact.estimated_max = 1
		if visible:
			result.visible_hostile_count += 1
		else:
			result.remembered_hostile_count += 1
	# Reports remain separate evidence; their ranges must not be added to contact counts.
	for report in snapshot.intel_reports:
		if report.superseded:
			continue
		var region := snapshot.get_strategic_region(report.region_id)
		if region == null:
			continue
		var fact := _fact(result, "report:%08d" % report.report_id, StaffSituationFact.Category.THREAT,
			StaffSituationFact.Kind.INTEL_ESTIMATE, &"STAFF_CONTRADICTORY_INTEL" if report.contradictory else &"STAFF_REPORTED_ESTIMATE")
		fact.report_id = report.report_id
		fact.source_key = report.source_key
		fact.region_id = report.region_id
		fact.position = region.position
		fact.last_observed_tick = report.observed_tick
		fact.has_estimate = report.has_estimate
		fact.estimated_min = report.estimated_min if report.has_estimate else 0
		fact.estimated_max = report.estimated_max if report.has_estimate else 0
		fact.contradictory = report.contradictory
		var initial := 25
		if report.confidence_key == &"INTEL_CONFIDENCE_HIGH":
			initial = 100
		elif report.confidence_key == &"INTEL_CONFIDENCE_MEDIUM":
			initial = 60
		fact.confidence_percent = mini(initial, _memory_confidence(snapshot.tick, report.observed_tick)) if report.has_estimate else 0
		if report.contradictory:
			fact.confidence_percent = mini(25, fact.confidence_percent)


func _assess_regions(snapshot: WorldSnapshot, result: StaffSituationSnapshot) -> void:
	for region in snapshot.strategic_regions:
		if not region.capturable or region.controller_faction_id == result.observer_faction_id:
			continue
		var candidate := _fact(result, "region:%s:capture" % region.region_id, StaffSituationFact.Category.OPPORTUNITY,
			StaffSituationFact.Kind.CAPTURE_CANDIDATE, &"STAFF_CAPTURE_CANDIDATE")
		candidate.region_id = region.region_id
		candidate.position = region.position
		candidate.current_value = region.supply_per_settlement
		# Confidence describes enemy evidence, not a probability of successful capture.
		candidate.confidence_percent = 0
		candidate.last_observed_tick = -1
		for evidence in result.facts:
			if evidence.category != StaffSituationFact.Category.THREAT:
				continue
			var relevant := evidence.region_id == region.region_id if evidence.report_id != 0 else evidence.position.distance_to(region.position) <= region.radius
			if relevant and evidence.confidence_percent > 0 and (evidence.confidence_percent > candidate.confidence_percent \
				or (evidence.confidence_percent == candidate.confidence_percent and evidence.last_observed_tick > candidate.last_observed_tick)):
				candidate.confidence_percent = evidence.confidence_percent
				candidate.last_observed_tick = evidence.last_observed_tick
		if candidate.confidence_percent == 0:
			var gap := _fact(result, "region:%s:unknown" % region.region_id, StaffSituationFact.Category.GAP,
				StaffSituationFact.Kind.UNKNOWN_REGION, &"STAFF_RECON_REQUIRED")
			gap.region_id = region.region_id
			gap.position = region.position
			gap.confidence_percent = 0
			gap.last_observed_tick = -1


func _assess_cards(snapshot: WorldSnapshot, result: StaffSituationSnapshot) -> void:
	for card in snapshot.unit_cards:
		if card.faction_id != result.observer_faction_id:
			continue
		var assessment := StaffCardAssessment.new()
		assessment.card_id = card.definition_id
		assessment.commander_id = card.commander_definition_id
		assessment.deployment_state = card.deployment_state
		assessment.control_state = card.control_state
		assessment.current_strength = card.current_strength
		assessment.available_strength = card.available_strength
		assessment.authorized_strength = card.authorized_strength
		assessment.position = card.center_position
		assessment.organization = card.organization
		assessment.organization_enabled = card.organization_enabled
		assessment.ammunition = card.ammunition
		assessment.ammunition_capacity = card.ammunition_capacity
		assessment.task_id = card.assigned_task_id
		assessment.supply_cost = card.supply_cost
		assessment.is_reserve = card.deployment_state == UnitCardState.DeploymentState.RESERVE and card.available_strength > 0
		assessment.can_allocate = card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.current_strength > 0 \
			and card.control_state in [UnitCardState.ControlState.AGENT_ASSIGNED, UnitCardState.ControlState.UNASSIGNED] \
			and not card.is_player_overridden and (not card.organization_enabled or card.organization > 0.0)
		assessment.reason_key = &"STAFF_CARD_ALLOCATABLE" if assessment.can_allocate else (&"STAFF_CARD_RESERVE" if assessment.is_reserve else &"STAFF_CARD_UNAVAILABLE")
		result.cards.append(assessment)
		if assessment.can_allocate:
			result.allocatable_strength += card.current_strength
		if assessment.is_reserve:
			result.reserve_strength += card.available_strength
		var strength := card.available_strength if assessment.is_reserve else card.current_strength
		if card.deployment_state not in [UnitCardState.DeploymentState.RESERVE, UnitCardState.DeploymentState.DEPLOYED]:
			continue
		if strength < card.authorized_strength:
			_card_gap(result, card, "strength", StaffSituationFact.Kind.STRENGTH_SHORTFALL, &"STAFF_REPLACEMENTS_REQUIRED", strength, card.authorized_strength)
		if card.organization_enabled and card.organization < LOW_ORGANIZATION:
			_card_gap(result, card, "organization", StaffSituationFact.Kind.LOW_ORGANIZATION, &"STAFF_RECOVERY_REQUIRED", card.organization, LOW_ORGANIZATION)
		if card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.ammunition_capacity > 0 and card.ammunition <= card.ammunition_capacity * LOW_AMMUNITION_RATIO:
			_card_gap(result, card, "ammunition", StaffSituationFact.Kind.LOW_AMMUNITION, &"STAFF_AMMUNITION_REQUIRED", card.ammunition, card.ammunition_capacity)
		if assessment.is_reserve and card.supply_cost > result.supply:
			_card_gap(result, card, "supply", StaffSituationFact.Kind.INSUFFICIENT_SUPPLY, &"STAFF_SUPPLY_REQUIRED", result.supply, card.supply_cost)
		var task := snapshot.get_task(card.assigned_task_id)
		if task != null and task.faction_id == result.observer_faction_id and task.lifecycle == TaskState.Lifecycle.BLOCKED:
			var fact := _card_gap(result, card, "task", StaffSituationFact.Kind.BLOCKED_TASK, &"STAFF_TASK_BLOCKED", 0, 0)
			fact.task_id = task.task_id
			fact.blocked_reason = task.blocked_reason
			fact.last_observed_tick = task.last_transition_tick


func _card_gap(result: StaffSituationSnapshot, card: UnitCardSnapshot, suffix: String, kind: StaffSituationFact.Kind, reason: StringName, current: float, required: float) -> StaffSituationFact:
	var fact := _fact(result, "card:%s:%s" % [card.definition_id, suffix], StaffSituationFact.Category.GAP, kind, reason)
	fact.card_id = card.definition_id
	fact.position = card.center_position
	fact.current_value = current
	fact.required_value = required
	return fact
