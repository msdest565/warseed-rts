extends SceneTree

func _initialize() -> void:
	var failures := TestEnemyOperation.new().run()
	print("ENEMY_OPERATION failures=", failures)
	quit(0 if failures.is_empty() else 1)
