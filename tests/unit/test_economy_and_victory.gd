class_name TestEconomyAndVictory
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_scenario_and_differentiated_data(failures)
	_test_harvest_and_production_pipeline(failures)
	_test_snapshot_copy_and_victory(failures)
	return failures


func _test_scenario_and_differentiated_data(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var definitions: Dictionary = {}
	for unit in world.create_snapshot().units:
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			definitions[unit.definition_id] = true
	_expect(definitions.size() == 5, "default formation should contain five differentiated unit definitions", failures)
	_expect(world.create_true_state_snapshot().buildings.size() == 4, "true-state scenario should contain three friendly buildings and enemy command center", failures)
	_expect(world.create_snapshot().ore_fields.size() == 1, "scenario should expose one authoritative ore field", failures)
	_expect(SimulationWorld.UNIT_CATALOG.validate().is_valid(), "five-unit catalog should validate", failures)
	_expect(SimulationWorld.BUILDING_CATALOG.validate().is_valid(), "three-building catalog should validate", failures)


func _test_harvest_and_production_pipeline(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var ore_before := (world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore
	var harvest := HarvestCommand.new(1, SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, 0, 1, SimulationWorld.DEFAULT_ORE_FIELD_ID, SimulationWorld.PLAYER_COMMAND_CENTER_ID)
	_expect(world.submit_command(harvest).is_accepted(), "valid harvest command should enter shared validator and queue", failures)
	_expect((world.units[1] as UnitState).harvest_ore_field_entity_id == 0, "harvest command must wait for tick", failures)
	for _tick in range(EconomySystem.HARVEST_INTERVAL_TICKS):
		world.advance_tick()
	_expect((world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore == ore_before + EconomySystem.HARVEST_AMOUNT, "harvest should transfer finite ore authoritatively", failures)

	var produce := ProduceUnitCommand.new(2, SimulationWorld.LOCAL_PLAYER_ID, GameCommand.IssuerKind.PLAYER, world.current_tick, SimulationWorld.PLAYER_FACTORY_ID, &"scout_vehicle")
	_expect(world.submit_command(produce).is_accepted(), "factory production should validate with available ore", failures)
	world.advance_tick()
	var ore_after_payment := (world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore
	_expect(ore_after_payment == ore_before + EconomySystem.HARVEST_AMOUNT - 100, "production cost should be paid at tick boundary", failures)
	_expect(world.submit_command(ProduceUnitCommand.new(3, 1, GameCommand.IssuerKind.PLAYER, world.current_tick, SimulationWorld.PLAYER_FACTORY_ID, &"scout_vehicle")).reason == CommandValidationResult.Reason.PRODUCTION_BUSY, "busy factory should reject another order", failures)
	for _tick in range(20):
		world.advance_tick()
	_expect(world.create_snapshot().get_unit(1100) != null, "completed production should create a snapshot-visible unit", failures)


func _test_snapshot_copy_and_victory(failures: Array[String]) -> void:
	var world := SimulationWorld.new()
	var old_snapshot := world.create_snapshot()
	var old_ore := old_snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID).ore
	(world.factions[SimulationWorld.LOCAL_PLAYER_ID] as FactionState).ore += 50
	(world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState).ore_remaining -= 50
	_expect(old_snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID).ore == old_ore, "old faction snapshot must remain immutable", failures)
	_expect(old_snapshot.get_ore_field(SimulationWorld.DEFAULT_ORE_FIELD_ID).ore_remaining == 1200, "old ore snapshot must remain immutable", failures)
	world.destroy_building(SimulationWorld.ENEMY_COMMAND_CENTER_ID)
	world.advance_tick()
	var snapshot := world.create_snapshot()
	_expect(snapshot.get_faction(SimulationWorld.ENEMY_PLAYER_ID).defeated, "losing all command centers should defeat faction", failures)
	_expect(snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID).victorious, "last faction with command center should win", failures)
	_expect(not old_snapshot.get_faction(SimulationWorld.ENEMY_PLAYER_ID).defeated, "old victory snapshot must remain immutable", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
