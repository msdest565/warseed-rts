extends SceneTree

const SLICE_TICKS := 3600


func _initialize() -> void:
	var world := SimulationWorld.new()
	var damage_events := 0
	var destroyed_events := 0
	var event_cursor := 0
	for _tick in range(SLICE_TICKS):
		world.advance_tick()
		while event_cursor < world.events.size():
			var event := world.events[event_cursor] as SimulationEvent
			if event.kind == SimulationEvent.Kind.DAMAGE_APPLIED:
				damage_events += 1
			elif event.kind in [SimulationEvent.Kind.UNIT_DESTROYED, SimulationEvent.Kind.BUILDING_DESTROYED]:
				destroyed_events += 1
			event_cursor += 1
	var enemy_harvester := world.units.get(SimulationWorld.ENEMY_HARVESTER_ID) as UnitState
	var enemy_ore := world.ore_fields[SimulationWorld.ENEMY_ORE_FIELD_ID] as OreFieldState
	var player_ore := world.ore_fields[SimulationWorld.DEFAULT_ORE_FIELD_ID] as OreFieldState
	print("WARSEED vertical slice: ticks=%d phases=%s damage=%d destroyed=%d player_ore=%d enemy_ore=%d enemy_gold=%d" % [
		SLICE_TICKS,
		str(world.enemy_raid_agent.phase_history),
		damage_events,
		destroyed_events,
		player_ore.ore_remaining,
		enemy_ore.ore_remaining,
		(world.factions[SimulationWorld.ENEMY_PLAYER_ID] as FactionState).ore,
	])
	var passed := (
		world.enemy_raid_agent.phase_history.has(EnemyRaidAgent.Phase.RAIDING)
		and damage_events > 0
		and enemy_ore.ore_remaining > 0
		and enemy_ore.ore_remaining < SimulationWorld.PRIMARY_ORE_CAPACITY
		and player_ore.ore_remaining == SimulationWorld.PRIMARY_ORE_CAPACITY
		and enemy_harvester != null
		and enemy_harvester.can_attack
	)
	if not passed:
		push_error("Vertical slice failed its economy/combat pacing gates")
	quit(0 if passed else 1)
