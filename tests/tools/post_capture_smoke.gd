extends SceneTree

func _initialize() -> void:
	var failures := TestPostCaptureDecisions.new().run()
	for failure in failures:
		push_error(failure)
	print("POST_CAPTURE status=%s failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	quit(0 if failures.is_empty() else 1)
