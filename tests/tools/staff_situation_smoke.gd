extends SceneTree


func _initialize() -> void:
	var failures := TestStaffSituation.new().run()
	var measurements: Array[Dictionary] = []
	for count in [60, 80]:
		var world := GreyRidgeBenchmarkFixture.create_world(count)
		var assessor := StaffSituationAssessor.new()
		var durations: Array[float] = []
		for index in range(150):
			var snapshot := world.advance_tick()
			var start := Time.get_ticks_usec()
			var board := assessor.assess(snapshot, 1)
			durations.append(float(Time.get_ticks_usec() - start) / 1000.0)
			if board == null:
				failures.append("live faction assessment is missing")
		durations.sort()
		var p95 := durations[142]
		measurements.append({"entities": count, "samples": durations.size(), "assessment_p95_ms": p95})
		if p95 > 5.0:
			failures.append("staff assessment exceeds its 5 ms on-demand budget")
	var report := {"work_item_id": "WS-R4-001", "source": "SIMULATED", "status": "PASS" if failures.is_empty() else "FAIL", "measurements": measurements, "failures": failures}
	var file := FileAccess.open("res://artifacts/r4-001-staff-situation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
