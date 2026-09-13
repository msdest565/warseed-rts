extends SceneTree

const REPORT_VERSION := 3
const DEFAULT_ENTITY_COUNTS: Array[int] = [80, 120]
const DEFAULT_SAMPLE_SECONDS := 15.0
const WARMUP_SECONDS := 3.0
const PROJECTILE_PEAK := 160
const INPUT_INTERVAL_SECONDS := 1.5
const FRAME_P95_BUDGET_USEC := 16667
const SIMULATION_P95_BUDGET_USEC := 100000
const PRESENTED_INPUT_P95_BUDGET_USEC := 150000
const LONG_RUN_SECONDS := 480.0
const LONG_RUN_MAX_FRAME_USEC := 250000
const LONG_RUN_MAX_STATIC_MEMORY_GROWTH_BYTES := 64 * 1024 * 1024
const LONG_RUN_MAX_NODE_GROWTH := 32
const LONG_RUN_MAX_ORPHAN_GROWTH := 2
const REPORT_PATH := "user://performance/grey_ridge_windows_render_latest.json"
const CAPTURE_DIRECTORY := "user://performance"


func _initialize() -> void:
	if DisplayServer.get_name().to_lower().contains("headless"):
		push_error("Windows render benchmark requires a real display and GPU renderer")
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var empty_frame_baseline := await _measure_empty_frame_baseline()
	var options := _parse_options()
	var entity_counts := options["entity_counts"] as Array[int]
	var sample_seconds := float(options["sample_seconds"])
	var projectile_count := int(options["projectile_count"])
	var hide_hud := bool(options["hide_hud"])
	var hide_battlefield := bool(options["hide_battlefield"])
	var disable_game_root_process := bool(options["disable_game_root_process"])
	var disable_battle_feedback := bool(options["disable_battle_feedback"])
	var results: Array[Dictionary] = []
	var failed := false
	for entity_count in entity_counts:
		var result := await _benchmark(
			entity_count, sample_seconds, projectile_count, hide_hud,
			hide_battlefield, disable_game_root_process, disable_battle_feedback,
			int(empty_frame_baseline["frame_p95_usec"]) <= FRAME_P95_BUDGET_USEC
		)
		results.append(result)
		print("WARSEED_RENDER_PERF %s" % JSON.stringify(result))
		if bool(result["gate_applicable"]) and not bool(result["passes_required_gate"]):
			failed = true
	var report := {
		"format_version": REPORT_VERSION,
		"generated_unix_time": int(Time.get_unix_time_from_system()),
		"engine_version": String(Engine.get_version_info().get("string", "unknown")),
		"operating_system": OS.get_name(),
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"screen_refresh_rate_hz": DisplayServer.screen_get_refresh_rate(),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"screen_size": _vector2i_array(DisplayServer.screen_get_size()),
		"window_size": _vector2i_array(root.size),
		"empty_frame_baseline": empty_frame_baseline,
		"results": results,
	}
	if not _save_report(report):
		failed = true
		push_error("Could not save Windows render benchmark report")
	else:
		print("WARSEED_RENDER_PERF_REPORT %s" % ProjectSettings.globalize_path(REPORT_PATH))
	quit(1 if failed else 0)


func _benchmark(
	entity_count: int,
	sample_seconds: float,
	projectile_count: int,
	hide_hud: bool,
	hide_battlefield: bool,
	disable_game_root_process: bool,
	disable_battle_feedback: bool,
	environment_supports_60fps: bool
) -> Dictionary:
	var packed_scene := load("res://scenes/game/grey_ridge.tscn") as PackedScene
	var game := packed_scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var host := game.get_node("SimulationHost") as SimulationHost
	host.start_grey_ridge(ArmyPlan.grey_ridge_default())
	host.process_mode = Node.PROCESS_MODE_DISABLED
	var world := _create_benchmark_world(entity_count, projectile_count)
	world.tick_profile_enabled = true
	var snapshot := world.create_snapshot()
	host.world = world
	host.previous_snapshot = snapshot
	host.current_snapshot = snapshot
	_configure_benchmark_game(game, snapshot)
	var presentation := game.get_node("WorldPresentation") as WorldPresentation
	var camera := game.get_node("CameraController") as CameraController
	camera.zoom = Vector2.ONE
	camera.center_on_world_position(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	(game.get_node("PrebattlePlanner") as PrebattlePlanner).visible = false
	(game.get_node("BattleDebrief") as BattleDebrief).visible = false
	if hide_hud:
		(game.get_node("HUDLayer") as CanvasLayer).visible = false
		(game.get_node("SelectionLayer") as CanvasLayer).visible = false
		(game.get_node("HoverTooltip") as CanvasLayer).visible = false
	if hide_battlefield:
		(game.get_node("Battlefield") as Battlefield).visible = false
	if disable_game_root_process:
		game.set_process(false)
	if disable_battle_feedback:
		game.battle_feedback_director = null

	var simulation_accumulator := 0.0
	var previous_frame_usec := Time.get_ticks_usec()
	var warmup_deadline := previous_frame_usec + int(WARMUP_SECONDS * 1000000.0)
	while Time.get_ticks_usec() < warmup_deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_delta := minf(float(now - previous_frame_usec) / 1000000.0, 0.25)
		previous_frame_usec = now
		simulation_accumulator = _advance_world(world, host, simulation_accumulator + frame_delta, null)

	var frame_samples: Array[int] = []
	var process_samples: Array[int] = []
	var simulation_samples: Array[int] = []
	var tick_profile_samples: Dictionary = {}
	var validation_samples: Array[int] = []
	var authoritative_input_samples: Array[int] = []
	var presented_input_samples: Array[int] = []
	var draw_call_samples: Array[int] = []
	var object_samples: Array[int] = []
	var memory_static_start := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var memory_static_peak := memory_static_start
	var node_count_start := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var node_count_peak := node_count_start
	var orphan_node_count_start := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var orphan_node_count_peak := orphan_node_count_start
	var resource_count_start := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var resource_count_peak := resource_count_start
	var pending_inputs: Array[Dictionary] = []
	var rejected_inputs := 0
	var rejected_input_reasons: Dictionary = {}
	var projectile_peak := 0
	var proxy_peak := 0
	var simulation_entity_peak := GreyRidgeBenchmarkFixture.active_entity_count(world)
	var recovering_peak := 0
	var column_formation_peak := 0
	var choke_occupancy_peak := 0
	var eastbound := true
	var next_input_usec := Time.get_ticks_usec() + int(INPUT_INTERVAL_SECONDS * 1000000.0)
	var sample_started_usec := Time.get_ticks_usec()
	var sample_deadline_usec := sample_started_usec + int(sample_seconds * 1000000.0)
	previous_frame_usec = sample_started_usec
	while Time.get_ticks_usec() < sample_deadline_usec:
		await process_frame
		var frame_now := Time.get_ticks_usec()
		var frame_usec := maxi(0, frame_now - previous_frame_usec)
		previous_frame_usec = frame_now
		frame_samples.append(frame_usec)
		process_samples.append(int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0))
		draw_call_samples.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		object_samples.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		memory_static_peak = maxi(memory_static_peak, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
		node_count_peak = maxi(node_count_peak, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		orphan_node_count_peak = maxi(orphan_node_count_peak, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
		resource_count_peak = maxi(resource_count_peak, int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))

		if frame_now >= next_input_usec:
			var formation := GreyRidgeBenchmarkFixture.benchmark_formation(world)
			if formation != null:
				var command := FormationMoveCommand.new(
					world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
					GameCommand.IssuerKind.PLAYER, world.current_tick,
					formation.leader_entity_id, formation.formation_id,
					GreyRidgeBenchmarkFixture.command_destination(world, eastbound)
				)
				var validation_started := Time.get_ticks_usec()
				var validation := world.submit_command(command)
				validation_samples.append(Time.get_ticks_usec() - validation_started)
				if validation.is_accepted():
					pending_inputs.append({
						"issued_usec": frame_now,
						"issued_tick": world.current_tick,
						"authoritative_usec": -1,
						"applied_tick": -1,
					})
				else:
					rejected_inputs += 1
					var reason := validation.describe()
					rejected_input_reasons[reason] = int(rejected_input_reasons.get(reason, 0)) + 1
				eastbound = not eastbound
			next_input_usec += int(INPUT_INTERVAL_SECONDS * 1000000.0)

		var before_tick := world.current_tick
		var tick_samples_before := simulation_samples.size()
		simulation_accumulator += minf(float(frame_usec) / 1000000.0, 0.25)
		while simulation_accumulator >= SimulationWorld.TICK_SECONDS:
			simulation_accumulator -= SimulationWorld.TICK_SECONDS
			var tick_started := Time.get_ticks_usec()
			var previous_snapshot := host.current_snapshot
			var current_snapshot := world.advance_tick()
			host.previous_snapshot = previous_snapshot
			host.current_snapshot = current_snapshot
			simulation_samples.append(Time.get_ticks_usec() - tick_started)
			_append_tick_profile_samples(tick_profile_samples, world.last_tick_profile_usec)
		if world.current_tick > before_tick or simulation_samples.size() > tick_samples_before:
			for input in pending_inputs:
				if int(input["authoritative_usec"]) < 0 and world.current_tick > int(input["issued_tick"]):
					input["authoritative_usec"] = Time.get_ticks_usec() - int(input["issued_usec"])
					input["applied_tick"] = world.current_tick
		for input in pending_inputs:
			if int(input["authoritative_usec"]) >= 0 and not bool(input.get("presented", false)) and presentation._synced_snapshot_tick >= int(input["applied_tick"]):
				input["presented"] = true
				presented_input_samples.append(Time.get_ticks_usec() - int(input["issued_usec"]))

		projectile_peak = maxi(projectile_peak, world.projectiles.size())
		proxy_peak = maxi(proxy_peak, presentation._proxies.size())
		simulation_entity_peak = maxi(simulation_entity_peak, GreyRidgeBenchmarkFixture.active_entity_count(world))
		var recovering := 0
		var choke_occupancy := 0
		for unit_variant in world.units.values():
			var unit := unit_variant as UnitState
			if unit.is_recovering:
				recovering += 1
			if unit.enabled and unit.position.distance_to(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION) <= 180.0:
				choke_occupancy += 1
		recovering_peak = maxi(recovering_peak, recovering)
		choke_occupancy_peak = maxi(choke_occupancy_peak, choke_occupancy)
		var column_formations := 0
		for formation_variant in world.formations.values():
			if (formation_variant as FormationState).mode == FormationState.MovementMode.COLUMN:
				column_formations += 1
		column_formation_peak = maxi(column_formation_peak, column_formations)

	for input in pending_inputs:
		if int(input["authoritative_usec"]) >= 0:
			authoritative_input_samples.append(int(input["authoritative_usec"]))
	var unresolved_authoritative_inputs := 0
	var unresolved_presented_inputs := 0
	for input in pending_inputs:
		if int(input["authoritative_usec"]) < 0:
			unresolved_authoritative_inputs += 1
		elif not bool(input.get("presented", false)):
			unresolved_presented_inputs += 1
	var memory_static_end := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var node_count_end := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphan_node_count_end := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var resource_count_end := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	memory_static_peak = maxi(memory_static_peak, memory_static_end)
	node_count_peak = maxi(node_count_peak, node_count_end)
	orphan_node_count_peak = maxi(orphan_node_count_peak, orphan_node_count_end)
	resource_count_peak = maxi(resource_count_peak, resource_count_end)
	var capture_suffix := ""
	if sample_seconds >= LONG_RUN_SECONDS:
		capture_suffix += "_long%d" % roundi(sample_seconds)
	if projectile_count > 0:
		capture_suffix += "_p%d" % projectile_count
	if hide_hud:
		capture_suffix += "_nohud"
	if hide_battlefield:
		capture_suffix += "_nobattlefield"
	if disable_game_root_process:
		capture_suffix += "_nogameroot"
	if disable_battle_feedback:
		capture_suffix += "_nofeedback"
	var capture_path := "%s/grey_ridge_render_%d%s.png" % [CAPTURE_DIRECTORY, entity_count, capture_suffix]
	var capture_metrics := _capture_viewport(capture_path)
	var metrics := world.metrics.create_snapshot()
	var frame_p95 := _percentile(frame_samples, 0.95)
	var simulation_p95 := _percentile(simulation_samples, 0.95)
	var presented_input_p95 := _percentile(presented_input_samples, 0.95)
	var gate_applicable := entity_count == 80 and projectile_count == 0
	var expected_sample_ticks := floori(sample_seconds / SimulationWorld.TICK_SECONDS)
	var tick_completion_ratio := float(simulation_samples.size()) / float(expected_sample_ticks) if expected_sample_ticks > 0 else 1.0
	var long_run_gate_applicable := gate_applicable and sample_seconds >= LONG_RUN_SECONDS
	var long_run_stable := (
		not long_run_gate_applicable or
		tick_completion_ratio >= 0.99 and
		_maximum(simulation_samples) <= SIMULATION_P95_BUDGET_USEC and
		_maximum(frame_samples) <= LONG_RUN_MAX_FRAME_USEC and
		unresolved_authoritative_inputs <= 1 and
		unresolved_presented_inputs <= 1 and
		int(metrics.path_failed_total) == 0 and
		memory_static_end - memory_static_start <= LONG_RUN_MAX_STATIC_MEMORY_GROWTH_BYTES and
		node_count_end - node_count_start <= LONG_RUN_MAX_NODE_GROWTH and
		orphan_node_count_end - orphan_node_count_start <= LONG_RUN_MAX_ORPHAN_GROWTH
	)
	var passes_gate := (
		not gate_applicable or
		environment_supports_60fps and
		frame_p95 <= FRAME_P95_BUDGET_USEC and
		simulation_p95 <= SIMULATION_P95_BUDGET_USEC and
		presented_input_p95 <= PRESENTED_INPUT_P95_BUDGET_USEC and
		simulation_entity_peak >= entity_count and
		proxy_peak > 0 and
		projectile_peak >= projectile_count and
		rejected_inputs == 0 and
		float(capture_metrics["nonblank_ratio"]) >= 0.05 and
		long_run_stable
	)
	var result := {
		"entities": entity_count,
		"sample_seconds": float(Time.get_ticks_usec() - sample_started_usec) / 1000000.0,
		"sample_frames": frame_samples.size(),
		"sample_ticks": simulation_samples.size(),
		"expected_sample_ticks": expected_sample_ticks,
		"tick_completion_ratio": tick_completion_ratio,
		"frame_average_usec": _average(frame_samples),
		"frame_p95_usec": frame_p95,
		"frame_max_usec": _maximum(frame_samples),
		"frames_over_budget_ratio": _ratio_over(frame_samples, FRAME_P95_BUDGET_USEC),
		"environment_supports_60fps": environment_supports_60fps,
		"main_process_average_usec": _average(process_samples),
		"main_process_p95_usec": _percentile(process_samples, 0.95),
		"simulation_average_usec": _average(simulation_samples),
		"simulation_p95_usec": simulation_p95,
		"simulation_max_usec": _maximum(simulation_samples),
		"tick_profile_average_usec": _average_tick_profile_samples(tick_profile_samples),
		"validation_average_usec": _average(validation_samples),
		"validation_p95_usec": _percentile(validation_samples, 0.95),
		"input_to_authoritative_p95_usec": _percentile(authoritative_input_samples, 0.95),
		"input_to_presented_p95_usec": presented_input_p95,
		"input_samples": presented_input_samples.size(),
		"unresolved_authoritative_inputs": unresolved_authoritative_inputs,
		"unresolved_presented_inputs": unresolved_presented_inputs,
		"rejected_inputs": rejected_inputs,
		"rejected_input_reasons": rejected_input_reasons,
		"draw_calls_average": _average(draw_call_samples),
		"draw_calls_peak": _maximum(draw_call_samples),
		"render_objects_peak": _maximum(object_samples),
		"memory_static_start_bytes": memory_static_start,
		"memory_static_end_bytes": memory_static_end,
		"memory_static_peak_bytes": memory_static_peak,
		"memory_static_growth_bytes": memory_static_end - memory_static_start,
		"node_count_start": node_count_start,
		"node_count_end": node_count_end,
		"node_count_peak": node_count_peak,
		"node_count_growth": node_count_end - node_count_start,
		"orphan_node_count_start": orphan_node_count_start,
		"orphan_node_count_end": orphan_node_count_end,
		"orphan_node_count_peak": orphan_node_count_peak,
		"orphan_node_count_growth": orphan_node_count_end - orphan_node_count_start,
		"resource_count_start": resource_count_start,
		"resource_count_end": resource_count_end,
		"resource_count_peak": resource_count_peak,
		"resource_count_growth": resource_count_end - resource_count_start,
		"simulation_entity_peak": simulation_entity_peak,
		"presentation_proxy_peak": proxy_peak,
		"projectile_peak": projectile_peak,
		"projectile_target": projectile_count,
		"diagnostic_hide_hud": hide_hud,
		"diagnostic_hide_battlefield": hide_battlefield,
		"diagnostic_disable_game_root_process": disable_game_root_process,
		"diagnostic_disable_battle_feedback": disable_battle_feedback,
		"choke_occupancy_peak": choke_occupancy_peak,
		"column_formation_peak": column_formation_peak,
		"recovering_unit_peak": recovering_peak,
		"stuck_events": metrics.get_event_count(SimulationEvent.Kind.UNIT_STUCK),
		"path_requests": metrics.path_requests_total,
		"path_failures": metrics.path_failed_total,
		"capture_path": ProjectSettings.globalize_path(capture_path),
		"capture_nonblank_ratio": capture_metrics["nonblank_ratio"],
		"capture_color_variance": capture_metrics["color_variance"],
		"gate_applicable": gate_applicable,
		"long_run_gate_applicable": long_run_gate_applicable,
		"long_run_stable": long_run_stable,
		"passes_required_gate": passes_gate,
	}
	game.free()
	await process_frame
	return result


func _create_benchmark_world(entity_count: int, projectile_count: int) -> SimulationWorld:
	return GreyRidgeBenchmarkFixture.create_world(entity_count, true, projectile_count)


func _configure_benchmark_game(_game: GameRoot, _snapshot: WorldSnapshot) -> void:
	pass


func _measure_empty_frame_baseline() -> Dictionary:
	for _index in range(30):
		await process_frame
	var samples: Array[int] = []
	var previous := Time.get_ticks_usec()
	for _index in range(120):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(now - previous)
		previous = now
	return {
		"sample_frames": samples.size(),
		"frame_average_usec": _average(samples),
		"frame_p95_usec": _percentile(samples, 0.95),
		"frame_max_usec": _maximum(samples),
		"supports_60fps": _percentile(samples, 0.95) <= FRAME_P95_BUDGET_USEC,
	}


func _advance_world(
	world: SimulationWorld,
	host: SimulationHost,
	accumulator: float,
	samples: Variant
) -> float:
	while accumulator >= SimulationWorld.TICK_SECONDS:
		accumulator -= SimulationWorld.TICK_SECONDS
		var started := Time.get_ticks_usec()
		var previous_snapshot := host.current_snapshot
		var current_snapshot := world.advance_tick()
		host.previous_snapshot = previous_snapshot
		host.current_snapshot = current_snapshot
		if samples is Array:
			samples.append(Time.get_ticks_usec() - started)
	return accumulator


func _capture_viewport(path: String) -> Dictionary:
	var absolute_directory := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	var image := root.get_texture().get_image()
	image.save_png(path)
	var samples := 0
	var nonblank := 0
	var luminance_sum := 0.0
	var luminance_squared_sum := 0.0
	for y in range(0, image.get_height(), 12):
		for x in range(0, image.get_width(), 12):
			var color := image.get_pixel(x, y)
			var luminance := color.get_luminance()
			samples += 1
			luminance_sum += luminance
			luminance_squared_sum += luminance * luminance
			if luminance > 0.025:
				nonblank += 1
	var average_luminance := luminance_sum / float(samples) if samples > 0 else 0.0
	return {
		"nonblank_ratio": float(nonblank) / float(samples) if samples > 0 else 0.0,
		"color_variance": maxf(0.0, luminance_squared_sum / float(samples) - average_luminance * average_luminance) if samples > 0 else 0.0,
	}


func _parse_options() -> Dictionary:
	var entity_counts: Array[int] = DEFAULT_ENTITY_COUNTS.duplicate()
	var sample_seconds := DEFAULT_SAMPLE_SECONDS
	var projectile_count := PROJECTILE_PEAK
	var hide_hud := false
	var hide_battlefield := false
	var disable_game_root_process := false
	var disable_battle_feedback := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--entities="):
			entity_counts.clear()
			for value in argument.trim_prefix("--entities=").split(","):
				var count := int(value)
				if count > 0:
					entity_counts.append(count)
		elif argument.begins_with("--sample-seconds="):
			sample_seconds = maxf(3.0, float(argument.trim_prefix("--sample-seconds=")))
		elif argument.begins_with("--projectiles="):
			projectile_count = maxi(0, int(argument.trim_prefix("--projectiles=")))
		elif argument == "--hide-hud":
			hide_hud = true
		elif argument == "--hide-battlefield":
			hide_battlefield = true
		elif argument == "--disable-game-root-process":
			disable_game_root_process = true
		elif argument == "--disable-battle-feedback":
			disable_battle_feedback = true
	if entity_counts.is_empty():
		entity_counts.assign(DEFAULT_ENTITY_COUNTS)
	return {
		"entity_counts": entity_counts,
		"sample_seconds": sample_seconds,
		"projectile_count": projectile_count,
		"hide_hud": hide_hud,
		"hide_battlefield": hide_battlefield,
		"disable_game_root_process": disable_game_root_process,
		"disable_battle_feedback": disable_battle_feedback,
	}


func _save_report(report: Dictionary) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(REPORT_PATH.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t"))
	return file.get_error() == OK


func _average(samples: Array[int]) -> int:
	var total := 0
	for sample in samples:
		total += sample
	return total / samples.size() if not samples.is_empty() else 0


func _percentile(samples: Array[int], percentile: float) -> int:
	if samples.is_empty():
		return 0
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[clampi(ceili(percentile * sorted.size()) - 1, 0, sorted.size() - 1)]


func _maximum(samples: Array[int]) -> int:
	var result := 0
	for sample in samples:
		result = maxi(result, sample)
	return result


func _ratio_over(samples: Array[int], threshold: int) -> float:
	if samples.is_empty():
		return 0.0
	var count := 0
	for sample in samples:
		if sample > threshold:
			count += 1
	return float(count) / float(samples.size())


func _append_tick_profile_samples(samples: Dictionary, profile: Dictionary) -> void:
	for section in profile:
		if not samples.has(section):
			samples[section] = [] as Array[int]
		(samples[section] as Array[int]).append(int(profile[section]))


func _average_tick_profile_samples(samples: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for section in samples:
		result[section] = _average(samples[section] as Array[int])
	return result


func _vector2i_array(value: Vector2i) -> Array[int]:
	return [value.x, value.y]
