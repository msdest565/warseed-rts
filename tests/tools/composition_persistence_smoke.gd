extends SceneTree

func _initialize() -> void:
	var failures := TestCompositionPersistence.new().run()
	for failure in failures:
		push_error(failure)
	print("WARSEED_COMPOSITION_PERSISTENCE failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
