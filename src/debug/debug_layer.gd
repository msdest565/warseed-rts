class_name DebugLayer
extends CanvasLayer

@onready var status_label: Label = $Panel/Status


func update_status(
	snapshot: WorldSnapshot,
	selected_entity_id: int,
	queue_size: int,
	command_status: String,
	timing: HostTickTimingSnapshot,
	true_snapshot: WorldSnapshot = null
) -> void:
	if snapshot == null:
		status_label.text = "Initializing simulation..."
		return
	var lines: PackedStringArray = [
		"WARSEED / AUTHORITATIVE COMBAT SLICE",
		"Tick: %d    Queue: %d" % [snapshot.tick, queue_size],
		"Selected: %s" % ("E%d" % selected_entity_id if selected_entity_id != 0 else "None"),
		"Command: %s" % command_status,
		"Controls: Alt+LMB Single | RMB Move/Attack | X Stop | R Return | Y Stay | J Join | M Manual",
	]
	if true_snapshot != null:
		var visible_hostiles := 0
		var stale_contacts := 0
		for unit in snapshot.units:
			if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
				continue
			if unit.is_visible_to_local_player:
				visible_hostiles += 1
			else:
				stale_contacts += 1
		var hidden_true_units := maxi(0, true_snapshot.units.size() - snapshot.units.size())
		lines.append("Knowledge: %d visible / %d stale / %d hidden true-state units" % [visible_hostiles, stale_contacts, hidden_true_units])
	if not snapshot.tasks.is_empty():
		var task := snapshot.tasks[0]
		lines.append("Task T%d / A%d: %s | %d/%d participants" % [
			task.task_id,
			task.agent_id,
			TaskState.Lifecycle.keys()[task.lifecycle],
			task.participant_entity_ids.size(),
			task.original_participant_entity_ids.size(),
		])
		if task.lifecycle == TaskState.Lifecycle.BLOCKED:
			lines.append("Blocked: %s | %s" % [TaskState.BlockedReason.keys()[task.blocked_reason], task.blocked_detail])
	var local_faction := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var enemy_faction := snapshot.get_faction(SimulationWorld.ENEMY_PLAYER_ID)
	if local_faction != null:
		lines.append("Economy: %d ore | H harvest selected harvester | P factory scout" % local_faction.ore)
	if local_faction != null and enemy_faction != null:
		lines.append("Victory: local %s | enemy %s" % ["WON" if local_faction.victorious else "ACTIVE", "DEFEATED" if enemy_faction.defeated else "ACTIVE"])
	var metrics := snapshot.metrics
	if metrics != null:
		lines.append("Commands: %d submitted / %d accepted / %d rejected / %d applied" % [
			metrics.commands_submitted_total,
			metrics.get_command_count(CommandValidationResult.Status.ACCEPTED),
			metrics.get_command_count(CommandValidationResult.Status.REJECTED),
			metrics.commands_applied_total,
		])
		lines.append("Paths: %d requested / %d succeeded / %d failed" % [
			metrics.path_requests_total,
			metrics.path_succeeded_total,
			metrics.path_failed_total,
		])
		lines.append("Events: %d total / %d damage / %d destroyed / %d lost" % [
			metrics.events_emitted_total,
			metrics.get_event_count(SimulationEvent.Kind.DAMAGE_APPLIED),
			metrics.get_event_count(SimulationEvent.Kind.UNIT_DESTROYED),
			metrics.get_event_count(SimulationEvent.Kind.TARGET_LOST),
		])
	if timing != null:
		lines.append("Tick wall: %.3f ms last / %.3f ms avg / %.3f ms max" % [
			timing.last_usec / 1000.0,
			timing.average_usec / 1000.0,
			timing.max_usec / 1000.0,
		])
	if selected_entity_id != 0:
		var unit := snapshot.get_unit(selected_entity_id)
		if unit != null:
			lines.append("Unit: %s" % unit.definition_id)
			lines.append("Position: (%.1f, %.1f)" % [unit.position.x, unit.position.y])
			lines.append("Target: (%.1f, %.1f)" % [unit.move_target.x, unit.move_target.y])
			var state := "RECOVERING" if unit.is_recovering else ("MOVING" if unit.is_moving else "IDLE")
			lines.append("State: %s" % state)
			lines.append("Control: %s / A%d / T%d%s" % [
				UnitState.ControlState.keys()[unit.control_state],
				unit.assigned_agent_id,
				unit.assigned_task_id,
				" / REJOIN F%d:S%d" % [unit.rejoin_formation_id, unit.rejoin_slot_id] if unit.rejoin_pending else "",
			])
			lines.append("Combat: F%d / HP %.0f/%.0f / Target E%d" % [
				unit.faction_id,
				unit.health,
				unit.max_health,
				unit.attack_target_entity_id,
			])
			lines.append("Weapon: range %.0f / power %.0f / armor %.0f / %.2f shots/s / cooldown %d" % [
				unit.attack_range,
				unit.attack_damage,
				unit.armor,
				unit.attacks_per_second,
				unit.attack_cooldown_remaining_ticks,
			])
			if unit.formation_id != 0:
				var formation := snapshot.get_formation(unit.formation_id)
				var mode: String = FormationState.MovementMode.keys()[formation.mode] if formation != null else "UNKNOWN"
				lines.append("Formation: F%d / Slot %d / %s / %s-%s" % [
					unit.formation_id,
					unit.formation_slot_id,
					mode,
					FormationState.OrderKind.keys()[formation.order_kind],
					FormationState.EngagementState.keys()[formation.engagement_state],
				])
		lines.append("Projectiles: %d" % snapshot.projectiles.size())
	status_label.text = "\n".join(lines)
