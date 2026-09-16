class_name TestGreyRidgeTacticalContent
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	var catalog := load(BattleContentLoader.DEFAULT_CATALOG_PATH) as BattleContentCatalog
	if catalog == null:
		failures.append("Grey Ridge tactical migration: battle catalog could not be loaded")
		return failures
	var validation := catalog.validate(SimulationWorld.UNIT_CATALOG)
	if not validation.is_valid():
		for issue in validation.issues:
			failures.append("Grey Ridge tactical migration: " + str(issue))
		return failures
	_test_weapon_binding(failures)
	_test_enemy_card_contract(failures)
	_test_cross_battle_identity(failures)
	_test_formal_observation_and_suppression(failures)
	_test_formal_engineering_and_breakthrough(failures)
	_test_formal_resupply(failures)
	_test_formal_same_tick_costs(failures)
	_test_effective_suppression_cap(failures)
	_test_migrated_doctrine_parameters(failures)
	return failures


func _formal_world(starting_cards: Array[StringName]) -> SimulationWorld:
	var battle := load("res://data/battles/grey_ridge.tres") as BattleDefinition
	var plan := battle.create_default_army_plan()
	plan.starting_unit_card_ids.assign(starting_cards)
	var world := SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, &"central_pressure", plan)
	TestTacticalCards._quiet(world)
	for value in world.unit_cards.values():
		var card := value as UnitCardState
		if card.faction_id == 1 and starting_cards.has(card.definition.definition_id):
			card.deployment_state = UnitCardState.DeploymentState.DEPLOYED
			card.control_state = UnitCardState.ControlState.AGENT_ASSIGNED
			card.organization_enabled = true
			card.organization = 100.0
			world.refresh_unit_card_organization_baseline(card)
	for value in world.units.values():
		var unit := value as UnitState
		unit.can_attack = false
	return world


func _command(world: SimulationWorld, id: StringName) -> TacticalAbilityCommand:
	return TacticalAbilityCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, id)


func _advance(world: SimulationWorld, ticks: int) -> void:
	for index in range(ticks):
		world.advance_tick()


func _test_formal_observation_and_suppression(failures: Array[String]) -> void:
	var world := _formal_world([&"falcon_recon_group", &"thunder_fire_group"])
	var observer := world.unit_cards[&"falcon_recon_group"] as UnitCardState
	var battery := world.unit_cards[&"thunder_fire_group"] as UnitCardState
	var opponent := world.unit_cards[&"grey_ridge_enemy_assault"] as UnitCardState
	TestTacticalCards._place(world, observer, Vector2(2400, 3500))
	TestTacticalCards._place(world, battery, Vector2(2400, 3420))
	TestTacticalCards._place(world, opponent, Vector2(2730, 3500))
	for id in opponent.member_entity_ids:
		var hostile := world.units[id] as UnitState
		hostile.enabled = true
		hostile.is_visible_to_local_player = true
	world.refresh_unit_card_organization_baseline(opponent)
	for id in battery.member_entity_ids:
		(world.units[id] as UnitState).can_attack = true
	world._update_faction_knowledge()
	var target := world.units[opponent.member_entity_ids[0]] as UnitState
	var suppress := _command(world, battery.definition.definition_id)
	suppress.target_entity_id = target.entity_id
	var initial_result := world.submit_command(suppress)
	_expect(initial_result.reason in [CommandValidationResult.Reason.TARGET_UNIDENTIFIED, CommandValidationResult.Reason.HIDDEN_TARGET], "formal battery requires optical identification (%s)" % initial_result.describe(), failures)
	_expect(world.submit_command(_command(world, observer.definition.definition_id)).is_accepted(), "formal observer uses normal command queue", failures)
	_advance(world, 34)
	var decisions := TacticalActionProjector.new().project(world.create_snapshot(), world.battle_definition)
	var found := false
	for decision in decisions:
		if decision.unit_card_id == battery.definition.definition_id and decision.target_entity_id == target.entity_id:
			found = true
			_expect(decision.reason == CommandValidationResult.Reason.NONE, "formal suppression decision is available after identification", failures)
	_expect(found, "formal decision panel exposes identified enemy formation", failures)
	suppress = _command(world, battery.definition.definition_id)
	suppress.target_entity_id = target.entity_id
	_expect(world.submit_command(suppress).is_accepted(), "formal identified battery accepts fire order", failures)
	var health_before := target.health
	_advance(world, 35)
	_expect(opponent.organization < 100.0 and target.health == health_before, "formal suppression reduces hostile organization without HP damage", failures)
	_expect(world.create_snapshot().get_unit_card(battery.definition.definition_id).ammunition < 24, "formal weapon override spends finite ammunition", failures)
	_expect(world.create_snapshot().get_unit_card(opponent.definition.definition_id) == null, "formal hostile organization remains hidden", failures)
	var contributions := _contributions(world)
	_expect(contributions[observer.definition.definition_id].contacts_identified > 0, "formal optical identification reaches after-action contribution", failures)
	_expect(contributions[battery.definition.definition_id].suppression_applied > 0 and contributions[battery.definition.definition_id].damage_dealt == 0, "formal effective suppression reaches after-action without HP damage", failures)
	opponent.organization = 0.0
	world.tactical_ability_system.prepare_weapons(world)
	_expect(target.organization_attack_restricted, "broken formal hostile card cannot proactively attack", failures)
	var attack := AttackMoveCommand.new(world.allocate_command_id(), 2, GameCommand.IssuerKind.PLAYER, world.current_tick, target.entity_id, opponent.formation_id, Vector2(2800, 3500))
	var attack_result := world.validate_command(attack)
	_expect(attack_result.reason == CommandValidationResult.Reason.INVALID_DEFINITION, "hostile card cannot be issued through player definition pipeline", failures)
	world.current_tick += world.battle_definition.organization_recovery_delay_ticks
	for id in opponent.member_entity_ids:
		(world.units[id] as UnitState).pending_suppression = 0.0
	world._advance_unit_card_organization()
	world.tactical_ability_system.prepare_weapons(world)
	_expect(opponent.organization > 0.0 and not target.organization_attack_restricted, "formal opponent recovers and regains proactive fire", failures)


func _test_formal_engineering_and_breakthrough(failures: Array[String]) -> void:
	var world := _formal_world([&"bridge_engineer_group", &"armored_spearhead"])
	var engineer := world.unit_cards[&"bridge_engineer_group"] as UnitCardState
	var assault := world.unit_cards[&"armored_spearhead"] as UnitCardState
	var route := world.battle_definition.engineering_routes[0]
	TestTacticalCards._place(world, engineer, world._engineering_route_center(route) + Vector2(0, 180))
	var start := world.logic_grid.cell_to_world(Vector2i(146, 58))
	var finish := world.logic_grid.cell_to_world(Vector2i(146, 66))
	var before := world.pathfinder.find_path(start, finish)
	var revision := world.logic_grid.revision
	_expect(world.logic_grid.is_blocked(Vector2i(145, 62)), "formal route crosses an existing blocked obstacle", failures)
	var command := _command(world, engineer.definition.definition_id)
	command.route_id = route.route_id
	_expect(world.submit_command(command).is_accepted(), "formal engineer accepts local clearance", failures)
	_advance(world, 33)
	var after := world.pathfinder.find_path(start, finish)
	_expect(world.opened_engineering_routes.has(route.route_id) and world.logic_grid.revision > revision, "formal route opens and invalidates navigation", failures)
	_expect(not after.is_empty() and _path_length(after) < _path_length(before), "formal route shortens the real blocked detour without synthetic obstacles", failures)
	_expect(not world.logic_grid.is_blocked(Vector2i(145, 62)), "formal cleared cells are traversable", failures)
	TestTacticalCards._place(world, assault, Vector2(2400, 3500))
	for id in assault.member_entity_ids:
		(world.units[id] as UnitState).can_attack = true
	var breakthrough := _command(world, assault.definition.definition_id)
	breakthrough.position = Vector2(2600, 3500)
	_expect(world.submit_command(breakthrough).is_accepted(), "formal armored card accepts breakthrough", failures)
	_advance(world, 18)
	var formation := world.formations[assault.formation_id] as FormationState
	_expect(formation.order_kind == FormationState.OrderKind.ATTACK_MOVE or assault.tactical_status_key != &"TACTICAL_PREPARING", "formal breakthrough resolves through tactical pipeline (status=%s)" % assault.tactical_status_key, failures)
	_expect(assault.organization < 100.0, "formal breakthrough pays organization cost", failures)
	var contributions := _contributions(world)
	_expect(contributions[engineer.definition.definition_id].routes_opened == 1, "formal opened route reaches after-action", failures)
	_expect(contributions[assault.definition.definition_id].tactical_completed == 1, "formal breakthrough reaches after-action (status=%s started=%d interrupted=%d)" % [assault.tactical_status_key, contributions[assault.definition.definition_id].tactical_started, contributions[assault.definition.definition_id].tactical_interrupted], failures)


func _test_formal_resupply(failures: Array[String]) -> void:
	var world := _formal_world([&"frontline_logistics_column", &"thunder_fire_group"])
	var supplier := world.unit_cards[&"frontline_logistics_column"] as UnitCardState
	var battery := world.unit_cards[&"thunder_fire_group"] as UnitCardState
	TestTacticalCards._place(world, supplier, Vector2(2400, 3500))
	TestTacticalCards._place(world, battery, Vector2(2500, 3500))
	for id in battery.member_entity_ids:
		(world.units[id] as UnitState).ammunition = 0
	battery.organization = 70.0
	var before := world.create_snapshot().get_unit_card(battery.definition.definition_id)
	var command := _command(world, supplier.definition.definition_id)
	command.target_card_id = battery.definition.definition_id
	_expect(world.submit_command(command).is_accepted(), "formal logistics accepts safe resupply", failures)
	_advance(world, 33)
	var after := world.create_snapshot().get_unit_card(battery.definition.definition_id)
	_expect(after.ammunition == 24 and after.organization >= 90.0, "formal logistics restores actual magazine and organization", failures)
	_expect(before.ammunition == 0 and before.organization == 70.0, "formal resupply preserves old snapshot values", failures)
	var contribution: AfterActionCardContribution = _contributions(world)[supplier.definition.definition_id]
	_expect(contribution.ammunition_restored == 24 and contribution.organization_restored > 0 and contribution.organization_restored <= 20, "formal resupply reports actual rounds and capped organization restoration", failures)
	_expect(contribution.supply_spent == supplier.definition.tactical_ability.supply_cost, "formal tactical cost is independently attributed to the supplier", failures)
	world._bind_unit_card_members(battery)
	_expect(world.create_snapshot().get_unit_card(battery.definition.definition_id).ammunition == 24, "formal magazine binding remains stable after resupply", failures)


func _test_formal_same_tick_costs(failures: Array[String]) -> void:
	var world := _formal_world([&"falcon_recon_group", &"ironwall_assault_group"])
	var observer := world.unit_cards[&"falcon_recon_group"] as UnitCardState
	var assault := world.unit_cards[&"ironwall_assault_group"] as UnitCardState
	(world.units[assault.member_entity_ids.back()] as UnitState).enabled = false
	world._refresh_battle_population()
	var faction := world.factions[1] as FactionState
	faction.supply = 100
	var reinforcement := SupportOrderCommand.new(world.allocate_command_id(), 1, GameCommand.IssuerKind.PLAYER, world.current_tick, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"", &"", assault.definition.definition_id)
	_expect(world.submit_command(reinforcement).is_accepted(), "same-tick fixture accepts normal reinforcement", failures)
	_expect(world.submit_command(_command(world, observer.definition.definition_id)).is_accepted(), "same-tick fixture accepts normal observation", failures)
	world.advance_tick()
	var contributions := _contributions(world)
	_expect(contributions[assault.definition.definition_id].supply_spent == world.get_support_cost(SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT), "actual reinforcement cost is attributed only to its card", failures)
	_expect(contributions[observer.definition.definition_id].supply_spent == observer.definition.tactical_ability.supply_cost, "actual same-tick observation keeps its own cost source", failures)


func _test_effective_suppression_cap(failures: Array[String]) -> void:
	var world := _formal_world([&"falcon_recon_group", &"thunder_fire_group"])
	var battery := world.unit_cards[&"thunder_fire_group"] as UnitCardState
	var target_card := world.unit_cards[&"grey_ridge_enemy_assault"] as UnitCardState
	var target := world.units[target_card.member_entity_ids[0]] as UnitState
	target.enabled = true
	target_card.organization = 5.0
	world.refresh_unit_card_organization_baseline(target_card)
	var first := SimulationEvent.new(world.current_tick, SimulationEvent.Kind.SUPPRESSION_APPLIED, battery.member_entity_ids[0])
	var second := SimulationEvent.new(world.current_tick, SimulationEvent.Kind.SUPPRESSION_APPLIED, battery.member_entity_ids[1])
	first.applied_amount = 4.0
	second.applied_amount = 4.0
	target.pending_suppression = 8.0
	target.pending_suppression_events.assign([first, second])
	world.events.append_array([first, second])
	world._advance_unit_card_organization()
	_expect(target_card.organization == 0 and first.applied_amount == 4 and second.applied_amount == 1, "same-tick pressure must cap at actual remaining organization in stable order", failures)
	var measured: AfterActionCardContribution = _contributions(world)[battery.definition.definition_id]
	_expect(measured.suppression_applied == 5 and measured.damage_dealt == 0, "saturated suppression must report exactly the effective organization loss", failures)
	world._advance_unit_card_organization()
	_expect(first.applied_amount == 4 and second.applied_amount == 1 and target.pending_suppression_events.is_empty(), "later ticks cannot rewrite published impact amounts or retain pending events", failures)
	var ineffective := SimulationEvent.new(world.current_tick, SimulationEvent.Kind.SUPPRESSION_APPLIED, battery.member_entity_ids[0])
	ineffective.applied_amount = 9.0
	target_card.organization_enabled = false
	target.pending_suppression_events.append(ineffective)
	world._advance_unit_card_organization()
	_expect(ineffective.applied_amount == 0 and target.pending_suppression_events.is_empty(), "non-organized targets cannot contribute effective suppression", failures)


func _test_migrated_doctrine_parameters(failures: Array[String]) -> void:
	for doctrine_id in [&"fire_preparation", &"covert_search", &"concentrated_breakthrough"]:
		var original := _doctrine_probe(doctrine_id, false, false, false, failures)
		var renamed := _doctrine_probe(doctrine_id, true, false, false, failures)
		var changed := _doctrine_probe(doctrine_id, true, true, false, failures)
		var hidden := _doctrine_probe(doctrine_id, true, false, true, failures)
		_expect(not original.is_empty() and original == renamed, "%s must retain task behavior after renaming" % doctrine_id, failures)
		_expect(renamed != changed, "%s typed parameters must change authoritative task behavior" % doctrine_id, failures)
		_expect(hidden == renamed, "%s task behavior must ignore hidden enemy changes" % doctrine_id, failures)


func _doctrine_probe(id: StringName, rename: bool, change_parameters: bool, pollute_hidden: bool, failures: Array[String]) -> Dictionary:
	var card_id: StringName = &"thunder_fire_group" if id == &"fire_preparation" else (&"falcon_recon_group" if id == &"covert_search" else &"ironwall_assault_group")
	var world := _formal_world([card_id, &"armored_spearhead" if card_id == &"ironwall_assault_group" else &"ironwall_assault_group"])
	var card := world.unit_cards[card_id] as UnitCardState
	var commander := world.commanders[card.commander_definition_id] as CommanderState
	var doctrine := (load("res://data/army/%s.tres" % id) as DoctrineDefinition).duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as DoctrineDefinition
	if rename:
		doctrine.definition_id = StringName("renamed_%s" % id)
	if change_parameters:
		if id == &"fire_preparation":
			doctrine.effects[0].timing.base_delay_ticks += 7
		else:
			doctrine.effects[0].effect.task_radius += 24.0
			if id == &"covert_search":
				doctrine.effects[0].effect.staging_fraction = 0.25
			else:
				doctrine.effects[0].effect.formation_spacing += 30.0
	world.doctrine_definitions[doctrine.definition_id] = doctrine
	commander.available_doctrine_ids = commander.available_doctrine_ids.duplicate()
	if not commander.available_doctrine_ids.has(doctrine.definition_id):
		commander.available_doctrine_ids.append(doctrine.definition_id)
	if pollute_hidden:
		for unit in world.units.values():
			if unit.faction_id != 1:
				unit.position = Vector2(5900, 100)
				unit.health = 1
		world._update_faction_knowledge()
	var equip := EquipDoctrineCommand.new(world.allocate_command_id(), 1, world.current_tick, commander.definition.definition_id, doctrine.definition_id)
	_expect(world.submit_command(equip).is_accepted(), "renamed doctrine must equip through shared command validation", failures)
	world.advance_tick()
	var command := CommanderOrderCommand.new(world.allocate_command_id(), 1, world.current_tick, commander.definition.definition_id, CommanderOrderCommand.OrderKind.ASSIGN_OBJECTIVE, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, &"central_relay")
	var order_result := world.submit_command(command)
	_expect(order_result.is_accepted(), "doctrine probe %s must issue a normal commander order (%s)" % [id, order_result.describe()], failures)
	world.advance_tick()
	var task := world.tasks.get(card.assigned_task_id) as TaskState
	_expect(task != null and task.doctrine_effect != null, "migrated doctrine must attach its effect to the authoritative task", failures)
	if task == null or task.doctrine_effect == null:
		return {}
	return {"activation": task.activation_tick, "radius": task.target_radius, "target": task.target_position, "final": task.final_target_position, "staged": task.has_staged_target, "contact": task.requires_observed_contact, "kind": task.doctrine_effect.action_kind, "reason": task.doctrine_effect.waiting_reason_key}


func _contributions(world: SimulationWorld) -> Dictionary:
	var report := GameplayObservabilityReport.new()
	var snapshot := world.create_faction_snapshot(1)
	report.start(snapshot)
	report.observe(snapshot, world.events)
	var review := AfterActionReviewProjector.new().project(report.create_report(), 1)
	var result: Dictionary = {}
	for entry in review.card_contributions:
		result[entry.unit_card_id] = entry
	return result


func _path_length(path: PackedVector2Array) -> float:
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return length


func _test_weapon_binding(failures: Array[String]) -> void:
	var world := TestTacticalCards.sample_world()
	var card := world.unit_cards[&"suppression_battery"] as UnitCardState
	card.definition = card.definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as UnitCardDefinition
	card.definition.tactical_weapon_override = (load("res://data/units/suppression_vehicle.tres") as UnitDefinition).tactical_weapon
	var member := world.units[card.member_entity_ids[0]] as UnitState
	member.ammunition = 0
	world._bind_unit_card_members(card)
	_expect(member.ammunition == 4, "newly bound weapon receives its initial magazine", failures)
	member.ammunition = 1
	world._bind_unit_card_members(card)
	world.apply_unit_card_persistent_modifiers(card)
	_expect(member.ammunition == 1, "rebinding and growth refresh cannot refill an existing magazine", failures)
	card.organization = 0.0
	world.tactical_ability_system.prepare_weapons(world)
	_expect(member.organization_attack_restricted and member.attack_target_entity_id == 0, "zero organization forbids proactive targeting", failures)
	card.organization = 50.0
	world.tactical_ability_system.prepare_weapons(world)
	_expect(not member.organization_attack_restricted, "organization recovery removes the fire restriction", failures)


func _test_enemy_card_contract(failures: Array[String]) -> void:
	var world := SimulationWorld.new(false, false, SimulationWorld.ScenarioKind.BLACK_WELL)
	world.battle_definition = world.battle_definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as BattleDefinition
	var formation := world.battle_definition.enemy_formations[0]
	var definition := UnitCardDefinition.new()
	definition.definition_id = &"test_hostile_formation"
	definition.display_name_key = &"UNIT_CARD_IRONWALL"
	definition.unit_definition_id = formation.unit_definition_id
	definition.authorized_strength = formation.strength
	definition.role_key = &"UNIT_CARD_ROLE_ASSAULT"
	definition.enforce_organization_rules = true
	formation.unit_card_definition = definition
	_expect(world.battle_definition.validate(SimulationWorld.UNIT_CATALOG).is_valid(), "explicit hostile formation card validates", failures)
	world._setup_grey_ridge_scenario()
	world._update_faction_knowledge()
	var card := world.unit_cards[definition.definition_id] as UnitCardState
	_expect(card.faction_id == formation.faction_id and card.formation_id == formation.formation_id and card.uses_tactical_organization(), "hostile formation receives its own authoritative organization card", failures)
	_expect(world.create_faction_snapshot(1).get_unit_card(definition.definition_id) == null, "opponent card organization is absent from player knowledge", failures)
	_expect(world.create_faction_snapshot(2).get_unit_card(definition.definition_id) != null, "opponent may observe its own organization card", failures)
	definition.authorized_strength += 1
	_expect(not world.battle_definition.validate(SimulationWorld.UNIT_CATALOG).is_valid(), "enemy card strength mismatch is rejected before setup", failures)


func _test_cross_battle_identity(failures: Array[String]) -> void:
	var catalog := (load(BattleContentLoader.DEFAULT_CATALOG_PATH) as BattleContentCatalog).duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as BattleContentCatalog
	_expect(catalog.validate(SimulationWorld.UNIT_CATALOG).is_valid(), "current shared card identities remain compatible", failures)
	var battle := catalog.battles[0]
	var original := battle.unit_card_definitions[0]
	var variant := original.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as UnitCardDefinition
	variant.authorized_strength += 1
	variant.composition.clear()
	battle.unit_card_definitions[0] = variant
	var result := catalog.validate(SimulationWorld.UNIT_CATALOG)
	var found := false
	for issue in result.issues:
		found = found or str(issue).contains("persistent composition")
	_expect(found, "a same-ID card cannot silently acquire a different cross-battle composition", failures)


func _expect(condition: bool, detail: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("Grey Ridge tactical migration: " + detail)
