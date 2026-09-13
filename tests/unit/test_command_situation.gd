class_name TestCommandSituation
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_card_action_projection(failures)
	_test_high_level_intent_command_pipeline(failures)
	_test_intent_validation_and_cancel(failures)
	_test_five_exception_contracts(failures)
	_test_exception_actions_match_current_control_state(failures)
	_test_determinism_value_copy_and_deduplication(failures)
	_test_knowledge_boundary_and_rejections(failures)
	return failures


func _test_high_level_intent_command_pipeline(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var command_id := world.allocate_command_id()
	var command := CommanderOrderCommand.new(
		command_id, SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_INTENT,
		SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay",
		CommanderState.Posture.AGGRESSIVE, PackedVector2Array(),
		StringName("intent:di_tian:%08d" % command_id), &"central_relay",
		CommanderState.ReservePolicy.REINFORCE_ON_REQUEST
	)
	_expect(world.submit_command(command).is_accepted(), "a complete high-level intent should enter the shared command queue", failures)
	var snapshot := world.advance_tick()
	var commander := world.commanders[&"di_tian"] as CommanderState
	_expect(commander.active_intent_id == command.intent_id, "the authoritative commander should retain the stable intent id", failures)
	_expect(commander.target_region_id == &"central_relay" and commander.intent_axis_region_id == &"central_relay", "intent objective and main axis should reach authoritative commander state", failures)
	_expect(commander.posture == CommanderState.Posture.AGGRESSIVE and commander.intent_reserve_policy == CommanderState.ReservePolicy.REINFORCE_ON_REQUEST, "intent risk and reserve policy should be applied atomically", failures)
	_expect(not commander.current_task_ids.is_empty(), "an accepted intent should create real whole-card tasks", failures)
	var projected := _project_command(world, snapshot)
	_expect(projected != null and projected.intents.size() == 1, "the legal player snapshot should expose the accepted intent", failures)
	if projected != null and not projected.intents.is_empty():
		var intent := projected.intents[0]
		_expect(intent.intent_id == command.intent_id and intent.task_ids == commander.current_task_ids, "intent DTO should preserve stable identity and assigned task ids", failures)
		var before := intent.to_dictionary()
		commander.clear_high_level_intent()
		commander.current_task_ids.clear()
		_expect(intent.to_dictionary() == before, "intent DTO should remain a deep value copy after world state changes", failures)


func _test_intent_validation_and_cancel(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var invalid := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_INTENT,
		SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"missing_region",
		CommanderState.Posture.BALANCED, PackedVector2Array(), &"intent:invalid", &"central_relay",
		CommanderState.ReservePolicy.HOLD
	)
	_expect(not world.submit_command(invalid).is_accepted(), "an intent with an unknown objective region must be rejected", failures)
	var valid_id := world.allocate_command_id()
	var valid := CommanderOrderCommand.new(
		valid_id, SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_INTENT,
		SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay",
		CommanderState.Posture.BALANCED, PackedVector2Array(), StringName("intent:di_tian:%08d" % valid_id),
		&"central_relay", CommanderState.ReservePolicy.HOLD
	)
	_expect(world.submit_command(valid).is_accepted(), "cancel fixture should accept its initial intent", failures)
	world.advance_tick()
	var commander := world.commanders[&"di_tian"] as CommanderState
	var previous_task_ids := commander.current_task_ids.duplicate()
	var cancel := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.CANCEL_INTENT
	)
	_expect(world.submit_command(cancel).is_accepted(), "cancel intent should use the same command pipeline", failures)
	world.advance_tick()
	_expect(commander.active_intent_id.is_empty() and commander.current_task_ids.is_empty(), "cancel intent should clear the authoritative intent and task list", failures)
	for task_id in previous_task_ids:
		var task := world.tasks.get(task_id) as TaskState
		_expect(task != null and task.lifecycle == TaskState.Lifecycle.CANCELLED, "cancel intent should explicitly terminate each open commander task", failures)


func _test_five_exception_contracts(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var target := snapshot.get_unit_card(&"ironwall_assault_group")
	var task := snapshot.get_task(target.assigned_task_id)
	target.organization_enabled = true
	target.organization = 10.0
	target.current_strength = 3
	target.authorized_strength = 12
	task.lifecycle = TaskState.Lifecycle.BLOCKED
	task.blocked_reason = TaskState.BlockedReason.PATH_UNAVAILABLE
	task.last_transition_tick = snapshot.tick
	var situation := _project_situation(world, snapshot)
	var threat := situation.threat_zones[0] as Dictionary
	target.center_position = threat["position"] as Vector2
	for card in situation.card_statuses:
		if card["card_id"] == target.definition_id:
			card["position"] = target.center_position
			card["organization_enabled"] = true
			card["organization"] = 10.0
			card["current_strength"] = 3
			card["authorized_strength"] = 12
			card["task_lifecycle"] = TaskState.Lifecycle.BLOCKED
			card["blocked_reason"] = TaskState.BlockedReason.PATH_UNAVAILABLE
		else:
			card["position"] = Vector2(8000.0, 8000.0)
	situation.supply["available"] = 0
	var command_situation := CommandSituationProjector.new().project(snapshot, situation, SimulationWorld.LOCAL_PLAYER_ID)
	_expect(command_situation != null, "legal exception fixture should produce a command situation", failures)
	if command_situation == null:
		return
	var kinds: Dictionary = {}
	for exception in command_situation.exceptions:
		kinds[exception.kind] = true
	_expect(kinds.has(CommandExceptionSnapshot.Kind.BLOCKED), "blocked tasks should become actionable exceptions", failures)
	_expect(kinds.has(CommandExceptionSnapshot.Kind.EXPOSED), "unsupported cards near known threats should become exposed exceptions", failures)
	_expect(kinds.has(CommandExceptionSnapshot.Kind.LOW_ORGANIZATION), "low organization should become an actionable exception", failures)
	_expect(kinds.has(CommandExceptionSnapshot.Kind.LOW_SUPPLY), "low authoritative Supply should become a theater exception", failures)
	_expect(kinds.has(CommandExceptionSnapshot.Kind.REINFORCEMENT_REQUEST), "low card strength should become a reinforcement request", failures)
	for exception in command_situation.exceptions:
		_expect(not exception.exception_id.is_empty() and not exception.reason_key.is_empty() and not exception.action_ids.is_empty(), "every exception should have stable identity, reason, and at least one legal action", failures)


func _test_exception_actions_match_current_control_state(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var situation := _project_situation(world, snapshot)
	var overridden_card := snapshot.get_unit_card(&"ironwall_assault_group")
	overridden_card.control_state = UnitCardState.ControlState.PLAYER_OVERRIDDEN
	overridden_card.return_formation_id = overridden_card.formation_id
	for card in situation.card_statuses:
		if card["card_id"] != &"ironwall_assault_group":
			continue
		card["organization_enabled"] = true
		card["organization"] = 10.0
		card["control_state"] = UnitCardState.ControlState.PLAYER_OVERRIDDEN
	var projected := CommandSituationProjector.new().project(snapshot, situation, SimulationWorld.LOCAL_PLAYER_ID)
	var low_organization: CommandExceptionSnapshot
	for exception in projected.exceptions:
		if exception.kind == CommandExceptionSnapshot.Kind.LOW_ORGANIZATION and exception.unit_card_id == &"ironwall_assault_group":
			low_organization = exception
			break
	_expect(low_organization != null, "a player-overridden low-organization card should remain visible as an exception", failures)
	if low_organization != null:
		_expect(low_organization.action_ids[0] == CommandExceptionSnapshot.Action.RETURN_TO_COMMANDER, "a player-overridden card must offer the executable return action instead of a misleading commander retreat", failures)
		_expect(not low_organization.action_ids.has(CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER), "a player-overridden card must not advertise a retreat that cannot control that card", failures)

	for card in situation.card_statuses:
		if card["card_id"] == &"ironwall_assault_group":
			card["commander_id"] = &"missing_commander"
			card["control_state"] = UnitCardState.ControlState.AGENT_ASSIGNED
	overridden_card.control_state = UnitCardState.ControlState.AGENT_ASSIGNED
	projected = CommandSituationProjector.new().project(snapshot, situation, SimulationWorld.LOCAL_PLAYER_ID)
	low_organization = null
	for exception in projected.exceptions:
		if exception.kind == CommandExceptionSnapshot.Kind.LOW_ORGANIZATION and exception.unit_card_id == &"ironwall_assault_group":
			low_organization = exception
			break
	_expect(low_organization != null and low_organization.action_ids[0] == CommandExceptionSnapshot.Action.FOCUS, "an exception without a legal commander must offer a harmless focus action instead of a command guaranteed to fail", failures)


func _test_determinism_value_copy_and_deduplication(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var situation := _project_situation(world, snapshot)
	var projector := CommandSituationProjector.new()
	var first := projector.project(snapshot, situation, SimulationWorld.LOCAL_PLAYER_ID)
	var second := projector.project(snapshot, situation, SimulationWorld.LOCAL_PLAYER_ID)
	_expect(first != null and second != null and first.canonical_json() == second.canonical_json(), "identical legal inputs should produce byte-equivalent command situations", failures)
	_expect(first != null and second != null and first.fingerprint() == second.fingerprint(), "identical legal inputs should preserve command-situation fingerprints", failures)
	if first == null:
		return
	var ids: Dictionary = {}
	for exception in first.exceptions:
		_expect(not ids.has(exception.exception_id), "a root condition should appear only once in the exception queue", failures)
		ids[exception.exception_id] = true
	var before := first.canonical_json()
	if not situation.card_statuses.is_empty():
		situation.card_statuses[0]["organization"] = -999.0
	if not snapshot.commanders.is_empty():
		snapshot.commanders[0].active_intent_id = &"mutated"
	_expect(first.canonical_json() == before, "command situation must remain a value copy after source DTOs are mutated", failures)
	var report := GameplayObservabilityReport.new(&"grey_ridge", &"fixture", &"fixture", 1701, SimulationWorld.LOCAL_PLAYER_ID, world.battle_definition.time_limit_ticks)
	var report_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var report_situation := _project_command(world, report_snapshot)
	_expect(report.start(report_snapshot) and report.observe_command_situation(report_situation), "gameplay observer should accept the legal command situation", failures)
	var empty_situation := CommandSituationSnapshot.new(report_snapshot.tick + 1, SimulationWorld.LOCAL_PLAYER_ID, [], [])
	_expect(report.observe_command_situation(empty_situation), "gameplay observer should accept an empty follow-up situation", failures)
	var exception_summary := report.create_report().get("exception_summary", {}) as Dictionary
	_expect(int(exception_summary.get("unique", 0)) == report_situation.exceptions.size(), "gameplay report should count unique exception roots", failures)
	_expect(int(exception_summary.get("resolved", 0)) == report_situation.exceptions.size(), "gameplay report should record automatic exception resolution", failures)


func _test_knowledge_boundary_and_rejections(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var before_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var before := _project_command(world, before_snapshot)
	var enemy := world.units[1001] as UnitState
	var original_position := enemy.position
	var original_health := enemy.health
	enemy.position = Vector2(6000.0, 300.0)
	enemy.health = 1.0
	var after_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var after := _project_command(world, after_snapshot)
	_expect(before != null and after != null and before.fingerprint() == after.fingerprint(), "changing only hidden hostile true state must not change player exceptions", failures)
	enemy.position = original_position
	enemy.health = original_health
	var projector := CommandSituationProjector.new()
	var legal_situation := _project_situation(world, world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID))
	_expect(projector.project(world.create_true_state_snapshot(), legal_situation, SimulationWorld.LOCAL_PLAYER_ID) == null and projector.last_rejection_reason == &"TRUE_STATE_FORBIDDEN", "command projector must reject diagnostic true-state snapshots", failures)
	var enemy_snapshot := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	var enemy_situation := BattlefieldSituationProjector.new().project(enemy_snapshot, SimulationWorld.ENEMY_PLAYER_ID, world.battle_definition.battlefield_bounds)
	_expect(projector.project(enemy_snapshot, enemy_situation, SimulationWorld.LOCAL_PLAYER_ID) == null and projector.last_rejection_reason == &"WRONG_OBSERVER_FACTION", "command projector must reject another faction's knowledge", failures)


func _project_command(world: SimulationWorld, snapshot: WorldSnapshot) -> CommandSituationSnapshot:
	return CommandSituationProjector.new().project(snapshot, _project_situation(world, snapshot), SimulationWorld.LOCAL_PLAYER_ID)


func _project_situation(world: SimulationWorld, snapshot: WorldSnapshot) -> BattlefieldSituationSnapshot:
	var support_costs := {}
	for support in world.battle_definition.support_abilities:
		support_costs[String(support.support_id)] = support.supply_cost
	return BattlefieldSituationProjector.new().project(
		snapshot, SimulationWorld.LOCAL_PLAYER_ID, world.battle_definition.battlefield_bounds,
		world.battle_definition.base_supply_interval_ticks,
		world.battle_definition.region_settlement_interval_ticks, support_costs
	)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _test_card_action_projection(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var projector := CardActionProjector.new()
	var card := snapshot.get_unit_card(&"ironwall_assault_group")
	card.current_strength = card.authorized_strength - 1
	var actions := projector.project(snapshot, world.battle_definition)
	var reinforcement: CardActionSnapshot
	var reserve: CardActionSnapshot
	for action in actions:
		if action.unit_card_id == card.definition_id and action.action_kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
			reinforcement = action
		if action.action_kind == CardActionSnapshot.DEPLOY:
			reserve = action
	_expect(reinforcement != null, "even one casualty must create a named reinforcement decision without selecting a card", failures)
	_expect(reserve != null and reserve.radius == world.battle_definition.deployment_radius and reserve.population_required > 0, "reserve decisions must expose real available strength and the HQ targeting radius", failures)
	if reinforcement == null:
		return
	var original_strength := reinforcement.current_strength
	card.current_strength = 0
	_expect(reinforcement.current_strength == original_strength, "card decisions must copy values rather than retain mutable source cards", failures)
	var faction := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	faction.supply = 0
	for action in projector.project(snapshot, world.battle_definition):
		_expect(action.reason == CommandValidationResult.Reason.INSUFFICIENT_SUPPLY, "unaffordable card decisions must remain visible with a Supply reason", failures)
	faction.supply = 100
	faction.population = faction.population_capacity
	for action in projector.project(snapshot, world.battle_definition):
		if action.action_kind in [CardActionSnapshot.DEPLOY, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT]:
			_expect(action.reason == CommandValidationResult.Reason.POPULATION_FULL, "full population must explain blocked reserve and reinforcement decisions", failures)
	faction.population = 0
	faction.reinforcement_cooldown_until_tick = snapshot.tick + 40
	for action in projector.project(snapshot, world.battle_definition):
		if action.action_kind == SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT:
			_expect(action.cooldown_ticks == 40 and action.reason == CommandValidationResult.Reason.SUPPORT_COOLDOWN, "reinforcement decisions must show the exact remaining cooldown", failures)
	snapshot.is_true_state = true
	_expect(projector.project(snapshot, world.battle_definition).is_empty(), "card decisions must reject true-state snapshots", failures)
	snapshot.is_true_state = false
	snapshot.observer_faction_id = SimulationWorld.ENEMY_PLAYER_ID
	_expect(projector.project(snapshot, world.battle_definition).is_empty(), "card decisions must reject mismatched faction knowledge", failures)
	var black := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	var black_snapshot := black.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var deployed: UnitCardSnapshot
	for candidate in black_snapshot.unit_cards:
		if candidate.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
			deployed = candidate
			break
	if deployed != null:
		var member := black_snapshot.get_unit(deployed.active_member_entity_ids[0])
		member.health -= 1.0
		var logistics := false
		var mobility := false
		for action in projector.project(black_snapshot, black.battle_definition):
			if action.unit_card_id == deployed.definition_id:
				logistics = logistics or action.action_kind == SupportOrderCommand.SupportKind.FRONTLINE_LOGISTICS
				mobility = mobility or action.action_kind == SupportOrderCommand.SupportKind.RAPID_MOBILITY
		_expect(logistics and mobility, "Black Well must expose logistics for wounded surviving members and mobility without hidden selection", failures)
	var private_faction := black.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
	private_faction.opened_engineering_route_ids.append(&"own_route")
	var old_snapshot := FactionSnapshot.new(private_faction)
	private_faction.opened_engineering_route_ids.append(&"later_route")
	_expect(old_snapshot.opened_engineering_route_ids == [&"own_route"] and FactionSnapshot.new(private_faction, false).opened_engineering_route_ids.is_empty(), "engineering route receipts must be copied and excluded from other factions' private snapshots", failures)
