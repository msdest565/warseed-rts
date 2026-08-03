class_name PauseMenu
extends CanvasLayer

@onready var backdrop: ColorRect = $Backdrop
@onready var continue_button: Button = $Backdrop/Menu/Content/Continue
@onready var exit_button: Button = $Backdrop/Menu/Content/Exit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.pressed.connect(close)
	exit_button.pressed.connect(_exit_game)
	backdrop.hide()


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
