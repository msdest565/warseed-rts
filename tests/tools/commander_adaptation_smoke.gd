extends SceneTree
func _initialize() -> void:
	var failures := TestCommanderAdaptation.new().run()
	for failure in failures: push_error(failure)
	print("COMMANDER_ADAPTATION failures=", failures)
	quit(0 if failures.is_empty() else 1)
