class_name TestPlayerInput
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_army_card_selects_bound_entities(failures)
	_test_reserve_card_enters_deployment_targeting(failures)
	_test_reserve_card_drag_commits_to_assigned_commander(failures)
	_test_commander_objective_does_not_take_over_cards(failures)
	_test_commander_card_drag_submits_intent(failures)
	_test_commander_task_arrow_drag_retargets(failures)
	_test_commander_attack_route_planning(failures)
	_test_rejected_commander_route_exposes_reason(failures)
	_test_all_rejections_offer_recovery(failures)
	_test_targeting_modes_keep_controls_visible(failures)
	_test_last_seen_contact_becomes_attack_move(failures)
	_test_agent_assigned_route_can_cancel_and_execute(failures)
	_test_grey_ridge_hides_individual_selection(failures)
	_test_grey_ridge_route_editing(failures)
	_test_formation_selection_and_groups(failures)
	_test_box_selection_and_command_deduplication(failures)
	_test_drag_input_event_sequence(failures)
	_test_produced_unit_can_be_selected(failures)
	_test_stop_and_attack_move_input(failures)
	_test_q_context_attack_and_range_preview(failures)
	_test_role_filtered_attack_and_targeted_orders(failures)
	_test_produced_assault_defense_and_scout_orders(failures)
	_test_context_attack_input(failures)
	_test_harvester_attack_input_is_rejected(failures)
	_test_engineering_and_building_attack_input(failures)
	return failures


func _test_agent_assigned_route_can_cancel_and_execute(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var card := host.world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	_expect(card.control_state == UnitCardState.ControlState.AGENT_ASSIGNED, "route fixture should begin under commander Agent control", failures)
	input.begin_unit_card_route(&"ironwall_assault_group")
	_expect(input.command_mode == InputController.CommandMode.FORMATION_ROUTE_TARGETING, "a deployed Agent-assigned card should enter route mode without a separate takeover step", failures)
	var queue_before_cancel := host.get_queue_size()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	input._input(escape)
	_expect(input.command_mode == InputController.CommandMode.FORMATION_ROUTE_TARGETING and host.get_queue_size() == queue_before_cancel, "Esc must remain reserved for pause and must not cancel formation route planning", failures)
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_C
	cancel.pressed = true
	input._input(cancel)
	_expect(input.command_mode == InputController.CommandMode.NORMAL and input.formation_route_points.is_empty() and host.get_queue_size() == queue_before_cancel, "C should leave formation route mode, clear its preview, and submit no command", failures)

	input.begin_unit_card_route(&"ironwall_assault_group")
	var formation := host.world.formations.get(card.formation_id) as FormationState
	var route_target := formation.anchor_position + Vector2(64.0, -192.0)
	input.formation_route_points = PackedVector2Array([route_target])
	var result := input.submit_selected_formation_route()
	_expect(result != null and result.is_accepted() and input.command_mode == InputController.CommandMode.NORMAL, "Execute should submit a waypoint-only formation route and exit planning (reason=%s)" % (result.reason if result != null else -1), failures)
	_expect(card.control_state == UnitCardState.ControlState.PLAYER_OVERRIDDEN, "an accepted direct route should atomically take over the whole card", failures)
	host.advance_tick()
	_expect(formation != null and formation.planned_route == PackedVector2Array([route_target]) and formation.is_moving, "the authoritative tick should commit and start the submitted route", failures)
	_free_fixture(fixture)


func _test_commander_attack_route_planning(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	input.begin_commander_route(&"di_tian")
	_expect(input.command_mode == InputController.CommandMode.COMMANDER_ROUTE_TARGETING, "commander route action should enter a dedicated high-level planning mode", failures)
	var waypoint := Vector2(1824.0, 1424.0)
	input.commander_route_points = PackedVector2Array([waypoint])
	var queue_before_cancel := host.get_queue_size()
	input.begin_commander_route(&"di_tian")
	_expect(input.command_mode == InputController.CommandMode.NORMAL and input.commander_route_points.is_empty(), "pressing the active commander route action again should cancel local planning", failures)
	_expect(host.get_queue_size() == queue_before_cancel, "cancelling commander route planning must not submit or replace an authoritative order", failures)
	input.begin_commander_route(&"di_tian")
	input.commander_route_points = PackedVector2Array([waypoint])
	var result := input.submit_commander_route(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	_expect(result != null and result.is_accepted(), "commander route planning should submit through the authoritative command pipeline", failures)
	host.advance_tick()
	var commander := host.world.commanders[&"di_tian"] as CommanderState
	_expect(commander.planned_route == PackedVector2Array([waypoint]), "accepted commander intent should retain its explicit attack axis", failures)
	var ironwall := host.world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var task := host.world.tasks.get(ironwall.assigned_task_id) as TaskState
	_expect(task != null and task.planned_route == commander.planned_route, "the commander should distribute one shared route plan to subordinate unit-card Agents", failures)
	_expect(task != null and task.lifecycle == TaskState.Lifecycle.EXECUTING, "an accepted commander route must remain executable after its subordinate card target is resolved", failures)
	_free_fixture(fixture)


func _test_rejected_commander_route_exposes_reason(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	input.begin_commander_route(&"di_tian")
	var blocked_cells := host.world.logic_grid.get_blocked_cells()
	var blocked_cell: Vector2i = blocked_cells[0]
	var blocked_target := host.world.logic_grid.cell_to_world(blocked_cell)
	input.commander_route_points = PackedVector2Array([blocked_target])
	var result := input.submit_selected_commander_route()
	_expect(result != null and not result.is_accepted() and input.command_mode == InputController.CommandMode.COMMANDER_ROUTE_TARGETING, "an invalid commander route should be rejected without silently leaving planning", failures)
	var guidance := input.get_operation_guidance()
	_expect(guidance.begins_with(input.last_command_status) and guidance.contains(GameText.t(&"REASON_PATH_UNAVAILABLE")), "route guidance must expose the authoritative rejection reason instead of replacing it with generic instructions", failures)
	_expect(guidance.contains(GameText.command_recovery(CommandValidationResult.Reason.PATH_UNAVAILABLE)) and guidance.contains(GameText.t(&"STATUS_COMMANDER_ROUTE_TARGETING")), "a rejected route should retain both a legal next step and the active-mode controls", failures)
	_free_fixture(fixture)


func _test_all_rejections_offer_recovery(failures: Array[String]) -> void:
	var original_locale := TranslationServer.get_locale()
	for locale in [&"zh_CN", &"en"]:
		TranslationServer.set_locale(locale)
		for reason_index in range(1, CommandValidationResult.Reason.size()):
			var reason := reason_index as CommandValidationResult.Reason
			var result := CommandValidationResult.new(CommandValidationResult.Status.REJECTED, reason)
			var receipt := GameText.command_result(result)
			var recovery := GameText.command_recovery(reason)
			var reason_text := GameText.t(StringName("REASON_%s" % CommandValidationResult.Reason.keys()[reason]))
			_expect(not recovery.is_empty() and receipt.contains(reason_text) and receipt.contains(recovery), "every rejection reason should include its localized cause and a legal next step in %s: %s" % [locale, CommandValidationResult.Reason.keys()[reason]], failures)
	TranslationServer.set_locale(original_locale)


func _test_targeting_modes_keep_controls_visible(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var guidance_keys := {
		InputController.CommandMode.ATTACK_MOVE_TARGETING: &"STATUS_ATTACK_MOVE_TARGET",
		InputController.CommandMode.BUILD_FACTORY_TARGETING: &"STATUS_BUILD_TARGET",
		InputController.CommandMode.BUILD_SUPPORT_TARGETING: &"STATUS_BUILD_TARGET",
		InputController.CommandMode.REPAIR_TARGETING: &"STATUS_REPAIR_TARGET",
		InputController.CommandMode.HARVEST_TARGETING: &"STATUS_HARVEST_TARGET",
		InputController.CommandMode.DEFEND_TARGETING: &"STATUS_DEFEND_TARGET",
		InputController.CommandMode.SCOUT_TARGETING: &"STATUS_SCOUT_TARGET",
		InputController.CommandMode.RALLY_TARGETING: &"STATUS_RALLY_TARGET",
		InputController.CommandMode.DEPLOY_UNIT_CARD_TARGETING: &"GUIDANCE_DEPLOY_UNIT_CARD_TARGET",
		InputController.CommandMode.FORMATION_ROUTE_TARGETING: &"STATUS_ROUTE_TARGETING",
		InputController.CommandMode.COMMANDER_ROUTE_TARGETING: &"STATUS_COMMANDER_ROUTE_TARGETING",
	}
	for mode_variant in guidance_keys:
		input.command_mode = mode_variant as InputController.CommandMode
		input.route_feedback_override = ""
		input.last_command_status = "REJECTED RECEIPT"
		var guidance := input.get_operation_guidance()
		_expect(guidance.begins_with(input.last_command_status) and guidance.contains(GameText.t(guidance_keys[mode_variant] as StringName)), "targeting mode should retain its controls after status changes: %s" % InputController.CommandMode.keys()[int(mode_variant)], failures)
	input.command_mode = InputController.CommandMode.NORMAL
	_expect(input.get_operation_guidance() == input.last_command_status, "normal mode should not display stale targeting controls", failures)
	_free_fixture(fixture)


func _test_last_seen_contact_becomes_attack_move(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var scout := host.world.units[(host.world.unit_cards[&"falcon_recon_group"] as UnitCardState).member_entity_ids[0]] as UnitState
	var hostile := host.world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	var scout_origin := scout.position
	scout.position = hostile.position
	host.world._update_faction_knowledge()
	scout.position = scout_origin
	host.world._update_faction_knowledge()
	host.current_snapshot = host.world.create_snapshot()
	var hidden_contact: UnitSnapshot
	for unit in host.current_snapshot.units:
		if unit.enabled and unit.faction_id != SimulationWorld.LOCAL_PLAYER_ID and not unit.is_visible_to_local_player:
			hidden_contact = unit
			break
	if hidden_contact == null:
		_expect(false, "last-seen contact fixture requires a hidden hostile intelligence snapshot", failures)
		_free_fixture(fixture)
		return
	input.select_unit_card(&"ironwall_assault_group")
	var result := input.attack_or_move_selected_at(hidden_contact.position)
	var queued := host.world.command_queue.snapshot()
	var attack_move: AttackMoveCommand
	if not queued.is_empty() and queued[-1] is AttackMoveCommand:
		attack_move = queued[-1] as AttackMoveCommand
	_expect(hidden_contact != null and result != null and result.is_accepted(), "clicking a last-seen contact should issue a valid investigation order", failures)
	_expect(attack_move != null and attack_move.target_position.is_equal_approx(hidden_contact.position), "last-seen intelligence should convert to attack-move at the recorded position rather than a hidden-target attack", failures)
	_expect(input.last_command_status == GameText.t(&"STATUS_ATTACK_MOVE_LAST_SEEN") % GameText.command_result(result), "the operation receipt should identify the order as investigation of a last-seen position", failures)
	_free_fixture(fixture)


func _test_commander_objective_does_not_take_over_cards(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	input.select_commander_card(&"di_tian")
	var result := input.context_command_selected_at(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	_expect(result != null and result.is_accepted(), "commander-card context input should submit a high-level commander objective", failures)
	_expect(host.get_queue_size() == 1, "commander intent should enqueue one authoritative high-level command", failures)
	host.advance_tick()
	var ironwall := host.world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var commander := host.world.commanders[&"di_tian"] as CommanderState
	_expect(ironwall.control_state == UnitCardState.ControlState.AGENT_ASSIGNED, "commander-level map intent must not trigger player takeover", failures)
	_expect(commander.target_position == SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, "commander-level input should update the named Agent objective", failures)
	_free_fixture(fixture)


func _test_commander_card_drag_submits_intent(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var presentation := fixture["presentation"] as WorldPresentation
	input.commander_intent_preview_changed.connect(presentation.set_commander_intent_preview)
	input.commander_intent_preview_cleared.connect(presentation.clear_commander_intent_preview)
	var drag_start := Vector2(420.0, 680.0)
	var army_board := ArmyBoard.new()
	army_board.input_controller = input
	var card_press := InputEventMouseButton.new()
	card_press.button_index = MOUSE_BUTTON_LEFT
	card_press.pressed = true
	card_press.global_position = drag_start
	army_board._handle_commander_button_input(card_press, &"di_tian")
	var card_motion := InputEventMouseMotion.new()
	card_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	card_motion.global_position = drag_start + Vector2(InputController.DRAG_THRESHOLD + 1.0, 0.0)
	army_board._handle_commander_button_input(card_motion, &"di_tian")
	_expect(input.commander_drag_active, "dragging a commander-card button past the threshold should enter formal map dragging", failures)
	var motion := InputEventMouseMotion.new()
	motion.position = SimulationWorld.GREY_RIDGE_WEST_POSITION
	motion.relative = motion.position - drag_start
	input._handle_commander_drag_input(motion)
	_expect(input.commander_drag_active and presentation.commander_intent_active and presentation.commander_intent_target == SimulationWorld.GREY_RIDGE_WEST_POSITION, "commander dragging should expose a live battlefield intent arrow", failures)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = SimulationWorld.GREY_RIDGE_WEST_POSITION
	input._handle_commander_drag_input(release)
	_expect(not input.commander_drag_active and not presentation.commander_intent_active and host.get_queue_size() == 1, "releasing a commander over the battlefield should clear preview and enqueue exactly one command", failures)
	host.advance_tick()
	var commander := host.world.commanders[&"di_tian"] as CommanderState
	_expect(commander.target_position == SimulationWorld.GREY_RIDGE_WEST_POSITION, "commander-card drag must update the named Agent only through the authoritative tick", failures)
	_expect(input.last_command_status.contains("1") and input.last_command_status.contains(GameText.t(&"RESULT_ACCEPTED")), "drag receipt should identify the affected deployed card count and command result", failures)

	var queue_before_cancel := host.get_queue_size()
	input.begin_commander_drag(&"di_tian", drag_start)
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	input._handle_commander_drag_input(cancel)
	_expect(not input.commander_drag_active and host.get_queue_size() == queue_before_cancel, "right-click should cancel commander dragging without submitting a command", failures)
	army_board.free()
	_free_fixture(fixture)


func _test_commander_task_arrow_drag_retargets(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var presentation := fixture["presentation"] as WorldPresentation
	input.commander_intent_preview_changed.connect(presentation.set_commander_intent_preview)
	input.commander_intent_preview_cleared.connect(presentation.clear_commander_intent_preview)
	input.select_commander_card(&"di_tian")
	input.issue_commander_objective(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	host.advance_tick()
	_expect(input._find_commander_task_handle_at(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION) == &"di_tian", "an active commander objective should expose a draggable map handle", failures)
	var commander_snapshot := host.current_snapshot.get_commander(&"di_tian")
	var arrow_origin := input._commander_task_origin(commander_snapshot, host.current_snapshot)
	var visible_arrow_point := arrow_origin.lerp(SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, 0.35)
	_expect(input._find_commander_task_handle_at(visible_arrow_point) == &"di_tian", "the visible task-arrow shaft should remain draggable when its target ring is covered by HUD", failures)
	var queue_before_drag := host.get_queue_size()

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = visible_arrow_point
	input._unhandled_input(press)
	_expect(input.commander_drag_active and presentation.commander_intent_active, "pressing a commander task handle should start the same live intent preview as card dragging", failures)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = SimulationWorld.GREY_RIDGE_EAST_POSITION
	input._handle_commander_drag_input(release)
	var commander := host.world.commanders[&"di_tian"] as CommanderState
	_expect(host.get_queue_size() == queue_before_drag + 1, "task-handle dragging should enqueue exactly one additional commander command", failures)
	_expect(commander.target_position == SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, "task-handle dragging must not mutate authoritative state before the next tick", failures)
	host.advance_tick()
	_expect(commander.target_position == SimulationWorld.GREY_RIDGE_EAST_POSITION and not presentation.commander_intent_active, "the authoritative tick should apply a task-arrow retarget and clear its preview", failures)
	_free_fixture(fixture)


func _test_grey_ridge_hides_individual_selection(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var member := host.current_snapshot.get_unit(9)
	input.select_at(member.position)
	_expect(input.selected_unit_card_id == &"ironwall_assault_group" and input.selected_entity_ids.size() == 12, "formal Grey Ridge selection should promote a clicked member to its whole unit card", failures)
	input.diagnostic_individual_selection_enabled = true
	input.select_at(member.position)
	_expect(input.selected_entity_ids == [member.entity_id], "F3 diagnostics should retain individual selection for development inspection only", failures)
	_free_fixture(fixture)


func _test_reserve_card_enters_deployment_targeting(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	input.select_unit_card(&"armored_spearhead")
	_expect(input.command_mode == InputController.CommandMode.DEPLOY_UNIT_CARD_TARGETING, "clicking a reserve card should enter map deployment targeting", failures)
	_expect(input.selected_unit_card_id == &"armored_spearhead" and input.selected_entity_ids.is_empty(), "reserve selection should retain card context without inventing battlefield entities", failures)
	var headquarters := host.current_snapshot.get_building(SimulationWorld.PLAYER_COMMAND_CENTER_ID)
	var result := input.deploy_selected_unit_card_at(headquarters.position + Vector2(128.0, 0.0))
	_expect(result != null and result.is_accepted() and input.command_mode == InputController.CommandMode.NORMAL, "valid map placement should submit the deployment through SimulationHost", failures)
	host.advance_tick()
	_expect(host.current_snapshot.get_unit_card(&"armored_spearhead").deployment_state == UnitCardState.DeploymentState.DEPLOYING, "deployment UI should reflect the next authoritative snapshot", failures)
	_free_fixture(fixture)


func _test_reserve_card_drag_commits_to_assigned_commander(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var army_board := ArmyBoard.new()
	army_board.input_controller = input
	army_board._snapshot = host.current_snapshot
	var drag_start := Vector2(720.0, 410.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = drag_start
	army_board._handle_unit_card_button_input(press, &"armored_spearhead")
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.global_position = drag_start + Vector2(InputController.DRAG_THRESHOLD + 1.0, 0.0)
	army_board._handle_unit_card_button_input(motion, &"armored_spearhead")
	_expect(army_board._reserve_drag_active and input.selected_unit_card_id == &"armored_spearhead", "dragging a reserve card past the threshold should enter formal commander-drop mode", failures)

	var expected_position := input._default_reserve_deployment_position(&"di_tian")
	var headquarters := host.current_snapshot.get_building(SimulationWorld.PLAYER_COMMAND_CENTER_ID)
	var queue_before_drop := host.get_queue_size()
	var result := army_board._complete_reserve_drag(&"di_tian")
	_expect(result != null and result.is_accepted(), "dropping a reserve card on its assigned commander should submit an authoritative deployment", failures)
	_expect(host.get_queue_size() == queue_before_drop + 1 and input.command_mode == InputController.CommandMode.NORMAL, "accepted reserve dragging should enqueue exactly one deployment and leave targeting mode", failures)
	_expect(expected_position.distance_to(headquarters.position) <= 384.0, "commander-drop deployment should choose a legal headquarters staging position", failures)
	var queued_deployment := host.world.command_queue.snapshot()[-1] as DeployUnitCardCommand
	var resolved_position := queued_deployment.deployment_position
	_expect(resolved_position.distance_to(headquarters.position) <= 384.0 and resolved_position.is_finite(), "deployment validation should resolve the quick-drop anchor to a legal whole-card position", failures)
	host.advance_tick()
	var armored_card := host.world.unit_cards[&"armored_spearhead"] as UnitCardState
	_expect(armored_card.deployment_state == UnitCardState.DeploymentState.DEPLOYING and armored_card.deployment_position == resolved_position, "the next authoritative tick should commit the whole reserve card at the validated commander-oriented staging point", failures)
	army_board.free()
	_free_fixture(fixture)

	var mismatch_fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var mismatch_input := mismatch_fixture["input"] as InputController
	var mismatch_host := mismatch_fixture["host"] as SimulationHost
	var supply_before := (mismatch_host.world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).supply
	var mismatch_queue_before := mismatch_host.get_queue_size()
	_expect(mismatch_input.begin_reserve_card_drag(&"armored_spearhead"), "reserve mismatch fixture should begin from a valid reserve card", failures)
	var mismatch_result := mismatch_input.deploy_reserve_card_to_commander(&"armored_spearhead", &"bai_jiuyang")
	_expect(mismatch_result != null and mismatch_result.status == CommandValidationResult.Status.REJECTED and mismatch_result.reason == CommandValidationResult.Reason.COMMANDER_MISMATCH, "battlefield reserve dragging must reject free cross-commander reassignment", failures)
	_expect(mismatch_host.get_queue_size() == mismatch_queue_before and (mismatch_host.world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).supply == supply_before, "rejected commander mismatch must not enqueue deployment or spend supply", failures)
	_free_fixture(mismatch_fixture)


func _test_grey_ridge_route_editing(failures: Array[String]) -> void:
	var fixture := _create_fixture(SimulationWorld.ScenarioKind.GREY_RIDGE)
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	input.set_unit_card_control(&"ironwall_assault_group", UnitCardControlCommand.Action.TAKEOVER)
	host.advance_tick()
	var card := host.world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var formation := host.world.formations[card.formation_id] as FormationState
	formation.planned_route = PackedVector2Array([formation.anchor_position + Vector2(64.0, -192.0)])
	formation.has_deployment_line = true
	var line_target := formation.anchor_position + Vector2(0.0, -384.0)
	formation.deployment_line_start = line_target + Vector2(0.0, -176.0)
	formation.deployment_line_end = line_target + Vector2(0.0, 176.0)
	host.current_snapshot = host.world.create_snapshot()
	input.formation_plan_preview_changed.connect((fixture["presentation"] as WorldPresentation).set_formation_plan_preview)
	input.begin_unit_card_route(&"ironwall_assault_group")
	_expect(input.command_mode == InputController.CommandMode.FORMATION_ROUTE_TARGETING and input.formation_route_points == formation.planned_route, "route editing should load the committed whole-card waypoints instead of starting from an empty plan", failures)
	_expect(input.formation_line_start == formation.deployment_line_start and input.formation_line_end == formation.deployment_line_end, "route editing should load the committed deployment line for redrawing", failures)
	var original_waypoint := input.formation_route_points[0]
	var moved_waypoint := original_waypoint + Vector2(32.0, 0.0)
	_simulate_left_drag(input, original_waypoint, moved_waypoint)
	_expect(input.formation_route_points[0] == moved_waypoint and formation.planned_route[0] == original_waypoint, "dragging a visible route handle should update only the local plan before authoritative submission", failures)
	var original_line_start := input.formation_line_start
	var moved_line_start := original_line_start + Vector2(0.0, 32.0)
	_simulate_left_drag(input, original_line_start, moved_line_start)
	_expect(input.formation_line_start == moved_line_start and formation.deployment_line_start == original_line_start, "deployment-line endpoint handles should be directly draggable without mutating authoritative state", failures)
	var submit_result := input._submit_formation_plan()
	_expect(submit_result != null and submit_result.is_accepted(), "edited route handles should still submit through the authoritative formation command (reason=%s)" % (submit_result.reason if submit_result != null else -1), failures)
	host.advance_tick()
	_expect(formation.planned_route[0] == moved_waypoint and formation.deployment_line_start == moved_line_start, "accepted route edits should update both committed waypoints and the deployment line on the next tick", failures)
	input.begin_unit_card_route(&"ironwall_assault_group")
	_expect(input.undo_formation_route_waypoint() and input.formation_route_points.is_empty(), "route editing should remove the latest waypoint without changing authoritative state before submission", failures)
	var clear_result := input.clear_selected_formation_route()
	_expect(clear_result != null and clear_result.is_accepted(), "route editing should expose an explicit authoritative clear action", failures)
	host.advance_tick()
	_expect(formation.planned_route.is_empty() and not formation.has_deployment_line and not formation.is_moving, "clearing a committed route should stop the formation and remove its deployment line", failures)
	_free_fixture(fixture)


func _simulate_left_drag(input: InputController, from_position: Vector2, to_position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from_position
	input._handle_formation_route_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to_position
	motion.relative = to_position - from_position
	input._handle_formation_route_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to_position
	input._handle_formation_route_input(release)


func _test_army_card_selects_bound_entities(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	input.select_unit_card(&"ironwall_assault_group")
	_expect(input.selected_entity_ids == [4, 5], "unit-card selection should select every live entity bound to the persistent card", failures)
	_expect(input.selected_unit_card_id == &"ironwall_assault_group" and input.selected_commander_id == &"di_tian", "unit-card selection should retain its army-board context", failures)
	input.select_commander_card(&"bai_jiuyang")
	_expect(input.selected_entity_ids == [3] and input.selected_commander_id == &"bai_jiuyang", "commander-card selection should select all subordinate unit-card entities", failures)
	_free_fixture(fixture)


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
	defense_input._set_selection([4])
	defense_input.begin_defend_targeting()
	_expect(defense_input.command_mode == InputController.CommandMode.DEFEND_TARGETING, "defense should enter location targeting mode", failures)
	var formation := defense_host.world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState
	var defense_position := formation.anchor_position + Vector2(160.0, 96.0)
	var defense_result := defense_input.defend_selected_at(defense_position)
	_expect(defense_result != null and defense_result.is_accepted(), "defense location should submit through the command pipeline", failures)
	_free_fixture(defense_fixture)


func _test_produced_assault_defense_and_scout_orders(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var production := host.create_produce_unit_command(SimulationWorld.PLAYER_FACTORY_ID, &"assault_vehicle")
	_expect(host.submit_command(production).is_accepted(), "assault production should enter the authoritative queue", failures)
	for _tick in range(40):
		host.advance_tick()
	var produced := host.current_snapshot.get_unit(1100)
	_expect(produced != null and produced.definition_id == &"assault_vehicle", "factory should produce a selectable assault unit", failures)
	if produced != null:
		input.select_at(produced.position)
		_expect(input.selected_entity_ids == [1100], "new assault should be individually selectable", failures)
		input.begin_defend_targeting()
		var defense_result := input.defend_selected_at(produced.position + Vector2(96.0, 0.0))
		_expect(defense_result != null and defense_result.is_accepted(), "new assault should accept a selected defense assignment", failures)
		host.advance_tick()
		var defense_task := host.world.tasks.get(1) as TaskState
		_expect(defense_task != null and defense_task.participant_entity_ids == [1100], "selected defense should assign only the new assault", failures)
		_expect((host.world.units[1100] as UnitState).assigned_task_id == 1, "new assault should receive authoritative defense ownership", failures)
	_free_fixture(fixture)

	var scout_fixture := _create_fixture()
	var scout_input := scout_fixture["input"] as InputController
	var scout_host := scout_fixture["host"] as SimulationHost
	scout_input._set_selection([3])
	scout_input.begin_scout_targeting()
	_expect(scout_input.command_mode == InputController.CommandMode.SCOUT_TARGETING, "selected scout should enter reconnaissance targeting", failures)
	var scout_origin := scout_host.current_snapshot.get_unit(3).position
	var observation_position := scout_origin + Vector2(256.0, 0.0)
	var observed_enemy := scout_host.world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	observed_enemy.position = observation_position + Vector2(24.0, 0.0)
	observed_enemy.can_attack = false
	var scout_result := scout_input.scout_selected_at(observation_position)
	_expect(scout_result != null and scout_result.is_accepted(), "scout-area order should use the strategic command pipeline", failures)
	for _tick in range(45):
		observed_enemy.position = observation_position + Vector2(24.0, 0.0)
		scout_host.advance_tick()
	var scout_task := scout_host.world.tasks.get(1) as TaskState
	_expect(scout_task != null and scout_task.kind == TaskState.Kind.SCOUT_AREA and scout_task.participant_entity_ids == [3], "reconnaissance should assign only selected scouts", failures)
	_expect(scout_task != null and scout_task.lifecycle == TaskState.Lifecycle.COMPLETED and scout_task.discovered_contact_count >= 1, "reconnaissance should observe for a fixed interval and report visible hostile contacts", failures)
	_free_fixture(scout_fixture)


func _create_fixture(scenario_kind: SimulationWorld.ScenarioKind = SimulationWorld.ScenarioKind.LEGACY_RTS) -> Dictionary:
	var host := SimulationHost.new()
	host.scenario_kind = scenario_kind
	Engine.get_main_loop().root.add_child(host)
	host._ready()
	if scenario_kind == SimulationWorld.ScenarioKind.GREY_RIDGE:
		host.start_grey_ridge(ArmyPlan.grey_ridge_default())
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


func _test_harvester_attack_input_is_rejected(failures: Array[String]) -> void:
	var fixture := _create_fixture()
	var input := fixture["input"] as InputController
	var host := fixture["host"] as SimulationHost
	var harvester := host.world.units[1] as UnitState
	var enemy := host.world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
	enemy.position = harvester.position + Vector2(48.0, 0.0)
	enemy.can_attack = false
	enemy.health = 1.0
	host.world._update_faction_knowledge()
	host.current_snapshot = host.world.create_snapshot()
	input.select_at(harvester.position)
	var result := input.context_command_selected_at(enemy.position)
	_expect(result != null and result.status == CommandValidationResult.Status.REJECTED and result.reason == CommandValidationResult.Reason.INVALID_DEFINITION, "a selected harvester should clearly reject an active attack order", failures)
	_expect(host.get_queue_size() == 0 and harvester.attack_target_entity_id == 0, "rejected harvester attacks must not enqueue or acquire a target", failures)
	for _tick in range(6):
		host.advance_tick()
	_expect(enemy.enabled and is_equal_approx(enemy.health, 1.0), "clicking a passive enemy with a harvester must not damage or instantly destroy it", failures)
	_free_fixture(fixture)

	var produced_fixture := _create_fixture()
	var produced_input := produced_fixture["input"] as InputController
	var produced_host := produced_fixture["host"] as SimulationHost
	var command_center := produced_host.current_snapshot.get_building(SimulationWorld.PLAYER_COMMAND_CENTER_ID)
	produced_input.select_at(command_center.position)
	var production_result := produced_input.produce_unit(&"harvester")
	_expect(production_result != null and production_result.is_accepted(), "command center should accept the produced-harvester regression fixture", failures)
	for _tick in range(35):
		produced_host.advance_tick()
	var produced := produced_host.world.units.get(1100) as UnitState
	_expect(produced != null and produced.can_harvest, "new harvester should complete production for attack-order regression coverage", failures)
	if produced != null:
		var produced_enemy := produced_host.world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState
		produced_enemy.position = produced.position + Vector2(48.0, 0.0)
		produced_enemy.can_attack = false
		produced_enemy.health = 1.0
		produced_host.world._update_faction_knowledge()
		produced_host.current_snapshot = produced_host.world.create_snapshot()
		produced_input.select_at(produced.position)
		var produced_result := produced_input.context_command_selected_at(produced_enemy.position)
		_expect(produced_result != null and produced_result.reason == CommandValidationResult.Reason.INVALID_DEFINITION, "newly produced harvesters should share the same active-attack restriction", failures)
		_expect(produced_host.get_queue_size() == 0 and produced.attack_target_entity_id == 0, "new harvester rejection must leave its command and combat state unchanged", failures)
		for _tick in range(6):
			produced_host.advance_tick()
		_expect(produced_enemy.enabled and is_equal_approx(produced_enemy.health, 1.0), "new harvester must not damage a passive clicked enemy", failures)
	_free_fixture(produced_fixture)


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
