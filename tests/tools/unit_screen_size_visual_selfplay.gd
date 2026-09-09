extends SceneTree

const VIEWPORT_SIZE := Vector2i(1280, 720)
const CAPTURE_HALF_SIZE := Vector2i(72, 72)
const TEST_ZOOMS := [0.2, 1.2]


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		push_error("unit screen-size visual selfplay requires a display")
		quit(2)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(VIEWPORT_SIZE)
	root.content_scale_size = VIEWPORT_SIZE
	var game := (load("res://scenes/game/game_root.tscn") as PackedScene).instantiate() as GameRoot
	game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	current_scene = game
	await _wait_frames(4)
	if game.simulation_host.scenario_kind != SimulationWorld.ScenarioKind.LEGACY_RTS:
		push_error("visual selfplay did not load the direct Legacy RTS game_root path")
		await _finish(game, 3)
		return
	game.world_presentation.set_snapshots(
		game.simulation_host.previous_snapshot,
		game.simulation_host.current_snapshot,
		0.0
	)
	await _wait_frames(2)
	var unit := game.simulation_host.current_snapshot.get_unit(3)
	if unit == null:
		push_error("visual selfplay could not find reference unit E3")
		await _finish(game, 4)
		return
	var proxy := game.world_presentation._proxies.get(unit.entity_id) as UnitProxy
	if proxy == null:
		push_error("visual selfplay could not find UnitProxy for E%d" % unit.entity_id)
		await _finish(game, 5)
		return
	proxy.selected = true
	for camera_zoom in TEST_ZOOMS:
		game.camera_controller.zoom = Vector2.ONE * camera_zoom
		game._update_unit_presentation_for_zoom()
		game.camera_controller.center_on_world_position(proxy.position)
		game.camera_controller.force_update_scroll()
		await _wait_frames(4)
		var screen_scale := proxy.scale.x * game.camera_controller.zoom.x
		if not is_equal_approx(proxy.scale.x, 1.0):
			push_error("unit proxy world scale changed at zoom %.2f: %.4f" % [camera_zoom, proxy.scale.x])
			await _finish(game, 6)
			return
		if not is_equal_approx(screen_scale, camera_zoom):
			push_error("unit screen scale did not follow camera zoom %.2f: %.4f" % [camera_zoom, screen_scale])
			await _finish(game, 8)
			return
		var screen_transform := proxy.get_global_transform_with_canvas()
		var canvas_screen_scale := screen_transform.x.length()
		if not is_equal_approx(canvas_screen_scale, camera_zoom):
			push_error("final Canvas unit scale did not follow camera zoom %.2f: %.4f" % [camera_zoom, canvas_screen_scale])
			await _finish(game, 8)
			return
		var screen_position := screen_transform.origin
		var image := root.get_texture().get_image()
		var capture_rect := Rect2i(Vector2i(screen_position) - CAPTURE_HALF_SIZE, CAPTURE_HALF_SIZE * 2)
		capture_rect = capture_rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var crop := image.get_region(capture_rect)
		var suffix := "%d_%02d" % [floori(camera_zoom), roundi(fmod(camera_zoom, 1.0) * 100.0)]
		var path := "res://artifacts/unit_scale_legacy_zoom_%s.png" % suffix
		if crop.save_png(ProjectSettings.globalize_path(path)) != OK:
			push_error("could not save visual selfplay screenshot %s" % path)
			await _finish(game, 7)
			return
		print("WARSEED_UNIT_WORLD_SCALE_VISUAL zoom=%.2f proxy_scale=%.4f screen_scale=%.4f canvas_scale=%.4f capture=%s" % [camera_zoom, proxy.scale.x, screen_scale, canvas_screen_scale, path])
	print("WARSEED unit world-scale visual selfplay passed: direct Legacy RTS path")
	await _finish(game, 0)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _finish(game: Node, exit_code: int) -> void:
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	quit(exit_code)
