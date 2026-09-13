extends SceneTree


func _initialize() -> void:
	var reports: Array[Dictionary] = []
	var fingerprints: Dictionary = {}
	var failed := false
	for profile_id in [&"direct_commitment", &"reconnaissance_first", &"flanking_advance", &"direct_commitment", &"reconnaissance_first", &"flanking_advance"]:
		var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
		var request := TestStaffPlans.request()
		var plans := StaffPlanGenerator.new().generate(world.create_snapshot(), 1, request)
		var plan: StaffCourseOfAction
		for candidate in plans.plans:
			if candidate.profile_id == profile_id:
				plan = candidate
		if plan == null:
			push_error("missing audit plan: %s" % profile_id)
			quit(1)
			return
		world.submit_command(StaffPlanApprovalCommand.new(world.allocate_command_id(), 1, world.current_tick, request, plan.profile_id, plan.fingerprint()))
		var maximum_tick_usec := 0
		for _tick in range(world.battle_definition.time_limit_ticks + 1):
			var started := Time.get_ticks_usec()
			world.advance_tick()
			maximum_tick_usec = maxi(maximum_tick_usec, Time.get_ticks_usec() - started)
			if world.battle_outcome.is_terminal():
				break
		var graph := world.create_snapshot().commander_task_graphs[0]
		var rows: Array[Dictionary] = []
		for node in graph.nodes:
			rows.append({"node": String(node.node_id), "phase": node.phase, "state": node.lifecycle, "reason": String(node.reason_key),
				"started": node.started_tick, "changed": node.changed_tick, "progress": node.progress_ticks, "task": node.task_id})
		var events: PackedStringArray = []
		for event in world.events:
			if event.kind == SimulationEvent.Kind.COMMANDER_GRAPH_CHANGED:
				events.append("%d:%s" % [event.tick, event.detail])
		var fingerprint := JSON.stringify(rows).sha256_text()
		if fingerprints.has(profile_id) and fingerprints[profile_id] != fingerprint:
			failed = true
		fingerprints[profile_id] = fingerprint
		failed = failed or not world.battle_outcome.is_terminal()
		reports.append({"profile": String(profile_id), "tick": world.current_tick, "peak_tick_usec": maximum_tick_usec,
			"nodes": rows, "events": events, "fingerprint": fingerprint, "terminal": world.battle_outcome.is_terminal(), "result": world.battle_outcome.result})
		print("COMMANDER_GRAPH_AUDIT profile=%s tick=%d nodes=%s" % [profile_id, world.current_tick, rows])
	var file := FileAccess.open("res://artifacts/r4-004-execution-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"evidence": "SIMULATED", "reports": reports}, "\t"))
	file.close()
	print("COMMANDER_GRAPH_FULL_AUDIT deterministic=%s completed_matches=%d" % [not failed, reports.size()])
	quit(1 if failed else 0)
