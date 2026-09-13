extends "res://tests/performance/grey_ridge_windows_render_benchmark.gd"


func _create_benchmark_world(entity_count: int, projectile_count: int) -> SimulationWorld:
	var world := GreyRidgeBenchmarkFixture.create_world(entity_count, false, projectile_count)
	var request := TestStaffPlans.request()
	var plans := StaffPlanGenerator.new().generate(world.create_snapshot(), 1, request)
	assert(plans != null, "active graph performance requires approved force")
	var plan := plans.plans[0]
	var result := world.submit_command(StaffPlanApprovalCommand.new(world.allocate_command_id(), 1,
		world.current_tick, request, plan.profile_id, plan.fingerprint()))
	assert(result.is_accepted(), "performance approval must pass normal validation")
	world.advance_tick()
	assert(world.commander_task_graph_system.is_running(), "performance must sample a running graph")
	print("COMMANDER_GRAPH_PERF entities=%d graph=%s cards=%d" % [entity_count,
		world.create_snapshot().commander_task_graphs[0].graph_id, plan.assignments.size()])
	return world
