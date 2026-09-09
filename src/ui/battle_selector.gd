class_name BattleSelector
extends Control

signal battle_requested(scenario_id: StringName, scene_path: String)

const CATALOG_PATH := BattleContentLoader.DEFAULT_CATALOG_PATH

@onready var title_label: Label = $SafeArea/Layout/Header/Title
@onready var subtitle_label: Label = $SafeArea/Layout/Header/Subtitle
@onready var battle_list: VBoxContainer = $SafeArea/Layout/Body/BattleList
@onready var operation_label: Label = $SafeArea/Layout/Body/Dossier/Content/Operation
@onready var battle_title_label: Label = $SafeArea/Layout/Body/Dossier/Content/BattleTitle
@onready var briefing_label: Label = $SafeArea/Layout/Body/Dossier/Content/Briefing
@onready var mechanics_label: Label = $SafeArea/Layout/Body/Dossier/Content/Mechanics
@onready var persistence_label: Label = $SafeArea/Layout/Body/Dossier/Content/Persistence
@onready var training_status_label: Label = $SafeArea/Layout/Body/Dossier/Content/Training/Status
@onready var replay_tutorial_button: Button = $SafeArea/Layout/Body/Dossier/Content/Training/Replay
@onready var deploy_button: Button = $SafeArea/Layout/Body/Dossier/Content/Deploy
@onready var language_button: Button = $SafeArea/Layout/Footer/Language
@onready var exit_button: Button = $SafeArea/Layout/Footer/Exit

var scene_changes_enabled: bool = true
var _battles: Array[BattleDefinition] = []
var _battle_buttons: Array[Button] = []
var _selected_index: int = -1
var _black_well_continuity_confirmed := false


func _ready() -> void:
	var session_id := ArmyRosterStore.active_playtest_session_id()
	var roster_path := ArmyRosterStore.campaign_record_path_for_session(session_id, &"black_well")
	_black_well_continuity_confirmed = TutorialProgressStore.confirm_black_well_continuity(
		ArmyRosterStore.load_record(roster_path)
	)
	_load_battles()
	language_button.pressed.connect(_toggle_language)
	exit_button.pressed.connect(_exit_game)
	deploy_button.pressed.connect(_deploy_selected)
	replay_tutorial_button.pressed.connect(_replay_selected_tutorial)
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_responsive_layout):
		viewport.size_changed.connect(_apply_responsive_layout)
	refresh_locale()
	if not _battles.is_empty():
		_select_battle(0)
	_apply_responsive_layout()


func _load_battles() -> void:
	var resource := ResourceLoader.load(CATALOG_PATH) as BattleContentCatalog
	if resource == null:
		deploy_button.disabled = true
		return
	_battles = resource.get_selectable_battles()
	for child in battle_list.get_children():
		child.queue_free()
	_battle_buttons.clear()
	for index in range(_battles.size()):
		var button := Button.new()
		button.name = "Battle_%s" % _battles[index].scenario_id
		button.custom_minimum_size = Vector2(0.0, 76.0)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(_select_battle.bind(index))
		battle_list.add_child(button)
		_battle_buttons.append(button)


func refresh_locale() -> void:
	title_label.text = GameText.t(&"BATTLE_SELECT_TITLE")
	subtitle_label.text = GameText.t(&"BATTLE_SELECT_SUBTITLE")
	persistence_label.text = GameText.t(&"BATTLE_SELECT_PERSISTENCE")
	if _black_well_continuity_confirmed:
		persistence_label.text = "%s\n%s" % [persistence_label.text, GameText.t(&"BLACK_WELL_CONTINUITY_CONFIRMED")]
	deploy_button.text = GameText.t(&"BATTLE_SELECT_DEPLOY")
	replay_tutorial_button.text = GameText.t(&"BATTLE_SELECT_TUTORIAL_REPLAY")
	replay_tutorial_button.tooltip_text = GameText.t(&"BATTLE_SELECT_TUTORIAL_REPLAY_TOOLTIP")
	language_button.text = GameText.t(&"BATTLE_SELECT_LANGUAGE")
	exit_button.text = GameText.t(&"EXIT_GAME")
	for index in range(_battle_buttons.size()):
		var battle := _battles[index]
		_battle_buttons[index].text = GameText.t(&"BATTLE_SELECT_OPERATION_BUTTON") % [
			battle.operation_number,
			GameText.t(battle.display_name_key),
		]
	if _selected_index >= 0:
		_refresh_dossier()


func _select_battle(index: int) -> void:
	if index < 0 or index >= _battles.size():
		return
	_selected_index = index
	for button_index in range(_battle_buttons.size()):
		_battle_buttons[button_index].button_pressed = button_index == index
	_refresh_dossier()
	deploy_button.disabled = false
	if deploy_button.is_inside_tree():
		deploy_button.grab_focus()


func _refresh_dossier() -> void:
	var battle := get_selected_battle()
	if battle == null:
		return
	operation_label.text = GameText.t(&"BATTLE_SELECT_OPERATION") % battle.operation_number
	battle_title_label.text = GameText.t(battle.display_name_key)
	briefing_label.text = GameText.t(battle.selector_briefing_key)
	mechanics_label.text = GameText.t(&"BATTLE_SELECT_MECHANICS") % GameText.t(battle.selector_mechanics_key)
	var status := TutorialProgressStore.get_scenario_status(battle.scenario_id)
	training_status_label.text = "%s: %s" % [
		GameText.t(&"BATTLE_SELECT_TUTORIAL_STATUS"),
		GameText.t(StringName("TUTORIAL_STATUS_%s" % status.to_upper())),
	]


func get_selected_battle() -> BattleDefinition:
	if _selected_index < 0 or _selected_index >= _battles.size():
		return null
	return _battles[_selected_index]


func get_selectable_battle_count() -> int:
	return _battles.size()


func get_battle_button(scenario_id: StringName) -> Button:
	for index in range(_battles.size()):
		if _battles[index].scenario_id == scenario_id:
			return _battle_buttons[index]
	return null


func _replay_selected_tutorial() -> void:
	var battle := get_selected_battle()
	if battle == null:
		return
	TutorialProgressStore.reset_scenario(battle.scenario_id)
	_refresh_dossier()


func _deploy_selected() -> void:
	var battle := get_selected_battle()
	if battle == null or battle.scene_path.is_empty():
		return
	battle_requested.emit(battle.scenario_id, battle.scene_path)
	if scene_changes_enabled:
		get_tree().change_scene_to_file(battle.scene_path)


func _toggle_language() -> void:
	TranslationServer.set_locale("en" if TranslationServer.get_locale().begins_with("zh") else "zh_CN")
	refresh_locale()


func _exit_game() -> void:
	get_tree().quit()


func _apply_responsive_layout() -> void:
	if not is_inside_tree():
		return
	var body := $SafeArea/Layout/Body as GridContainer
	var viewport_width := get_viewport_rect().size.x
	var narrow := viewport_width < 820.0
	body.columns = 1 if narrow else 2
	battle_list.custom_minimum_size = Vector2(0.0 if narrow else 310.0, 156.0)
	briefing_label.custom_minimum_size.y = 60.0 if narrow else 92.0
	for button in _battle_buttons:
		button.custom_minimum_size.y = 44.0 if narrow else 76.0
	body.add_theme_constant_override("h_separation", 22)
	body.add_theme_constant_override("v_separation", 12)
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.024, 0.025))
	var grid_color := Color(0.12, 0.18, 0.175, 0.22)
	for x in range(0, ceili(size.x / 64.0) + 1):
		draw_line(Vector2(x * 64.0, 0.0), Vector2(x * 64.0, size.y), grid_color, 1.0)
	for y in range(0, ceili(size.y / 64.0) + 1):
		draw_line(Vector2(0.0, y * 64.0), Vector2(size.x, y * 64.0), grid_color, 1.0)
	var river_points := PackedVector2Array([
		Vector2(size.x * 0.08, size.y * 0.16), Vector2(size.x * 0.28, size.y * 0.29),
		Vector2(size.x * 0.43, size.y * 0.52), Vector2(size.x * 0.66, size.y * 0.61),
		Vector2(size.x * 0.92, size.y * 0.88),
	])
	draw_polyline(river_points, Color(0.12, 0.30, 0.31, 0.34), 26.0, true)
	draw_polyline(river_points, Color(0.24, 0.58, 0.55, 0.28), 2.0, true)
