extends SceneTree


func _initialize() -> void:
	var reports: Array[Dictionary] = []
	var fingerprints: Dictionary = {}
	var failed := false
	var has_interrupted_stage := false
	for scenario_id in [&"direct_commitment", &"reconnaissance_first", &"flanking_advance", &"direct_commitment_retreat", &"direct_commitment", &"reconnaissance_first", &"flanking_advance", &"direct_commitment_retreat"]:
		var profile_id: StringName = &"direct_commitment" if scenario_id == &"direct_commitment_retreat" else scenario_id
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
		var approval := world.submit_command(StaffPlanApprovalCommand.new(world.allocate_command_id(), 1, world.current_tick, request, plan.profile_id, plan.fingerprint()))
		if not approval.is_accepted():
			push_error("audit approval rejected: %s" % scenario_id)
			quit(1)
			return
		var retreat_accepted := false
		var maximum_tick_usec := 0
		for _tick in range(world.battle_definition.time_limit_ticks + 1):
			if scenario_id == &"direct_commitment_retreat" and world.current_tick == 320 and not world.battle_outcome.is_terminal():
				var active_graphs := world.create_snapshot().commander_task_graphs
				if not active_graphs.is_empty():
					var retreat := CommanderCardTaskCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER,
						world.current_tick, active_graphs[0].graph_id, &"", CommanderCardTaskCommand.Action.RETREAT)
					retreat_accepted = world.submit_command(retreat).is_accepted()
			var started := Time.get_ticks_usec()
			world.advance_tick()
			maximum_tick_usec = maxi(maximum_tick_usec, Time.get_ticks_usec() - started)
			if world.battle_outcome.is_terminal():
				break
		var graphs := world.create_snapshot().commander_task_graphs
		if graphs.is_empty():
			push_error("audit has no applied task graph: %s" % scenario_id)
			quit(1)
			return
		var graph := graphs[0]
		if scenario_id == &"direct_commitment_retreat" and (not retreat_accepted or not graph.retreat_requested):
			failed = true
			push_error("audit retreat was not accepted and applied")
		var rows: Array[Dictionary] = []
		var expected_nodes := 0
		for node in graph.nodes:
			var required_phase := CommanderTaskStageDefinition.Phase.RETREAT if scenario_id == &"direct_commitment_retreat" else CommanderTaskStageDefinition.Phase.EXPLOIT
			if profile_id == &"direct_commitment" and node.phase == required_phase:
				expected_nodes += 1
				if node.lifecycle != CommanderTaskNodeSnapshot.Lifecycle.COMPLETED:
					failed = true
					push_error("audit phase did not complete: %s/%s" % [scenario_id, node.node_id])
			if node.lifecycle in [CommanderTaskNodeSnapshot.Lifecycle.FAILED, CommanderTaskNodeSnapshot.Lifecycle.BLOCKED] and not node.reason_key.is_empty():
				has_interrupted_stage = true
			rows.append({"node": String(node.node_id), "phase": node.phase, "state": node.lifecycle, "reason": String(node.reason_key),
				"started": node.started_tick, "changed": node.changed_tick, "progress": node.progress_ticks, "task": node.task_id})
		var events: PackedStringArray = []
		for event in world.events:
			if event.kind == SimulationEvent.Kind.COMMANDER_GRAPH_CHANGED:
				events.append("%d:%s" % [event.tick, event.detail])
		var fingerprint := JSON.stringify(rows).sha256_text()
		if profile_id == &"direct_commitment" and expected_nodes == 0:
			failed = true
			push_error("audit expected success/failure evidence missing: %s" % scenario_id)
		if fingerprints.has(scenario_id) and fingerprints[scenario_id] != fingerprint:
			failed = true
			push_error("audit repeat diverged: %s" % scenario_id)
		fingerprints[scenario_id] = fingerprint
		failed = failed or not world.battle_outcome.is_terminal()
		reports.append({"scenario_id": String(scenario_id), "profile": String(profile_id), "retreat_accepted": retreat_accepted, "tick": world.current_tick, "peak_tick_usec": maximum_tick_usec,
			"nodes": rows, "events": events, "fingerprint": fingerprint, "terminal": world.battle_outcome.is_terminal(), "result": world.battle_outcome.result})
		print("COMMANDER_GRAPH_AUDIT scenario=%s tick=%d fingerprint=%s" % [scenario_id, world.current_tick, fingerprint])
	if fingerprints[&"direct_commitment"] == fingerprints[&"reconnaissance_first"]:
		failed = true
		push_error("normal plans must produce distinct execution trajectories")
	if not has_interrupted_stage:
		failed = true
		push_error("audit requires a blocked or failed stage with a reason")
	var file := FileAccess.open("res://artifacts/r4-004-resume-execution-audit.json", FileAccess.WRITE)
	if file == null:
		push_error("cannot write execution audit report")
		quit(1)
		return
	file.store_string(JSON.stringify({"evidence": "SIMULATED", "reports": reports}, "\t"))
	file.close()
	print("COMMANDER_GRAPH_FULL_AUDIT deterministic=%s completed_matches=%d" % [not failed, reports.size()])
	if failed:
		push_error("commander graph full audit failed")
	quit(1 if failed else 0)
