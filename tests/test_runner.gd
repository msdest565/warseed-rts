extends SceneTree


func _initialize() -> void:
	var suites: Array[RefCounted] = [
		TestCommandPipeline.new(),
		TestSimulationWorld.new(),
		TestNavigation.new(),
		TestObservability.new(),
		TestDataResources.new(),
		TestMapDefinition.new(),
		TestPlayerInput.new(),
		TestCombatSystem.new(),
		TestEconomyAndVictory.new(),
		TestFactionKnowledge.new(),
		TestStrategicTasks.new(),
		TestGameIntegration.new(),
	]
	var failures: Array[String] = []
	var suite_count := 0
	for suite in suites:
		suite_count += 1
		print("WARSEED test suite %d/%d started: %s" % [suite_count, suites.size(), suite.get_class()])
		failures.append_array(suite.run())
		print("WARSEED test suite %d/%d completed: %s" % [suite_count, suites.size(), suite.get_class()])

	if failures.is_empty():
		print("WARSEED tests passed: %d suites" % suite_count)
		quit(0)
		return

	for failure in failures:
		push_error("TEST FAILED: %s" % failure)
	print("WARSEED tests failed: %d failures" % failures.size())
	quit(1)
