class_name TestEnemyOperation
extends RefCounted

func run() -> Array[String]:
	var failures: Array[String] = []
	_test_content(failures)
	_test_lock_and_fairness(failures)
	_test_withdrawal(failures)
	_test_threshold(failures)
	return failures

func _test_content(failures: Array[String]) -> void:
	for id in [&"grey_ridge", &"broken_bridge", &"fog_forest", &"black_well"]:
		var loaded := BattleContentLoader.load_battle(id)
		_expect(loaded.validation.is_valid(), "four operations compile typed legacy plans: " + String(id), failures)
	var battle := BattleContentLoader.load_battle(&"grey_ridge").battle
	var definition := EnemyOperationDefinition.compile_legacy(battle, battle.enemy_plans[0])
	definition.doctrine.max_committed_strength = 1
	_expect(not definition.validate(battle).is_valid(), "overcommitted opening rejected", failures)
	definition.doctrine.max_committed_strength = 40
	definition.phases[0].formation_role_id = &"missing"
	_expect(not definition.validate(battle).is_valid(), "unknown formation rejected", failures)
	definition.phases[0].formation_role_id = &"assault"
	definition.phases[0].target_position = Vector2(NAN, 0)
	_expect(not definition.validate(battle).is_valid(), "nonfinite target rejected", failures)

func _test_lock_and_fairness(failures: Array[String]) -> void:
	var a := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var b := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var old := a.create_faction_snapshot(2).enemy_operation
	_expect(old != null and old.locked_tick == 0 and old.phases.size() >= 3, "operation locked before play", failures)
	_expect(a.create_snapshot().enemy_operation == null, "player cannot inspect hidden enemy plan", failures)
	old.phases[0].definition.target_position = Vector2.ZERO
	old.doctrine.max_committed_strength = 999
	_expect(a.create_faction_snapshot(2).enemy_operation.phases[0].definition.target_position != Vector2.ZERO and a.create_faction_snapshot(2).enemy_operation.doctrine.max_committed_strength != 999, "snapshot nested resources copied", failures)
	# Same legal own state, different hidden player HQ: the locked objective is identical.
	(b.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState).position += Vector2(1000, 0)
	(b.factions[1] as FactionState).supply = 0
	for world in [a, b]:
		world.current_tick = world.battle_definition.enemy_offensive_followup_tick
		world.enemy_reaction_committed_until_tick = 0
		for formation_variant in world.formations.values():
			var formation := formation_variant as FormationState
			formation.is_moving = false
			formation.order_target_entity_id = 0
		world.enemy_operation_system.advance(world)
	var qa := a.command_queue.snapshot()
	var qb := b.command_queue.snapshot()
	_expect(qa.size() == qb.size() and not qa.is_empty(), "hidden HQ/economy do not alter stage proposal count", failures)
	if not qa.is_empty() and qa.size() == qb.size():
		_expect(qa[-1] is AttackMoveCommand and qb[-1] is AttackMoveCommand and qa[-1].target_position == qb[-1].target_position, "exploit does not track hidden live HQ", failures)
	_expect(a.enemy_offensive_followup_executed, "real exploit command accepted", failures)
	var before := a.create_faction_snapshot(2).enemy_operation
	a.advance_tick()
	var assault := a._enemy_formation_state(&"assault")
	_expect(assault.order_kind == FormationState.OrderKind.ATTACK_MOVE, "accepted exploit is applied through ordinary combat order", failures)
	_expect(before.phases[-1].changed_tick < a.current_tick, "old snapshot stays unchanged after world tick", failures)

func _test_withdrawal(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	var kept := 0
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id == 2:
			kept += 1
			if kept > 2: unit.enabled = false
	world.current_tick = 200
	world.enemy_operation_system.advance(world)
	_expect(world.enemy_operation_system.is_withdrawing(), "own observed losses trigger doctrine retreat", failures)
	var snapshot := world.create_faction_snapshot(2).enemy_operation
	_expect(not snapshot.withdrawn_formation_ids.is_empty(), "retreat submitted for surviving force", failures)
	world.advance_tick()
	var formation := world.formations[snapshot.withdrawn_formation_ids[0]] as FormationState
	_expect(formation.order_destination.distance_to(snapshot.retreat_position) < 1, "retreat applies to actual formation", failures)
	for _tick in range(5): world.advance_tick()
	_expect(world.enemy_operation_system.is_withdrawing() and formation.order_destination.distance_to(snapshot.retreat_position) < 1, "strategic followup cannot override withdrawal", failures)

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition: failures.append("Enemy operation: " + message)


func _test_threshold(failures: Array[String]) -> void:
	for survivors in [8, 7]:
		var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
		world.enemy_operation_system._state.doctrine.retreat_strength_ratio = 0.5
		var kept := 0
		for unit in world.units.values():
			if unit.faction_id == 2:
				kept += 1
				if kept > survivors: unit.enabled = false
		world.current_tick = 200
		world.enemy_operation_system.advance(world)
		_expect(world.enemy_operation_system.is_withdrawing() == (survivors == 7), "retreat threshold includes equality, not above boundary", failures)
