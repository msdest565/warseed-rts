class_name TestManualBattleReliability
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_manual_reactions(failures)
	_test_attack_move(failures)
	_test_headquarters(failures)
	_test_headquarters_maps(failures)
	_test_speed(failures)
	return failures


func _fixture() -> SimulationWorld:
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE)
	world.agents.clear()
	world.command_queue.drain()
	for value in world.units.values():
		var unit := value as UnitState
		if unit.faction_id != 1:
			unit.enabled = false
	return world


func _enemy(world: SimulationWorld, position: Vector2) -> UnitState:
	var enemy := UnitState.new(99999, position, 0.0, 2)
	world._apply_unit_definition(enemy, SimulationWorld.UNIT_CATALOG.get_unit(&"assault_vehicle"))
	enemy.can_attack = false
	enemy.health = 10000.0
	enemy.max_health = enemy.health
	world.units[enemy.entity_id] = enemy
	world._update_faction_knowledge()
	return enemy


func _test_manual_reactions(failures: Array[String]) -> void:
	var world := _fixture()
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var formation := world.formations[card.formation_id] as FormationState
	var enemy := _enemy(world, formation.anchor_position + Vector2(160, 0))
	var command := UnitCardControlCommand.new(world.allocate_command_id(), 1, 0, card.definition.definition_id, UnitCardControlCommand.Action.TAKEOVER)
	_expect(world.submit_command(command).is_accepted(), "takeover accepted", failures)
	world.advance_tick()
	_expect(card.control_state == UnitCardState.ControlState.PLAYER_OVERRIDDEN, "fixture retains blocked old task after takeover", failures)
	card.organization = 0
	var before := enemy.health
	for _tick in range(15):
		world.advance_tick()
	_expect(enemy.health < before, "manual card fires despite paused old task and zero organization", failures)
	var destination := formation.anchor_position + Vector2(400, 0)
	var move := FormationMoveCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, formation.leader_entity_id, formation.formation_id, destination)
	_expect(world.submit_command(move).is_accepted(), "manual movement accepted during combat", failures)
	destination = move.target_position
	var origin := formation.anchor_position
	for _tick in range(10):
		world.advance_tick()
	_expect(formation.order_kind == FormationState.OrderKind.MOVE and formation.order_destination == destination and formation.anchor_position.distance_to(origin) > 10, "self-defense preserves manual movement and destination", failures)
	var attack := AttackCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, formation.leader_entity_id, enemy.entity_id, formation.formation_id)
	card.organization = 0
	_expect(world.submit_command(attack).is_accepted(), "low organization does not reject basic player attack", failures)
	var automated := AttackCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.AGENT, world.current_tick, formation.leader_entity_id, enemy.entity_id, formation.formation_id)
	automated.agent_id = card.assigned_agent_id
	_expect(not world.submit_command(automated).is_accepted(), "manual control still rejects agent takeover", failures)


func _test_attack_move(failures: Array[String]) -> void:
	var world := _fixture()
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var formation := world.formations[card.formation_id] as FormationState
	var enemy := _enemy(world, formation.anchor_position + Vector2(240, 0))
	var destination := formation.anchor_position + Vector2(500, 0)
	var attack := AttackMoveCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, 0, formation.leader_entity_id, formation.formation_id, destination)
	_expect(world.submit_command(attack).is_accepted(), "Q attack-move enters same command pipeline", failures)
	destination = attack.target_position
	var before := enemy.health
	for _tick in range(45):
		world.advance_tick()
	_expect(enemy.health < before, "attack move acquires nearby enemy and deals real damage", failures)
	_expect(formation.order_destination == destination, "engagement preserves original attack-move destination", failures)
	enemy.enabled = false
	world._update_faction_knowledge()
	for _tick in range(3):
		world.advance_tick()
	_expect(formation.order_target_entity_id == 0 and formation.order_kind == FormationState.OrderKind.ATTACK_MOVE, "lost target resumes attack-move", failures)
	var mixed := TestTacticalCards.sample_world()
	var mixed_card := mixed.unit_cards[&"combined_assault"] as UnitCardState
	var mixed_formation := mixed.formations[mixed_card.formation_id] as FormationState
	var original_members := mixed_formation.member_entity_ids.duplicate()
	mixed._detach_noncombat_members(mixed_formation.formation_id)
	_expect(mixed_formation.member_entity_ids == original_members, "basic attacks never detach support members from a whole card", failures)


func _test_headquarters(failures: Array[String]) -> void:
	var world := _fixture()
	var projector := CardActionProjector.new()
	for action in projector.project(world.create_snapshot(), world.battle_definition):
		_expect(action.action_kind != CardActionSnapshot.ATTACK_HEADQUARTERS, "unseen enemy headquarters has no decision", failures)
	var headquarters := world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState
	var card := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	var member := world.units[card.member_entity_ids[0]] as UnitState
	member.position = headquarters.position + Vector2(-220, 0)
	world._update_faction_knowledge()
	var actions := projector.project(world.create_snapshot(), world.battle_definition)
	var decision: CardActionSnapshot
	for action in actions:
		if action.action_kind == CardActionSnapshot.ATTACK_HEADQUARTERS and action.commander_id == card.commander_definition_id:
			decision = action
	_expect(decision != null, "discovered headquarters exposes commander attack decision", failures)
	if decision == null:
		return
	var command := CardActionProjector.headquarters_command(decision, world.allocate_command_id(), 1, world.current_tick)
	_expect(world.submit_command(command).is_accepted(), "headquarters location order passes real path validation", failures)
	world.advance_tick()
	var commander := world.commanders[card.commander_definition_id] as CommanderState
	_expect(commander.target_position == decision.position and not commander.current_task_ids.is_empty(), "headquarters decision creates real commander tasks", failures)
	member.position = Vector2(800, 2400)
	world._update_faction_knowledge()
	var remembered := world.create_snapshot().get_building(headquarters.entity_id)
	_expect(remembered != null and not remembered.is_visible, "headquarters location remains legal remembered knowledge", failures)
	var old_position := remembered.position
	headquarters.position += Vector2(64, 0)
	world._update_faction_knowledge()
	for action in projector.project(world.create_snapshot(), world.battle_definition):
		if action.action_kind == CardActionSnapshot.ATTACK_HEADQUARTERS:
			var acting_card := world.create_snapshot().get_unit_card(action.unit_card_id)
			_expect(action.position == old_position + old_position.direction_to(acting_card.center_position) * 320.0, "decision never tracks hidden headquarters truth", failures)


func _test_headquarters_maps(failures: Array[String]) -> void:
	for kind in [SimulationWorld.ScenarioKind.GREY_RIDGE, SimulationWorld.ScenarioKind.BROKEN_BRIDGE, SimulationWorld.ScenarioKind.FOG_FOREST, SimulationWorld.ScenarioKind.BLACK_WELL]:
		var world := SimulationWorld.new(true, false, kind)
		var headquarters := world.buildings[SimulationWorld.ENEMY_COMMAND_CENTER_ID] as BuildingState
		for value in world.units.values():
			var scout := value as UnitState
			if scout.faction_id == 1 and scout.enabled:
				scout.sight_range = 10000
				break
		world._update_faction_knowledge()
		var count := 0
		for action in CardActionProjector.new().project(world.create_snapshot(), world.battle_definition):
			if action.action_kind != CardActionSnapshot.ATTACK_HEADQUARTERS:
				continue
			count += 1
			var command := CardActionProjector.headquarters_command(action, world.allocate_command_id(), 1, world.current_tick)
			var result := world.validate_command(command)
			_expect(result.is_accepted(), "headquarters route accepted in scenario %d for %s: %s" % [kind, action.commander_id, result.describe()], failures)
		_expect(count > 0, "each map offers discovered headquarters attack", failures)


func _test_speed(failures: Array[String]) -> void:
	var world := _fixture()
	var unit := world.units[(world.unit_cards[&"ironwall_assault_group"] as UnitCardState).member_entity_ids[0]] as UnitState
	var base := unit.base_move_speed
	for _tick in range(10):
		world._update_grey_ridge_terrain_effects(true)
	_expect(unit.move_speed > 0 and unit.move_speed >= base * 0.7, "terrain refresh cannot compound a speed penalty", failures)
	var formation := world.formations[unit.formation_id] as FormationState
	_expect(FormationMovementSystem.LAGGED_ANCHOR_SPEED_SCALE == 0.25 and formation.member_entity_ids.size() > 1, "existing cohesive movement has explicit quarter-speed regrouping", failures)


func _expect(value: bool, message: String, failures: Array[String]) -> void:
	if not value:
		failures.append("Manual combat: " + message)
