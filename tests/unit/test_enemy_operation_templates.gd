class_name TestEnemyOperationTemplates
extends RefCounted

func run() -> Array[String]:
	var failures: Array[String] = []
	var traces: Dictionary = {}
	for repeat_index in range(2):
		for plan in [&"central_assault", &"western_hook", &"western_feint"]:
			var world := SimulationWorld.new(true,false,SimulationWorld.ScenarioKind.GREY_RIDGE,{},plan)
			var definition := world.battle_definition.enemy_plan_dictionary()[plan] as BattleEnemyPlanDefinition
			_check(definition.operation != null and definition.operation.operation_id == plan,"explicit stable template",failures)
			# Isolate authored movement from combat; complete natural battles remain in the release matrix.
			for unit in world.units.values():
				if unit.faction_id == 1: unit.enabled=false
			var trace: PackedStringArray = []
			for tick in range(400):
				world.advance_tick()
				if world.current_tick % 40 == 0:
					trace.append("%d/%s/%s" % [world.current_tick,world._enemy_formation_state(&"assault").anchor_position,world._enemy_formation_state(&"probe").anchor_position])
			var west := world.strategic_regions[&"west_mine"] as StrategicRegionState
			_check(west.controller_faction_id == (2 if plan == &"western_hook" else 0),"only occupying assault captures west; scout does not",failures)
			_check(world.enemy_opening_followup_executed == (plan == &"western_feint"),"feint actually redirects",failures)
			var fingerprint := "|".join(trace)
			if repeat_index == 1: _check(traces[plan] == fingerprint,"trajectory repeat deterministic",failures)
			else: traces[plan]=fingerprint
			print("ENEMY_TEMPLATE plan=",plan," repeat=",repeat_index," trace=",fingerprint," west=",west.controller_faction_id)
	_check(traces[&"central_assault"] != traces[&"western_hook"] and traces[&"central_assault"] != traces[&"western_feint"] and traces[&"western_hook"] != traces[&"western_feint"],"three actual distinct trajectories",failures)
	_test_supply(failures)
	return failures

func _test_supply(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true,false,SimulationWorld.ScenarioKind.GREY_RIDGE,{},&"western_hook")
	var west := world.strategic_regions[&"west_mine"] as StrategicRegionState
	var guard := world.formations[2] as FormationState
	# Establish ownership through ordinary capture before the enemy arrives.
	for id in guard.member_entity_ids: (world.units[id] as UnitState).position=west.position
	for tick in range(west.capture_required_ticks): world._advance_strategic_regions()
	_check(west.controller_faction_id == 1,"fixture captures west through ordinary control",failures)
	var before := _settlement(world)
	_check(before == 2,"held west grants two supply",failures)
	# Remove local defenders to isolate the actual authored west-hook march and capture.
	world.current_tick=0
	for unit in world.units.values():
		if unit.faction_id == 1: unit.enabled=false
	for tick in range(400): world.advance_tick()
	_check(west.controller_faction_id == 2,"west hook really takes supply region",failures)
	var cut := _settlement(world)
	_check(cut == 0,"ordinary settlement cuts player region income",failures)
	# Reclaim through actual player movement, not direct ownership mutation.
	for unit in world.units.values():
		if unit.faction_id == 2: unit.enabled=false
	for id in guard.member_entity_ids:
		var unit := world.units[id] as UnitState
		unit.enabled=true
		unit.position=west.position+Vector2(0,400)
	guard.anchor_position=west.position+Vector2(0,400)
	var command := FormationMoveCommand.new(world.allocate_command_id(),1,GameCommand.IssuerKind.PLAYER,world.current_tick,guard.leader_entity_id,guard.formation_id,west.position)
	_check(world.submit_command(command).is_accepted(),"recapture movement accepted",failures)
	for tick in range(200): world.advance_tick()
	_check(west.controller_faction_id == 1,"ordinary movement recaptures west",failures)
	var restored := _settlement(world)
	_check(restored == 2,"ordinary settlement restores region income",failures)
	print("ENEMY_SUPPLY held=",before," cut=",cut," restored=",restored)

func _settlement(world: SimulationWorld) -> int:
	var faction := world.factions[1] as FactionState
	faction.supply=0
	var saved_tick := world.current_tick
	world.current_tick=world.battle_definition.region_settlement_interval_ticks
	world._advance_strategic_regions()
	world.current_tick=saved_tick
	return faction.supply

func _check(value: bool, label: String, failures: Array[String]) -> void:
	if not value: failures.append("Enemy templates: "+label)
