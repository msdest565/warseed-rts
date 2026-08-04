class_name TestPlayerInput
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_formation_selection_and_groups(failures)
	_test_box_selection_and_command_deduplication(failures)
	_test_drag_input_event_sequence(failures)
	_test_produced_unit_can_be_selected(failures)
	_test_stop_and_attack_move_input(failures)
	_test_q_context_attack_and_range_preview(failures)
	_test_role_filtered_attack_and_targeted_orders(failures)
	_test_context_attack_input(failures)
	_test_engineering_and_building_attack_input(failures)
	return failures


func _test_formation_selection_and_groups(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	input.select_at(host.current_snapshot.get_unit(1).position)
	_expect(input.selected_entity_ids == [1], "plain point selection should select only the clicked unit", failures)
	var single_move := input.move_selected_to(host.current_snapshot.get_unit(1).position + Vector2(96.0, 0.0))
	_expect(single_move != null and single_move.is_accepted(), "single selected unit should accept an individual move", failures)
	host.advance_tick()
	_expect(host.current_snapshot.get_unit(1).formation_id == 0, "individual move should detach only the selected unit from formation following", failures)
	_expect(host.current_snapshot.get_unit(2).formation_id == SimulationWorld.DEFAULT_FORMATION_ID, "individual move should leave unselected formation members in place", failures)
	input.select_at(host.current_snapshot.get_unit(2).position, false, true)
	_expect(input.selected_entity_ids == [2, 3, 4, 5], "Alt point selection should select the remaining formation members", failures)
	input.assign_control_group(1)
	input.select_at(Vector2(100.0, 100.0))
	_expect(input.selected_entity_ids.is_empty(), "empty plain click should clear selection", failures)
	input.recall_control_group(1)
	_expect(input.selected_entity_ids == [2, 3, 4, 5], "control group should recall the exact stable entity IDs", failures)
	_free_fixture(fixture)


func _test_produced_unit_can_be_selected(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var factory := host.current_snapshot.get_building(SimulationWorld.PLAYER_FACTORY_ID)
	input.select_at(factory.position)
	_expect(input.selected_building_id == SimulationWorld.PLAYER_FACTORY_ID, "friendly factory should be point selectable", failures)
	var result := input.produce_unit(&"scout_vehicle")
	_expect(result != null and result.is_accepted(), "player factory should accept scout production", failures)
	for _tick in range(40):
		host.advance_tick()
	var produced := host.current_snapshot.get_unit(1100)
	_expect(produced != null, "completed production should enter the player snapshot", failures)
	if produced != null:
		input.select_at(produced.position)
		_expect(input.selected_entity_ids == [produced.entity_id], "newly produced unit should be point selectable", failures)
		_expect(produced.position.x > 396.0, "player factory deployment should avoid the left HUD interaction area", failures)
		var move_result := input.move_selected_to(produced.position + Vector2(96.0, 0.0))
		_expect(move_result != null and move_result.is_accepted(), "newly produced selected unit should accept movement", failures)
	_free_fixture(fixture)


func _test_box_selection_and_command_deduplication(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	input.select_in_rect(Rect2(Vector2(380.0, 270.0), Vector2(140.0, 130.0)))
	_expect(input.selected_entity_ids.size() == 5, "box touching formation should select all members", failures)
	var result := input.move_selected_to(Vector2(800.0, 336.0))
	_expect(result != null and result.is_accepted(), "multi-selection move should use authoritative pipeline", failures)
	_expect((fixture["host"] as SimulationHost).get_queue_size() == 1, "selected formation members should deduplicate to one command", failures)
	_free_fixture(fixture)


func _test_drag_input_event_sequence(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var overlay := fixture["overlay"] as SelectionOverlay
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(380.0, 270.0)
	input._unhandled_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(520.0, 400.0)
	motion.relative = motion.position - press.position
	input._unhandled_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	input._unhandled_input(release)
	_expect(not input.left_dragging and not overlay.drag_active, "mouse release should finish drag state cleanly", failures)
	_expect(input.selected_entity_ids == [1, 2, 3, 4, 5], "real drag input sequence should select all units inside the box", failures)
	_free_fixture(fixture)


func _test_stop_and_attack_move_input(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	input.select_at(host.current_snapshot.get_unit(1).position, false, true)
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


func _test_q_context_attack_and_range_preview(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var presentation := fixture["presentation"] as WorldPresentation
	input.attack_targeting_started.connect(presentation.begin_attack_targeting)
	input.attack_preview_changed.connect(presentation.set_attack_preview)
	input.attack_preview_cleared.connect(presentation.clear_attack_preview)
	input.select_at(host.current_snapshot.get_unit(3).position)
	var key := InputEventKey.new()
	key.keycode = KEY_Q
	key.pressed = true
	input._handle_key(key)
	_expect(input.command_mode == InputController.CommandMode.ATTACK_MOVE_TARGETING and presentation.attack_targeting_active, "Q should enter unified attack targeting and reveal selected weapon ranges", failures)
	var ground_target := host.current_snapshot.get_unit(3).position + Vector2(320.0, 0.0)
	input._update_attack_preview(ground_target)
	_expect(presentation.attack_preview_active and presentation.attack_preview_target_entity_id == 0, "ground hover should publish an attack-move marker", failures)
	var ground_result := input.attack_or_move_selected_at(ground_target)
	_expect(ground_result != null and ground_result.is_accepted(), "Q ground click should issue standalone attack-move", failures)
	host.advance_tick()
	_expect((host.world.units[3] as UnitState).is_attack_moving and (host.world.units[3] as UnitState).formation_id == 0, "standalone Q attack-move should enter authoritative state", failures)
	_expect(not presentation.attack_targeting_active, "accepted Q command should clear attack targeting visuals", failures)
	_free_fixture(fixture)


func _test_role_filtered_attack_and_targeted_orders(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var ore := host.world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState
	ore.position = (host.world.units[1] as UnitState).position + Vector2(80.0, 0.0)
	host.world._update_faction_knowledge()
	host.current_snapshot = host.world.create_snapshot()
	input.select_at(host.current_snapshot.get_unit(1).position)
	var harvest_result := input.harvest_with_selected()
	_expect(harvest_result != null and harvest_result.is_accepted(), "one selected harvester should immediately take the only known ore assignment", failures)
	host.advance_tick()
	input._set_selection([1, 2, 3, 4, 5])
	var enemy := host.world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = (host.world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState).anchor_position + Vector2(128.0, 0.0)
	host.world._update_faction_knowledge()
	host.current_snapshot = host.world.create_snapshot()
	var attack_result := input.context_command_selected_at(enemy.position)
	_expect(attack_result != null and attack_result.is_accepted(), "mixed formation should retain a valid combat attack", failures)
	host.advance_tick()
	_expect((host.world.units[1] as UnitState).harvest_ore_field_entity_id == ore.entity_id, "combat order should not interrupt the harvester", failures)
	_expect((host.world.units[2] as UnitState).attack_target_entity_id == 0, "engineer should ignore combat orders", failures)
	_expect((host.world.units[3] as UnitState).attack_target_entity_id == enemy.entity_id, "combat unit should receive the attack order", failures)
	_free_fixture(fixture)

	var defense_fixture := _create_fixture()
	var defense_input := defense_fixture["input"] as InputController
	var defense_host := defense_fixture["host"] as SimulationHost
	defense_input.begin_defend_targeting()
	_expect(defense_input.command_mode == InputController.CommandMode.DEFEND_TARGETING, "defense should enter location targeting mode", failures)
	var formation := defense_host.world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState
	var defense_position := formation.anchor_position + Vector2(160.0, 96.0)
	var defense_result := defense_input.defend_selected_at(defense_position)
	_expect(defense_result != null and defense_result.is_accepted(), "defense location should submit through the command pipeline", failures)
	_free_fixture(defense_fixture)


func _create_fixture() -> Dictionary:
	var host := SimulationHost.new()
	Engine.get_main_loop().root.add_child(host)
	host._ready()
	var presentation := WorldPresentation.new()
	var units_root := Node2D.new()
	units_root.name = "Units"
	presentation.add_child(units_root)
	var buildings_root := Node2D.new()
	buildings_root.name = "Buildings"
	presentation.add_child(buildings_root)
	var ore_root := Node2D.new()
	ore_root.name = "OreFields"
	presentation.add_child(ore_root)
	Engine.get_main_loop().root.add_child(presentation)
	presentation.units_root = units_root
	presentation.buildings_root = buildings_root
	presentation.ore_fields_root = ore_root
	presentation.set_snapshots(host.current_snapshot, host.current_snapshot, 0.0)
	var input := InputController.new()
	Engine.get_main_loop().root.add_child(input)
	var overlay := SelectionOverlay.new()
	Engine.get_main_loop().root.add_child(overlay)
	input.simulation_host = host
	input.world_presentation = presentation
	input.selection_overlay = overlay
	return {"host": host, "presentation": presentation, "input": input, "overlay": overlay}


func _free_fixture(fixture: Dictionary) -> void:
	(fixture["input"] as InputController).free()
	(fixture["overlay"] as SelectionOverlay).free()
	(fixture["presentation"] as WorldPresentation).free()
	(fixture["host"] as SimulationHost).free()


func _test_context_attack_input(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var enemy_state := host.world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy_state.position = (host.world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState).anchor_position + Vector2(128.0, 0.0)
	host.world._update_faction_knowledge()
	host.current_snapshot = host.world.create_snapshot()
	var enemy := host.current_snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID)
	input.select_at(host.current_snapshot.get_unit(1).position, false, true)
	var result := input.context_command_selected_at(enemy.position)
	_expect(result != null and result.is_accepted(), "right-clicking enemy should submit attack command", failures)
	_expect(host.get_queue_size() == 1, "formation attack input should deduplicate to one command", failures)
	_expect(host.current_snapshot.get_unit(SimulationWorld.DEFAULT_ENEMY_UNIT_ID).health == enemy.health, "input attack must wait for tick", failures)
	host.advance_tick()
	_expect(host.current_snapshot.get_unit(3).attack_target_entity_id == SimulationWorld.DEFAULT_ENEMY_UNIT_ID, "combat unit should receive the authoritative attack target", failures)
	_expect(host.current_snapshot.get_unit(1).attack_target_entity_id == 0, "harvester should ignore combat commands", failures)
	input.select_at(enemy.position)
	_expect(input.selected_entity_id == 0, "enemy should not be selectable by local player", failures)
	_free_fixture(fixture)


func _test_engineering_and_building_attack_input(failures: Array[String]) -> void:
	var build_fixture := _create_fixture()
	var build_input := build_fixture["input"] as InputController
	var build_host := build_fixture["host"] as SimulationHost
	var build_presentation := build_fixture["presentation"] as WorldPresentation
	build_input.build_preview_changed.connect(build_presentation.set_build_preview)
	build_input.build_preview_cleared.connect(build_presentation.clear_build_preview)
	build_input.begin_build_targeting(&"automated_factory")
	_expect(build_input.command_mode == InputController.CommandMode.BUILD_FACTORY_TARGETING, "build button should enter factory placement mode with an engineer selected", failures)
	_expect(build_input.selected_entity_ids == [2], "build command should select an available engineer when none is selected", failures)
	var valid_position := build_host.world.logic_grid.cell_to_world(Vector2i(24, 14))
	var valid_preview := build_host.get_build_placement_preview(2, &"automated_factory", valid_position)
	_expect(valid_preview["valid"] and valid_preview["footprint_size"] == Vector2i(3, 3), "construction preview should expose a legal factory footprint", failures)
	build_input._update_build_preview(valid_position)
	_expect(build_presentation.build_preview_active and build_presentation.build_preview_valid, "construction targeting should publish a visible legal placement preview", failures)
	var occupied_position := (build_host.world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState).position
	var occupied_preview := build_host.get_build_placement_preview(2, &"automated_factory", occupied_position)
	_expect(not occupied_preview["valid"] and occupied_preview["reason"] == CommandValidationResult.Reason.BUILDING_OCCUPIED, "construction preview should mark occupied footprints invalid", failures)
	var unsnapped_position := valid_position + Vector2(11.0, 9.0)
	_expect(build_host.get_build_placement_preview(2, &"automated_factory", unsnapped_position)["position"] == valid_position, "construction placement should snap to the authoritative logic grid", failures)
	var build_result := build_input.build_selected_at(&"automated_factory", valid_position)
	_expect(build_result != null and build_result.is_accepted(), "map placement should submit an authoritative construction command", failures)
	_expect(not build_presentation.build_preview_active, "accepted construction should clear the placement preview", failures)
	_expect(build_host.get_queue_size() == 1, "accepted construction input should wait in the shared command queue", failures)
	_free_fixture(build_fixture)

	var attack_fixture := _create_fixture()
	var attack_input := attack_fixture["input"] as InputController
	var attack_host := attack_fixture["host"] as SimulationHost
	var enemy_center := attack_host.world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState
	var formation := attack_host.world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState
	formation.anchor_position = enemy_center.position + Vector2(-96.0, 0.0)
	for index in range(formation.member_entity_ids.size()):
		var unit := attack_host.world.units[formation.member_entity_ids[index]] as UnitState
		unit.position = formation.anchor_position + Vector2(0.0, float(index - 2) * 16.0)
	attack_host.world._update_faction_knowledge()
	attack_host.current_snapshot = attack_host.world.create_snapshot()
	attack_input.select_at(attack_host.current_snapshot.get_unit(1).position, false, true)
	var attack_result := attack_input.context_command_selected_at(enemy_center.position)
	_expect(attack_result != null and attack_result.is_accepted(), "right-clicking a visible enemy building should submit an attack", failures)
	_free_fixture(attack_fixture)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
