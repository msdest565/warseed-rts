class_name TestGameIntegration
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_host_and_presentation_consume_faction_snapshot(failures)
	_test_combat_snapshot_feedback_is_visible_and_transient(failures)
	_test_battle_feedback_director_aggregates_authoritative_events(failures)
	_test_operational_effects_emit_text_audio_and_map_feedback(failures)
	_test_player_takeover_blocks_agent_and_rejoins(failures)
	_test_game_scene_task_and_pause_controls(failures)
	_test_operation_selector_flow(failures)
	_test_grey_ridge_prebattle_planning(failures)
	_test_command_desk_action_receipt_persists(failures)
	_test_grey_ridge_scene_is_the_playable_slice(failures)
	_test_grey_ridge_tutorial_progression(failures)
	return failures


func _test_operation_selector_flow(failures: Array[String]) -> void:
	var packed_scene := load("res://scenes/game/battle_selector.tscn") as PackedScene
	_expect(packed_scene != null, "the project should provide a loadable operation selector scene", failures)
	if packed_scene == null:
		return
	var selector := packed_scene.instantiate() as BattleSelector
	selector.scene_changes_enabled = false
	Engine.get_main_loop().root.add_child(selector)
	selector._ready()
	_expect(selector.get_selectable_battle_count() == 4, "the operation selector should hide loader fixtures and display all four playable battles", failures)
	var grey_button := selector.get_battle_button(&"grey_ridge")
	var bridge_button := selector.get_battle_button(&"broken_bridge")
	var forest_button := selector.get_battle_button(&"fog_forest")
	var black_well_button := selector.get_battle_button(&"black_well")
	_expect(grey_button != null and bridge_button != null and forest_button != null and black_well_button != null, "each playable battle should have a keyboard-focusable operation button", failures)
	var request: Dictionary = {}
	selector.battle_requested.connect(func(scenario_id: StringName, scene_path: String) -> void:
		request["scenario_id"] = scenario_id
		request["scene_path"] = scene_path
	)
	if bridge_button != null:
		bridge_button.pressed.emit()
		selector.deploy_button.pressed.emit()
	_expect(request.get("scenario_id", &"") == &"broken_bridge" and request.get("scene_path", "") == "res://scenes/game/broken_bridge.tscn", "selecting Broken Bridge should request its own scene instead of the default battle", failures)
	_expect(selector.battle_title_label != null and selector.battle_title_label.text == GameText.t(&"BROKEN_BRIDGE_TITLE") and not selector.briefing_label.text.is_empty(), "battle selection should expose localized identity and tactical briefing before deployment", failures)
	selector.free()


func _test_grey_ridge_tutorial_progression(failures: Array[String]) -> void:
	var packed_scene := load("res://scenes/game/grey_ridge.tscn") as PackedScene
	var game := packed_scene.instantiate()
	Engine.get_main_loop().root.add_child(game)
	var tutorial := game.get_node("HUDLayer/TaskPanel/Margin/Layout/Tutorial") as TutorialPanel
	tutorial.persistence_enabled = false
	tutorial.begin()
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	tutorial.observe_snapshot(world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID))
	_expect(tutorial.visible and tutorial.current_step == TutorialPanel.Step.COMMANDER_OBJECTIVE, "first-battle training should begin in the map-external sidebar", failures)
	tutorial.observe_player_action({"category": "support", "action": "air_recon"})
	_expect(tutorial.current_step == TutorialPanel.Step.COMMANDER_OBJECTIVE and not tutorial.has_completed_fact(&"air_recon"), "tutorial facts should not complete from a click without an authoritative snapshot result", failures)
	tutorial.observe_player_action({"category": "commander", "subject": "di_tian", "action": "objective"})
	_expect(tutorial.current_step == TutorialPanel.Step.COMMANDER_OBJECTIVE, "an accepted interaction alone must not complete commander training before world confirmation", failures)
	var objective_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var objective_commander := objective_snapshot.get_commander(&"di_tian")
	objective_commander.target_region_id = &"central_relay"
	objective_commander.current_task_ids = [1]
	tutorial.observe_snapshot(objective_snapshot)
	_expect(tutorial.current_step == TutorialPanel.Step.AIR_RECON, "an authoritative commander objective should advance to reconnaissance", failures)
	var recon_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	recon_snapshot.intel_reports.append(recon_snapshot.intel_reports[0])
	tutorial.observe_snapshot(recon_snapshot)
	_expect(tutorial.current_step == TutorialPanel.Step.RESERVE_DEPLOYMENT, "the remembered reconnaissance action should complete only after a new report appears", failures)
	tutorial.observe_player_action({"category": "unit_card", "subject": "armored_spearhead", "action": "deploy"})
	var deployment_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	deployment_snapshot.get_unit_card(&"armored_spearhead").deployment_state = UnitCardState.DeploymentState.DEPLOYING
	tutorial.observe_snapshot(deployment_snapshot)
	tutorial.observe_player_action({"category": "unit_card", "subject": "ironwall_assault_group", "action": "direct_order_takeover", "route_planned": false})
	_expect(tutorial.current_step == TutorialPanel.Step.FORMATION_ROUTE, "a takeover without a planned route should not satisfy route training", failures)
	tutorial.observe_player_action({"category": "unit_card", "subject": "ironwall_assault_group", "action": "direct_order_takeover", "route_planned": true})
	var route_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	var routed_card := route_snapshot.get_unit_card(&"ironwall_assault_group")
	routed_card.control_state = UnitCardState.ControlState.PLAYER_OVERRIDDEN
	route_snapshot.get_formation(routed_card.formation_id).is_moving = true
	tutorial.observe_snapshot(route_snapshot)
	tutorial.observe_player_action({"category": "unit_card", "subject": "ironwall_assault_group", "action": "return_to_commander"})
	var return_snapshot := world.create_faction_snapshot(SimulationWorld.LOCAL_PLAYER_ID)
	return_snapshot.get_unit_card(&"ironwall_assault_group").control_state = UnitCardState.ControlState.RETURNING
	tutorial.observe_snapshot(return_snapshot)
	_expect(tutorial.current_step == TutorialPanel.Step.BATTLE_DEBRIEF and tutorial.visible, "accepted route and return actions should reach the debrief step without hiding guidance early", failures)
	tutorial._on_campaign_concluded({"cards": {}})
	_expect(not tutorial.is_active() and not tutorial.visible and tutorial.current_step == TutorialPanel.Step.COMPLETE, "battle conclusion should complete and close the six-step tutorial", failures)
	game.free()


func _test_combat_snapshot_feedback_is_visible_and_transient(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
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
	var before_fire := world.create_snapshot()
	var target := world.units[1] as UnitState
	var projectile := ProjectileState.new(777001, 3, target.entity_id, SimulationWorld.LOCAL_PLAYER_ID, (world.units[3] as UnitState).position, 900.0, 20.0, world.current_tick)
	world.projectiles[projectile.projectile_id] = projectile
	world.current_tick += 1
	var after_fire := world.create_snapshot()
	presentation.set_snapshots(before_fire, after_fire, 0.0)
	_expect(presentation.get_active_combat_effect_count() == 1, "a new authoritative projectile should create a muzzle flash in presentation only", failures)
	var health_before := target.health
	target.health -= 10.0
	world.projectiles.erase(projectile.projectile_id)
	world.current_tick += 1
	var after_impact := world.create_snapshot()
	presentation.set_snapshots(after_fire, after_impact, 0.0)
	var target_proxy := presentation._proxies.get(target.entity_id) as UnitProxy
	_expect(target.health < health_before and presentation.get_active_combat_effect_count() >= 2, "projectile disappearance plus authoritative damage should create a visible impact effect", failures)
	_expect(target_proxy != null and target_proxy.hit_flash_remaining > 0.0, "damaged units should visibly flash on receipt of authoritative damage", failures)
	var command_center := world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState
	var building_projectile := ProjectileState.new(777002, 3, command_center.entity_id, SimulationWorld.ENEMY_PLAYER_ID, command_center.position + Vector2(80.0, 0.0), 900.0, 20.0, world.current_tick)
	world.projectiles[building_projectile.projectile_id] = building_projectile
	world.current_tick += 1
	var before_building_impact := world.create_snapshot()
	presentation.set_snapshots(after_impact, before_building_impact, 0.0)
	command_center.health -= 10.0
	world.projectiles.erase(building_projectile.projectile_id)
	world.current_tick += 1
	var after_building_impact := world.create_snapshot()
	presentation.set_snapshots(before_building_impact, after_building_impact, 0.0)
	var building_proxy := presentation._building_proxies.get(command_center.entity_id) as BuildingProxy
	_expect(building_proxy != null and building_proxy.hit_flash_remaining > 0.0, "damaged buildings should visibly flash from the same authoritative projectile transition", failures)
	presentation._update_combat_effects(2.0)
	_expect(presentation.get_active_combat_effect_count() == 0, "combat effects should recycle after their short presentation lifetime", failures)
	presentation.free()


func _test_battle_feedback_director_aggregates_authoritative_events(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var snapshot := world.create_snapshot()
	var local_units: Array[UnitSnapshot] = []
	for unit in snapshot.units:
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID and unit.can_attack:
			local_units.append(unit)
	_expect(local_units.size() >= 3, "battle feedback fixture should expose three local combat sources", failures)
	if local_units.size() < 3:
		return
	var target := local_units[0]
	var director := BattleFeedbackDirector.new()
	Engine.get_main_loop().root.add_child(director)
	director._ready()
	director.reset(0)
	var message_keys: Array[StringName] = []
	var effect_kinds: Array[StringName] = []
	director.feedback_emitted.connect(func(message_key: StringName, _arguments: Array, _severity: int) -> void:
		message_keys.append(message_key)
	)
	director.effect_requested.connect(func(kind: StringName, _position: Vector2, _faction_id: int, _entity_id: int) -> void:
		effect_kinds.append(kind)
	)
	var card := snapshot.get_unit_card(target.unit_card_id)
	var events: Array[SimulationEvent] = []
	events.append(SimulationEvent.new(10, SimulationEvent.Kind.ATTACK_STARTED, local_units[0].entity_id, "target=%d" % target.entity_id))
	for index in range(3):
		events.append(SimulationEvent.new(10, SimulationEvent.Kind.PROJECTILE_FIRED, local_units[index].entity_id, "projectile=%d;target=%d" % [9000 + index, target.entity_id]))
	events.append(SimulationEvent.new(10, SimulationEvent.Kind.DAMAGE_APPLIED, 9990, "target=%d;amount=24.0;remaining=50.0" % target.entity_id))
	events.append(SimulationEvent.new(10, SimulationEvent.Kind.DAMAGE_APPLIED, 9990, "target=%d;amount=10.0;remaining=790.0" % SimulationWorld.PLAYER_COMMAND_CENTER_ID))
	if card != null:
		events.append(SimulationEvent.new(10, SimulationEvent.Kind.UNIT_CARD_REINFORCED, target.entity_id, "card=%s;strength=2" % card.definition_id))
	events.append(SimulationEvent.new(10, SimulationEvent.Kind.SCOUT_CONTACT_REPORTED, 1, "report=test"))
	director.process_events(events, snapshot)
	_expect(director.get_feedback_count(BattleFeedbackDirector.Cue.ENGAGEMENT) == 1 and effect_kinds.has(&"engagement"), "attack start should map to one formation-level engagement receipt and map pulse", failures)
	_expect(director.get_feedback_count(BattleFeedbackDirector.Cue.FOCUS_FIRE) == 1 and effect_kinds.has(&"focus"), "three sources on one target should aggregate into one focus-fire cue and map effect", failures)
	_expect(director.get_feedback_count(BattleFeedbackDirector.Cue.UNDER_PRESSURE) == 1 and effect_kinds.has(&"pressure"), "card damage should aggregate into one under-pressure cue and map effect", failures)
	_expect(director.get_feedback_count(BattleFeedbackDirector.Cue.HEADQUARTERS_CRITICAL) == 1 and effect_kinds.has(&"headquarters"), "headquarters damage should preempt ordinary combat feedback with a critical cue", failures)
	_expect(card == null or director.get_feedback_count(BattleFeedbackDirector.Cue.REINFORCEMENT) == 1 and effect_kinds.has(&"reinforcement"), "reinforcement events should identify the persistent card in text and on the map", failures)
	_expect(message_keys.has(&"BATTLE_FEEDBACK_SCOUT_REPORT") and message_keys.has(&"BATTLE_FEEDBACK_HEADQUARTERS_CRITICAL"), "scout and headquarters alerts should retain visible text independent of audio", failures)
	_expect(director.peak_concurrent_voice_count > 0 and director.peak_concurrent_voice_count <= BattleFeedbackDirector.MAX_CONCURRENT_VOICES and director.dropped_audio_count + director.preempted_audio_count > 0, "dense combat should use audio while capping concurrent voices and allowing critical-cue preemption", failures)
	var critical_stream := director._streams.get(BattleFeedbackDirector.Cue.HEADQUARTERS_CRITICAL) as AudioStreamWAV
	_expect(critical_stream != null and critical_stream.data.size() > 0, "battle cues should contain generated PCM rather than relying on missing external assets", failures)
	var play_count_before_mute := director.play_count
	var visual_count_before_mute := director.visual_count
	director.set_audio_enabled(false)
	events.append(SimulationEvent.new(100, SimulationEvent.Kind.FACTION_VICTORIOUS, SimulationWorld.LOCAL_PLAYER_ID))
	director.process_events(events, snapshot)
	_expect(director.play_count == play_count_before_mute and director.visual_count == visual_count_before_mute + 1 and director.last_message_key == &"BATTLE_FEEDBACK_VICTORY", "muting battle audio should preserve the authoritative text and visual outcome receipt", failures)
	director.free()


func _test_operational_effects_emit_text_audio_and_map_feedback(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BROKEN_BRIDGE)
	var battlefield := Battlefield.new()
	battlefield.battle_definition = world.battle_definition
	battlefield.logic_grid = world.logic_grid
	Engine.get_main_loop().root.add_child(battlefield)
	battlefield._ready()
	var route := world.battle_definition.engineering_routes[0]
	_expect(not battlefield._engineering_route_is_open(route) and battlefield._engineering_routes_root.get_child_count() > 0, "the engineering crossing should have a persistent blocked map marker before construction", failures)
	var director := BattleFeedbackDirector.new()
	Engine.get_main_loop().root.add_child(director)
	var message_keys: Array[StringName] = []
	var effect_kinds: Array[StringName] = []
	director.feedback_emitted.connect(func(message_key: StringName, _arguments: Array, _severity: int) -> void:
		message_keys.append(message_key)
	)
	director.effect_requested.connect(func(kind: StringName, _position: Vector2, _faction_id: int, _entity_id: int) -> void:
		effect_kinds.append(kind)
	)
	director.reset(world.events.size())
	var result := world.submit_command(SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, SupportOrderCommand.SupportKind.ENGINEERING_ROUTE,
		&"east_engineering_ford", &"", &"bridge_engineer_group"
	))
	_expect(result.is_accepted(), "the operational feedback fixture should accept the engineering order", failures)
	world.advance_tick()
	var snapshot := world.create_snapshot()
	director.process_events(world.events, snapshot)
	battlefield._process(0.0)
	_expect(message_keys.has(&"BATTLE_FEEDBACK_ENGINEERING_OPENED") and director.get_feedback_count(BattleFeedbackDirector.Cue.ENGINEERING) == 1, "engineering completion should emit authoritative visible text and its own audible cue", failures)
	_expect(effect_kinds.has(&"engineering_route") and battlefield._engineering_route_is_open(route), "engineering completion should emit a positioned map effect and replace the blocked crossing with an open bridge state", failures)
	var presentation := WorldPresentation.new()
	presentation.play_battle_feedback_effect(&"engineering_route", Vector2(4736.0, 2048.0), SimulationWorld.LOCAL_PLAYER_ID, 0)
	var map_effect := presentation._combat_effects.back() as Dictionary
	_expect(map_effect.get("label_key", &"") == &"MAP_FEEDBACK_ENGINEERING_ROUTE" and float(map_effect.get("duration", 0.0)) >= 3.0, "map-related operational effects should retain a readable localized label long enough to notice", failures)
	var region_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	for unit_variant in region_world.units.values():
		var unit := unit_variant as UnitState
		if unit.faction_id == SimulationWorld.ENEMY_PLAYER_ID:
			unit.enabled = false
	var west := region_world.strategic_regions[&"west_mine"] as StrategicRegionState
	var ironwall := region_world.formations[SimulationWorld.GREY_RIDGE_IRONWALL_FORMATION_ID] as FormationState
	ironwall.anchor_position = west.position
	for entity_id in ironwall.member_entity_ids:
		(region_world.units[entity_id] as UnitState).position = west.position
	var region_director := BattleFeedbackDirector.new()
	Engine.get_main_loop().root.add_child(region_director)
	var region_messages: Array[StringName] = []
	var region_effects: Array[StringName] = []
	region_director.feedback_emitted.connect(func(message_key: StringName, _arguments: Array, _severity: int) -> void:
		region_messages.append(message_key)
	)
	region_director.effect_requested.connect(func(kind: StringName, _position: Vector2, _faction_id: int, _entity_id: int) -> void:
		region_effects.append(kind)
	)
	region_director.reset(region_world.events.size())
	region_world._advance_strategic_regions()
	region_director.process_events(region_world.events, region_world.create_snapshot())
	_expect(region_messages.has(&"BATTLE_FEEDBACK_CAPTURE_STARTED_LOCAL") and region_effects.has(&"region_capture"), "starting a supply-point capture should emit localized HUD text and a positioned map effect", failures)
	_expect(region_director.get_feedback_count(BattleFeedbackDirector.Cue.REGION) == 1 and region_director.play_count == 1, "starting a supply-point capture should play its dedicated region audio cue exactly once", failures)
	presentation.play_battle_feedback_effect(&"region_capture", west.position, SimulationWorld.LOCAL_PLAYER_ID, 0)
	var capture_effect := presentation._combat_effects.back() as Dictionary
	_expect(capture_effect.get("label_key", &"") == &"MAP_FEEDBACK_REGION_CAPTURE", "capture feedback should remain visibly anchored to the affected supply point", failures)
	presentation.free()
	region_director.free()
	director.free()
	battlefield.free()


func _test_grey_ridge_prebattle_planning(failures: Array[String]) -> void:
	var packed_scene := load("res://scenes/game/grey_ridge.tscn") as PackedScene
	var game := packed_scene.instantiate()
	Engine.get_main_loop().root.add_child(game)
	var host := game.get_node("SimulationHost") as SimulationHost
	var planner := game.get_node("PrebattlePlanner") as PrebattlePlanner
	host._ready()
	planner._ready()
	game.simulation_host = host
	game.prebattle_planner = planner
	game.resource_bar = game.get_node("HUDLayer/ResourceBar") as ResourceBar
	game.scenario_status = game.get_node("HUDLayer/ScenarioStatus") as ScenarioStatus
	game.map_frame = game.get_node("HUDLayer/MapFrame") as PanelContainer
	game.camera_controller = game.get_node("CameraController") as CameraController
	planner.configure(host)
	var planning_viewport_size := Vector2(1280.0, 720.0)
	game._apply_grey_ridge_planning_layout(planning_viewport_size)
	_expect(planner.visible and not host.is_grey_ridge_battle_started(), "Grey Ridge should open on the army composition board before simulation begins", failures)
	var planning_map_rect: Rect2 = game.get_grey_ridge_map_rect()
	var planner_backdrop := planner.get_node("Backdrop") as Control
	planner._apply_layout_for_size(planning_viewport_size)
	_expect(planning_map_rect == Rect2(Vector2.ZERO, planning_viewport_size), "the prebattle background should retain a full-viewport map preview behind the configuration layer", failures)
	_expect(planner_backdrop.anchor_left == 0.0 and planner_backdrop.anchor_top == 0.0 and planner_backdrop.anchor_right == 1.0 and planner_backdrop.anchor_bottom == 1.0, "the prebattle configuration layer should fill the laptop screen instead of using a fixed side sheet", failures)
	_expect(planner.commander_grid.columns == 2 and planner.unit_card_grid.columns == 1, "1280-wide laptop planning should keep every card inside the visible scroll area", failures)
	var bai_personality := planner._personality_labels.get(&"bai_jiuyang") as Label
	var bai_doctrine := planner._doctrine_menus.get(&"bai_jiuyang") as OptionButton
	var bai_posture := planner._posture_menus.get(&"bai_jiuyang") as OptionButton
	var bai_detail := planner._tactical_detail_labels.get(&"bai_jiuyang") as Label
	_expect(bai_personality != null and bai_personality.tooltip_text.contains(GameText.t(&"PERSONALITY_CAUTIOUS_TOOLTIP")), "prebattle personality should explain its identity role and distinguish it from actionable controls", failures)
	_expect(bai_doctrine != null and bai_doctrine.tooltip_text.contains(GameText.t(&"DOCTRINE_COVERT_SEARCH_BEHAVIOR")) and bai_doctrine.tooltip_text.contains(GameText.t(&"DOCTRINE_COVERT_SEARCH_TRADEOFF")), "the selected prebattle doctrine should expose its real behavior and tradeoff", failures)
	_expect(bai_posture != null and bai_posture.tooltip_text.contains(GameText.t(&"COMMANDER_POSTURE_CAUTIOUS_TOOLTIP")), "the selected prebattle posture should explain the behavior it changes", failures)
	_expect(bai_doctrine != null and bai_doctrine.get_parent().get_node("DoctrineLabel").text == GameText.t(&"PREBATTLE_DOCTRINE_FIELD"), "the doctrine selector should have an explicit execution-method field label", failures)
	_expect(bai_posture != null and bai_posture.get_parent().get_node("PostureLabel").text == GameText.t(&"PREBATTLE_POSTURE_FIELD"), "the posture selector should have an explicit action-rules field label", failures)
	_expect(bai_detail != null and bai_detail.text.contains(GameText.t(&"DOCTRINE_COVERT_SEARCH_BEHAVIOR")), "the commander card should disclose the selected tactic without relying only on a delayed system tooltip", failures)
	if bai_doctrine != null:
		for doctrine_index in range(bai_doctrine.item_count):
			_expect(not bai_doctrine.get_popup().get_item_tooltip(doctrine_index).is_empty(), "every prebattle doctrine choice should have a per-item explanation", failures)
	if bai_posture != null:
		for posture in range(CommanderState.Posture.size()):
			_expect(not bai_posture.get_popup().get_item_tooltip(posture).is_empty(), "every prebattle posture choice should have a per-item explanation", failures)
		planner._on_posture_item_focused(CommanderState.Posture.DISENGAGE, bai_posture, bai_detail)
		_expect(bai_detail.text.contains(GameText.t(&"COMMANDER_POSTURE_DISENGAGE_TOOLTIP")), "focusing a posture choice should immediately disclose its concrete battlefield effect", failures)
	planner._apply_layout_for_size(Vector2(1920.0, 1080.0))
	_expect(planner.commander_grid.columns == 3 and planner.unit_card_grid.columns == 2, "wide desktop planning should use the available width for a compact multi-column card board", failures)
	planner._apply_layout_for_size(Vector2(480.0, 800.0))
	_expect(planner.commander_grid.columns == 1 and planner.unit_card_grid.columns == 1, "narrow prebattle layout should collapse cards into one scrollable column", failures)
	planner._apply_layout_for_size(planning_viewport_size)
	var damaged_record := {
		"format_version": ArmyRosterStore.FORMAT_VERSION,
		"scenario_id": "grey_ridge",
		"battle_count": 1,
		"replacement_points": 4,
		"merit": 0,
		"campaign_days": 0,
		"cards": {
			"ironwall_assault_group": {
				"authorized_strength": 12,
				"available_strength": 10,
				"last_battle_losses": 2,
				"cumulative_losses": 2,
				"battles_survived": 1,
				"honor_id": "",
				"equipment_id": "",
				"last_refit_days": 0,
			},
		},
	}
	host._campaign_record = damaged_record
	host._campaign_record_updated()
	_expect((planner._readiness_labels[&"ironwall_assault_group"] as Label).text.contains("10 / 12"), "prebattle card board should expose persistent depleted strength before battle", failures)
	planner._on_replenish_pressed(&"ironwall_assault_group")
	var replenished_record := host.get_campaign_record()
	var replenished_card := ((replenished_record["cards"] as Dictionary)["ironwall_assault_group"] as Dictionary)
	_expect(int(replenished_card["available_strength"]) == 12 and int(replenished_record["replacement_points"]) == 0, "prebattle refit action should spend available points and restore the card in one click", failures)
	var prebattle_command := host.create_commander_objective_command(&"di_tian", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION)
	_expect(prebattle_command.target_region_id == &"central_relay", "commander map input should resolve an objective inside a strategic region to its stable region ID", failures)
	_expect(host.submit_command(prebattle_command).reason == CommandValidationResult.Reason.SCENARIO_NOT_STARTED and host.get_queue_size() == 0, "battlefield commands must not mutate the tick-zero preview world before composition is committed", failures)
	host.advance_tick()
	_expect(host.world.current_tick == 0 and host.current_snapshot.tick == 0, "prebattle planning must keep the authoritative Grey Ridge clock at tick zero", failures)

	planner.set_unit_card_commander(&"ironwall_assault_group", &"bai_jiuyang")
	planner.set_unit_card_commander(&"armored_spearhead", &"bai_jiuyang")
	_expect(not planner.is_plan_valid() and planner.start_button.disabled and planner.get_capacity_text(&"bai_jiuyang").contains("5 / 3"), "over-capacity composition should visibly disable battle start", failures)

	var custom_plan := ArmyPlan.grey_ridge_default()
	custom_plan.set_unit_card_commander(&"thunder_fire_group", &"bai_jiuyang")
	custom_plan.set_unit_card_commander(&"armored_spearhead", &"di_tian")
	custom_plan.set_unit_card_commander(&"ironwall_assault_group", &"lin_mo")
	custom_plan.set_commander_doctrine(&"bai_jiuyang", &"alternating_cover")
	custom_plan.set_commander_doctrine(&"di_tian", &"concentrated_breakthrough")
	custom_plan.set_unit_card_starting(&"falcon_recon_group", false)
	custom_plan.set_unit_card_starting(&"ironwall_assault_group", false)
	custom_plan.set_unit_card_starting(&"thunder_fire_group", true)
	custom_plan.set_unit_card_starting(&"armored_spearhead", true)
	planner.open_prebattle(custom_plan)
	_expect(planner.is_plan_valid() and not planner.start_button.disabled, "a legal custom commander, doctrine, posture, and deployment plan should enable battle start", failures)
	var metrics_now_msec := Time.get_ticks_msec()
	planner._prebattle_started_msec = maxi(1, metrics_now_msec - 2500)
	var expected_planning_seconds := float(metrics_now_msec - planner._prebattle_started_msec) / 1000.0
	planner.set_commander_posture(&"di_tian", CommanderState.Posture.AGGRESSIVE)
	planner.set_unit_card_commander(&"ironwall_assault_group", &"bai_jiuyang")
	planner.set_unit_card_commander(&"ironwall_assault_group", &"lin_mo")
	planner._start_battle()
	var thunder := host.current_snapshot.get_unit_card(&"thunder_fire_group")
	var armor := host.current_snapshot.get_unit_card(&"armored_spearhead")
	var falcon := host.current_snapshot.get_unit_card(&"falcon_recon_group")
	_expect(host.is_grey_ridge_battle_started() and not planner.visible and host.current_snapshot.tick == 0, "starting a valid plan should hide planning and begin from authoritative tick zero", failures)
	_expect(host.current_snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID).population == 14, "custom starting cards should determine real opening population", failures)
	_expect(thunder.formation_id == 1 and armor.formation_id == 2 and falcon.deployment_state == UnitCardState.DeploymentState.RESERVE, "custom starting cards should become the two real friendly formations while other cards remain in reserve", failures)
	_expect(thunder.commander_definition_id == &"bai_jiuyang" and host.current_snapshot.get_commander(&"lin_mo").subordinate_unit_card_ids.has(&"ironwall_assault_group"), "the active command tree should match the submitted prebattle assignment", failures)
	var playtest_summary := host.get_playtest_summary()
	_expect(float(playtest_summary["prebattle_duration_seconds"]) >= expected_planning_seconds and int(playtest_summary["prebattle_plan_changes"]) == 3 and int(playtest_summary["prebattle_invalid_plan_changes"]) == 1, "starting Grey Ridge should carry wall-clock planning time, player edits, and post-edit invalid states into observability only (actual=%s)" % playtest_summary, failures)
	host.restart_grey_ridge()
	_expect(planner.visible and not host.is_grey_ridge_battle_started() and host.current_snapshot.tick == 0, "Fight Again should return to editable army composition without advancing time", failures)
	_expect(host.reset_grey_ridge_campaign_record() and host.get_campaign_record().is_empty(), "prebattle reset should clear the active persistent roster after archiving runtime data", failures)
	_expect((planner._readiness_labels[&"ironwall_assault_group"] as Label).text.contains("12 / 12"), "campaign reset should immediately restore the card board to full authorized strength", failures)
	game.free()


func _test_grey_ridge_scene_is_the_playable_slice(failures: Array[String]) -> void:
	var packed_scene := load("res://scenes/game/grey_ridge.tscn") as PackedScene
	var game := packed_scene.instantiate()
	Engine.get_main_loop().root.add_child(game)
	var host := game.get_node("SimulationHost") as SimulationHost
	var army_board := game.get_node("HUDLayer/ArmyBoard") as ArmyBoard
	var resource_bar := game.get_node("HUDLayer/ResourceBar") as ResourceBar
	var scenario_status := game.get_node("HUDLayer/ScenarioStatus") as ScenarioStatus
	var workflow_panel := game.get_node("HUDLayer/WorkflowPanel") as WorkflowPanel
	var support_panel := game.get_node("HUDLayer/SupportPanel") as SupportPanel
	var route_mode_hint := game.get_node("HUDLayer/RouteModeHint") as PanelContainer
	var route_mode_hint_label := game.get_node("HUDLayer/RouteModeHint/Label") as Label
	var battle_debrief := game.get_node("BattleDebrief") as BattleDebrief
	var task_panel := game.get_node("HUDLayer/TaskPanel") as TaskPanel
	var task_layout := task_panel.get_node("Margin/Layout") as HBoxContainer
	var input_controller := game.get_node("InputController") as InputController
	_expect(host.scenario_kind == SimulationWorld.ScenarioKind.GREY_RIDGE, "Grey Ridge scene should serialize the dedicated scenario selection", failures)
	host._ready()
	resource_bar.label = resource_bar.get_node("Label") as Label
	scenario_status.title_label = scenario_status.get_node("Margin/Layout/Title") as Label
	scenario_status.objective_label = scenario_status.get_node("Margin/Layout/Objective") as Label
	scenario_status.visible = true
	army_board.title_label = army_board.get_node("Margin/Layout/Header/Title") as Label
	army_board.hint_label = army_board.get_node("Margin/Layout/Header/Hint") as Label
	army_board.commander_row = army_board.get_node("Margin/Layout/Scroll/CommanderRow") as VBoxContainer
	army_board.input_controller = input_controller
	input_controller.simulation_host = host
	input_controller.world_presentation = game.get_node("WorldPresentation") as WorldPresentation
	input_controller.camera_controller = game.get_node("CameraController") as CameraController
	input_controller.selection_overlay = game.get_node("SelectionLayer/SelectionOverlay") as SelectionOverlay
	task_panel.simulation_host = host
	task_panel.input_controller = input_controller
	task_panel.instruction_label = task_panel.get_node("Margin/Layout/Intel/Instruction") as Label
	task_panel.task_label = task_panel.get_node("Margin/Layout/Intel/TaskStatus") as Label
	task_panel.strategic_title_label = task_panel.get_node("Margin/Layout/Strategic/Title") as Label
	task_panel.headquarters_directive_label = task_panel.get_node("Margin/Layout/Strategic/DirectiveLabel") as Label
	task_panel.headquarters_directive_selector = task_panel.get_node("Margin/Layout/Strategic/Directive") as OptionButton
	task_panel.defend_button = task_panel.get_node("Margin/Layout/Strategic/Commands/Defend") as Button
	task_panel.scout_button = task_panel.get_node("Margin/Layout/Strategic/Commands/Scout") as Button
	task_panel.attack_button = task_panel.get_node("Margin/Layout/Strategic/Commands/Attack") as Button
	support_panel.simulation_host = host
	support_panel.input_controller = input_controller
	support_panel.pair_selector = support_panel.get_node("Margin/Scroll/Layout/Pair") as OptionButton
	support_panel.recon_button = support_panel.get_node("Margin/Scroll/Layout/Recon") as Button
	support_panel.fortify_button = support_panel.get_node("Margin/Scroll/Layout/Fortify") as Button
	support_panel.reinforcement_button = support_panel.get_node("Margin/Scroll/Layout/Reinforcement") as Button
	support_panel.status_label = support_panel.get_node("Margin/Scroll/Layout/Status") as Label
	support_panel.intel_label = support_panel.get_node("Margin/Scroll/Layout/Intel") as Label
	game.simulation_host = host
	game.battlefield = game.get_node("Battlefield") as Battlefield
	game.workflow_panel = workflow_panel
	game.scenario_status = scenario_status
	game.support_panel = support_panel
	game.camera_controller = input_controller.camera_controller
	game.task_panel = task_panel
	game.resource_bar = resource_bar
	game.minimap = game.get_node("HUDLayer/Minimap") as MinimapControl
	game.map_frame = game.get_node("HUDLayer/MapFrame") as PanelContainer
	game.overlay_controls = game.get_node("HUDLayer/BattlefieldOverlayControls") as BattlefieldOverlayControls
	game.command_desk = game.get_node("HUDLayer/TaskPanel/Margin/Layout/CommandDesk") as CommandDesk
	game.route_mode_hint = route_mode_hint
	game.route_mode_hint_label = route_mode_hint_label
	game.army_board = army_board
	game.prebattle_planner = game.get_node("PrebattlePlanner") as PrebattlePlanner
	game.pause_button = game.get_node("HUDLayer/PauseButton") as Button
	game._configure_scenario_ui()
	game._apply_grey_ridge_desktop_layout(Vector2(1280.0, 720.0))
	game._update_map_masks(Vector2(1280.0, 720.0))
	TranslationServer.set_locale("en")
	task_panel._refresh_strategy_locale()
	army_board.update_snapshot(host.current_snapshot)
	_expect(army_board.is_commander_only(), "card battles should switch the right-hand army board to commander-only mode", failures)
	resource_bar.update_snapshot(host.current_snapshot)
	scenario_status.update_snapshot(host.current_snapshot)
	_expect(host.world.scenario_kind == SimulationWorld.ScenarioKind.GREY_RIDGE, "Grey Ridge scene should instantiate the dedicated authoritative scenario", failures)
	_expect(army_board.get_commander_card_count() == 3 and army_board.get_unit_card_button_count() == 0, "Grey Ridge army board should expose exactly three commander cards and no subordinate unit-card controls", failures)
	TranslationServer.set_locale("en")
	army_board.refresh_locale()
	var english_status := army_board.get_commander_status_text(&"bai_jiuyang")
	var english_outlook := army_board.get_commander_status_tooltip(&"bai_jiuyang")
	_expect(not english_status.contains("COMMANDER_") and english_status.contains("Preparing") and english_status.contains("ETA") and english_status.contains("Risk"), "army board should show a localized action, ETA, risk, and exit boundary for each commander (actual=%s)" % english_status, failures)
	_expect(english_outlook.contains("Objective:") and english_outlook.contains("Participants:") and english_outlook.contains("Action reason:") and english_outlook.contains("Exit condition:"), "commander outlook tooltip should expose the complete execution explanation (actual=%s)" % english_outlook, failures)
	TranslationServer.set_locale("zh_CN")
	army_board.refresh_locale()
	var chinese_status := army_board.get_commander_status_text(&"bai_jiuyang")
	var chinese_outlook := army_board.get_commander_status_tooltip(&"bai_jiuyang")
	_expect(chinese_status != english_status and chinese_status.contains("风险") and not chinese_status.contains("COMMANDER_"), "commander behavior feedback should refresh into Chinese without exposing localization keys", failures)
	_expect(chinese_outlook.contains("目标：") and chinese_outlook.contains("参与：") and chinese_outlook.contains("退出条件："), "commander outlook tooltip should refresh its complete explanation into Chinese", failures)
	TranslationServer.set_locale("en")
	army_board.refresh_locale()
	_expect(not resource_bar.visible and not scenario_status.visible and not workflow_panel.visible, "card battles should hide resource, status, and workflow panels from the permanent HUD", failures)
	_expect(not game.get_node("HUDLayer/BattlefieldOverlayControls").visible and not (task_layout.get_node("ProductionSection") as CanvasItem).visible, "card battles should hide overlay toggles and legacy production workflow surfaces", failures)
	_expect(not task_panel.headquarters_directive_selector.visible and task_panel.headquarters_directive_label.visible and task_panel.headquarters_directive_label.text == GameText.t(&"CARD_COMMANDS_GUIDANCE"), "card battles should replace the inert legacy full-takeover selector with the real commander/card command workflow", failures)
	_expect(task_panel.attack_button.tooltip_text.contains("visible") and task_panel.defend_button.tooltip_text.contains("unit card"), "card-battle area orders should explain their selection and intelligence prerequisites", failures)
	_expect(support_panel.visible and support_panel.has_node("Margin/Scroll/Layout/Recon") and support_panel.has_node("Margin/Scroll/Layout/Fortify") and support_panel.has_node("Margin/Scroll/Layout/Reinforcement"), "Grey Ridge should expose recon, fortification, and field reinforcement support orders", failures)
	input_controller.last_command_status = "ROUTE TEST GUIDANCE"
	var displayed_task := host.current_snapshot.tasks[0] as TaskSnapshot if not host.current_snapshot.tasks.is_empty() else null
	task_panel._update_task(displayed_task)
	_expect(task_panel.instruction_label.text.contains("ROUTE TEST GUIDANCE"), "contextual operation guidance must remain visible even while strategic tasks are active", failures)
	input_controller.selected_unit_card_id = &""
	support_panel.update_snapshot(host.current_snapshot)
	_expect(support_panel.status_label.text.contains("Air recon:") and support_panel.reinforcement_button.tooltip_text.contains("Select a damaged"), "support panel should keep its usage steps visible and explain why reinforcement is disabled", failures)
	host.start_grey_ridge(ArmyPlan.grey_ridge_default())
	game.prebattle_planner.visible = false
	var reinforcement_card := host.world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	for entity_id in reinforcement_card.member_entity_ids.slice(-2):
		var casualty := host.world.units[entity_id] as UnitState
		casualty.enabled = false
		casualty.health = 0.0
	host.world._refresh_battle_population()
	host.current_snapshot = host.world.create_snapshot()
	input_controller.select_unit_card(&"ironwall_assault_group")
	support_panel.update_snapshot(host.current_snapshot)
	_expect(not support_panel.reinforcement_button.disabled and support_panel.reinforcement_button.text.contains("10/12"), "a deployed card with two missing entities should enable the field-reinforcement action", failures)
	support_panel._request_reinforcement()
	_expect(support_panel.status_label.text.contains("REINFORCEMENT ACCEPTED") and support_panel._pending_reinforcement_card_id == &"ironwall_assault_group", "the support panel should retain a visible receipt identifying the queued real-unit reinforcement (text=%s pending=%s queue=%d)" % [support_panel.status_label.text, support_panel._pending_reinforcement_card_id, host.get_queue_size()], failures)
	host.current_snapshot = host.world.advance_tick()
	support_panel.update_snapshot(host.current_snapshot)
	_expect(host.current_snapshot.get_unit_card(&"ironwall_assault_group").current_strength == 12 and support_panel.status_label.text.contains("REINFORCEMENT COMPLETE"), "the next authoritative tick should add two visible unit entities and replace the queued receipt with a completion receipt (strength=%d text=%s)" % [host.current_snapshot.get_unit_card(&"ironwall_assault_group").current_strength, support_panel.status_label.text], failures)
	if not input_controller.command_mode_changed.is_connected(game._on_command_mode_changed):
		input_controller.command_mode_changed.connect(game._on_command_mode_changed)
	input_controller.begin_unit_card_route(&"ironwall_assault_group")
	_expect(route_mode_hint.visible and route_mode_hint_label.text.contains("Enter") and route_mode_hint_label.text.contains("C exits") and route_mode_hint_label.text.contains("Backspace"), "formation route mode should show persistent save, exit, and undo shortcuts above the map (visible=%s text=%s planner=%s mode=%s)" % [route_mode_hint.visible, route_mode_hint_label.text, game.prebattle_planner.visible, InputController.CommandMode.keys()[input_controller.command_mode]], failures)
	var cancel_route := InputEventKey.new()
	cancel_route.keycode = KEY_C
	cancel_route.pressed = true
	input_controller._input(cancel_route)
	_expect(input_controller.command_mode == InputController.CommandMode.NORMAL and not route_mode_hint.visible, "C should exit route planning without saving and immediately hide the route shortcut hint", failures)
	var map_rect: Rect2 = game.get_grey_ridge_map_rect()
	_expect(map_rect.size.x >= 780.0 and map_rect.size.y >= 440.0, "the 1280x720 battle layout should retain a usable central battlefield while reserving 220 pixels for decisions", failures)
	_expect(game.task_panel.size.y >= 220.0 and game.pause_button.visible and map_rect.grow(1.0).encloses(game.pause_button.get_global_rect()), "the battle layout should enlarge the decision desk and keep a visible pause button inside the map", failures)
	input_controller.camera_controller.fit_world_in_screen_rect(map_rect)
	var visible_world := input_controller.camera_controller.get_visible_world_rect()
	_expect(visible_world.encloses(CameraController.WORLD_RECT), "the initial Grey Ridge camera should fit the complete battlefield inside the central map viewport", failures)
	var outside_wheel := InputEventMouseButton.new()
	outside_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	outside_wheel.pressed = true
	outside_wheel.position = Vector2(20.0, 20.0)
	var zoom_before_outside_wheel := input_controller.camera_controller.zoom
	_expect(not input_controller.camera_controller.handle_input(outside_wheel) and input_controller.camera_controller.zoom == zoom_before_outside_wheel, "wheel input over a HUD panel must remain available for UI scrolling and never zoom the map", failures)
	var inside_wheel := InputEventMouseButton.new()
	inside_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	inside_wheel.pressed = true
	inside_wheel.position = map_rect.get_center()
	_expect(input_controller.camera_controller.handle_input(inside_wheel) and input_controller.camera_controller.zoom.x > zoom_before_outside_wheel.x, "wheel input inside the battlefield viewport should zoom the map", failures)
	game._apply_grey_ridge_narrow_layout(Vector2(480.0, 800.0))
	var narrow_map_rect: Rect2 = game.get_grey_ridge_map_rect()
	input_controller.camera_controller.fit_world_in_screen_rect(narrow_map_rect)
	_expect(input_controller.camera_controller.get_visible_world_rect().encloses(CameraController.WORLD_RECT), "the battlefield scale should refit the complete map inside a narrow-screen map panel", failures)
	game._apply_grey_ridge_desktop_layout(Vector2(1280.0, 720.0))
	game._update_map_masks(Vector2(1280.0, 720.0))
	input_controller.camera_controller.fit_world_in_screen_rect(map_rect)
	for mask in game._map_masks():
		_expect(mask.visible and not mask.get_global_rect().intersects(map_rect), "%s should hide world rendering outside the central map without covering it" % mask.name, failures)
	var separated_panels: Array[Control] = [resource_bar, scenario_status, support_panel, army_board, task_panel, game.get_node("HUDLayer/Minimap") as Control]
	for panel in separated_panels:
		if panel.visible:
			_expect(not panel.get_global_rect().intersects(map_rect), "%s must remain outside the dedicated battlefield viewport" % panel.name, failures)
	battle_debrief.show_debrief(ArmyRosterStore.build_battle_record(host.current_snapshot))
	_expect(battle_debrief.visible and battle_debrief.cards_button.button_pressed and battle_debrief.rows.get_child_count() == 4, "Grey Ridge debrief without a completed live report should fall back to a progression row for every persistent friendly unit card", failures)
	for row in battle_debrief.rows.get_children():
		_expect(row.has_meta(&"unit_card_id") and not String(row.get_meta(&"unit_card_id", "")).is_empty(), "every debrief action row should retain a stable unit-card identity", failures)
	battle_debrief._on_review_view_pressed(BattleDebrief.ReviewView.CAUSES)
	_expect(battle_debrief.causes_button.button_pressed and not battle_debrief.cards_button.button_pressed, "Grey Ridge debrief should expose a reachable causal explanation view", failures)
	battle_debrief._on_review_view_pressed(BattleDebrief.ReviewView.TURNING_POINTS)
	_expect(battle_debrief.timeline_button.button_pressed and not battle_debrief.causes_button.button_pressed, "Grey Ridge debrief should expose a reachable turning-point view", failures)
	battle_debrief.refresh_locale()
	var debrief_return := battle_debrief.get_node_or_null("Backdrop/Panel/Margin/Layout/Footer/ReturnToOperations") as Button
	_expect(debrief_return != null and debrief_return.text == GameText.t(&"RETURN_TO_OPERATIONS"), "the debrief should provide a localized return path to operation selection", failures)
	battle_debrief.visible = false
	var pause_menu := game.get_node("PauseMenu") as PauseMenu
	game.pause_menu = pause_menu
	pause_menu.backdrop = pause_menu.get_node("Backdrop") as ColorRect
	pause_menu.continue_button = pause_menu.get_node("Backdrop/Menu/Content/Continue") as Button
	if not game.pause_button.pressed.is_connected(game._open_pause_menu):
		game.pause_button.pressed.connect(game._open_pause_menu)
	game.pause_button.pressed.emit()
	_expect(Engine.get_main_loop().paused and pause_menu.backdrop.visible, "the visible card-battle pause button should open the shared pause menu and stop the scene tree", failures)
	pause_menu.close()
	_expect(not Engine.get_main_loop().paused and not pause_menu.backdrop.visible, "Continue should resume the same pause state opened from the HUD button", failures)
	army_board._select_unit_card(&"armored_spearhead")
	_expect(input_controller.command_mode == InputController.CommandMode.DEPLOY_UNIT_CARD_TARGETING, "Grey Ridge reserve card should enter battlefield deployment targeting", failures)
	game.free()


func _test_command_desk_action_receipt_persists(failures: Array[String]) -> void:
	var packed_scene := load("res://scenes/game/grey_ridge.tscn") as PackedScene
	var game := packed_scene.instantiate()
	Engine.get_main_loop().root.add_child(game)
	var host := game.get_node("SimulationHost") as SimulationHost
	var desk := game.get_node("HUDLayer/TaskPanel/Margin/Layout/CommandDesk") as CommandDesk
	desk.intent_title = desk.get_node("Intent/Title") as Label
	desk.approval_hint = desk.get_node("Intent/ApprovalHint") as Label
	desk.commander_label = desk.get_node("Intent/Selectors/CommanderLabel") as Label
	desk.commander_selector = desk.get_node("Intent/Selectors/Commander") as OptionButton
	desk.objective_label = desk.get_node("Intent/Selectors/ObjectiveLabel") as Label
	desk.objective_selector = desk.get_node("Intent/Selectors/Objective") as OptionButton
	desk.axis_label = desk.get_node("Intent/Selectors/AxisLabel") as Label
	desk.axis_selector = desk.get_node("Intent/Selectors/Axis") as OptionButton
	desk.risk_label = desk.get_node("Intent/Selectors/RiskLabel") as Label
	desk.risk_selector = desk.get_node("Intent/Selectors/Risk") as OptionButton
	desk.reserve_label = desk.get_node("Intent/Selectors/ReserveLabel") as Label
	desk.reserve_selector = desk.get_node("Intent/Selectors/Reserve") as OptionButton
	desk.apply_button = desk.get_node("Intent/Actions/Apply") as Button
	desk.cancel_button = desk.get_node("Intent/Actions/Cancel") as Button
	desk.intent_status = desk.get_node("Intent/Status") as Label
	desk.exception_title = desk.get_node("Exceptions/Header/Title") as Label
	desk.exception_count = desk.get_node("Exceptions/Header/Count") as Label
	desk.exception_rows = desk.get_node("Exceptions/Scroll/Rows") as VBoxContainer
	desk.separator = desk.get_node("Separator") as VSeparator
	desk.guide_button = desk.get_node("Exceptions/Header/Guide") as Button
	desk.guide_popup = desk.get_node("GuidePopup") as PopupPanel
	desk.guide_text = desk.get_node("GuidePopup/Margin/Text") as RichTextLabel
	desk.history_button = desk.get_node("Exceptions/Footer/History") as Button
	desk.history_popup = desk.get_node("HistoryPopup") as PopupPanel
	desk.history_text = desk.get_node("HistoryPopup/Margin/Text") as RichTextLabel
	desk.decision_failure_dialog = desk.get_node("DecisionFailureDialog") as AcceptDialog
	desk._ready()
	host._ready()
	host.start_grey_ridge(ArmyPlan.grey_ridge_default())
	desk.configure(host, game.get_node("InputController") as InputController, game.get_node("CameraController") as CameraController)
	var actions: Array[int] = [CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER]
	var exception := CommandExceptionSnapshot.new(
		&"exposed:falcon_recon_group:test", CommandExceptionSnapshot.Kind.EXPOSED,
		CommandExceptionSnapshot.Severity.WARNING, &"COMMAND_EXCEPTION_EXPOSED",
		host.current_snapshot.tick, &"bai_jiuyang", &"falcon_recon_group", &"UNIT_CARD_FALCON_RECON_GROUP",
		host.current_snapshot.get_unit_card(&"falcon_recon_group").assigned_task_id,
		host.current_snapshot.get_unit_card(&"falcon_recon_group").center_position, 8.0, 6.0, actions
	)
	var exceptions: Array[CommandExceptionSnapshot] = [exception]
	var intents: Array[HighLevelIntentSnapshot] = []
	var situation := CommandSituationSnapshot.new(host.current_snapshot.tick, SimulationWorld.LOCAL_PLAYER_ID, intents, exceptions)
	desk.update_command_situation(host.current_snapshot, situation)
	desk._perform_exception_action(exception.exception_id, CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER)
	var action_name := desk._action_text(CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER)
	var commander_name := GameText.t(host.current_snapshot.get_commander(&"bai_jiuyang").display_name_key)
	_expect(desk.intent_status.text.contains(action_name) and desk.intent_status.text.contains(commander_name) and desk.intent_status.text.contains(GameText.t(&"RESULT_ACCEPTED")), "the decision area should immediately name the affected commander and accepted action (actual=%s)" % desk.intent_status.text, failures)
	host.current_snapshot = host.world.advance_tick()
	var next_situation := CommandSituationSnapshot.new(host.current_snapshot.tick, SimulationWorld.LOCAL_PLAYER_ID, intents, exceptions)
	desk.update_command_situation(host.current_snapshot, next_situation)
	_expect(desk.intent_status.text.contains(action_name) and desk.intent_status.text.contains(commander_name) and desk.intent_status.text.contains(GameText.t(&"RESULT_ACCEPTED")), "the named action receipt should survive the next authoritative snapshot (actual=%s)" % desk.intent_status.text, failures)
	var action_button: Button
	for row_index in range(desk.exception_rows.get_child_count() - 1, -1, -1):
		var row := desk.exception_rows.get_child(row_index)
		if row.get_meta(&"exception_id", &"") == exception.exception_id:
			action_button = row.get_node("Buttons/Action") as Button
			break
	_expect(action_button != null and action_button.disabled, "the accepted primary action should be disabled while its receipt remains visible", failures)
	_expect(desk.guide_button != null and not desk.guide_button.tooltip_text.is_empty() and desk.guide_text.text.length() > 100, "the command desk should keep an always-available contextual guide for intent, coordination, decisions, and withdrawal", failures)
	_expect(desk.get_decision_history_count() == 1 and not desk.history_popup.visible, "an accepted decision should enter hidden session history without opening it automatically", failures)
	desk._show_history()
	_expect(desk.history_text.text.contains(action_name) and desk.history_text.text.contains(commander_name), "the history view should render an auditable newest-first record with action and subject", failures)
	desk.history_popup.hide()

	var preview_events: Array[Dictionary] = []
	var clear_events: Array[int] = []
	desk.decision_preview_changed.connect(func(route: PackedVector2Array, target: Vector2, radius: float, label: String) -> void:
		preview_events.append({"route": route, "target": target, "radius": radius, "label": label})
	)
	desk.decision_preview_cleared.connect(func() -> void: clear_events.append(1))
	desk._preview_selected_axis()
	_expect(preview_events.size() == 1 and (preview_events[0]["route"] as PackedVector2Array).size() == 2 and not (preview_events[0]["target"] as Vector2).is_zero_approx(), "hovering the selected main axis should emit a commander-to-region route preview", failures)
	desk._preview_exception(exception.exception_id)
	_expect(preview_events.size() == 2 and not (preview_events[1]["target"] as Vector2).is_zero_approx(), "hovering an actionable decision should emit its legal snapshot target preview", failures)
	desk._clear_decision_preview()
	_expect(clear_events.size() == 1, "leaving a decision hover should immediately clear the map preview", failures)

	desk._perform_exception_action(&"stale:missing", CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER)
	_expect(desk.decision_failure_dialog.dialog_text.contains(GameText.t(&"DECISION_RESPONSE_STALE")), "an expired decision row should prepare a modal explanation instead of silently returning", failures)
	desk.decision_failure_dialog.hide()
	var invalid_exception := CommandExceptionSnapshot.new(
		&"exposed:missing_commander:test", CommandExceptionSnapshot.Kind.EXPOSED,
		CommandExceptionSnapshot.Severity.WARNING, &"COMMAND_EXCEPTION_EXPOSED",
		host.current_snapshot.tick, &"missing_commander", &"falcon_recon_group", &"UNIT_CARD_FALCON_RECON_GROUP",
		0, host.current_snapshot.get_unit_card(&"falcon_recon_group").center_position, 8.0, 6.0, actions
	)
	var invalid_exceptions: Array[CommandExceptionSnapshot] = [invalid_exception]
	desk.update_command_situation(host.current_snapshot, CommandSituationSnapshot.new(host.current_snapshot.tick, SimulationWorld.LOCAL_PLAYER_ID, intents, invalid_exceptions))
	desk._perform_exception_action(invalid_exception.exception_id, CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER)
	_expect(desk.decision_failure_dialog.dialog_text.contains(GameText.t(&"COMMAND_EXCEPTION_DISENGAGE_INVALID")) and desk.get_decision_history_count() == 3, "an immediate command rejection should prepare a modal reason and write exactly one history entry", failures)
	desk.decision_failure_dialog.hide()

	desk.simulation_host = null
	desk.update_command_situation(host.current_snapshot, next_situation)
	desk._perform_exception_action(exception.exception_id, CommandExceptionSnapshot.Action.DISENGAGE_COMMANDER)
	_expect(desk.decision_failure_dialog.dialog_text.contains(GameText.t(&"DECISION_RESPONSE_UNAVAILABLE")), "a missing command host should prepare a modal unavailable reason instead of an error or no-op", failures)
	desk.decision_failure_dialog.hide()
	desk.simulation_host = host

	var timeout_history_index := desk._record_decision("timeout subject", "timeout action", GameText.t(&"RESULT_ACCEPTED"), true)
	var issued_tick := host.current_snapshot.tick
	desk._watch_response({
		"kind": "intent", "commander_id": &"bai_jiuyang", "intent_id": &"never_confirmed",
		"objective_id": &"central_relay", "axis_id": &"central_relay",
		"issued_tick": issued_tick, "history_index": timeout_history_index,
		"subject": "timeout subject", "action": "timeout action",
	})
	for _tick in range(CommandDesk.DECISION_RESPONSE_TIMEOUT_TICKS):
		host.current_snapshot = host.world.advance_tick()
	var timeout_situation := CommandSituationSnapshot.new(host.current_snapshot.tick, SimulationWorld.LOCAL_PLAYER_ID, intents, exceptions)
	desk.update_command_situation(host.current_snapshot, timeout_situation)
	_expect(desk.decision_failure_dialog.dialog_text.contains(GameText.t(&"DECISION_RESPONSE_TIMEOUT_REASON")) and desk._pending_responses.is_empty() and desk.history_text.text.contains(GameText.t(&"DECISION_RESPONSE_TIMEOUT_REASON")), "an accepted decision without authoritative confirmation should time out at the configured tick and explain the failure in both modal and history", failures)
	_expect(desk.get_decision_history_count() == 5, "success, stale, rejection, unavailable, and timeout decisions should persist across snapshot refreshes", failures)
	game.free()


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
	var first_sync_count := presentation.get_full_sync_count()
	presentation.set_snapshots(host.current_snapshot, host.current_snapshot, 0.75)
	_expect(host.current_snapshot.observer_faction_id == SimulationWorld.LOCAL_PLAYER_ID, "host should publish the local faction snapshot", failures)
	_expect(presentation.get_full_sync_count() == first_sync_count, "presentation should not rebuild proxies more than once for the same authoritative tick", failures)
	_expect(units_root.get_child_count() == host.current_snapshot.units.size(), "presentation should create one proxy per known unit", failures)
	presentation.set_unit_labels_visible(false)
	var visible_proxy := units_root.get_child(0) as UnitProxy
	_expect(visible_proxy.visible and visible_proxy.scale.is_equal_approx(Vector2.ONE) and not visible_proxy.show_labels, "known units should keep fixed world scale when overview labels are hidden", failures)
	presentation.set_unit_labels_visible(true)
	_expect(visible_proxy.scale.is_equal_approx(Vector2.ONE) and visible_proxy.show_labels, "label visibility changes must not alter unit world scale", failures)
	presentation._detailed_units_enabled = false
	presentation._update_unit_batches()
	var first_unit := host.current_snapshot.units[0]
	var expected_role_scale := Vector2.ONE
	match first_unit.tactical_role:
		UnitState.TacticalRole.SCOUT:
			expected_role_scale = Vector2(0.72, 0.65)
		UnitState.TacticalRole.FIREPOWER:
			expected_role_scale = Vector2(1.12, 0.62)
		UnitState.TacticalRole.ARMOR:
			expected_role_scale = Vector2(1.16, 0.94)
		UnitState.TacticalRole.ASSAULT:
			expected_role_scale = Vector2(0.92, 0.88)
	_expect(
		is_equal_approx(presentation._unit_body_buffer[0], expected_role_scale.x)
			and is_equal_approx(presentation._unit_body_buffer[5], expected_role_scale.y),
		"batched units should keep their role-specific fixed world scale",
		failures
	)
	_expect(buildings_root.get_child_count() == host.current_snapshot.buildings.size(), "presentation should create one proxy per known building", failures)
	_expect(ore_root.get_child_count() == host.current_snapshot.ore_fields.size(), "presentation should create one proxy per explored ore field", failures)
	var tracked_unit := host.world.units[1] as UnitState
	tracked_unit.following_formation = false
	tracked_unit.has_move_target = false
	var previous_unit_position := tracked_unit.position
	var previous_projectile_position := previous_unit_position + Vector2(16.0, 0.0)
	var projectile := ProjectileState.new(999999, tracked_unit.entity_id, SimulationWorld.DEFAULT_ENEMY_UNIT_ID, SimulationWorld.LOCAL_PLAYER_ID, previous_projectile_position, 0.0, 1.0, -1)
	host.world.projectiles[projectile.projectile_id] = projectile
	host.world._update_faction_knowledge()
	var interpolation_previous := host.world.create_snapshot()
	tracked_unit.position += Vector2(32.0, 0.0)
	projectile.position += Vector2(48.0, 0.0)
	host.world.current_tick += 1
	host.world._update_faction_knowledge()
	var interpolation_current := host.world.create_snapshot()
	presentation.set_snapshots(interpolation_previous, interpolation_current, 0.5)
	presentation._update_proxy_positions(false)
	var tracked_proxy := presentation._proxies[tracked_unit.entity_id] as UnitProxy
	_expect(tracked_proxy.position.is_equal_approx(previous_unit_position + Vector2(16.0, 0.0)), "unit interpolation should use the cached previous visible position", failures)
	_expect(is_equal_approx(presentation._projectile_buffer[3], previous_projectile_position.x + 24.0) and is_equal_approx(presentation._projectile_buffer[7], previous_projectile_position.y), "projectile interpolation should write the cached midpoint into the reusable MultiMesh buffer", failures)
	var stale_contact := KnowledgeContact.from_unit(host.world.units[SimulationWorld.DEFAULT_ENEMY_UNIT_ID] as UnitState, host.world.current_tick)
	var stale_proxy := UnitProxy.new()
	stale_proxy.apply_snapshot(UnitSnapshot.new(null, stale_contact))
	_expect(not stale_proxy.currently_visible and stale_proxy.is_last_seen_contact(), "a surviving hostile outside vision should render as intelligence memory rather than a death marker", failures)
	stale_contact.enabled = false
	stale_contact.health = 0.0
	stale_proxy.apply_snapshot(UnitSnapshot.new(null, stale_contact))
	_expect(not stale_proxy.is_last_seen_contact(), "a confirmed destroyed hostile should use wreck presentation rather than the living last-seen marker", failures)
	stale_proxy.free()
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
	var contact_alert := game.get_node("HUDLayer/ContactAlert") as ContactAlert
	var command_feedback := game.get_node("CommandFeedback") as CommandFeedback
	var battle_feedback_director := game.get_node("BattleFeedbackDirector") as BattleFeedbackDirector
	var debug_layer := game.get_node("DebugLayer") as DebugLayer
	var input_controller := game.get_node("InputController") as InputController
	var workflow_panel := game.get_node("HUDLayer/WorkflowPanel") as WorkflowPanel
	var pause_menu := game.get_node("PauseMenu") as PauseMenu
	var camera := game.get_node("CameraController") as CameraController
	var presentation := game.get_node("WorldPresentation") as WorldPresentation
	var hover_tooltip := game.get_node("HoverTooltip") as HoverTooltip
	var battle_debrief := game.get_node("BattleDebrief") as BattleDebrief
	var army_board := game.get_node("HUDLayer/ArmyBoard") as ArmyBoard
	host._ready()
	panel.mission_label = panel.get_node("Margin/Layout/Intel/Mission")
	panel.task_label = panel.get_node("Margin/Layout/Intel/TaskStatus")
	panel.develop_button = panel.get_node("Margin/Layout/Strategic/Commands/Develop")
	panel.defend_button = panel.get_node("Margin/Layout/Strategic/Commands/Defend")
	panel.attack_button = panel.get_node("Margin/Layout/Strategic/Commands/Attack")
	panel.pause_button = panel.get_node("Margin/Layout/Operations/Grid/Pause")
	panel.resume_button = panel.get_node("Margin/Layout/Operations/Grid/Resume")
	panel.cancel_button = panel.get_node("Margin/Layout/Operations/Grid/Cancel")
	panel.production_queue_label = panel.get_node("Margin/Layout/ProductionSection/Queue")
	panel.cancel_production_button = panel.get_node("Margin/Layout/ProductionSection/Controls/CancelProduction")
	panel.rally_button = panel.get_node("Margin/Layout/ProductionSection/Controls/Rally")
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
	hover_tooltip.panel = hover_tooltip.get_node("Panel")
	hover_tooltip.label = hover_tooltip.get_node("Panel/Margin/Text")
	hover_tooltip._ready()
	army_board.input_controller = input_controller
	army_board._ready()
	game._ready()
	army_board.update_snapshot(host.current_snapshot)
	_expect(Engine.max_fps >= 60, "project presentation should target at least 60 rendered frames per second", failures)
	_expect(host.scenario_kind == SimulationWorld.ScenarioKind.LEGACY_RTS, "direct game_root scene verification should exercise its default Legacy RTS path", failures)
	presentation.units_root = presentation.get_node("Units") as Node2D
	presentation.buildings_root = presentation.get_node("Buildings") as Node2D
	presentation.ore_fields_root = presentation.get_node("OreFields") as Node2D
	presentation.set_snapshots(host.previous_snapshot, host.current_snapshot, 0.0)
	var direct_scene_proxy := presentation._proxies.values()[0] as UnitProxy
	for direct_scene_zoom in [0.1, 1.1]:
		camera.zoom = Vector2.ONE * direct_scene_zoom
		game._update_unit_presentation_for_zoom()
		_expect(
			direct_scene_proxy.scale.is_equal_approx(Vector2.ONE),
			"direct game_root units should keep fixed world scale at zoom %.2f" % direct_scene_zoom,
			failures
		)
	camera.zoom = Vector2.ONE
	var camera_limits := camera.get_center_limits(Vector2(1280.0, 720.0))
	_expect(camera_limits.end.y + 360.0 >= CameraController.WORLD_RECT.end.y + 250.0, "camera should overscroll below the map enough to reveal terrain behind the bottom command bar", failures)
	_expect(panel.simulation_host == host, "task panel should accept the authoritative simulation host", failures)
	minimap.add_contact_ping(Vector2(640.0, 480.0))
	var contact_audio_before := contact_alert.get_audio_play_count()
	contact_alert.show_contact(&"assault_vehicle")
	_expect(minimap.get_contact_ping_count() == 1 and contact_alert.visible, "enemy contacts should have a visible minimap ping and alert surface", failures)
	_expect(contact_alert.get_audio_play_count() == contact_audio_before + 1 and contact_alert.alert_audio.stream is AudioStreamWAV and (contact_alert.alert_audio.stream as AudioStreamWAV).data.size() > 0, "enemy contact alerts should play a generated audible warning without requiring an external asset", failures)
	contact_alert.show_battle_feedback(&"BATTLE_FEEDBACK_HEADQUARTERS_CRITICAL", [], BattleFeedbackDirector.Severity.CRITICAL)
	contact_alert.show_contact(&"assault_vehicle", false, false)
	_expect(contact_alert._message_key == &"BATTLE_FEEDBACK_HEADQUARTERS_CRITICAL", "ordinary contact discovery should not overwrite an active battle or headquarters warning", failures)
	contact_alert._remaining = 0.0
	contact_alert.visible = false
	var feedback_before := command_feedback.play_count
	var accepted_move := MoveCommand.new(
		host.world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, host.world.current_tick, 3,
		(host.world.units[3] as UnitState).position + Vector2(32.0, 0.0)
	)
	host.submit_command(accepted_move)
	var accepted_cue := command_feedback.last_cue
	var rejected_move := MoveCommand.new(
		host.world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER, host.world.current_tick, 999999, Vector2.ZERO
	)
	host.submit_command(rejected_move)
	_expect(command_feedback.play_count == feedback_before + 2 and accepted_cue == CommandFeedback.Cue.ACCEPTED and command_feedback.last_cue == CommandFeedback.Cue.REJECTED, "command evaluation should produce distinct accepted and rejected audio receipts through the host signal", failures)
	_expect(contact_alert.visible and contact_alert._message_key == &"BATTLE_FEEDBACK_COMMAND_RESULT" and not contact_alert._message_arguments.is_empty(), "every evaluated player command should also produce a persistent visible acceptance or rejection receipt", failures)
	_expect(command_feedback.stream is AudioStreamWAV and (command_feedback.stream as AudioStreamWAV).data.size() > 0, "command receipt audio should contain generated PCM samples", failures)
	_expect(pause_menu.battle_audio_toggle != null and pause_menu.battle_audio_toggle.button_pressed, "pause menu should expose an enabled-by-default battle audio toggle", failures)
	pause_menu._select_battle_audio(false)
	_expect(not battle_feedback_director.audio_enabled and not contact_alert.audio_enabled and not command_feedback.audio_enabled, "pause menu battle audio toggle should mute command, contact, and battle channels without disabling visual alerts", failures)
	pause_menu._select_battle_audio(true)
	host.world.command_queue.drain()
	_expect(panel.has_node("Margin/Layout/Intel") and panel.has_node("Margin/Layout/Strategic") and panel.has_node("Margin/Layout/Operations") and panel.has_node("Margin/Layout/ProductionSection"), "task panel should separate intelligence, strategy, operations, and production", failures)
	_expect(panel.has_node("Margin/Layout/Strategic/Directive"), "the command panel should expose a top-level General Staff directive selector", failures)
	_expect(panel.has_node("Margin/Layout/Strategic/Commands/Scout"), "strategy controls should expose selected-unit reconnaissance", failures)
	_expect(panel.production_buttons.size() == 5, "production section should retain all five unit controls", failures)
	_expect(panel.has_node("Margin/Layout/ProductionSection/Queue") and panel.has_node("Margin/Layout/ProductionSection/Controls/Rally"), "production section should expose queue state and rally controls", failures)
	_expect(panel.build_factory_button.text.contains("300") and panel.production_buttons[4].text.contains("350"), "construction and production controls should expose authoritative ore costs", failures)
	_expect(workflow_panel != null and workflow_panel.has_node("Margin/Layout/UnitFlows") and workflow_panel.has_node("Margin/Layout/Tasks"), "left workflow panel should expose unit work and delegated tasks", failures)
	_expect(hover_tooltip != null, "game scene should include the delayed contextual tooltip layer", failures)
	_expect(army_board.get_unit_card_button_count() == 2, "persistent army board should expose the two authoritative starter unit cards", failures)
	army_board._select_unit_card(&"ironwall_assault_group")
	_expect(input_controller.selected_entity_ids == [4, 5], "army-board card interaction should select its real battlefield entities", failures)
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
	panel.headquarters_directive_selector.select(StrategicHeadquarters.Directive.OFFENSIVE)
	panel._select_headquarters_directive(StrategicHeadquarters.Directive.OFFENSIVE)
	_expect(host.get_headquarters_directive() == StrategicHeadquarters.Directive.OFFENSIVE and host.get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID) == AgentPolicy.Authorization.AUTONOMOUS, "General Staff UI should directly enable and configure full takeover", failures)
	pause_menu._select_agent_authorization(AgentPolicy.Authorization.ASSISTED, StrategicTaskSystem.INDUSTRIAL_AGENT_ID)
	pause_menu._select_agent_authorization(AgentPolicy.Authorization.ASSISTED, StrategicTaskSystem.BATTLEFIELD_AGENT_ID)
	pause_menu._select_agent_authorization(AgentPolicy.Authorization.ADVISORY, StrategicTaskSystem.INDUSTRIAL_AGENT_ID)
	panel.update_snapshot(host.current_snapshot)
	_expect(host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID) == AgentPolicy.Authorization.ADVISORY and panel.develop_button.disabled, "advisory industrial authority should disable executable development orders", failures)
	pause_menu._select_agent_authorization(AgentPolicy.Authorization.ASSISTED, StrategicTaskSystem.INDUSTRIAL_AGENT_ID)
	panel.update_snapshot(host.current_snapshot)
	panel.develop_button.pressed.emit()
	_expect(host.get_queue_size() == 1, "Develop button should submit a strategic command through the host", failures)
	pause_menu.open()
	_expect(Engine.get_main_loop().paused and pause_menu.backdrop.visible, "ESC menu should pause the game and remain visible", failures)
	_expect(pause_menu.operations_button != null and pause_menu.return_confirmation.dialog_text == GameText.t(&"RETURN_TO_OPERATIONS_CONFIRM_BODY"), "leaving an unfinished battle should expose a localized confirmation instead of returning immediately", failures)
	pause_menu.close()
	_expect(not Engine.get_main_loop().paused and not pause_menu.backdrop.visible, "Continue should resume the game and hide the menu", failures)
	pause_menu._select_language(0)
	_expect(pause_menu.language_changed.is_connected(Callable(game, "_on_language_changed")), "pause menu language signal should be connected to the game root", failures)
	_expect(TranslationServer.get_locale() == "zh_CN", "language menu should switch the runtime locale to Chinese", failures)
	_expect(pause_menu.title_label.text == "游戏暂停" and panel.title_label.text == "指挥网络", "Chinese selection should immediately refresh pause menu and HUD", failures)
	_expect(pause_menu.authorization_help.text.contains("建议") and pause_menu.authorization_help.text.contains("自主"), "Chinese pause menu should explain all four authorization levels", failures)
	_expect(panel.selection_title_label.text == "当前选择" and panel.strategic_title_label.text == "参谋部" and panel.operations_title_label.text == "工程与控制" and panel.production_title_label.text == "单位生产", "Chinese HUD should localize every command section", failures)
	_expect(workflow_panel.title_label.text == "当前工作流程", "Chinese HUD should localize the workflow monitor", failures)
	_expect(GameText.unit_description(&"assault_vehicle").contains("前线作战"), "Chinese unit descriptions should explain battlefield roles", failures)
	hover_tooltip.update_candidate("unit:assault_vehicle", GameText.unit_tooltip(&"assault_vehicle"), Vector2(400.0, 300.0), 0.5)
	_expect(not hover_tooltip.panel.visible, "context tooltip should remain hidden before its one-second delay", failures)
	hover_tooltip.update_candidate("unit:assault_vehicle", GameText.unit_tooltip(&"assault_vehicle"), Vector2(400.0, 300.0), 0.51)
	_expect(hover_tooltip.panel.visible and hover_tooltip.label.text.contains("突击车"), "context tooltip should appear after the delay with localized details", failures)
	hover_tooltip.update_candidate("unit:scout_vehicle", GameText.unit_tooltip(&"scout_vehicle"), Vector2(400.0, 300.0), 0.1)
	_expect(not hover_tooltip.panel.visible, "changing the hovered target should restart the tooltip delay", failures)
	hover_tooltip.update_candidate("unit:scout_vehicle", GameText.unit_tooltip(&"scout_vehicle"), Vector2(400.0, 300.0), 1.01)
	battle_debrief.visible = true
	game._update_hover_tooltip(0.01)
	_expect(not hover_tooltip.panel.visible, "opening the battle debrief should immediately clear any battlefield hover tooltip", failures)
	battle_debrief.visible = false
	pause_menu._select_language(1)
	_expect(TranslationServer.get_locale() == "en", "language menu should switch the runtime locale to English", failures)
	_expect(pause_menu.title_label.text == "PAUSED" and panel.title_label.text == "COMMAND NETWORK", "English selection should immediately refresh pause menu and HUD", failures)
	_expect(pause_menu.authorization_help.text.contains("Advisory") and pause_menu.authorization_help.text.contains("Autonomous"), "English pause menu should explain all four authorization levels", failures)
	_expect(panel.selection_title_label.text == "SELECTION" and panel.strategic_title_label.text == "GENERAL STAFF" and panel.operations_title_label.text == "OPERATIONS" and panel.production_title_label.text == "PRODUCTION", "English HUD should localize every command section", failures)
	_expect(workflow_panel.title_label.text == "ACTIVE WORKFLOWS", "English HUD should localize the workflow monitor", failures)
	_expect(GameText.building_description(&"command_center").contains("Economic hub"), "English building descriptions should update with the selected language", failures)
	(world_faction(host) as FactionState).ore = 120
	host.current_snapshot = host.world.create_snapshot()
	input_controller.selected_building_id = SimulationWorld.PLAYER_FACTORY_ID
	panel.update_snapshot(host.current_snapshot)
	_expect(not panel.production_buttons[2].disabled and panel.production_buttons[4].disabled, "production controls should distinguish affordable and unaffordable unit costs", failures)
	_expect(panel.production_buttons[0].disabled and panel.production_buttons[1].disabled, "automated factory should disable economic units outside its catalog", failures)
	(world_faction(host) as FactionState).ore = 500
	host.current_snapshot = host.world.create_snapshot()
	input_controller.selected_building_id = SimulationWorld.PLAYER_COMMAND_CENTER_ID
	panel.update_snapshot(host.current_snapshot)
	_expect(not panel.production_buttons[0].disabled and not panel.production_buttons[1].disabled and panel.production_buttons[2].disabled, "command center should enable only harvester and engineer production", failures)
	_expect(panel.production_queue_label.text == "Queue 0 / 5" and panel.rally_button.disabled == false, "selected production building should expose queue capacity and rally targeting", failures)
	host.advance_tick()
	host.advance_tick()
	input_controller._set_selection([4])
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
