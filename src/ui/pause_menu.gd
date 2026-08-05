class_name PauseMenu
extends CanvasLayer

signal language_changed(locale: String)
signal enemy_difficulty_changed(difficulty: EnemyDifficultyProfile.Difficulty)
signal agent_authorization_changed(agent_id: int, authorization: AgentPolicy.Authorization)

@onready var backdrop: ColorRect = $Backdrop
@onready var title_label: Label = $Backdrop/Menu/Content/Title
@onready var continue_button: Button = $Backdrop/Menu/Content/Continue
@onready var language_label: Label = $Backdrop/Menu/Content/LanguageLabel
@onready var language_selector: OptionButton = $Backdrop/Menu/Content/LanguageSelector
@onready var difficulty_label: Label = $Backdrop/Menu/Content/DifficultyLabel
@onready var difficulty_selector: OptionButton = $Backdrop/Menu/Content/DifficultySelector
@onready var industrial_ai_label: Label = $Backdrop/Menu/Content/IndustrialAILabel
@onready var industrial_ai_selector: OptionButton = $Backdrop/Menu/Content/IndustrialAISelector
@onready var battlefield_ai_label: Label = $Backdrop/Menu/Content/BattlefieldAILabel
@onready var battlefield_ai_selector: OptionButton = $Backdrop/Menu/Content/BattlefieldAISelector
@onready var exit_button: Button = $Backdrop/Menu/Content/Exit

var _enemy_difficulty: EnemyDifficultyProfile.Difficulty = EnemyDifficultyProfile.Difficulty.NORMAL
var _industrial_authorization: AgentPolicy.Authorization = AgentPolicy.Authorization.ASSISTED
var _battlefield_authorization: AgentPolicy.Authorization = AgentPolicy.Authorization.ASSISTED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.pressed.connect(close)
	language_selector.item_selected.connect(_select_language)
	difficulty_selector.item_selected.connect(_select_difficulty)
	industrial_ai_selector.item_selected.connect(_select_agent_authorization.bind(StrategicTaskSystem.INDUSTRIAL_AGENT_ID))
	battlefield_ai_selector.item_selected.connect(_select_agent_authorization.bind(StrategicTaskSystem.BATTLEFIELD_AGENT_ID))
	exit_button.pressed.connect(_exit_game)
	var initial_locale := "zh_CN" if TranslationServer.get_locale().begins_with("zh") else "en"
	TranslationServer.set_locale(initial_locale)
	_refresh_locale()
	backdrop.hide()


func _refresh_locale() -> void:
	for control in [title_label, continue_button, language_label, language_selector, difficulty_label, difficulty_selector, industrial_ai_label, industrial_ai_selector, battlefield_ai_label, battlefield_ai_selector, exit_button]:
		(control as Control).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_label.text = GameText.t(&"PAUSED_TITLE")
	continue_button.text = GameText.t(&"CONTINUE_GAME")
	language_label.text = GameText.t(&"LANGUAGE_LABEL")
	difficulty_label.text = GameText.t(&"ENEMY_DIFFICULTY_LABEL")
	industrial_ai_label.text = GameText.t(&"INDUSTRIAL_AI_LABEL")
	battlefield_ai_label.text = GameText.t(&"BATTLEFIELD_AI_LABEL")
	exit_button.text = GameText.t(&"EXIT_GAME")
	language_selector.clear()
	language_selector.add_item(GameText.t(&"LANGUAGE_CHINESE"))
	language_selector.set_item_metadata(0, "zh_CN")
	language_selector.add_item(GameText.t(&"LANGUAGE_ENGLISH"))
	language_selector.set_item_metadata(1, "en")
	language_selector.select(0 if TranslationServer.get_locale().begins_with("zh") else 1)
	_populate_enum_selector(difficulty_selector, "AI_DIFFICULTY", EnemyDifficultyProfile.Difficulty.keys(), _enemy_difficulty)
	_populate_enum_selector(industrial_ai_selector, "AI_AUTH", AgentPolicy.Authorization.keys(), _industrial_authorization)
	_populate_enum_selector(battlefield_ai_selector, "AI_AUTH", AgentPolicy.Authorization.keys(), _battlefield_authorization)


func _select_language(index: int) -> void:
	var locale := String(language_selector.get_item_metadata(index))
	TranslationServer.set_locale(locale)
	_refresh_locale()
	language_changed.emit(locale)


func _select_difficulty(index: int) -> void:
	_enemy_difficulty = int(difficulty_selector.get_item_metadata(index))
	enemy_difficulty_changed.emit(_enemy_difficulty)


func _select_agent_authorization(index: int, agent_id: int) -> void:
	var selector := industrial_ai_selector if agent_id == StrategicTaskSystem.INDUSTRIAL_AGENT_ID else battlefield_ai_selector
	var authorization: AgentPolicy.Authorization = int(selector.get_item_metadata(index))
	if agent_id == StrategicTaskSystem.INDUSTRIAL_AGENT_ID:
		_industrial_authorization = authorization
	else:
		_battlefield_authorization = authorization
	agent_authorization_changed.emit(agent_id, authorization)


func set_ai_settings(
	difficulty: EnemyDifficultyProfile.Difficulty,
	industrial_authorization: AgentPolicy.Authorization,
	battlefield_authorization: AgentPolicy.Authorization
) -> void:
	_enemy_difficulty = difficulty
	_industrial_authorization = industrial_authorization
	_battlefield_authorization = battlefield_authorization
	_refresh_locale()


func _populate_enum_selector(selector: OptionButton, prefix: String, values: PackedStringArray, selected_value: int) -> void:
	selector.clear()
	for value_index in range(values.size()):
		selector.add_item(GameText.enum_name(prefix, values[value_index]))
		selector.set_item_metadata(value_index, value_index)
	selector.select(selected_value)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if backdrop.visible:
			close()
		else:
			open()


func open() -> void:
	backdrop.show()
	(Engine.get_main_loop() as SceneTree).paused = true
	if continue_button.is_inside_tree():
		continue_button.grab_focus()


func close() -> void:
	(Engine.get_main_loop() as SceneTree).paused = false
	backdrop.hide()


func _exit_game() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	tree.quit()
