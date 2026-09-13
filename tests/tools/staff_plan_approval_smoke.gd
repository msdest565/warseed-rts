extends SceneTree


func _initialize() -> void:
	var failures := TestStaffPlanApproval.new().run()
	for failure in failures:
		push_error(failure)
	print("STAFF_PLAN_APPROVAL failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
