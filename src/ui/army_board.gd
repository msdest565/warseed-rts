class_name ArmyBoard
extends PanelContainer

@onready var title_label: Label = $Margin/Layout/Header/Title
@onready var hint_label: Label = $Margin/Layout/Header/Hint
@onready var commander_row: BoxContainer = $Margin/Layout/Scroll/CommanderRow

@export var input_controller: InputController

var _snapshot: WorldSnapshot
var _content_signature: String = ""
var _unit_card_buttons: Dictionary = {}
var _unit_card_control_buttons: Dictionary = {}
var _unit_card_deploy_buttons: Dictionary = {}
var _unit_card_route_buttons: Dictionary = {}
var _unit_card_route_submit_buttons: Dictionary = {}
var _unit_card_route_undo_buttons: Dictionary = {}
var _commander_buttons: Dictionary = {}
var _commander_route_buttons: Dictionary = {}
var _commander_route_submit_buttons: Dictionary = {}
var _commander_route_undo_buttons: Dictionary = {}
var _commander_status_labels: Dictionary = {}
var _pending_commander_drag_id: StringName
var _pending_commander_drag_start: Vector2
var _pending_reserve_drag_id: StringName
var _pending_reserve_drag_start: Vector2
var _reserve_drag_active: bool = false
var _reserve_drag_id: StringName
var _reserve_drop_commander_id: StringName
var _narrow_layout: bool = false
var _commander_only: bool = false
var _tactical_cards: bool = false
var _posture_menus: Dictionary = {}
var _overview_card_columns: int = 1
var _overview_card_height: float = 40.0
var _handoff_button: Button


func _ready() -> void:
	_ensure_node_bindings()
	var viewport := get_viewport()
	if viewport != null:
		_narrow_layout = viewport.get_visible_rect().size.x < 900.0
		if not viewport.size_changed.is_connected(_on_viewport_size_changed):
			viewport.size_changed.connect(_on_viewport_size_changed)
	refresh_locale()


func _input(event: InputEvent) -> void:
	if not _reserve_drag_active or not _handle_reserve_drag_input(event):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func refresh_locale() -> void:
	_ensure_node_bindings()
	if title_label == null or hint_label == null:
		return
	title_label.text = GameText.t(&"ARMY_BOARD_TITLE")
	hint_label.text = GameText.t(&"ARMY_BOARD_HINT")
	_content_signature = ""
	_rebuild_if_needed()


func update_snapshot(snapshot: WorldSnapshot) -> void:
	_ensure_node_bindings()
	_snapshot = snapshot
	if _reserve_drag_active:
		var dragged_card := _snapshot.get_unit_card(_reserve_drag_id)
		if dragged_card == null or dragged_card.deployment_state != UnitCardState.DeploymentState.RESERVE:
			_cancel_reserve_drag()
	_rebuild_if_needed()
	_update_dynamic_content()
	_update_selection_state()


func get_unit_card_button_count() -> int:
	return _unit_card_buttons.size()


func get_commander_card_count() -> int:
	return _commander_buttons.size()


func set_commander_only(enabled: bool) -> void:
	if _commander_only == enabled:
		return
	_commander_only = enabled
	_content_signature = ""
	_rebuild_if_needed()


func is_commander_only() -> bool:
	return _commander_only


func get_commander_status_text(commander_id: StringName) -> String:
	var label := _commander_status_labels.get(commander_id) as Label
	return label.text if label != null else ""


func get_commander_status_tooltip(commander_id: StringName) -> String:
	var label := _commander_status_labels.get(commander_id) as Label
	return label.tooltip_text if label != null else ""


func _rebuild_if_needed() -> void:
	if _snapshot == null or commander_row == null:
		return
	var signature_parts: Array[String] = []
	for commander in _snapshot.commanders:
		signature_parts.append("%s:%s:%d:%s:%s" % [
			commander.definition_id,
			commander.subordinate_unit_card_ids,
			commander.posture,
			commander.available_doctrine_ids,
			commander.equipped_doctrine_ids,
		])
	for unit_card in _snapshot.unit_cards:
		signature_parts.append("%s:%s:%d:%d" % [
			unit_card.definition_id,
			unit_card.commander_definition_id,
			unit_card.deployment_state,
			unit_card.control_state,
		])
	if _tactical_cards:
		signature_parts.clear()
		signature_parts.append("overview:%d:%s" % [_overview_card_columns, _overview_card_height])
		for commander in _snapshot.commanders:
			signature_parts.append("%s:%s" % [commander.definition_id, commander.subordinate_unit_card_ids])
	var signature := "%s:%s:%s" % ["|".join(signature_parts), TranslationServer.get_locale(), _commander_only]
	if signature == _content_signature:
		return
	_content_signature = signature
	for child in commander_row.get_children():
		commander_row.remove_child(child)
		child.queue_free()
	_unit_card_buttons.clear()
	_unit_card_control_buttons.clear()
	_unit_card_deploy_buttons.clear()
	_unit_card_route_buttons.clear()
	_unit_card_route_submit_buttons.clear()
	_unit_card_route_undo_buttons.clear()
	_commander_buttons.clear()
	_commander_route_buttons.clear()
	_commander_route_submit_buttons.clear()
	_commander_route_undo_buttons.clear()
	_commander_status_labels.clear()
	_posture_menus.clear()
	for commander in _snapshot.commanders:
		if (_commander_only or _tactical_cards) and commander.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			continue
		commander_row.add_child(_create_tactical_column(commander) if _tactical_cards else _create_commander_column(commander))
	_update_dynamic_content()


func _create_commander_column(commander: CommanderSnapshot) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(0.0, 0.0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)

	var commander_button := Button.new()
	commander_button.custom_minimum_size = Vector2(0.0, 25.0)
	commander_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	commander_button.clip_text = true
	commander_button.text = GameText.t(&"COMMANDER_CARD_HEADER") % [
		GameText.t(commander.display_name_key), commander.capacity, GameText.t(commander.personality_key),
	]
	commander_button.tooltip_text = GameText.t(&"COMMANDER_CARD_TOOLTIP") % [
		_localized_join(commander.specialty_keys), _localized_doctrine_join(commander.equipped_doctrine_ids),
	]
	commander_button.pressed.connect(_select_commander.bind(commander.definition_id))
	commander_button.gui_input.connect(_handle_commander_button_input.bind(commander.definition_id))
	column.add_child(commander_button)
	_commander_buttons[commander.definition_id] = commander_button

	var status_label := Label.new()
	status_label.custom_minimum_size = Vector2(0.0, 36.0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 9)
	_apply_commander_status(status_label, commander)
	column.add_child(status_label)
	_commander_status_labels[commander.definition_id] = status_label
	if _commander_only:
		status_label.custom_minimum_size.y = 52.0
		status_label.add_theme_font_size_override("font_size", 10)
		return column

	var posture_menu := OptionButton.new()
	posture_menu.custom_minimum_size = Vector2(0.0, 23.0)
	posture_menu.fit_to_longest_item = false
	posture_menu.tooltip_text = GameText.t(&"COMMANDER_POSTURE_TOOLTIP")
	for posture_value in range(CommanderState.Posture.size()):
		posture_menu.add_item(GameText.t(StringName("COMMANDER_POSTURE_%s" % CommanderState.Posture.keys()[posture_value])), posture_value)
	posture_menu.select(commander.posture)
	posture_menu.item_selected.connect(_set_commander_posture.bind(commander.definition_id))
	column.add_child(posture_menu)

	var commander_route_button := Button.new()
	commander_route_button.custom_minimum_size = Vector2(0.0, 23.0)
	commander_route_button.clip_text = true
	commander_route_button.text = GameText.t(&"COMMANDER_ACTION_ROUTE")
	commander_route_button.tooltip_text = GameText.t(&"COMMANDER_ROUTE_TOOLTIP")
	commander_route_button.pressed.connect(_begin_commander_route.bind(commander.definition_id))
	column.add_child(commander_route_button)
	_commander_route_buttons[commander.definition_id] = commander_route_button
	var commander_route_actions := HBoxContainer.new()
	commander_route_actions.add_theme_constant_override("separation", 2)
	var commander_submit_button := Button.new()
	commander_submit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commander_submit_button.clip_text = true
	commander_submit_button.text = GameText.t(&"UNIT_CARD_ACTION_ROUTE_SUBMIT")
	commander_submit_button.pressed.connect(_submit_commander_route.bind(commander.definition_id))
	commander_route_actions.add_child(commander_submit_button)
	_commander_route_submit_buttons[commander.definition_id] = commander_submit_button
	var commander_undo_button := Button.new()
	commander_undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commander_undo_button.clip_text = true
	commander_undo_button.text = GameText.t(&"UNIT_CARD_ACTION_ROUTE_UNDO")
	commander_undo_button.pressed.connect(_undo_commander_route.bind(commander.definition_id))
	commander_route_actions.add_child(commander_undo_button)
	_commander_route_undo_buttons[commander.definition_id] = commander_undo_button
	column.add_child(commander_route_actions)

	var doctrine_menu := OptionButton.new()
	doctrine_menu.custom_minimum_size = Vector2(0.0, 23.0)
	doctrine_menu.fit_to_longest_item = false
	for doctrine_id in commander.available_doctrine_ids:
		doctrine_menu.add_item(GameText.t(_doctrine_key(doctrine_id)))
		doctrine_menu.set_item_metadata(doctrine_menu.item_count - 1, doctrine_id)
	var equipped_id: StringName = commander.equipped_doctrine_ids[0] if not commander.equipped_doctrine_ids.is_empty() else &""
	var equipped_index := commander.available_doctrine_ids.find(equipped_id)
	if equipped_index >= 0:
		doctrine_menu.select(equipped_index)
		doctrine_menu.tooltip_text = GameText.t(&"DOCTRINE_SLOT_TOOLTIP") % [
			GameText.t(_doctrine_key(equipped_id)),
			GameText.t(_doctrine_key(equipped_id, "_BEHAVIOR")),
			GameText.t(_doctrine_key(equipped_id, "_TRADEOFF")),
		]
	doctrine_menu.item_selected.connect(_equip_commander_doctrine.bind(commander.definition_id))
	column.add_child(doctrine_menu)

	var cards_row := BoxContainer.new()
	var stack_cards := _narrow_layout or commander.subordinate_unit_card_ids.size() > 2
	cards_row.vertical = stack_cards
	cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_row.add_theme_constant_override("separation", 4)
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := _snapshot.get_unit_card(unit_card_id)
		if unit_card == null:
			continue
		var card_column := VBoxContainer.new()
		card_column.custom_minimum_size = Vector2(0.0 if stack_cards else 102.0, 0.0)
		card_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_column.add_theme_constant_override("separation", 2)
		var card_button := Button.new()
		card_button.custom_minimum_size = Vector2(0.0, 56.0)
		card_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_button.toggle_mode = true
		card_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card_button.clip_text = true
		card_button.text = _unit_card_body(unit_card)
		card_button.tooltip_text = "" if _tactical_cards else _unit_card_tooltip(unit_card, commander) + "\n" + CompositionText.from_snapshot(unit_card)
		card_button.disabled = unit_card.deployment_state in [
			UnitCardState.DeploymentState.WITHDRAWN,
			UnitCardState.DeploymentState.DISABLED,
		]
		card_button.pressed.connect(_select_unit_card.bind(unit_card.definition_id))
		if unit_card.deployment_state == UnitCardState.DeploymentState.RESERVE:
			card_button.gui_input.connect(_handle_unit_card_button_input.bind(unit_card.definition_id))
			card_button.mouse_default_cursor_shape = Control.CURSOR_DRAG
		card_column.add_child(card_button)
		if unit_card.deployment_state == UnitCardState.DeploymentState.RESERVE:
			var deploy_button := _create_deploy_button(unit_card)
			card_column.add_child(deploy_button)
			_unit_card_deploy_buttons[unit_card.definition_id] = deploy_button
		var control_button := _create_control_button(unit_card)
		if control_button != null:
			card_column.add_child(control_button)
			_unit_card_control_buttons[unit_card.definition_id] = control_button
		var route_button := _create_route_button(unit_card)
		if route_button != null:
			card_column.add_child(route_button)
			_unit_card_route_buttons[unit_card.definition_id] = route_button
			var route_actions := HBoxContainer.new()
			route_actions.add_theme_constant_override("separation", 2)
			var submit_button := Button.new()
			submit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			submit_button.clip_text = true
			submit_button.text = GameText.t(&"UNIT_CARD_ACTION_ROUTE_SUBMIT")
			submit_button.tooltip_text = GameText.t(&"UNIT_CARD_ROUTE_SUBMIT_TOOLTIP")
			submit_button.pressed.connect(_submit_unit_card_route.bind(unit_card.definition_id))
			route_actions.add_child(submit_button)
			_unit_card_route_submit_buttons[unit_card.definition_id] = submit_button
			var undo_button := Button.new()
			undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			undo_button.clip_text = true
			undo_button.text = GameText.t(&"UNIT_CARD_ACTION_ROUTE_UNDO")
			undo_button.tooltip_text = GameText.t(&"UNIT_CARD_ROUTE_UNDO_TOOLTIP")
			undo_button.pressed.connect(_undo_unit_card_route.bind(unit_card.definition_id))
			route_actions.add_child(undo_button)
			_unit_card_route_undo_buttons[unit_card.definition_id] = undo_button
			card_column.add_child(route_actions)
		cards_row.add_child(card_column)
		_unit_card_buttons[unit_card.definition_id] = card_button
	column.add_child(cards_row)
	return column


func _on_viewport_size_changed() -> void:
	var viewport := get_viewport()
	var narrow := viewport != null and viewport.get_visible_rect().size.x < 900.0
	if narrow == _narrow_layout:
		return
	_narrow_layout = narrow
	_content_signature = ""
	_rebuild_if_needed()


func _update_dynamic_content() -> void:
	if _snapshot == null:
		return
	_update_commander_route_buttons()
	_update_unit_card_route_buttons()
	for commander in _snapshot.commanders:
		var status_label := _commander_status_labels.get(commander.definition_id) as Label
		if status_label != null:
			_apply_commander_status(status_label, commander)
		if _tactical_cards:
			_update_tactical_commander(commander)
	for unit_card in _snapshot.unit_cards:
		var card_button := _unit_card_buttons.get(unit_card.definition_id) as Button
		if card_button == null:
			continue
		card_button.text = _unit_card_body(unit_card)
		var commander := _snapshot.get_commander(unit_card.commander_definition_id)
		if commander != null:
			card_button.tooltip_text = "" if _tactical_cards else _unit_card_tooltip(unit_card, commander) + "\n" + CompositionText.from_snapshot(unit_card)
		card_button.disabled = unit_card.deployment_state in [
			UnitCardState.DeploymentState.WITHDRAWN,
			UnitCardState.DeploymentState.DISABLED,
		]
		var control_button := _unit_card_control_buttons.get(unit_card.definition_id) as Button
		if control_button != null and unit_card.control_state == UnitCardState.ControlState.RETURNING:
			control_button.text = GameText.t(&"UNIT_CARD_ACTION_RETURNING") % unit_card.returning_member_count
		var deploy_button := _unit_card_deploy_buttons.get(unit_card.definition_id) as Button
		if deploy_button != null:
			_update_deploy_button(deploy_button, unit_card)
	if _handoff_button != null:
		_handoff_button.text = GameText.t(&"CONTROL_AI_BOARD")
		_handoff_button.tooltip_text = GameText.t(&"CONTROL_AI_HELP")
		_handoff_button.disabled = input_controller == null or input_controller.get_handoff_card_ids().is_empty()


func _apply_commander_status(label: Label, commander: CommanderSnapshot) -> void:
	var behavior_text := GameText.t(&"COMMANDER_BEHAVIOR_LINE") % [
		GameText.t(commander.behavior_state_key), GameText.t(commander.behavior_reason_key),
	]
	var eta_text := _commander_eta_text(commander)
	var status_text := "%s\n%s" % [behavior_text, GameText.t(&"COMMANDER_OUTLOOK_LINE") % [
		eta_text, GameText.t(commander.risk_key), GameText.t(commander.exit_condition_key),
	]]
	label.tooltip_text = GameText.t(&"COMMANDER_OUTLOOK_TOOLTIP") % [
		_commander_target_text(commander),
		_commander_participants_text(commander),
		GameText.t(commander.behavior_state_key),
		GameText.t(commander.behavior_reason_key),
		eta_text,
		GameText.t(commander.risk_key),
		GameText.t(commander.risk_reason_key),
		GameText.t(commander.exit_condition_key),
	]
	if _tactical_cards:
		var state := _tactical_activity(commander)
		status_text = GameText.t([&"CONTROL_STATE_IDLE", &"CONTROL_STATE_WORKING", &"CONTROL_STATE_CONTACT"][state])
		var status_color: Color = [Color("80dba0"), Color("eed16a"), Color("ff807a")][state]
		if label.get_theme_color("font_color") != status_color:
			label.add_theme_color_override("font_color", status_color)
	label.text = status_text


func _commander_eta_text(commander: CommanderSnapshot) -> String:
	if commander.estimated_arrival_min_ticks < 0 or commander.estimated_arrival_max_ticks < 0:
		return GameText.t(&"COMMANDER_ETA_UNKNOWN")
	if commander.estimated_arrival_max_ticks == 0:
		return GameText.t(&"COMMANDER_ETA_CURRENT")
	var min_seconds := ceili(float(commander.estimated_arrival_min_ticks) * SimulationWorld.TICK_SECONDS)
	var max_seconds := ceili(float(commander.estimated_arrival_max_ticks) * SimulationWorld.TICK_SECONDS)
	if min_seconds == max_seconds:
		return GameText.t(&"COMMANDER_ETA_SECONDS") % min_seconds
	return GameText.t(&"COMMANDER_ETA_RANGE") % [min_seconds, max_seconds]


func _commander_target_text(commander: CommanderSnapshot) -> String:
	var region := _snapshot.get_strategic_region(commander.target_region_id) if _snapshot != null else null
	if region != null:
		return GameText.t(region.display_name_key)
	return GameText.t(&"COMMANDER_TARGET_POSITION") % [roundi(commander.target_position.x), roundi(commander.target_position.y)]


func _commander_participants_text(commander: CommanderSnapshot) -> String:
	var entries: Array[String] = []
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := _snapshot.get_unit_card(unit_card_id) if _snapshot != null else null
		if unit_card == null or unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
			continue
		entries.append(GameText.t(&"COMMANDER_PARTICIPANT_ENTRY") % [GameText.t(unit_card.display_name_key), unit_card.current_strength])
	return GameText.t(&"COMMANDER_PARTICIPANTS_NONE") if entries.is_empty() else ", ".join(entries)


func _create_control_button(unit_card: UnitCardSnapshot) -> Button:
	if unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
		return null
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 22.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match unit_card.control_state:
		UnitCardState.ControlState.AGENT_ASSIGNED:
			button.text = GameText.t(&"UNIT_CARD_ACTION_TAKEOVER")
			button.pressed.connect(_set_unit_card_control.bind(unit_card.definition_id, UnitCardControlCommand.Action.TAKEOVER))
		UnitCardState.ControlState.PLAYER_OVERRIDDEN:
			button.text = GameText.t(&"UNIT_CARD_ACTION_RETURN")
			button.pressed.connect(_set_unit_card_control.bind(unit_card.definition_id, UnitCardControlCommand.Action.RETURN_TO_COMMANDER))
		UnitCardState.ControlState.RETURNING:
			button.text = GameText.t(&"UNIT_CARD_ACTION_RETURNING") % unit_card.returning_member_count
			button.disabled = true
		UnitCardState.ControlState.PLAYER_CONTROLLED:
			button.text = GameText.t(&"UNIT_CARD_ACTION_RETURN")
			button.pressed.connect(_set_unit_card_control.bind(unit_card.definition_id, UnitCardControlCommand.Action.RETURN_TO_COMMANDER))
		_:
			button.text = GameText.t(&"UNIT_CARD_ACTION_UNASSIGNED")
			button.disabled = true
	return button


func _create_route_button(unit_card: UnitCardSnapshot) -> Button:
	if unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
		return null
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 22.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = GameText.t(&"UNIT_CARD_ACTION_ROUTE")
	button.tooltip_text = GameText.t(&"UNIT_CARD_ROUTE_TOOLTIP")
	button.pressed.connect(_begin_unit_card_route.bind(unit_card.definition_id))
	return button


func _create_deploy_button(unit_card: UnitCardSnapshot) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 24.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_deploy_reserve_card.bind(unit_card.definition_id))
	_update_deploy_button(button, unit_card)
	return button


func _update_deploy_button(button: Button, unit_card: UnitCardSnapshot) -> void:
	button.text = GameText.t(&"UNIT_CARD_ACTION_DEPLOY") % unit_card.supply_cost
	var faction := _snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID) if _snapshot != null else null
	var enough_supply := faction != null and faction.supply >= unit_card.supply_cost
	var enough_population := faction != null and faction.population + unit_card.authorized_strength <= faction.population_capacity
	button.disabled = not enough_supply or not enough_population
	if not enough_supply:
		button.tooltip_text = GameText.t(&"UNIT_CARD_DEPLOY_DISABLED_SUPPLY")
	elif not enough_population:
		button.tooltip_text = GameText.t(&"UNIT_CARD_DEPLOY_DISABLED_POPULATION")
	else:
		button.tooltip_text = GameText.t(&"UNIT_CARD_DEPLOY_TOOLTIP")


func _deploy_reserve_card(unit_card_id: StringName) -> void:
	if input_controller == null or _snapshot == null:
		return
	var unit_card := _snapshot.get_unit_card(unit_card_id)
	if unit_card != null:
		input_controller.deploy_reserve_card_to_commander(unit_card_id, unit_card.commander_definition_id)


func _begin_unit_card_route(unit_card_id: StringName) -> void:
	if input_controller != null:
		input_controller.begin_unit_card_route(unit_card_id)
		_update_unit_card_route_buttons()


func _submit_unit_card_route(unit_card_id: StringName) -> void:
	if input_controller == null or not input_controller.is_unit_card_route_planning(unit_card_id):
		return
	input_controller.submit_selected_formation_route()
	_update_unit_card_route_buttons()


func _undo_unit_card_route(unit_card_id: StringName) -> void:
	if input_controller == null or not input_controller.is_unit_card_route_planning(unit_card_id):
		return
	input_controller.undo_formation_route_waypoint()
	_update_unit_card_route_buttons()


func _begin_commander_route(commander_id: StringName) -> void:
	if input_controller != null:
		input_controller.begin_commander_route(commander_id)
		_update_commander_route_buttons()


func _submit_commander_route(commander_id: StringName) -> void:
	if input_controller == null or not input_controller.is_commander_route_planning(commander_id):
		return
	input_controller.submit_selected_commander_route()
	_update_commander_route_buttons()


func _undo_commander_route(commander_id: StringName) -> void:
	if input_controller == null or not input_controller.is_commander_route_planning(commander_id):
		return
	input_controller.undo_commander_route_waypoint()
	_update_commander_route_buttons()


func update_command_mode(_mode: InputController.CommandMode) -> void:
	_update_commander_route_buttons()
	_update_unit_card_route_buttons()


func _update_unit_card_route_buttons() -> void:
	for unit_card_id_variant in _unit_card_route_buttons:
		var unit_card_id := unit_card_id_variant as StringName
		var planning := input_controller != null and input_controller.is_unit_card_route_planning(unit_card_id)
		var route_button := _unit_card_route_buttons[unit_card_id] as Button
		if route_button != null:
			route_button.text = GameText.t(&"UNIT_CARD_ACTION_ROUTE_CANCEL" if planning else &"UNIT_CARD_ACTION_ROUTE")
			route_button.tooltip_text = GameText.t(&"UNIT_CARD_ROUTE_CANCEL_TOOLTIP" if planning else &"UNIT_CARD_ROUTE_TOOLTIP")
		var submit_button := _unit_card_route_submit_buttons.get(unit_card_id) as Button
		if submit_button != null:
			submit_button.visible = planning
		var undo_button := _unit_card_route_undo_buttons.get(unit_card_id) as Button
		if undo_button != null:
			undo_button.visible = planning
			undo_button.disabled = input_controller == null or input_controller.formation_route_points.is_empty()


func _update_commander_route_buttons() -> void:
	for commander_id in _commander_route_buttons:
		var button := _commander_route_buttons[commander_id] as Button
		if button == null:
			continue
		var cancelling := input_controller != null and input_controller.is_commander_route_planning(commander_id)
		button.text = GameText.t(&"COMMANDER_ACTION_CANCEL_ROUTE" if cancelling else &"COMMANDER_ACTION_ROUTE")
		button.tooltip_text = GameText.t(&"COMMANDER_CANCEL_ROUTE_TOOLTIP" if cancelling else &"COMMANDER_ROUTE_TOOLTIP")
		var submit_button := _commander_route_submit_buttons.get(commander_id) as Button
		if submit_button != null:
			submit_button.visible = cancelling
		var undo_button := _commander_route_undo_buttons.get(commander_id) as Button
		if undo_button != null:
			undo_button.visible = cancelling
			undo_button.disabled = input_controller == null or input_controller.commander_route_points.is_empty()


func _set_unit_card_control(unit_card_id: StringName, action: UnitCardControlCommand.Action) -> void:
	if input_controller != null:
		input_controller.set_unit_card_control(unit_card_id, action)


func _set_commander_posture(index: int, commander_id: StringName) -> void:
	if input_controller != null:
		input_controller.set_commander_posture(commander_id, index)


func _equip_commander_doctrine(index: int, commander_id: StringName) -> void:
	if input_controller == null:
		return
	var commander := _snapshot.get_commander(commander_id) if _snapshot != null else null
	if commander == null or index < 0 or index >= commander.available_doctrine_ids.size():
		return
	input_controller.equip_commander_doctrine(commander_id, commander.available_doctrine_ids[index])


func _select_commander(commander_id: StringName) -> void:
	if input_controller != null:
		input_controller.select_commander_card(commander_id)
	_update_selection_state()


func _handle_commander_button_input(event: InputEvent, commander_id: StringName) -> void:
	if input_controller == null:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_pending_commander_drag_id = commander_id
			_pending_commander_drag_start = mouse.global_position
		else:
			_pending_commander_drag_id = &""
		return
	if event is InputEventMouseMotion and _pending_commander_drag_id == commander_id:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			_pending_commander_drag_id = &""
			return
		var current_position := motion.global_position
		if _pending_commander_drag_start.distance_to(current_position) > InputController.DRAG_THRESHOLD:
			if input_controller.begin_commander_drag(commander_id, _pending_commander_drag_start):
				_pending_commander_drag_id = &""


func _handle_unit_card_button_input(event: InputEvent, unit_card_id: StringName) -> void:
	if input_controller == null or _snapshot == null:
		return
	var unit_card := _snapshot.get_unit_card(unit_card_id)
	if unit_card == null or unit_card.deployment_state != UnitCardState.DeploymentState.RESERVE:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_pending_reserve_drag_id = unit_card_id
			_pending_reserve_drag_start = mouse.global_position
		else:
			_pending_reserve_drag_id = &""
		return
	if event is InputEventMouseMotion and _pending_reserve_drag_id == unit_card_id:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			_pending_reserve_drag_id = &""
			return
		if _pending_reserve_drag_start.distance_to(motion.global_position) <= InputController.DRAG_THRESHOLD:
			return
		_pending_reserve_drag_id = &""
		if input_controller.begin_reserve_card_drag(unit_card_id):
			_reserve_drag_active = true
			_reserve_drag_id = unit_card_id
			_set_reserve_drop_target(&"")


func _handle_reserve_drag_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_C:
			_cancel_reserve_drag()
			return true
		return false
	if event is InputEventMouseMotion:
		_set_reserve_drop_target(_commander_at_global_position((event as InputEventMouseMotion).position))
		return true
	if not event is InputEventMouseButton:
		return false
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		_cancel_reserve_drag()
		return true
	if mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return false
	var commander_id := _commander_at_global_position(mouse.position)
	if commander_id.is_empty():
		_cancel_reserve_drag()
	else:
		_complete_reserve_drag(commander_id)
	return true


func _complete_reserve_drag(commander_id: StringName) -> CommandValidationResult:
	if not _reserve_drag_active or _reserve_drag_id.is_empty():
		return null
	var unit_card_id := _reserve_drag_id
	_clear_reserve_drag_state()
	return input_controller.deploy_reserve_card_to_commander(unit_card_id, commander_id)


func _cancel_reserve_drag() -> void:
	if not _reserve_drag_active:
		return
	_clear_reserve_drag_state()
	input_controller.cancel_reserve_card_drag()


func _clear_reserve_drag_state() -> void:
	_reserve_drag_active = false
	_reserve_drag_id = &""
	_pending_reserve_drag_id = &""
	_set_reserve_drop_target(&"")


func _set_reserve_drop_target(commander_id: StringName) -> void:
	_reserve_drop_commander_id = commander_id
	var dragged_card := _snapshot.get_unit_card(_reserve_drag_id) if _snapshot != null and not _reserve_drag_id.is_empty() else null
	for id_variant in _commander_buttons:
		var id := id_variant as StringName
		var button := _commander_buttons[id] as Button
		if button == null:
			continue
		button.self_modulate = Color.WHITE
		if id != commander_id:
			continue
		button.self_modulate = Color("9ee8c4") if dragged_card != null and dragged_card.commander_definition_id == id else Color("f19a91")
	if input_controller != null and _reserve_drag_active:
		input_controller.preview_reserve_card_drop(commander_id)
		if hint_label != null:
			hint_label.text = input_controller.last_command_status
	elif hint_label != null:
		hint_label.text = GameText.t(&"ARMY_BOARD_HINT")


func _commander_at_global_position(global_position: Vector2) -> StringName:
	for commander_id_variant in _commander_buttons:
		var commander_id := commander_id_variant as StringName
		var button := _commander_buttons[commander_id] as Button
		if button != null and is_instance_valid(button) and button.visible and button.get_global_rect().has_point(global_position):
			return commander_id
	return &""


func _select_unit_card(unit_card_id: StringName) -> void:
	if input_controller != null:
		input_controller.select_unit_card(unit_card_id)
	_update_selection_state()


func _update_selection_state() -> void:
	if input_controller == null or _snapshot == null:
		return
	for unit_card_id in _unit_card_buttons:
		var button := _unit_card_buttons[unit_card_id] as Button
		var unit_card := _snapshot.get_unit_card(unit_card_id)
		button.set_pressed_no_signal(unit_card != null and (
			input_controller.selected_unit_card_id == unit_card_id
			or _all_members_selected(unit_card.active_member_entity_ids)
		))


func set_handoff_available(available: bool) -> void:
	if _handoff_button != null:
		_handoff_button.disabled = not available


func _unit_card_body(unit_card: UnitCardSnapshot) -> String:
	if _tactical_cards:
		var badge := ""
		if unit_card.deployment_state == UnitCardState.DeploymentState.RESERVE:
			badge = GameText.t(&"TACTICAL_RESERVE_CARD")
		elif unit_card.control_state in [UnitCardState.ControlState.PLAYER_CONTROLLED, UnitCardState.ControlState.PLAYER_OVERRIDDEN]:
			badge = GameText.t(&"CONTROL_MANUAL_BADGE")
		elif unit_card.control_state == UnitCardState.ControlState.RETURNING:
			badge = GameText.t(&"CONTROL_RETURNING_BADGE")
		return "%s\n%d / %d%s" % [GameText.t(unit_card.display_name_key), _display_strength(unit_card), unit_card.authorized_strength, " · " + badge if not badge.is_empty() else ""]
	match unit_card.deployment_state:
		UnitCardState.DeploymentState.RESERVE:
			return GameText.t(&"UNIT_CARD_RESERVE_BODY") % [
				GameText.t(unit_card.display_name_key), unit_card.supply_cost,
				unit_card.deployment_ticks * SimulationWorld.TICK_SECONDS,
			]
		UnitCardState.DeploymentState.DEPLOYING:
			return GameText.t(&"UNIT_CARD_DEPLOYING_BODY") % [
				GameText.t(unit_card.display_name_key),
				unit_card.deployment_ticks_remaining * SimulationWorld.TICK_SECONDS,
			]
		UnitCardState.DeploymentState.DEPLOYED:
			if unit_card.fortified_ticks_remaining > 0:
				return GameText.t(&"UNIT_CARD_FORTIFIED_BODY") % [
					GameText.t(unit_card.display_name_key), unit_card.current_strength,
					unit_card.authorized_strength,
					unit_card.fortified_ticks_remaining * SimulationWorld.TICK_SECONDS,
				]
			if unit_card.organization_enabled:
				return GameText.t(&"UNIT_CARD_BODY_ORGANIZATION") % [
					GameText.t(unit_card.display_name_key), unit_card.current_strength,
					unit_card.authorized_strength, roundi(unit_card.organization),
					GameText.t(unit_card.organization_state_key),
				]
			return GameText.t(&"UNIT_CARD_BODY") % [
				GameText.t(unit_card.display_name_key), unit_card.current_strength,
				unit_card.authorized_strength, GameText.t(unit_card.role_key),
			]
	if unit_card.deployment_state == UnitCardState.DeploymentState.WITHDRAWN:
		return GameText.t(&"UNIT_CARD_WITHDRAWN_BODY") % [GameText.t(unit_card.display_name_key), unit_card.withdrawn_strength]
	return GameText.t(&"UNIT_CARD_DISABLED_BODY") % GameText.t(unit_card.display_name_key)


func _unit_card_tooltip(unit_card: UnitCardSnapshot, commander: CommanderSnapshot) -> String:
	if unit_card.deployment_state == UnitCardState.DeploymentState.RESERVE:
		return GameText.t(&"UNIT_CARD_RESERVE_TOOLTIP") % [
			GameText.t(commander.display_name_key), unit_card.supply_cost,
			unit_card.authorized_strength,
		]
	return GameText.t(&"UNIT_CARD_PERSISTENT_TOOLTIP") % [
		GameText.t(commander.display_name_key), unit_card.command_cost,
		unit_card.active_member_entity_ids.size(), _terrain_name(unit_card.terrain_kind),
		GameText.t(unit_card.terrain_effect_key), unit_card.cumulative_losses,
		unit_card.battles_survived,
	]


func _terrain_name(terrain_kind: UnitState.TerrainKind) -> String:
	return GameText.t(StringName("TERRAIN_%s" % UnitState.TerrainKind.keys()[terrain_kind]))


func _all_members_selected(member_ids: Array[int]) -> bool:
	if member_ids.is_empty():
		return false
	for entity_id in member_ids:
		if not input_controller.selected_entity_ids.has(entity_id):
			return false
	return true


func _localized_join(keys: Array[StringName]) -> String:
	var values: Array[String] = []
	for key in keys:
		values.append(GameText.t(key))
	return " / ".join(values)


func _localized_doctrine_join(doctrine_ids: Array[StringName]) -> String:
	var keys: Array[StringName] = []
	for doctrine_id in doctrine_ids:
		keys.append(_doctrine_key(doctrine_id))
	return _localized_join(keys)


func _doctrine_key(doctrine_id: StringName, suffix: String = "") -> StringName:
	return StringName("DOCTRINE_%s%s" % [String(doctrine_id).to_upper(), suffix])


func _ensure_node_bindings() -> void:
	if title_label == null:
		title_label = get_node_or_null("Margin/Layout/Header/Title") as Label
	if hint_label == null:
		hint_label = get_node_or_null("Margin/Layout/Header/Hint") as Label
	if commander_row == null:
		commander_row = get_node_or_null("Margin/Layout/Scroll/CommanderRow") as BoxContainer


func set_tactical_cards(enabled: bool) -> void:
	_ensure_node_bindings()
	if _tactical_cards == enabled:
		return
	_tactical_cards = enabled
	_commander_only = false
	if commander_row != null:
		commander_row.vertical = not enabled
	var scroll := get_node_or_null("Margin/Layout/Scroll") as ScrollContainer
	if scroll != null:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if enabled else ScrollContainer.SCROLL_MODE_AUTO
	if enabled and _handoff_button == null:
		_handoff_button = Button.new()
		_handoff_button.custom_minimum_size.y = 32.0
		_handoff_button.custom_minimum_size.x = 210.0
		_handoff_button.clip_text = true
		_handoff_button.add_theme_font_size_override("font_size", 11)
		_handoff_button.pressed.connect(func() -> void: input_controller.return_selected_cards_to_ai())
		get_node("Margin/Layout/Header").add_child(_handoff_button)
		title_label.visible = true
	_content_signature = ""
	_rebuild_if_needed()


func is_tactical_cards() -> bool:
	return _tactical_cards


func get_overview_height(available_width: float) -> float:
	if _snapshot == null:
		return 220.0
	var local_commanders: Array[CommanderSnapshot] = []
	for commander in _snapshot.commanders:
		if commander.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			local_commanders.append(commander)
	var group_width := (available_width - 20.0 - maxf(0.0, local_commanders.size() - 1) * 8.0) / maxi(1, local_commanders.size())
	var card_columns := maxi(1, floori(group_width / 110.0))
	var card_height := 40.0 if group_width / card_columns >= 110.0 else 48.0
	if card_columns != _overview_card_columns or card_height != _overview_card_height:
		_overview_card_columns = card_columns
		_overview_card_height = card_height
		_content_signature = ""
		_rebuild_if_needed()
	var content_height := 0.0
	for commander in local_commanders:
		var card_rows := ceili(float(commander.subordinate_unit_card_ids.size()) / card_columns)
		var cards_height := float(card_rows) * card_height + maxi(0, card_rows - 1) * 4.0
		content_height = maxf(content_height, 72.0 + cards_height)
	return content_height + 52.0


func _create_tactical_column(commander: CommanderSnapshot) -> BoxContainer:
	var column := BoxContainer.new()
	column.vertical = true
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(details)
	var button := Button.new()
	button.clip_text = true
	button.custom_minimum_size.y = 32.0
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(_select_commander.bind(commander.definition_id))
	button.gui_input.connect(_handle_commander_button_input.bind(commander.definition_id))
	details.add_child(button)
	_commander_buttons[commander.definition_id] = button
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 2)
	details.add_child(controls)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 10)
	status.custom_minimum_size.x = 24.0
	status.clip_text = true
	controls.add_child(status)
	_commander_status_labels[commander.definition_id] = status
	var posture := OptionButton.new()
	posture.fit_to_longest_item = false
	posture.custom_minimum_size.y = 32.0
	posture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	posture.add_theme_font_size_override("font_size", 11)
	for value in range(CommanderState.Posture.size()):
		posture.add_item(GameText.enum_name("COMMANDER_POSTURE", CommanderState.Posture.keys()[value]), value)
	posture.select(commander.posture)
	posture.item_selected.connect(_set_commander_posture.bind(commander.definition_id))
	controls.add_child(posture)
	_posture_menus[commander.definition_id] = posture
	var cards := GridContainer.new()
	cards.columns = _overview_card_columns
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("v_separation", 4)
	cards.add_theme_constant_override("h_separation", 4)
	column.add_child(cards)
	for card_id in commander.subordinate_unit_card_ids:
		var card := _snapshot.get_unit_card(card_id)
		if card == null:
			continue
		var card_button := Button.new()
		card_button.custom_minimum_size.y = _overview_card_height
		card_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_button.clip_text = true
		card_button.toggle_mode = true
		card_button.add_theme_font_size_override("font_size", 11)
		card_button.pressed.connect(_select_unit_card.bind(card_id))
		cards.add_child(card_button)
		_unit_card_buttons[card_id] = card_button
	return column


func _display_strength(card: UnitCardSnapshot) -> int:
	return card.available_strength if card.deployment_state in [UnitCardState.DeploymentState.RESERVE, UnitCardState.DeploymentState.DEPLOYING] else card.current_strength


func _update_tactical_commander(commander: CommanderSnapshot) -> void:
	var button := _commander_buttons.get(commander.definition_id) as Button
	if button == null:
		return
	var menu := _posture_menus.get(commander.definition_id) as OptionButton
	if menu != null and menu.selected != commander.posture and not menu.get_popup().visible and (input_controller == null or input_controller.simulation_host == null or input_controller.simulation_host.get_queue_size() == 0):
		menu.select(commander.posture)
	var strength := 0
	var capacity := 0
	for card_id in commander.subordinate_unit_card_ids:
		var card := _snapshot.get_unit_card(card_id)
		if card != null:
			strength += _display_strength(card)
			capacity += card.authorized_strength
	button.text = "%s %d/%d\n%s" % [GameText.t(commander.display_name_key), strength, capacity, GameText.t(commander.personality_key)]


func _tactical_activity(commander: CommanderSnapshot) -> int:
	var working := false
	for card_id in commander.subordinate_unit_card_ids:
		var card := _snapshot.get_unit_card(card_id)
		if card == null:
			continue
		working = working or card.deployment_state == UnitCardState.DeploymentState.DEPLOYING
		working = working or not card.tactical_ability_id.is_empty() and card.tactical_status_key in [&"TACTICAL_PREPARING", &"TACTICAL_ACTIVE"]
		for unit_id in card.active_member_entity_ids:
			var unit := _snapshot.get_unit(unit_id)
			if unit == null:
				continue
			if unit.is_attacking:
				return 2
			var task := _snapshot.get_task(unit.assigned_task_id)
			working = working or unit.is_moving or (task != null and task.lifecycle in [TaskState.Lifecycle.PREPARING, TaskState.Lifecycle.EXECUTING])
			for enemy in _snapshot.units:
				if enemy.enabled and enemy.faction_id != commander.faction_id and enemy.is_visible_to_local_player and unit.position.distance_squared_to(enemy.position) <= unit.sight_range * unit.sight_range:
					return 2
	if commander.behavior_state_key == &"COMMANDER_BEHAVIOR_ENGAGING":
		return 2
	return 1 if working or not commander.active_intent_id.is_empty() else 0


func get_hover_context(mouse_position: Vector2) -> Dictionary:
	if not _tactical_cards or _snapshot == null:
		return {}
	var open_menu: OptionButton
	for candidate in _posture_menus.values():
		if candidate.get_popup().visible:
			open_menu = candidate
	for commander_id in _posture_menus:
		var menu := _posture_menus[commander_id] as OptionButton
		if open_menu != null and menu != open_menu:
			continue
		var popup := menu.get_popup()
		var index := menu.selected
		if popup.visible:
			if not Rect2(Vector2.ZERO, Vector2(popup.size)).has_point(popup.get_mouse_position()):
				return {}
			index = popup.get_focused_item()
		elif not menu.get_global_rect().has_point(mouse_position):
			continue
		if index >= 0:
			return {"key": "army-posture:%s:%d:%s" % [commander_id, index, popup.visible], "text": TacticalHelp.posture(menu.get_item_id(index)), "avoid": Rect2(popup.position, popup.size) if popup.visible else Rect2(), "anchor": Vector2(popup.position) + Vector2(-18, popup.size.y) if popup.visible else mouse_position}
	for commander_id in _commander_buttons:
		var button := _commander_buttons[commander_id] as Button
		if button.get_global_rect().has_point(mouse_position):
			var commander := _snapshot.get_commander(commander_id)
			return {"key": "army-personality:%s" % commander_id, "text": button.text + "\n" + TacticalHelp.personality(commander.personality_key)}
	for card_id in _unit_card_buttons:
		var button := _unit_card_buttons[card_id] as Button
		if button.get_global_rect().has_point(mouse_position):
			var card := _snapshot.get_unit_card(card_id)
			return {"key": "army-card:%s" % card_id, "text": button.text + "\n" + _unit_card_tooltip(card, _snapshot.get_commander(card.commander_definition_id)) + "\n" + CompositionText.from_snapshot(card)}
	return {}


func has_open_help_popup() -> bool:
	for menu in _posture_menus.values():
		if menu.get_popup().visible:
			return true
	return false
