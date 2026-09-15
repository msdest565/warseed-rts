class_name TestSimulationWorld
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(TestEnemyOperation.new().run())
	failures.append_array(TestCompositionPersistence.new().run())
	failures.append_array(TestControlHandoff.new().run())
	failures.append_array(TestDoctrineEffectRuntime.new().run())
	_test_fixed_tick_movement(failures)
	_test_arrival_without_overshoot(failures)
	_test_snapshot_is_value_copy(failures)
	_test_deterministic_replay(failures)
	_test_default_formation_and_snapshot_copy(failures)
	_test_army_roster_snapshot_tracks_real_entities(failures)
	_test_grey_ridge_initial_state(failures)
	_test_grey_ridge_prebattle_army_plan(failures)
	_test_grey_ridge_reserve_deployment(failures)
	_test_grey_ridge_safe_reserve_deployment_exit(failures)
	_test_grey_ridge_deployment_validation(failures)
	_test_grey_ridge_region_control_and_settlement(failures)
	_test_strategic_region_capture_lifecycle(failures)
	_test_enemy_strategic_recon_attack_and_capture(failures)
	_test_grey_ridge_support_orders(failures)
	_test_black_well_extended_support_orders(failures)
	_test_black_well_doctrine_execution(failures)
	_test_grey_ridge_unit_card_takeover_and_return(failures)
	_test_grey_ridge_independent_commander_orders(failures)
	_test_commander_disengage_ends_reconnaissance(failures)
	_test_grey_ridge_commander_objective_moves_unit_card(failures)
	_test_grey_ridge_commander_behavior_feedback(failures)
	_test_grey_ridge_commander_outlook_uses_legal_intelligence(failures)
	_test_grey_ridge_doctrine_constraints(failures)
	_test_grey_ridge_locked_enemy_reactions_use_faction_knowledge(failures)
	_test_grey_ridge_locked_plan_advances_on_headquarters(failures)
	_test_no_intervention_grey_ridge_produces_combat(failures)
	_test_grey_ridge_terrain_role_behaviors(failures)
	_test_grey_ridge_multisegment_route_and_line(failures)
	_test_shared_formation_response_is_faction_symmetric(failures)
	_test_persistent_task_formations_auto_attack_in_range(failures)
	_test_commander_focus_fire_and_conditional_reinforcement(failures)
	_test_commander_multi_card_autonomous_engagement(failures)
	_test_formation_commands_survive_member_casualties(failures)
	_test_coordinated_combat_resumes_strategic_task(failures)
	_test_blocked_commander_task_replans_to_reachable_position(failures)
	_test_grey_ridge_battle_loss_persistence(failures)
	_test_shared_roster_cross_scenario_persistence(failures)
	_test_grey_ridge_post_battle_progression(failures)
	_test_data_driven_growth_modifiers(failures)
	_test_army_roster_v1_migration(failures)
	_test_formation_member_snapshot_without_unit_path(failures)
	_test_stale_formation_command_after_withdrawal(failures)
	_test_stuck_detection_and_recovery(failures)
	_test_destroyed_unit_wreck_expires(failures)
	return failures


func _test_stale_formation_command_after_withdrawal(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	var formation_id := (world.unit_cards[&"blackwell_guard_battalion"] as UnitCardState).formation_id
	var formation := world.formations[formation_id] as FormationState
	var stale_command := FormationMoveCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, formation.leader_entity_id, formation_id, formation.anchor_position
	)
	world.formations.erase(formation_id)
	world._apply_command(stale_command)
	_expect(not world.formations.has(formation_id), "a queued formation command should become a safe no-op when complete-card withdrawal removes its formation before application", failures)


func _test_shared_formation_response_is_faction_symmetric(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	world.tasks.clear()
	var friendly := world.formations[SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID] as FormationState
	var hostile := world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	var friendly_anchor := Vector2(1400.0, 1200.0)
	var hostile_anchor := Vector2(1600.0, 1200.0)
	for setup in [[friendly, friendly_anchor], [hostile, hostile_anchor]]:
		var formation := setup[0] as FormationState
		var anchor := setup[1] as Vector2
		formation.anchor_position = anchor
		formation.is_moving = false
		formation.order_kind = FormationState.OrderKind.IDLE
		formation.order_target_entity_id = 0
		for index in range(formation.member_entity_ids.size()):
			var member := world.units[formation.member_entity_ids[index]] as UnitState
			member.position = anchor + Vector2(float(index % 4) * 12.0, float(index / 4) * 12.0)
			member.assigned_task_id = 0
	for formation_id in [SimulationWorld.GREY_RIDGE_FALCON_FORMATION_ID, SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID]:
		for entity_id in (world.formations[formation_id] as FormationState).member_entity_ids:
			(world.units[entity_id] as UnitState).enabled = false
	world._update_faction_knowledge()
	world._update_shared_formation_responses()
	var friendly_response := false
	var hostile_response := false
	for queued in world.command_queue.snapshot():
		if not queued is AttackCommand:
			continue
		var attack := queued as AttackCommand
		friendly_response = friendly_response or attack.formation_id == friendly.formation_id and attack.issuer_id == SimulationWorld.LOCAL_PLAYER_ID
		hostile_response = hostile_response or attack.formation_id == hostile.formation_id and attack.issuer_id == SimulationWorld.ENEMY_PLAYER_ID
	_expect(friendly_response and hostile_response, "idle opposing formations should use the same knowledge-limited autonomous response logic for both factions", failures)


func _test_persistent_task_formations_auto_attack_in_range(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var friendly := world.formations[SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID] as FormationState
	var hostile := world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	var friendly_anchor := Vector2(1400.0, 1200.0)
	var hostile_anchor := Vector2(1540.0, 1200.0)
	_set_test_formation_position(world, friendly, friendly_anchor)
	_set_test_formation_position(world, hostile, hostile_anchor)
	for index in range(hostile.member_entity_ids.size()):
		(world.units[hostile.member_entity_ids[index]] as UnitState).enabled = index == 1
	for formation_id in [SimulationWorld.GREY_RIDGE_FALCON_FORMATION_ID, SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID]:
		for entity_id in (world.formations[formation_id] as FormationState).member_entity_ids:
			(world.units[entity_id] as UnitState).enabled = false
	var persistent_task := world.tasks[(world.units[friendly.leader_entity_id] as UnitState).assigned_task_id] as TaskState
	_expect(persistent_task != null and persistent_task.persistent_order, "test fixture should retain the real commander persistent task", failures)
	world._update_faction_knowledge()
	world._update_shared_formation_responses()
	var friendly_attack_queued := false
	var hostile_attack_queued := false
	for queued in world.command_queue.snapshot():
		if queued is AttackCommand:
			var attack := queued as AttackCommand
			friendly_attack_queued = friendly_attack_queued or attack.formation_id == friendly.formation_id and hostile.member_entity_ids.has(attack.attack_target_entity_id)
			hostile_attack_queued = hostile_attack_queued or attack.formation_id == hostile.formation_id and friendly.member_entity_ids.has(attack.attack_target_entity_id)
	_expect(friendly_attack_queued, "a friendly formation must auto-attack an in-range hostile without dropping its persistent commander task", failures)
	_expect(hostile_attack_queued, "the same in-range auto-attack rule must remain faction symmetric", failures)
	_expect(not (world.units[hostile.leader_entity_id] as UnitState).enabled, "the hostile response fixture should cover a formation whose stable leader has been destroyed", failures)
	world.advance_tick()
	_expect(world.projectiles.size() > 0, "accepted autonomous formation attacks should reach the authoritative combat system and fire", failures)


func _test_commander_focus_fire_and_conditional_reinforcement(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var armor := world.unit_cards[&"armored_spearhead"] as UnitCardState
	world._apply_unit_card_deployment(DeployUnitCardCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, armor.definition.definition_id, headquarters.position + Vector2(128.0, 0.0), &"di_tian"
	))
	armor.deployment_ticks_remaining = 1
	world._advance_unit_card_deployments()
	var ironwall := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var primary := world.formations[ironwall.formation_id] as FormationState
	var reinforcement := world.formations[armor.formation_id] as FormationState
	var hostile := world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	var contact_position := Vector2(1500.0, 1000.0)
	_set_test_formation_position(world, primary, contact_position + Vector2(0.0, 150.0))
	_set_test_formation_position(world, reinforcement, contact_position + Vector2(0.0, 700.0))
	_set_test_formation_position(world, hostile, contact_position)
	for index in range(8, hostile.member_entity_ids.size()):
		(world.units[hostile.member_entity_ids[index]] as UnitState).enabled = false
	for entity_id in primary.member_entity_ids:
		var member := world.units[entity_id] as UnitState
		member.health = member.max_health * 0.2
	world._update_faction_knowledge()
	world._update_commander_combat_coordination()
	var primary_target := 0
	var reinforcement_target := 0
	for queued in world.command_queue.snapshot():
		if not queued is AttackCommand:
			continue
		var attack := queued as AttackCommand
		if attack.formation_id == primary.formation_id:
			primary_target = attack.attack_target_entity_id
		elif attack.formation_id == reinforcement.formation_id:
			reinforcement_target = attack.attack_target_entity_id
	_expect(primary_target != 0 and reinforcement_target == primary_target, "a commander should focus the engaged card and a viable rear reinforcement on one visible target", failures)
	var primary_task := world._task_for_unit_card(ironwall.definition.definition_id)
	_expect(primary_task != null and primary_task.reinforcement_committed, "the commander task should record a conditional reinforcement commitment", failures)

	var sufficient_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var sufficient_primary_card := sufficient_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var sufficient_primary := sufficient_world.formations[sufficient_primary_card.formation_id] as FormationState
	var sufficient_hostile := sufficient_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	_set_test_formation_position(sufficient_world, sufficient_primary, contact_position + Vector2(0.0, 150.0))
	_set_test_formation_position(sufficient_world, sufficient_hostile, contact_position)
	for index in range(1, sufficient_hostile.member_entity_ids.size()):
		(sufficient_world.units[sufficient_hostile.member_entity_ids[index]] as UnitState).enabled = false
	sufficient_world._update_faction_knowledge()
	sufficient_world._update_commander_combat_coordination()
	var reserve_deployment_queued := false
	for queued in sufficient_world.command_queue.snapshot():
		reserve_deployment_queued = reserve_deployment_queued or queued is DeployUnitCardCommand
	_expect(not reserve_deployment_queued, "a commander must not spend or deploy reserves when the engaged force is already sufficient", failures)

	var insufficient_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var insufficient_headquarters := insufficient_world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var insufficient_armor := insufficient_world.unit_cards[&"armored_spearhead"] as UnitCardState
	insufficient_world._apply_unit_card_deployment(DeployUnitCardCommand.new(
		insufficient_world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		insufficient_world.current_tick, insufficient_armor.definition.definition_id,
		insufficient_headquarters.position + Vector2(128.0, 0.0), &"di_tian"
	))
	insufficient_armor.deployment_ticks_remaining = 1
	insufficient_world._advance_unit_card_deployments()
	var insufficient_ironwall := insufficient_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var insufficient_primary := insufficient_world.formations[insufficient_ironwall.formation_id] as FormationState
	var insufficient_reinforcement := insufficient_world.formations[insufficient_armor.formation_id] as FormationState
	var insufficient_hostile := insufficient_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	_set_test_formation_position(insufficient_world, insufficient_primary, contact_position + Vector2(0.0, 150.0))
	_set_test_formation_position(insufficient_world, insufficient_reinforcement, contact_position + Vector2(0.0, 700.0))
	_set_test_formation_position(insufficient_world, insufficient_hostile, contact_position)
	for index in range(8, insufficient_hostile.member_entity_ids.size()):
		(insufficient_world.units[insufficient_hostile.member_entity_ids[index]] as UnitState).enabled = false
	for weak_card in [insufficient_ironwall, insufficient_armor]:
		for entity_id in (weak_card as UnitCardState).member_entity_ids:
			var member := insufficient_world.units[entity_id] as UnitState
			member.health = member.max_health * 0.1
	insufficient_world._update_faction_knowledge()
	insufficient_world._update_commander_combat_coordination()
	var doomed_reinforcement_queued := false
	for queued in insufficient_world.command_queue.snapshot():
		if queued is AttackCommand and (queued as AttackCommand).formation_id == insufficient_reinforcement.formation_id:
			doomed_reinforcement_queued = true
	_expect(doomed_reinforcement_queued, "deployed cards under one commander should answer a nearby shared threat instead of leaving the first card to fight alone", failures)


func _test_commander_multi_card_autonomous_engagement(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var armor := world.unit_cards[&"armored_spearhead"] as UnitCardState
	world._apply_unit_card_deployment(DeployUnitCardCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, armor.definition.definition_id, headquarters.position + Vector2(128.0, 0.0), &"di_tian"
	))
	armor.deployment_ticks_remaining = 1
	world._advance_unit_card_deployments()
	var ironwall := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var primary := world.formations[ironwall.formation_id] as FormationState
	var support := world.formations[armor.formation_id] as FormationState
	var primary_start := primary.anchor_position
	var support_start := support.anchor_position
	var shared_objective := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"
	)
	_expect(world.submit_command(shared_objective).is_accepted(), "a commander objective should accept once for every subordinate card", failures)
	for _tick in range(40):
		world.advance_tick()
	var primary_task := world._task_for_unit_card(ironwall.definition.definition_id)
	var support_task := world._task_for_unit_card(armor.definition.definition_id)
	_expect(primary_task != null and support_task != null and primary_task.task_id != support_task.task_id, "one commander objective should create coordinated whole-card tasks for both deployed cards", failures)
	_expect(primary.anchor_position.distance_to(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION) < primary_start.distance_to(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION), "the commander's first card should move toward the shared objective (start=%s current=%s task=%s/%s)" % [primary_start, primary.anchor_position, TaskState.Lifecycle.keys()[primary_task.lifecycle], TaskState.Phase.keys()[primary_task.phase]], failures)
	_expect(support.anchor_position.distance_to(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION) < support_start.distance_to(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION), "the commander's second card should move toward the shared objective instead of waiting at headquarters (start=%s current=%s task=%s/%s)" % [support_start, support.anchor_position, TaskState.Lifecycle.keys()[support_task.lifecycle], TaskState.Phase.keys()[support_task.phase]], failures)
	var hostile := world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	var contact := Vector2(1800.0, 1300.0)
	_set_test_formation_position(world, primary, contact + Vector2(-260.0, 0.0))
	_set_test_formation_position(world, support, contact + Vector2(-640.0, 0.0))
	_set_test_formation_position(world, hostile, contact)
	for index in range(hostile.member_entity_ids.size()):
		(world.units[hostile.member_entity_ids[index]] as UnitState).enabled = index == 0
	for entity_id in (world.formations[SimulationWorld.GREY_RIDGE_FALCON_FORMATION_ID] as FormationState).member_entity_ids:
		(world.units[entity_id] as UnitState).enabled = false
	world._update_faction_knowledge()
	world._update_commander_combat_coordination()
	var targets_by_formation := {}
	for queued in world.command_queue.snapshot():
		if queued is AttackCommand:
			targets_by_formation[(queued as AttackCommand).formation_id] = (queued as AttackCommand).attack_target_entity_id
	_expect(targets_by_formation.has(primary.formation_id) and targets_by_formation.has(support.formation_id), "one visible shared threat should coordinate every nearby deployed combat card under the same commander", failures)
	_expect(targets_by_formation.get(primary.formation_id, 0) == targets_by_formation.get(support.formation_id, -1), "coordinated cards should receive the same stable target", failures)
	_set_test_formation_position(world, primary, contact + Vector2(-140.0, 0.0))
	world.advance_tick()
	world.advance_tick()
	var firing_members := {}
	for event in world.events:
		if event.kind == SimulationEvent.Kind.PROJECTILE_FIRED and primary.member_entity_ids.has(event.entity_id):
			firing_members[event.entity_id] = true
	_expect(firing_members.size() > 1, "whole-card combat should produce fire from multiple capable members instead of only the formation leader", failures)


func _test_formation_commands_survive_member_casualties(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var formation := world.formations[card.formation_id] as FormationState
	(world.units[formation.leader_entity_id] as UnitState).enabled = false
	(world.units[formation.member_entity_ids[1]] as UnitState).enabled = false
	var move := FormationMoveCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, formation.leader_entity_id, formation.formation_id,
		formation.anchor_position + Vector2(-256.0, -192.0)
	)
	move.agent_id = (world.commanders[&"di_tian"] as CommanderState).agent_id
	move.task_id = card.assigned_task_id
	var move_result := world.submit_command(move)
	_expect(move_result.is_accepted(), "a whole-card move must remain valid after its stable leader and another member become casualties (result=%s)" % move_result.describe(), failures)
	for entity_id in formation.member_entity_ids:
		(world.units[entity_id] as UnitState).enabled = false
	var destroyed_move := FormationMoveCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.AGENT,
		world.current_tick, formation.leader_entity_id, formation.formation_id,
		formation.anchor_position + Vector2(-256.0, -192.0)
	)
	destroyed_move.agent_id = move.agent_id
	destroyed_move.task_id = move.task_id
	_expect(world.submit_command(destroyed_move).reason == CommandValidationResult.Reason.ENTITY_DISABLED, "a formation command should reject only after the entire card has been destroyed", failures)


func _test_coordinated_combat_resumes_strategic_task(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var task := world._task_for_unit_card(card.definition.definition_id)
	var formation := world.formations[card.formation_id] as FormationState
	var hostile := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	task.coordinated_target_entity_id = hostile.entity_id
	task.coordinated_support_until_tick = world.current_tick + 10
	formation.order_kind = FormationState.OrderKind.ATTACK_TARGET
	formation.order_target_entity_id = hostile.entity_id
	hostile.enabled = false
	world.strategic_task_system.advance(world)
	_expect(task.coordinated_target_entity_id == 0 and task.phase == TaskState.Phase.RETURNING, "destroying a coordinated target should clear tactical state and resume the original strategic objective", failures)


func _test_blocked_commander_task_replans_to_reachable_position(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var task := world._task_for_unit_card(card.definition.definition_id)
	var formation := world.formations[card.formation_id] as FormationState
	task.final_target_position = SimulationWorld.GREY_RIDGE_CENTRAL_POSITION
	task.target_position = Vector2(-100.0, -100.0)
	task.planned_route = PackedVector2Array([Vector2(-100.0, -100.0)])
	task.set_lifecycle(TaskState.Lifecycle.BLOCKED, world.current_tick - StrategicTaskSystem.BLOCKED_REPLAN_INTERVAL_TICKS, TaskState.BlockedReason.PATH_UNAVAILABLE, "fixture")
	world.strategic_task_system.advance(world)
	_expect(task.lifecycle == TaskState.Lifecycle.EXECUTING and task.phase in [TaskState.Phase.PREPARING, TaskState.Phase.MUSTERING], "a persistent commander task should resume after replacing a blocked route", failures)
	_expect(task.planned_route.is_empty() and task.target_position.is_finite() and not task.target_position.is_equal_approx(formation.anchor_position), "blocked-route recovery should clear the stale route and choose a reachable deployment position", failures)


func _test_grey_ridge_locked_plan_advances_on_headquarters(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT)
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			unit.enabled = false
	for _tick in range(SimulationWorld.GREY_RIDGE_OFFENSIVE_FOLLOWUP_TICK + 700):
		world.advance_tick()
	var headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var logged_followup := false
	for entry in world.enemy_reaction_log:
		logged_followup = logged_followup or entry.contains("source=LOCKED_PLAN_TIMELINE") and entry.contains("EXPLOIT_PLAYER_HEADQUARTERS")
	_expect(world.enemy_offensive_followup_executed and logged_followup, "the locked enemy opening should deterministically continue from regional occupation toward the player headquarters", failures)
	_expect(headquarters.health < headquarters.max_health, "the locked offensive follow-up should reach weapon range and produce real headquarters damage", failures)


func _test_no_intervention_grey_ridge_produces_combat(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT)
	var combat_damage_observed := false
	for _tick in range(3200):
		world.advance_tick()
		for unit_variant in world.units.values():
			var unit := unit_variant as UnitState
			if not unit.enabled or unit.health < unit.max_health:
				combat_damage_observed = true
				break
		if combat_damage_observed:
			break
	_expect(combat_damage_observed and world.current_tick < SimulationWorld.GREY_RIDGE_TIME_LIMIT_TICKS, "a no-intervention battle should produce autonomous contact and real combat before the timeout", failures)


func _set_test_formation_position(world: SimulationWorld, formation: FormationState, anchor: Vector2) -> void:
	formation.anchor_position = anchor
	formation.target_position = anchor
	formation.order_destination = anchor
	formation.is_moving = false
	formation.order_kind = FormationState.OrderKind.IDLE
	formation.order_target_entity_id = 0
	for index in range(formation.member_entity_ids.size()):
		var member := world.units[formation.member_entity_ids[index]] as UnitState
		member.position = anchor + Vector2(float(index % 4) * 10.0, float(index / 4) * 10.0)
		member.desired_position = member.position


func _test_grey_ridge_multisegment_route_and_line(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var formation := world.formations[card.formation_id] as FormationState
	var waypoint := formation.anchor_position + Vector2(64.0, -192.0)
	var target := formation.anchor_position + Vector2(0.0, -384.0)
	var line_start := target + Vector2(0.0, -176.0)
	var line_end := target + Vector2(0.0, 176.0)
	var command := FormationMoveCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, world.current_tick,
		formation.leader_entity_id, formation.formation_id, target,
		PackedVector2Array([waypoint]), line_start, line_end, true
	)
	var route_result := world.submit_command(command)
	_expect(route_result.is_accepted(), "whole-card route with a final line should pass authoritative validation (reason=%s)" % route_result.reason, failures)
	world.advance_tick()
	var route_snapshot := world.create_snapshot().get_formation(formation.formation_id)
	_expect(route_snapshot.planned_route == PackedVector2Array([waypoint]) and route_snapshot.has_deployment_line, "formation snapshot should preserve the player-authored route and line", failures)
	for _tick in range(260):
		if not formation.is_moving:
			break
		world.advance_tick()
	_expect(not formation.is_moving, "formation should complete a bounded multi-segment route", failures)
	for slot_id in range(formation.member_entity_ids.size()):
		var member := world.units[formation.member_entity_ids[slot_id]] as UnitState
		if not member.enabled:
			continue
		_expect(member.position.distance_to(line_start.lerp(line_end, float(slot_id) / float(formation.member_entity_ids.size() - 1))) <= 0.1, "every surviving card member should finish on its stable line slot", failures)
	world._apply_attack(AttackCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, world.current_tick,
		formation.leader_entity_id, SimulationWorld.DEFAULT_ENEMY_UNIT_ID,
		formation.formation_id
	))
	_expect(not formation.has_deployment_line, "a new attack order should clear the previous deployment line before pursuing", failures)


func _test_grey_ridge_prebattle_army_plan(failures: Array[String]) -> void:
	var validation_world := SimulationWorld.new(false, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var default_plan := ArmyPlan.grey_ridge_default()
	_expect(validation_world.get_grey_ridge_army_plan_errors(default_plan).is_empty(), "the authored Grey Ridge default army plan should satisfy capacity, doctrine, posture, and deployment constraints", failures)
	var overloaded_plan := default_plan.duplicate_plan()
	for unit_card_id in ArmyPlan.UNIT_CARD_IDS:
		overloaded_plan.set_unit_card_commander(unit_card_id, &"bai_jiuyang")
	_expect(validation_world.get_grey_ridge_army_plan_errors(overloaded_plan).has(&"ARMY_PLAN_ERROR_CAPACITY"), "prebattle validation should reject command assignments above a commander's visible capacity", failures)

	var custom_plan := default_plan.duplicate_plan()
	custom_plan.set_unit_card_commander(&"falcon_recon_group", &"bai_jiuyang")
	custom_plan.set_unit_card_commander(&"thunder_fire_group", &"bai_jiuyang")
	custom_plan.set_unit_card_commander(&"armored_spearhead", &"di_tian")
	custom_plan.set_unit_card_commander(&"ironwall_assault_group", &"lin_mo")
	custom_plan.set_commander_doctrine(&"bai_jiuyang", &"alternating_cover")
	custom_plan.set_commander_doctrine(&"di_tian", &"concentrated_breakthrough")
	custom_plan.starting_unit_card_ids.assign([&"thunder_fire_group", &"armored_spearhead"])
	_expect(validation_world.get_grey_ridge_army_plan_errors(custom_plan).is_empty(), "a legal cross-commander composition should pass authoritative prebattle validation", failures)
	var world := SimulationWorld.new(
		true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {},
		SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT, custom_plan
	)
	var snapshot := world.create_snapshot()
	var local_faction := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var thunder := snapshot.get_unit_card(&"thunder_fire_group")
	var armor := snapshot.get_unit_card(&"armored_spearhead")
	var falcon := snapshot.get_unit_card(&"falcon_recon_group")
	var ironwall := snapshot.get_unit_card(&"ironwall_assault_group")
	_expect(local_faction.population == 14 and snapshot.units.filter(func(unit: UnitSnapshot) -> bool: return unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID).size() == 14, "the selected six-entity fire group and eight-entity armor group should define the real opening population", failures)
	_expect(thunder.deployment_state == UnitCardState.DeploymentState.DEPLOYED and thunder.formation_id == 1 and armor.deployment_state == UnitCardState.DeploymentState.DEPLOYED and armor.formation_id == 2, "the selected starting cards should unfold into the two stable friendly formations", failures)
	_expect(falcon.deployment_state == UnitCardState.DeploymentState.RESERVE and ironwall.deployment_state == UnitCardState.DeploymentState.RESERVE, "cards omitted from the starting pair should remain visible headquarters reserves", failures)
	_expect(thunder.commander_definition_id == &"bai_jiuyang" and ironwall.commander_definition_id == &"lin_mo", "unit-card snapshots should expose mutable prebattle command relationships instead of definition defaults", failures)
	var bai := snapshot.get_commander(&"bai_jiuyang")
	var lin := snapshot.get_commander(&"lin_mo")
	_expect(bai.subordinate_unit_card_ids.has(&"thunder_fire_group") and bai.equipped_doctrine_ids.has(&"alternating_cover"), "the custom plan should authoritatively change Bai's subordinates and doctrine", failures)
	_expect(lin.subordinate_unit_card_ids.has(&"ironwall_assault_group") and not lin.subordinate_unit_card_ids.has(&"thunder_fire_group"), "reassigned cards should appear under exactly one commander", failures)


func _test_grey_ridge_battle_loss_persistence(failures: Array[String]) -> void:
	var first_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var first_card := first_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	for entity_id in first_card.member_entity_ids.slice(-2):
		(first_world.units[entity_id] as UnitState).enabled = false
	var record := ArmyRosterStore.build_battle_record(first_world.create_snapshot())
	var card_record := (record["cards"] as Dictionary)["ironwall_assault_group"] as Dictionary
	_expect(int(card_record["available_strength"]) == 10 and int(card_record["cumulative_losses"]) == 2, "battle record should write real card losses by stable ID", failures)
	var second_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, record)
	var second_card := second_world.create_snapshot().get_unit_card(&"ironwall_assault_group")
	_expect(second_card.current_strength == 10 and second_card.cumulative_losses == 2 and second_card.battles_survived == 1, "a second Grey Ridge match should restore the surviving persistent card strength", failures)
	var reserve := second_world.unit_cards[&"armored_spearhead"] as UnitCardState
	_expect(reserve.available_strength == reserve.definition.authorized_strength, "an uncommitted reserve card must not be recorded as entirely lost", failures)


func _test_shared_roster_cross_scenario_persistence(failures: Array[String]) -> void:
	var grey_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var grey_ironwall := grey_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	for entity_id in grey_ironwall.member_entity_ids.slice(-2):
		(grey_world.units[entity_id] as UnitState).enabled = false
	var grey_record := ArmyRosterStore.build_battle_record(grey_world.create_snapshot(), {}, &"grey_ridge")

	var black_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL, grey_record)
	var inherited_ironwall := black_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	_expect(inherited_ironwall.available_strength == 10 and inherited_ironwall.cumulative_losses == 2, "matching stable card IDs should inherit losses across different operations", failures)
	var guard := black_world.unit_cards[&"blackwell_guard_battalion"] as UnitCardState
	guard.organization = 43.0
	guard.deployment_state = UnitCardState.DeploymentState.WITHDRAWN
	guard.withdrawn_strength = guard.available_strength
	for entity_id in guard.member_entity_ids:
		var member := black_world.units.get(entity_id) as UnitState
		if member != null:
			member.enabled = false
	var black_record := ArmyRosterStore.build_battle_record(black_world.create_snapshot(), grey_record, &"black_well")
	var guard_record := (black_record.get("cards", {}) as Dictionary).get("blackwell_guard_battalion", {}) as Dictionary
	_expect(int(black_record.get("battle_count", 0)) == 2 and (black_record.get("cards", {}) as Dictionary).has("ironwall_assault_group"), "a later operation should merge its results into the existing shared roster", failures)
	_expect(is_equal_approx(float(guard_record.get("organization", 0.0)), 43.0) and String(guard_record.get("last_status", "")) == "withdrawn" and String(guard_record.get("last_scenario_id", "")) == "black_well", "shared records should preserve organization, withdrawal status, and the last operation per card", failures)

	var next_grey_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, black_record)
	var merged_record := ArmyRosterStore.build_battle_record(next_grey_world.create_snapshot(), black_record, &"grey_ridge")
	_expect((merged_record.get("cards", {}) as Dictionary).has("blackwell_guard_battalion"), "building a smaller operation record must retain cards that only exist in other operations", failures)
	_expect(ArmyRosterStore.campaign_record_path_for_session("shared-roster", &"grey_ridge") == ArmyRosterStore.campaign_record_path_for_session("shared-roster", &"black_well"), "all operations in one isolated session should resolve to the same campaign roster path", failures)
	_expect(ArmyRosterStore.campaign_record_path_for_session("other-session", &"black_well") != ArmyRosterStore.campaign_record_path_for_session("shared-roster", &"black_well"), "shared operation records must remain isolated between playtest sessions", failures)


func _test_grey_ridge_post_battle_progression(failures: Array[String]) -> void:
	var first_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var player := first_world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
	player.victorious = true
	var ironwall := first_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	for entity_id in ironwall.member_entity_ids.slice(-2):
		(first_world.units[entity_id] as UnitState).enabled = false
	var record := ArmyRosterStore.build_battle_record(first_world.create_snapshot())
	_expect(int(record.get("replacement_points", 0)) == ArmyRosterStore.VICTORY_REPLACEMENT_AWARD and int(record.get("merit", 0)) == ArmyRosterStore.VICTORY_MERIT_AWARD, "victory should grant the locked replacement and merit awards exactly once per battle record", failures)
	var batch_record := record.duplicate(true)
	_expect(ArmyRosterStore.affordable_replacements(batch_record, &"ironwall_assault_group") == 2, "prebattle refit should report how many missing members are currently affordable", failures)
	_expect(ArmyRosterStore.replenish_card_as_much_as_possible(batch_record, &"ironwall_assault_group") == 2, "one refit action should restore every currently affordable missing member", failures)
	var batch_card := ((batch_record["cards"] as Dictionary)["ironwall_assault_group"] as Dictionary)
	_expect(int(batch_card["available_strength"]) == 12 and int(batch_record["replacement_points"]) == 8, "batch refit should reach authorized strength and deduct the per-member cost exactly", failures)
	_expect(ArmyRosterStore.replenish_card(record, &"ironwall_assault_group"), "a damaged card should accept one affordable replacement", failures)
	var card_record := (record["cards"] as Dictionary)["ironwall_assault_group"] as Dictionary
	_expect(int(card_record["available_strength"]) == 11 and int(record["replacement_points"]) == 10 and int(record["campaign_days"]) == 1, "replacement should restore one member, deduct two points, and advance one campaign day", failures)
	_expect(ArmyRosterStore.award_collective_commendation(record, &"ironwall_assault_group"), "a surviving card with three merit should accept Collective Commendation", failures)
	_expect(int(record["merit"]) == 0 and ArmyRosterStore.replacement_cost(record, &"ironwall_assault_group") == 3, "Collective Commendation should spend merit and raise future replacement cost", failures)
	_expect(ArmyRosterStore.replenish_card(record, &"ironwall_assault_group"), "an honored damaged card should still replenish when the increased cost is affordable", failures)
	_expect(int(card_record["available_strength"]) == 12 and int(record["replacement_points"]) == 7 and int(record["campaign_days"]) == 2, "honored replenishment should spend three points without exceeding authorized strength", failures)
	_expect(not ArmyRosterStore.replenish_card(record, &"ironwall_assault_group"), "a full card must reject further replacement", failures)
	_expect(ArmyRosterStore.install_reinforced_side_skirts(record, &"ironwall_assault_group"), "an affordable card should accept reinforced side skirts", failures)
	_expect(int(record["replacement_points"]) == 1 and int(record["campaign_days"]) == 4, "side-skirt refit should spend six replacement points and two campaign days", failures)

	var second_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, record)
	var second_card := second_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var member := second_world.units[second_card.member_entity_ids[0]] as UnitState
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(member.definition_id)
	_expect(is_equal_approx(member.base_attack_damage, definition.combat.attack_power * 1.1), "Collective Commendation should apply +10% authoritative attack damage", failures)
	_expect(is_equal_approx(member.base_armor, definition.combat.armor + 2.0) and is_equal_approx(member.base_move_speed, definition.move_speed * 0.9), "reinforced side skirts should apply armor and movement tradeoffs to real entities", failures)
	var modified_damage := member.base_attack_damage
	var modified_armor := member.base_armor
	second_world.apply_unit_card_persistent_modifiers(second_card)
	_expect(is_equal_approx(member.base_attack_damage, modified_damage) and is_equal_approx(member.base_armor, modified_armor), "reapplying a persistent record must rebuild from definitions without compounding modifiers", failures)

	var deployment_record := ArmyRosterStore.build_battle_record(first_world.create_snapshot())
	_expect(ArmyRosterStore.award_collective_commendation(deployment_record, &"armored_spearhead"), "a reserve card in the persistent roster should be eligible for an earned commendation", failures)
	var deployment_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, deployment_record)
	var armored_card := deployment_world.create_snapshot().get_unit_card(&"armored_spearhead")
	_expect(armored_card.supply_cost == 5, "honor tradeoff should be visible as the reserve card's effective deployment cost", failures)
	var headquarters := deployment_world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var deploy := DeployUnitCardCommand.new(deployment_world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, 0, &"armored_spearhead", headquarters.position + Vector2(128.0, 0.0))
	_expect(deployment_world.submit_command(deploy).is_accepted(), "an honored reserve should deploy when all five supply are available", failures)
	deployment_world.advance_tick()
	_expect((deployment_world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).supply == 0, "authoritative deployment should deduct the honored card's effective cost", failures)


func _test_data_driven_growth_modifiers(failures: Array[String]) -> void:
	var initial_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var record := ArmyRosterStore.build_battle_record(initial_world.create_snapshot())
	record["merit"] = 12
	record["replacement_points"] = 20
	_expect(ArmyRosterStore.apply_growth(record, &"falcon_recon_group", &"eyes_of_advance"), "an eligible card should accept a selected honor from the data-driven pool", failures)
	_expect(ArmyRosterStore.apply_growth(record, &"falcon_recon_group", &"long_range_optics"), "the same card should independently accept one selected equipment item", failures)
	_expect(not ArmyRosterStore.apply_growth(record, &"falcon_recon_group", &"breakthrough_banner"), "a card with an honor must reject a second honor", failures)
	_expect(int(record.get("merit", 0)) == 9 and int(record.get("replacement_points", 0)) == 15 and int(record.get("campaign_days", 0)) == 1, "generic growth application should deduct declared currencies and refit time", failures)

	var modified_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, record)
	var falcon := modified_world.unit_cards[&"falcon_recon_group"] as UnitCardState
	var member := modified_world.units[falcon.member_entity_ids[0]] as UnitState
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(member.definition_id)
	_expect(is_equal_approx(member.sight_range, definition.sight_range * 1.2 * 1.25), "honor and equipment sight modifiers should stack from their data definitions", failures)
	_expect(is_equal_approx(member.attack_range, definition.combat.attack_range * 1.1) and is_equal_approx(member.attack_damage, definition.combat.attack_power * 0.95), "growth should apply its declared range benefit and damage tradeoff to real entities", failures)

	var black_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	var black_record := ArmyRosterStore.build_battle_record(black_world.create_snapshot(), {}, &"black_well")
	black_record["replacement_points"] = 20
	_expect(ArmyRosterStore.apply_growth(black_record, &"blackwell_guard_battalion", &"field_repair_kit"), "Black Well cards should accept organization-oriented equipment", failures)
	var recovery_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL, black_record)
	var guard := recovery_world.unit_cards[&"blackwell_guard_battalion"] as UnitCardState
	var core := recovery_world.strategic_regions[&"black_well_core"] as StrategicRegionState
	var total_health := 0.0
	for entity_id in guard.member_entity_ids:
		var guard_member := recovery_world.units[entity_id] as UnitState
		guard_member.position = core.position
		total_health += guard_member.health
	guard.organization = 50.0
	guard.last_damage_tick = recovery_world.current_tick - recovery_world.battle_definition.organization_recovery_delay_ticks
	guard.last_total_health = total_health
	guard.last_active_strength = guard.member_entity_ids.size()
	recovery_world._advance_unit_card_organization()
	var base_recovery := recovery_world.battle_definition.organization_recovery_per_tick + recovery_world.battle_definition.organization_recovery_region_bonus * 2.0
	_expect(is_equal_approx(guard.organization, 50.0 + base_recovery * 1.35), "organization equipment should multiply authoritative out-of-contact recovery", failures)


func _test_black_well_extended_support_orders(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	var faction := world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
	faction.supply = faction.supply_capacity
	var core := world.strategic_regions[&"black_well_core"] as StrategicRegionState
	var hostile: UnitState
	for unit_variant in world.units.values():
		var candidate := unit_variant as UnitState
		if candidate.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			hostile = candidate
			break
	_expect(hostile != null, "Black Well support fixture should contain hostile units", failures)
	if hostile == null:
		return
	hostile.position = core.position
	var hostile_health := hostile.health
	var fire := SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, SupportOrderCommand.SupportKind.FIRE_SUPPORT, core.region_id
	)
	_expect(world.submit_command(fire).is_accepted(), "Black Well fire support should accept a valid strategic region target", failures)
	world.advance_tick()
	_expect(hostile.health < hostile_health and int(faction.support_cooldown_until_by_kind.get(SupportOrderCommand.SupportKind.FIRE_SUPPORT, 0)) > world.current_tick, "fire support should damage hostile entities in the region and start its independent cooldown", failures)

	var guard := world.unit_cards[&"blackwell_guard_battalion"] as UnitCardState
	var mobility := SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, SupportOrderCommand.SupportKind.RAPID_MOBILITY, &"", &"", guard.definition.definition_id
	)
	_expect(world.submit_command(mobility).is_accepted(), "rapid mobility should accept a deployed unit card", failures)
	world.advance_tick()
	var guard_member := world.units[guard.member_entity_ids[0]] as UnitState
	_expect(guard.rapid_mobility_ticks_remaining > 0 and guard_member.move_speed >= guard_member.base_move_speed * 1.35, "rapid mobility should raise real member movement for its configured duration", failures)

	guard_member.health -= 30.0
	guard.organization = 40.0
	var health_before := guard_member.health
	var organization_before := guard.organization
	var logistics := SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, SupportOrderCommand.SupportKind.FRONTLINE_LOGISTICS, &"", &"", guard.definition.definition_id
	)
	_expect(world.submit_command(logistics).is_accepted(), "frontline logistics should accept a damaged or disorganized deployed card", failures)
	world.advance_tick()
	_expect(guard_member.health > health_before and guard.organization > organization_before and int(faction.support_cooldown_until_by_kind.get(SupportOrderCommand.SupportKind.FRONTLINE_LOGISTICS, 0)) > world.current_tick, "frontline logistics should restore real health and organization with an independent cooldown", failures)


func _test_black_well_doctrine_execution(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	var lin := world.commanders[&"lin_mo"] as CommanderState
	var pump := world.strategic_regions[&"pump_heights"] as StrategicRegionState
	world._assign_commander_objective(lin, pump.position, pump.region_id)
	var thunder_task := world._task_for_unit_card(&"thunder_fire_group")
	var expected_elastic_target := pump.position + (world._faction_base_position(SimulationWorld.LOCAL_PLAYER_ID) - pump.position).normalized() * 200.0
	_expect(thunder_task != null and thunder_task.target_radius == 224.0 and thunder_task.final_target_position.distance_to(expected_elastic_target) < 1.0, "elastic defense should form a broad position 200 units behind the requested objective (task=%s radius=%s final=%s expected=%s)" % [thunder_task, thunder_task.target_radius if thunder_task != null else -1.0, thunder_task.final_target_position if thunder_task != null else Vector2.ZERO, expected_elastic_target], failures)

	var bai := world.commanders[&"bai_jiuyang"] as CommanderState
	_expect(world.commander_agent_has_doctrine(bai.agent_id, &"encounter_disengagement"), "the scout commander should expose encounter-disengagement behavior to the shared task system", failures)
	var falcon := world.unit_cards[&"falcon_recon_group"] as UnitCardState
	var falcon_task := world._task_for_unit_card(falcon.definition.definition_id)
	var scout := world.units[falcon.member_entity_ids[0]] as UnitState
	var hostile: UnitState
	for unit_variant in world.units.values():
		var candidate := unit_variant as UnitState
		if candidate.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			hostile = candidate
			break
	if hostile != null and falcon_task != null:
		hostile.position = scout.position + Vector2(450.0, 0.0)
		scout.sight_range = 600.0
		world._update_faction_knowledge()
		var threat := StrategicTaskSystem.new()._nearest_visible_threat_to_scouts(falcon_task, world)
		_expect(not threat.is_empty(), "encounter disengagement should detect threats beyond the normal 384-unit scout danger radius", failures)

	var lu := world.commanders[&"lu_zheng"] as CommanderState
	lu.equip_doctrine(&"fighting_withdrawal")
	var withdrawal := world.strategic_regions[&"withdrawal_corridor"] as StrategicRegionState
	world._assign_commander_objective(lu, withdrawal.position, withdrawal.region_id)
	var guard_task := world._task_for_unit_card(&"blackwell_guard_battalion")
	world._update_commander_behavior_feedback()
	_expect(guard_task != null and guard_task.target_radius == 80.0 and lu.behavior_reason_key == &"COMMANDER_REASON_FIGHTING_WITHDRAWAL", "fighting withdrawal should tighten execution only after the player explicitly assigns the withdrawal corridor (task=%s radius=%s reason=%s phase=%s)" % [guard_task, guard_task.target_radius if guard_task != null else -1.0, lu.behavior_reason_key, guard_task.phase if guard_task != null else -1], failures)

	var gu := world.commanders[&"gu_hanxing"] as CommanderState
	var mobile := world.unit_cards[&"mobile_counterattack_group"] as UnitCardState
	for entity_id in mobile.member_entity_ids:
		(world.units[entity_id] as UnitState).enabled = false
	mobile.deployment_state = UnitCardState.DeploymentState.RESERVE
	gu.target_position = (world.strategic_regions[&"black_well_core"] as StrategicRegionState).position
	gu.target_region_id = &"black_well_core"
	(world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).supply = (world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).supply_capacity
	var reserve_estimate := world._commander_hostile_estimate(gu)
	world._advance_reserve_commitment_doctrine()
	var reserve_queued := false
	for command in world.command_queue.snapshot():
		reserve_queued = reserve_queued or command is DeployUnitCardCommand and (command as DeployUnitCardCommand).unit_card_id == mobile.definition.definition_id
	_expect(reserve_queued and gu.behavior_reason_key == &"COMMANDER_REASON_RESERVE_COMMITMENT", "reserve commitment should deploy an affordable reserve only when legal target intelligence outnumbers active strength (estimate=%s queue=%s reason=%s state=%s)" % [reserve_estimate, world.command_queue.snapshot(), gu.behavior_reason_key, mobile.deployment_state], failures)
	var disengage := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		gu.definition.definition_id, CommanderOrderCommand.OrderKind.SET_POSTURE,
		Vector2.ZERO, &"", CommanderState.Posture.DISENGAGE
	)
	_expect(world.submit_command(disengage).is_accepted(), "a player disengage order should supersede pending doctrine automation", failures)
	var queued_after_disengage := world.command_queue.snapshot()
	var pending_reserve_after_disengage := queued_after_disengage.any(func(command: GameCommand) -> bool:
		return command is DeployUnitCardCommand and (command as DeployUnitCardCommand).unit_card_id == mobile.definition.definition_id
	)
	_expect(not pending_reserve_after_disengage, "disengage should remove a reserve deployment already queued by that commander's doctrine", failures)
	world.advance_tick()
	_expect(mobile.deployment_state == UnitCardState.DeploymentState.RESERVE, "a superseded automatic reserve must remain at headquarters after disengage applies", failures)
	world._advance_reserve_commitment_doctrine()
	var reserve_requeued := world.command_queue.snapshot().any(func(command: GameCommand) -> bool:
		return command is DeployUnitCardCommand and (command as DeployUnitCardCommand).unit_card_id == mobile.definition.definition_id
	)
	_expect(not reserve_requeued, "a disengaging commander must not automatically commit a headquarters reserve", failures)


func _test_army_roster_v1_migration(failures: Array[String]) -> void:
	var path := "user://warseed_test_roster_v1.json"
	var v1_record := {
		"format_version": 1,
		"scenario_id": "grey_ridge",
		"battle_count": 1,
		"last_result": "defeat",
		"cards": {
			"ironwall_assault_group": {
				"authorized_strength": 12,
				"available_strength": 9,
				"last_battle_losses": 3,
				"cumulative_losses": 3,
				"battles_survived": 1,
			}
		}
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_expect(false, "v1 migration test could not create an isolated user record", failures)
		return
	file.store_string(JSON.stringify(v1_record))
	file = null
	var migrated := ArmyRosterStore.load_record(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var migrated_card := (migrated.get("cards", {}) as Dictionary).get("ironwall_assault_group", {}) as Dictionary
	_expect(int(migrated.get("format_version", 0)) == ArmyRosterStore.FORMAT_VERSION, "v1 records should migrate to the current format", failures)
	_expect(int(migrated.get("replacement_points", -1)) == 0 and int(migrated.get("merit", -1)) == 0 and int(migrated.get("campaign_days", -1)) == 0, "v1 migration should initialize campaign currencies and time safely", failures)
	_expect(String(migrated_card.get("honor_id", "")).is_empty() and String(migrated_card.get("equipment_id", "")).is_empty(), "v1 migration should initialize persistent card attachments without changing strength", failures)


func _test_grey_ridge_unit_card_takeover_and_return(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var ironwall := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var formation := world.formations[ironwall.formation_id] as FormationState
	var original_task_id := ironwall.assigned_task_id
	var task := world.tasks[original_task_id] as TaskState
	_expect(ironwall.control_state == UnitCardState.ControlState.AGENT_ASSIGNED and original_task_id != 0, "deployed Grey Ridge cards should begin under their named commander task", failures)
	var move := FormationMoveCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, formation.leader_entity_id, formation.formation_id,
		formation.anchor_position + Vector2(-256.0, -192.0)
	)
	_expect(world.submit_command(move).is_accepted(), "a direct formation order should atomically take over its unit card", failures)
	_expect(ironwall.control_state == UnitCardState.ControlState.PLAYER_OVERRIDDEN and task.lifecycle == TaskState.Lifecycle.BLOCKED, "whole-card takeover should block the owning commander task", failures)
	for entity_id in ironwall.member_entity_ids:
		var member := world.units[entity_id] as UnitState
		_expect(member.control_state == UnitState.ControlState.TEMPORARILY_OVERRIDDEN and member.return_task_id == original_task_id, "whole-card takeover should reserve every living member for the player", failures)
	world.advance_tick()
	var di := world.commanders[&"di_tian"] as CommanderState
	_expect(di.behavior_state_key == &"COMMANDER_BEHAVIOR_COORDINATING" and di.behavior_reason_key == &"COMMANDER_REASON_CARD_PLAYER_CONTROLLED", "commander feedback should explain that a subordinate card is under direct player control", failures)
	var return_command := UnitCardControlCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		ironwall.definition.definition_id, UnitCardControlCommand.Action.RETURN_TO_COMMANDER
	)
	_expect(world.submit_command(return_command).is_accepted(), "an overridden unit card should accept explicit return to commander", failures)
	world.advance_tick()
	_expect(ironwall.control_state in [UnitCardState.ControlState.RETURNING, UnitCardState.ControlState.AGENT_ASSIGNED], "return should enter an authoritative whole-card transition", failures)
	if ironwall.control_state == UnitCardState.ControlState.RETURNING:
		_expect(di.behavior_state_key == &"COMMANDER_BEHAVIOR_RETURNING" and di.behavior_reason_key == &"COMMANDER_REASON_CARD_RETURNING", "commander feedback should explain an in-progress whole-card return", failures)
	for _tick in range(120):
		if ironwall.control_state == UnitCardState.ControlState.AGENT_ASSIGNED:
			break
		world.advance_tick()
	_expect(ironwall.control_state == UnitCardState.ControlState.AGENT_ASSIGNED, "all card members should rejoin without hanging", failures)
	_expect(task.lifecycle == TaskState.Lifecycle.EXECUTING and task.participant_entity_ids.size() == ironwall.member_entity_ids.size(), "commander task should resume only after the full card returns", failures)
	_expect(di.behavior_reason_key not in [&"COMMANDER_REASON_CARD_PLAYER_CONTROLLED", &"COMMANDER_REASON_CARD_RETURNING"], "commander feedback should resume the authoritative task reason after the card returns", failures)
	for entity_id in ironwall.member_entity_ids:
		_expect((world.units[entity_id] as UnitState).control_state == UnitState.ControlState.AGENT_ASSIGNED, "returned card members should all restore named-Agent control", failures)


func _test_grey_ridge_independent_commander_orders(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var bai_target := SimulationWorld.GREY_RIDGE_WEST_POSITION
	var di_target := SimulationWorld.GREY_RIDGE_CENTRAL_POSITION
	var bai_order := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"bai_jiuyang", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, bai_target, &"west_mine"
	)
	var di_order := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, di_target, &"central_relay"
	)
	_expect(world.submit_command(bai_order).is_accepted() and world.submit_command(di_order).is_accepted(), "two named commanders should accept independent objectives in the same tick", failures)
	world.advance_tick()
	var bai := world.commanders[&"bai_jiuyang"] as CommanderState
	var di := world.commanders[&"di_tian"] as CommanderState
	_expect(bai.target_position == bai_target and di.target_position == di_target, "named commanders should retain separate objective state", failures)
	_expect(bai.current_task_ids.size() == 1 and di.current_task_ids.size() == 1 and bai.current_task_ids[0] != di.current_task_ids[0], "each commander should own an independent persistent task", failures)
	var falcon := world.unit_cards[&"falcon_recon_group"] as UnitCardState
	var ironwall := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	_expect(falcon.assigned_agent_id == SimulationWorld.COMMANDER_AGENT_BAI_JIUYANG and ironwall.assigned_agent_id == SimulationWorld.COMMANDER_AGENT_DI_TIAN, "unit cards should remain bound to their named Agent rather than a generic supervisor", failures)
	var posture := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.SET_POSTURE, Vector2.ZERO, &"", CommanderState.Posture.DISENGAGE
	)
	var expected_disengage_position := world._commander_disengage_position(di)
	_expect(world.submit_command(posture).is_accepted(), "commander posture should pass through the command validator", failures)
	world.advance_tick()
	_expect(di.posture == CommanderState.Posture.DISENGAGE and di.target_position == expected_disengage_position, "disengage posture should re-task the commander toward a formation-safe headquarters staging area", failures)
	var disengage_task := world.tasks[di.current_task_ids[0]] as TaskState
	_expect(di.behavior_reason_key == &"COMMANDER_REASON_POSTURE_DISENGAGE", "disengage posture should expose its execution reason (actual=%s/%s task=%s/%s detail=%s target=%s deployable=%s)" % [di.behavior_state_key, di.behavior_reason_key, TaskState.Lifecycle.keys()[disengage_task.lifecycle], TaskState.BlockedReason.keys()[disengage_task.blocked_reason], disengage_task.blocked_detail, di.target_position, world._formation_can_deploy_at(world.formations[disengage_task.formation_id] as FormationState, di.target_position)], failures)


func _test_commander_disengage_ends_reconnaissance(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var commander := world.commanders[&"bai_jiuyang"] as CommanderState
	var card := world.unit_cards[&"falcon_recon_group"] as UnitCardState
	var intent := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander.definition.definition_id, CommanderOrderCommand.OrderKind.ASSIGN_INTENT,
		SimulationWorld.GREY_RIDGE_WEST_POSITION, &"west_mine", CommanderState.Posture.CAUTIOUS,
		PackedVector2Array(), &"intent:disengage_regression", &"west_mine", CommanderState.ReservePolicy.HOLD
	)
	_expect(world.submit_command(intent).is_accepted(), "disengage regression fixture should accept a high-level reconnaissance intent", failures)
	world.advance_tick()
	var old_task := world.tasks[card.assigned_task_id] as TaskState
	_expect(old_task != null and old_task.kind == TaskState.Kind.SCOUT_AREA and commander.active_intent_id == &"intent:disengage_regression", "fixture should begin with a traceable persistent reconnaissance intent", failures)
	var safe_rally := world._commander_disengage_position(commander)
	var disengage := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		commander.definition.definition_id, CommanderOrderCommand.OrderKind.SET_POSTURE,
		Vector2.ZERO, &"", CommanderState.Posture.DISENGAGE
	)
	_expect(world.submit_command(disengage).is_accepted(), "the reconnaissance commander should accept a disengage order", failures)
	world.advance_tick()
	var rally_task := world.tasks[card.assigned_task_id] as TaskState
	_expect(old_task.lifecycle == TaskState.Lifecycle.CANCELLED, "disengage should preserve the replaced reconnaissance task as CANCELLED", failures)
	_expect(commander.active_intent_id.is_empty(), "disengage should clear the previous high-level intent instead of continuing to advertise its objective", failures)
	_expect(rally_task != null and rally_task.kind == TaskState.Kind.DEFEND_AREA, "a reconnaissance card under disengage should receive a holding rally task instead of SCOUT_AREA", failures)
	_expect(rally_task.target_position.distance_to(safe_rally) <= rally_task.target_radius, "the disengage task should resolve within its formation-safe headquarters rally area", failures)
	var rally_task_id := rally_task.task_id
	var rally_target := rally_task.target_position
	for _tick in range(StrategicTaskSystem.SCOUT_OBSERVE_TICKS + 5):
		world.advance_tick()
	var sustained_task := world.tasks.get(rally_task_id) as TaskState
	_expect(card.assigned_task_id == rally_task_id and sustained_task != null and sustained_task.kind == TaskState.Kind.DEFEND_AREA and sustained_task.target_position.is_equal_approx(rally_target), "disengage should remain at the safe rally beyond a complete reconnaissance observation cycle", failures)
	_expect(commander.posture == CommanderState.Posture.DISENGAGE and commander.behavior_reason_key == &"COMMANDER_REASON_POSTURE_DISENGAGE", "commander feedback should keep the disengage posture and reason while rallying", failures)


func _test_grey_ridge_commander_objective_moves_unit_card(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var ironwall := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var formation := world.formations[ironwall.formation_id] as FormationState
	var starting_anchor := formation.anchor_position
	var order := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"
	)
	_expect(world.submit_command(order).is_accepted(), "a commander objective should enter the shared command queue", failures)
	world.advance_tick()
	var task := world.tasks[ironwall.assigned_task_id] as TaskState
	var queued_move: FormationMoveCommand
	for queued_command in world.command_queue.snapshot():
		if queued_command is FormationMoveCommand and (queued_command as FormationMoveCommand).formation_id == formation.formation_id:
			queued_move = queued_command as FormationMoveCommand
			break
	_expect(queued_move != null and queued_move.issuer_kind == GameCommand.IssuerKind.AGENT and queued_move.agent_id == task.agent_id and queued_move.task_id == task.task_id, "the named Agent should translate its task into a formation command through the shared queue", failures)
	for _tick in range(12):
		world.advance_tick()
	_expect(formation.anchor_position.distance_to(starting_anchor) > 1.0 and formation.anchor_position.distance_to(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION) < starting_anchor.distance_to(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION), "the commander-owned unit card should physically advance toward its objective (start=%s current=%s task=%s/%s detail=%s queue=%d path=%d)" % [starting_anchor, formation.anchor_position, TaskState.Lifecycle.keys()[task.lifecycle], TaskState.BlockedReason.keys()[task.blocked_reason], task.blocked_detail, world.command_queue.size(), formation.path.size()], failures)


func _test_grey_ridge_commander_behavior_feedback(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var bai := world.commanders[&"bai_jiuyang"] as CommanderState
	var di := world.commanders[&"di_tian"] as CommanderState
	var cautious_order := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"bai_jiuyang", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		SimulationWorld.GREY_RIDGE_WEST_POSITION, &"west_mine"
	)
	_expect(world.submit_command(cautious_order).is_accepted(), "cautious commander feedback fixture should accept a distant objective", failures)
	world.advance_tick()
	_expect(bai.behavior_state_key == &"COMMANDER_BEHAVIOR_ADVANCING" and bai.behavior_reason_key == &"COMMANDER_REASON_POSTURE_CAUTIOUS", "cautious posture should explain why the commander preserves a favorable engagement", failures)

	var aggressive_order := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.SET_POSTURE,
		Vector2.ZERO, &"", CommanderState.Posture.AGGRESSIVE
	)
	_expect(world.submit_command(aggressive_order).is_accepted(), "aggressive commander feedback fixture should accept a posture change", failures)
	world.advance_tick()
	_expect(di.behavior_reason_key == &"COMMANDER_REASON_POSTURE_AGGRESSIVE", "aggressive posture should produce a distinct authoritative execution reason (actual=%s/%s)" % [di.behavior_state_key, di.behavior_reason_key], failures)

	var ironwall := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var doctrine_task := world.tasks[ironwall.assigned_task_id] as TaskState
	doctrine_task.activation_tick = world.current_tick + 10
	doctrine_task.set_phase(TaskState.Phase.PREPARING, world.current_tick)
	world._update_commander_behavior_feedback()
	_expect(di.behavior_state_key == &"COMMANDER_BEHAVIOR_PREPARING" and di.behavior_reason_key == &"COMMANDER_REASON_ALTERNATING_COVER_TIMING", "doctrine timing should be visible without parsing task detail text", failures)

	doctrine_task.set_lifecycle(TaskState.Lifecycle.BLOCKED, world.current_tick, TaskState.BlockedReason.PATH_UNAVAILABLE)
	world._update_commander_behavior_feedback()
	_expect(di.behavior_state_key == &"COMMANDER_BEHAVIOR_BLOCKED" and di.behavior_reason_key == &"COMMANDER_REASON_BLOCKED_PATH_UNAVAILABLE", "blocked commander feedback should expose a localized structured cause", failures)

	var snapshot := world.create_snapshot()
	var copied_commander := snapshot.get_commander(&"di_tian")
	var copied_reason := copied_commander.behavior_reason_key
	var copied_eta := copied_commander.estimated_arrival_min_ticks
	var copied_risk := copied_commander.risk_key
	var copied_exit := copied_commander.exit_condition_key
	di.set_behavior(&"COMMANDER_BEHAVIOR_STANDING_BY", &"COMMANDER_REASON_NO_ACTIVE_TASK", world.current_tick + 1)
	di.estimated_arrival_min_ticks = copied_eta + 99
	di.risk_key = &"COMMANDER_RISK_LOW"
	di.exit_condition_key = &"COMMANDER_EXIT_AWAIT_ORDER"
	_expect(copied_commander.behavior_reason_key == copied_reason and copied_commander.behavior_changed_tick != di.behavior_changed_tick, "commander behavior snapshots should remain immutable value copies", failures)
	_expect(copied_commander.estimated_arrival_min_ticks == copied_eta and copied_commander.risk_key == copied_risk and copied_commander.exit_condition_key == copied_exit, "commander outlook snapshots should remain immutable value copies", failures)


func _test_grey_ridge_commander_outlook_uses_legal_intelligence(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var bai := world.commanders[&"bai_jiuyang"] as CommanderState
	var di := world.commanders[&"di_tian"] as CommanderState
	var west_order := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"bai_jiuyang", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		SimulationWorld.GREY_RIDGE_WEST_POSITION, &"west_mine"
	)
	var central_order := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay"
	)
	_expect(world.submit_command(west_order).is_accepted() and world.submit_command(central_order).is_accepted(), "commander outlook fixture should accept independent west and central objectives", failures)
	world.advance_tick()
	_expect(bai.estimated_arrival_min_ticks > 0 and bai.estimated_arrival_max_ticks >= bai.estimated_arrival_min_ticks, "commander outlook should derive an arrival interval from authoritative formation routes", failures)
	_expect(bai.risk_key == &"COMMANDER_RISK_LOW" and bai.risk_reason_key == &"COMMANDER_RISK_REASON_CONTACT_ADVANTAGE", "the west medium-confidence 1-3 vehicle report should produce a low but explained risk for eight scouts", failures)
	_expect(bai.exit_condition_key == &"COMMANDER_EXIT_CONTACT_OR_REORDER", "a cautious commander should publish contact or re-order as the execution boundary", failures)
	_expect(di.risk_key == &"COMMANDER_RISK_HIGH" and di.risk_reason_key == &"COMMANDER_RISK_REASON_CONTACT_OUTNUMBERED", "the central high-confidence twelve-unit report should expose high risk against twelve assault members", failures)
	_expect(di.exit_condition_key == &"COMMANDER_EXIT_OBJECTIVE_OR_REORDER", "a balanced commander should publish objective or re-order as the execution boundary", failures)

	var hidden_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var hidden_di := hidden_world.commanders[&"di_tian"] as CommanderState
	var east_order := CommanderOrderCommand.new(
		hidden_world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, hidden_world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		SimulationWorld.GREY_RIDGE_EAST_POSITION, &"east_supply"
	)
	_expect(hidden_world.submit_command(east_order).is_accepted(), "hidden-intelligence outlook fixture should accept an eastern objective", failures)
	hidden_world.advance_tick()
	for enemy_variant in hidden_world.units.values():
		var enemy := enemy_variant as UnitState
		if enemy.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			enemy.position = SimulationWorld.GREY_RIDGE_EAST_POSITION + Vector2(float(enemy.entity_id % 4) * 12.0, float(enemy.entity_id % 3) * 12.0)
	hidden_world._update_commander_behavior_feedback()
	_expect(hidden_di.risk_key == &"COMMANDER_RISK_UNKNOWN" and hidden_di.risk_reason_key == &"COMMANDER_RISK_REASON_NO_RELIABLE_INTEL", "commander risk must not change from hostile true-state positions hidden outside faction knowledge", failures)
	var hidden_ironwall := hidden_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var observer := hidden_world.units[hidden_ironwall.member_entity_ids[0]] as UnitState
	observer.position = SimulationWorld.GREY_RIDGE_EAST_POSITION
	hidden_world._update_faction_knowledge()
	hidden_world._update_commander_behavior_feedback()
	_expect(hidden_di.risk_key == &"COMMANDER_RISK_HIGH" and hidden_di.risk_reason_key == &"COMMANDER_RISK_REASON_CONTACT_OUTNUMBERED", "commander risk should update after the same hostile force enters legal faction observation", failures)


func _test_grey_ridge_doctrine_constraints(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var bai := world.commanders[&"bai_jiuyang"] as CommanderState
	var di := world.commanders[&"di_tian"] as CommanderState
	var lin := world.commanders[&"lin_mo"] as CommanderState
	_expect(world.doctrine_definitions.size() >= 4, "the first slice should expose persistent doctrine definitions", failures)
	_expect(bai.has_doctrine(&"covert_search") and di.has_doctrine(&"alternating_cover") and lin.has_doctrine(&"fire_preparation"), "named commanders should start with authoritative equipped doctrine slots", failures)
	var distant_recon := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"bai_jiuyang", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, SimulationWorld.GREY_RIDGE_EAST_POSITION
	)
	_expect(world.submit_command(distant_recon).is_accepted(), "covert-search commander should accept a distant reconnaissance objective", failures)
	world.advance_tick()
	var falcon_task := world.tasks[(world.unit_cards[&"falcon_recon_group"] as UnitCardState).assigned_task_id] as TaskState
	_expect(falcon_task.has_staged_target and falcon_task.target_position != falcon_task.final_target_position and is_equal_approx(falcon_task.target_radius, 96.0), "covert search should create a narrower staged observation route", failures)
	var equip := EquipDoctrineCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", &"concentrated_breakthrough"
	)
	_expect(world.submit_command(equip).is_accepted(), "available doctrine should equip through the shared command pipeline", failures)
	world.advance_tick()
	var ironwall_task := world.tasks[(world.unit_cards[&"ironwall_assault_group"] as UnitCardState).assigned_task_id] as TaskState
	_expect(di.has_doctrine(&"concentrated_breakthrough") and is_equal_approx(ironwall_task.target_radius, 64.0), "concentrated breakthrough should narrow the commander's active frontage", failures)
	var illegal := EquipDoctrineCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"bai_jiuyang", &"fire_preparation"
	)
	_expect(world.submit_command(illegal).reason == CommandValidationResult.Reason.INVALID_DISPOSITION, "a commander should reject doctrines outside the visible available set", failures)


func _test_grey_ridge_locked_enemy_reactions_use_faction_knowledge(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	_expect(world.enemy_opening_plan_id == SimulationWorld.ENEMY_PLAN_CENTRAL_ASSAULT and world.enemy_reaction_log[0].contains("plan=central_assault"), "the first Grey Ridge battle should lock and log its central opening before player input", failures)
	var second_battle_record := {"format_version": ArmyRosterStore.FORMAT_VERSION, "content_version": ArmyRosterMigration.CONTENT_VERSION, "scenario_id": "grey_ridge", "battle_count": 1, "cards": {}}
	var western_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, second_battle_record)
	var repeated_western_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, second_battle_record)
	var western_formation := western_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	_expect(western_world.enemy_opening_plan_id == SimulationWorld.ENEMY_PLAN_WESTERN_HOOK and western_formation.target_position == SimulationWorld.GREY_RIDGE_WEST_POSITION, "the second battle should lock a distinct western-hook opening without reading player behavior", failures)
	var western_probe := western_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID] as FormationState
	_expect(western_probe.target_position == SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, "the western hook should assign the independent probe formation as a central screen", failures)
	_expect(repeated_western_world.enemy_opening_plan_id == western_world.enemy_opening_plan_id and repeated_western_world.enemy_reaction_log[0] == western_world.enemy_reaction_log[0], "identical pre-battle records should deterministically select and log the same hostile opening", failures)
	var third_battle_record := {"format_version": ArmyRosterStore.FORMAT_VERSION, "content_version": ArmyRosterMigration.CONTENT_VERSION, "scenario_id": "grey_ridge", "battle_count": 2, "cards": {}}
	var feint_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, third_battle_record)
	var feint_probe := feint_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID] as FormationState
	_expect(feint_world.enemy_opening_plan_id == SimulationWorld.ENEMY_PLAN_WESTERN_FEINT and feint_probe.target_position == SimulationWorld.GREY_RIDGE_WEST_POSITION, "the third battle should lock the western feint before any player command", failures)
	for _tick in range(SimulationWorld.GREY_RIDGE_FEINT_REDIRECT_TICK + 2):
		feint_world.advance_tick()
	_expect(feint_world.enemy_opening_followup_executed and feint_probe.target_position == SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, "the feint probe should redirect on its locked timeline without inspecting player behavior (executed=%s target=%s path=%d queue=%d)" % [feint_world.enemy_opening_followup_executed, feint_probe.target_position, feint_probe.path.size(), feint_world.command_queue.size()], failures)
	_expect(feint_world.enemy_reaction_log.size() == 2 and feint_world.enemy_reaction_log[-1].contains("source=LOCKED_PLAN_TIMELINE") and feint_world.enemy_reaction_log[-1].contains("action=FEINT_REDIRECT_CENTRAL"), "the scheduled feint redirect should have an auditable non-observation source (log=%s)" % [feint_world.enemy_reaction_log], failures)
	_expect(world.enemy_reaction_rules.size() == 4 and world.create_true_state_snapshot().enemy_reactions.size() == 4, "Grey Ridge should lock four typed reaction rules at scenario creation", failures)
	_expect(world.create_snapshot().enemy_reactions.is_empty(), "normal player snapshots must not leak the hostile reaction table", failures)
	var falcon := world.unit_cards[&"falcon_recon_group"] as UnitCardState
	var hidden_member := world.units[falcon.member_entity_ids[0]] as UnitState
	hidden_member.position = SimulationWorld.GREY_RIDGE_WEST_POSITION
	world.current_tick = SimulationWorld.GREY_RIDGE_OPENING_COMMITMENT_TICKS
	for _tick in range(50):
		world._update_faction_knowledge()
		world._advance_grey_ridge_enemy_reactions()
		world.current_tick += 1
	var central_rule := world.enemy_reaction_rules[3] as EnemyReactionRuleState
	_expect(central_rule.observed_tick == -1 and central_rule.fired_count == 0, "reaction rules must not arm from hidden true-state positions", failures)
	var enemy_formation := world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	enemy_formation.anchor_position = SimulationWorld.GREY_RIDGE_CENTRAL_POSITION
	for entity_id in enemy_formation.member_entity_ids:
		(world.units[entity_id] as UnitState).position = SimulationWorld.GREY_RIDGE_CENTRAL_POSITION
	hidden_member.position = SimulationWorld.GREY_RIDGE_CENTRAL_POSITION
	var observation_start := world.current_tick
	for _tick in range(central_rule.delay_ticks + 1):
		world._update_faction_knowledge()
		world._advance_grey_ridge_enemy_reactions()
		world.current_tick += 1
	_expect(central_rule.fired_count == 1 and central_rule.last_fired_tick == observation_start + central_rule.delay_ticks, "visible central contact should fire only after the rule's locked delay", failures)
	_expect(world.enemy_reaction_log.size() == 2 and world.enemy_reaction_log[-1].contains("source=LEGAL_FACTION_OBSERVATION"), "every hostile replan should trace to the opening plan or a legal observation", failures)
	_expect(world.command_queue.size() == 1, "a fired reaction should still wait in the shared authoritative command queue", failures)

	var flank_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var flank_probe := flank_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID] as FormationState
	flank_probe.anchor_position = SimulationWorld.GREY_RIDGE_WEST_POSITION
	for entity_id in flank_probe.member_entity_ids:
		(flank_world.units[entity_id] as UnitState).position = SimulationWorld.GREY_RIDGE_WEST_POSITION
	var flank_falcon := flank_world.unit_cards[&"falcon_recon_group"] as UnitCardState
	(flank_world.units[flank_falcon.member_entity_ids[0]] as UnitState).position = SimulationWorld.GREY_RIDGE_WEST_POSITION
	flank_world.current_tick = SimulationWorld.GREY_RIDGE_OPENING_COMMITMENT_TICKS
	var flank_rule := flank_world.enemy_reaction_rules[2] as EnemyReactionRuleState
	for _tick in range(flank_rule.delay_ticks + 1):
		flank_world._update_faction_knowledge()
		flank_world._advance_grey_ridge_enemy_reactions()
		flank_world.current_tick += 1
	var flank_command := flank_world.command_queue.snapshot()[-1] as GameCommand
	_expect(flank_rule.fired_count == 1 and flank_command is AttackCommand and (flank_command as AttackCommand).formation_id == SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID, "a legal flank observation should assign the independent probe rather than teleporting the central assault formation", failures)


func _test_grey_ridge_terrain_role_behaviors(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var falcon := world.unit_cards[&"falcon_recon_group"] as UnitCardState
	var ironwall := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var scout := world.units[falcon.member_entity_ids[0]] as UnitState
	var assault := world.units[ironwall.member_entity_ids[0]] as UnitState
	_expect(scout.tactical_role == UnitState.TacticalRole.SCOUT and assault.tactical_role == UnitState.TacticalRole.ASSAULT, "unit-card role should write through to every bound battlefield entity", failures)
	scout.position = SimulationWorld.GREY_RIDGE_EAST_POSITION
	assault.position = SimulationWorld.GREY_RIDGE_CENTRAL_POSITION
	world._update_grey_ridge_terrain_effects()
	_expect(scout.terrain_kind == UnitState.TerrainKind.FOREST and scout.sight_range > scout.base_sight_range and scout.move_speed > scout.base_move_speed, "scouts should visibly search faster and farther in forest", failures)
	_expect(assault.terrain_kind == UnitState.TerrainKind.RUINS and assault.armor == assault.base_armor + 2.0 and assault.attack_damage > assault.base_attack_damage, "assault formations should gain close-combat protection in ruins", failures)
	assault.tactical_role = UnitState.TacticalRole.ARMOR
	assault.position = SimulationWorld.GREY_RIDGE_WEST_POSITION
	world._update_grey_ridge_terrain_effects()
	_expect(assault.terrain_effect_key == &"TERRAIN_EFFECT_OPEN_ARMOR" and assault.move_speed > assault.base_move_speed and assault.attack_damage > assault.base_attack_damage, "armor should gain an observable open-ground breakthrough profile", failures)
	assault.position = SimulationWorld.GREY_RIDGE_CENTRAL_POSITION
	world._update_grey_ridge_terrain_effects()
	_expect(assault.terrain_effect_key == &"TERRAIN_EFFECT_RUINS_ARMOR" and assault.move_speed < assault.base_move_speed and assault.attack_range < assault.base_attack_range, "the same armor entity should become constrained in ruins", failures)
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			unit.enabled = false
	for entity_id in falcon.member_entity_ids:
		(world.units[entity_id] as UnitState).position = SimulationWorld.GREY_RIDGE_WEST_POSITION
	world._advance_strategic_regions()
	_expect((world.strategic_regions[&"west_mine"] as StrategicRegionState).controller_faction_id == 0, "scout-only presence should report a region but cannot hold it as organized combat power", failures)
	for entity_id in ironwall.member_entity_ids:
		var member := world.units[entity_id] as UnitState
		member.tactical_role = UnitState.TacticalRole.ASSAULT
		member.position = SimulationWorld.GREY_RIDGE_WEST_POSITION
	var west := world.strategic_regions[&"west_mine"] as StrategicRegionState
	for _tick in range(west.capture_required_ticks):
		world._advance_strategic_regions()
	_expect(west.controller_faction_id == SimulationWorld.LOCAL_PLAYER_ID, "a combat unit card should convert presence into region control after completing the capture bar", failures)


func _test_grey_ridge_initial_state(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var snapshot := world.create_snapshot()
	var true_state := world.create_true_state_snapshot()
	var faction := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	_expect(world.scenario_kind == SimulationWorld.ScenarioKind.GREY_RIDGE, "Grey Ridge should be an explicit simulation scenario", failures)
	_expect(true_state.units.size() == 34 and snapshot.units.size() == 20, "Grey Ridge should start with 20 friendly, 12 hostile assault units, and a hidden two-vehicle probe", failures)
	_expect(snapshot.commanders.size() == 4 and snapshot.unit_cards.size() == 6, "Grey Ridge should expose four commanders and six tactical cards", failures)
	_expect(faction.supply == 5 and faction.supply_capacity == 10, "Grey Ridge should start at 5/10 supply", failures)
	_expect(faction.population == 20 and faction.population_capacity == 40, "Grey Ridge should start at 20/40 population", failures)
	_expect(snapshot.ore_fields.is_empty() and snapshot.buildings.size() == 1, "local Grey Ridge snapshot should contain no ore economy and only the friendly headquarters", failures)
	var falcon := snapshot.get_unit_card(&"falcon_recon_group")
	var ironwall := snapshot.get_unit_card(&"ironwall_assault_group")
	var armor := snapshot.get_unit_card(&"armored_spearhead")
	var firepower := snapshot.get_unit_card(&"thunder_fire_group")
	_expect(falcon.current_strength == 8 and falcon.formation_id == SimulationWorld.GREY_RIDGE_FALCON_FORMATION_ID, "Falcon should unfold into its own stable eight-entity formation", failures)
	_expect(ironwall.current_strength == 12 and ironwall.formation_id == SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID, "Ironwall should unfold into its own stable twelve-entity formation", failures)
	_expect(armor.deployment_state == UnitCardState.DeploymentState.RESERVE and firepower.deployment_state == UnitCardState.DeploymentState.RESERVE, "armor and firepower cards should begin in headquarters reserve", failures)
	var enemy_formation := true_state.get_formation(SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID)
	_expect(enemy_formation != null and enemy_formation.is_moving, "the locked hostile opening plan should already be advancing toward the central relay", failures)
	var enemy_probe := true_state.get_formation(SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID)
	_expect(enemy_probe != null and enemy_probe.member_entity_ids.size() == 2 and enemy_probe.is_moving and enemy_probe.target_position == SimulationWorld.GREY_RIDGE_WEST_POSITION, "the acoustic west report should correspond to a real independent two-vehicle probe (members=%d moving=%s target=%s path=%d)" % [enemy_probe.member_entity_ids.size() if enemy_probe != null else -1, enemy_probe.is_moving if enemy_probe != null else false, enemy_probe.target_position if enemy_probe != null else Vector2.ZERO, enemy_probe.path.size() if enemy_probe != null else -1], failures)
	for entity_id in enemy_probe.member_entity_ids:
		_expect((world.units[entity_id] as UnitState).tactical_role == UnitState.TacticalRole.SCOUT, "the tracked probe should be an actual reconnaissance formation that can execute the shared scout cycle", failures)
	_expect(snapshot.strategic_regions.size() == 3, "Grey Ridge should expose all three authoritative strategic regions", failures)
	for region in snapshot.strategic_regions:
		_expect(region.controller_faction_id == 0 and not region.contested, "strategic regions should begin neutral and uncontested", failures)
	_expect(snapshot.intel_reports.size() == 3, "Cardinal should expose the three locked opening intelligence reports", failures)
	_expect(snapshot.intel_reports[0].source_key == &"INTEL_SOURCE_OPTICAL" and snapshot.intel_reports[0].estimated_max == 12, "central opening report should retain source, estimate, direction, and confidence data", failures)
	_expect(snapshot.intel_reports[0].eta_min_ticks == 230 and snapshot.intel_reports[0].eta_max_ticks == 270 and snapshot.intel_reports[0].freshness_key == &"INTEL_FRESH_CURRENT", "opening intelligence should expose a live ETA and freshness state", failures)
	_expect(snapshot.intel_reports[1].estimated_min == 1 and snapshot.intel_reports[1].estimated_max == 3 and enemy_probe.member_entity_ids.size() in range(snapshot.intel_reports[1].estimated_min, snapshot.intel_reports[1].estimated_max + 1), "the medium-confidence acoustic estimate should bracket the real probe without exposing its exact count", failures)
	_expect(not snapshot.intel_reports[2].has_estimate and snapshot.intel_reports[2].eta_max_ticks == -1, "unscouted east should remain explicitly unknown rather than being encoded as a confirmed zero", failures)


func _test_grey_ridge_region_control_and_settlement(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	# Isolate income from the observer's separately tested automatic Supply commitment.
	var takeover := UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick, &"falcon_recon_group", UnitCardControlCommand.Action.TAKEOVER)
	_expect(world.submit_command(takeover).is_accepted(), "income fixture should take control of its observer", failures)
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			unit.enabled = false
	var friendly_formation := world.formations[SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID] as FormationState
	_set_test_formation_position(world, friendly_formation, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	world.advance_tick()
	var capturing := world.create_snapshot().get_strategic_region(&"central_relay")
	_expect(capturing.controller_faction_id == 0 and capturing.capture_faction_id == SimulationWorld.LOCAL_PLAYER_ID and capturing.capture_progress > 0.0, "a sole friendly presence should begin a visible capture without granting ownership immediately", failures)
	for _tick in range(capturing.capture_required_ticks - 1):
		world.advance_tick()
	var controlled := world.create_snapshot().get_strategic_region(&"central_relay")
	_expect(controlled.controller_faction_id == SimulationWorld.LOCAL_PLAYER_ID and controlled.capture_progress == 1.0 and not controlled.contested, "ownership should turn friendly only when the authoritative capture bar reaches 100 percent", failures)
	for _tick in range(300 - world.current_tick):
		world.advance_tick()
	var faction := world.create_snapshot().get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var settled := world.create_snapshot().get_strategic_region(&"central_relay")
	_expect(faction.supply == 7, "300 ticks should grant one base income and the central region's +1 settlement", failures)
	_expect(settled.last_settlement_tick == 300, "strategic region settlement should be recorded at the exact 30-second tick", failures)
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.enabled = true
	_set_test_formation_position(world, friendly_formation, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	enemy.position = SimulationWorld.GREY_RIDGE_CENTRAL_POSITION
	enemy.desired_position = enemy.position
	world._advance_strategic_regions()
	var broken := world.create_snapshot().get_strategic_region(&"central_relay")
	_expect(not broken.contested, "a revived member of a zero-organization enemy card cannot capture a new objective", failures)
	var enemy_card := world.unit_cards[enemy.unit_card_id] as UnitCardState
	enemy_card.organization = world.battle_definition.organization_max
	world.refresh_unit_card_organization_baseline(enemy_card)
	world._advance_strategic_regions()
	var contested := world.create_snapshot().get_strategic_region(&"central_relay")
	_expect(contested.controller_faction_id == SimulationWorld.LOCAL_PLAYER_ID and contested.contested, "hostile presence should contest income without erasing the current owner (controller=%d contested=%s capture=%d progress=%d/%d friendly_enabled=%d enemy_enabled=%s)" % [contested.controller_faction_id, contested.contested, contested.capture_faction_id, contested.capture_progress_ticks, contested.capture_required_ticks, friendly_formation.member_entity_ids.filter(func(entity_id: int) -> bool: return (world.units[entity_id] as UnitState).enabled).size(), enemy.enabled], failures)


func _test_strategic_region_capture_lifecycle(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var west := world.strategic_regions[&"west_mine"] as StrategicRegionState
	var friendly := world.formations[SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID] as FormationState
	var hostile := world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		unit.enabled = unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID
	_set_test_formation_position(world, friendly, west.position)
	for _tick in range(12):
		world._advance_strategic_regions()
	_expect(west.controller_faction_id == 0 and west.capture_faction_id == SimulationWorld.LOCAL_PLAYER_ID and west.capture_ratio() > 0.0, "neutral supply points should remain gray while a friendly blue capture bar advances", failures)
	_set_test_formation_position(world, friendly, world.battle_definition.player_headquarters_position)
	for _tick in range(6):
		world._advance_strategic_regions()
	_expect(west.capture_progress_ticks == 0 and west.capture_faction_id == 0, "an abandoned neutral capture should decay to zero and return to the neutral gray state", failures)
	var interruption_logged := false
	for event in world.events:
		interruption_logged = interruption_logged or event.kind == SimulationEvent.Kind.REGION_CAPTURE_INTERRUPTED and event.detail.contains("region=west_mine")
	_expect(interruption_logged, "capture decay should emit an interruption event for HUD, sound, and map feedback", failures)
	_set_test_formation_position(world, friendly, west.position)
	for _tick in range(west.capture_required_ticks):
		world._advance_strategic_regions()
	_expect(west.controller_faction_id == SimulationWorld.LOCAL_PLAYER_ID and west.capture_ratio() == 1.0, "a completed friendly capture should turn the supply point blue", failures)
	for entity_id in hostile.member_entity_ids:
		(world.units[entity_id] as UnitState).enabled = entity_id == hostile.member_entity_ids[0]
	_set_test_formation_position(world, friendly, world.battle_definition.player_headquarters_position)
	_set_test_formation_position(world, hostile, west.position)
	for _tick in range(15):
		world._advance_strategic_regions()
	var hostile_progress := west.capture_progress_ticks
	_expect(west.controller_faction_id == SimulationWorld.LOCAL_PLAYER_ID and west.capture_faction_id == SimulationWorld.ENEMY_PLAYER_ID and hostile_progress > 0, "enemy takeover progress should be red while completed ownership remains blue", failures)
	_set_test_formation_position(world, friendly, west.position)
	world._advance_strategic_regions()
	_expect(west.contested and west.capture_progress_ticks == hostile_progress, "opposing capture-capable units should visibly contest and pause the progress bar", failures)
	_set_test_formation_position(world, friendly, world.battle_definition.player_headquarters_position)
	for _tick in range(west.capture_required_ticks - hostile_progress):
		world._advance_strategic_regions()
	_expect(west.controller_faction_id == SimulationWorld.ENEMY_PLAYER_ID and west.capture_ratio() == 1.0 and not west.contested, "a completed hostile takeover should turn the supply point red", failures)


func _test_enemy_strategic_recon_attack_and_capture(failures: Array[String]) -> void:
	var recon_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	recon_world.tasks.clear()
	recon_world.enemy_reaction_committed_until_tick = 0
	recon_world._next_enemy_strategic_decision_tick = 0
	var probe := recon_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID] as FormationState
	var recon_assault := recon_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	_set_test_formation_position(recon_world, probe, probe.anchor_position)
	recon_assault.is_moving = true
	recon_world._advance_enemy_strategic_ai()
	var recon_command: StrategicOrderCommand
	for queued in recon_world.command_queue.snapshot():
		if queued is StrategicOrderCommand and (queued as StrategicOrderCommand).formation_id == probe.formation_id:
			recon_command = queued as StrategicOrderCommand
	_expect(recon_command != null and recon_command.order_kind == StrategicOrderCommand.OrderKind.SCOUT_AREA and recon_command.issuer_id == SimulationWorld.ENEMY_PLAYER_ID, "enemy reconnaissance should submit a legal scout-area order through the shared command pipeline (queue=%d next=%s last=%s)" % [recon_world.command_queue.size(), recon_world.find_reachable_scout_target(SimulationWorld.ENEMY_PLAYER_ID, probe.anchor_position), recon_world.events[-1].detail if not recon_world.events.is_empty() else "none"], failures)

	var attack_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	attack_world.tasks.clear()
	attack_world.enemy_reaction_committed_until_tick = 0
	attack_world.enemy_offensive_followup_executed = true
	attack_world.current_tick = attack_world.battle_definition.enemy_offensive_followup_tick + 300
	attack_world._next_enemy_strategic_decision_tick = 0
	var attacking := attack_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	var target := attack_world.formations[SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID] as FormationState
	for entity_id in (attack_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID] as FormationState).member_entity_ids:
		(attack_world.units[entity_id] as UnitState).enabled = false
	_set_test_formation_position(attack_world, attacking, Vector2(3072.0, 2048.0))
	_set_test_formation_position(attack_world, target, Vector2(3192.0, 2048.0))
	attack_world._update_faction_knowledge()
	attack_world._advance_enemy_strategic_ai()
	var attack_command: StrategicOrderCommand
	for queued in attack_world.command_queue.snapshot():
		if queued is StrategicOrderCommand:
			attack_command = queued as StrategicOrderCommand
	_expect(attack_command != null and attack_command.order_kind == StrategicOrderCommand.OrderKind.ATTACK_TARGET and attack_command.issuer_id == SimulationWorld.ENEMY_PLAYER_ID, "enemy assault AI should use visible legal contacts to issue a shared attack-target order", failures)

	var capture_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	capture_world.tasks.clear()
	capture_world.enemy_reaction_committed_until_tick = 0
	capture_world.enemy_offensive_followup_executed = true
	capture_world.current_tick = capture_world.battle_definition.enemy_offensive_followup_tick + 300
	capture_world._next_enemy_strategic_decision_tick = 0
	for unit_variant in capture_world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID or unit.formation_id == SimulationWorld.GREY_RIDGE_ENEMY_PROBE_FORMATION_ID:
			unit.enabled = false
	var capturing := capture_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState
	_set_test_formation_position(capture_world, capturing, Vector2(3072.0, 2048.0))
	capture_world._update_faction_knowledge()
	capture_world._advance_enemy_strategic_ai()
	var capture_command: StrategicOrderCommand
	for queued in capture_world.command_queue.snapshot():
		if queued is StrategicOrderCommand:
			capture_command = queued as StrategicOrderCommand
	_expect(capture_command != null and capture_command.order_kind == StrategicOrderCommand.OrderKind.DEFEND_AREA and capture_command.issuer_id == SimulationWorld.ENEMY_PLAYER_ID, "enemy strategic AI should select and legally order a reachable valuable supply point (queue=%d contact=%s region=%s last=%s)" % [capture_world.command_queue.size(), capture_world._best_visible_hostile(capture_world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID), capturing.anchor_position), capture_world._best_enemy_capture_region(capturing.anchor_position).region_id if capture_world._best_enemy_capture_region(capturing.anchor_position) != null else &"none", capture_world.events[-1].detail if not capture_world.events.is_empty() else "none"], failures)
	if capture_command != null:
		var chosen_region := capture_world._region_near_position(capture_command.target_position)
		_expect(chosen_region != null and chosen_region.capturable, "enemy capture orders should target an authoritative capturable region instead of an arbitrary map coordinate", failures)


func _test_grey_ridge_support_orders(failures: Array[String]) -> void:
	var recon_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var spotted_enemy := recon_world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	spotted_enemy.position = SimulationWorld.GREY_RIDGE_EAST_POSITION
	(recon_world.formations[SimulationWorld.GREY_RIDGE_ENEMY_ASSAULT_FORMATION_ID] as FormationState).is_moving = false
	recon_world._update_faction_knowledge()
	_expect(not recon_world.is_entity_visible_to_faction(spotted_enemy.entity_id, SimulationWorld.LOCAL_PLAYER_ID), "east-region hostile should begin outside fair local vision", failures)
	var invalid_pair := SupportOrderCommand.new(recon_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SupportOrderCommand.SupportKind.AIR_RECON, &"west_mine", &"east_supply")
	_expect(recon_world.submit_command(invalid_pair).reason == CommandValidationResult.Reason.INVALID_TARGET, "air reconnaissance should reject non-adjacent region pairs", failures)
	var recon := SupportOrderCommand.new(recon_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SupportOrderCommand.SupportKind.AIR_RECON, &"central_relay", &"east_supply")
	_expect(recon_world.submit_command(recon).is_accepted(), "air reconnaissance should accept two adjacent regions", failures)
	recon_world.advance_tick()
	_expect(recon_world.is_entity_visible_to_faction(spotted_enemy.entity_id, SimulationWorld.LOCAL_PLAYER_ID), "air reconnaissance should reveal real hostile state through faction knowledge", failures)
	_expect((recon_world.factions[1] as FactionState).supply == 3, "air reconnaissance should deduct two supply", failures)
	_expect((recon_world.factions[1] as FactionState).air_recon_cooldown_until_tick == SimulationWorld.SUPPORT_COOLDOWN_TICKS, "support outside central control should use the full authoritative cooldown", failures)
	var repeated_recon := SupportOrderCommand.new(recon_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, recon_world.current_tick, SupportOrderCommand.SupportKind.AIR_RECON, &"central_relay", &"east_supply")
	_expect(recon_world.submit_command(repeated_recon).reason == CommandValidationResult.Reason.SUPPORT_COOLDOWN, "support should reject repeated use during cooldown", failures)
	_expect(recon_world.create_snapshot().intel_reports.size() == 5, "air reconnaissance should append one authoritative report per covered region", failures)
	var active_reports: Array[IntelReportSnapshot] = []
	for report in recon_world.create_snapshot().intel_reports:
		if not report.superseded:
			active_reports.append(report)
	_expect(active_reports.size() == 3, "Cardinal should merge superseded reports into one active assessment per region", failures)
	var central_assessment := active_reports.filter(func(report: IntelReportSnapshot) -> bool: return report.region_id == &"central_relay")[0] as IntelReportSnapshot
	var east_assessment := active_reports.filter(func(report: IntelReportSnapshot) -> bool: return report.region_id == &"east_supply")[0] as IntelReportSnapshot
	_expect(central_assessment.contradictory and central_assessment.estimated_min == 0 and central_assessment.estimated_max == 12, "non-overlapping direct reports should surface a conservative contradiction instead of silently replacing evidence", failures)
	_expect(east_assessment.has_estimate and east_assessment.eta_max_ticks == 0, "air reconnaissance should replace an unknown sector with a current confirmed estimate", failures)

	var relay_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	for unit_variant in relay_world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			unit.enabled = false
	var relay_formation := relay_world.formations[SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID] as FormationState
	_set_test_formation_position(relay_world, relay_formation, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	var relay := relay_world.strategic_regions[&"central_relay"] as StrategicRegionState
	for _tick in range(relay.capture_required_ticks):
		relay_world.advance_tick()
	var accelerated := SupportOrderCommand.new(relay_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, relay_world.current_tick, SupportOrderCommand.SupportKind.AIR_RECON, &"west_mine", &"central_relay")
	_expect(relay_world.submit_command(accelerated).is_accepted(), "central controller should still pay and submit support normally", failures)
	relay_world.advance_tick()
	var relay_faction := relay_world.factions[1] as FactionState
	_expect(relay_faction.air_recon_cooldown_until_tick - relay_world.current_tick + 1 == SimulationWorld.CENTRAL_RELAY_SUPPORT_COOLDOWN_TICKS, "owning the uncontested central relay should halve support cooldown", failures)

	var fortify_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var ironwall := fortify_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var formation := fortify_world.formations[ironwall.formation_id] as FormationState
	var member := fortify_world.units[ironwall.member_entity_ids[0]] as UnitState
	var base_armor := member.armor
	var move := FormationMoveCommand.new(fortify_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, formation.leader_entity_id, formation.formation_id, formation.anchor_position + Vector2(0.0, -320.0))
	var fortify := SupportOrderCommand.new(fortify_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY, &"", &"", &"ironwall_assault_group")
	_expect(fortify_world.submit_command(move).is_accepted() and fortify_world.submit_command(fortify).is_accepted(), "emergency fortification should accept a deployed friendly unit card", failures)
	fortify_world.advance_tick()
	_expect(not formation.is_moving and ironwall.fortified_ticks_remaining == 199, "fortification should stop the whole formation and start a 20-second effect", failures)
	_expect(is_equal_approx(member.armor, base_armor + SimulationWorld.FORTIFICATION_ARMOR_BONUS), "fortification should apply a temporary authoritative armor bonus", failures)
	for _tick in range(199):
		fortify_world.advance_tick()
	_expect(ironwall.fortified_ticks_remaining == 0 and is_equal_approx(member.armor, base_armor), "fortification expiry should restore unit armor exactly (remaining=%d armor=%.2f base=%.2f enabled=%s terrain=%s)" % [ironwall.fortified_ticks_remaining, member.armor, base_armor, member.enabled, UnitState.TerrainKind.keys()[member.terrain_kind]], failures)

	var reinforcement_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var reinforcement_card := reinforcement_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var full_strength_order := SupportOrderCommand.new(reinforcement_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"", &"", &"ironwall_assault_group")
	_expect(reinforcement_world.submit_command(full_strength_order).reason == CommandValidationResult.Reason.UNIT_CARD_FULL_STRENGTH, "field reinforcement should reject a card already at authorized strength", failures)
	for entity_id in reinforcement_card.member_entity_ids.slice(-2):
		var casualty := reinforcement_world.units[entity_id] as UnitState
		casualty.enabled = false
		casualty.health = 0.0
		casualty.death_tick = reinforcement_world.current_tick
	reinforcement_world._refresh_battle_population()
	var reinforcement_order := SupportOrderCommand.new(reinforcement_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"", &"", &"ironwall_assault_group")
	_expect(reinforcement_world.submit_command(reinforcement_order).is_accepted(), "a damaged deployed card should accept field reinforcement paid from battle supply", failures)
	reinforcement_world.advance_tick()
	var reinforced_snapshot := reinforcement_world.create_snapshot().get_unit_card(&"ironwall_assault_group")
	var reinforced_formation := reinforcement_world.formations[reinforcement_card.formation_id] as FormationState
	var reinforced_ids: Array[int] = []
	for entity_id in reinforcement_card.member_entity_ids:
		if entity_id >= 1100:
			reinforced_ids.append(entity_id)
	_expect(reinforced_snapshot.current_strength == 12 and reinforced_ids.size() == 2, "field reinforcement should restore two real entities up to authorized card strength", failures)
	_expect(reinforced_formation.member_entity_ids.size() == 12 and (reinforcement_world.factions[1] as FactionState).population == 20, "reinforced entities should occupy stable formation slots and population", failures)
	_expect((reinforcement_world.factions[1] as FactionState).supply == 3 and (reinforcement_world.factions[1] as FactionState).reinforcement_cooldown_until_tick == SimulationWorld.SUPPORT_COOLDOWN_TICKS, "field reinforcement should spend two battle supply and start its independent cooldown", failures)
	for entity_id in reinforced_ids:
		var reinforcement := reinforcement_world.units[entity_id] as UnitState
		_expect(reinforcement.unit_card_id == &"ironwall_assault_group" and reinforcement.control_state == UnitState.ControlState.AGENT_ASSIGNED and reinforcement.assigned_task_id == reinforcement_card.assigned_task_id, "new entities should inherit their card, commander Agent, and active task", failures)
	var renewed_casualty := reinforcement_world.units[reinforced_ids[0]] as UnitState
	renewed_casualty.enabled = false
	renewed_casualty.death_tick = reinforcement_world.current_tick
	reinforcement_world._refresh_battle_population()
	var cooldown_order := SupportOrderCommand.new(reinforcement_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, reinforcement_world.current_tick, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"", &"", &"ironwall_assault_group")
	_expect(reinforcement_world.submit_command(cooldown_order).reason == CommandValidationResult.Reason.SUPPORT_COOLDOWN, "new casualties should not bypass the reinforcement card cooldown", failures)

	var capped_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var capped_card := capped_world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	for entity_id in capped_card.member_entity_ids.slice(-2):
		(capped_world.units[entity_id] as UnitState).enabled = false
	capped_world._refresh_battle_population()
	(capped_world.factions[1] as FactionState).population_capacity = 19
	var capped_order := SupportOrderCommand.new(capped_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"", &"", &"ironwall_assault_group")
	_expect(capped_world.submit_command(capped_order).is_accepted(), "field reinforcement should accept a partial batch when only one population slot remains", failures)
	capped_world.advance_tick()
	_expect(capped_world.create_snapshot().get_unit_card(&"ironwall_assault_group").current_strength == 11 and (capped_world.factions[1] as FactionState).population == 19, "partial reinforcement should fill but never exceed the population cap", failures)


func _test_grey_ridge_reserve_deployment(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var position := headquarters.position + Vector2(160.0, -64.0)
	var objective := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE,
		SimulationWorld.GREY_RIDGE_WEST_POSITION, &"west_mine"
	)
	var command := DeployUnitCardCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, world.current_tick, &"armored_spearhead", position
	)
	_expect(world.submit_command(objective).is_accepted() and world.submit_command(command).is_accepted(), "a reserve card should accept deployment while its commander has an active objective", failures)
	world.advance_tick()
	var deploying := world.create_snapshot().get_unit_card(&"armored_spearhead")
	_expect(deploying.deployment_state == UnitCardState.DeploymentState.DEPLOYING and deploying.deployment_ticks_remaining == 99, "accepted deployment should deduct time only inside authoritative ticks", failures)
	_expect((world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).supply == 1, "deployment should deduct its authoritative supply cost", failures)
	_expect((world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).population == 28, "deploying reserves should commit population capacity immediately", failures)
	for _tick in range(99):
		world.advance_tick()
	var deployed := world.create_snapshot().get_unit_card(&"armored_spearhead")
	_expect(deployed.deployment_state == UnitCardState.DeploymentState.DEPLOYED and deployed.current_strength == 8, "deployment completion should create all authorized battlefield entities", failures)
	_expect(deployed.formation_id != 0 and world.formations.has(deployed.formation_id), "a deployed unit card should own one stable real formation", failures)
	var deployed_task := world.tasks[deployed.assigned_task_id] as TaskState
	_expect(deployed_task != null and deployed_task.target_position.distance_to(SimulationWorld.GREY_RIDGE_WEST_POSITION) <= deployed_task.target_radius, "a newly deployed card should join its commander's current objective instead of idling at the deployment point", failures)


func _test_grey_ridge_deployment_validation(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var valid_position := headquarters.position + Vector2(128.0, 0.0)
	var armor := DeployUnitCardCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, &"armored_spearhead", valid_position)
	var duplicate := DeployUnitCardCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, &"armored_spearhead", valid_position)
	var firepower := DeployUnitCardCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, &"thunder_fire_group", valid_position)
	_expect(world.submit_command(armor).is_accepted(), "first same-tick reserve deployment should be accepted", failures)
	_expect(world.submit_command(duplicate).reason == CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE, "the same reserve card cannot be queued twice in one tick", failures)
	_expect(world.submit_command(firepower).reason == CommandValidationResult.Reason.INSUFFICIENT_SUPPLY, "same-tick deployment validation should reserve pending supply", failures)
	var far_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var far_command := DeployUnitCardCommand.new(far_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, &"armored_spearhead", Vector2(100.0, 100.0))
	_expect(far_world.submit_command(far_command).reason == CommandValidationResult.Reason.INVALID_POSITION, "reserves must deploy within the headquarters radius", failures)
	(far_world.factions[1] as FactionState).population_capacity = 27
	var full_command := DeployUnitCardCommand.new(far_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, &"armored_spearhead", valid_position)
	_expect(far_world.submit_command(full_command).reason == CommandValidationResult.Reason.POPULATION_FULL, "deployment should reject population overflow", failures)


func _test_grey_ridge_safe_reserve_deployment_exit(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var headquarters := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var desired_position := headquarters.position + Vector2(0.0, -160.0)
	var deploy := DeployUnitCardCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, &"armored_spearhead", desired_position, &"di_tian"
	)
	_expect(world.submit_command(deploy).is_accepted(), "a near-HQ reserve deployment should resolve to a whole-formation-safe staging point", failures)
	_expect(not deploy.deployment_position.is_equal_approx(desired_position), "an unsafe requested anchor should be deterministically adjusted before entering the authoritative queue", failures)
	for _tick in range(101):
		world.advance_tick()
	var card := world.unit_cards[&"armored_spearhead"] as UnitCardState
	var formation := world.formations.get(card.formation_id) as FormationState
	_expect(formation != null and card.member_entity_ids.size() == card.definition.authorized_strength, "the resolved deployment should create the full reserve card", failures)
	if formation == null:
		return
	var starting_positions: Dictionary = {}
	for entity_id in card.member_entity_ids:
		var member := world.units[entity_id] as UnitState
		starting_positions[entity_id] = member.position
		_expect(world.logic_grid.is_world_position_walkable(member.position), "reserve member E%d must not spawn inside the headquarters footprint" % entity_id, failures)
	var target := world.find_formation_deployment_position(formation, formation.anchor_position + Vector2(0.0, -480.0), 192.0)
	_expect(target.is_finite(), "the deployed card should have a reachable outbound staging position", failures)
	var move := FormationMoveCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, formation.leader_entity_id, formation.formation_id, target
	)
	var move_result := world.submit_command(move)
	_expect(move_result.is_accepted(), "the newly deployed whole card should accept an outbound route (reason=%s)" % CommandValidationResult.Reason.keys()[move_result.reason], failures)
	for _tick in range(240):
		world.advance_tick()
		if not formation.is_moving:
			break
	for entity_id in card.member_entity_ids:
		var member := world.units[entity_id] as UnitState
		_expect(member.position.distance_to(starting_positions[entity_id] as Vector2) > 96.0, "reserve member E%d should leave its base staging position with the whole-card order" % entity_id, failures)
		_expect(world.logic_grid.is_world_position_walkable(member.position), "reserve member E%d should remain on walkable terrain after leaving the base" % entity_id, failures)


func _test_army_roster_snapshot_tracks_real_entities(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var snapshot := world.create_snapshot()
	_expect(snapshot.commanders.size() == 2, "default slice should expose two persistent commander cards", failures)
	_expect(snapshot.unit_cards.size() == 2, "default slice should expose two persistent unit cards", failures)
	var falcon := snapshot.get_unit_card(&"falcon_recon_group")
	var ironwall := snapshot.get_unit_card(&"ironwall_assault_group")
	_expect(falcon != null and falcon.active_member_entity_ids == [3], "Falcon card should bind the real scout entity", failures)
	_expect(ironwall != null and ironwall.active_member_entity_ids == [4, 5], "Ironwall card should bind the real assault and fire-support entities", failures)
	var old_strength := ironwall.current_strength
	(world.units[5] as UnitState).enabled = false
	var updated := world.create_snapshot().get_unit_card(&"ironwall_assault_group")
	_expect(old_strength == 2 and updated.current_strength == 1, "unit-card strength should derive from current authoritative survivors", failures)
	_expect(ironwall.current_strength == 2, "old unit-card snapshots must remain immutable value copies", failures)


func _test_destroyed_unit_wreck_expires(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.enabled = false
	enemy.health = 0.0
	enemy.death_tick = world.current_tick
	for _tick in range(SimulationWorld.WRECK_LIFETIME_TICKS):
		world.advance_tick()
	_expect(world.units.has(enemy.entity_id), "destroyed unit should remain briefly as a wreck", failures)
	world.advance_tick()
	_expect(not world.units.has(enemy.entity_id), "expired unit wreck should be removed from authoritative state", failures)


func _test_fixed_tick_movement(failures: Array[String]) -> void:
	var world := _moving_world(Vector2(700.0, 360.0))
	var before := world.create_snapshot().get_unit(1).position
	var after := world.advance_tick().get_unit(1).position
	_expect(is_equal_approx(after.distance_to(before), 18.0), "10 Hz tick should move exactly 18 pixels", failures)


func _test_arrival_without_overshoot(failures: Array[String]) -> void:
	var target := Vector2(325.0, 360.0)
	var world := _moving_world(target)
	var unit := world.advance_tick().get_unit(1)
	_expect(unit.position == target, "unit should stop exactly at close target", failures)
	_expect(not unit.is_moving, "unit should become idle on arrival", failures)


func _test_snapshot_is_value_copy(failures: Array[String]) -> void:
	var world := _moving_world(Vector2(700.0, 360.0))
	var old_snapshot := world.create_snapshot()
	var old_position := old_snapshot.get_unit(1).position
	world.advance_tick()
	_expect(old_snapshot.get_unit(1).position == old_position, "old snapshot must not mutate", failures)


func _test_deterministic_replay(failures: Array[String]) -> void:
	var first := _moving_world(Vector2(700.0, 500.0))
	var second := _moving_world(Vector2(700.0, 500.0))
	for index in range(20):
		var first_unit := first.advance_tick().get_unit(1)
		var second_unit := second.advance_tick().get_unit(1)
		_expect(first_unit.position == second_unit.position, "replay diverged at tick %d" % index, failures)


func _test_default_formation_and_snapshot_copy(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var snapshot := world.create_snapshot()
	_expect(snapshot.units.size() == 5, "local snapshot should hide the distant enemy at match start", failures)
	_expect(world.create_true_state_snapshot().units.size() == 8, "true state should contain player formation plus enemy garrison, harvester, and engineer", failures)
	var old_mode := snapshot.get_formation(1).mode
	var old_slot := snapshot.get_unit(5).formation_slot_id
	var command := FormationMoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, 1, Vector2(800.0, 336.0))
	world.submit_command(command)
	for tick in range(20):
		world.advance_tick()
	_expect(snapshot.get_formation(1).mode == old_mode, "old formation snapshot must not mutate", failures)
	_expect(snapshot.get_unit(5).formation_slot_id == old_slot, "old unit slot snapshot must not mutate", failures)


func _test_stuck_detection_and_recovery(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var formation := world.formations[1] as FormationState
	formation.target_position = Vector2(800.0, 336.0)
	formation.path = world.pathfinder.find_path(formation.anchor_position, formation.target_position)
	formation.path_index = 1
	formation.is_moving = true
	var unit := world.units[5] as UnitState
	unit.position = Vector2(600.0, 90.0)
	unit.following_formation = true
	unit.has_move_target = true
	var system := world.formation_movement
	for tick in range(FormationMovementSystem.STUCK_TICK_LIMIT):
		system._update_stuck_state(unit, formation, unit.position, world.events, tick)
	var saw_stuck := false
	for event in world.events:
		if event.kind == SimulationEvent.Kind.UNIT_STUCK and event.entity_id == 5:
			saw_stuck = true
	_expect(saw_stuck, "no-progress unit should emit UNIT_STUCK at threshold", failures)
	_expect(unit.recovery_attempts == 1, "stuck unit should perform one bounded recovery attempt", failures)


func _test_formation_member_snapshot_without_unit_path(failures: Array[String]) -> void:
	var unit := UnitState.new(77, Vector2(320.0, 240.0), 180.0, SimulationWorld.LOCAL_PLAYER_ID)
	unit.formation_id = SimulationWorld.DEFAULT_FORMATION_ID
	unit.following_formation = true
	unit.has_move_target = true
	unit.path_index = 1
	unit.path = PackedVector2Array()
	var snapshot := UnitSnapshot.new(unit)
	_expect(snapshot.is_moving, "formation member should remain marked moving when its route is owned by the formation", failures)
	_expect(snapshot.path.is_empty(), "formation-owned movement should allow an empty per-unit snapshot path", failures)


func _moving_world(target: Vector2) -> SimulationWorld:
	var world := SimulationWorld.new(false)
	world.units[1] = UnitState.new(1, Vector2(320.0, 360.0), 180.0, 1)
	var command := MoveCommand.new(1, 1, GameCommand.IssuerKind.PLAYER, 0, 1, target)
	world.submit_command(command)
	return world


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
