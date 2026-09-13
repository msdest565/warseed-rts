class_name BattlefieldSituationProjector
extends RefCounted

const CONTACT_RECENT_TICKS := 100
const CONTACT_AGING_TICKS := 250
const DEFAULT_BASE_SUPPLY_INTERVAL_TICKS := 200
const DEFAULT_REGION_SETTLEMENT_INTERVAL_TICKS := 300

var last_rejection_reason: StringName
var _uncertainty_cells := PackedByteArray()
var _uncertainty_grid_size := Vector2i.ZERO
var _uncertainty_bounds := Rect2()
var _uncertainty_cache: Array[Dictionary] = []
var _uncertainty_row_cells: Array[PackedByteArray] = []
var _uncertainty_row_results: Array[Array] = []


func project(
	snapshot: WorldSnapshot,
	observer_faction_id: int,
	battlefield_bounds: Rect2,
	base_supply_interval_ticks: int = DEFAULT_BASE_SUPPLY_INTERVAL_TICKS,
	region_settlement_interval_ticks: int = DEFAULT_REGION_SETTLEMENT_INTERVAL_TICKS,
	support_cost_by_id: Dictionary = {}
) -> BattlefieldSituationSnapshot:
	last_rejection_reason = &""
	if snapshot == null:
		last_rejection_reason = &"SNAPSHOT_REQUIRED"
		return null
	if snapshot.is_true_state:
		last_rejection_reason = &"TRUE_STATE_FORBIDDEN"
		return null
	if snapshot.observer_faction_id != observer_faction_id:
		last_rejection_reason = &"WRONG_OBSERVER_FACTION"
		return null
	if snapshot.knowledge == null or snapshot.knowledge.faction_id != observer_faction_id:
		last_rejection_reason = &"FACTION_KNOWLEDGE_REQUIRED"
		return null
	var faction := snapshot.get_faction(observer_faction_id)
	if faction == null:
		last_rejection_reason = &"OBSERVER_FACTION_REQUIRED"
		return null

	var cards := _derive_card_statuses(snapshot, observer_faction_id)
	var task_axes := _derive_task_axes(snapshot, cards)
	var threats := _derive_threat_zones(snapshot, observer_faction_id)
	var frontlines := _derive_frontlines(snapshot, cards, threats, observer_faction_id)
	var uncertainty := _derive_uncertainty(snapshot, battlefield_bounds)
	var supply := _derive_supply(
		snapshot, faction, cards, observer_faction_id,
		base_supply_interval_ticks, region_settlement_interval_ticks, support_cost_by_id
	)
	return BattlefieldSituationSnapshot.new(
		snapshot.tick, observer_faction_id, battlefield_bounds,
		frontlines, task_axes, threats, uncertainty, cards, supply
	)


func _derive_card_statuses(snapshot: WorldSnapshot, observer_faction_id: int) -> Array[Dictionary]:
	var cards: Array[UnitCardSnapshot] = []
	for card in snapshot.unit_cards:
		if card.faction_id == observer_faction_id:
			cards.append(card)
	cards.sort_custom(func(left: UnitCardSnapshot, right: UnitCardSnapshot) -> bool:
		return String(left.definition_id) < String(right.definition_id)
	)
	var result: Array[Dictionary] = []
	for card in cards:
		var task := snapshot.get_task(card.assigned_task_id) if card.assigned_task_id != 0 else null
		result.append({
			"card_id": card.definition_id,
			"display_name_key": card.display_name_key,
			"commander_id": card.commander_definition_id,
			"position": card.center_position,
			"current_strength": card.current_strength,
			"authorized_strength": card.authorized_strength,
			"deployment_state": card.deployment_state,
			"deployment_ticks_remaining": card.deployment_ticks_remaining,
			"supply_cost": card.supply_cost,
			"task_id": card.assigned_task_id,
			"task_kind": task.kind if task != null else -1,
			"task_phase": task.phase if task != null else -1,
			"task_lifecycle": task.lifecycle if task != null else -1,
			"blocked_reason": task.blocked_reason if task != null else TaskState.BlockedReason.NONE,
			"control_state": card.control_state,
			"organization": card.organization,
			"organization_enabled": card.organization_enabled,
			"fortified_ticks_remaining": card.fortified_ticks_remaining,
		})
	return result


func _derive_task_axes(snapshot: WorldSnapshot, cards: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in cards:
		var task_id := int(card["task_id"])
		if task_id == 0:
			continue
		var task := snapshot.get_task(task_id)
		if task == null or task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
			continue
		var start := card["position"] as Vector2
		if start.is_zero_approx() and not task.participant_entity_ids.is_empty():
			var participant := snapshot.get_unit(task.participant_entity_ids[0])
			start = participant.position if participant != null else task.target_position
		var route := task.route.duplicate()
		if route.size() < 2:
			route = task.planned_route.duplicate()
		if route.size() < 2:
			route = PackedVector2Array([start, task.target_position])
		elif not route[0].is_equal_approx(start):
			route.insert(0, start)
		result.append({
			"axis_id": "task:%08d:%s" % [task.task_id, card["card_id"]],
			"task_id": task.task_id,
			"card_id": card["card_id"],
			"display_name_key": card["display_name_key"],
			"route": route,
			"target_position": task.target_position,
			"kind": task.kind,
			"phase": task.phase,
			"lifecycle": task.lifecycle,
			"blocked_reason": task.blocked_reason,
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["axis_id"]) < String(right["axis_id"])
	)
	return result


func _derive_threat_zones(snapshot: WorldSnapshot, observer_faction_id: int) -> Array[Dictionary]:
	var regions := {}
	for region in snapshot.strategic_regions:
		regions[region.region_id] = region
	var zone_by_id := {}
	var reports: Array[IntelReportSnapshot] = []
	for report in snapshot.intel_reports:
		if not report.superseded:
			reports.append(report)
	reports.sort_custom(func(left: IntelReportSnapshot, right: IntelReportSnapshot) -> bool: return left.report_id < right.report_id)
	for report in reports:
		var region := regions.get(report.region_id) as StrategicRegionSnapshot
		if region == null:
			continue
		var zone_id := "region:%s" % report.region_id
		zone_by_id[zone_id] = {
			"zone_id": zone_id,
			"region_id": report.region_id,
			"position": region.position,
			"radius": maxf(160.0, region.radius),
			"visible_count": 0,
			"stale_count": 0,
			"estimated_min": report.estimated_min if report.has_estimate else 0,
			"estimated_max": report.estimated_max if report.has_estimate else 0,
			"has_estimate": report.has_estimate,
			"age_ticks": report.age_ticks,
			"freshness_key": report.freshness_key,
			"confidence_key": report.confidence_key,
			"source_key": report.source_key,
			"direction_key": report.direction_key,
			"last_seen_tick": report.observed_tick,
		}
	var hostile_units: Array[UnitSnapshot] = []
	for unit in snapshot.units:
		if unit.enabled and unit.faction_id != observer_faction_id:
			hostile_units.append(unit)
	hostile_units.sort_custom(func(left: UnitSnapshot, right: UnitSnapshot) -> bool: return left.entity_id < right.entity_id)
	for unit in hostile_units:
		var nearest_region := _nearest_region(unit.position, snapshot.strategic_regions)
		var zone_id := "contact:%08d" % unit.entity_id
		if nearest_region != null and unit.position.distance_to(nearest_region.position) <= nearest_region.radius * 1.75:
			zone_id = "region:%s" % nearest_region.region_id
		var zone := zone_by_id.get(zone_id, {}) as Dictionary
		if zone.is_empty():
			zone = {
				"zone_id": zone_id,
				"region_id": nearest_region.region_id if nearest_region != null else &"",
				"position": unit.position,
				"radius": maxf(128.0, nearest_region.radius if nearest_region != null else 128.0),
				"visible_count": 0,
				"stale_count": 0,
				"estimated_min": 0,
				"estimated_max": 0,
				"has_estimate": true,
				"age_ticks": maxi(0, snapshot.tick - unit.last_seen_tick),
				"freshness_key": _freshness_key(maxi(0, snapshot.tick - unit.last_seen_tick)),
				"confidence_key": &"INTEL_CONFIDENCE_HIGH" if unit.is_visible_to_local_player else &"INTEL_CONFIDENCE_MEDIUM",
				"source_key": &"INTEL_SOURCE_CONTACT",
				"direction_key": &"INTEL_DIRECTION_CURRENT",
				"last_seen_tick": unit.last_seen_tick,
			}
		zone["visible_count"] = int(zone["visible_count"]) + (1 if unit.is_visible_to_local_player else 0)
		zone["stale_count"] = int(zone["stale_count"]) + (0 if unit.is_visible_to_local_player else 1)
		zone["estimated_min"] = maxi(int(zone["estimated_min"]), int(zone["visible_count"]))
		zone["estimated_max"] = maxi(int(zone["estimated_max"]), int(zone["visible_count"]) + int(zone["stale_count"]))
		if unit.is_visible_to_local_player:
			zone["position"] = unit.position
			zone["age_ticks"] = 0
			zone["freshness_key"] = &"INTEL_FRESH_CURRENT"
			zone["confidence_key"] = &"INTEL_CONFIDENCE_HIGH"
			zone["last_seen_tick"] = snapshot.tick
		else:
			var age := maxi(0, snapshot.tick - unit.last_seen_tick)
			zone["age_ticks"] = mini(int(zone["age_ticks"]), age)
			zone["freshness_key"] = _freshness_key(int(zone["age_ticks"]))
		zone_by_id[zone_id] = zone
	var result: Array[Dictionary] = []
	var zone_ids := zone_by_id.keys()
	zone_ids.sort()
	for zone_id in zone_ids:
		var zone := zone_by_id[zone_id] as Dictionary
		zone["known_threat"] = int(zone["estimated_max"]) > 0 or int(zone["visible_count"]) > 0 or int(zone["stale_count"]) > 0
		result.append(zone)
	return result


func _derive_frontlines(
	snapshot: WorldSnapshot,
	cards: Array[Dictionary],
	threats: Array[Dictionary],
	observer_faction_id: int
) -> Array[Dictionary]:
	var friendly_positions: Array[Vector2] = []
	for card in cards:
		if int(card["deployment_state"]) == UnitCardState.DeploymentState.DEPLOYED and int(card["current_strength"]) > 0:
			friendly_positions.append(card["position"] as Vector2)
	if friendly_positions.is_empty():
		for building in snapshot.buildings:
			if building.faction_id == observer_faction_id and building.enabled:
				friendly_positions.append(building.position)
	var result: Array[Dictionary] = []
	for threat in threats:
		if not bool(threat["known_threat"]) or friendly_positions.is_empty():
			continue
		var threat_position := threat["position"] as Vector2
		var friendly_position := _nearest_position(threat_position, friendly_positions)
		var direction := (threat_position - friendly_position).normalized()
		if direction.is_zero_approx():
			direction = Vector2.UP
		var midpoint := friendly_position.lerp(threat_position, 0.5)
		var half_length := clampf(float(threat["radius"]) * 0.75, 150.0, 300.0)
		var tangent := direction.orthogonal() * half_length
		result.append({
			"segment_id": "front:%s" % threat["zone_id"],
			"start": midpoint - tangent,
			"end": midpoint + tangent,
			"friendly_anchor": friendly_position,
			"threat_anchor": threat_position,
			"confidence_key": threat["confidence_key"],
			"known_hostile_max": threat["estimated_max"],
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["segment_id"]) < String(right["segment_id"])
	)
	return result


func _derive_uncertainty(snapshot: WorldSnapshot, battlefield_bounds: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var knowledge := snapshot.knowledge
	if knowledge.grid_size == _uncertainty_grid_size and battlefield_bounds == _uncertainty_bounds and knowledge.cells == _uncertainty_cells:
		return _uncertainty_cache
	if knowledge.grid_size != _uncertainty_grid_size or battlefield_bounds != _uncertainty_bounds:
		_uncertainty_row_cells.clear()
		_uncertainty_row_results.clear()
		_uncertainty_row_cells.resize(knowledge.grid_size.y)
		_uncertainty_row_results.resize(knowledge.grid_size.y)
	_uncertainty_grid_size = knowledge.grid_size
	_uncertainty_bounds = battlefield_bounds
	_uncertainty_cells = knowledge.cells.duplicate()
	for y in range(knowledge.grid_size.y):
		var row_offset := y * knowledge.grid_size.x
		var row_cells := knowledge.cells.slice(row_offset, row_offset + knowledge.grid_size.x)
		if row_cells == _uncertainty_row_cells[y]:
			result.append_array(_uncertainty_row_results[y])
			continue
		var row_result: Array[Dictionary] = []
		var run_state := FactionKnowledge.CellState.VISIBLE
		var run_start := -1
		for x in range(knowledge.grid_size.x + 1):
			var state := FactionKnowledge.CellState.VISIBLE
			if x < knowledge.grid_size.x:
				state = knowledge.cells[row_offset + x] as FactionKnowledge.CellState
			if state == run_state:
				continue
			if run_start >= 0 and run_state != FactionKnowledge.CellState.VISIBLE:
				var world_rect := Rect2(
					LogicGrid.WORLD_ORIGIN + Vector2(run_start, y) * LogicGrid.CELL_SIZE,
					Vector2(x - run_start, 1) * LogicGrid.CELL_SIZE
				).intersection(battlefield_bounds)
				if world_rect.has_area():
					row_result.append({
						"zone_id": "fog:%03d:%03d:%d" % [y, run_start, run_state],
						"rect": world_rect,
						"state": run_state,
					})
			run_state = state
			run_start = x if state != FactionKnowledge.CellState.VISIBLE else -1
		_uncertainty_row_cells[y] = row_cells
		_uncertainty_row_results[y] = row_result
		result.append_array(row_result)
	_uncertainty_cache = result
	return result


func _derive_supply(
	snapshot: WorldSnapshot,
	faction: FactionSnapshot,
	cards: Array[Dictionary],
	observer_faction_id: int,
	base_interval: int,
	region_interval: int,
	support_cost_by_id: Dictionary
) -> Dictionary:
	base_interval = maxi(1, base_interval)
	region_interval = maxi(1, region_interval)
	var committed := 0
	var commitments: Array[Dictionary] = []
	for card in cards:
		if int(card["deployment_state"]) != UnitCardState.DeploymentState.DEPLOYING:
			continue
		var cost := int(card["supply_cost"])
		committed += cost
		commitments.append({
			"commitment_id": "deploy:%s" % card["card_id"],
			"kind": "deployment",
			"subject_id": card["card_id"],
			"supply": cost,
			"remaining_ticks": int(card["deployment_ticks_remaining"]),
		})
	var cooldowns := [
		["air_recon", faction.air_recon_cooldown_until_tick],
		["emergency_fortify", faction.fortify_cooldown_until_tick],
		["field_reinforcement", faction.reinforcement_cooldown_until_tick],
	]
	for item in cooldowns:
		var until_tick := int(item[1])
		if until_tick <= snapshot.tick:
			continue
		var cost := int(support_cost_by_id.get(item[0], 0))
		committed += cost
		commitments.append({
			"commitment_id": "support:%s" % item[0],
			"kind": "support",
			"subject_id": item[0],
			"supply": cost,
			"remaining_ticks": until_tick - snapshot.tick,
		})
	commitments.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left["commitment_id"]) < String(right["commitment_id"])
	)
	var recovery_sources: Array[Dictionary] = [{
		"source_id": &"base",
		"amount": 1,
		"remaining_ticks": base_interval - snapshot.tick % base_interval,
		"interval_ticks": base_interval,
	}]
	for region in snapshot.strategic_regions:
		if region.controller_faction_id != observer_faction_id or region.supply_per_settlement <= 0:
			continue
		var next_tick := region.last_settlement_tick + region_interval
		if next_tick <= snapshot.tick:
			next_tick = snapshot.tick + region_interval - snapshot.tick % region_interval
		recovery_sources.append({
			"source_id": region.region_id,
			"display_name_key": region.display_name_key,
			"amount": region.supply_per_settlement,
			"remaining_ticks": maxi(0, next_tick - snapshot.tick),
			"interval_ticks": region_interval,
		})
	recovery_sources.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_ticks := int(left["remaining_ticks"])
		var right_ticks := int(right["remaining_ticks"])
		return left_ticks < right_ticks or left_ticks == right_ticks and String(left["source_id"]) < String(right["source_id"])
	)
	return {
		"available": faction.supply,
		"committed": committed,
		"capacity": faction.supply_capacity,
		"population": faction.population,
		"population_capacity": faction.population_capacity,
		"commitments": commitments,
		"recovery_sources": recovery_sources,
	}


func _nearest_region(position: Vector2, regions: Array[StrategicRegionSnapshot]) -> StrategicRegionSnapshot:
	var nearest: StrategicRegionSnapshot
	var nearest_distance := INF
	for region in regions:
		var distance := position.distance_squared_to(region.position)
		if distance < nearest_distance or is_equal_approx(distance, nearest_distance) and (nearest == null or String(region.region_id) < String(nearest.region_id)):
			nearest = region
			nearest_distance = distance
	return nearest


func _nearest_position(origin: Vector2, candidates: Array[Vector2]) -> Vector2:
	var result := candidates[0]
	var distance := origin.distance_squared_to(result)
	for candidate in candidates:
		var candidate_distance := origin.distance_squared_to(candidate)
		var sorts_first := candidate.x < result.x or is_equal_approx(candidate.x, result.x) and candidate.y < result.y
		if candidate_distance < distance or is_equal_approx(candidate_distance, distance) and sorts_first:
			result = candidate
			distance = candidate_distance
	return result


func _freshness_key(age_ticks: int) -> StringName:
	if age_ticks < CONTACT_RECENT_TICKS:
		return &"INTEL_FRESH_CURRENT"
	if age_ticks < CONTACT_AGING_TICKS:
		return &"INTEL_FRESH_AGING"
	return &"INTEL_FRESH_STALE"
