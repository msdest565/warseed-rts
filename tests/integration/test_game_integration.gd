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
	var pause_menu := game.get_node("PauseMenu") as PauseMenu
	host._ready()
	panel.mission_label = panel.get_node("Layout/Mission")
	panel.task_label = panel.get_node("Layout/TaskStatus")
	panel.develop_button = panel.get_node("Layout/Orders/Develop")
	panel.defend_button = panel.get_node("Layout/Orders/Defend")
	panel.attack_button = panel.get_node("Layout/Orders/Attack")
	panel.pause_button = panel.get_node("Layout/Orders/Pause")
	panel.resume_button = panel.get_node("Layout/Orders/Resume")
	panel.cancel_button = panel.get_node("Layout/Orders/Cancel")
	panel.simulation_host = host
	panel._ready()
	pause_menu.backdrop = pause_menu.get_node("Backdrop")
	pause_menu.continue_button = pause_menu.get_node("Backdrop/Menu/Content/Continue")
	pause_menu.exit_button = pause_menu.get_node("Backdrop/Menu/Content/Exit")
	pause_menu._ready()
	game._ready()
	_expect(panel.simulation_host == host, "task panel should accept the authoritative simulation host", failures)
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
	pause_menu._select_language(1)
	_expect(TranslationServer.get_locale() == "en", "language menu should switch the runtime locale to English", failures)
	_expect(pause_menu.title_label.text == "PAUSED" and panel.title_label.text == "COMMAND NETWORK", "English selection should immediately refresh pause menu and HUD", failures)
	game.free()


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
