extends SceneTree

const ENTITY_COUNTS: Array[int] = [40, 80, 120]
const WARMUP_TICKS := 60
const SAMPLE_TICKS := 300
const EIGHTY_ENTITY_TICK_BUDGET_USEC := 100000


func _initialize() -> void:
	var failed := false
	for entity_count in ENTITY_COUNTS:
		var result := _benchmark(entity_count)
		print("WARSEED_PERF %s" % JSON.stringify(result))
		if entity_count == 80 and int(result["simulation_p95_usec"]) > EIGHTY_ENTITY_TICK_BUDGET_USEC:
			failed = true
			push_error("80-entity simulation P95 exceeded the 10 Hz budget")
	quit(1 if failed else 0)


func _benchmark(entity_count: int) -> Dictionary:
	var world := _create_benchmark_world(entity_count)
	for _tick in range(WARMUP_TICKS):
		world.advance_tick()
	var presentation := WorldPresentation.new()
	presentation.units_root = Node2D.new()
	presentation.buildings_root = Node2D.new()
	presentation.ore_fields_root = Node2D.new()
	presentation.add_child(presentation.units_root)
	presentation.add_child(presentation.buildings_root)
	presentation.add_child(presentation.ore_fields_root)
	var simulation_samples: Array[int] = []
	var presentation_samples: Array[int] = []
	var previous := world.create_true_state_snapshot()
	for _tick in range(SAMPLE_TICKS):
		var started := Time.get_ticks_usec()
		world.advance_tick()
		var current := world.create_true_state_snapshot()
		simulation_samples.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		presentation.set_snapshots(previous, current, 1.0)
		presentation_samples.append(Time.get_ticks_usec() - started)
		previous = current
	var result := {
		"entities": entity_count,
		"sample_ticks": SAMPLE_TICKS,
		"simulation_average_usec": _average(simulation_samples),
		"simulation_p95_usec": _percentile(simulation_samples, 0.95),
		"simulation_max_usec": _maximum(simulation_samples),
		"presentation_average_usec": _average(presentation_samples),
		"presentation_p95_usec": _percentile(presentation_samples, 0.95),
		"presentation_max_usec": _maximum(presentation_samples),
		"presentation_proxy_count": presentation._proxies.size(),
	}
	presentation.free()
	return result


func _create_benchmark_world(entity_count: int) -> SimulationWorld:
	return GreyRidgeBenchmarkFixture.create_world(entity_count)


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
