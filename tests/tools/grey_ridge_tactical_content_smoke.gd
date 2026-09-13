extends SceneTree


func _initialize() -> void:
	var failures := TestGreyRidgeTacticalContent.new().run()
	for failure in failures:
		push_error(failure)
	print("WARSEED_GREY_TACTICAL failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)
