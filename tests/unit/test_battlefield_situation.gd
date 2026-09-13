class_name TestBattlefieldSituation
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_initial_situation_contract(failures)
	_test_determinism_and_value_copy(failures)
	_test_hidden_state_boundary(failures)
	_test_last_known_contact_age(failures)
	_test_supply_commitment(failures)
	_test_support_commitment(failures)
	_test_rejection_contract(failures)
	return failures


func _test_initial_situation_contract(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var situation := _project(world, snapshot)
	_expect(situation != null, "Grey Ridge player snapshot should produce a battlefield situation", failures)
	if situation == null:
		return
	_expect(situation.observer_faction_id == SimulationWorld.LOCAL_PLAYER_ID and situation.source_tick == snapshot.tick, "situation identity should preserve observer and source tick", failures)
	_expect(situation.card_statuses.size() == 6, "situation should expose all six Grey Ridge tactical cards", failures)
	_expect(situation.task_axes.size() >= 2, "initial deployed cards should expose whole-card task axes", failures)
	_expect(_known_threat_count(situation) >= 2, "initial central and western reports should produce known threat zones", failures)
	_expect(situation.frontline_segments.size() >= 2, "known pressure should produce estimated frontline segments", failures)
	_expect(not situation.uncertainty_zones.is_empty(), "faction knowledge should produce explicit unexplored or stale map zones", failures)
	_expect(int(situation.supply.get("available", -1)) == 5 and int(situation.supply.get("capacity", -1)) == 10, "situation should expose authoritative available and capacity Supply", failures)
	_expect(not (situation.supply.get("recovery_sources", []) as Array).is_empty(), "situation should name at least the base Supply recovery source", failures)


func _test_determinism_and_value_copy(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var first := _project(world, snapshot)
	var second := _project(world, snapshot)
	_expect(first != null and second != null and first.canonical_json() == second.canonical_json(), "identical faction snapshots should produce byte-equivalent situation DTOs", failures)
	_expect(first != null and second != null and first.fingerprint() == second.fingerprint(), "identical faction snapshots should preserve situation fingerprints", failures)
	if first == null:
		return
	var projector := BattlefieldSituationProjector.new()
	var cached := projector.project(snapshot, 1, world.battle_definition.battlefield_bounds)
	var cached_json := cached.canonical_json()
	cached.uncertainty_zones.clear()
	_expect(projector.project(snapshot, 1, world.battle_definition.battlefield_bounds).canonical_json() == cached_json, "mutating a projected result cannot corrupt the cached legal fog", failures)
	var changed := world.create_faction_snapshot(1)
	changed.knowledge.cells.fill(FactionKnowledge.CellState.VISIBLE)
	_expect(projector.project(changed, 1, world.battle_definition.battlefield_bounds).uncertainty_zones.is_empty(), "a changed visibility mask invalidates the cached fog", failures)
	_expect(projector.project(snapshot, 1, world.battle_definition.battlefield_bounds).canonical_json() == cached_json, "an older immutable snapshot remains projectable after a newer mask", failures)
	var before := first.canonical_json()
	if not snapshot.knowledge.cells.is_empty():
		snapshot.knowledge.cells[0] = FactionKnowledge.CellState.VISIBLE
	if not snapshot.unit_cards.is_empty():
		snapshot.unit_cards[0].current_strength = 999
	_expect(first.canonical_json() == before, "situation DTO must remain a value copy after its source snapshot is mutated", failures)


func _test_hidden_state_boundary(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var before := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var first := _project(world, before)
	var enemy := world.units[1001] as UnitState
	var original_position := enemy.position
	var original_health := enemy.health
	enemy.position = Vector2(5900.0, 320.0)
	enemy.health = 1.0
	var after := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var second := _project(world, after)
	_expect(first != null and second != null and first.fingerprint() == second.fingerprint(), "changing hidden enemy true state must not change the player situation overlay", failures)
	enemy.position = original_position
	enemy.health = original_health


func _test_last_known_contact_age(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var enemy := world.units[1001] as UnitState
	var knowledge := world.faction_knowledge[SimulationWorld.LOCAL_PLAYER_ID] as FactionKnowledge
	knowledge.hostile_contacts[enemy.entity_id] = KnowledgeContact.from_unit(enemy, 0)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	snapshot.tick = BattlefieldSituationProjector.CONTACT_AGING_TICKS + 10
	var situation := _project(world, snapshot)
	var found_stale := false
	if situation != null:
		for threat in situation.threat_zones:
			if int(threat["stale_count"]) > 0 and int(threat["age_ticks"]) >= BattlefieldSituationProjector.CONTACT_AGING_TICKS:
				found_stale = true
				break
	_expect(found_stale, "a lost contact should retain only its last-known position with explicit stale age", failures)


func _test_supply_commitment(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var reserve := world.unit_cards[&"thunder_fire_group"] as UnitCardState
	var command := DeployUnitCardCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, reserve.definition.definition_id,
		world.battle_definition.player_headquarters_position + Vector2(-160.0, -64.0)
	)
	var validation := world.submit_command(command)
	_expect(validation.is_accepted(), "Supply commitment fixture should accept a legal reserve deployment", failures)
	var snapshot := world.advance_tick()
	var situation := _project(world, snapshot)
	if situation == null:
		_expect(false, "deployed snapshot should produce a situation", failures)
		return
	_expect(int(situation.supply["available"]) == 5 - reserve.effective_supply_cost(), "available Supply should reflect the paid deployment cost", failures)
	_expect(int(situation.supply["committed"]) == reserve.effective_supply_cost(), "deploying card cost should remain visible as committed Supply", failures)
	var commitments := situation.supply["commitments"] as Array
	_expect(commitments.any(func(item: Dictionary) -> bool: return item["commitment_id"] == "deploy:thunder_fire_group" and int(item["remaining_ticks"]) > 0), "deployment commitment should expose subject and recovery time", failures)


func _test_support_commitment(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var command := SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, SupportOrderCommand.SupportKind.AIR_RECON, &"west_mine", &"central_relay"
	)
	var validation := world.submit_command(command)
	_expect(validation.is_accepted(), "support commitment fixture should accept legal air reconnaissance", failures)
	var situation := _project(world, world.advance_tick())
	if situation == null:
		_expect(false, "support snapshot should produce a situation", failures)
		return
	_expect(int(situation.supply["available"]) == 3 and int(situation.supply["committed"]) == 2, "active support should expose both paid available Supply and committed cost", failures)
	var commitments := situation.supply["commitments"] as Array
	_expect(commitments.any(func(item: Dictionary) -> bool: return item["commitment_id"] == "support:air_recon" and int(item["supply"]) == 2), "support commitment should use its typed battle definition cost", failures)


func _test_rejection_contract(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var projector := BattlefieldSituationProjector.new()
	_expect(projector.project(world.create_true_state_snapshot(), SimulationWorld.LOCAL_PLAYER_ID, world.battle_definition.battlefield_bounds) == null and projector.last_rejection_reason == &"TRUE_STATE_FORBIDDEN", "situation projector must reject diagnostic true-state snapshots", failures)
	_expect(projector.project(world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID), SimulationWorld.LOCAL_PLAYER_ID, world.battle_definition.battlefield_bounds) == null and projector.last_rejection_reason == &"WRONG_OBSERVER_FACTION", "situation projector must reject another faction's knowledge", failures)


func _project(world: SimulationWorld, snapshot: WorldSnapshot) -> BattlefieldSituationSnapshot:
	var support_costs := {}
	for support in world.battle_definition.support_abilities:
		support_costs[String(support.support_id)] = support.supply_cost
	return BattlefieldSituationProjector.new().project(
		snapshot,
		SimulationWorld.LOCAL_PLAYER_ID,
		world.battle_definition.battlefield_bounds,
		world.battle_definition.base_supply_interval_ticks,
		world.battle_definition.region_settlement_interval_ticks,
		support_costs
	)


func _known_threat_count(situation: BattlefieldSituationSnapshot) -> int:
	var count := 0
	for threat in situation.threat_zones:
		if bool(threat["known_threat"]):
			count += 1
	return count


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
