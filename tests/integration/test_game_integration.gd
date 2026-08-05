class_name TestGameIntegration
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_host_and_presentation_consume_faction_snapshot(failures)
	_test_player_takeover_blocks_agent_and_rejoins(failures)
	_test_game_scene_task_and_pause_controls(failures)
	return failures


func _test_host_and_presentation_consume_faction_snapshot(failures: Array[String]) -> void:
	var host := SimulationHost.new()
	Engine.get_main_loop().root.add_child(host)
	host._ready()
	var presentation := WorldPresentation.new()
	var units_root := Node2D.new()
	units_root.name = "Units"
	var buildings_root := Node2D.new()
	buildings_root.name = "Buildings"
	var ore_root := Node2D.new()
	ore_root.name = "OreFields"
	presentation.add_child(units_root)
	presentation.add_child(buildings_root)
	presentation.add_child(ore_root)
	Engine.get_main_loop().root.add_child(presentation)
	presentation.units_root = units_root
	presentation.buildings_root = buildings_root
	presentation.ore_fields_root = ore_root
	presentation.set_snapshots(host.current_snapshot, host.current_snapshot, 0.0)
	_expect(host.current_snapshot.observer_faction_id == SimulationWorld.LOCAL_PLAYER_ID, "host should publish the local faction snapshot", failures)
	_expect(units_root.get_child_count() == host.current_snapshot.units.size(), "presentation should create one proxy per known unit", failures)
	_expect(buildings_root.get_child_count() == host.current_snapshot.buildings.size(), "presentation should create one proxy per known building", failures)
	_expect(ore_root.get_child_count() == host.current_snapshot.ore_fields.size(), "presentation should create one proxy per explored ore field", failures)
	presentation.free()
	host.free()


func _test_player_takeover_blocks_agent_and_rejoins(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, true)
	world.advance_tick()
	var task := world.tasks[SimulationWorld.TEST_TASK_ID] as TaskState
	var agent := world.agents[0] as DeterministicFormationAgent
	_expect(agent.command_issued, "test agent should issue its formation order through the shared queue", failures)
	var takeover := MoveCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		5,
		(world.units[5] as UnitState).position + Vector2(96.0, 0.0)
	)
	_expect(world.submit_command(takeover).is_accepted(), "player should be able to take over an agent-assigned member", failures)
	var overridden := world.units[5] as UnitState
	_expect(overridden.control_state == UnitState.ControlState.TEMPORARILY_OVERRIDDEN, "takeover should immediately reserve the member for the player", failures)
	_expect(task.lifecycle == TaskState.Lifecycle.BLOCKED, "participant takeover should block the owning task", failures)
	_expect(not task.has_participant(5), "overridden member should leave active task participants", failures)
	var blocked_agent_command := FormationMoveCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.AGENT,
		world.current_tick,
		1,
		SimulationWorld.DEFAULT_FORMATION_ID,
		task.target_position
	)
	blocked_agent_command.agent_id = SimulationWorld.TEST_AGENT_ID
	blocked_agent_command.task_id = SimulationWorld.TEST_TASK_ID
	_expect(world.submit_command(blocked_agent_command).is_accepted(), "remaining formation should continue after a member detaches", failures)
	_expect((world.units[5] as UnitState).control_state == UnitState.ControlState.TEMPORARILY_OVERRIDDEN, "agent must not overwrite a detached player-controlled member", failures)
	world.advance_tick()

	var return_command := UnitDispositionCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		5,
		UnitDispositionCommand.Disposition.RETURN
	)
	_expect(world.submit_command(return_command).is_accepted(), "player should be able to request an explicit return", failures)
	world.advance_tick()
	for _tick in range(120):
		if not (world.units[5] as UnitState).rejoin_pending:
			break
		world.advance_tick()
	var returned := world.units[5] as UnitState
	_expect(not returned.rejoin_pending, "return should finish without teleporting or hanging", failures)
	_expect(returned.control_state == UnitState.ControlState.AGENT_ASSIGNED, "returned member should restore agent ownership", failures)
	_expect(returned.formation_id == SimulationWorld.DEFAULT_FORMATION_ID and returned.following_formation, "returned member should restore its formation slot", failures)
	_expect(task.has_participant(5) and task.lifecycle == TaskState.Lifecycle.EXECUTING, "return should restore task participation and execution", failures)


func _test_game_scene_task_and_pause_controls(failures: Array[String]) -> void:
	var packed_scene := load("res://scenes/game/game_root.tscn") as PackedScene
	var game := packed_scene.instantiate()
	Engine.get_main_loop().root.add_child(game)
	var host := game.get_node("SimulationHost") as SimulationHost
	var panel := game.get_node("HUDLayer/TaskPanel") as TaskPanel
	var minimap := game.get_node("HUDLayer/Minimap") as MinimapControl
	var debug_layer := game.get_node("DebugLayer") as DebugLayer
	var input_controller := game.get_node("InputController") as InputController
	var workflow_panel := game.get_node("HUDLayer/WorkflowPanel") as WorkflowPanel
	var pause_menu := game.get_node("PauseMenu") as PauseMenu
	var camera := game.get_node("CameraController") as CameraController
	host._ready()
	panel.mission_label = panel.get_node("Margin/Layout/Intel/Mission")
	panel.task_label = panel.get_node("Margin/Layout/Intel/TaskStatus")
	panel.develop_button = panel.get_node("Margin/Layout/Strategic/Develop")
	panel.defend_button = panel.get_node("Margin/Layout/Strategic/Defend")
	panel.attack_button = panel.get_node("Margin/Layout/Strategic/Attack")
	panel.pause_button = panel.get_node("Margin/Layout/Operations/Grid/Pause")
	panel.resume_button = panel.get_node("Margin/Layout/Operations/Grid/Resume")
	panel.cancel_button = panel.get_node("Margin/Layout/Operations/Grid/Cancel")
	panel.simulation_host = host
	panel._ready()
	workflow_panel.title_label = workflow_panel.get_node("Margin/Layout/Title")
	workflow_panel.unit_flows_label = workflow_panel.get_node("Margin/Layout/UnitFlows")
	workflow_panel.tasks_title_label = workflow_panel.get_node("Margin/Layout/TasksTitle")
	workflow_panel.tasks_label = workflow_panel.get_node("Margin/Layout/Tasks")
	pause_menu.backdrop = pause_menu.get_node("Backdrop")
	pause_menu.continue_button = pause_menu.get_node("Backdrop/Menu/Content/Continue")
	pause_menu.exit_button = pause_menu.get_node("Backdrop/Menu/Content/Exit")
	pause_menu._ready()
	game._ready()
	camera.zoom = Vector2.ONE
	var camera_limits := camera.get_center_limits(Vector2(1280.0, 720.0))
	_expect(camera_limits.end.y + 360.0 >= CameraController.WORLD_RECT.end.y + 250.0, "camera should overscroll below the map enough to reveal terrain behind the bottom command bar", failures)
	_expect(panel.simulation_host == host, "task panel should accept the authoritative simulation host", failures)
	_expect(panel.has_node("Margin/Layout/Intel") and panel.has_node("Margin/Layout/Strategic") and panel.has_node("Margin/Layout/Operations") and panel.has_node("Margin/Layout/ProductionSection"), "task panel should separate intelligence, strategy, operations, and production", failures)
	_expect(panel.production_buttons.size() == 5, "production section should retain all five unit controls", failures)
	_expect(panel.build_factory_button.text.contains("300") and panel.production_buttons[4].text.contains("350"), "construction and production controls should expose authoritative ore costs", failures)
	_expect(workflow_panel != null and workflow_panel.has_node("Margin/Layout/UnitFlows") and workflow_panel.has_node("Margin/Layout/Tasks"), "left workflow panel should expose unit work and delegated tasks", failures)
	var panel_rect_720p := Rect2(Vector2(panel.offset_left, 720.0 + panel.offset_top), Vector2(1280.0 + panel.offset_right - panel.offset_left, panel.offset_bottom - panel.offset_top))
	var minimap_rect_720p := Rect2(Vector2(minimap.offset_left, 720.0 + minimap.offset_top), Vector2(minimap.offset_right - minimap.offset_left, minimap.offset_bottom - minimap.offset_top))
	_expect(not panel_rect_720p.intersects(minimap_rect_720p), "bottom command panel and minimap should not overlap at 1280x720", failures)
	_expect(not debug_layer.visible, "developer diagnostics should be hidden by default", failures)
	var debug_toggle := InputEventKey.new()
	debug_toggle.keycode = KEY_F3
	debug_toggle.pressed = true
	debug_layer._unhandled_input(debug_toggle)
	_expect(debug_layer.visible, "F3 should reveal developer diagnostics", failures)
	debug_layer._unhandled_input(debug_toggle)
	_expect(not debug_layer.visible, "F3 should hide developer diagnostics again", failures)
	pause_menu._select_difficulty(EnemyDifficultyProfile.Difficulty.HARD)
	_expect(host.get_enemy_difficulty() == EnemyDifficultyProfile.Difficulty.HARD, "pause menu should apply enemy difficulty to the authoritative world", failures)
	pause_menu._select_agent_authorization(AgentPolicy.Authorization.ADVISORY, StrategicTaskSystem.INDUSTRIAL_AGENT_ID)
	panel.update_snapshot(host.current_snapshot)
	_expect(host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID) == AgentPolicy.Authorization.ADVISORY and panel.develop_button.disabled, "advisory industrial authority should disable executable development orders", failures)
	pause_menu._select_agent_authorization(AgentPolicy.Authorization.ASSISTED, StrategicTaskSystem.INDUSTRIAL_AGENT_ID)
	panel.update_snapshot(host.current_snapshot)
	panel.develop_button.pressed.emit()
	_expect(host.get_queue_size() == 1, "Develop button should submit a strategic command through the host", failures)
	pause_menu.open()
	_expect(Engine.get_main_loop().paused and pause_menu.backdrop.visible, "ESC menu should pause the game and remain visible", failures)
	pause_menu.close()
	_expect(not Engine.get_main_loop().paused and not pause_menu.backdrop.visible, "Continue should resume the game and hide the menu", failures)
	pause_menu._select_language(0)
	_expect(pause_menu.language_changed.is_connected(Callable(game, "_on_language_changed")), "pause menu language signal should be connected to the game root", failures)
	_expect(TranslationServer.get_locale() == "zh_CN", "language menu should switch the runtime locale to Chinese", failures)
	_expect(pause_menu.title_label.text == "游戏暂停" and panel.title_label.text == "指挥网络", "Chinese selection should immediately refresh pause menu and HUD", failures)
	_expect(panel.selection_title_label.text == "当前选择" and panel.strategic_title_label.text == "战略指令" and panel.operations_title_label.text == "工程与控制" and panel.production_title_label.text == "单位生产", "Chinese HUD should localize every command section", failures)
	_expect(workflow_panel.title_label.text == "当前工作流程", "Chinese HUD should localize the workflow monitor", failures)
	pause_menu._select_language(1)
	_expect(TranslationServer.get_locale() == "en", "language menu should switch the runtime locale to English", failures)
	_expect(pause_menu.title_label.text == "PAUSED" and panel.title_label.text == "COMMAND NETWORK", "English selection should immediately refresh pause menu and HUD", failures)
	_expect(panel.selection_title_label.text == "SELECTION" and panel.strategic_title_label.text == "STRATEGY" and panel.operations_title_label.text == "OPERATIONS" and panel.production_title_label.text == "PRODUCTION", "English HUD should localize every command section", failures)
	_expect(workflow_panel.title_label.text == "ACTIVE WORKFLOWS", "English HUD should localize the workflow monitor", failures)
	(world_faction(host) as FactionState).ore = 120
	host.current_snapshot = host.world.create_snapshot()
	input_controller.selected_building_id = SimulationWorld.PLAYER_FACTORY_ID
	panel.update_snapshot(host.current_snapshot)
	_expect(not panel.production_buttons[2].disabled and panel.production_buttons[4].disabled, "production controls should distinguish affordable and unaffordable unit costs", failures)
	host.advance_tick()
	host.advance_tick()
	panel.update_snapshot(host.current_snapshot)
	workflow_panel.update_snapshot(host.current_snapshot)
	_expect(workflow_panel.unit_flows_label.text.contains("Mining  1") and workflow_panel.tasks_label.text.contains("T1"), "workflow monitor should show authoritative mining and task activity", failures)
	_expect(panel.develop_button.disabled and not panel.defend_button.disabled, "industrial work should not disable the parallel battlefield command domain", failures)
	input_controller.selected_building_id = 0
	input_controller.selected_entity_ids.assign([1])
	panel.update_snapshot(host.current_snapshot)
	_expect(panel.selection_label.text.contains("Harvester") and panel.selection_label.text.contains("HP"), "single-unit selection should show identity and health", failures)
	input_controller.selected_entity_ids.clear()
	input_controller.selected_building_id = SimulationWorld.PLAYER_FACTORY_ID
	panel.update_snapshot(host.current_snapshot)
	_expect(panel.selection_label.text.contains("Automated Factory"), "building selection should show the selected structure", failures)
	input_controller.selected_building_id = 0
	input_controller.selected_entity_ids.assign([1, 2, 3])
	panel.update_snapshot(host.current_snapshot)
	_expect(panel.selection_label.text.contains("3 units") and panel.selection_label.text.contains("Workers 2"), "group selection should summarize combat and worker roles", failures)
	game.free()


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func world_faction(host: SimulationHost) -> FactionState:
	return host.world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
