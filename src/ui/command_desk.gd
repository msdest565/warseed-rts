class_name CommandDesk
extends HBoxContainer

signal decision_preview_changed(route: PackedVector2Array, target_position: Vector2, radius: float, label: String)
signal decision_preview_cleared

const ACTION_RECEIPT_HOLD_TICKS := 30
const DECISION_RESPONSE_TIMEOUT_TICKS := 15
const DECISION_HISTORY_LIMIT := 64

@onready var intent_title: Label = $Intent/Title
@onready var approval_hint: Label = $Intent/ApprovalHint
@onready var commander_label: Label = $Intent/Selectors/CommanderLabel
@onready var commander_selector: OptionButton = $Intent/Selectors/Commander
@onready var objective_label: Label = $Intent/Selectors/ObjectiveLabel
@onready var objective_selector: OptionButton = $Intent/Selectors/Objective
@onready var axis_label: Label = $Intent/Selectors/AxisLabel
@onready var axis_selector: OptionButton = $Intent/Selectors/Axis
@onready var risk_label: Label = $Intent/Selectors/RiskLabel
@onready var risk_selector: OptionButton = $Intent/Selectors/Risk
@onready var reserve_label: Label = $Intent/Selectors/ReserveLabel
@onready var reserve_selector: OptionButton = $Intent/Selectors/Reserve
@onready var apply_button: Button = $Intent/Actions/Apply
@onready var cancel_button: Button = $Intent/Actions/Cancel
@onready var intent_status: Label = $Intent/Status
@onready var exception_title: Label = $Exceptions/Header/Title
@onready var exception_count: Label = $Exceptions/Header/Count
@onready var guide_button: Button = $Exceptions/Header/Guide
@onready var exception_rows: VBoxContainer = $Exceptions/Scroll/Rows
@onready var separator: VSeparator = $Separator
@onready var guide_popup: PopupPanel = $GuidePopup
@onready var guide_text: RichTextLabel = $GuidePopup/Margin/Text
@onready var history_button: Button = $Exceptions/Footer/History
@onready var history_popup: PopupPanel = $HistoryPopup
@onready var history_text: RichTextLabel = $HistoryPopup/Margin/Text
@onready var decision_failure_dialog: AcceptDialog = $DecisionFailureDialog

var simulation_host: SimulationHost
var input_controller: InputController
var camera_controller: CameraController
var current_snapshot: WorldSnapshot
var current_command_situation: CommandSituationSnapshot
var acknowledged_exception_ids: Dictionary = {}
var _loaded_intent_id: StringName
var _compact: bool = false
var _action_receipt_exception_id: StringName
var _action_receipt_action: int = -1
var _action_receipt_result: CommandValidationResult
var _action_receipt_accepted: bool = false
var _action_receipt_expires_at_tick: int = -1
var _action_receipt_subject := ""
var _decision_history: Array[Dictionary] = []
var _pending_responses: Array[Dictionary] = []


func _ready() -> void:
	apply_button.pressed.connect(_submit_intent)
	cancel_button.pressed.connect(_cancel_intent)
	guide_button.pressed.connect(_show_guide)
	history_button.pressed.connect(_show_history)
	objective_selector.mouse_entered.connect(_preview_selected_objective)
	axis_selector.mouse_entered.connect(_preview_selected_axis)
	objective_selector.mouse_exited.connect(_clear_decision_preview)
	axis_selector.mouse_exited.connect(_clear_decision_preview)
	objective_selector.item_selected.connect(_preview_selected_objective.unbind(1))
	axis_selector.item_selected.connect(_preview_selected_axis.unbind(1))
	mouse_exited.connect(_clear_decision_preview)
	_populate_static_options()
	refresh_locale()


func configure(host: SimulationHost, input: InputController, camera: CameraController) -> void:
	simulation_host = host
	input_controller = input
	camera_controller = camera
	current_snapshot = null
	current_command_situation = null
	acknowledged_exception_ids.clear()
	_loaded_intent_id = &""
	reset_decision_session()
	_clear_action_receipt()
	refresh_locale()


func reset_decision_session() -> void:
	_decision_history.clear()
	_pending_responses.clear()
	_clear_decision_preview()
	_update_history_display()


func update_command_situation(snapshot: WorldSnapshot, command_situation: CommandSituationSnapshot) -> void:
	current_snapshot = snapshot
	current_command_situation = command_situation
	if snapshot == null or command_situation == null:
		return
	_check_pending_responses()
	_refresh_dynamic_options()
	_sync_selected_intent()
	_rebuild_exception_rows()
	_update_status()


func set_compact(compact: bool) -> void:
	_compact = compact
	$Intent.custom_minimum_size.x = 220.0 if compact else 360.0
	$Exceptions.custom_minimum_size.x = 200.0 if compact else 340.0
	$Intent/Selectors.columns = 2 if compact else 4
	for label in [commander_label, objective_label, axis_label, risk_label, reserve_label]:
		if label != null:
			label.visible = not compact
	for selector in [commander_selector, objective_selector, axis_selector, risk_selector, reserve_selector]:
		if selector != null:
			selector.custom_minimum_size.y = 32.0
			selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if commander_selector != null and commander_label != null:
		commander_selector.tooltip_text = commander_label.text
	if objective_selector != null and objective_label != null:
		objective_selector.tooltip_text = objective_label.text
	if axis_selector != null and axis_label != null:
		axis_selector.tooltip_text = axis_label.text
	if risk_selector != null and risk_label != null:
		risk_selector.tooltip_text = risk_label.text
	if reserve_selector != null and reserve_label != null:
		reserve_selector.tooltip_text = reserve_label.text
	_rebuild_exception_rows()


func refresh_locale() -> void:
	if intent_title == null:
		return
	intent_title.text = GameText.t(&"COMMAND_DESK_INTENT_TITLE")
	approval_hint.text = GameText.t(&"COMMAND_DESK_APPROVAL_HINT")
	commander_label.text = GameText.t(&"COMMAND_DESK_COMMANDER")
	objective_label.text = GameText.t(&"COMMAND_DESK_OBJECTIVE")
	axis_label.text = GameText.t(&"COMMAND_DESK_AXIS")
	risk_label.text = GameText.t(&"COMMAND_DESK_RISK")
	reserve_label.text = GameText.t(&"COMMAND_DESK_RESERVE")
	for label in [commander_label, objective_label, axis_label, risk_label, reserve_label]:
		label.visible = not _compact
	commander_selector.tooltip_text = commander_label.text
	objective_selector.tooltip_text = objective_label.text
	axis_selector.tooltip_text = axis_label.text
	risk_selector.tooltip_text = risk_label.text
	reserve_selector.tooltip_text = reserve_label.text
	apply_button.text = GameText.t(&"COMMAND_DESK_APPLY")
	cancel_button.text = GameText.t(&"COMMAND_DESK_CANCEL")
	exception_title.text = GameText.t(&"COMMAND_DESK_EXCEPTIONS")
	guide_button.tooltip_text = GameText.t(&"COMMAND_DESK_GUIDE_TOOLTIP")
	guide_text.text = GameText.t(&"COMMAND_DESK_GUIDE_BODY")
	if decision_failure_dialog != null:
		decision_failure_dialog.ok_button_text = GameText.t(&"DECISION_FAILURE_OK")
	_update_history_display()
	_populate_static_options()
	if current_snapshot != null:
		_refresh_dynamic_options()
		_rebuild_exception_rows()
		_update_status()


func _populate_static_options() -> void:
	if risk_selector == null or reserve_selector == null:
		return
	var selected_risk: Variant = _selected_metadata(risk_selector, CommanderState.Posture.BALANCED)
	risk_selector.clear()
	for posture in [CommanderState.Posture.CAUTIOUS, CommanderState.Posture.BALANCED, CommanderState.Posture.AGGRESSIVE, CommanderState.Posture.HOLD]:
		risk_selector.add_item(GameText.enum_name("COMMANDER_POSTURE", CommanderState.Posture.keys()[posture]))
		risk_selector.set_item_metadata(risk_selector.item_count - 1, posture)
	_select_metadata(risk_selector, selected_risk)
	var selected_reserve: Variant = _selected_metadata(reserve_selector, CommanderState.ReservePolicy.HOLD)
	reserve_selector.clear()
	for policy in range(CommanderState.ReservePolicy.size()):
		reserve_selector.add_item(GameText.t(StringName("COMMAND_RESERVE_%s" % CommanderState.ReservePolicy.keys()[policy])))
		reserve_selector.set_item_metadata(reserve_selector.item_count - 1, policy)
	_select_metadata(reserve_selector, selected_reserve)


func _refresh_dynamic_options() -> void:
	var selected_commander := StringName(_selected_metadata(commander_selector, &""))
	var selected_objective := StringName(_selected_metadata(objective_selector, &""))
	var selected_axis := StringName(_selected_metadata(axis_selector, &""))
	commander_selector.clear()
	var commanders: Array[CommanderSnapshot] = []
	for commander in current_snapshot.commanders:
		if commander.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			commanders.append(commander)
	commanders.sort_custom(func(left: CommanderSnapshot, right: CommanderSnapshot) -> bool: return String(left.definition_id) < String(right.definition_id))
	for commander in commanders:
		commander_selector.add_item(GameText.t(commander.display_name_key))
		commander_selector.set_item_metadata(commander_selector.item_count - 1, commander.definition_id)
	var regions: Array[StrategicRegionSnapshot] = current_snapshot.strategic_regions.duplicate()
	regions.sort_custom(func(left: StrategicRegionSnapshot, right: StrategicRegionSnapshot) -> bool: return String(left.region_id) < String(right.region_id))
	for selector in [objective_selector, axis_selector]:
		selector.clear()
		for region in regions:
			selector.add_item(GameText.t(region.display_name_key))
			selector.set_item_metadata(selector.item_count - 1, region.region_id)
	_select_metadata(commander_selector, selected_commander)
	_select_metadata(objective_selector, selected_objective)
	_select_metadata(axis_selector, selected_axis)
	apply_button.disabled = commander_selector.item_count == 0 or objective_selector.item_count == 0 or axis_selector.item_count == 0


func _sync_selected_intent() -> void:
	var commander_id := StringName(_selected_metadata(commander_selector, &""))
	var commander := current_snapshot.get_commander(commander_id)
	var intent_id := commander.active_intent_id if commander != null else &""
	if intent_id.is_empty() or intent_id == _loaded_intent_id:
		cancel_button.disabled = intent_id.is_empty()
		return
	_loaded_intent_id = intent_id
	_select_metadata(objective_selector, commander.intent_objective_region_id)
	_select_metadata(axis_selector, commander.intent_axis_region_id)
	_select_metadata(risk_selector, commander.posture)
	_select_metadata(reserve_selector, commander.intent_reserve_policy)
	cancel_button.disabled = false


func _submit_intent() -> void:
	if simulation_host == null:
		_record_and_show_unavailable(GameText.t(&"COMMAND_DESK_INTENT_TITLE"))
		return
	var command := simulation_host.create_high_level_intent_command(
		StringName(_selected_metadata(commander_selector, &"")),
		StringName(_selected_metadata(objective_selector, &"")),
		StringName(_selected_metadata(axis_selector, &"")),
		int(_selected_metadata(risk_selector, CommanderState.Posture.BALANCED)),
		int(_selected_metadata(reserve_selector, CommanderState.ReservePolicy.HOLD))
	)
	var result := simulation_host.submit_command(command)
	intent_status.text = GameText.t(&"COMMAND_DESK_INTENT_RESULT") % GameText.command_result(result)
	var subject := _commander_name(command.commander_id)
	var history_index := _record_decision(subject, GameText.t(&"COMMAND_DESK_APPLY"), GameText.command_result(result), result.is_accepted())
	if result.is_accepted():
		_watch_response({
			"kind": "intent", "commander_id": command.commander_id, "intent_id": command.intent_id,
			"objective_id": command.target_region_id, "axis_id": command.main_axis_region_id,
			"issued_tick": command.issued_tick, "history_index": history_index,
			"subject": subject, "action": GameText.t(&"COMMAND_DESK_APPLY"),
		})
	else:
		_show_decision_failure(subject, GameText.t(&"COMMAND_DESK_APPLY"), GameText.command_result(result))


func _cancel_intent() -> void:
	if simulation_host == null:
		_record_and_show_unavailable(GameText.t(&"COMMAND_DESK_CANCEL"))
		return
	var commander_id := StringName(_selected_metadata(commander_selector, &""))
	var command := simulation_host.create_cancel_high_level_intent_command(commander_id)
	var result := simulation_host.submit_command(command)
	intent_status.text = GameText.t(&"COMMAND_DESK_CANCEL_RESULT") % GameText.command_result(result)
	var subject := _commander_name(commander_id)
	var history_index := _record_decision(subject, GameText.t(&"COMMAND_DESK_CANCEL"), GameText.command_result(result), result.is_accepted())
	if result.is_accepted():
		_watch_response({
			"kind": "cancel_intent", "commander_id": commander_id,
			"issued_tick": command.issued_tick, "history_index": history_index,
			"subject": subject, "action": GameText.t(&"COMMAND_DESK_CANCEL"),
		})
	else:
		_show_decision_failure(subject, GameText.t(&"COMMAND_DESK_CANCEL"), GameText.command_result(result))


func _rebuild_exception_rows() -> void:
	if exception_rows == null:
		return
	for child in exception_rows.get_children():
		child.queue_free()
	if current_command_situation == null or current_command_situation.exceptions.is_empty():
		var clear_label := Label.new()
		clear_label.text = GameText.t(&"COMMAND_DESK_NO_EXCEPTIONS")
		clear_label.add_theme_color_override("font_color", Color(0.48, 0.75, 0.65))
		exception_rows.add_child(clear_label)
		return
	for exception in current_command_situation.exceptions:
		_add_exception_row(exception)


func _add_exception_row(exception: CommandExceptionSnapshot) -> void:
	var row := VBoxContainer.new()
	row.name = "Exception_%s" % String(exception.exception_id).validate_node_name()
	row.set_meta(&"exception_id", exception.exception_id)
	row.add_theme_constant_override("separation", 2)
	var summary := Button.new()
	summary.name = "Summary"
	summary.flat = true
	summary.alignment = HORIZONTAL_ALIGNMENT_LEFT
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.custom_minimum_size.y = 30.0
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.text = _exception_text(exception)
	summary.tooltip_text = _exception_tooltip(exception)
	summary.pressed.connect(_perform_exception_action.bind(exception.exception_id, CommandExceptionSnapshot.Action.FOCUS))
	summary.mouse_entered.connect(_preview_exception.bind(exception.exception_id))
	summary.mouse_exited.connect(_clear_decision_preview)
	if exception.severity == CommandExceptionSnapshot.Severity.CRITICAL:
		summary.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
	elif exception.severity == CommandExceptionSnapshot.Severity.WARNING:
		summary.add_theme_color_override("font_color", Color(1.0, 0.78, 0.36))
	row.add_child(summary)
	var context := Label.new()
	context.name = "Context"
	context.add_theme_font_size_override("font_size", 9)
	context.add_theme_color_override("font_color", Color(0.64, 0.72, 0.7))
	context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context.text = GameText.t(&"DECISION_ROW_CONTEXT") % [
		GameText.t(StringName("COMMAND_EXCEPTION_KIND_%s" % CommandExceptionSnapshot.Kind.keys()[exception.kind])),
		floori(exception.source_tick * SimulationWorld.TICK_SECONDS),
		exception.value_current,
		exception.value_limit,
	]
	row.add_child(context)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 4)
	var primary_action := exception.action_ids[0] if not exception.action_ids.is_empty() else CommandExceptionSnapshot.Action.KEEP_PLAN
	var action_button := Button.new()
	action_button.name = "Action"
	action_button.custom_minimum_size = Vector2(110.0 if not _compact else 82.0, 30.0)
	action_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_button.text = _action_text(primary_action)
	action_button.tooltip_text = _action_tooltip(primary_action, exception)
	action_button.disabled = _has_active_action_receipt() \
		and _action_receipt_accepted \
		and _action_receipt_exception_id == exception.exception_id \
		and _action_receipt_action == primary_action
	action_button.pressed.connect(_perform_exception_action.bind(exception.exception_id, primary_action))
	action_button.mouse_entered.connect(_preview_exception.bind(exception.exception_id))
	action_button.mouse_exited.connect(_clear_decision_preview)
	buttons.add_child(action_button)
	var acknowledge := Button.new()
	acknowledge.name = "Acknowledge"
	acknowledge.custom_minimum_size = Vector2(64.0, 30.0)
	acknowledge.text = GameText.t(&"COMMAND_EXCEPTION_ACK_SHORT")
	acknowledge.tooltip_text = GameText.t(&"COMMAND_EXCEPTION_ACK_TOOLTIP")
	acknowledge.disabled = acknowledged_exception_ids.has(exception.exception_id)
	acknowledge.pressed.connect(_acknowledge_exception.bind(exception.exception_id))
	buttons.add_child(acknowledge)
	row.add_child(buttons)
	exception_rows.add_child(row)


func _perform_exception_action(exception_id: StringName, action: int) -> void:
	if current_command_situation == null:
		_record_and_show_stale(exception_id)
		return
	var exception := current_command_situation.get_exception(exception_id)
	if exception == null:
		_record_and_show_stale(exception_id)
		return
	if simulation_host == null and action not in [CommandExceptionSnapshot.Action.FOCUS, CommandExceptionSnapshot.Action.KEEP_PLAN]:
		_record_and_show_unavailable(_action_subject(exception, action))
		return
	var action_name := String(CommandExceptionSnapshot.Action.keys()[action]).to_lower()
	var result: CommandValidationResult
	match action:
		CommandExceptionSnapshot.Action.FOCUS:
			_focus_exception(exception)
		CommandExceptionSnapshot.Action.RESUME_TASK:
			result = simulation_host.submit_command(simulation_host.create_task_control_command(exception.task_id, TaskControlCommand.Action.RESUME))
		CommandExceptionSnapshot.Action.CANCEL_TASK:
			result = simulation_host.submit_command(simulation_host.create_task_control_command(exception.task_id, TaskControlCommand.Action.CANCEL))
		CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER:
			result = simulation_host.submit_command(simulation_host.create_commander_posture_command(exception.commander_id, CommanderState.Posture.DISENGAGE))
		CommandExceptionSnapshot.Action.RETURN_TO_COMMANDER:
			result = simulation_host.submit_command(simulation_host.create_unit_card_control_command(
				exception.unit_card_id, UnitCardControlCommand.Action.RETURN_TO_COMMANDER
			))
		CommandExceptionSnapshot.Action.REQUEST_REINFORCEMENT:
			if input_controller != null:
				input_controller.select_unit_card(exception.unit_card_id)
			result = simulation_host.submit_command(simulation_host.create_support_order_command(
				SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"", &"", exception.unit_card_id
			))
		CommandExceptionSnapshot.Action.KEEP_PLAN:
			_acknowledge_exception(exception_id)
	var accepted := result == null or result.is_accepted()
	_set_action_receipt(exception_id, action, result, accepted)
	var subject := _action_subject(exception, action)
	var result_text := _action_result_text(action, result)
	var history_index := _record_decision(subject, _action_text(action), result_text, accepted)
	if result != null and not result.is_accepted():
		_show_decision_failure(subject, _action_text(action), result_text)
	elif result != null:
		_watch_exception_response(exception, action, history_index, subject)
	if simulation_host != null:
		simulation_host.record_playtest_ui_event("exception_action_%s" % action_name, exception_id)
		simulation_host.record_gameplay_exception_action(exception_id, action_name, accepted)
	if result != null:
		if result.is_accepted():
			acknowledged_exception_ids[exception_id] = true
	_rebuild_exception_rows()


func _focus_exception(exception: CommandExceptionSnapshot) -> void:
	if input_controller != null and not exception.unit_card_id.is_empty():
		input_controller.select_unit_card(exception.unit_card_id)
	if camera_controller != null and not exception.position.is_zero_approx():
		camera_controller.position = exception.position
		camera_controller.clamp_to_bounds()


func _acknowledge_exception(exception_id: StringName) -> void:
	acknowledged_exception_ids[exception_id] = true
	if simulation_host != null:
		simulation_host.record_playtest_ui_event("exception_acknowledged", exception_id)
	_rebuild_exception_rows()


func _update_status() -> void:
	exception_count.text = str(current_command_situation.exceptions.size()) if current_command_situation != null else "0"
	if _has_active_action_receipt():
		_show_action_receipt()
		return
	_clear_action_receipt()
	var commander_id := StringName(_selected_metadata(commander_selector, &""))
	var commander := current_snapshot.get_commander(commander_id) if current_snapshot != null else null
	if commander == null or commander.active_intent_id.is_empty():
		intent_status.text = GameText.t(&"COMMAND_DESK_NO_INTENT")
		cancel_button.disabled = true
	else:
		var objective := current_snapshot.get_strategic_region(commander.intent_objective_region_id)
		var axis := current_snapshot.get_strategic_region(commander.intent_axis_region_id)
		intent_status.text = GameText.t(&"COMMAND_DESK_ACTIVE_INTENT") % [
			GameText.t(objective.display_name_key) if objective != null else String(commander.intent_objective_region_id),
			GameText.t(axis.display_name_key) if axis != null else String(commander.intent_axis_region_id),
		]
		cancel_button.disabled = false


func _set_action_receipt(
	exception_id: StringName,
	action: int,
	result: CommandValidationResult,
	accepted: bool
) -> void:
	_action_receipt_exception_id = exception_id
	_action_receipt_action = action
	_action_receipt_result = result
	_action_receipt_accepted = accepted
	var exception := current_command_situation.get_exception(exception_id) if current_command_situation != null else null
	_action_receipt_subject = _action_subject(exception, action)
	_action_receipt_expires_at_tick = (current_snapshot.tick if current_snapshot != null else 0) + ACTION_RECEIPT_HOLD_TICKS
	_show_action_receipt()


func _show_action_receipt() -> void:
	var result_text := _action_result_text(_action_receipt_action, _action_receipt_result)
	intent_status.text = GameText.t(&"COMMAND_EXCEPTION_ACTION_RESULT_CONTEXT") % [_action_receipt_subject, _action_text(_action_receipt_action), result_text]
	intent_status.tooltip_text = intent_status.text
	intent_status.add_theme_color_override("font_color", Color(0.48, 0.84, 0.64) if _action_receipt_accepted else Color(1.0, 0.52, 0.42))


func _has_active_action_receipt() -> bool:
	if _action_receipt_action < 0 or _action_receipt_exception_id.is_empty():
		return false
	return current_snapshot == null or current_snapshot.tick <= _action_receipt_expires_at_tick


func _clear_action_receipt() -> void:
	_action_receipt_exception_id = &""
	_action_receipt_action = -1
	_action_receipt_result = null
	_action_receipt_accepted = false
	_action_receipt_expires_at_tick = -1
	_action_receipt_subject = ""
	if intent_status != null:
		intent_status.remove_theme_color_override("font_color")
		intent_status.tooltip_text = ""


func _exception_text(exception: CommandExceptionSnapshot) -> String:
	var subject := GameText.t(exception.unit_card_name_key) if not exception.unit_card_name_key.is_empty() else GameText.t(&"COMMAND_DESK_FORCE_WIDE")
	return "%s | %s" % [subject, GameText.t(exception.reason_key)]


func _exception_tooltip(exception: CommandExceptionSnapshot) -> String:
	return GameText.t(&"COMMAND_EXCEPTION_DETAIL") % [
		GameText.t(StringName("COMMAND_EXCEPTION_KIND_%s" % CommandExceptionSnapshot.Kind.keys()[exception.kind])),
		floori(exception.source_tick * SimulationWorld.TICK_SECONDS),
		exception.value_current,
		exception.value_limit,
	]


func _action_text(action: int) -> String:
	return GameText.t(StringName("COMMAND_EXCEPTION_ACTION_%s_SHORT" % CommandExceptionSnapshot.Action.keys()[action]))


func _action_tooltip(action: int, exception: CommandExceptionSnapshot = null) -> String:
	var base := GameText.t(StringName("COMMAND_EXCEPTION_ACTION_%s_TOOLTIP" % CommandExceptionSnapshot.Action.keys()[action]))
	if exception == null:
		return base
	if action == CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER:
		return base % _commander_name(exception.commander_id)
	if action == CommandExceptionSnapshot.Action.RETURN_TO_COMMANDER:
		return base % GameText.t(exception.unit_card_name_key)
	return base


func _action_subject(exception: CommandExceptionSnapshot, action: int) -> String:
	if exception == null:
		return GameText.t(&"COMMAND_DESK_FORCE_WIDE")
	if action == CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER:
		return GameText.t(&"COMMAND_EXCEPTION_SCOPE_COMMANDER") % _commander_name(exception.commander_id)
	if not exception.unit_card_name_key.is_empty():
		return GameText.t(&"COMMAND_EXCEPTION_SCOPE_CARD") % GameText.t(exception.unit_card_name_key)
	return GameText.t(&"COMMAND_DESK_FORCE_WIDE")


func _action_result_text(action: int, result: CommandValidationResult) -> String:
	if result == null or result.is_accepted():
		return GameText.command_result(result)
	if action == CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER and result.reason == CommandValidationResult.Reason.INVALID_TARGET:
		return GameText.t(&"COMMAND_EXCEPTION_DISENGAGE_INVALID")
	if action == CommandExceptionSnapshot.Action.RETURN_TO_COMMANDER and result.reason == CommandValidationResult.Reason.INVALID_DISPOSITION:
		return GameText.t(&"COMMAND_EXCEPTION_RETURN_INVALID")
	return GameText.command_result(result)


func _commander_name(commander_id: StringName) -> String:
	var commander := current_snapshot.get_commander(commander_id) if current_snapshot != null else null
	return GameText.t(commander.display_name_key) if commander != null else String(commander_id)


func _show_guide() -> void:
	if guide_popup == null:
		return
	var viewport_size := get_viewport_rect().size
	var preferred := Vector2i(mini(500, maxi(300, int(viewport_size.x * 0.9))), mini(420, maxi(260, int(viewport_size.y * 0.8))))
	guide_popup.popup_centered(preferred)


func _show_history() -> void:
	if history_popup == null:
		return
	_update_history_display()
	if not history_popup.is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var preferred := Vector2i(mini(560, maxi(300, int(viewport_size.x * 0.92))), mini(440, maxi(260, int(viewport_size.y * 0.82))))
	history_popup.popup_centered(preferred)


func get_decision_history_count() -> int:
	return _decision_history.size()


func _record_decision(subject: String, action: String, result_text: String, accepted: bool) -> int:
	var tick := current_snapshot.tick if current_snapshot != null else 0
	_decision_history.append({
		"tick": tick, "subject": subject, "action": action,
		"result": result_text, "accepted": accepted,
	})
	if _decision_history.size() > DECISION_HISTORY_LIMIT:
		_decision_history.pop_front()
	_update_history_display()
	return _decision_history.size() - 1


func _update_history_display() -> void:
	if history_button == null or history_text == null:
		return
	history_button.text = GameText.t(&"DECISION_HISTORY_BUTTON") % _decision_history.size()
	history_button.tooltip_text = GameText.t(&"DECISION_HISTORY_TOOLTIP")
	if _decision_history.is_empty():
		history_text.text = "[b]%s[/b]\n\n%s" % [GameText.t(&"DECISION_HISTORY_TITLE"), GameText.t(&"DECISION_HISTORY_EMPTY")]
		return
	var lines: Array[String] = ["[b]%s[/b]" % GameText.t(&"DECISION_HISTORY_TITLE")]
	for index in range(_decision_history.size() - 1, -1, -1):
		var entry := _decision_history[index]
		var seconds := floori(int(entry["tick"]) * SimulationWorld.TICK_SECONDS)
		lines.append(GameText.t(&"DECISION_HISTORY_ENTRY") % [
			seconds, entry["subject"], entry["action"], entry["result"],
		])
	history_text.text = "\n\n".join(lines)


func _watch_response(response: Dictionary) -> void:
	response["deadline_tick"] = int(response.get("issued_tick", 0)) + DECISION_RESPONSE_TIMEOUT_TICKS
	_pending_responses.append(response)


func _watch_exception_response(
	exception: CommandExceptionSnapshot,
	action: int,
	history_index: int,
	subject: String
) -> void:
	if action in [CommandExceptionSnapshot.Action.FOCUS, CommandExceptionSnapshot.Action.KEEP_PLAN, CommandExceptionSnapshot.Action.REQUEST_REINFORCEMENT]:
		return
	_watch_response({
		"kind": "exception", "action_id": action, "commander_id": exception.commander_id,
		"unit_card_id": exception.unit_card_id, "task_id": exception.task_id,
		"issued_tick": current_snapshot.tick if current_snapshot != null else 0,
		"history_index": history_index, "subject": subject, "action": _action_text(action),
	})


func _check_pending_responses() -> void:
	for response_index in range(_pending_responses.size() - 1, -1, -1):
		var response := _pending_responses[response_index]
		if _response_is_confirmed(response):
			_update_history_result(int(response["history_index"]), GameText.t(&"DECISION_RESPONSE_CONFIRMED"), true)
			_pending_responses.remove_at(response_index)
			continue
		if current_snapshot.tick < int(response["deadline_tick"]):
			continue
		var reason := GameText.t(&"DECISION_RESPONSE_TIMEOUT_REASON")
		_update_history_result(int(response["history_index"]), reason, false)
		_show_decision_failure(String(response["subject"]), String(response["action"]), reason)
		_pending_responses.remove_at(response_index)


func _response_is_confirmed(response: Dictionary) -> bool:
	var kind := String(response.get("kind", ""))
	var commander := current_snapshot.get_commander(response.get("commander_id", &"") as StringName)
	if kind == "intent":
		return commander != null \
			and commander.active_intent_id == response.get("intent_id", &"") \
			and commander.intent_objective_region_id == response.get("objective_id", &"") \
			and commander.intent_axis_region_id == response.get("axis_id", &"")
	if kind == "cancel_intent":
		return commander != null and commander.active_intent_id.is_empty()
	if kind != "exception":
		return true
	var action := int(response.get("action_id", -1))
	match action:
		CommandExceptionSnapshot.Action.RESUME_TASK:
			var resumed := current_snapshot.get_task(int(response.get("task_id", 0)))
			return resumed != null and resumed.lifecycle == TaskState.Lifecycle.EXECUTING
		CommandExceptionSnapshot.Action.CANCEL_TASK:
			var cancelled := current_snapshot.get_task(int(response.get("task_id", 0)))
			return cancelled == null or cancelled.lifecycle == TaskState.Lifecycle.CANCELLED
		CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER:
			return commander != null and commander.posture == CommanderState.Posture.DISENGAGE
		CommandExceptionSnapshot.Action.RETURN_TO_COMMANDER:
			var card := current_snapshot.get_unit_card(response.get("unit_card_id", &"") as StringName)
			return card != null and card.control_state not in [UnitCardState.ControlState.PLAYER_CONTROLLED, UnitCardState.ControlState.PLAYER_OVERRIDDEN]
	return true


func _update_history_result(index: int, result_text: String, accepted: bool) -> void:
	if index < 0 or index >= _decision_history.size():
		return
	_decision_history[index]["result"] = result_text
	_decision_history[index]["accepted"] = accepted
	_update_history_display()


func _record_and_show_unavailable(subject: String) -> void:
	var reason := GameText.t(&"DECISION_RESPONSE_UNAVAILABLE")
	_record_decision(subject, GameText.t(&"DECISION_ACTION_ATTEMPT"), reason, false)
	_show_decision_failure(subject, GameText.t(&"DECISION_ACTION_ATTEMPT"), reason)


func _record_and_show_stale(exception_id: StringName) -> void:
	var subject := String(exception_id)
	var reason := GameText.t(&"DECISION_RESPONSE_STALE")
	_record_decision(subject, GameText.t(&"DECISION_ACTION_ATTEMPT"), reason, false)
	_show_decision_failure(subject, GameText.t(&"DECISION_ACTION_ATTEMPT"), reason)


func _show_decision_failure(subject: String, action: String, reason: String) -> void:
	if decision_failure_dialog == null:
		return
	decision_failure_dialog.title = GameText.t(&"DECISION_FAILURE_TITLE")
	decision_failure_dialog.dialog_text = GameText.t(&"DECISION_FAILURE_BODY") % [subject, action, reason]
	if not decision_failure_dialog.is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var preferred := Vector2i(
		mini(520, maxi(300, int(viewport_size.x * 0.92))),
		mini(230, maxi(180, int(viewport_size.y * 0.55)))
	)
	decision_failure_dialog.popup_centered(preferred)


func _preview_selected_objective() -> void:
	_preview_selected_region(objective_selector, false)


func _preview_selected_axis() -> void:
	_preview_selected_region(axis_selector, true)


func _preview_selected_region(selector: OptionButton, include_route: bool) -> void:
	if current_snapshot == null:
		return
	var region := current_snapshot.get_strategic_region(StringName(_selected_metadata(selector, &"")))
	if region == null:
		return
	var route := PackedVector2Array()
	if include_route:
		var origin := _selected_commander_origin()
		if not origin.is_zero_approx():
			route = PackedVector2Array([origin, region.position])
	decision_preview_changed.emit(route, region.position, region.radius, GameText.t(region.display_name_key))


func _preview_exception(exception_id: StringName) -> void:
	if current_snapshot == null or current_command_situation == null:
		return
	var exception := current_command_situation.get_exception(exception_id)
	if exception == null:
		return
	var route := PackedVector2Array()
	var target := exception.position
	var task := current_snapshot.get_task(exception.task_id)
	if task != null:
		route = task.route.duplicate() if not task.route.is_empty() else task.planned_route.duplicate()
		if target.is_zero_approx():
			target = task.target_position
		if route.size() == 1 and not target.is_zero_approx() and not route[0].is_equal_approx(target):
			route.append(target)
	decision_preview_changed.emit(route, target, 54.0, _exception_text(exception))


func _selected_commander_origin() -> Vector2:
	var commander_id := StringName(_selected_metadata(commander_selector, &""))
	var commander := current_snapshot.get_commander(commander_id)
	if commander == null:
		return Vector2.ZERO
	var total := Vector2.ZERO
	var count := 0
	for card_id in commander.subordinate_unit_card_ids:
		var card := current_snapshot.get_unit_card(card_id)
		if card == null or card.center_position.is_zero_approx():
			continue
		total += card.center_position
		count += 1
	return total / float(count) if count > 0 else commander.target_position


func _clear_decision_preview() -> void:
	decision_preview_cleared.emit()


func _selected_metadata(selector: OptionButton, fallback: Variant) -> Variant:
	if selector == null or selector.item_count == 0 or selector.selected < 0:
		return fallback
	return selector.get_item_metadata(selector.selected)


func _select_metadata(selector: OptionButton, value: Variant) -> void:
	if selector == null or selector.item_count == 0:
		return
	for index in range(selector.item_count):
		if selector.get_item_metadata(index) == value:
			selector.select(index)
			return
	selector.select(0)
