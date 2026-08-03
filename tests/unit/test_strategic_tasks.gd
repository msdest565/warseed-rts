class_name TestStrategicTasks
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_develop_resource_completes_visible_work(failures)
	_test_defend_area_respects_leash(failures)
	_test_attack_target_advances_and_completes(failures)
	_test_task_controls_use_command_pipeline(failures)
	_test_complete_vertical_slice(failures)
	return failures


func _test_develop_resource_completes_visible_work(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var ore_field := world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState
	var order := StrategicOrderCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		world.current_tick,
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE,
		0,
		ore_field.entity_id,
		ore_field.position
	)
	_expect(world.submit_command(order).is_accepted(), "develop-resource order should enter the shared command queue", failures)
	var original_ore_remaining := ore_field.ore_remaining
	for _tick in range(80):
		world.advance_tick()
		var task := world.tasks.get(1) as TaskState
		if task != null and task.lifecycle == TaskState.Lifecycle.COMPLETED:
			break
	var task := world.tasks.get(1) as TaskState
	_expect(task != null and task.lifecycle == TaskState.Lifecycle.COMPLETED, "develop-resource task should complete", failures)
	_expect(ore_field.ore_remaining <= original_ore_remaining - EconomySystem.HARVEST_AMOUNT, "develop-resource task should perform authoritative harvesting", failures)
	_expect(_count_definition(world, &"harvester") >= 2, "develop-resource task should produce a second harvester", failures)
	_expect(world.create_snapshot().get_task(task.task_id).kind == TaskState.Kind.DEVELOP_RESOURCE, "task snapshot should expose strategic kind", failures)
	_expect(world.mission_state.developed_resource, "completed develop task should update mission progress", failures)


func _test_defend_area_respects_leash(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var formation := world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState
	var center := formation.anchor_position
	var radius := 40.0
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	_expect(enemy.position.distance_to(center) > radius, "defense fixture enemy should begin beyond the leash", failures)
	var order := StrategicOrderCommand.new(
		world.allocate_command_id(), 1, world.current_tick,
		StrategicOrderCommand.OrderKind.DEFEND_AREA,
		formation.formation_id, 0, center, radius
	)
	_expect(world.submit_command(order).is_accepted(), "defend-area order should validate", failures)
	for _tick in range(StrategicTaskSystem.DEFEND_HOLD_TICKS + 4):
		world.advance_tick()
	var task := world.tasks[1] as TaskState
	_expect(task.lifecycle == TaskState.Lifecycle.COMPLETED, "defend-area task should complete its hold interval", failures)
	_expect(formation.anchor_position.distance_to(center) <= radius, "defending formation must remain inside defense radius", failures)
	_expect(formation.order_target_entity_id == 0, "defending formation must not pursue a hostile beyond the leash", failures)
	_expect(world.mission_state.defended_area, "completed defense should update mission progress", failures)


func _test_attack_target_advances_and_completes(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var formation := world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState
	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	var order := StrategicOrderCommand.new(
		world.allocate_command_id(), 1, world.current_tick,
		StrategicOrderCommand.OrderKind.ATTACK_TARGET,
		formation.formation_id, enemy.entity_id, enemy.position
	)
	_expect(world.submit_command(order).is_accepted(), "attack-target order should validate against visible faction knowledge", failures)
	var saw_route_or_engagement := false
	for _tick in range(120):
		var snapshot := world.advance_tick()
		var task := snapshot.get_task(1)
		if task != null and (not task.route.is_empty() or task.phase == TaskState.Phase.ENGAGING):
			saw_route_or_engagement = true
		if task != null and task.lifecycle == TaskState.Lifecycle.COMPLETED:
			break
	var task := world.tasks[1] as TaskState
	_expect(saw_route_or_engagement, "attack task should expose its route or engagement phase", failures)
	_expect(not enemy.enabled and task.lifecycle == TaskState.Lifecycle.COMPLETED, "attack task should complete after destroying its target", failures)
	_expect(world.mission_state.attacked_target, "completed attack should update mission progress", failures)


func _test_task_controls_use_command_pipeline(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var formation := world.formations[1] as FormationState
	var order := StrategicOrderCommand.new(world.allocate_command_id(), 1, 0, StrategicOrderCommand.OrderKind.DEFEND_AREA, 1, 0, formation.anchor_position, 40.0)
	world.submit_command(order)
	world.advance_tick()
	var pause := TaskControlCommand.new(world.allocate_command_id(), 1, world.current_tick, 1, TaskControlCommand.Action.PAUSE)
	_expect(world.submit_command(pause).is_accepted(), "task pause should use shared validation and queue", failures)
	world.advance_tick()
	_expect((world.tasks[1] as TaskState).lifecycle == TaskState.Lifecycle.PAUSED, "pause should apply at tick boundary", failures)
	var resume := TaskControlCommand.new(world.allocate_command_id(), 1, world.current_tick, 1, TaskControlCommand.Action.RESUME)
	world.submit_command(resume)
	world.advance_tick()
	_expect((world.tasks[1] as TaskState).lifecycle == TaskState.Lifecycle.EXECUTING, "resume should restore task execution", failures)
	var cancel := TaskControlCommand.new(world.allocate_command_id(), 1, world.current_tick, 1, TaskControlCommand.Action.CANCEL)
	world.submit_command(cancel)
	world.advance_tick()
	_expect((world.tasks[1] as TaskState).lifecycle == TaskState.Lifecycle.CANCELLED, "cancel should terminate task authoritatively", failures)


func _test_complete_vertical_slice(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var ore_field := world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState
	world.submit_command(StrategicOrderCommand.new(
		world.allocate_command_id(), 1, world.current_tick,
		StrategicOrderCommand.OrderKind.DEVELOP_RESOURCE, 0, ore_field.entity_id, ore_field.position
	))
	_advance_until_terminal(world, 1, 90)
	_expect((world.tasks[1] as TaskState).lifecycle == TaskState.Lifecycle.COMPLETED, "slice should complete resource development", failures)

	var formation := world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState
	world.submit_command(StrategicOrderCommand.new(
		world.allocate_command_id(), 1, world.current_tick,
		StrategicOrderCommand.OrderKind.DEFEND_AREA, formation.formation_id, 0, formation.anchor_position, 40.0
	))
	world.advance_tick()
	var missile := world.units[5] as UnitState
	var takeover := MoveCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, missile.entity_id, missile.position + Vector2(0.0, 64.0))
	_expect(world.submit_command(takeover).is_accepted(), "slice should allow explicit missile takeover", failures)
	world.advance_tick()
	_expect(world.mission_state.missile_taken_over and (world.tasks[2] as TaskState).lifecycle == TaskState.Lifecycle.BLOCKED, "missile takeover should block defense without agent overwrite", failures)
	var return_command := UnitDispositionCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, missile.entity_id, UnitDispositionCommand.Disposition.RETURN)
	world.submit_command(return_command)
	world.advance_tick()
	for _tick in range(120):
		if not missile.rejoin_pending:
			break
		world.advance_tick()
	_expect(world.mission_state.missile_returned and missile.control_state == UnitState.ControlState.AGENT_ASSIGNED, "slice should return missile to its task without teleporting", failures)
	_advance_until_terminal(world, 2, 100)
	_expect((world.tasks[2] as TaskState).lifecycle == TaskState.Lifecycle.COMPLETED, "slice should resume and complete defense", failures)

	var enemy := world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	world.submit_command(StrategicOrderCommand.new(
		world.allocate_command_id(), 1, world.current_tick,
		StrategicOrderCommand.OrderKind.ATTACK_TARGET, formation.formation_id, enemy.entity_id, enemy.position
	))
	_advance_until_terminal(world, 3, 140)
	_expect((world.tasks[3] as TaskState).lifecycle == TaskState.Lifecycle.COMPLETED, "slice should complete final attack", failures)
	_expect(world.mission_state.completed, "all three assignments plus missile takeover and return should complete the mission", failures)
	_expect(world.create_snapshot().mission.completed, "mission completion should be visible in immutable snapshot", failures)


func _advance_until_terminal(world: SimulationWorld, task_id: int, tick_limit: int) -> void:
	for _tick in range(tick_limit):
		world.advance_tick()
		var task := world.tasks.get(task_id) as TaskState
		if task != null and task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
			return


func _count_definition(world: SimulationWorld, definition_id: StringName) -> int:
	var count := 0
	for unit_variant in world.units.values():
		var unit := unit_variant as UnitState
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID and unit.definition_id == definition_id:
			count += 1
	return count


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
