class_name TestStaffPlanApproval
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_approval_and_copy(failures)
	_test_rejections(failures)
	_test_application_revalidation(failures)
	return failures


func _world() -> SimulationWorld:
	return SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)


func _command(world: SimulationWorld) -> StaffPlanApprovalCommand:
	var request := TestStaffPlans.request()
	var plans := StaffPlanGenerator.new().generate(world.create_snapshot(), 1, request)
	return StaffPlanApprovalCommand.new(world.allocate_command_id(), 1, world.current_tick, request,
		plans.plans[0].profile_id, plans.plans[0].fingerprint())


func _test_approval_and_copy(failures: Array[String]) -> void:
	var world := _world()
	var original := world.create_snapshot()
	var command := _command(world)
	var before_supply := (world.factions[1] as FactionState).supply
	_expect(world.submit_command(command).is_accepted(), "legal approval enters the common queue", failures)
	_expect(world.create_snapshot().staff_plan_decisions.is_empty(), "enqueue does not mean approval applied", failures)
	command.request.max_supply_cost = 999
	command.expected_fingerprint = "tampered after submission"
	var snapshot := world.advance_tick()
	_expect(snapshot.staff_plan_decisions.size() == 1 and snapshot.staff_plan_decisions[0].accepted, "queue holds value copy and applies reviewed plan", failures)
	if snapshot.staff_plan_decisions.is_empty():
		return
	var decision := snapshot.staff_plan_decisions[0]
	_expect(decision.command_id == command.command_id and decision.approved_plan != null and decision.decided_tick == 0, "receipt has command, plan and authority tick", failures)
	_expect((world.factions[1] as FactionState).supply == before_supply, "approval does not prematurely spend deployment budget", failures)
	_expect(original.staff_plan_decisions.is_empty(), "old snapshots stay unchanged", failures)
	_expect(world.create_faction_snapshot(2).staff_plan_decisions.is_empty(), "opponent cannot read private plan", failures)
	var fingerprint := decision.approved_plan.fingerprint()
	decision.approved_plan.assignments.clear()
	_expect(world.create_snapshot().staff_plan_decisions[0].approved_plan.fingerprint() == fingerprint, "consumer cannot mutate approved authority state", failures)
	var events := world.events.filter(func(event: SimulationEvent) -> bool: return event.kind == SimulationEvent.Kind.STAFF_PLAN_DECIDED)
	_expect(events.size() == 1 and events[0].detail.contains("accepted=1"), "approval emits one auditable event", failures)
	_expect(_world().create_snapshot().staff_plan_decisions.is_empty(), "new battle clears prior approval", failures)


func _test_rejections(failures: Array[String]) -> void:
	var world := _world()
	var command := _command(world)
	command.issuer_kind = GameCommand.IssuerKind.AGENT
	_expect(world.submit_command(command).reason == CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED, "Agent cannot approve its own suggestion", failures)
	command = _command(world)
	command.issuer_id = SimulationWorld.ENEMY_PLAYER_ID
	_expect(world.submit_command(command).reason == CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED, "player cannot approve a foreign faction plan", failures)
	_expect(world.command_queue.size() == 0 and world.create_true_state_snapshot().staff_plan_decisions.is_empty(), "foreign approval leaves no queue or decision", failures)
	command = _command(world)
	command.expected_fingerprint = "forged"
	_expect(world.submit_command(command).reason == CommandValidationResult.Reason.STAFF_PLAN_STALE, "forged plan rejected", failures)
	command = _command(world)
	command.request.max_supply_cost = 999
	command.request.risk_aversion = 3
	_expect(world.submit_command(command).reason == CommandValidationResult.Reason.STAFF_PLAN_STALE, "changed request cannot reuse reviewed signature", failures)
	command = _command(world)
	world.advance_tick()
	_expect(world.submit_command(command).reason == CommandValidationResult.Reason.STAFF_PLAN_STALE, "old source tick requires regeneration", failures)
	command = _command(world)
	_expect(world.submit_command(command).is_accepted(), "fresh request accepted", failures)
	_expect(world.submit_command(_command(world)).reason == CommandValidationResult.Reason.TASK_CONFLICT, "duplicate pending approval rejected", failures)
	_expect(world.command_queue.snapshot().filter(func(value: GameCommand) -> bool: return value is StaffPlanApprovalCommand).size() == 1, "duplicate cannot enter queue", failures)


func _test_application_revalidation(failures: Array[String]) -> void:
	var world := _world()
	var first := _command(world)
	world.submit_command(first)
	world.advance_tick()
	var previous := world.create_snapshot().staff_plan_decisions[0].approved_plan.fingerprint()
	# Allocate the takeover first so both accepted commands resolve in that order.
	var takeover := UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick,
		&"ironwall_assault_group", UnitCardControlCommand.Action.TAKEOVER)
	_expect(world.submit_command(takeover).is_accepted(), "same-tick takeover enters queue", failures)
	var second := _command(world)
	_expect(world.submit_command(second).is_accepted(), "replacement enters queue", failures)
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var snapshot := world.advance_tick()
	var receipt := snapshot.staff_plan_decisions[0]
	_expect(not receipt.accepted and receipt.command_id == second.command_id and receipt.reason == CommandValidationResult.Reason.STAFF_PLAN_STALE, "application rechecks state before changing approval", failures)
	_expect(receipt.approved_plan.fingerprint() == previous, "failed replacement preserves earlier approval", failures)
	_expect(card.control_state == UnitCardState.ControlState.PLAYER_OVERRIDDEN, "approval never steals newly taken control", failures)


func _expect(value: bool, message: String, failures: Array[String]) -> void:
	if not value:
		failures.append("Staff approval: " + message)
