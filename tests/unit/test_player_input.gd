class_name TestPlayerInput
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_formation_selection_and_groups(failures)
	_test_box_selection_and_command_deduplication(failures)
	_test_stop_and_attack_move_input(failures)
	_test_context_attack_input(failures)
	return failures


func _test_formation_selection_and_groups(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	input.select_at(Vector2(328.0, 336.0))
	_expect(input.selected_entity_ids.size() == 5, "point selecting a formation member should select the formation atom", failures)
	_expect(input.selected_entity_ids == [1, 2, 3, 4, 5], "formation selection should be stable and sorted", failures)
	input.assign_control_group(1)
	input.select_at(Vector2(100.0, 100.0))
	_expect(input.selected_entity_ids.is_empty(), "empty plain click should clear selection", failures)
	input.recall_control_group(1)
	_expect(input.selected_entity_ids == [1, 2, 3, 4, 5], "control group should recall stable entity IDs", failures)
	_free_fixture(fixture)


func _test_box_selection_and_command_deduplication(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	input.select_in_rect(Rect2(Vector2(180.0, 230.0), Vector2(210.0, 200.0)))
	_expect(input.selected_entity_ids.size() == 5, "box touching formation should select all members", failures)
	var result := input.move_selected_to(Vector2(800.0, 336.0))
	_expect(result != null and result.is_accepted(), "multi-selection move should use authoritative pipeline", failures)
	_expect((fixture["host"] as SimulationHost).get_queue_size() == 1, "selected formation members should deduplicate to one command", failures)
	_free_fixture(fixture)


func _test_stop_and_attack_move_input(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	input.select_at(host.current_snapshot.get_unit(1).position)
	_expect(input.selected_entity_ids.size() == 5, "command input fixture should select formation", failures)
	input.begin_attack_move_targeting()
	_expect(input.command_mode == InputController.CommandMode.ATTACK_MOVE_TARGETING, "T mode should enter attack-move targeting", failures)
	var target := host.current_snapshot.get_unit(1).position + Vector2(400.0, 0.0)
	var attack_result := input.attack_move_selected_to(target)
	_expect(attack_result != null and attack_result.is_accepted(), "attack-move input should submit authoritative formation command", failures)
	_expect(host.get_queue_size() == 1, "attack-move selected formation should deduplicate", failures)
	var stop_result := input.stop_selected()
	_expect(stop_result != null and stop_result.is_accepted(), "stop input should submit authoritative stop", failures)
	_expect(host.get_queue_size() == 1, "stop should supersede pending formation movement", failures)
	host.advance_tick()
	_expect(not (host.world.formations[1] as FormationState).is_moving, "authoritative stop should leave formation idle", failures)
	_free_fixture(fixture)


func _create_fixture() -> Dictionary:
	var host := SimulationHost.new()
	Engine.get_main_loop().root.add_child(host)
	host._ready()
	var presentation := WorldPresentation.new()
	var units_root := Node2D.new()
	units_root.name = "Units"
	presentation.add_child(units_root)
	Engine.get_main_loop().root.add_child(presentation)
	presentation.units_root = units_root
	presentation.set_snapshots(host.current_snapshot, host.current_snapshot, 0.0)
	var input := InputController.new()
	Engine.get_main_loop().root.add_child(input)
	input.simulation_host = host
	input.world_presentation = presentation
	return {"host": host, "presentation": presentation, "input": input}


func _free_fixture(fixture: Dictionary) -> void:
	(fixture["input"] as InputController).free()
	(fixture["presentation"] as WorldPresentation).free()
	(fixture["host"] as SimulationHost).free()


func _test_context_attack_input(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var enemy := host.current_snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID)
	input.select_at(host.current_snapshot.get_unit(1).position)
	var result := input.context_command_selected_at(enemy.position)
	_expect(result != null and result.is_accepted(), "right-clicking enemy should submit attack command", failures)
	_expect(host.get_queue_size() == 1, "formation attack input should deduplicate to one command", failures)
	_expect(host.current_snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID).health == enemy.health, "input attack must wait for tick", failures)
	host.advance_tick()
	_expect(host.current_snapshot.get_unit(1).attack_target_entity_id == SimulationWorld.DEFAULT_ENEMY_UNIT_ID, "attack target should reach authoritative snapshot", failures)
	input.select_at(enemy.position)
	_expect(input.selected_entity_id == 0, "enemy should not be selectable by local player", failures)
	_free_fixture(fixture)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
