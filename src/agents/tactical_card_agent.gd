class_name TacticalCardAgent
extends RefCounted


func propose(snapshot: WorldSnapshot, battle: BattleDefinition) -> Array[TacticalAbilityCommand]:
	var commands: Array[TacticalAbilityCommand] = []
	if snapshot == null or snapshot.is_true_state:
		return commands
	var considered: Dictionary = {}
	for decision in TacticalActionProjector.new().project(snapshot, battle):
		var card := snapshot.get_unit_card(decision.unit_card_id)
		if considered.has(card.definition_id) or decision.reason != CommandValidationResult.Reason.NONE:
			continue
		if card.control_state != UnitCardState.ControlState.AGENT_ASSIGNED or card.assigned_agent_id == 0 or card.assigned_task_id == 0:
			continue
		var task := snapshot.get_task(card.assigned_task_id)
		if task == null or task.agent_id != card.assigned_agent_id or task.lifecycle not in [TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING]:
			continue
		var moving := false
		for id in card.active_member_entity_ids:
			var unit := snapshot.get_unit(id)
			moving = moving or unit != null and unit.is_moving
		if moving:
			continue
		var command := TacticalActionProjector.command_for(decision, 0, snapshot.observer_faction_id, snapshot.tick, GameCommand.IssuerKind.AGENT)
		command.agent_id = card.assigned_agent_id
		command.task_id = card.assigned_task_id
		commands.append(command)
		considered[card.definition_id] = true
	return commands
