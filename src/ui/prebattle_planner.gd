class_name PrebattlePlanner
extends CanvasLayer

var simulation_host: SimulationHost
var start_button: Button
var validation_label: Label
var commander_grid: GridContainer
var unit_card_grid: GridContainer
var roster_summary_label: Label
var reset_campaign_button: Button
var roster_bar: BoxContainer
var roster_status: RosterStatusPanel
var tutorial_toggle: CheckButton

var _plan: ArmyPlan = ArmyPlan.grey_ridge_default()
var _capacity_labels: Dictionary = {}
var _readiness_labels: Dictionary = {}
var _personality_labels: Dictionary = {}
var _doctrine_menus: Dictionary = {}
var _posture_menus: Dictionary = {}
var _tactical_detail_labels: Dictionary = {}
var _built := false
var _prebattle_started_msec: int = 0
var _plan_change_count: int = 0
var _invalid_plan_change_count: int = 0
var _commander_definitions: Array[CommanderDefinition] = []
var _unit_card_definitions: Array[UnitCardDefinition] = []
var _doctrine_definitions: Dictionary = {}


func _ready() -> void:
	_build_ui()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.connect(_apply_responsive_layout)
	refresh_locale()


func configure(host: SimulationHost) -> void:
	_build_ui()
	simulation_host = host
	if simulation_host == null:
		return
	if roster_status == null:
		roster_status = RosterStatusPanel.new()
		roster_bar.get_parent().add_child(roster_status)
		roster_bar.get_parent().move_child(roster_status, roster_bar.get_index() + 1)
	roster_status.configure(host)
	if not host.campaign_persistence_changed.is_connected(_refresh_validity):
		host.campaign_persistence_changed.connect(_refresh_validity)
	var battle := simulation_host.world.battle_definition
	if battle != null:
		_commander_definitions.assign(battle.commander_definitions)
		_unit_card_definitions.assign(battle.unit_card_definitions)
		_doctrine_definitions = battle.doctrine_dictionary()
	_plan = simulation_host.get_grey_ridge_army_plan()
	if not simulation_host.grey_ridge_prebattle_opened.is_connected(open_prebattle):
		simulation_host.grey_ridge_prebattle_opened.connect(open_prebattle)
	if not simulation_host.grey_ridge_battle_started.is_connected(_on_battle_started):
		simulation_host.grey_ridge_battle_started.connect(_on_battle_started)
	if not simulation_host.campaign_record_changed.is_connected(_on_campaign_record_changed):
		simulation_host.campaign_record_changed.connect(_on_campaign_record_changed)
	visible = SimulationWorld.is_card_battle_kind(simulation_host.scenario_kind) and not simulation_host.is_grey_ridge_battle_started()
	if visible:
		_begin_prebattle_metrics()
	_rebuild_content()


func open_prebattle(plan: ArmyPlan) -> void:
	_plan = plan.duplicate_plan() if plan != null else _default_plan()
	_begin_prebattle_metrics()
	visible = true
	_rebuild_content()


func refresh_locale() -> void:
	if not _built:
		return
	_rebuild_content()
	if roster_status != null:
		roster_status.refresh()


func get_plan() -> ArmyPlan:
	return _plan.duplicate_plan()


func is_plan_valid() -> bool:
	return _validation_errors().is_empty()


func set_unit_card_commander(unit_card_id: StringName, commander_id: StringName) -> void:
	if (_plan.commander_by_unit_card.get(unit_card_id, &"") as StringName) == commander_id:
		return
	_plan.set_unit_card_commander(unit_card_id, commander_id)
	_record_plan_change()
	_rebuild_content()


func set_unit_card_starting(unit_card_id: StringName, starts_deployed: bool) -> void:
	if _plan.is_unit_card_starting(unit_card_id) == starts_deployed:
		return
	_plan.set_unit_card_starting(unit_card_id, starts_deployed)
	_record_plan_change()
	_rebuild_content()


func set_commander_doctrine(commander_id: StringName, doctrine_id: StringName) -> void:
	if (_plan.doctrine_by_commander.get(commander_id, &"") as StringName) == doctrine_id:
		return
	_plan.set_commander_doctrine(commander_id, doctrine_id)
	_record_plan_change()
	_rebuild_content()


func set_commander_posture(commander_id: StringName, posture: CommanderState.Posture) -> void:
	if int(_plan.posture_by_commander.get(commander_id, -1)) == posture:
		return
	_plan.set_commander_posture(commander_id, posture)
	_record_plan_change()
	_rebuild_content()


func get_capacity_text(commander_id: StringName) -> String:
	var label := _capacity_labels.get(commander_id) as Label
	return label.text if label != null else ""


func _build_ui() -> void:
	if _built:
		return
	_built = true
	layer = 80

	var backdrop := PanelContainer.new()
	backdrop.name = "Backdrop"
	backdrop.add_theme_stylebox_override("panel", _panel_style(Color(0.31, 0.48, 0.45)))
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	backdrop.add_child(margin)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var header := BoxContainer.new()
	header.name = "Header"
	layout.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.96, 0.78, 0.28))
	header.add_child(title)
	var operation := Label.new()
	operation.name = "Operation"
	operation.custom_minimum_size.x = 240.0
	operation.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	operation.add_theme_font_size_override("font_size", 13)
	operation.add_theme_color_override("font_color", Color(0.46, 0.78, 0.69))
	header.add_child(operation)

	var objective := Label.new()
	objective.name = "Objective"
	objective.add_theme_font_size_override("font_size", 12)
	objective.add_theme_color_override("font_color", Color(0.68, 0.73, 0.71))
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(objective)
	layout.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	roster_bar = BoxContainer.new()
	roster_bar.name = "RosterBar"
	roster_bar.add_theme_constant_override("separation", 8)
	content.add_child(roster_bar)
	roster_summary_label = Label.new()
	roster_summary_label.name = "RosterSummary"
	roster_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster_summary_label.add_theme_color_override("font_color", Color(0.55, 0.78, 0.72))
	roster_bar.add_child(roster_summary_label)
	tutorial_toggle = CheckButton.new()
	tutorial_toggle.name = "TutorialToggle"
	tutorial_toggle.custom_minimum_size = Vector2(170.0, 32.0)
	tutorial_toggle.toggled.connect(_on_tutorial_toggled)
	roster_bar.add_child(tutorial_toggle)
	reset_campaign_button = Button.new()
	reset_campaign_button.name = "ResetCampaign"
	reset_campaign_button.custom_minimum_size = Vector2(170.0, 32.0)
	reset_campaign_button.pressed.connect(_reset_campaign_progress)
	roster_bar.add_child(reset_campaign_button)

	var commander_title := Label.new()
	commander_title.name = "CommanderTitle"
	commander_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	commander_title.add_theme_font_size_override("font_size", 14)
	commander_title.add_theme_color_override("font_color", Color(0.84, 0.89, 0.86))
	content.add_child(commander_title)
	commander_grid = GridContainer.new()
	commander_grid.name = "CommanderGrid"
	commander_grid.columns = 1
	commander_grid.add_theme_constant_override("h_separation", 8)
	commander_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(commander_grid)

	var card_title := Label.new()
	card_title.name = "UnitCardTitle"
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_title.add_theme_font_size_override("font_size", 14)
	card_title.add_theme_color_override("font_color", Color(0.84, 0.89, 0.86))
	content.add_child(card_title)
	unit_card_grid = GridContainer.new()
	unit_card_grid.name = "UnitCardGrid"
	unit_card_grid.columns = 1
	unit_card_grid.add_theme_constant_override("h_separation", 8)
	unit_card_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(unit_card_grid)

	var footer := BoxContainer.new()
	footer.name = "Footer"
	footer.custom_minimum_size.y = 42.0
	footer.add_theme_constant_override("separation", 10)
	layout.add_child(footer)
	var reset_button := Button.new()
	reset_button.name = "Reset"
	reset_button.custom_minimum_size = Vector2(128.0, 36.0)
	reset_button.pressed.connect(_reset_plan)
	footer.add_child(reset_button)
	validation_label = Label.new()
	validation_label.name = "Validation"
	validation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(validation_label)
	start_button = Button.new()
	start_button.name = "StartBattle"
	start_button.custom_minimum_size = Vector2(210.0, 38.0)
	start_button.add_theme_font_size_override("font_size", 14)
	start_button.pressed.connect(_start_battle)
	footer.add_child(start_button)

	_apply_responsive_layout()


func _rebuild_content() -> void:
	if not _built:
		return
	var battle := simulation_host.world.battle_definition if simulation_host != null else null
	var battle_name := GameText.t(battle.display_name_key) if battle != null else GameText.t(&"GREY_RIDGE_TITLE")
	var starting_count := battle.starting_card_count if battle != null else ArmyPlan.STARTING_CARD_COUNT
	var limit_minutes := ceili(float(battle.time_limit_ticks if battle != null else SimulationWorld.GREY_RIDGE_TIME_LIMIT_TICKS) * SimulationWorld.TICK_SECONDS / 60.0)
	get_node("Backdrop/Margin/Layout/Header/Title").text = GameText.t(&"PREBATTLE_TITLE_GENERIC") % battle_name
	get_node("Backdrop/Margin/Layout/Header/Operation").text = String(battle.scenario_id).to_upper() if battle != null else GameText.t(&"PREBATTLE_OPERATION")
	get_node("Backdrop/Margin/Layout/Objective").text = GameText.t(&"PREBATTLE_OBJECTIVE_GENERIC") % limit_minutes
	get_node("Backdrop/Margin/Layout/Scroll/Content/CommanderTitle").text = GameText.t(&"PREBATTLE_COMMANDERS")
	get_node("Backdrop/Margin/Layout/Scroll/Content/UnitCardTitle").text = GameText.t(&"PREBATTLE_UNIT_CARDS_GENERIC") % starting_count
	get_node("Backdrop/Margin/Layout/Footer/Reset").text = GameText.t(&"PREBATTLE_RESET")
	start_button.text = GameText.t(&"PREBATTLE_START")
	reset_campaign_button.text = GameText.t(&"PREBATTLE_RESET_CAMPAIGN")
	reset_campaign_button.tooltip_text = GameText.t(&"PREBATTLE_RESET_CAMPAIGN_TOOLTIP")
	tutorial_toggle.text = GameText.t(&"PREBATTLE_TUTORIAL_TOGGLE")
	tutorial_toggle.tooltip_text = GameText.t(&"PREBATTLE_TUTORIAL_TOOLTIP")
	tutorial_toggle.set_pressed_no_signal(TutorialProgressStore.is_scenario_enabled(_tutorial_scenario_id()))
	var campaign_record := simulation_host.get_campaign_record() if simulation_host != null else {}
	roster_summary_label.text = GameText.t(&"PREBATTLE_ROSTER_SUMMARY") % [
		int(campaign_record.get("replacement_points", 0)),
		int(campaign_record.get("merit", 0)),
		int(campaign_record.get("battle_count", 0)),
	]
	reset_campaign_button.disabled = campaign_record.is_empty() and (simulation_host == null or not simulation_host.has_campaign_error())
	_clear_container(commander_grid)
	_clear_container(unit_card_grid)
	_capacity_labels.clear()
	_readiness_labels.clear()
	_personality_labels.clear()
	_doctrine_menus.clear()
	_posture_menus.clear()
	_tactical_detail_labels.clear()
	for definition in _commander_definitions:
		commander_grid.add_child(_create_commander_panel(definition as CommanderDefinition))
	for definition in _unit_card_definitions:
		unit_card_grid.add_child(_create_unit_card_panel(definition as UnitCardDefinition))
	_refresh_validity()
	_apply_responsive_layout()


func _create_commander_panel(definition: CommanderDefinition) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0.0, 252.0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.22, 0.42, 0.39)))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = GameText.t(definition.display_name_key)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.92))
	header.add_child(name_label)
	var capacity := Label.new()
	capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	capacity.add_theme_font_size_override("font_size", 12)
	layout.add_child(capacity)
	_capacity_labels[definition.definition_id] = capacity
	var personality := Label.new()
	personality.name = "Personality"
	personality.text = GameText.t(&"PREBATTLE_PERSONALITY") % GameText.t(definition.personality_key)
	personality.tooltip_text = GameText.t(&"PREBATTLE_PERSONALITY_TOOLTIP") % [
		GameText.t(definition.personality_key),
		GameText.t(StringName("%s_TOOLTIP" % String(definition.personality_key))),
	]
	personality.add_theme_color_override("font_color", Color(0.61, 0.7, 0.67))
	layout.add_child(personality)
	_personality_labels[definition.definition_id] = personality
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	layout.add_child(controls)
	var doctrine_label := Label.new()
	doctrine_label.name = "DoctrineLabel"
	doctrine_label.text = GameText.t(&"PREBATTLE_DOCTRINE_FIELD")
	doctrine_label.tooltip_text = GameText.t(&"PREBATTLE_DOCTRINE_FIELD_TOOLTIP")
	doctrine_label.add_theme_font_size_override("font_size", 11)
	doctrine_label.add_theme_color_override("font_color", Color(0.48, 0.82, 0.7))
	controls.add_child(doctrine_label)
	var doctrine_menu := OptionButton.new()
	doctrine_menu.fit_to_longest_item = false
	doctrine_menu.clip_text = true
	doctrine_menu.name = "Doctrine"
	doctrine_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for doctrine_id in definition.available_doctrine_ids:
		var doctrine := _doctrine_definitions.get(doctrine_id) as DoctrineDefinition
		doctrine_menu.add_item(GameText.t(doctrine.display_name_key))
		var doctrine_index := doctrine_menu.item_count - 1
		doctrine_menu.set_item_metadata(doctrine_index, doctrine_id)
		doctrine_menu.get_popup().set_item_tooltip(doctrine_index, _doctrine_tooltip(doctrine))
	var selected_doctrine: StringName = _plan.doctrine_by_commander.get(definition.definition_id, &"")
	for index in range(doctrine_menu.item_count):
		if doctrine_menu.get_item_metadata(index) as StringName == selected_doctrine:
			doctrine_menu.select(index)
			doctrine_menu.tooltip_text = _doctrine_tooltip(_doctrine_definitions.get(selected_doctrine) as DoctrineDefinition)
			break
	doctrine_menu.item_selected.connect(_on_doctrine_selected.bind(definition.definition_id, doctrine_menu))
	controls.add_child(doctrine_menu)
	_doctrine_menus[definition.definition_id] = doctrine_menu
	var posture_label := Label.new()
	posture_label.name = "PostureLabel"
	posture_label.text = GameText.t(&"PREBATTLE_POSTURE_FIELD")
	posture_label.tooltip_text = GameText.t(&"PREBATTLE_POSTURE_FIELD_TOOLTIP")
	posture_label.add_theme_font_size_override("font_size", 11)
	posture_label.add_theme_color_override("font_color", Color(0.48, 0.82, 0.7))
	controls.add_child(posture_label)
	var posture_menu := OptionButton.new()
	posture_menu.fit_to_longest_item = false
	posture_menu.clip_text = true
	posture_menu.name = "Posture"
	posture_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for posture in range(CommanderState.Posture.size()):
		posture_menu.add_item(GameText.t(StringName("COMMANDER_POSTURE_%s" % CommanderState.Posture.keys()[posture])), posture)
		posture_menu.get_popup().set_item_tooltip(posture, _posture_tooltip(posture as CommanderState.Posture))
	var selected_posture := int(_plan.posture_by_commander.get(definition.definition_id, CommanderState.Posture.BALANCED)) as CommanderState.Posture
	posture_menu.select(selected_posture)
	posture_menu.tooltip_text = _posture_tooltip(selected_posture)
	posture_menu.item_selected.connect(_on_posture_selected.bind(definition.definition_id))
	controls.add_child(posture_menu)
	_posture_menus[definition.definition_id] = posture_menu
	var tactical_detail := Label.new()
	tactical_detail.name = "TacticalDetail"
	tactical_detail.custom_minimum_size.y = 58.0
	tactical_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tactical_detail.max_lines_visible = 4
	tactical_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tactical_detail.add_theme_font_size_override("font_size", 11)
	tactical_detail.add_theme_color_override("font_color", Color(0.72, 0.78, 0.75))
	controls.add_child(tactical_detail)
	_tactical_detail_labels[definition.definition_id] = tactical_detail
	_set_tactical_detail(doctrine_menu.tooltip_text, tactical_detail)
	personality.mouse_entered.connect(_set_tactical_detail.bind(personality.tooltip_text, tactical_detail))
	doctrine_label.mouse_entered.connect(_set_tactical_detail.bind(doctrine_label.tooltip_text, tactical_detail))
	doctrine_menu.mouse_entered.connect(_set_tactical_detail.bind(doctrine_menu.tooltip_text, tactical_detail))
	posture_label.mouse_entered.connect(_set_tactical_detail.bind(posture_label.tooltip_text, tactical_detail))
	posture_menu.mouse_entered.connect(_set_tactical_detail.bind(posture_menu.tooltip_text, tactical_detail))
	doctrine_menu.get_popup().id_focused.connect(_on_doctrine_item_focused.bind(doctrine_menu, tactical_detail))
	posture_menu.get_popup().id_focused.connect(_on_posture_item_focused.bind(posture_menu, tactical_detail))
	return panel


func _doctrine_tooltip(doctrine: DoctrineDefinition) -> String:
	if doctrine == null:
		return ""
	var description := GameText.t(&"DOCTRINE_SLOT_TOOLTIP") % [
		GameText.t(doctrine.display_name_key),
		GameText.t(doctrine.behavior_key),
		GameText.t(doctrine.tradeoff_key),
	]
	for definition in doctrine.effects:
		description += "\n" + GameText.t(definition.counterplay.explanation_key)
	return description


func _posture_tooltip(posture: CommanderState.Posture) -> String:
	var posture_name: String = CommanderState.Posture.keys()[posture]
	return GameText.t(&"COMMANDER_POSTURE_DETAIL") % [
		GameText.t(StringName("COMMANDER_POSTURE_%s" % posture_name)),
		GameText.t(StringName("COMMANDER_POSTURE_%s_TOOLTIP" % posture_name)),
	]


func _set_tactical_detail(detail: String, label: Label) -> void:
	if label == null:
		return
	var disclosure := GameText.t(&"PREBATTLE_TACTICAL_DISCLOSURE") % detail
	if label.text == disclosure:
		return
	label.text = disclosure
	label.tooltip_text = detail


func _on_doctrine_item_focused(item_id: int, menu: OptionButton, label: Label) -> void:
	var index := menu.get_popup().get_item_index(item_id)
	if index < 0:
		return
	var doctrine_id := menu.get_item_metadata(index) as StringName
	_set_tactical_detail(_doctrine_tooltip(_doctrine_definitions.get(doctrine_id) as DoctrineDefinition), label)


func _on_posture_item_focused(item_id: int, menu: OptionButton, label: Label) -> void:
	var index := menu.get_popup().get_item_index(item_id)
	if index < 0:
		return
	_set_tactical_detail(_posture_tooltip(menu.get_item_id(index) as CommanderState.Posture), label)


func _create_unit_card_panel(definition: UnitCardDefinition) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "UnitCard_%s" % definition.definition_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0.0, 92.0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.39, 0.34, 0.18)))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var layout := BoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var identity := VBoxContainer.new()
	identity.name = "Identity"
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 3)
	layout.add_child(identity)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = GameText.t(definition.display_name_key)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.72))
	identity.add_child(name_label)
	var role := Label.new()
	role.name = "Role"
	role.text = GameText.t(definition.role_key)
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role.add_theme_color_override("font_color", Color(0.67, 0.72, 0.69))
	identity.add_child(role)
	var stats := Label.new()
	stats.name = "Stats"
	stats.text = GameText.t(&"PREBATTLE_CARD_STATS") % [definition.authorized_strength, definition.command_cost, definition.supply_cost]
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_theme_color_override("font_color", Color(0.48, 0.78, 0.69))
	identity.add_child(stats)
	var record := simulation_host.get_campaign_record() if simulation_host != null else {}
	var card_record := (record.get("cards", {}) as Dictionary).get(String(definition.definition_id), {}) as Dictionary
	stats.tooltip_text = CompositionText.from_definition(definition, card_record)
	if definition.composition.size() > 1:
		stats.text += "\n" + CompositionText.from_definition(definition, card_record)
	var available_strength := int(card_record.get("available_strength", definition.authorized_strength))
	var readiness := Label.new()
	readiness.name = "Readiness"
	readiness.text = GameText.t(&"PREBATTLE_CARD_READINESS") % [available_strength, definition.authorized_strength]
	readiness.add_theme_color_override("font_color", Color(0.95, 0.5, 0.38) if available_strength < definition.authorized_strength else Color(0.48, 0.82, 0.7))
	identity.add_child(readiness)
	_readiness_labels[definition.definition_id] = readiness
	var choices := VBoxContainer.new()
	choices.name = "Choices"
	choices.custom_minimum_size.x = 190.0
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 5)
	layout.add_child(choices)
	var commander_menu := OptionButton.new()
	commander_menu.fit_to_longest_item = false
	commander_menu.clip_text = true
	for commander in _commander_definitions:
		commander_menu.add_item(GameText.t((commander as CommanderDefinition).display_name_key))
		commander_menu.set_item_metadata(commander_menu.item_count - 1, (commander as CommanderDefinition).definition_id)
	var assigned_commander: StringName = _plan.commander_by_unit_card.get(definition.definition_id, &"")
	for index in range(commander_menu.item_count):
		if commander_menu.get_item_metadata(index) as StringName == assigned_commander:
			commander_menu.select(index)
			break
	commander_menu.item_selected.connect(_on_unit_commander_selected.bind(definition.definition_id, commander_menu))
	choices.add_child(commander_menu)
	var starting := CheckButton.new()
	starting.text = GameText.t(&"PREBATTLE_STARTING")
	starting.button_pressed = _plan.is_unit_card_starting(definition.definition_id)
	starting.toggled.connect(_on_starting_toggled.bind(definition.definition_id))
	choices.add_child(starting)
	if available_strength < definition.authorized_strength:
		var replacement_cost := ArmyRosterStore.replacement_cost(record, definition.definition_id)
		var affordable := ArmyRosterStore.affordable_replacements(record, definition.definition_id)
		var replenish := Button.new()
		replenish.text = GameText.t(&"PREBATTLE_REPLENISH") % [affordable, replacement_cost]
		replenish.tooltip_text = GameText.t(&"PREBATTLE_REPLENISH_TOOLTIP") % replacement_cost
		replenish.disabled = affordable <= 0
		replenish.pressed.connect(_on_replenish_pressed.bind(definition.definition_id))
		choices.add_child(replenish)
	_apply_unit_card_layout(panel, _current_viewport_width() < 600.0)
	return panel


func _refresh_validity() -> void:
	for definition in _commander_definitions:
		var commander := definition as CommanderDefinition
		var used := 0
		for card_definition in _unit_card_definitions:
			var card := card_definition as UnitCardDefinition
			if _plan.commander_by_unit_card.get(card.definition_id, &"") == commander.definition_id:
				used += card.command_cost
		var label := _capacity_labels.get(commander.definition_id) as Label
		if label != null:
			label.text = GameText.t(&"PREBATTLE_CAPACITY") % [used, commander.capacity]
			label.modulate = Color(1.0, 0.42, 0.34) if used > commander.capacity else Color(0.48, 0.82, 0.7)
	var errors := _validation_errors()
	start_button.disabled = not errors.is_empty()
	if errors.is_empty():
		var battle := simulation_host.world.battle_definition if simulation_host != null else null
		validation_label.text = GameText.t(&"ARMY_PLAN_READY_GENERIC") % (battle.starting_card_count if battle != null else ArmyPlan.STARTING_CARD_COUNT)
		validation_label.modulate = Color(0.46, 0.84, 0.67)
	else:
		var localized_errors: Array[String] = []
		for error in errors:
			localized_errors.append(GameText.t(error))
		validation_label.text = " | ".join(localized_errors)
		validation_label.modulate = Color(1.0, 0.48, 0.38)


func _validation_errors() -> Array[StringName]:
	if simulation_host == null:
		return [&"ARMY_PLAN_ERROR_UNAVAILABLE"]
	return simulation_host.get_grey_ridge_army_plan_errors(_plan)


func _on_unit_commander_selected(index: int, unit_card_id: StringName, menu: OptionButton) -> void:
	set_unit_card_commander(unit_card_id, menu.get_item_metadata(index) as StringName)


func _on_starting_toggled(enabled: bool, unit_card_id: StringName) -> void:
	set_unit_card_starting(unit_card_id, enabled)


func _on_doctrine_selected(index: int, commander_id: StringName, menu: OptionButton) -> void:
	set_commander_doctrine(commander_id, menu.get_item_metadata(index) as StringName)


func _on_posture_selected(index: int, commander_id: StringName) -> void:
	set_commander_posture(commander_id, index as CommanderState.Posture)


func _reset_plan() -> void:
	_plan = _default_plan()
	_record_plan_change()
	_rebuild_content()


func _default_plan() -> ArmyPlan:
	if simulation_host != null and simulation_host.world.battle_definition != null:
		return simulation_host.world.battle_definition.create_default_army_plan()
	return ArmyPlan.grey_ridge_default()


func _reset_campaign_progress() -> void:
	if simulation_host != null:
		simulation_host.reset_grey_ridge_campaign_record()


func _on_replenish_pressed(unit_card_id: StringName) -> void:
	if simulation_host != null:
		simulation_host.replenish_unit_card_as_much_as_possible(unit_card_id)


func _on_campaign_record_changed(_record: Dictionary) -> void:
	if visible:
		_rebuild_content()


func _on_tutorial_toggled(enabled: bool) -> void:
	TutorialProgressStore.set_scenario_enabled(_tutorial_scenario_id(), enabled)


func _tutorial_scenario_id() -> StringName:
	if simulation_host != null:
		return simulation_host.get_scenario_id()
	return &"grey_ridge"


func _start_battle() -> void:
	if simulation_host != null and simulation_host.start_grey_ridge(_plan, _create_prebattle_metrics()):
		visible = false


func _begin_prebattle_metrics() -> void:
	_prebattle_started_msec = Time.get_ticks_msec()
	_plan_change_count = 0
	_invalid_plan_change_count = 0


func _record_plan_change() -> void:
	_plan_change_count += 1
	if not _validation_errors().is_empty():
		_invalid_plan_change_count += 1


func _create_prebattle_metrics() -> Dictionary:
	var elapsed_msec := maxi(0, Time.get_ticks_msec() - _prebattle_started_msec) if _prebattle_started_msec > 0 else 0
	return {
		"duration_seconds": float(elapsed_msec) / 1000.0,
		"plan_changes": _plan_change_count,
		"invalid_plan_changes": _invalid_plan_change_count,
	}


func _on_battle_started(_snapshot: WorldSnapshot) -> void:
	visible = false


func _apply_responsive_layout() -> void:
	if not _built:
		return
	var viewport := get_viewport()
	var viewport_size := viewport.get_visible_rect().size if viewport != null else Vector2(1280.0, 720.0)
	_apply_layout_for_size(viewport_size)


func _apply_layout_for_size(viewport_size: Vector2) -> void:
	var width := viewport_size.x
	var backdrop := get_node("Backdrop") as Control
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	commander_grid.columns = 3 if width >= 1800.0 else (2 if width >= 1040.0 else 1)
	unit_card_grid.columns = 2 if width >= 1800.0 else 1
	var margin := get_node("Backdrop/Margin") as MarginContainer
	var horizontal_margin := 8 if width < 600.0 else int(clampf(width * 0.025, 14.0, 32.0))
	margin.add_theme_constant_override("margin_left", horizontal_margin)
	margin.add_theme_constant_override("margin_right", horizontal_margin)
	var title := get_node("Backdrop/Margin/Layout/Header/Title") as Label
	var operation := get_node("Backdrop/Margin/Layout/Header/Operation") as Label
	var header := get_node("Backdrop/Margin/Layout/Header") as BoxContainer
	var footer := get_node("Backdrop/Margin/Layout/Footer") as BoxContainer
	var narrow := width < 700.0
	header.vertical = narrow
	footer.vertical = narrow
	roster_bar.vertical = narrow
	footer.custom_minimum_size.y = 96.0 if narrow else 42.0
	var battle := simulation_host.world.battle_definition if simulation_host != null else null
	var battle_name := GameText.t(battle.display_name_key) if battle != null else GameText.t(&"GREY_RIDGE_TITLE")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = GameText.t(&"PREBATTLE_TITLE_GENERIC") % battle_name
	operation.visible = not narrow
	operation.custom_minimum_size.x = 0.0 if narrow else 240.0
	start_button.custom_minimum_size = Vector2(0.0 if narrow else 210.0, 38.0)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_SHRINK_END
	var reset_button := get_node("Backdrop/Margin/Layout/Footer/Reset") as Button
	reset_button.custom_minimum_size = Vector2(0.0 if narrow else 128.0, 36.0)
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_SHRINK_BEGIN
	var compact_cards := width < 600.0
	for child_variant in unit_card_grid.get_children():
		var panel := child_variant as PanelContainer
		if panel != null:
			_apply_unit_card_layout(panel, compact_cards)


func _apply_unit_card_layout(panel: PanelContainer, compact: bool) -> void:
	var layout := panel.get_node_or_null("MarginContainer/Layout") as BoxContainer
	if layout == null:
		return
	layout.vertical = compact
	panel.custom_minimum_size.y = 154.0 if compact else 92.0
	var choices := layout.get_node_or_null("Choices") as VBoxContainer
	if choices != null:
		choices.custom_minimum_size.x = 0.0 if compact else 190.0


func _current_viewport_width() -> float:
	var viewport := get_viewport()
	return viewport.get_visible_rect().size.x if viewport != null else 1280.0


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _panel_style(border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.064, 0.98)
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style
