class_name GameplayObservabilityReport
extends RefCounted

const FORMAT_VERSION := 1
const EVIDENCE_LEVEL := "SIMULATED"

var scenario_id: StringName
var enemy_plan_id: StringName
var strategy_id: StringName
var seed: int
var observer_faction_id: int
var max_ticks: int
var illegal_input_reason := ""

var _started_tick := 0
var _latest_tick := 0
var _commands: Array[Dictionary] = []
var _first_high_level_order: Dictionary = {}
var _player_corrections: Array[Dictionary] = []
var _supply_commitments: Dictionary = {}
var _tasks: Dictionary = {}
var _task_transitions: Array[Dictionary] = []
var _cards: Dictionary = {}
var _control_sessions: Array[Dictionary] = []
var _active_control_sessions: Dictionary = {}
var _turning_points: Array[Dictionary] = []
var _entity_card_ids: Dictionary = {}
var _entity_faction_ids: Dictionary = {}
var _last_damage_source_by_target: Dictionary = {}
var _outcome: Dictionary = {}
var _exceptions: Dictionary = {}
var _active_exception_ids: Dictionary = {}
var _exception_transitions: Array[Dictionary] = []
var _exception_action_count: int = 0


func _init(
	new_scenario_id: StringName = &"grey_ridge",
	new_enemy_plan_id: StringName = &"",
	new_strategy_id: StringName = &"",
	new_seed: int = 0,
	new_observer_faction_id: int = SimulationWorld.LOCAL_PLAYER_ID,
	new_max_ticks: int = 0
) -> void:
	scenario_id = new_scenario_id
	enemy_plan_id = new_enemy_plan_id
	strategy_id = new_strategy_id
	seed = new_seed
	observer_faction_id = new_observer_faction_id
	max_ticks = new_max_ticks


func start(snapshot: WorldSnapshot) -> bool:
	if not _accepts_snapshot(snapshot):
		return false
	_started_tick = snapshot.tick
	_latest_tick = snapshot.tick
	_observe_cards(snapshot)
	_observe_tasks(snapshot)
	_observe_outcome(snapshot)
	return true


func record_command(command: GameCommand, validation: CommandValidationResult, descriptor: Dictionary) -> void:
	if command == null or validation == null:
		return
	var accepted := validation.is_accepted()
	var actor_id := str(descriptor.get("actor_id", descriptor.get("subject", "")))
	var card_id := str(descriptor.get("card_id", ""))
	var task_id := int(descriptor.get("task_id", 0))
	var reason_key := str(descriptor.get("reason_key", "strategy_intent"))
	var record := {
		"tick": command.issued_tick,
		"command_id": command.command_id,
		"command_type": command.get_class(),
		"actor_id": actor_id,
		"card_id": card_id,
		"task_id": task_id,
		"reason_key": reason_key,
		"status": "accepted" if accepted else "rejected",
		"rejection_reason": "" if accepted else CommandValidationResult.Reason.keys()[validation.reason],
	}
	_commands.append(record)
	if not accepted:
		return
	var category := str(descriptor.get("category", ""))
	var action := str(descriptor.get("action", ""))
	if _first_high_level_order.is_empty() and category == "commander" and action in ["objective", "intent"]:
		_first_high_level_order = record.duplicate(true)
		_append_turning_point(command.issued_tick, actor_id, card_id, task_id, "first_high_level_order", "command_accepted", action)
	if bool(descriptor.get("is_correction", false)):
		var correction := record.duplicate(true)
		correction["correction_reason"] = str(descriptor.get("correction_reason", reason_key))
		_player_corrections.append(correction)
		_append_turning_point(command.issued_tick, actor_id, card_id, task_id, "player_correction", "command_accepted", correction["correction_reason"])
	if action == "card_control" and int(descriptor.get("control_action", -1)) == UnitCardControlCommand.Action.RETURN_TO_COMMANDER and _active_control_sessions.has(card_id):
		(_active_control_sessions[card_id] as Dictionary)["return_started_tick"] = command.issued_tick
	if descriptor.has("exception_id"):
		record_exception_action(StringName(descriptor["exception_id"]), str(descriptor.get("exception_action", action)), command.issued_tick, accepted)


func observe(snapshot: WorldSnapshot, new_events: Array[SimulationEvent] = []) -> bool:
	if not _accepts_snapshot(snapshot):
		return false
	_latest_tick = maxi(_latest_tick, snapshot.tick)
	_observe_cards(snapshot)
	_observe_tasks(snapshot)
	_observe_events(new_events)
	_observe_outcome(snapshot)
	return true


func finish(snapshot: WorldSnapshot) -> bool:
	if not observe(snapshot):
		return false
	var card_ids := _active_control_sessions.keys()
	card_ids.sort_custom(func(left: String, right: String) -> bool: return left < right)
	for card_id_variant in card_ids:
		_close_control_session(String(card_id_variant), snapshot.tick, "not_returned_at_battle_end")
	return true


func observe_command_situation(command_situation: CommandSituationSnapshot) -> bool:
	if command_situation == null:
		return false
	if command_situation.observer_faction_id != observer_faction_id:
		illegal_input_reason = "WRONG_COMMAND_SITUATION_FACTION"
		return false
	var current_ids: Dictionary = {}
	for exception in command_situation.exceptions:
		var exception_id := String(exception.exception_id)
		current_ids[exception_id] = true
		var record := _exceptions.get(exception_id, {}) as Dictionary
		if record.is_empty():
			record = exception.to_dictionary()
			record["first_seen_tick"] = command_situation.source_tick
			record["last_seen_tick"] = command_situation.source_tick
			record["opened_count"] = 1
			record["resolved_count"] = 0
			_exceptions[exception_id] = record
			_record_exception_transition(exception, "opened", command_situation.source_tick)
		elif not _active_exception_ids.has(exception_id):
			record["opened_count"] = int(record["opened_count"]) + 1
			record["last_seen_tick"] = command_situation.source_tick
			_record_exception_transition(exception, "reopened", command_situation.source_tick)
		else:
			record["last_seen_tick"] = command_situation.source_tick
	var previous_ids := _active_exception_ids.keys()
	previous_ids.sort()
	for exception_id_variant in previous_ids:
		var exception_id := String(exception_id_variant)
		if current_ids.has(exception_id):
			continue
		var record := _exceptions[exception_id] as Dictionary
		record["resolved_count"] = int(record["resolved_count"]) + 1
		_exception_transitions.append({
			"tick": command_situation.source_tick,
			"exception_id": exception_id,
			"kind": int(record["kind"]),
			"transition": "resolved",
		})
		_append_turning_point(command_situation.source_tick, "player_staff", String(record["unit_card_id"]), int(record["task_id"]), "exception_resolved", "command_situation", exception_id)
	_active_exception_ids = current_ids
	_latest_tick = maxi(_latest_tick, command_situation.source_tick)
	return true


func record_exception_action(exception_id: StringName, action: String, tick: int, accepted: bool = true) -> void:
	_exception_action_count += 1
	_exception_transitions.append({
		"tick": tick,
		"exception_id": String(exception_id),
		"kind": -1,
		"transition": "action",
		"action": action,
		"accepted": accepted,
	})
	_append_turning_point(tick, "player", "", 0, "exception_action", "command_situation", "%s:%s:%s" % [exception_id, action, accepted])


func create_report() -> Dictionary:
	var report := _report_without_fingerprint()
	report["fingerprint"] = canonical_json(report, "").sha256_text()
	return report


func fingerprint() -> String:
	return String(create_report()["fingerprint"])


func normalized_json(indent: String = "\t") -> String:
	return canonical_json(create_report(), indent)


func save_to_path(path: String) -> bool:
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(normalized_json())
	file.close()
	return true


static func canonical_json(value: Variant, indent: String = "") -> String:
	return JSON.stringify(value, indent, true, true)


func _report_without_fingerprint() -> Dictionary:
	var accepted_commands := 0
	for command in _commands:
		if command["status"] == "accepted":
			accepted_commands += 1
	var task_counts := {
		"created": 0,
		"replaced": 0,
		"blocked": 0,
		"retreated": 0,
		"completed": 0,
		"failed": 0,
		"cancelled": 0,
	}
	var task_records: Array[Dictionary] = []
	var task_ids := _tasks.keys()
	task_ids.sort()
	for task_id_variant in task_ids:
		var task := (_tasks[task_id_variant] as Dictionary).duplicate(true)
		task_records.append(task)
		task_counts["created"] = int(task_counts["created"]) + 1
		if bool(task.get("was_replaced", false)):
			task_counts["replaced"] = int(task_counts["replaced"]) + 1
		if int(task.get("blocked_count", 0)) > 0:
			task_counts["blocked"] = int(task_counts["blocked"]) + 1
		if bool(task.get("entered_retreat", false)):
			task_counts["retreated"] = int(task_counts["retreated"]) + 1
		match str(task.get("final_lifecycle", "")):
			"COMPLETED": task_counts["completed"] = int(task_counts["completed"]) + 1
			"FAILED": task_counts["failed"] = int(task_counts["failed"]) + 1
			"CANCELLED": task_counts["cancelled"] = int(task_counts["cancelled"]) + 1
	var card_records: Array[Dictionary] = []
	var card_ids := _cards.keys()
	card_ids.sort_custom(func(left: String, right: String) -> bool: return left < right)
	for card_id_variant in card_ids:
		card_records.append((_cards[card_id_variant] as Dictionary).duplicate(true))
	var supply_records: Array[Dictionary] = []
	var supply_keys := _supply_commitments.keys()
	supply_keys.sort_custom(func(left: String, right: String) -> bool: return left < right)
	var total_supply := 0
	for key_variant in supply_keys:
		var supply := (_supply_commitments[key_variant] as Dictionary).duplicate(true)
		supply_records.append(supply)
		total_supply += int(supply["total_supply"])
	var exception_records: Array[Dictionary] = []
	var exception_ids := _exceptions.keys()
	exception_ids.sort()
	var opened_exceptions := 0
	var resolved_exceptions := 0
	for exception_id_variant in exception_ids:
		var exception_record := (_exceptions[exception_id_variant] as Dictionary).duplicate(true)
		exception_records.append(exception_record)
		opened_exceptions += int(exception_record["opened_count"])
		resolved_exceptions += int(exception_record["resolved_count"])
	return {
		"format_version": FORMAT_VERSION,
		"schema_id": "warseed.gameplay_baseline.case.v1",
		"evidence_level": EVIDENCE_LEVEL,
		"scenario_id": String(scenario_id),
		"enemy_plan_id": String(enemy_plan_id),
		"strategy_id": String(strategy_id),
		"seed": seed,
		"observer_faction_id": observer_faction_id,
		"tick_rate_hz": roundi(1.0 / SimulationWorld.TICK_SECONDS),
		"started_tick": _started_tick,
		"final_tick": _latest_tick,
		"max_ticks": max_ticks,
		"legal_observation_only": illegal_input_reason.is_empty(),
		"illegal_input_reason": illegal_input_reason,
		"first_high_level_order": _first_high_level_order.duplicate(true),
		"command_summary": {
			"accepted": accepted_commands,
			"rejected": _commands.size() - accepted_commands,
			"player_corrections": _player_corrections.size(),
		},
		"commands": _commands.duplicate(true),
		"player_corrections": _player_corrections.duplicate(true),
		"supply_summary": {
			"total_committed": total_supply,
			"commitment_count": supply_records.reduce(func(total: int, item: Dictionary) -> int: return total + int(item["count"]), 0),
		},
		"supply_commitments": supply_records,
		"task_summary": task_counts,
		"tasks": task_records,
		"task_transitions": _task_transitions.duplicate(true),
		"control_summary": {
			"takeovers": _control_sessions.size(),
			"returned": _control_sessions.filter(func(item: Dictionary) -> bool: return item["return_result"] == "returned_to_agent").size(),
		},
		"control_sessions": _control_sessions.duplicate(true),
		"exception_summary": {
			"unique": exception_records.size(),
			"opened": opened_exceptions,
			"resolved": resolved_exceptions,
			"active": _active_exception_ids.size(),
			"player_actions": _exception_action_count,
		},
		"exceptions": exception_records,
		"exception_transitions": _exception_transitions.duplicate(true),
		"cards": card_records,
		"outcome": _outcome.duplicate(true),
		"causal_turning_points": _turning_points.duplicate(true),
	}


func _accepts_snapshot(snapshot: WorldSnapshot) -> bool:
	if snapshot == null:
		illegal_input_reason = "NULL_SNAPSHOT"
		return false
	if snapshot.is_true_state:
		illegal_input_reason = "TRUE_STATE_FORBIDDEN"
		return false
	if snapshot.observer_faction_id != observer_faction_id:
		illegal_input_reason = "WRONG_OBSERVER_FACTION"
		return false
	return true


func _observe_cards(snapshot: WorldSnapshot) -> void:
	for card_snapshot in snapshot.unit_cards:
		if card_snapshot.faction_id != observer_faction_id:
			continue
		var card_id := String(card_snapshot.definition_id)
		var card := _cards.get(card_id, {}) as Dictionary
		if card.is_empty():
			card = {
				"card_id": card_id,
				"authorized_strength": card_snapshot.authorized_strength,
				"initial_strength": card_snapshot.current_strength,
				"peak_strength": card_snapshot.current_strength,
				"final_strength": card_snapshot.current_strength,
				"losses": 0,
				"damage_dealt": 0.0,
				"damage_taken": 0.0,
				"kills": 0,
				"tasks_completed": 0,
				"tasks_blocked": 0,
				"supply_spent": 0,
				"tactical_started": 0,
				"tactical_completed": 0,
				"tactical_interrupted": 0,
				"contacts_identified": 0,
				"routes_opened": 0,
				"suppression_applied": 0.0,
				"ammunition_restored": 0,
				"organization_restored": 0.0,
				"final_deployment_state": UnitCardState.DeploymentState.keys()[card_snapshot.deployment_state],
				"final_control_state": UnitCardState.ControlState.keys()[card_snapshot.control_state],
			}
			_cards[card_id] = card
		card["peak_strength"] = maxi(int(card["peak_strength"]), card_snapshot.current_strength)
		card["final_strength"] = card_snapshot.current_strength
		card["final_deployment_state"] = UnitCardState.DeploymentState.keys()[card_snapshot.deployment_state]
		var previous_control := String(card["final_control_state"])
		var next_control: String = UnitCardState.ControlState.keys()[card_snapshot.control_state]
		card["final_control_state"] = next_control
		for entity_id in card_snapshot.member_entity_ids:
			_entity_card_ids[entity_id] = card_id
			_entity_faction_ids[entity_id] = card_snapshot.faction_id
		_observe_card_control(card_id, previous_control, next_control, snapshot.tick)
	for unit in snapshot.units:
		_entity_faction_ids[unit.entity_id] = unit.faction_id
		if unit.faction_id == observer_faction_id and not unit.unit_card_id.is_empty():
			_entity_card_ids[unit.entity_id] = String(unit.unit_card_id)
	for building in snapshot.buildings:
		_entity_faction_ids[building.entity_id] = building.faction_id


func _observe_card_control(card_id: String, previous_control: String, next_control: String, tick: int) -> void:
	var manual_states := ["PLAYER_OVERRIDDEN", "PLAYER_CONTROLLED"]
	if next_control in manual_states and not _active_control_sessions.has(card_id):
		_active_control_sessions[card_id] = {
			"card_id": card_id,
			"takeover_tick": tick,
			"return_started_tick": -1,
			"returned_tick": -1,
			"duration_ticks": 0,
			"return_result": "active",
		}
		_append_turning_point(tick, "player", card_id, 0, "unit_card_takeover", "card_snapshot", next_control)
	elif next_control == "RETURNING" and _active_control_sessions.has(card_id):
		(_active_control_sessions[card_id] as Dictionary)["return_started_tick"] = tick
		_append_turning_point(tick, "player", card_id, 0, "unit_card_return_started", "card_snapshot", next_control)
	elif _active_control_sessions.has(card_id) and previous_control in manual_states + ["RETURNING"] and next_control in ["AGENT_ASSIGNED", "UNASSIGNED"]:
		_close_control_session(card_id, tick, "returned_to_agent" if next_control == "AGENT_ASSIGNED" else "returned_unassigned")


func _close_control_session(card_id: String, tick: int, result: String) -> void:
	if not _active_control_sessions.has(card_id):
		return
	var session := (_active_control_sessions[card_id] as Dictionary).duplicate(true)
	session["returned_tick"] = tick if result != "not_returned_at_battle_end" else -1
	session["duration_ticks"] = maxi(0, tick - int(session["takeover_tick"]))
	session["return_result"] = result
	_control_sessions.append(session)
	_active_control_sessions.erase(card_id)
	_append_turning_point(tick, "player", card_id, 0, "unit_card_return_result", "card_snapshot", result)


func _observe_tasks(snapshot: WorldSnapshot) -> void:
	for task_snapshot in snapshot.tasks:
		if task_snapshot.faction_id != observer_faction_id:
			continue
		var task_id := task_snapshot.task_id
		var lifecycle: String = TaskState.Lifecycle.keys()[task_snapshot.lifecycle]
		var phase: String = TaskState.Phase.keys()[task_snapshot.phase]
		var blocked_reason: String = TaskState.BlockedReason.keys()[task_snapshot.blocked_reason]
		var task := _tasks.get(task_id, {}) as Dictionary
		if task.is_empty():
			task = {
				"task_id": task_id,
				"agent_id": task_snapshot.agent_id,
				"card_id": String(task_snapshot.unit_card_id),
				"kind": TaskState.Kind.keys()[task_snapshot.kind],
				"accepted_tick": task_snapshot.accepted_tick,
				"first_lifecycle": lifecycle,
				"first_phase": phase,
				"final_lifecycle": lifecycle,
				"final_phase": phase,
				"blocked_count": 0,
				"entered_retreat": phase == "RETREATING",
				"was_replaced": false,
				"last_reason": task_snapshot.last_detail,
			}
			_tasks[task_id] = task
			_record_task_transition(task_snapshot, "task_created", lifecycle, phase, blocked_reason)
			continue
		var previous_lifecycle := String(task["final_lifecycle"])
		var previous_phase := String(task["final_phase"])
		if lifecycle != previous_lifecycle or phase != previous_phase:
			task["final_lifecycle"] = lifecycle
			task["final_phase"] = phase
			if lifecycle == "BLOCKED" and previous_lifecycle != "BLOCKED":
				task["blocked_count"] = int(task["blocked_count"]) + 1
				_increment_card_metric(String(task["card_id"]), "tasks_blocked", 1)
			if phase == "RETREATING":
				task["entered_retreat"] = true
			if lifecycle == "CANCELLED" and task_snapshot.last_detail.to_lower().contains("replaced"):
				task["was_replaced"] = true
			if lifecycle == "COMPLETED" and previous_lifecycle != "COMPLETED":
				_increment_card_metric(String(task["card_id"]), "tasks_completed", 1)
			_record_task_transition(task_snapshot, "task_state_changed", lifecycle, phase, blocked_reason)
		task["last_reason"] = task_snapshot.last_detail


func _record_task_transition(task: TaskSnapshot, reason_key: String, lifecycle: String, phase: String, blocked_reason: String) -> void:
	var transition := {
		"tick": task.last_transition_tick,
		"actor_id": str(task.agent_id),
		"card_id": String(task.unit_card_id),
		"task_id": task.task_id,
		"reason_key": reason_key,
		"source_event": "task_snapshot",
		"result": "%s:%s" % [lifecycle, phase],
		"blocked_reason": blocked_reason,
		"detail": task.last_detail,
	}
	_task_transitions.append(transition)
	_turning_points.append(transition.duplicate(true))


func _observe_events(new_events: Array[SimulationEvent]) -> void:
	for event in new_events:
		var event_name: String = String(SimulationEvent.Kind.keys()[event.kind]).to_lower()
		var detail := _parse_detail(event.detail)
		match event.kind:
			SimulationEvent.Kind.TACTICAL_ACTION_STARTED, SimulationEvent.Kind.TACTICAL_ACTION_COMPLETED, SimulationEvent.Kind.TACTICAL_ACTION_INTERRUPTED:
				if event.entity_id != observer_faction_id or not _cards.has(str(detail.get("card", ""))):
					continue
				var metric := "tactical_started" if event.kind == SimulationEvent.Kind.TACTICAL_ACTION_STARTED else ("tactical_completed" if event.kind == SimulationEvent.Kind.TACTICAL_ACTION_COMPLETED else "tactical_interrupted")
				_increment_card_metric(str(detail["card"]), metric, 1)
				_append_turning_point(event.tick, str(observer_faction_id), str(detail["card"]), 0, event_name, event_name, str(detail.get("reason", "")))
			SimulationEvent.Kind.TACTICAL_IDENTIFIED:
				if int(detail.get("faction", 0)) == observer_faction_id:
					_increment_card_metric(str(detail.get("card", "")), "contacts_identified", 1)
			SimulationEvent.Kind.ENGINEERING_ROUTE_OPENED:
				if event.entity_id == observer_faction_id:
					_increment_card_metric(str(detail.get("engineer_card", "")), "routes_opened", 1)
			SimulationEvent.Kind.AMMUNITION_RESTORED:
				if event.entity_id == observer_faction_id:
					_increment_card_metric(str(detail.get("card", "")), "ammunition_restored", int(detail.get("rounds", 0)))
					_increment_card_metric(str(detail.get("card", "")), "organization_restored", float(detail.get("organization_restored", 0.0)))
			SimulationEvent.Kind.SUPPRESSION_APPLIED:
				_increment_card_metric(str(_entity_card_ids.get(event.entity_id, "")), "suppression_applied", event.applied_amount)
			SimulationEvent.Kind.SUPPLY_CHANGED:
				var delta := int(detail.get("delta", 0))
				if event.entity_id == observer_faction_id and delta < 0:
					_record_supply_commitment(event, -delta)
			SimulationEvent.Kind.DAMAGE_APPLIED:
				_observe_damage(event, detail)
			SimulationEvent.Kind.UNIT_DESTROYED:
				_observe_unit_destroyed(event)
			SimulationEvent.Kind.REGION_CONTROL_CHANGED:
				_append_turning_point(event.tick, str(detail.get("controller", "0")), "", 0, "region_control_changed", event_name, "%s:%s" % [detail.get("region", ""), detail.get("controller", "0")])
			SimulationEvent.Kind.BUILDING_DESTROYED:
				if _entity_faction_ids.has(event.entity_id):
					_append_turning_point(event.tick, str(event.entity_id), "", 0, "building_destroyed", event_name, str(event.entity_id))
			SimulationEvent.Kind.BATTLE_CONCLUDED:
				_append_turning_point(event.tick, str(observer_faction_id), "", 0, "battle_concluded", event_name, event.detail)


func _record_supply_commitment(event: SimulationEvent, amount: int) -> void:
	var detail := _parse_detail(event.detail)
	var category := str(detail.get("source", "other"))
	if category == "support":
		var kind := int(detail.get("support_kind", -1))
		if kind >= 0 and kind < SupportOrderCommand.SupportKind.size():
			category += "." + String(SupportOrderCommand.SupportKind.keys()[kind]).to_lower()
	var card_id := str(detail.get("card", ""))
	if not card_id.is_empty() and not _cards.has(card_id):
		return
	var record := _supply_commitments.get(category, {}) as Dictionary
	if record.is_empty():
		record = {"category": category, "count": 0, "total_supply": 0}
		_supply_commitments[category] = record
	record["count"] = int(record["count"]) + 1
	record["total_supply"] = int(record["total_supply"]) + amount
	_increment_card_metric(card_id, "supply_spent", amount)
	_append_turning_point(event.tick, str(observer_faction_id), card_id, 0, "supply_committed", "supply_changed", "%s:%d" % [category, amount])


func _observe_damage(event: SimulationEvent, detail: Dictionary) -> void:
	var target_id := int(detail.get("target", 0))
	var amount := float(detail.get("amount", 0.0))
	_last_damage_source_by_target[target_id] = event.entity_id
	var source_card := str(_entity_card_ids.get(event.entity_id, ""))
	var target_card := str(_entity_card_ids.get(target_id, ""))
	if not source_card.is_empty():
		_increment_card_metric(source_card, "damage_dealt", amount)
	if not target_card.is_empty():
		_increment_card_metric(target_card, "damage_taken", amount)


func _observe_unit_destroyed(event: SimulationEvent) -> void:
	var target_card := str(_entity_card_ids.get(event.entity_id, ""))
	var source_id := int(_last_damage_source_by_target.get(event.entity_id, 0))
	var observable_source_id := source_id if _entity_faction_ids.has(source_id) else 0
	if not target_card.is_empty():
		_increment_card_metric(target_card, "losses", 1)
		_append_turning_point(event.tick, str(observable_source_id), target_card, 0, "unit_card_loss", "unit_destroyed", str(event.entity_id))
	var source_card := str(_entity_card_ids.get(source_id, ""))
	if not source_card.is_empty():
		_increment_card_metric(source_card, "kills", 1)


func _observe_outcome(snapshot: WorldSnapshot) -> void:
	if snapshot.outcome == null:
		return
	var reason_ids: Array[String] = []
	for reason_id in snapshot.outcome.reason_objective_ids:
		reason_ids.append(String(reason_id))
	reason_ids.sort()
	_outcome = {
		"result": String(snapshot.outcome.result_key()),
		"grade": String(snapshot.outcome.grade_key()),
		"concluded_tick": snapshot.outcome.concluded_tick,
		"conclusion_group_id": String(snapshot.outcome.conclusion_group_id),
		"reason_objective_ids": reason_ids,
	}


func _increment_card_metric(card_id: String, metric: String, amount: Variant) -> void:
	if card_id.is_empty() or not _cards.has(card_id):
		return
	var card := _cards[card_id] as Dictionary
	card[metric] = card.get(metric, 0) + amount


func _append_turning_point(tick: int, actor_id: String, card_id: String, task_id: int, reason_key: String, source_event: String, result: String) -> void:
	_turning_points.append({
		"tick": tick,
		"actor_id": actor_id,
		"card_id": card_id,
		"task_id": task_id,
		"reason_key": reason_key,
		"source_event": source_event,
		"result": result,
	})


func _record_exception_transition(exception: CommandExceptionSnapshot, transition: String, tick: int) -> void:
	_exception_transitions.append({
		"tick": tick,
		"exception_id": String(exception.exception_id),
		"kind": exception.kind,
		"transition": transition,
	})
	_append_turning_point(tick, "player_staff", String(exception.unit_card_id), exception.task_id, "exception_%s" % transition, "command_situation", String(exception.exception_id))


func _parse_detail(value: String) -> Dictionary:
	var result: Dictionary = {}
	for part in value.split(";", false):
		var separator := part.find("=")
		if separator <= 0:
			continue
		result[part.left(separator)] = part.substr(separator + 1)
	return result
