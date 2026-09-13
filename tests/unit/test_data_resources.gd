class_name TestDataResources
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(TestDoctrineEffectDefinitions.new().run())
	failures.append_array(TestTacticalCards.new().run())
	failures.append_array(TestGreyRidgeTacticalContent.new().run())
	_test_committed_catalog_loads(failures)
	_test_growth_catalog(failures)
	_test_structured_validation(failures)
	_test_battle_content_loader(failures)
	_test_battle_reference_validation(failures)
	_test_world_consumes_battle_content(failures)
	_test_broken_bridge_engineering_and_terrain(failures)
	_test_fog_forest_intel_and_escort(failures)
	_test_black_well_organization_and_withdrawal(failures)
	return failures


func _test_growth_catalog(failures: Array[String]) -> void:
	var catalog: Variant = ResourceLoader.load("res://data/army/growth_catalog.tres")
	_expect(catalog != null and catalog.has_method("validate"), "growth pool should load as a validated typed resource catalog", failures)
	if catalog == null or not catalog.has_method("validate"):
		return
	_expect(catalog.validate().is_valid(), "the committed growth pool should pass structured validation", failures)
	_expect(catalog.get_by_kind(ArmyRosterStore.GROWTH_KIND_HONOR).size() == 6 and catalog.get_by_kind(ArmyRosterStore.GROWTH_KIND_EQUIPMENT).size() == 6, "the MVP growth pool should contain exactly six honors and six equipment choices", failures)
	_expect(catalog.get_growth(&"eyes_of_advance") != null and catalog.get_growth(&"field_repair_kit") != null, "growth choices should resolve by stable ID", failures)


func _test_committed_catalog_loads(failures: Array[String]) -> void:
	var resource := ResourceLoader.load("res://data/units/unit_catalog.tres")
	_expect(resource is UnitDefinitionCatalog, "unit catalog .tres should load as typed catalog", failures)
	if not resource is UnitDefinitionCatalog:
		return
	var catalog := resource as UnitDefinitionCatalog
	_expect(catalog.validate().is_valid(), "committed unit catalog should validate", failures)
	var scout := catalog.get_unit(&"scout_vehicle")
	_expect(scout is UnitDefinition, "typed external unit reference should resolve", failures)
	if scout != null:
		_expect(is_equal_approx(scout.move_speed, 180.0), "loaded typed definition should retain move speed", failures)


func _test_structured_validation(failures: Array[String]) -> void:
	var catalog := UnitDefinitionCatalog.new()
	catalog.units.append(null)
	var invalid := UnitDefinition.new()
	invalid.definition_id = &""
	invalid.display_name = " "
	invalid.move_speed = -1.0
	catalog.units.append(invalid)
	var duplicate_a := UnitDefinition.new()
	duplicate_a.definition_id = &"duplicate"
	duplicate_a.display_name = "A"
	var duplicate_b := UnitDefinition.new()
	duplicate_b.definition_id = &"duplicate"
	duplicate_b.display_name = "B"
	catalog.units.append(duplicate_a)
	catalog.units.append(duplicate_b)
	var result := catalog.validate()
	_expect(result.has_reason(DataValidationResult.Reason.NULL_REFERENCE), "catalog should report null references", failures)
	_expect(result.has_reason(DataValidationResult.Reason.EMPTY_ID), "catalog should report empty IDs", failures)
	_expect(result.has_reason(DataValidationResult.Reason.EMPTY_DISPLAY_NAME), "catalog should report empty display names", failures)
	_expect(result.has_reason(DataValidationResult.Reason.INVALID_MOVE_SPEED), "catalog should report invalid speeds", failures)
	_expect(result.has_reason(DataValidationResult.Reason.DUPLICATE_ID), "catalog should report duplicate IDs", failures)


func _test_battle_content_loader(failures: Array[String]) -> void:
	var grey_ridge_result := BattleContentLoader.load_battle(&"grey_ridge")
	_expect(grey_ridge_result.is_valid(), "Grey Ridge should load through the validated battle content catalog (issues=%s)" % [grey_ridge_result.validation.issues], failures)
	if grey_ridge_result.battle != null:
		_expect(grey_ridge_result.catalog.battles.size() == 5, "the shared battle loader should expose four playable battles and the minimal loader fixture", failures)
		var selectable := grey_ridge_result.catalog.get_selectable_battles()
		_expect(selectable.size() == 4, "the operation selector should expose exactly the four playable battles", failures)
		if selectable.size() == 4:
			_expect(selectable[0].scenario_id == &"grey_ridge" and selectable[1].scenario_id == &"broken_bridge" and selectable[2].scenario_id == &"fog_forest" and selectable[3].scenario_id == &"black_well", "selectable battles should be ordered by operation number", failures)
			var scenes_load := true
			for battle in selectable:
				scenes_load = scenes_load and ResourceLoader.exists(battle.scene_path, "PackedScene")
			_expect(scenes_load, "every selectable battle should reference a loadable scene", failures)
		_expect(grey_ridge_result.battle.region_dictionary().size() == 3, "Grey Ridge content should define all strategic regions", failures)
		_expect(grey_ridge_result.battle.enemy_plan_dictionary().size() == 3, "Grey Ridge content should define all locked enemy plans", failures)
		_expect(grey_ridge_result.battle.support_dictionary().size() == 3, "Grey Ridge content should define all support abilities", failures)
	var minimal_result := BattleContentLoader.load_battle(&"loader_test")
	_expect(minimal_result.is_valid() and minimal_result.battle.scenario_id == &"loader_test", "the shared loader should create a second minimal battle definition", failures)
	var missing_result := BattleContentLoader.load_battle(&"grey_ridge", "res://data/battles/missing_catalog.tres")
	_expect(missing_result.validation.has_reason(DataValidationResult.Reason.RESOURCE_NOT_FOUND), "missing battle catalogs should return a structured resource-not-found issue", failures)
	var wrong_type_result := BattleContentLoader.load_battle(&"grey_ridge", "res://data/units/unit_catalog.tres")
	_expect(wrong_type_result.validation.has_reason(DataValidationResult.Reason.INVALID_RESOURCE_TYPE), "wrong catalog resource types should return a structured type issue", failures)
	var unknown_result := BattleContentLoader.load_battle(&"unknown_battle")
	_expect(unknown_result.validation.has_reason(DataValidationResult.Reason.INVALID_REFERENCE), "unknown scenario IDs should return a structured reference issue", failures)


func _test_battle_reference_validation(failures: Array[String]) -> void:
	var battle := BattleDefinition.new()
	battle.scenario_id = &"invalid_reference_test"
	battle.display_name_key = &"GREY_RIDGE_TITLE"
	battle.starting_card_count = 1
	battle.friendly_formation_ids.assign([1])
	battle.friendly_spawn_positions.assign([Vector2(64.0, 64.0)])
	var region := BattleRegionDefinition.new()
	region.region_id = &"only_region"
	region.display_name_key = &"GREY_RIDGE_CENTRAL"
	region.terrain_key = &"TERRAIN_OPEN"
	region.adjacent_region_ids.assign([&"missing_region"])
	battle.strategic_regions.append(region)
	var result := battle.validate()
	_expect(result.has_reason(DataValidationResult.Reason.INVALID_REFERENCE), "battle validation should report dangling region references", failures)
	var loaded := BattleContentLoader.load_battle(&"grey_ridge")
	if loaded.battle != null:
		var mismatched := loaded.battle.duplicate(true) as BattleDefinition
		mismatched.enemy_formations[0].agent_id = 2
		var mismatch_result := mismatched.validate(BattleContentLoader.UNIT_CATALOG)
		_expect(mismatch_result.has_reason(DataValidationResult.Reason.INVALID_REFERENCE), "battle validation should reject enemy formations assigned to a different Agent contract", failures)


func _test_world_consumes_battle_content(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	_expect(world.battle_definition != null and world.battle_definition.scenario_id == &"grey_ridge", "Grey Ridge SimulationWorld should retain its validated battle definition", failures)
	if world.battle_definition == null:
		return
	var central := world.strategic_regions.get(&"central_relay") as StrategicRegionState
	_expect(central != null and central.adjacent_region_ids.has(&"west_mine") and central.support_cooldown_ticks == 150, "strategic region adjacency and support timing should come from battle content", failures)
	var recon := world.battle_definition.support_for_kind(SupportOrderCommand.SupportKind.AIR_RECON)
	_expect(recon != null and world.get_support_cost(SupportOrderCommand.SupportKind.AIR_RECON) == recon.supply_cost, "authoritative support cost should come from battle content", failures)
	var default_plan := world.battle_definition.create_default_army_plan()
	_expect(default_plan.starting_unit_card_ids == world.grey_ridge_army_plan.starting_unit_card_ids, "the active default army plan should come from battle content", failures)


func _test_broken_bridge_engineering_and_terrain(failures: Array[String]) -> void:
	var loaded := BattleContentLoader.load_battle(&"broken_bridge")
	_expect(loaded.is_valid(), "Broken Bridge should load as a validated battle package (issues=%s)" % [loaded.validation.issues], failures)
	if not loaded.is_valid():
		return
	_expect(loaded.battle.unit_card_definitions.size() == 6 and loaded.battle.doctrine_definitions.size() == 6, "Broken Bridge should add two unit cards and two doctrines to the four-card baseline", failures)
	_expect(loaded.battle.enemy_plans.size() == 3 and loaded.battle.engineering_routes.size() == 1, "Broken Bridge should define three locked plans and one engineering route", failures)
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BROKEN_BRIDGE)
	_expect(world.get_scenario_id() == &"broken_bridge" and world.unit_cards.has(&"bridge_engineer_group"), "Broken Bridge should initialize its own scenario and engineering card", failures)
	var crossing_cell := Vector2i(146, 63)
	_expect(world.logic_grid.is_blocked(crossing_cell), "the damaged east ford should initially block authoritative navigation", failures)
	var open_route := SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, SupportOrderCommand.SupportKind.ENGINEERING_ROUTE,
		&"east_engineering_ford", &"", &"bridge_engineer_group"
	)
	_expect(world.submit_command(open_route).is_accepted(), "a deployed engineering card should be able to order the side route opened", failures)
	var revision_before := world.logic_grid.revision
	world.advance_tick()
	_expect(not world.logic_grid.is_blocked(crossing_cell) and world.logic_grid.revision > revision_before, "opening the engineering route should mutate the shared grid and invalidate cached paths", failures)
	var duplicate := SupportOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER,
		world.current_tick, SupportOrderCommand.SupportKind.ENGINEERING_ROUTE,
		&"east_engineering_ford", &"", &"bridge_engineer_group"
	)
	_expect(not world.submit_command(duplicate).is_accepted(), "an already opened engineering route should reject duplicate orders", failures)
	var fire_card := world.unit_cards.get(&"thunder_fire_group") as UnitCardState
	var fire_unit := world.units.get(fire_card.member_entity_ids[0]) as UnitState if fire_card != null and not fire_card.member_entity_ids.is_empty() else null
	if fire_unit != null:
		fire_unit.position = Vector2(1664.0, 1472.0)
		world._update_grey_ridge_terrain_effects()
		_expect(fire_unit.terrain_kind == UnitState.TerrainKind.HIGH_GROUND and fire_unit.attack_range > fire_unit.base_attack_range and fire_unit.sight_range > fire_unit.base_sight_range, "high ground should measurably improve firepower range and vision", failures)
	else:
		_expect(false, "the default Broken Bridge plan should deploy a firepower card for terrain verification", failures)

	var bridging_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BROKEN_BRIDGE)
	var ford := bridging_world.battle_definition.region_dictionary()[&"east_supply"] as BattleRegionDefinition
	var ford_order := CommanderOrderCommand.new(
		bridging_world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, bridging_world.current_tick,
		&"di_tian", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, ford.position, ford.region_id
	)
	_expect(bridging_world.submit_command(ford_order).is_accepted(), "Rapid Bridging should retain a legal player-selected eastern attack axis", failures)
	bridging_world.advance_tick()
	var engineer_task := bridging_world._task_for_unit_card(&"bridge_engineer_group")
	var assault_task := bridging_world._task_for_unit_card(&"ironwall_assault_group")
	var player_hq := bridging_world.battle_definition.player_headquarters_position
	_expect(engineer_task != null and assault_task != null and engineer_task.target_position.distance_to(player_hq) < assault_task.target_position.distance_to(player_hq), "Rapid Bridging should keep the engineering card behind the assault card instead of using it as frontline infantry", failures)
	bridging_world.advance_tick()
	_expect(bridging_world.opened_engineering_routes.has(&"east_engineering_ford") and (bridging_world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).supply == 4, "Rapid Bridging should automatically open the linked ford through the normal two-supply command path after the player selects that axis", failures)

	var overwatch_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BROKEN_BRIDGE)
	var heights := overwatch_world.battle_definition.region_dictionary()[&"west_mine"] as BattleRegionDefinition
	var heights_order := CommanderOrderCommand.new(
		overwatch_world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, overwatch_world.current_tick,
		&"lin_mo", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, heights.position, heights.region_id
	)
	_expect(overwatch_world.submit_command(heights_order).is_accepted(), "Overwatch Lattice should retain a legal player-selected high-ground objective", failures)
	overwatch_world.advance_tick()
	var fire_task := overwatch_world._task_for_unit_card(&"thunder_fire_group")
	var lin := overwatch_world.commanders[&"lin_mo"] as CommanderState
	_expect(fire_task != null and fire_task.target_position.distance_to(player_hq) < heights.position.distance_to(player_hq) and fire_task.activation_tick >= 30, "Overwatch Lattice should stage firepower behind the objective with a deliberate setup interval", failures)
	_expect(lin.behavior_reason_key == &"COMMANDER_REASON_OVERWATCH_LATTICE_STAGING", "Overwatch Lattice preparation should be visible in commander behavior feedback", failures)


func _test_fog_forest_intel_and_escort(failures: Array[String]) -> void:
	var loaded := BattleContentLoader.load_battle(&"fog_forest")
	_expect(loaded.is_valid(), "Fog Forest should load as a validated battle package (issues=%s)" % [loaded.validation.issues], failures)
	if not loaded.is_valid():
		return
	_expect(loaded.battle.unit_card_definitions.size() == 6 and loaded.battle.enemy_plans.size() == 3, "Fog Forest should add two persistent unit cards and three locked enemy plans", failures)
	_expect(loaded.battle.contact_fade_after_ticks > 0 and loaded.battle.contact_expire_after_ticks > loaded.battle.contact_fade_after_ticks, "Fog Forest should define a valid intelligence decay window", failures)

	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.FOG_FOREST)
	_expect(world.get_scenario_id() == &"fog_forest" and world.unit_cards.has(&"frontline_logistics_column"), "Fog Forest should initialize its logistics objective through scenario content", failures)
	var logistics := world.unit_cards.get(&"frontline_logistics_column") as UnitCardState
	var destination := world.strategic_regions.get(&"forward_supply_node") as StrategicRegionState
	var transport := world.units.get(logistics.member_entity_ids[0]) as UnitState if logistics != null and not logistics.member_entity_ids.is_empty() else null
	var player := world.factions.get(SimulationWorld.LOCAL_PLAYER_ID) as FactionState
	if transport != null and destination != null and player != null:
		var previous_capacity := player.supply_capacity
		transport.position = destination.position
		world._advance_escort_supply_node()
		_expect(world.escort_supply_node_active and destination.supply_node_active, "a surviving transport reaching the configured node should activate it", failures)
		_expect(player.supply_capacity == previous_capacity + loaded.battle.escort_supply_capacity_bonus and destination.supply_per_settlement == loaded.battle.escort_region_supply_bonus, "node activation should apply capacity and regional income rewards exactly once", failures)
	else:
		_expect(false, "Fog Forest should deploy a real transport formation and destination region", failures)

	var hidden_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.FOG_FOREST)
	hidden_world.current_tick = hidden_world.enemy_reaction_committed_until_tick
	hidden_world._update_faction_knowledge()
	hidden_world._advance_escort_interception()
	_expect(hidden_world.enemy_escort_intercept_target_id == 0, "enemy interception must not use a convoy hidden from enemy faction knowledge", failures)
	var hidden_logistics := hidden_world.unit_cards.get(&"frontline_logistics_column") as UnitCardState
	var hidden_transport := hidden_world.units.get(hidden_logistics.member_entity_ids[0]) as UnitState
	var enemy_probe := hidden_world._enemy_formation_state(&"probe")
	hidden_transport.position = enemy_probe.anchor_position + Vector2(96.0, 0.0)
	hidden_world._update_faction_knowledge()
	hidden_world._advance_escort_interception()
	hidden_world.current_tick += hidden_world.battle_definition.escort_intercept_delay_ticks
	hidden_world._update_faction_knowledge()
	hidden_world._advance_escort_interception()
	var enemy_knowledge := hidden_world.faction_knowledge[SimulationWorld.ENEMY_PLAYER_ID] as FactionKnowledge
	_expect(hidden_world.enemy_escort_intercept_target_id == hidden_transport.entity_id, "enemy interception should begin after enemy knowledge visibly identifies a transport (visible=%s contacts=%s tick=%d commit=%d log=%s)" % [enemy_knowledge.visible_hostile_unit_ids, enemy_knowledge.hostile_contacts.keys(), hidden_world.current_tick, hidden_world.enemy_reaction_committed_until_tick, hidden_world.enemy_reaction_log], failures)

	var decay_world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.FOG_FOREST)
	var local_scout := decay_world.units.get(1) as UnitState
	var hostile := decay_world.units.get(1001) as UnitState
	hostile.position = local_scout.position + Vector2(64.0, 0.0)
	decay_world._update_faction_knowledge()
	var local_knowledge := decay_world.faction_knowledge[SimulationWorld.LOCAL_PLAYER_ID] as FactionKnowledge
	_expect(local_knowledge.hostile_contacts.has(hostile.entity_id), "visible Fog Forest hostiles should enter faction knowledge", failures)
	hostile.position = decay_world.battle_definition.enemy_headquarters_position
	decay_world.current_tick += decay_world.battle_definition.contact_fade_after_ticks + 1
	decay_world._update_faction_knowledge()
	var stale_snapshot := decay_world.create_snapshot()
	var stale_contact := stale_snapshot.get_unit(hostile.entity_id)
	_expect(stale_contact != null and not stale_contact.is_visible_to_local_player and stale_contact.intel_freshness < 1.0, "old contacts should become visibly stale without becoming live targets", failures)
	decay_world.current_tick += decay_world.battle_definition.contact_expire_after_ticks
	decay_world._update_faction_knowledge()
	_expect(not local_knowledge.hostile_contacts.has(hostile.entity_id), "Fog Forest contacts should expire from authoritative faction knowledge", failures)


func _test_black_well_organization_and_withdrawal(failures: Array[String]) -> void:
	var loaded := BattleContentLoader.load_battle(&"black_well")
	_expect(loaded.is_valid(), "Black Well should load as a validated battle package (issues=%s)" % [loaded.validation.issues], failures)
	if not loaded.is_valid():
		return
	_expect(loaded.battle.commander_definitions.size() == 5 and loaded.battle.unit_card_definitions.size() == 12 and loaded.battle.doctrine_definitions.size() == 12, "Black Well should complete the five-commander, twelve-card, twelve-doctrine content roster", failures)
	_expect(loaded.battle.enemy_plans.size() == 3 and loaded.battle.support_abilities.size() == 6 and not loaded.battle.withdrawal_region_id.is_empty() and loaded.battle.organization_max == 100.0, "Black Well should define three locked plans, six support types, limited withdrawal, and organization", failures)

	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	_expect(world.get_scenario_id() == &"black_well" and world.commanders.size() == 5 and world.unit_cards.size() == 12, "Black Well should instantiate its complete roster from content", failures)
	var gu := world.commanders.get(&"gu_hanxing") as CommanderState
	_expect(gu != null and gu.subordinate_unit_card_ids == [&"armored_spearhead", &"mobile_counterattack_group"], "commander subordinates should use stable lexical card ordering for deterministic task assignment", failures)
	var guard := world.unit_cards.get(&"blackwell_guard_battalion") as UnitCardState
	var core := world.strategic_regions.get(&"black_well_core") as StrategicRegionState
	var withdrawal := world.strategic_regions.get(&"withdrawal_corridor") as StrategicRegionState
	_expect(guard != null and guard.organization_enabled and is_equal_approx(guard.organization, 100.0), "deployed Black Well cards should begin with authoritative organization", failures)
	if guard == null or core == null or withdrawal == null:
		return
	var damaged_member := world.units.get(guard.member_entity_ids[0]) as UnitState
	damaged_member.health -= 30.0
	world._advance_unit_card_organization()
	var organization_after_damage := guard.organization
	_expect(organization_after_damage < 100.0 and guard.last_damage_tick == world.current_tick, "real member damage should reduce card organization and start its recovery delay", failures)
	for entity_id in guard.member_entity_ids:
		var member := world.units.get(entity_id) as UnitState
		if member != null and member.enabled:
			member.position = core.position
	guard.last_damage_tick = world.current_tick - loaded.battle.organization_recovery_delay_ticks
	world._advance_unit_card_organization()
	_expect(guard.organization > organization_after_damage, "a card out of contact in the Black Well rally sector should recover organization", failures)

	var order := CommanderOrderCommand.new(
		world.allocate_command_id(), SimulationWorld.LOCAL_PLAYER_ID, world.current_tick,
		&"lu_zheng", CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, withdrawal.position, withdrawal.region_id
	)
	_expect(world.submit_command(order).is_accepted(), "Lu Zheng should accept the explicit withdrawal-corridor objective", failures)
	world.advance_tick()
	for entity_id in guard.member_entity_ids:
		var survivor := world.units.get(entity_id) as UnitState
		if survivor != null and survivor.enabled:
			survivor.position = withdrawal.position
	world._advance_limited_withdrawals()
	var snapshot := world.create_snapshot().get_unit_card(&"blackwell_guard_battalion")
	_expect(guard.deployment_state == UnitCardState.DeploymentState.WITHDRAWN and guard.withdrawn_strength > 0, "all surviving members reaching an explicitly targeted corridor should withdraw the whole persistent card", failures)
	_expect(snapshot != null and snapshot.current_strength == guard.withdrawn_strength and snapshot.active_member_entity_ids.is_empty(), "withdrawn survivors should remain recorded without staying as active battlefield entities", failures)
	world._advance_strategic_regions()
	_expect(withdrawal.controller_faction_id == 0 and not withdrawal.contested, "the withdrawal corridor should never become a capturable resource sector", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
