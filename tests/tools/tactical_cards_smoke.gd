extends SceneTree

func _initialize() -> void:
	var failures := TestTacticalCards.new().run()
	for failure in failures:
		push_error(failure)
	print("WARSEED_TACTICAL_CARDS failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
