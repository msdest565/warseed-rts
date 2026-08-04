class_name PauseMenu
extends CanvasLayer

signal language_changed(locale: String)

@onready var backdrop: ColorRect = $Backdrop
@onready var title_label: Label = $Backdrop/Menu/Content/Title
@onready var continue_button: Button = $Backdrop/Menu/Content/Continue
@onready var language_label: Label = $Backdrop/Menu/Content/LanguageLabel
@onready var language_selector: OptionButton = $Backdrop/Menu/Content/LanguageSelector
@onready var exit_button: Button = $Backdrop/Menu/Content/Exit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.pressed.connect(close)
	language_selector.item_selected.connect(_select_language)
	exit_button.pressed.connect(_exit_game)
	var initial_locale := "zh_CN" if TranslationServer.get_locale().begins_with("zh") else "en"
	TranslationServer.set_locale(initial_locale)
	_refresh_locale()
	backdrop.hide()


func _refresh_locale() -> void:
	for control in [title_label, continue_button, language_label, language_selector, exit_button]:
		(control as Control).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_label.text = GameText.t(&"PAUSED_TITLE")
	continue_button.text = GameText.t(&"CONTINUE_GAME")
	language_label.text = GameText.t(&"LANGUAGE_LABEL")
	exit_button.text = GameText.t(&"EXIT_GAME")
	language_selector.clear()
	language_selector.add_item(GameText.t(&"LANGUAGE_CHINESE"))
	language_selector.set_item_metadata(0, "zh_CN")
	language_selector.add_item(GameText.t(&"LANGUAGE_ENGLISH"))
	language_selector.set_item_metadata(1, "en")
	language_selector.select(0 if TranslationServer.get_locale().begins_with("zh") else 1)


func _select_language(index: int) -> void:
	var locale := String(language_selector.get_item_metadata(index))
	TranslationServer.set_locale(locale)
	_refresh_locale()
	language_changed.emit(locale)


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
