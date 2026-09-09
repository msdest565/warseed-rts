extends SceneTree

const VIEWPORT_SIZE := Vector2i(1440, 900)
const OUTPUT_PATH := "res://artifacts/strategic_region_capture_states.png"


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		push_error("Strategic-region UI verification requires a display")
		quit(2)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(VIEWPORT_SIZE)
	root.content_scale_size = VIEWPORT_SIZE
	await _wait_frames(5)
	var game := (load("res://scenes/game/grey_ridge.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	current_scene = game
	await _wait_frames(8)
	var host := game.simulation_host
	if not host.start_grey_ridge(ArmyPlan.grey_ridge_default()):
		push_error("Could not start Grey Ridge for strategic-region UI verification")
		quit(1)
		return
	host.set_process(false)
	var west := host.world.strategic_regions[&"west_mine"] as StrategicRegionState
	var central := host.world.strategic_regions[&"central_relay"] as StrategicRegionState
	var east := host.world.strategic_regions[&"east_supply"] as StrategicRegionState
	west.controller_faction_id = 0
	west.capture_faction_id = SimulationWorld.LOCAL_PLAYER_ID
	west.capture_progress_ticks = west.capture_required_ticks / 2
	central.controller_faction_id = SimulationWorld.LOCAL_PLAYER_ID
	central.capture_faction_id = SimulationWorld.LOCAL_PLAYER_ID
	central.capture_progress_ticks = central.capture_required_ticks
	east.controller_faction_id = SimulationWorld.ENEMY_PLAYER_ID
	east.capture_faction_id = SimulationWorld.ENEMY_PLAYER_ID
	east.capture_progress_ticks = east.capture_required_ticks
	host.world.current_tick = 1
	host.previous_snapshot = host.current_snapshot
	host.current_snapshot = host.world.create_snapshot()
	await _wait_frames(20)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Could not save strategic-region UI screenshot: %s" % error_string(error))
		quit(1)
		return
	var blue_pixels := _count_approximate_color(image, Color("3b8eea"), 0.22)
	var red_pixels := _count_approximate_color(image, Color("d95757"), 0.22)
	var gray_pixels := _count_approximate_color(image, Color("7f898e"), 0.18)
	if blue_pixels < 20 or red_pixels < 20 or gray_pixels < 20:
		push_error("Strategic-region colors were not visibly rendered: blue=%d red=%d gray=%d" % [blue_pixels, red_pixels, gray_pixels])
		quit(1)
		return
	print("WARSEED_REGION_UI passed blue=%d red=%d gray=%d screenshot=%s" % [
		blue_pixels, red_pixels, gray_pixels, ProjectSettings.globalize_path(OUTPUT_PATH),
	])
	quit(0)


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _count_approximate_color(image: Image, target: Color, tolerance: float) -> int:
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var pixel := image.get_pixel(x, y)
			if Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(target.r, target.g, target.b)) <= tolerance:
				count += 1
	return count
