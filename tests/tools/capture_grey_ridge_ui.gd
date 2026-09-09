extends SceneTree

const CAPTURE_DIRECTORY := "user://ui-captures"


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		push_error("Grey Ridge UI capture requires a real display")
		quit(2)
		return
	var options := _parse_options()
	var capture_size := options["size"] as Vector2i
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(capture_size)
	root.content_scale_size = capture_size
	await process_frame
	await process_frame

	var game := (load("res://scenes/game/grey_ridge.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var host := game.get_node("SimulationHost") as SimulationHost
	var state := String(options["state"])
	if state == "battle":
		host.start_grey_ridge(ArmyPlan.grey_ridge_default())
		for _frame in range(8):
			await process_frame
	var output_path := String(options["output_path"])
	if output_path.is_empty():
		output_path = "%s/grey_ridge_%s_%dx%d.png" % [
			CAPTURE_DIRECTORY, state, capture_size.x, capture_size.y,
		]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var image := root.get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save Grey Ridge UI capture: %s" % error_string(error))
		quit(1)
		return
	print("WARSEED_UI_CAPTURE %s" % ProjectSettings.globalize_path(output_path))
	quit(0)


func _parse_options() -> Dictionary:
	var capture_size := Vector2i(1280, 720)
	var state := "planning"
	var output_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x")
			if dimensions.size() == 2:
				capture_size = Vector2i(maxi(360, int(dimensions[0])), maxi(640, int(dimensions[1])))
		elif argument.begins_with("--state="):
			var requested_state := argument.trim_prefix("--state=")
			if requested_state in ["planning", "battle"]:
				state = requested_state
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	return {"size": capture_size, "state": state, "output_path": output_path}
