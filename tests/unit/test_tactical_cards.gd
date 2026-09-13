class_name TestTacticalCards
extends RefCounted

const CARD_PATHS: Array[String] = [
	"res://data/army/tactical/forward_observers.tres",
	"res://data/army/tactical/route_engineers.tres",
	"res://data/army/tactical/suppression_battery.tres",
	"res://data/army/tactical/combined_assault.tres",
	"res://data/army/tactical/ammunition_column.tres",
]


static func sample_world() -> SimulationWorld:
	var world := SimulationWorld.new(false, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	var battle := world.battle_definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as BattleDefinition
	battle.unit_card_definitions.clear()
	battle.default_commander_by_unit_card.clear()
	battle.default_starting_unit_card_ids.clear()
	battle.starting_card_count = 5
	battle.starting_supply = 30
	battle.supply_capacity = 40
	for path in CARD_PATHS:
		var card := load(path) as UnitCardDefinition
		battle.unit_card_definitions.append(card)
		battle.default_commander_by_unit_card[card.definition_id] = card.commander_definition_id
		battle.default_starting_unit_card_ids.append(card.definition_id)
	# Use an existing, publicly defined route to verify local engineer preparation.
	var bridge := load("res://data/battles/broken_bridge.tres") as BattleDefinition
	battle.engineering_routes.clear()
	for source in bridge.engineering_routes:
		var route := source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as BattleEngineeringRouteDefinition
		route.linked_region_id = battle.strategic_regions[0].region_id
		battle.engineering_routes.append(route)
	world.battle_definition = battle
	world.grey_ridge_army_plan = battle.create_default_army_plan()
	world.doctrine_definitions = battle.doctrine_dictionary()
	world._setup_grey_ridge_scenario()
	world._update_faction_knowledge()
	return world


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_data(failures)
	_test_observation_and_cost(failures)
	_test_observation_restart(failures)
	_test_weapon_constraints(failures)
	_test_resupply_and_interruption(failures)
	_test_engineering_breakthrough_and_control(failures)
	_test_suppression_and_agent(failures)
	_test_projected_targets(failures)
	return failures


func _test_projected_targets(failures: Array[String]) -> void:
	var world := sample_world()
	_quiet(world)
	var battery := world.unit_cards[&"suppression_battery"] as UnitCardState
	_place(world, battery, Vector2(2400, 3500))
	world._create_scenario_formation(800, 2, &"assault_vehicle", 2, Vector2(2700, 3500), 8000, Vector2.RIGHT)
	world._update_faction_knowledge()
	var snapshot := world.create_snapshot()
	snapshot.knowledge.identification_until_by_entity[8000] = snapshot.tick + 15
	var projector := TacticalActionProjector.new()
	var actions := projector.project(snapshot, world.battle_definition).filter(func(action: CardActionSnapshot) -> bool: return action.unit_card_id == &"suppression_battery")
	_expect(actions.size() == 1 and actions[0].target_entity_id == 8000, "visible formation yields one suppression decision and prefers its identified member", failures)
	if actions.is_empty():
		return
	var stable_id: StringName = actions[0].decision_id
	snapshot.units.reverse()
	snapshot.get_unit(8000).position = snapshot.get_unit_card(&"suppression_battery").center_position
	snapshot.knowledge.identification_until_by_entity[8001] = snapshot.tick + 15
	actions = projector.project(snapshot, world.battle_definition).filter(func(action: CardActionSnapshot) -> bool: return action.unit_card_id == &"suppression_battery")
	_expect(actions.size() == 1 and actions[0].target_entity_id == 8001 and actions[0].decision_id == stable_id, "same formation decision survives member order changes and avoids a target in the firing dead zone", failures)
	snapshot.get_unit(8000).is_visible_to_local_player = false
	snapshot.get_unit(8000).position = Vector2(2600, 3500)
	actions = projector.project(snapshot, world.battle_definition).filter(func(action: CardActionSnapshot) -> bool: return action.unit_card_id == &"suppression_battery")
	_expect(actions.size() == 1 and actions[0].target_entity_id == 8001, "hidden member cannot become a formation's selected fire-control target", failures)


func _test_data(failures: Array[String]) -> void:
	var sample := sample_world()
	_expect(sample.battle_definition.validate(SimulationWorld.UNIT_CATALOG).is_valid(), "five-card battle sample validates with existing content loader rules: %s" % [sample.battle_definition.validate(SimulationWorld.UNIT_CATALOG).issues], failures)
	_expect(SimulationWorld.UNIT_CATALOG.validate().is_valid(), "new typed unit catalog validates", failures)
	for path in CARD_PATHS:
		var card := load(path) as UnitCardDefinition
		_expect(card != null and card.tactical_ability.validate(SimulationWorld.UNIT_CATALOG).is_valid(), "tactical card data validates: " + path, failures)
	var bad := TacticalWeaponDefinition.new()
	bad.damage_tag = TacticalWeaponDefinition.DamageTag.GUIDED
	_expect(not bad.validate().is_valid(), "unbounded guided ammunition is refused", failures)
	bad.ammunition_capacity = 4
	bad.identification_required = true
	_expect(bad.validate().is_valid(), "bounded identified guided fire validates", failures)


func _test_observation_and_cost(failures: Array[String]) -> void:
	var world := sample_world()
	var card := world.unit_cards[&"forward_observers"] as UnitCardState
	_quiet(world)
	_place(world, card, Vector2(2400, 3500))
	var enemy := _enemy(world)
	enemy.position = Vector2(2800, 3500)
	enemy.enabled = true
	enemy.can_attack = false
	enemy.following_formation = false
	enemy.has_move_target = false
	enemy.is_attack_moving = false
	enemy.assigned_task_id = 0
	enemy.assigned_agent_id = 0
	world._update_faction_knowledge()
	var before := world.create_snapshot()
	var supply := (world.factions[1] as FactionState).supply
	var command := _command(world, card)
	_expect(world.submit_command(command).is_accepted(), "observation enters shared queue", failures)
	_expect(not world.submit_command(_command(world, card)).is_accepted(), "duplicate action in same tick refused", failures)
	_expect((world.factions[1] as FactionState).supply == supply, "queued action does not mutate before tick", failures)
	for index in range(35):
		world.advance_tick()
	var knowledge := world.faction_knowledge[1] as FactionKnowledge
	_expect(int(knowledge.identification_until_by_entity.get(enemy.entity_id, 0)) > world.current_tick, "stationary optical observation yields identified contact (tick=%d enemy=%s observer=%s visible=%s identified=%s)" % [world.current_tick, enemy.position, UnitCardSnapshot.new(card, world.units).center_position, knowledge.visible_hostile_unit_ids, knowledge.identification_until_by_entity], failures)
	_expect(before.knowledge.identification_until_by_entity.is_empty(), "old knowledge snapshot remains a value copy", failures)
	_expect(card.tactical_status_key == &"TACTICAL_ACTIVE", "observation becomes active after preparation", failures)
	_place(world, card, Vector2(2200, 3500))
	world.advance_tick()
	_expect(card.tactical_status_key == &"TACTICAL_MOVED", "movement interrupts observer at real cost", failures)
	_expect(card.tactical_ready_tick > world.current_tick, "interruption retains cooldown", failures)
	enemy.position = Vector2(6000, 100)
	world._update_faction_knowledge()
	_expect(not knowledge.identification_until_by_entity.has(enemy.entity_id), "lost visible contact immediately drops fire control identification", failures)
	_expect(TacticalCardAgent.new().propose(world.create_true_state_snapshot(), world.battle_definition).is_empty(), "agent refuses true-state input", failures)


func _test_observation_restart(failures: Array[String]) -> void:
	var world := sample_world()
	_quiet(world)
	var card := world.unit_cards[&"forward_observers"] as UnitCardState
	_place(world, card, Vector2(2400, 3500))
	world._create_scenario_formation(990, 2, &"assault_vehicle", 1, Vector2(2700, 3500), 9900, Vector2.RIGHT)
	world.tactical_ability_system.start(world, _command(world, card))
	var ready_tick := card.tactical_ready_tick
	var first_identified := false
	var knowledge := world.faction_knowledge[1] as FactionKnowledge
	for tick in range(1, ready_tick + 1):
		world.current_tick = tick
		world.tactical_ability_system.advance(world)
		world._update_faction_knowledge()
		first_identified = first_identified or knowledge.identification_until_by_entity.has(9900)
	_expect(first_identified, "first observation identifies the visible contact", failures)
	_expect(card.tactical_command == null and knowledge.identification_until_by_entity.is_empty(), "observation and fire-control lifetime expire naturally before reuse", failures)
	world.tactical_ability_system.start(world, _command(world, card))
	var identification_tick := card.tactical_complete_tick + TacticalAbilitySystem.IDENTIFICATION_TICKS
	var identified_early := false
	for tick in range(ready_tick + 1, identification_tick + 1):
		world.current_tick = tick
		world.tactical_ability_system.advance(world)
		world._update_faction_knowledge()
		if tick < identification_tick:
			identified_early = identified_early or knowledge.identification_until_by_entity.has(9900)
	_expect(not identified_early, "a new observation cannot reuse continuous-contact time from an expired action", failures)
	_expect(knowledge.identification_until_by_entity.has(9900), "second observation identifies only after its own complete contact window", failures)


func _test_weapon_constraints(failures: Array[String]) -> void:
	var units: Dictionary = {}
	var projectiles: Dictionary = {}
	var events: Array[SimulationEvent] = []
	var attacker := UnitState.new(1, Vector2.ZERO, 0.0, 1)
	attacker.attack_target_entity_id = 2
	attacker.attack_damage = 1.0
	attacker.attack_range = 600.0
	attacker.projectile_speed = 10000.0
	attacker.damage_tag = TacticalWeaponDefinition.DamageTag.SUPPRESSION
	attacker.suppression_power = 12.0
	attacker.ammunition_capacity = 1
	attacker.ammunition = 1
	attacker.identification_required = true
	attacker.minimum_attack_range = 100.0
	var target := UnitState.new(2, Vector2(300, 0), 0.0, 2)
	units[1] = attacker
	units[2] = target
	var system := CombatSystem.new()
	var next := system.advance(units, {}, projectiles, 1, events, 0)
	_expect(projectiles.is_empty() and attacker.ammunition == 1, "unidentified fire cannot consume ammunition or fire", failures)
	attacker.target_identified = true
	target.position = Vector2(50, 0)
	next = system.advance(units, {}, projectiles, next, events, 1)
	_expect(projectiles.is_empty(), "minimum-range counterplay prevents firing", failures)
	target.position = Vector2(300, 0)
	next = system.advance(units, {}, projectiles, next, events, 2)
	_expect(projectiles.size() == 1 and attacker.ammunition == 0, "identified professional shot spends exactly one round", failures)
	next = system.advance(units, {}, projectiles, next, events, 3)
	_expect(target.health == target.max_health and target.pending_suppression == 12.0, "suppression changes organization pressure without HP damage", failures)
	for tick in range(4, 25):
		next = system.advance(units, {}, projectiles, next, events, tick)
	_expect(projectiles.is_empty() and attacker.weapon_reason_key == &"TACTICAL_NO_AMMO", "empty specialist stops firing with reason", failures)


func _test_resupply_and_interruption(failures: Array[String]) -> void:
	var world := sample_world()
	_quiet(world)
	var supplier := world.unit_cards[&"ammunition_column"] as UnitCardState
	var battery := world.unit_cards[&"suppression_battery"] as UnitCardState
	_place(world, supplier, Vector2(2400, 3500))
	_place(world, battery, Vector2(2500, 3500))
	for id in battery.member_entity_ids:
		(world.units[id] as UnitState).ammunition = 0
	var before := world.create_snapshot().get_unit_card(battery.definition.definition_id)
	var command := _command(world, supplier)
	command.target_card_id = battery.definition.definition_id
	_expect(world.submit_command(command).is_accepted(), "safe nearby empty battery accepts supply action", failures)
	for index in range(35):
		world.advance_tick()
	var after := world.create_snapshot().get_unit_card(battery.definition.definition_id)
	_expect(after.ammunition == after.ammunition_capacity and after.ammunition > 0, "supply preparation restores finite ammunition", failures)
	_expect(before.ammunition == 0, "ammunition snapshot is a value copy", failures)
	supplier.tactical_ready_tick = 0
	var useless := _command(world, supplier)
	useless.target_card_id = battery.definition.definition_id
	_expect(world.submit_command(useless).reason == CommandValidationResult.Reason.RESUPPLY_NOT_NEEDED, "full battery cannot consume another supply action", failures)
	for id in battery.member_entity_ids:
		(world.units[id] as UnitState).ammunition = 0
	var interrupted := _command(world, supplier)
	interrupted.target_card_id = battery.definition.definition_id
	_expect(world.submit_command(interrupted).is_accepted(), "second empty battery can be resupplied after cooldown", failures)
	world.advance_tick()
	var supply_before := (world.factions[1] as FactionState).supply
	for id in supplier.member_entity_ids:
		(world.units[id] as UnitState).enabled = false
	world.advance_tick()
	_expect(supplier.tactical_command == null and supplier.tactical_status_key == &"REASON_CAPABILITY_LOST", "destroying supply vehicles interrupts preparation", failures)
	_expect((world.factions[1] as FactionState).supply == supply_before and world.create_snapshot().get_unit_card(battery.definition.definition_id).ammunition == 0, "failed supply neither refunds nor grants ammunition", failures)


func _test_engineering_breakthrough_and_control(failures: Array[String]) -> void:
	var world := sample_world()
	_quiet(world)
	var engineer := world.unit_cards[&"route_engineers"] as UnitCardState
	var route := world.battle_definition.engineering_routes[0]
	var center := world._engineering_route_center(route)
	_place(world, engineer, center + Vector2(0, 180))
	var command := _command(world, engineer)
	command.route_id = route.route_id
	var wall_cell := route.cleared_rects[0].position
	world.logic_grid.set_blocked(wall_cell, true)
	world._update_faction_knowledge()
	_expect(world.submit_command(command).is_accepted(), "engineer accepts a local publicly defined blocked route", failures)
	world.advance_tick()
	_expect(not world.opened_engineering_routes.has(route.route_id), "route does not open before preparation", failures)
	for index in range(32):
		world.advance_tick()
	_expect(world.opened_engineering_routes.has(route.route_id) and not world.logic_grid.is_blocked(wall_cell), "engineer preparation clears authoritative navigation cells", failures)
	var assault := world.unit_cards[&"combined_assault"] as UnitCardState
	_place(world, assault, Vector2(2400, 3500))
	assault.organization = 29.0
	var breach := _command(world, assault)
	breach.position = Vector2(2600, 3500)
	_expect(world.submit_command(breach).reason == CommandValidationResult.Reason.LOW_ORGANIZATION, "suppression below 30 forbids breakthrough", failures)
	assault.organization = 50.0
	_expect(world.submit_command(breach).is_accepted(), "organized assault starts breakthrough", failures)
	world.advance_tick()
	_expect(assault.tactical_complete_tick - assault.tactical_started_tick == 30, "organization below 60 doubles preparation", failures)
	var formation := world.formations[assault.formation_id] as FormationState
	var attempted_agent_move := FormationMoveCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.AGENT, world.current_tick, formation.leader_entity_id, formation.formation_id, Vector2(2600, 3500))
	attempted_agent_move.agent_id = assault.assigned_agent_id
	attempted_agent_move.task_id = assault.assigned_task_id
	_expect(not world.submit_command(attempted_agent_move).is_accepted(), "background movement cannot overwrite preparation", failures)
	for index in range(34):
		world.advance_tick()
	_expect(formation.order_kind == FormationState.OrderKind.ATTACK_MOVE and formation.order_destination.distance_to(breach.position) < 1.0, "breakthrough submits real attack movement", failures)
	var observer := world.unit_cards[&"forward_observers"] as UnitCardState
	_place(world, observer, Vector2(2200, 3500))
	_expect(world.submit_command(_command(world, observer)).is_accepted(), "observer preparation starts for takeover test", failures)
	world.advance_tick()
	var takeover := UnitCardControlCommand.new(world.allocate_command_id(), 1, world.current_tick, observer.definition.definition_id, UnitCardControlCommand.Action.TAKEOVER)
	_expect(world.submit_command(takeover).is_accepted(), "whole-card takeover uses existing pipeline", failures)
	world.advance_tick()
	_expect(observer.tactical_command == null, "takeover interrupts an outstanding card action", failures)
	var before := (world.factions[1] as FactionState).supply
	var illegal := _command(world, observer)
	illegal.issuer_kind = GameCommand.IssuerKind.AGENT
	illegal.agent_id = observer.assigned_agent_id
	_expect(not world.submit_command(illegal).is_accepted() and (world.factions[1] as FactionState).supply == before, "Agent cannot bypass player takeover or spend its supply", failures)


func _test_suppression_and_agent(failures: Array[String]) -> void:
	var world := sample_world()
	_quiet(world)
	var observer := world.unit_cards[&"forward_observers"] as UnitCardState
	var battery := world.unit_cards[&"suppression_battery"] as UnitCardState
	_place(world, observer, Vector2(2400, 3500))
	_place(world, battery, Vector2(2300, 3500))
	var enemy := _enemy(world)
	enemy.enabled = true
	enemy.can_attack = false
	enemy.position = Vector2(2730, 3500)
	enemy.has_move_target = false
	enemy.following_formation = false
	enemy.assigned_task_id = 0
	enemy.assigned_agent_id = 0
	var enemy_definition := UnitCardDefinition.new()
	enemy_definition.definition_id = &"fixture_opponent"
	enemy_definition.display_name_key = &"UNIT_CARD_IRONWALL"
	enemy_definition.unit_definition_id = enemy.definition_id
	enemy_definition.authorized_strength = 1
	var opponent := UnitCardState.new(enemy_definition, 2, [enemy.entity_id])
	opponent.organization_enabled = true
	opponent.organization = 100.0
	world.unit_cards[enemy_definition.definition_id] = opponent
	enemy.unit_card_id = enemy_definition.definition_id
	world.refresh_unit_card_organization_baseline(opponent)
	world._update_faction_knowledge()
	var suppress := _command(world, battery)
	suppress.target_entity_id = enemy.entity_id
	_expect(world.submit_command(suppress).reason == CommandValidationResult.Reason.TARGET_UNIDENTIFIED, "suppression action refuses an unobserved fire-control target", failures)
	world.submit_command(_command(world, observer))
	for index in range(34):
		world.advance_tick()
	suppress = _command(world, battery)
	suppress.target_entity_id = enemy.entity_id
	_expect(world.submit_command(suppress).is_accepted(), "same target becomes valid after optical identification", failures)
	var health_before := enemy.health
	for index in range(28):
		world.advance_tick()
	_expect(opponent.organization < 100.0 and enemy.health == health_before, "professional battery suppresses opposing card organization without killing it", failures)
	_expect(world.create_snapshot().get_unit_card(battery.definition.definition_id).ammunition < 24, "real battery uses its finite ammunition", failures)
	var snapshot := world.create_snapshot()
	var planned_before := TacticalCardAgent.new().propose(snapshot, world.battle_definition)
	var hidden := _enemy(world)
	hidden.position = Vector2(6500, 400)
	world._update_faction_knowledge()
	hidden.health = 1.0
	hidden.ammunition = 999
	var planned_after := TacticalCardAgent.new().propose(snapshot, world.battle_definition)
	_expect(planned_before.size() == planned_after.size(), "hidden truth mutation cannot change commands derived from the same legal value snapshot", failures)
	observer.tactical_command = null
	observer.tactical_ready_tick = 0
	observer.assigned_task_id = 990
	observer.assigned_agent_id = world.commanders[observer.commander_definition_id].agent_id
	observer.control_state = UnitCardState.ControlState.AGENT_ASSIGNED
	var task := TaskState.new(990, observer.assigned_agent_id, observer.member_entity_ids)
	task.faction_id = 1
	task.lifecycle = TaskState.Lifecycle.EXECUTING
	world.tasks[990] = task
	var agent_snapshot := world.create_snapshot()
	var proposals := TacticalCardAgent.new().propose(agent_snapshot, world.battle_definition)
	_expect(not proposals.is_empty(), "an assigned stationary Agent proposes a real card command", failures)
	if not proposals.is_empty():
		proposals[0].command_id = world.allocate_command_id()
		_expect(world.submit_command(proposals[0]).is_accepted(), "Agent proposal passes the same command validator", failures)
	world._create_scenario_formation(901, 2, &"assault_vehicle", 1, Vector2(6000, 400), 9000, Vector2.RIGHT)
	world._update_faction_knowledge()
	var legal_before := world.create_faction_snapshot(1)
	_expect(legal_before.get_unit(9000) == null, "pollution fixture must be outside all legal player knowledge", failures)
	var unseen := world.units[9000] as UnitState
	unseen.position = Vector2(6100, 500)
	unseen.health = 1.0
	unseen.ammunition = 999
	world._update_faction_knowledge()
	var legal_after := world.create_faction_snapshot(1)
	var before_commands := TacticalCardAgent.new().propose(legal_before, world.battle_definition)
	var after_commands := TacticalCardAgent.new().propose(legal_after, world.battle_definition)
	_expect(not before_commands.is_empty() and before_commands.size() == after_commands.size(), "fresh legal snapshots keep the same nonempty Agent proposals after hidden-state pollution", failures)
	for index in range(mini(before_commands.size(), after_commands.size())):
		var before_command := before_commands[index]
		var after_command := after_commands[index]
		_expect(before_command.unit_card_id == after_command.unit_card_id and before_command.position == after_command.position and before_command.target_entity_id == after_command.target_entity_id and before_command.target_card_id == after_command.target_card_id and before_command.route_id == after_command.route_id, "hidden movement, health and ammunition cannot alter tactical command contents", failures)


static func _quiet(world: SimulationWorld) -> void:
	world.agents.clear()
	world.tasks.clear()
	world.command_queue.drain()
	for value in world.unit_cards.values():
		var card := value as UnitCardState
		card.assigned_task_id = 0
	for value in world.units.values():
		var unit := value as UnitState
		unit.attack_target_entity_id = 0
		unit.has_move_target = false
		unit.assigned_task_id = 0
		if unit.faction_id != 1:
			unit.enabled = false


static func _place(world: SimulationWorld, card: UnitCardState, center: Vector2) -> void:
	var formation := world.formations[card.formation_id] as FormationState
	formation.anchor_position = center
	formation.target_position = center
	formation.order_destination = center
	formation.is_moving = false
	formation.path = PackedVector2Array()
	for index in range(card.member_entity_ids.size()):
		var unit := world.units[card.member_entity_ids[index]] as UnitState
		unit.position = center + Vector2(index * 4, 0)
		unit.desired_position = unit.position
		unit.move_target = unit.position
		unit.has_move_target = false
		unit.following_formation = false
		unit.assigned_task_id = 0


func _enemy(world: SimulationWorld) -> UnitState:
	for value in world.units.values():
		var unit := value as UnitState
		if unit.faction_id != 1:
			return unit
	return null


func _command(world: SimulationWorld, card: UnitCardState) -> TacticalAbilityCommand:
	return TacticalAbilityCommand.new(world.allocate_command_id(), card.faction_id, GameCommand.IssuerKind.PLAYER, world.current_tick, card.definition.definition_id)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("R3 tactical cards: " + message)
