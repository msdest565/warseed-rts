class_name TestEconomyAndVictory
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_scenario_and_differentiated_data(failures)
	_test_real_harvest_trip_and_production_pipeline(failures)
	_test_production_catalog_queue_cancel_and_rally(failures)
	_test_construction_occupancy_and_repair(failures)
	_test_manual_building_destruction_victory(failures)
	return failures


func _test_scenario_and_differentiated_data(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var definitions: Dictionary = {}
	for unit in world.create_snapshot().units:
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			definitions[unit.definition_id] = true
	_expect(definitions.size() == 5, "default formation should contain five differentiated unit definitions", failures)
	_expect(world.create_true_state_snapshot().buildings.size() == 4, "true-state scenario should contain three friendly buildings and enemy command center", failures)
	_expect(world.create_true_state_snapshot().ore_fields.size() == 4, "scenario should provide primary and expansion ore fields for both factions", failures)
	_expect(world.create_snapshot().ore_fields.size() == 1, "scenario should expose one authoritative ore field", failures)
	_expect((world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState).ore_remaining == SimulationWorld.PRIMARY_ORE_CAPACITY, "player primary ore should support a full-length match", failures)
	_expect((world.ore_fields[SimulationWorld.PLAYER_EXPANSION_ORE_FIELD_ID] as OreFieldState).ore_remaining == SimulationWorld.EXPANSION_ORE_CAPACITY, "player expansion should provide a second economic objective", failures)
	_expect(SimulationWorld.PRIMARY_ORE_CAPACITY + SimulationWorld.EXPANSION_ORE_CAPACITY >= 18000, "each faction should have enough finite ore for sustained development", failures)
	_expect(SimulationWorld.UNIT_CATALOG.validate().is_valid(), "five-unit catalog should validate", failures)
	_expect(SimulationWorld.BUILDING_CATALOG.validate().is_valid(), "three-building catalog should validate", failures)
	var player_spawn := LogicGrid.MAP_DEFINITION.player_spawn_cell
	var enemy_spawn := LogicGrid.MAP_DEFINITION.enemy_spawn_cell
	_expect(player_spawn.x < LogicGrid.GRID_SIZE.x / 2 and player_spawn.y < LogicGrid.GRID_SIZE.y / 2, "player base should start in the upper-left quadrant", failures)
	_expect(enemy_spawn.x > LogicGrid.GRID_SIZE.x / 2 and enemy_spawn.y > LogicGrid.GRID_SIZE.y / 2, "enemy base should start in the lower-right quadrant", failures)
	var enemy_ore := world.ore_fields[SimulationWorld.ENEMY_ORE_FIELD_ID] as OreFieldState
	_expect(enemy_ore.position.distance_to((world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState).position) < 320.0, "enemy ore field should be located near the enemy base", failures)
	_expect(enemy_ore.position.distance_to((world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState).position) > 1600.0, "player and enemy ore fields should be spatially separated", failures)
	var enemy_harvester := world.units[SimulationWorld.ENEMY_HARVESTER_ID] as UnitState
	enemy_ore.ore_remaining = 0
	world.current_tick = world.enemy_raid_agent.difficulty_profile.opening_delay_ticks
	world.advance_tick()
	world.advance_tick()
	_expect(enemy_harvester.harvest_ore_field_entity_id == SimulationWorld.ENEMY_EXPANSION_ORE_FIELD_ID, "enemy harvesters should switch to their own expansion after primary depletion", failures)


func _test_real_harvest_trip_and_production_pipeline(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var faction := world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState
	var ore_before := faction.ore
	var ore_field := world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState
	var field_before := ore_field.ore_remaining
	var harvest := HarvestCommand.new(1, SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, 0, 1, SimulationWorld.DEFAULT_ORE_FIELD_ID, SimulationWorld.PLAYER_COMMAND_CENTER_ID)
	_expect(world.submit_command(harvest).is_accepted(), "valid harvest command should enter shared validator and queue", failures)
	_expect((world.units[1] as UnitState).harvest_phase == UnitState.HarvestPhase.IDLE, "harvest command must wait for tick", failures)
	var saw_outbound_movement := false
	var saw_loaded_cargo_before_delivery := false
	for _tick in range(180):
		world.advance_tick()
		var harvester := world.units[1] as UnitState
		saw_outbound_movement = saw_outbound_movement or harvester.harvest_phase == UnitState.HarvestPhase.TO_FIELD and harvester.has_move_target
		if harvester.cargo_ore > 0 and faction.ore == ore_before:
			saw_loaded_cargo_before_delivery = true
		if faction.ore > ore_before:
			break
	_expect(saw_outbound_movement, "harvester should physically travel to the ore field", failures)
	_expect(saw_loaded_cargo_before_delivery, "loaded cargo should not become faction ore until the return trip completes", failures)
	_expect(faction.ore == ore_before + EconomySystem.HARVEST_AMOUNT, "returning harvester should unload finite ore at the refinery", failures)
	_expect(ore_field.ore_remaining == field_before - EconomySystem.HARVEST_AMOUNT, "ore should be removed when cargo is loaded", failures)

	var produce := ProduceUnitCommand.new(2, SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, SimulationWorld.PLAYER_FACTORY_ID, &"scout_vehicle")
	_expect(world.submit_command(produce).is_accepted(), "factory production should validate with available ore", failures)
	world.advance_tick()
	var ore_after_payment := faction.ore
	_expect(ore_after_payment == ore_before + EconomySystem.HARVEST_AMOUNT - 100, "production cost should be paid at tick boundary", failures)
	_expect(world.submit_command(ProduceUnitCommand.new(3, 1, GameCommand.IssuerKind.PLAYER, world.current_tick, SimulationWorld.PLAYER_FACTORY_ID, &"scout_vehicle")).is_accepted(), "busy factory should accept another valid item into its queue", failures)
	world.advance_tick()
	_expect((world.buildings[SimulationWorld.PLAYER_FACTORY_ID] as BuildingState).production_queue == [&"scout_vehicle"], "second production order should remain in the authoritative waiting queue", failures)
	for _tick in range(19):
		world.advance_tick()
	_expect(world.create_snapshot().get_unit(1100) != null, "completed production should create a snapshot-visible unit", failures)


func _test_production_catalog_queue_cancel_and_rally(failures: Array[String]) -> void:
	var catalog_world := SimulationWorld.new()
	var factory_harvester := ProduceUnitCommand.new(catalog_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SimulationWorld.PLAYER_FACTORY_ID, &"harvester")
	var center_scout := ProduceUnitCommand.new(catalog_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SimulationWorld.PLAYER_COMMAND_CENTER_ID, &"scout_vehicle")
	var center_harvester := ProduceUnitCommand.new(catalog_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SimulationWorld.PLAYER_COMMAND_CENTER_ID, &"harvester")
	_expect(catalog_world.submit_command(factory_harvester).reason == CommandValidationResult.Reason.INVALID_DEFINITION, "factory should reject economic units outside its production catalog", failures)
	_expect(catalog_world.submit_command(center_scout).reason == CommandValidationResult.Reason.INVALID_DEFINITION, "command center should reject combat units outside its production catalog", failures)
	_expect(catalog_world.submit_command(center_harvester).is_accepted(), "command center should produce harvesters through the shared command pipeline", failures)

	var queue_world := SimulationWorld.new()
	(queue_world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore = 1000
	for index in range(BuildingState.MAX_PRODUCTION_QUEUE_SIZE):
		var queued := ProduceUnitCommand.new(queue_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SimulationWorld.PLAYER_FACTORY_ID, &"scout_vehicle")
		_expect(queue_world.submit_command(queued).is_accepted(), "production slot %d should be accepted" % index, failures)
	var overflow := ProduceUnitCommand.new(queue_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SimulationWorld.PLAYER_FACTORY_ID, &"scout_vehicle")
	_expect(queue_world.submit_command(overflow).reason == CommandValidationResult.Reason.PRODUCTION_QUEUE_FULL, "sixth item should be rejected by the five-item queue limit", failures)
	queue_world.advance_tick()
	var queued_factory := queue_world.buildings[SimulationWorld.PLAYER_FACTORY_ID] as BuildingState
	_expect(queued_factory.production_count() == BuildingState.MAX_PRODUCTION_QUEUE_SIZE, "accepted production commands should preserve FIFO queue state", failures)
	var ore_after_queue := (queue_world.factions[1] as FactionState).ore
	var cancel_waiting := CancelProductionCommand.new(queue_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, queue_world.current_tick, queued_factory.entity_id, queued_factory.production_count() - 1)
	_expect(queue_world.submit_command(cancel_waiting).is_accepted(), "player should be able to cancel a waiting production item", failures)
	queue_world.advance_tick()
	_expect((queue_world.factions[1] as FactionState).ore == ore_after_queue + 100, "waiting production cancellation should refund its full cost", failures)

	var cancel_world := SimulationWorld.new()
	(cancel_world.factions[1] as FactionState).ore = 1000
	var assault := ProduceUnitCommand.new(cancel_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SimulationWorld.PLAYER_FACTORY_ID, &"assault_vehicle")
	cancel_world.submit_command(assault)
	cancel_world.advance_tick()
	var cancel_active := CancelProductionCommand.new(cancel_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, cancel_world.current_tick, SimulationWorld.PLAYER_FACTORY_ID, 0)
	_expect(cancel_world.submit_command(cancel_active).is_accepted(), "player should be able to cancel active production", failures)
	cancel_world.advance_tick()
	_expect((cancel_world.factions[1] as FactionState).ore == 937, "active cancellation should refund 75 percent of the paid 250 ore", failures)

	var rally_world := SimulationWorld.new()
	var rally_position := rally_world.logic_grid.cell_to_world(Vector2i(24, 12))
	var rally := SetRallyPointCommand.new(rally_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, SimulationWorld.PLAYER_FACTORY_ID, rally_position)
	_expect(rally_world.submit_command(rally).is_accepted(), "reachable production rally point should validate", failures)
	rally_world.advance_tick()
	var rally_factory := rally_world.buildings[SimulationWorld.PLAYER_FACTORY_ID] as BuildingState
	_expect(rally_factory.production_rally_position == rally_position, "rally point should apply only at the authoritative tick boundary", failures)
	rally_world.submit_command(ProduceUnitCommand.new(rally_world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, rally_world.current_tick, rally_factory.entity_id, &"scout_vehicle"))
	for _tick in range(22):
		rally_world.advance_tick()
	var rallied_unit := rally_world.units.get(1100) as UnitState
	_expect(rallied_unit != null and rallied_unit.has_move_target and rallied_unit.move_target == rally_position, "completed units should automatically path toward the configured rally point", failures)


func _test_construction_occupancy_and_repair(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var engineer := world.units[2] as UnitState
	var build_position := world.logic_grid.cell_to_world(Vector2i(24, 14))
	var build := BuildBuildingCommand.new(
		world.allocate_command_id(),
		SimulationWorld.LOCAL_PLAYER_ID,
		GameCommand.IssuerKind.PLAYER,
		world.current_tick,
		engineer.entity_id,
		&"automated_factory",
		build_position
	)
	_expect(world.submit_command(build).is_accepted(), "engineer should accept a funded building placement", failures)
	_expect(not world.buildings.has(SimulationWorld.FIRST_CONSTRUCTED_BUILDING_ID), "construction placement must wait for tick", failures)
	world.advance_tick()
	var building := world.buildings[SimulationWorld.FIRST_CONSTRUCTED_BUILDING_ID] as BuildingState
	_expect(building != null and building.under_construction and not building.operational, "placed building should begin as non-operational construction", failures)
	var footprint_blocked := true
	for cell in building.footprint_cells:
		footprint_blocked = footprint_blocked and world.logic_grid.is_blocked(cell)
	_expect(footprint_blocked, "placed building footprint should immediately block navigation", failures)
	var occupied := BuildBuildingCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, engineer.entity_id, &"forward_support_station", (world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState).position)
	_expect(world.submit_command(occupied).reason in [CommandValidationResult.Reason.CONSTRUCTION_BUSY, CommandValidationResult.Reason.BUILDING_OCCUPIED], "construction should reject busy engineers or occupied footprints", failures)
	for _tick in range(180):
		world.advance_tick()
		if building.operational:
			break
	_expect(building.operational and not building.under_construction and is_equal_approx(building.health, building.max_health), "engineer should travel to and finish the structure", failures)

	building.health -= 120.0
	var repair := RepairBuildingCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, engineer.entity_id, building.entity_id)
	_expect(world.submit_command(repair).is_accepted(), "engineer should accept repair for a damaged friendly building", failures)
	for _tick in range(30):
		world.advance_tick()
		if is_equal_approx(building.health, building.max_health):
			break
	_expect(is_equal_approx(building.health, building.max_health), "repair order should restore building health over authoritative ticks", failures)


func _test_manual_building_destruction_victory(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var old_snapshot := world.create_snapshot()
	var enemy_center := world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState
	enemy_center.health = 15.0
	var formation := world.formations[SimulationWorld.DEFAULT_FORMATION_ID] as FormationState
	formation.anchor_position = enemy_center.position + Vector2(-96.0, 0.0)
	for index in range(formation.member_entity_ids.size()):
		var unit := world.units[formation.member_entity_ids[index]] as UnitState
		unit.position = formation.anchor_position + Vector2(0.0, float(index - 2) * 16.0)
		unit.desired_position = unit.position
	world._update_faction_knowledge()
	var attack := AttackCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, formation.leader_entity_id, enemy_center.entity_id, formation.formation_id)
	_expect(world.submit_command(attack).is_accepted(), "visible enemy building should be a legal manual attack target", failures)
	for _tick in range(30):
		world.advance_tick()
		if not enemy_center.enabled:
			break
	var snapshot := world.create_snapshot()
	_expect(not enemy_center.enabled, "manual projectile combat should destroy the enemy command center", failures)
	_expect(snapshot.get_faction(SimulationWorld.ENEMY_PLAYER_ID).defeated, "destroying the final command center should defeat its faction", failures)
	_expect(snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID).victorious, "manual command-center destruction should complete the victory chain", failures)
	_expect(enemy_center.footprint_cells.is_empty(), "destroyed building should release its navigation footprint", failures)
	_expect(not old_snapshot.get_faction(SimulationWorld.ENEMY_PLAYER_ID).defeated, "old victory snapshot must remain immutable", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
