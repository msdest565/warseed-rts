class_name BattleDebrief
extends CanvasLayer

enum ReviewView {
	TURNING_POINTS,
	CARDS,
	CAUSES,
}

var result_label: Label
var summary_label: Label
var playtest_label: Label
var timeline_button: Button
var cards_button: Button
var causes_button: Button
var rows: VBoxContainer
var fight_again_button: Button
var return_to_operations_button: Button
var feedback_button: Button

var simulation_host: SimulationHost
var _record: Dictionary = {}
var _review: AfterActionReview
var _review_projector := AfterActionReviewProjector.new()
var _active_view: ReviewView = ReviewView.TURNING_POINTS
var _narrow_layout := false
var _compact_actions := false


func _ready() -> void:
	_resolve_nodes()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	_apply_responsive_layout()
	refresh_locale()


func configure(host: SimulationHost) -> void:
	_resolve_nodes()
	simulation_host = host
	refresh_locale()
	if not simulation_host.campaign_concluded.is_connected(show_debrief):
		simulation_host.campaign_concluded.connect(show_debrief)
	if not simulation_host.campaign_record_changed.is_connected(_on_campaign_record_changed):
		simulation_host.campaign_record_changed.connect(_on_campaign_record_changed)
	if not simulation_host.scenario_restarted.is_connected(_on_scenario_restarted):
		simulation_host.scenario_restarted.connect(_on_scenario_restarted)


func show_debrief(record: Dictionary) -> void:
	_resolve_nodes()
	_record = record.duplicate(true)
	var hover_tooltip := get_parent().get_node_or_null("HoverTooltip") as HoverTooltip
	if hover_tooltip != null and hover_tooltip.is_node_ready():
		hover_tooltip.clear()
	visible = true
	_active_view = ReviewView.TURNING_POINTS
	_apply_responsive_layout()
	_refresh()
	if fight_again_button.is_inside_tree():
		fight_again_button.grab_focus()


func refresh_locale() -> void:
	_resolve_nodes()
	var battle_name := GameText.t(simulation_host.world.battle_definition.display_name_key) if simulation_host != null and simulation_host.world != null and simulation_host.world.battle_definition != null else GameText.t(&"GREY_RIDGE_TITLE")
	$Backdrop/Panel/Margin/Layout/Title.text = GameText.t(&"DEBRIEF_TITLE") % battle_name
	$Backdrop/Panel/Margin/Layout/Columns/Card.text = GameText.t(&"DEBRIEF_COLUMN_CARD")
	$Backdrop/Panel/Margin/Layout/Columns/Strength.text = GameText.t(&"DEBRIEF_COLUMN_STRENGTH")
	$Backdrop/Panel/Margin/Layout/Columns/Actions.text = GameText.t(&"DEBRIEF_COLUMN_ACTIONS")
	timeline_button.text = GameText.t(&"DEBRIEF_VIEW_TIMELINE")
	cards_button.text = GameText.t(&"DEBRIEF_VIEW_CARDS")
	causes_button.text = GameText.t(&"DEBRIEF_VIEW_CAUSES")
	fight_again_button.text = GameText.t(&"DEBRIEF_FIGHT_AGAIN")
	return_to_operations_button.text = GameText.t(&"RETURN_TO_OPERATIONS")
	feedback_button.text = GameText.t(&"DEBRIEF_PROVIDE_FEEDBACK")
	if visible and not _record.is_empty():
		_refresh()


func _resolve_nodes() -> void:
	result_label = get_node("Backdrop/Panel/Margin/Layout/Result") as Label
	summary_label = get_node("Backdrop/Panel/Margin/Layout/Summary") as Label
	playtest_label = get_node("Backdrop/Panel/Margin/Layout/PlaytestSummary") as Label
	timeline_button = get_node("Backdrop/Panel/Margin/Layout/ViewTabs/Timeline") as Button
	cards_button = get_node("Backdrop/Panel/Margin/Layout/ViewTabs/Cards") as Button
	causes_button = get_node("Backdrop/Panel/Margin/Layout/ViewTabs/Causes") as Button
	rows = get_node("Backdrop/Panel/Margin/Layout/RowsScroll/Rows") as VBoxContainer
	fight_again_button = get_node("Backdrop/Panel/Margin/Layout/Footer/FightAgain") as Button
	return_to_operations_button = get_node("Backdrop/Panel/Margin/Layout/Footer/ReturnToOperations") as Button
	feedback_button = get_node("Backdrop/Panel/Margin/Layout/Footer/Feedback") as Button
	if not fight_again_button.pressed.is_connected(_on_fight_again_pressed):
		fight_again_button.pressed.connect(_on_fight_again_pressed)
	if not return_to_operations_button.pressed.is_connected(_on_return_to_operations_pressed):
		return_to_operations_button.pressed.connect(_on_return_to_operations_pressed)
	if not feedback_button.pressed.is_connected(_on_feedback_pressed):
		feedback_button.pressed.connect(_on_feedback_pressed)
	if not timeline_button.pressed.is_connected(_on_review_view_pressed.bind(ReviewView.TURNING_POINTS)):
		timeline_button.pressed.connect(_on_review_view_pressed.bind(ReviewView.TURNING_POINTS))
	if not cards_button.pressed.is_connected(_on_review_view_pressed.bind(ReviewView.CARDS)):
		cards_button.pressed.connect(_on_review_view_pressed.bind(ReviewView.CARDS))
	if not causes_button.pressed.is_connected(_on_review_view_pressed.bind(ReviewView.CAUSES)):
		causes_button.pressed.connect(_on_review_view_pressed.bind(ReviewView.CAUSES))


func _refresh() -> void:
	if _record.is_empty():
		return
	_apply_responsive_layout()
	var result_key := String(_record.get("last_result", "defeat"))
	if result_key == "victory":
		result_label.text = GameText.t(&"GREY_RIDGE_VICTORY")
		result_label.modulate = Color(0.42, 0.86, 0.68)
	elif result_key == "ordered_withdrawal":
		result_label.text = GameText.t(&"BATTLE_OUTCOME_ORDERED_WITHDRAWAL")
		result_label.modulate = Color(0.88, 0.76, 0.38)
	else:
		result_label.text = GameText.t(&"GREY_RIDGE_DEFEAT")
		result_label.modulate = Color(1.0, 0.48, 0.38)
	summary_label.text = GameText.t(&"DEBRIEF_SUMMARY") % [
		int(_record.get("last_replacement_award", 0)),
		int(_record.get("last_merit_award", 0)),
		int(_record.get("replacement_points", 0)),
		int(_record.get("merit", 0)),
		int(_record.get("campaign_days", 0)),
	]
	_refresh_playtest_summary()
	_review = null
	if simulation_host != null:
		var source_report := simulation_host.get_gameplay_observability_report()
		if not source_report.is_empty():
			_review = _review_projector.project(source_report, SimulationWorld.LOCAL_PLAYER_ID)
	if _review == null:
		_active_view = ReviewView.CARDS
	_refresh_review_rows()


func _refresh_review_rows() -> void:
	for child in rows.get_children():
		child.queue_free()
	_update_view_buttons()
	var columns := get_node("Backdrop/Panel/Margin/Layout/Columns") as Control
	columns.visible = _active_view == ReviewView.CARDS and not _narrow_layout
	match _active_view:
		ReviewView.TURNING_POINTS:
			_refresh_turning_points()
		ReviewView.CAUSES:
			_refresh_causes()
		_:
			_refresh_card_rows()


func _refresh_card_rows() -> void:
	var card_records := _record.get("cards", {}) as Dictionary
	var card_ids: Array[StringName] = []
	if simulation_host != null and simulation_host.current_snapshot != null:
		for card in simulation_host.current_snapshot.unit_cards:
			if card.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
				card_ids.append(card.definition_id)
	if card_ids.is_empty():
		for key in card_records:
			card_ids.append(StringName(key))
		card_ids.sort_custom(func(left: StringName, right: StringName) -> bool:
			return String(left) < String(right)
		)
	for card_id in card_ids:
		var card_record := card_records.get(String(card_id), {}) as Dictionary
		if not card_record.is_empty():
			rows.add_child(_create_card_row(card_id, card_record))


func _refresh_turning_points() -> void:
	if _review == null or _review.turning_points.is_empty():
		rows.add_child(_create_empty_review_label(&"AFTER_ACTION_NO_TIMELINE"))
		return
	for entry in _review.turning_points:
		rows.add_child(_create_turning_point_row(entry))


func _refresh_causes() -> void:
	if _review == null or _review.causes.is_empty():
		rows.add_child(_create_empty_review_label(&"AFTER_ACTION_NO_CAUSES"))
		return
	for entry in _review.causes:
		rows.add_child(_create_cause_row(entry))


func _create_empty_review_label(key: StringName) -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(0.0, 54.0)
	label.text = GameText.t(key)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.62, 0.69, 0.67))
	return label


func _create_turning_point_row(entry: AfterActionTurningPoint) -> Control:
	var row := BoxContainer.new()
	row.set_meta(&"turning_point_id", String(entry.stable_id))
	row.vertical = _narrow_layout
	row.custom_minimum_size = Vector2(0.0, 76.0 if _narrow_layout else 58.0)
	row.add_theme_constant_override("separation", 10)
	var time_label := Label.new()
	time_label.custom_minimum_size = Vector2(76.0, 0.0)
	time_label.text = _format_tick(entry.first_tick)
	time_label.add_theme_color_override("font_color", Color(0.96, 0.78, 0.28))
	row.add_child(time_label)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 2)
	var summary := Label.new()
	summary.text = _turning_point_text(entry)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", Color(0.91, 0.94, 0.9))
	detail.add_child(summary)
	var source := Label.new()
	source.text = GameText.t(&"AFTER_ACTION_SOURCE") % [String(entry.source_event), _turning_point_subject(entry)]
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source.add_theme_font_size_override("font_size", 10)
	source.add_theme_color_override("font_color", Color(0.55, 0.68, 0.65))
	detail.add_child(source)
	row.add_child(detail)
	return row


func _turning_point_text(entry: AfterActionTurningPoint) -> String:
	match String(entry.reason_key):
		"first_high_level_order":
			return GameText.t(&"AFTER_ACTION_EVENT_FIRST_ORDER") % entry.result
		"player_correction":
			return GameText.t(&"AFTER_ACTION_EVENT_CORRECTION") % entry.result
		"region_control_changed":
			return GameText.t(&"AFTER_ACTION_EVENT_REGION") % entry.result
		"building_destroyed":
			return GameText.t(&"AFTER_ACTION_EVENT_BUILDING") % entry.result
		"unit_card_loss":
			return GameText.t(&"AFTER_ACTION_EVENT_LOSS") % [_card_display_name(entry.unit_card_id), entry.occurrences]
		"task_state_changed":
			return GameText.t(&"AFTER_ACTION_EVENT_TASK") % [entry.task_id, entry.result]
		"exception_opened", "exception_reopened":
			return GameText.t(&"AFTER_ACTION_EVENT_EXCEPTION") % entry.result
		"exception_action":
			return GameText.t(&"AFTER_ACTION_EVENT_EXCEPTION_ACTION") % entry.result
		"supply_committed":
			return GameText.t(&"AFTER_ACTION_EVENT_SUPPLY") % entry.result
		"unit_card_takeover":
			return GameText.t(&"AFTER_ACTION_EVENT_TAKEOVER") % _card_display_name(entry.unit_card_id)
		"unit_card_return_result":
			return GameText.t(&"AFTER_ACTION_EVENT_RETURN") % [_card_display_name(entry.unit_card_id), entry.result]
		"battle_concluded":
			return GameText.t(&"AFTER_ACTION_EVENT_CONCLUDED") % entry.result
	return GameText.t(&"AFTER_ACTION_EVENT_GENERIC") % [String(entry.reason_key), entry.result]


func _turning_point_subject(entry: AfterActionTurningPoint) -> String:
	var parts: Array[String] = []
	if not entry.unit_card_id.is_empty():
		parts.append(_card_display_name(entry.unit_card_id))
	if entry.task_id != 0:
		parts.append(GameText.t(&"AFTER_ACTION_TASK_ID") % entry.task_id)
	if entry.occurrences > 1:
		parts.append(GameText.t(&"AFTER_ACTION_OCCURRENCES") % entry.occurrences)
	if parts.is_empty():
		parts.append(entry.actor_id)
	return " | ".join(parts)


func _create_cause_row(entry: AfterActionCause) -> Control:
	var row := VBoxContainer.new()
	row.set_meta(&"cause_id", String(entry.stable_id))
	row.custom_minimum_size = Vector2(0.0, 68.0)
	row.add_theme_constant_override("separation", 3)
	var title := Label.new()
	title.text = GameText.t(&"AFTER_ACTION_PRIMARY_CAUSE" if entry.role == AfterActionCause.Role.PRIMARY else &"AFTER_ACTION_SUPPORTING_CAUSE")
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(0.96, 0.78, 0.28) if entry.role == AfterActionCause.Role.PRIMARY else Color(0.35, 0.78, 0.72))
	row.add_child(title)
	var detail := Label.new()
	detail.text = _cause_text(entry)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", Color(0.91, 0.94, 0.9))
	row.add_child(detail)
	var source := Label.new()
	source.text = GameText.t(&"AFTER_ACTION_CAUSE_SOURCE") % [_format_tick(entry.source_tick), String(entry.source_event), String(entry.reason_key)]
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source.add_theme_font_size_override("font_size", 10)
	source.add_theme_color_override("font_color", Color(0.55, 0.68, 0.65))
	row.add_child(source)
	return row


func _cause_text(entry: AfterActionCause) -> String:
	match String(entry.kind):
		"outcome":
			var objectives := entry.facts.get("reason_objective_ids", []) as Array
			return GameText.t(&"AFTER_ACTION_CAUSE_OUTCOME") % [entry.facts.get("result", ""), entry.facts.get("conclusion_group_id", ""), ", ".join(objectives)]
		"task_blocked":
			return GameText.t(&"AFTER_ACTION_CAUSE_TASK_BLOCKED") % [entry.task_id, _card_display_name(entry.unit_card_id), entry.facts.get("blocked_count", 0), entry.facts.get("blocked_reason", "")]
		"card_attrition":
			return GameText.t(&"AFTER_ACTION_CAUSE_CARD_ATTRITION") % [_card_display_name(entry.unit_card_id), entry.facts.get("losses", 0), entry.facts.get("initial_strength", 0), entry.facts.get("final_strength", 0)]
		"unresolved_exception":
			return GameText.t(&"AFTER_ACTION_CAUSE_UNRESOLVED_EXCEPTION") % [entry.facts.get("exception_id", ""), _card_display_name(entry.unit_card_id)]
		"task_completion_shortfall":
			return GameText.t(&"AFTER_ACTION_CAUSE_NO_COMPLETED_TASKS") % [entry.facts.get("completed", 0), entry.facts.get("created", 0), entry.facts.get("blocked", 0)]
	return GameText.t(&"AFTER_ACTION_CAUSE_GENERIC") % String(entry.kind)


func _format_tick(tick: int) -> String:
	var total_seconds := maxi(0, tick) / 10
	return "T+%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func _on_review_view_pressed(view: ReviewView) -> void:
	_active_view = view
	_refresh_review_rows()


func _update_view_buttons() -> void:
	timeline_button.button_pressed = _active_view == ReviewView.TURNING_POINTS
	cards_button.button_pressed = _active_view == ReviewView.CARDS
	causes_button.button_pressed = _active_view == ReviewView.CAUSES


func _refresh_playtest_summary() -> void:
	var summary := simulation_host.get_playtest_summary() if simulation_host != null else {}
	if summary.is_empty():
		playtest_label.text = GameText.t(&"DEBRIEF_PLAYTEST_UNAVAILABLE")
		return
	var direct_control_percent := roundi(float(summary.get("direct_control_ratio", 0.0)) * 100.0)
	playtest_label.text = GameText.t(&"DEBRIEF_PLAYTEST_SUMMARY") % [
		_format_seconds(float(summary.get("prebattle_duration_seconds", 0.0))),
		int(summary.get("prebattle_plan_changes", 0)),
		int(summary.get("prebattle_invalid_plan_changes", 0)),
		_format_seconds(float(summary.get("first_commander_command_seconds", -1.0))),
		_format_seconds(float(summary.get("first_unit_card_command_seconds", -1.0))),
		float(summary.get("replans_per_minute", 0.0)),
		_format_seconds(float(summary.get("average_intel_action_delay_seconds", -1.0))),
		direct_control_percent,
		int(summary.get("takeovers", 0)),
		int(summary.get("returns_to_commander", 0)),
		int(summary.get("diagnostic_individual_mode_activations", 0)),
	]
	var record_path := simulation_host.get_playtest_record_path()
	playtest_label.tooltip_text = GameText.t(&"DEBRIEF_PLAYTEST_RECORD_PATH") % record_path if not record_path.is_empty() else GameText.t(&"DEBRIEF_PLAYTEST_MEMORY_ONLY")


func _format_seconds(value: float) -> String:
	return GameText.t(&"DEBRIEF_PLAYTEST_NOT_RECORDED") if value < 0.0 else GameText.t(&"DEBRIEF_PLAYTEST_SECONDS") % value


func _create_card_row(card_id: StringName, card_record: Dictionary) -> Control:
	var row := BoxContainer.new()
	row.set_meta(&"unit_card_id", String(card_id))
	row.vertical = _narrow_layout
	row.custom_minimum_size = Vector2(0.0, 174.0 if _compact_actions else (108.0 if _narrow_layout else 54.0))
	row.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(0.0 if _narrow_layout else 210.0, 0.0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = _card_display_name(card_id)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_color_override("font_color", Color(0.91, 0.94, 0.9))
	row.add_child(name_label)

	var strength_label := Label.new()
	strength_label.custom_minimum_size = Vector2(0.0 if _narrow_layout else 190.0, 0.0)
	strength_label.text = GameText.t(&"DEBRIEF_STRENGTH") % [
		int(card_record.get("available_strength", 0)),
		int(card_record.get("authorized_strength", 0)),
		int(card_record.get("last_battle_losses", 0)),
	]
	var contribution := _review_card(card_id)
	if contribution != null:
		strength_label.text += "\n" + GameText.t(&"AFTER_ACTION_CARD_METRICS") % [
			roundi(contribution.damage_dealt), contribution.kills,
			contribution.tasks_completed, contribution.tasks_blocked,
		]
	strength_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strength_label.add_theme_color_override("font_color", Color(0.72, 0.79, 0.76))
	row.add_child(strength_label)

	var actions := BoxContainer.new()
	actions.vertical = _compact_actions
	actions.custom_minimum_size = Vector2(0.0 if _narrow_layout else 520.0, 0.0)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 7)
	row.add_child(actions)

	var replacement_cost := ArmyRosterStore.replacement_cost(_record, card_id)
	var affordable_replacements := ArmyRosterStore.affordable_replacements(_record, card_id)
	var replenish := Button.new()
	replenish.custom_minimum_size = Vector2(0.0 if _compact_actions else 108.0, 36.0)
	replenish.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact_actions else Control.SIZE_SHRINK_BEGIN
	replenish.text = GameText.t(&"DEBRIEF_REPLENISH") % [affordable_replacements, replacement_cost]
	replenish.tooltip_text = GameText.t(&"DEBRIEF_REPLENISH_TOOLTIP") % replacement_cost
	replenish.disabled = affordable_replacements <= 0
	replenish.pressed.connect(_on_replenish_pressed.bind(card_id))
	actions.add_child(replenish)

	var honor := MenuButton.new()
	honor.custom_minimum_size = Vector2(0.0 if _compact_actions else 180.0, 36.0)
	honor.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact_actions else Control.SIZE_SHRINK_BEGIN
	var has_honor := not String(card_record.get("honor_id", "")).is_empty()
	_configure_growth_menu(honor, card_id, card_record, ArmyRosterStore.GROWTH_KIND_HONOR, StringName(card_record.get("honor_id", "")))
	honor.disabled = has_honor or not _has_available_growth(card_id, ArmyRosterStore.GROWTH_KIND_HONOR)
	actions.add_child(honor)

	var equipment := MenuButton.new()
	equipment.custom_minimum_size = Vector2(0.0 if _compact_actions else 205.0, 36.0)
	equipment.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact_actions else Control.SIZE_SHRINK_BEGIN
	var has_equipment := not String(card_record.get("equipment_id", "")).is_empty()
	_configure_growth_menu(equipment, card_id, card_record, ArmyRosterStore.GROWTH_KIND_EQUIPMENT, StringName(card_record.get("equipment_id", "")))
	equipment.disabled = has_equipment or not _has_available_growth(card_id, ArmyRosterStore.GROWTH_KIND_EQUIPMENT)
	actions.add_child(equipment)
	return row


func _review_card(card_id: StringName) -> AfterActionCardContribution:
	if _review == null:
		return null
	for entry in _review.card_contributions:
		if entry.unit_card_id == card_id:
			return entry
	return null


func _configure_growth_menu(menu: MenuButton, card_id: StringName, card_record: Dictionary, kind: int, active_id: StringName) -> void:
	var active: Variant = ArmyRosterStore.GROWTH_CATALOG.get_growth(active_id)
	menu.text = GameText.t(active.display_name_key) if active != null else GameText.t(&"GROWTH_CHOOSE_HONOR" if kind == ArmyRosterStore.GROWTH_KIND_HONOR else &"GROWTH_CHOOSE_EQUIPMENT")
	if active != null:
		menu.tooltip_text = _growth_tooltip(active)
		return
	var popup := menu.get_popup()
	var definitions := ArmyRosterStore.GROWTH_CATALOG.get_by_kind(kind)
	for index in range(definitions.size()):
		var definition: Variant = definitions[index]
		popup.add_item(GameText.t(&"GROWTH_OPTION_COST") % [GameText.t(definition.display_name_key), definition.merit_cost, definition.replacement_cost, definition.refit_days], index)
		popup.set_item_metadata(index, String(definition.definition_id))
		popup.set_item_tooltip(index, _growth_tooltip(definition))
		popup.set_item_disabled(index, not ArmyRosterStore.can_apply_growth(_record, card_id, definition.definition_id))
	popup.id_pressed.connect(_on_growth_selected.bind(card_id, menu))
	menu.tooltip_text = GameText.t(&"GROWTH_MENU_TOOLTIP")


func _growth_tooltip(definition) -> String:
	return GameText.t(&"GROWTH_DETAIL") % [
		GameText.t(definition.benefit_key),
		GameText.t(definition.tradeoff_key),
		definition.merit_cost,
		definition.replacement_cost,
		definition.refit_days,
	]


func _has_available_growth(card_id: StringName, kind: int) -> bool:
	for definition in ArmyRosterStore.GROWTH_CATALOG.get_by_kind(kind):
		if ArmyRosterStore.can_apply_growth(_record, card_id, definition.definition_id):
			return true
	return false


func _card_display_name(card_id: StringName) -> String:
	if simulation_host != null and simulation_host.current_snapshot != null:
		var card := simulation_host.current_snapshot.get_unit_card(card_id)
		if card != null:
			return GameText.t(card.display_name_key)
	return String(card_id).replace("_", " ").capitalize()


func _on_replenish_pressed(card_id: StringName) -> void:
	if simulation_host != null:
		simulation_host.replenish_unit_card_as_much_as_possible(card_id)


func _on_growth_selected(item_id: int, card_id: StringName, menu: MenuButton) -> void:
	var growth_id := StringName(menu.get_popup().get_item_metadata(item_id))
	if simulation_host != null:
		simulation_host.apply_unit_card_growth(card_id, growth_id)


func _on_fight_again_pressed() -> void:
	if simulation_host != null:
		simulation_host.restart_grey_ridge()


func _on_return_to_operations_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/battle_selector.tscn")


func _on_feedback_pressed() -> void:
	var dialog := get_parent().get_node_or_null("PlaytestFeedbackDialog") as PlaytestFeedbackDialog
	if dialog != null:
		dialog.open_feedback(_record)


func _on_campaign_record_changed(record: Dictionary) -> void:
	_record = record.duplicate(true)
	if visible:
		_refresh()


func _on_scenario_restarted(_snapshot: WorldSnapshot) -> void:
	visible = false


func _on_viewport_size_changed() -> void:
	var previous_narrow := _narrow_layout
	var previous_compact := _compact_actions
	_apply_responsive_layout()
	if visible and not _record.is_empty() and (previous_narrow != _narrow_layout or previous_compact != _compact_actions):
		_refresh()


func _apply_responsive_layout() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	var viewport_width: float = viewport.get_visible_rect().size.x if viewport != null else 1280.0
	_narrow_layout = viewport_width < 900.0
	_compact_actions = viewport_width < 620.0
	var panel := get_node("Backdrop/Panel") as Control
	var inset := 8.0 if _narrow_layout else 24.0
	panel.offset_left = inset
	panel.offset_top = inset
	panel.offset_right = -inset
	panel.offset_bottom = -inset
	var margin := get_node("Backdrop/Panel/Margin") as MarginContainer
	var horizontal_margin := 10 if _narrow_layout else 28
	var vertical_margin := 10 if _narrow_layout else 22
	margin.add_theme_constant_override("margin_left", horizontal_margin)
	margin.add_theme_constant_override("margin_right", horizontal_margin)
	margin.add_theme_constant_override("margin_top", vertical_margin)
	margin.add_theme_constant_override("margin_bottom", vertical_margin)
	var columns := get_node("Backdrop/Panel/Margin/Layout/Columns") as Control
	columns.visible = _active_view == ReviewView.CARDS and not _narrow_layout
	var summary := get_node("Backdrop/Panel/Margin/Layout/Summary") as Label
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var playtest_summary := get_node("Backdrop/Panel/Margin/Layout/PlaytestSummary") as Label
	playtest_summary.custom_minimum_size.y = 72.0 if _narrow_layout else 54.0
	var result := get_node("Backdrop/Panel/Margin/Layout/Result") as Label
	result.add_theme_font_size_override("font_size", 24 if _narrow_layout else 30)
	var rows_scroll := get_node("Backdrop/Panel/Margin/Layout/RowsScroll") as ScrollContainer
	rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
