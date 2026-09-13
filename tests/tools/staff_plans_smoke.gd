extends SceneTree


func _initialize() -> void:
	var failures := TestStaffPlans.new().run()
	var measurements: Array[Dictionary] = []
	var sample: StaffPlanSet
	for count in [60, 80]:
		var world := GreyRidgeBenchmarkFixture.create_world(count)
		var generator := StaffPlanGenerator.new()
		var durations: Array[float] = []
		for index in range(150):
			var snapshot := world.advance_tick()
			var start := Time.get_ticks_usec()
			var plans := generator.generate(snapshot, 1, TestStaffPlans.request())
			durations.append(float(Time.get_ticks_usec() - start) / 1000.0)
			if index == 0:
				sample = plans
			if plans == null:
				failures.append("active benchmark requires at least two alternatives")
		durations.sort()
		measurements.append({"entities": count, "samples": durations.size(), "planning_p95_ms": durations[142]})
		if durations[142] > 10.0:
			failures.append("planning exceeds its 10ms on-demand budget")
	var report := {"work_item_id": "WS-R4-002", "source": "SIMULATED", "status": "PASS" if failures.is_empty() else "FAIL",
		"measurements": measurements, "failures": failures, "sample": sample.to_dictionary() if sample != null else {}}
	var file := FileAccess.open("res://artifacts/r4-002-staff-plans.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("STAFF_PLANS status=%s measurements=%s failures=%s" % [report.status, measurements, failures])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
