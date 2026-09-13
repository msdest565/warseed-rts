extends SceneTree


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var game := (load("res://scenes/game/grey_ridge.tscn") as PackedScene).instantiate() as GameRoot
	root.add_child(game)
	current_scene = game
	await process_frame
	game.simulation_host.set_process(false)
	game.prebattle_planner.hide()
	var world := GreyRidgeBenchmarkFixture.create_world(80)
	for value in world.units.values():
		var unit := value as UnitState
		if unit.faction_id == 1:
			unit.sight_range = 10000
	world._update_faction_knowledge()
	game.simulation_host.world = world
	game.simulation_host._grey_ridge_battle_started = true
	var presentation := game.world_presentation
	var failed := false
	for count in [55, 57, 80, 40]:
		var snapshot := world.create_snapshot()
		snapshot.units.resize(count)
		snapshot.tick = count
		game.simulation_host.current_snapshot = snapshot
		game.simulation_host.previous_snapshot = snapshot
		presentation.set_snapshots(snapshot, snapshot, 1.0)
		var unit := snapshot.units[0]
		game.camera_controller.zoom = Vector2.ONE
		game.camera_controller.center_on_world_position(unit.position)
		game.camera_controller.force_update_scroll()
		for _frame in range(6):
			await process_frame
		var screen := presentation.get_global_transform_with_canvas() * unit.position
		var capture := root.get_texture().get_image()
		screen *= Vector2(capture.get_size()) / root.get_visible_rect().size
		capture.save_png("res://artifacts/manual-visibility-%d.png" % count)
		var rect := Rect2i(Vector2i(screen) - Vector2i(14, 9), Vector2i(28, 18)).intersection(Rect2i(Vector2i.ZERO, capture.get_size()))
		var pixels := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var color := capture.get_pixel(x, y)
				if color.g > color.r * 1.3 and color.b > color.r * 1.3 and color.g > 0.25:
					pixels += 1
		print("MANUAL_VISIBILITY count=%d batched=%s body_pixels=%d screen=%s" % [count, not presentation._detailed_units_enabled, pixels, screen])
		failed = failed or pixels < 30
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
