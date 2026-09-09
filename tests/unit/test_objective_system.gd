class_name TestObjectiveSystem
extends RefCounted

const ESCORT_OBJECTIVES: BattleObjectiveSetDefinition = preload("res://data/objectives/r1_escort_victory.tres")
const WITHDRAWAL_OBJECTIVES: BattleObjectiveSetDefinition = preload("res://data/objectives/r1_ordered_withdrawal.tres")


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_objective_content_contract(failures)
	_test_four_operation_equivalence(failures)
	_test_same_tick_tie_break_and_terminal_freeze(failures)
	_test_two_layer_all_group(failures)
	_test_escort_victory_vertical_slice(failures)
	_test_ordered_withdrawal_vertical_slice(failures)
	return failures


func _test_objective_content_contract(failures: Array[String]) -> void:
	for scenario_id in [&"grey_ridge", &"broken_bridge", &"fog_forest", &"black_well"]:
		var loaded := BattleContentLoader.load_battle(scenario_id)
		_expect(loaded.is_valid(), "%s objective content should load and validate: %s" % [scenario_id, loaded.validation.issues], failures)
		if not loaded.is_valid():
			continue
		var objective_set := loaded.battle.objective_set
		_expect(objective_set != null and objective_set.objective_set_id == &"standard_card_battle", "%s should use the shared equivalent headquarters objective set" % scenario_id, failures)
		_expect(objective_set.objectives.size() == 3 and objective_set.conclusion_groups.size() == 3, "%s should expose three stable objectives and three deterministic conclusions" % scenario_id, failures)
	_expect(ESCORT_OBJECTIVES.validate(BattleContentLoader.load_battle(&"fog_forest").battle).is_valid(), "escort test objective set should validate against Fog Forest content", failures)
	_expect(WITHDRAWAL_OBJECTIVES.validate(BattleContentLoader.load_battle(&"black_well").battle).is_valid(), "withdrawal test objective set should validate against Black Well content", failures)


func _test_four_operation_equivalence(failures: Array[String]) -> void:
	var scenario_kinds := [
		SimulationWorld.ScenarioKind.GREY_RIDGE,
		SimulationWorld.ScenarioKind.BROKEN_BRIDGE,
		SimulationWorld.ScenarioKind.FOG_FOREST,
		SimulationWorld.ScenarioKind.BLACK_WELL,
	]
	for scenario_kind in scenario_kinds:
		var victory_world := SimulationWorld.new(true, false, scenario_kind)
		var before := victory_world.create_snapshot()
		victory_world.destroy_building(SimulationWorld.ENEMY_COMMAND_CENTER_ID)
		var victory_snapshot := victory_world.advance_tick()
		_expect(victory_snapshot.outcome.result == BattleOutcome.Result.VICTORY, "%s enemy-HQ destruction should remain a victory" % victory_world.get_scenario_id(), failures)
		_expect(victory_snapshot.outcome.conclusion_group_id == &"headquarters_victory", "%s victory should retain its structured reason" % victory_world.get_scenario_id(), failures)
		_expect(victory_snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID).victorious and victory_snapshot.get_faction(SimulationWorld.ENEMY_PLAYER_ID).defeated, "%s equivalent migration should preserve faction compatibility flags" % victory_world.get_scenario_id(), failures)
		_expect(victory_snapshot.get_objective(&"enemy_headquarters_destroyed").status == ObjectiveState.Status.COMPLETED, "%s winning objective should remain completed in the terminal snapshot" % victory_world.get_scenario_id(), failures)
		_expect(victory_snapshot.get_objective(&"player_headquarters_destroyed").status == ObjectiveState.Status.FAILED and victory_snapshot.get_objective(&"time_limit_reached").status == ObjectiveState.Status.FAILED, "%s unresolved objectives should become failed in the terminal snapshot" % victory_world.get_scenario_id(), failures)
		_expect(before.outcome.result == BattleOutcome.Result.ONGOING, "%s old snapshots must remain immutable after conclusion" % victory_world.get_scenario_id(), failures)
		_expect(before.get_objective(&"enemy_headquarters_destroyed").status == ObjectiveState.Status.ACTIVE, "%s old objective snapshots must remain immutable after conclusion" % victory_world.get_scenario_id(), failures)

		var defeat_world := SimulationWorld.new(true, false, scenario_kind)
		defeat_world.destroy_building(SimulationWorld.PLAYER_COMMAND_CENTER_ID)
		var defeat_snapshot := defeat_world.advance_tick()
		_expect(defeat_snapshot.outcome.result == BattleOutcome.Result.DEFEAT and defeat_snapshot.outcome.conclusion_group_id == &"headquarters_defeat", "%s player-HQ destruction should remain a defeat" % defeat_world.get_scenario_id(), failures)

		var timeout_world := SimulationWorld.new(true, false, scenario_kind)
		timeout_world.current_tick = timeout_world.battle_definition.time_limit_ticks - 1
		var timeout_snapshot := timeout_world.advance_tick()
		_expect(timeout_snapshot.outcome.result == BattleOutcome.Result.DEFEAT and timeout_snapshot.outcome.conclusion_group_id == &"time_limit_defeat", "%s time limit should remain an authoritative defeat" % timeout_world.get_scenario_id(), failures)
	_expect(ScenarioStatus.objective_status_marker_key(ObjectiveState.Status.ACTIVE) == &"OBJECTIVE_STATUS_ACTIVE", "objective HUD should expose an active marker", failures)
	_expect(ScenarioStatus.objective_status_marker_key(ObjectiveState.Status.COMPLETED) == &"OBJECTIVE_STATUS_COMPLETE", "objective HUD should expose a completed marker", failures)
	_expect(ScenarioStatus.objective_status_marker_key(ObjectiveState.Status.FAILED) == &"OBJECTIVE_STATUS_FAILED", "objective HUD should expose a failed marker", failures)


func _test_same_tick_tie_break_and_terminal_freeze(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	world.destroy_building(SimulationWorld.PLAYER_COMMAND_CENTER_ID)
	world.destroy_building(SimulationWorld.ENEMY_COMMAND_CENTER_ID)
	var snapshot := world.advance_tick()
	_expect(snapshot.outcome.result == BattleOutcome.Result.DEFEAT and snapshot.outcome.conclusion_group_id == &"headquarters_defeat", "same-tick mutual HQ destruction should use the higher-priority defeat tie-break", failures)
	var conclusion_events := 0
	for event in world.events:
		if event.kind == SimulationEvent.Kind.BATTLE_CONCLUDED:
			conclusion_events += 1
	_expect(conclusion_events == 1, "a battle should publish exactly one BATTLE_CONCLUDED event", failures)
	var frozen_tick := world.current_tick
	var rejected := world.submit_command(MoveCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, frozen_tick, 1, Vector2.ZERO))
	_expect(rejected.reason == CommandValidationResult.Reason.BATTLE_CONCLUDED, "commands after conclusion should reject with BATTLE_CONCLUDED", failures)
	world.advance_tick()
	_expect(world.current_tick == frozen_tick, "authoritative time should freeze after battle conclusion", failures)
	var conclusion_events_after := 0
	for event in world.events:
		if event.kind == SimulationEvent.Kind.BATTLE_CONCLUDED:
			conclusion_events_after += 1
	_expect(conclusion_events_after == 1, "frozen post-conclusion ticks must not emit duplicate conclusion events", failures)


func _test_two_layer_all_group(failures: Array[String]) -> void:
	var first := BattleObjectiveDefinition.new()
	first.objective_id = &"first_window"
	first.display_name_key = &"OBJECTIVE_FINISH_BEFORE_TIME_LIMIT"
	first.kind = BattleObjectiveDefinition.Kind.TIME_LIMIT_REACHED
	first.target_tick = 1
	var second := BattleObjectiveDefinition.new()
	second.objective_id = &"second_window"
	second.display_name_key = &"OBJECTIVE_FINISH_BEFORE_TIME_LIMIT"
	second.kind = BattleObjectiveDefinition.Kind.TIME_LIMIT_REACHED
	second.target_tick = 2
	var group := ObjectiveGroupDefinition.new()
	group.group_id = &"two_step_all"
	group.rule = ObjectiveGroupDefinition.Rule.ALL
	group.objective_ids.assign([&"first_window", &"second_window"])
	group.outcome_result = BattleOutcome.Result.VICTORY
	group.outcome_grade = BattleOutcome.Grade.TACTICAL
	var objective_set := BattleObjectiveSetDefinition.new()
	objective_set.objective_set_id = &"two_layer_test"
	objective_set.objectives.assign([first, second])
	objective_set.conclusion_groups.assign([group])
	var system := ObjectiveSystem.new()
	system.configure(objective_set)
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var target_events: Array[SimulationEvent] = []
	_expect(system.advance(world, target_events, 1).result == BattleOutcome.Result.ONGOING, "ALL group should remain active when only one child objective is complete", failures)
	_expect(system.advance(world, target_events, 2).result == BattleOutcome.Result.VICTORY, "ALL group should conclude after every child objective completes", failures)


func _test_escort_victory_vertical_slice(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.FOG_FOREST)
	world.objective_system.configure(ESCORT_OBJECTIVES)
	world.battle_outcome = world.objective_system.outcome
	var card := world.unit_cards.get(&"frontline_logistics_column") as UnitCardState
	var destination := world.strategic_regions.get(&"forward_supply_node") as StrategicRegionState
	if card == null or destination == null:
		_expect(false, "Fog Forest escort fixture requires the logistics card and forward node", failures)
		return
	for entity_id in card.member_entity_ids:
		var member := world.units.get(entity_id) as UnitState
		if member != null and member.enabled:
			member.position = destination.position
			member.desired_position = destination.position
	var snapshot := world.advance_tick()
	_expect(snapshot.outcome.result == BattleOutcome.Result.VICTORY and snapshot.outcome.grade == BattleOutcome.Grade.TACTICAL, "delivering a surviving logistics card should produce a tactical escort victory", failures)
	_expect(snapshot.outcome.conclusion_group_id == &"escort_victory" and world.escort_supply_node_active, "escort victory should retain its objective reason and authoritative node effect", failures)


func _test_ordered_withdrawal_vertical_slice(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	world.objective_system.configure(WITHDRAWAL_OBJECTIVES)
	world.battle_outcome = world.objective_system.outcome
	var card := world.unit_cards.get(&"blackwell_guard_battalion") as UnitCardState
	var withdrawal := world.strategic_regions.get(&"withdrawal_corridor") as StrategicRegionState
	if card == null or withdrawal == null:
		_expect(false, "Black Well withdrawal fixture requires the guard battalion and corridor", failures)
		return
	var commander := world.commanders.get(card.commander_definition_id) as CommanderState
	world._assign_commander_objective(commander, withdrawal.position, withdrawal.region_id)
	for entity_id in card.member_entity_ids:
		var survivor := world.units.get(entity_id) as UnitState
		if survivor != null and survivor.enabled:
			survivor.position = withdrawal.position
			survivor.desired_position = withdrawal.position
	var snapshot := world.advance_tick()
	_expect(snapshot.outcome.result == BattleOutcome.Result.ORDERED_WITHDRAWAL and snapshot.outcome.grade == BattleOutcome.Grade.ORDERED, "a complete-card corridor withdrawal should produce an ordered-withdrawal result", failures)
	_expect(not snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID).defeated and not snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID).victorious, "ordered withdrawal should not be collapsed into legacy victory/defeat flags", failures)
	var record := ArmyRosterStore.build_battle_record(snapshot)
	_expect(String(record.get("last_result", "")) == "ordered_withdrawal" and int(record.get("last_merit_award", 0)) == ArmyRosterStore.ORDERED_WITHDRAWAL_MERIT_AWARD, "campaign persistence should retain the ordered result and its distinct award tier", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
