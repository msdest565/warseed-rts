class_name StaffPlanSystem
extends RefCounted

var _decisions: Dictionary[int, StaffPlanDecisionSnapshot] = {}


func validate(world: SimulationWorld, command: StaffPlanApprovalCommand) -> CommandValidationResult:
	if command.issuer_kind != GameCommand.IssuerKind.PLAYER or command.issuer_id != SimulationWorld.LOCAL_PLAYER_ID:
		return _rejected(CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED)
	if not world.is_card_battle() or not world.factions.has(command.issuer_id) or command.request == null or command.expected_fingerprint.is_empty():
		return _rejected(CommandValidationResult.Reason.INVALID_TARGET)
	if _resolve(world, command) == null:
		return _rejected(CommandValidationResult.Reason.STAFF_PLAN_STALE)
	return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)


func apply(world: SimulationWorld, command: StaffPlanApprovalCommand) -> void:
	var validation := validate(world, command)
	var plan := _resolve(world, command) if validation.is_accepted() else null
	var decision := StaffPlanDecisionSnapshot.new()
	decision.faction_id = command.issuer_id
	decision.command_id = command.command_id
	decision.decided_tick = world.current_tick
	decision.accepted = plan != null
	decision.reason = validation.reason
	if plan != null:
		decision.approved_plan = plan.duplicate_value()
	elif _decisions.has(command.issuer_id):
		var previous := _decisions[command.issuer_id].approved_plan
		decision.approved_plan = previous.duplicate_value() if previous != null else null
	_decisions[command.issuer_id] = decision
	world.events.append(SimulationEvent.new(world.current_tick, SimulationEvent.Kind.STAFF_PLAN_DECIDED, 0,
		"faction=%d;command=%d;accepted=%d;profile=%s;reason=%s" % [command.issuer_id, command.command_id,
			1 if decision.accepted else 0, command.profile_id, CommandValidationResult.Reason.keys()[decision.reason]]))


func create_snapshots(observer: int) -> Array[StaffPlanDecisionSnapshot]:
	var result: Array[StaffPlanDecisionSnapshot] = []
	var ids := _decisions.keys()
	ids.sort()
	for id in ids:
		if observer == 0 or observer == id:
			result.append(_decisions[id].duplicate_value())
	return result


func _resolve(world: SimulationWorld, command: StaffPlanApprovalCommand) -> StaffCourseOfAction:
	var plans := StaffPlanGenerator.new().generate(world.create_faction_snapshot(command.issuer_id), command.issuer_id, command.request)
	if plans == null:
		return null
	for plan in plans.plans:
		if plan.profile_id == command.profile_id and plan.fingerprint() == command.expected_fingerprint:
			return plan
	return null


func _rejected(reason: CommandValidationResult.Reason) -> CommandValidationResult:
	return CommandValidationResult.new(CommandValidationResult.Status.REJECTED, reason)
