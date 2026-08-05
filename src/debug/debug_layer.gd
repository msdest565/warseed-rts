class_name DebugLayer
extends CanvasLayer

@onready var status_label: Label = $Panel/Status


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func update_status(
	snapshot: WorldSnapshot,
	selected_entity_id: int,
	queue_size: int,
	command_status: String,
	timing: HostTickTimingSnapshot,
	true_snapshot: WorldSnapshot = null,
	enemy_phase: String = "",
	enemy_difficulty: String = "",
	enemy_decision: String = "",
	industrial_authorization: AgentPolicy.Authorization = AgentPolicy.Authorization.ASSISTED,
	battlefield_authorization: AgentPolicy.Authorization = AgentPolicy.Authorization.ASSISTED
) -> void:
	if snapshot == null:
		status_label.text = GameText.t(&"DEBUG_INITIALIZING")
		return
	var selected_unit := snapshot.get_unit(selected_entity_id) if selected_entity_id != 0 else null
	var lines: PackedStringArray = [
		GameText.t(&"DEBUG_TITLE"),
		GameText.t(&"DEBUG_TICK") % [snapshot.tick, queue_size],
		GameText.t(&"DEBUG_SELECTED") % ("E%d" % selected_entity_id if selected_entity_id != 0 else GameText.t(&"DEBUG_NONE")),
		GameText.t(&"DEBUG_COMMAND") % command_status,
		GameText.t(&"DEBUG_CONTROLS"),
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
		lines.append(GameText.t(&"DEBUG_KNOWLEDGE") % [visible_hostiles, stale_contacts, hidden_true_units])
	if not snapshot.tasks.is_empty():
		var task := snapshot.tasks[-1]
		lines.append(GameText.t(&"DEBUG_TASK") % [
			task.task_id,
			GameText.enum_name("TASK_LIFECYCLE", TaskState.Lifecycle.keys()[task.lifecycle]),
			task.participant_entity_ids.size(),
			task.original_participant_entity_ids.size(),
		])
	var local_faction := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var enemy_faction := snapshot.get_faction(SimulationWorld.ENEMY_PLAYER_ID)
	if local_faction != null:
		lines.append(GameText.t(&"DEBUG_ECONOMY") % [local_faction.ore, selected_unit.cargo_ore if selected_unit != null else 0])
	if local_faction != null and enemy_faction != null:
		lines.append(GameText.t(&"DEBUG_VICTORY") % [
			GameText.faction_name(local_faction.faction_id),
			GameText.t(&"STATE_WON") if local_faction.victorious else GameText.t(&"STATE_ACTIVE"),
			GameText.faction_name(enemy_faction.faction_id),
			GameText.t(&"STATE_DEFEATED") if enemy_faction.defeated else GameText.t(&"STATE_ACTIVE"),
		])
	if not enemy_phase.is_empty():
		lines.append(GameText.t(&"DEBUG_ENEMY_PHASE") % GameText.enum_name("ENEMY_PHASE", enemy_phase))
	if not enemy_difficulty.is_empty():
		lines.append(GameText.t(&"DEBUG_ENEMY_AI") % [GameText.enum_name("AI_DIFFICULTY", enemy_difficulty), enemy_decision])
	lines.append(GameText.t(&"DEBUG_FRIENDLY_AI") % [
		GameText.enum_name("AI_AUTH", AgentPolicy.Authorization.keys()[industrial_authorization]),
		GameText.enum_name("AI_AUTH", AgentPolicy.Authorization.keys()[battlefield_authorization]),
	])
	var metrics := snapshot.metrics
	if metrics != null:
		lines.append(GameText.t(&"DEBUG_COMMANDS") % [
			metrics.commands_submitted_total,
			metrics.get_command_count(CommandValidationResult.Status.ACCEPTED),
			metrics.get_command_count(CommandValidationResult.Status.REJECTED),
			metrics.commands_applied_total,
		])
		lines.append(GameText.t(&"DEBUG_PATHS") % [metrics.path_requests_total, metrics.path_succeeded_total, metrics.path_failed_total])
		lines.append(GameText.t(&"DEBUG_EVENTS") % [
			metrics.events_emitted_total,
			metrics.get_event_count(SimulationEvent.Kind.DAMAGE_APPLIED),
			metrics.get_event_count(SimulationEvent.Kind.UNIT_DESTROYED) + metrics.get_event_count(SimulationEvent.Kind.BUILDING_DESTROYED),
		])
	if timing != null:
		lines.append(GameText.t(&"DEBUG_TICK_WALL") % [timing.last_usec / 1000.0, timing.average_usec / 1000.0, timing.max_usec / 1000.0])
	if selected_unit != null:
		lines.append(GameText.t(&"DEBUG_UNIT") % [GameText.unit_name(selected_unit.definition_id), selected_unit.position.x, selected_unit.position.y])
		lines.append(GameText.t(&"DEBUG_UNIT_STATE") % [
			GameText.enum_name("CONTROL", UnitState.ControlState.keys()[selected_unit.control_state]),
			selected_unit.health,
			selected_unit.max_health,
			selected_unit.attack_target_entity_id,
		])
	status_label.text = "\n".join(lines)
