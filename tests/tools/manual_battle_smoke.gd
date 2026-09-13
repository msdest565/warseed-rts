extends SceneTree


func _initialize() -> void:
	var failures := TestManualBattleReliability.new().run()
	for failure in failures:
		push_error(failure)
	print("MANUAL_BATTLE failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)
