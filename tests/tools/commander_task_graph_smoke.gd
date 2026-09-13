extends SceneTree


func _initialize() -> void:
	var failures := TestCommanderTaskGraphs.new().run()
	for failure in failures:
		push_error(failure)
	print("COMMANDER_TASK_GRAPH failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
