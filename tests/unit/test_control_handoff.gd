class_name TestControlHandoff
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_decision_handoff(failures)
	_test_missing_return_task(failures)
	_test_cancelled_return_task(failures)
	return failures


func _world() -> SimulationWorld:
	return SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)


func _control(world: SimulationWorld, card_id: StringName, action: UnitCardControlCommand.Action) -> CommandValidationResult:
	return world.submit_command(UnitCardControlCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, card_id, action))


func _intent(world: SimulationWorld) -> CommanderOrderCommand:
	return CommanderOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, &"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_INTENT, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay", CommanderState.Posture.BALANCED, PackedVector2Array(), &"handoff_intent", &"central_relay")


func _test_decision_handoff(failures: Array[String]) -> void:
	var world := _world()
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var other := world.unit_cards[&"falcon_recon_group"] as UnitCardState
	_expect(_control(world, card.definition.definition_id, UnitCardControlCommand.Action.TAKEOVER).is_accepted(), "takeover accepted", failures)
	_expect(_control(world, other.definition.definition_id, UnitCardControlCommand.Action.TAKEOVER).is_accepted(), "other commander takeover accepted", failures)
	world.advance_tick()
	var old_snapshot := world.create_snapshot()
	var invalid := _intent(world)
	invalid.target_position = Vector2.INF
	_expect(not world.submit_command(invalid).is_accepted(), "invalid decision rejected before handoff", failures)
	_expect(card.control_state == UnitCardState.ControlState.PLAYER_OVERRIDDEN, "rejected decision preserves manual control", failures)
	var background := _intent(world)
	background.issuer_kind = GameCommand.IssuerKind.AGENT
	# Exercise the authoritative handler to isolate the handoff guard; actual agents
	# still have to pass their ordinary command authorization before reaching it.
	world._apply_commander_order(background)
	_expect(card.control_state == UnitCardState.ControlState.PLAYER_OVERRIDDEN, "background Agent updates cannot reclaim manual cards", failures)
	_expect(world.submit_command(_intent(world)).is_accepted(), "player decision accepted", failures)
	world.advance_tick()
	_expect(card.control_state == UnitCardState.ControlState.AGENT_ASSIGNED, "decision hands its manual card to AI", failures)
	_expect(other.control_state == UnitCardState.ControlState.PLAYER_OVERRIDDEN, "decision does not reclaim another commander's card", failures)
	_expect(old_snapshot.get_unit_card(card.definition.definition_id).control_state == UnitCardState.ControlState.PLAYER_OVERRIDDEN, "old snapshots remain manual after new handoff", failures)
	var task := world.tasks[card.assigned_task_id] as TaskState
	_expect(task.lifecycle == TaskState.Lifecycle.EXECUTING and task.final_target_position.is_finite(), "handoff creates an executable current task", failures)
	for entity_id in card.member_entity_ids:
		var unit := world.units[entity_id] as UnitState
		_expect(not unit.rejoin_pending and unit.return_task_id == 0 and unit.control_state == UnitState.ControlState.AGENT_ASSIGNED, "members cannot complete stale rejoins after a decision handoff", failures)
	# Both accepted orders execute in command order within one tick.
	_expect(_control(world, card.definition.definition_id, UnitCardControlCommand.Action.TAKEOVER).is_accepted(), "same tick takeover accepted", failures)
	_expect(world.submit_command(_intent(world)).is_accepted(), "same tick decision accepted", failures)
	world.advance_tick()
	_expect(card.control_state == UnitCardState.ControlState.AGENT_ASSIGNED, "later decision owns the final same tick control state", failures)


func _test_missing_return_task(failures: Array[String]) -> void:
	var world := _world()
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	_control(world, card.definition.definition_id, UnitCardControlCommand.Action.STAY_MANUAL)
	world.advance_tick()
	_expect(card.return_task_id == 0 and card.return_formation_id == 0, "manual fixture has no legacy return metadata", failures)
	_expect(_control(world, card.definition.definition_id, UnitCardControlCommand.Action.RETURN_TO_COMMANDER).is_accepted(), "manual card without old task can return", failures)
	world.advance_tick()
	_expect(card.control_state == UnitCardState.ControlState.AGENT_ASSIGNED and card.assigned_task_id != 0, "AI resumes current commander work without old return metadata", failures)


func _test_cancelled_return_task(failures: Array[String]) -> void:
	var world := _world()
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	_control(world, card.definition.definition_id, UnitCardControlCommand.Action.TAKEOVER)
	world.advance_tick()
	var old_task := world.tasks[card.return_task_id] as TaskState
	var cancel := CommanderOrderCommand.new(world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick, &"di_tian", CommanderOrderCommand.OrderKind.CANCEL_INTENT)
	_expect(world.submit_command(cancel).is_accepted(), "cancellation accepted", failures)
	world.advance_tick()
	_expect(old_task.lifecycle == TaskState.Lifecycle.CANCELLED, "previous task is terminal", failures)
	_expect(_control(world, card.definition.definition_id, UnitCardControlCommand.Action.RETURN_TO_COMMANDER).is_accepted(), "return after cancellation accepted", failures)
	world.advance_tick()
	_expect(card.control_state == UnitCardState.ControlState.AGENT_ASSIGNED and card.assigned_task_id != old_task.task_id, "cancelled task is not resurrected during return", failures)
	_expect(old_task.lifecycle == TaskState.Lifecycle.CANCELLED, "old cancellation remains terminal", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("control handoff: " + message)
