extends SceneTree

const Life := CommanderTaskNodeSnapshot.Lifecycle
const Phase := CommanderTaskStageDefinition.Phase
const PROFILES: Array[StringName] = [&"direct_commitment", &"flanking_advance", &"reconnaissance_first"]
const ENEMIES: Array[StringName] = [&"central_assault", &"western_hook", &"western_feint"]
var failed := false

func _initialize() -> void:
	var reports: Array[Dictionary] = []
	var fingerprints: Dictionary = {}
	var complete_by_profile: Dictionary = {}
	var successes := 0
	for repeat_index in range(2):
		for enemy in ENEMIES:
			for profile in PROFILES:
				var report := _run(enemy,profile)
				report["repeat"] = repeat_index
				reports.append(report)
				var key := "%s/%s" % [enemy,profile]
				if fingerprints.has(key) and fingerprints[key] != report.fingerprint: _fail("repeat divergence: "+key)
				fingerprints[key] = report.fingerprint
				if repeat_index == 0 and report.plan_complete:
					successes += 1
					complete_by_profile[profile] = int(complete_by_profile.get(profile,0))+1
				var summary := report.duplicate()
				summary.erase("trace")
				summary.erase("initial_plan")
				print("R4_EXIT ",JSON.stringify(summary))
	var complete_profiles := 0
	for count in complete_by_profile.values():
		if count == 3: complete_profiles += 1
	if successes < 6 or complete_profiles < 2: _fail("D-029 completion threshold unmet: %d/9, profiles=%d" % [successes,complete_profiles])
	var file := FileAccess.open("res://artifacts/r4-phase-exit-audit.json",FileAccess.WRITE)
	if file == null:
		_fail("cannot write exit audit")
	else:
		file.store_string(JSON.stringify({"evidence":"SIMULATED","decision":"D-029","pass":not failed,"successes":successes,"combinations":9,"complete_profiles":complete_profiles,"reports":reports},"\t"))
		file.close()
	print("R4_EXIT_GATE pass=%s successes=%d/9 profiles=%d matches=%d" % [not failed,successes,complete_profiles,reports.size()])
	quit(1 if failed else 0)

func _run(enemy: StringName, profile: StringName) -> Dictionary:
	var world := SimulationWorld.new(true,false,SimulationWorld.ScenarioKind.GREY_RIDGE,{},enemy)
	var request := TestStaffPlans.request()
	var plan: StaffCourseOfAction
	for candidate in StaffPlanGenerator.new().generate(world.create_snapshot(),1,request).plans:
		if candidate.profile_id == profile: plan=candidate
	if plan == null:
		_fail("missing requested plan")
		return {"fingerprint":"missing","plan_complete":false}
	var initial_plan := JSON.stringify(plan.to_dictionary())
	var accepted := world.submit_command(StaffPlanApprovalCommand.new(world.allocate_command_id(),1,0,request,profile,plan.fingerprint())).is_accepted()
	if not accepted: _fail("initial approval rejected")
	var complete := false
	var completed_tick := -1
	var corrections: Array[Dictionary] = []
	var required_keys: Array[StringName] = []
	var trace: PackedStringArray = []
	var event_cursor := 0
	while not world.battle_outcome.is_terminal() and world.current_tick <= world.battle_definition.time_limit_ticks:
		var snapshot := world.create_faction_snapshot(1)
		if not snapshot.commander_task_graphs.is_empty():
			var graph := snapshot.commander_task_graphs[0]
			if not complete and not graph.retreat_requested:
				var all_complete := true
				for node in graph.nodes:
					if node.phase == Phase.EXPLOIT and node.lifecycle != Life.COMPLETED: all_complete=false
				complete=all_complete
				if complete: completed_tick=snapshot.tick
			# A monitor identifies exhausted authoritative work; it does not count silence as success.
			if not complete and not graph.retreat_requested:
				for node in graph.nodes:
					if node.phase == Phase.RETREAT or required_keys.has(graph.graph_id): continue
					var needs_correction := node.lifecycle == Life.FAILED or node.lifecycle == Life.BLOCKED and graph.replan_count >= graph.adaptation_policy.max_replans and snapshot.tick-node.changed_tick >= graph.adaptation_policy.interval_ticks
					if not needs_correction: continue
					required_keys.append(graph.graph_id)
					var command := CommanderCardTaskCommand.new(world.allocate_command_id(),1,GameCommand.IssuerKind.PLAYER,snapshot.tick,graph.graph_id,&"",CommanderCardTaskCommand.Action.RETREAT)
					var receipt := world.submit_command(command)
					corrections.append({"tick":snapshot.tick,"graph":String(graph.graph_id),"source_node":String(node.node_id),"reason":String(node.reason_key),"command":command.command_id,"action":"RETREAT","accepted":receipt.is_accepted(),"forced":true})
					if not receipt.is_accepted(): _fail("required correction rejected")
		world.advance_tick()
		for index in range(event_cursor,world.events.size()):
			var event := world.events[index]
			if event.kind == SimulationEvent.Kind.COMMANDER_GRAPH_CHANGED:
				trace.append("%d:%s" % [event.tick,event.detail])
				if event.detail.contains("state=adapted") and not event.detail.contains("reason="): _fail("missing adjustment reason")
		event_cursor=world.events.size()
	for correction in corrections:
		var window_count := 0
		for other in corrections:
			if other.tick <= correction.tick and correction.tick-other.tick < 6000: window_count+=1
		if window_count > 2: _fail("correction burden >2 per rolling10min")
	var final_graph := world.create_snapshot().commander_task_graphs[0]
	var recovered := 0
	var failed_retreat := 0
	for node in final_graph.nodes:
		if node.phase == Phase.RETREAT:
			if node.lifecycle == Life.COMPLETED: recovered+=1
			elif node.lifecycle == Life.FAILED: failed_retreat+=1
	if not world.battle_outcome.is_terminal(): _fail("match did not end")
	trace.append("terminal=%d:%d:complete=%s" % [world.current_tick,world.battle_outcome.result,complete])
	return {"initial_plan":initial_plan,"enemy":String(enemy),"profile":String(profile),"plan_complete":complete,"completed_tick":completed_tick,"battle_result":world.battle_outcome.result,"terminal":world.battle_outcome.is_terminal(),"tick":world.current_tick,"corrections":corrections,"required_corrections":required_keys.size(),"retreat_completed_cards":recovered,"retreat_failed_cards":failed_retreat,"trace":trace,"fingerprint":"|".join(trace).sha256_text()}

func _fail(message: String) -> void:
	failed=true
	push_error(message)
