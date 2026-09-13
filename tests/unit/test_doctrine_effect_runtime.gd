class_name TestDoctrineEffectRuntime
extends RefCounted

const GOLDEN_SHA256 := "6f25498076d942bc0474796ddc632fad517d02d5bfcddb577c85cee5ffdca266"


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_golden_trajectory(failures)
	_test_registry_boundaries(failures)
	_test_authoritative_renaming_and_values(failures)
	return failures


func _world() -> SimulationWorld:
	var plan := ArmyPlan.grey_ridge_default()
	plan.starting_unit_card_ids.assign([&"armored_spearhead", &"ironwall_assault_group"])
	return SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, &"central_assault", plan)


func _definition() -> DoctrineDefinition:
	return (load("res://data/army/alternating_cover.tres") as DoctrineDefinition).duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as DoctrineDefinition


func _order(world: SimulationWorld) -> CommandValidationResult:
	return world.submit_command(CommanderOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, &"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"))


func _test_golden_trajectory(failures: Array[String]) -> void:
	var world := _world()
	var trace: Array = []
	for step in range(61):
		if step in [0, 5, 18]:
			_expect(_order(world).is_accepted(), "golden commander order must pass the shared queue", failures)
		if step == 2:
			_expect(world.submit_command(UnitCardControlCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, &"armored_spearhead", UnitCardControlCommand.Action.TAKEOVER)).is_accepted(), "golden takeover must pass", failures)
		if step == 8:
			_expect(world.submit_command(UnitCardControlCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, &"armored_spearhead", UnitCardControlCommand.Action.RETURN_TO_COMMANDER)).is_accepted(), "golden return must pass", failures)
		var snapshot := world.advance_tick()
		var row: Dictionary = {"tick": snapshot.tick, "tasks": [], "units": [], "cards": [], "commander_reason": snapshot.get_commander(&"di_tian").behavior_reason_key}
		for task in snapshot.tasks:
			row.tasks.append([task.task_id, task.unit_card_id, task.activation_tick, task.lifecycle, task.phase, task.target_position, task.last_detail])
		for unit in snapshot.units:
			row.units.append([unit.entity_id, unit.position, unit.health, unit.assigned_task_id, unit.control_state])
		for card in snapshot.unit_cards:
			row.cards.append([card.definition_id, card.control_state, card.assigned_task_id, card.current_strength])
		trace.append(row)
	var trace_hash := JSON.stringify(trace).sha256_text()
	print("WARSEED_R3_GOLDEN_TRACE hash=%s" % trace_hash)
	_expect(trace_hash == GOLDEN_SHA256, "61 tick staged departure/takeover/return/reorder trajectory must match the updated tactical baseline", failures)


func _evaluate(registry: DoctrineEffectRegistry, snapshot: WorldSnapshot, definitions: Array[DoctrineDefinition]) -> DoctrineTaskParameters:
	return registry.create_task_parameters(snapshot, SimulationWorld.LOCAL_PLAYER_ID, &"di_tian", &"ironwall_assault_group", definitions)


func _test_registry_boundaries(failures: Array[String]) -> void:
	var world := _world()
	var registry := DoctrineEffectRegistry.new()
	var definition := _definition()
	var definitions: Array[DoctrineDefinition] = [definition]
	var snapshot := world.create_snapshot()
	var result := _evaluate(registry, snapshot, definitions)
	_expect(result.applied and result.activation_tick == snapshot.tick + 20 and result.trigger_tick == snapshot.tick, "the second deployed card must receive the authored delay", failures)
	var copied := result.duplicate_value()
	definition.effects[0].timing.interval_ticks = 73
	definition.effects[0].reason.waiting_reason_key = &"CHANGED_TEST_KEY"
	_expect(result.activation_tick == snapshot.tick + 20 and result.waiting_reason_key == &"COMMANDER_REASON_ALTERNATING_COVER_TIMING" and copied.activation_tick == result.activation_tick, "effect parameters must own values, not live Resource references", failures)
	definition = _definition()
	definitions.assign([definition])
	snapshot.is_true_state = true
	_expect(_evaluate(registry, snapshot, definitions).rejection_reason == &"TRUE_STATE_FORBIDDEN", "true state must be rejected", failures)
	snapshot.is_true_state = false
	snapshot.observer_faction_id = SimulationWorld.ENEMY_PLAYER_ID
	_expect(_evaluate(registry, snapshot, definitions).rejection_reason == &"WRONG_OBSERVER_FACTION", "foreign observations must be rejected", failures)
	snapshot.observer_faction_id = SimulationWorld.LOCAL_PLAYER_ID
	snapshot.knowledge = null
	_expect(_evaluate(registry, snapshot, definitions).rejection_reason == &"FACTION_KNOWLEDGE_REQUIRED", "unfiltered snapshots without faction knowledge must be rejected", failures)
	snapshot = world.create_snapshot()
	snapshot.get_unit_card(&"ironwall_assault_group").control_state = UnitCardState.ControlState.PLAYER_OVERRIDDEN
	_expect(_evaluate(registry, snapshot, definitions).rejection_reason == &"CARD_NOT_ELIGIBLE", "effects may not replace a player-overridden card task", failures)
	snapshot = world.create_snapshot()
	# The effect is a formation timing rule: even polluted enemy observations
	# must not influence its own-card ordinal or timing.
	for unit in snapshot.units:
		if unit.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			unit.position = Vector2(-99999, 99999)
			unit.health = 99999
	var injected_enemy := UnitState.new(999999, Vector2(-99999, 99999), 180.0, SimulationWorld.ENEMY_PLAYER_ID)
	injected_enemy.health = 99999
	snapshot.units.append(UnitSnapshot.new(injected_enemy))
	snapshot.tasks.clear()
	snapshot.enemy_reactions.clear()
	_expect(_evaluate(registry, snapshot, definitions).activation_tick == result.activation_tick, "enemy facts and foreign task metadata must not influence departure timing", failures)
	definition.effects[0].timing.interval_ticks = -1
	_expect(_evaluate(registry, snapshot, definitions).rejection_reason == &"INVALID_EFFECT_DEFINITION", "invalid runtime definitions must not partially apply", failures)
	definition.effects.clear()
	var compatible := _evaluate(registry, snapshot, definitions)
	_expect(not compatible.applied and compatible.rejection_reason.is_empty(), "legacy empty effects must leave task timing to the compatibility path", failures)
	var alpha := _definition()
	alpha.definition_id = &"alpha_cover"
	alpha.effects[0].timing.interval_ticks = 11
	var zeta := _definition()
	zeta.definition_id = &"zeta_cover"
	zeta.effects[0].timing.interval_ticks = 31
	snapshot.get_commander(&"di_tian").equipped_doctrine_ids.assign([zeta.definition_id, alpha.definition_id])
	var forward := _evaluate(registry, snapshot, [zeta, alpha])
	var reverse := _evaluate(registry, snapshot, [alpha, zeta])
	_expect(forward.applied and forward.doctrine_id == alpha.definition_id and forward.activation_tick == snapshot.tick + 11 and reverse.activation_tick == forward.activation_tick, "diagnostic multi-slot timing conflicts must resolve by stable doctrine ID, independent of input order", failures)


func _test_authoritative_renaming_and_values(failures: Array[String]) -> void:
	var world := _world()
	var renamed := _definition()
	renamed.definition_id = &"renamed_cover"
	renamed.effects[0].timing.interval_ticks = 7
	world.doctrine_definitions[renamed.definition_id] = renamed
	var commander := world.commanders[&"di_tian"] as CommanderState
	commander.available_doctrine_ids = commander.available_doctrine_ids.duplicate()
	commander.available_doctrine_ids.append(renamed.definition_id)
	var equip := EquipDoctrineCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, &"di_tian", renamed.definition_id)
	_expect(world.submit_command(equip).is_accepted(), "renamed typed doctrine must equip through the public command pipeline", failures)
	world.advance_tick()
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var task := world.tasks[card.assigned_task_id] as TaskState
	_expect(task.activation_tick == 7 and task.doctrine_effect != null and task.doctrine_effect.doctrine_id == renamed.definition_id, "renaming the doctrine must not disable kind dispatch; authored timing must reach the task", failures)
	_expect(commander.behavior_reason_key == renamed.effects[0].reason.waiting_reason_key, "commander feedback must consume the applied effect reason after renaming", failures)
	var snapshot := world.create_snapshot()
	var old_effect := snapshot.get_task(task.task_id).doctrine_effect
	_expect(old_effect != null and old_effect.effect_id == &"staged_departure" and old_effect.exit_condition == DoctrineCounterplayDefinition.ExitCondition.PLAYER_OVERRIDE_OR_TASK_END, "task snapshots must expose effect trigger and exit semantics", failures)
	if old_effect != null:
		task.doctrine_effect.waiting_reason_key = &"CHANGED_TASK_KEY"
		task.doctrine_effect.trigger_tick = 999
		_expect(old_effect.waiting_reason_key == &"COMMANDER_REASON_ALTERNATING_COVER_TIMING" and old_effect.trigger_tick == 0, "old snapshots must retain copied effect metadata", failures)
	_expect(_order(world).is_accepted() and _order(world).is_accepted(), "same-tick reorders must remain valid commands", failures)
	var accepted_tick := world.current_tick
	world.advance_tick()
	var replacement := world.tasks[card.assigned_task_id] as TaskState
	_expect(replacement.activation_tick == accepted_tick + 7 and task.lifecycle == TaskState.Lifecycle.CANCELLED, "same-tick replacement must terminate the old effect and use the new task trigger tick", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
