class_name TestEnemyActionAudit
extends RefCounted

func run() -> Array[String]:
	var failures: Array[String] = []
	_test_delay(failures)
	_test_escort_delay(failures)
	_test_partial_intel(failures)
	_test_strategic_child(failures)
	_test_queue_and_projection(failures)
	return failures

func _test_delay(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true,false,SimulationWorld.ScenarioKind.GREY_RIDGE)
	var rule := world.enemy_reaction_rules[3] as EnemyReactionRuleState
	world.enemy_reaction_rules.assign([rule])
	world.enemy_reaction_committed_until_tick=0
	world.current_tick=1000
	world._is_advancing_tick=true
	var formation := world.formations[1] as FormationState
	var a := world.units[formation.member_entity_ids[0]] as UnitState
	var b := world.units[formation.member_entity_ids[1]] as UnitState
	var knowledge := world.faction_knowledge[2] as FactionKnowledge
	var position := world.strategic_regions[&"central_relay"].position as Vector2
	for unit in [a,b]:
		unit.position=position
		knowledge.hostile_contacts[unit.entity_id]=KnowledgeContact.from_unit(unit,world.current_tick)
	knowledge.reveal(world.logic_grid.world_to_cell(position),4)
	knowledge.visible_hostile_unit_ids=PackedInt32Array([a.entity_id])
	world._advance_grey_ridge_enemy_reactions()
	world.current_tick+=rule.delay_ticks-1
	knowledge.visible_hostile_unit_ids=PackedInt32Array([b.entity_id])
	world._advance_grey_ridge_enemy_reactions()
	var switched_tick := world.current_tick
	_check(rule.observed_tick == switched_tick and rule.fired_count == 0,"new target resets observation delay",failures)
	world.current_tick+=1
	(knowledge.hostile_contacts[b.entity_id] as KnowledgeContact).position+=Vector2(1,0)
	world._advance_grey_ridge_enemy_reactions()
	_check(rule.observed_tick == switched_tick,"moving same contact does not restart delay",failures)
	_check(rule.fired_count == 0,"old deadline cannot fire new target",failures)
	world.current_tick=switched_tick+rule.delay_ticks
	world._advance_grey_ridge_enemy_reactions()
	_check(rule.fired_count == 1,"new target fires after its full delay",failures)
	var audit := world.create_faction_snapshot(2).enemy_action_audit[-1]
	_check(audit.observed_tick == switched_tick and audit.required_delay_ticks == rule.delay_ticks and audit.target_entity_id == b.entity_id and audit.status == &"ACCEPTED" and audit.applied_tick == -1,"typed fact delay target and acceptance recorded",failures)
	_check(audit.committed_strength > 0 and audit.supply_cost == 0 and audit.committed_until_tick == world.current_tick+rule.commitment_ticks,"actual force and commitment costs recorded",failures)
	var old := audit.duplicate_value()
	world.advance_tick()
	_check((world.enemy_action_audit._by_command[old.command_id] as EnemyActionAuditRecord).applied_tick >= 0 and old.applied_tick == -1,"application distinct and old snapshot immutable",failures)
	knowledge.visible_hostile_unit_ids=PackedInt32Array()
	var observation_before := world._enemy_reaction_observation(rule,knowledge,world._enemy_formation_state(&"assault"))
	b.position+=Vector2(1000,0)
	(world.factions[1] as FactionState).supply=0
	(world.buildings[SimulationWorld.PLAYER_COMMAND_CENTER_ID] as BuildingState).position+=Vector2(700,0)
	var observation_after := world._enemy_reaction_observation(rule,knowledge,world._enemy_formation_state(&"assault"))
	_check(observation_before == observation_after and not observation_after.active,"hidden unit economy HQ and stale contact cannot arm reaction",failures)

func _test_queue_and_projection(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true,false,SimulationWorld.ScenarioKind.GREY_RIDGE)
	var formation := world._enemy_formation_state(&"assault")
	var first := FormationMoveCommand.new(world.allocate_command_id(),2,GameCommand.IssuerKind.AGENT,0,formation.leader_entity_id,formation.formation_id,formation.anchor_position+Vector2(0,128))
	var second := FormationMoveCommand.new(world.allocate_command_id(),2,GameCommand.IssuerKind.AGENT,0,formation.leader_entity_id,formation.formation_id,formation.anchor_position)
	first.agent_id=world.battle_definition.enemy_agent_id
	second.agent_id=world.battle_definition.enemy_agent_id
	first.task_id=world.battle_definition.enemy_task_id
	second.task_id=world.battle_definition.enemy_task_id
	_check(world.submit_command(first).is_accepted() and world.submit_command(second).is_accepted(),"queue test accepted",failures)
	world.advance_tick()
	var cancelled := world.enemy_action_audit._by_command[first.command_id] as EnemyActionAuditRecord
	var arrived := world.enemy_action_audit._by_command[second.command_id] as EnemyActionAuditRecord
	_check(cancelled.command_id == first.command_id and cancelled.status == &"NOT_APPLIED" and cancelled.applied_tick == -1,"superseded queue command never claimed applied",failures)
	_check(arrived.command_id == second.command_id and arrived.status == &"AREA_REACHED" and arrived.applied_tick == 0,"ordinary movement completion observed",failures)
	_check(world.create_snapshot().enemy_action_audit.is_empty() and world.create_snapshot().enemy_observed_actions.is_empty(),"player cannot read hidden audit or maneuver",failures)
	var player := world.units[(world.formations[1] as FormationState).leader_entity_id] as UnitState
	var enemy := world.units[formation.leader_entity_id] as UnitState
	enemy.position=player.position+Vector2(100,0)
	world._update_faction_knowledge()
	world.enemy_action_audit.advance(world)
	var snapshot := world.create_snapshot()
	_check(not snapshot.enemy_observed_actions.is_empty(),"visible enemy creates independent public evidence",failures)
	var report := GameplayObservabilityReport.new()
	report.start(snapshot)
	report.observe(snapshot)
	var review := AfterActionReviewProjector.new().project(report.create_report(),1)
	_check(review != null and not review.enemy_observed_actions.is_empty(),"legal observation reaches after-action projection",failures)
	if review == null or review.enemy_observed_actions.is_empty(): return
	var copied := review.duplicate_review()
	review.enemy_observed_actions[0].visible_strength=999
	_check(copied.enemy_observed_actions[0].visible_strength != 999,"review observation is a value copy",failures)
	var previous := JSON.stringify(copied.enemy_observed_actions[0].to_dictionary())
	world.events.append(SimulationEvent.new(world.current_tick,SimulationEvent.Kind.PROJECTILE_FIRED,enemy.entity_id,"audit fixture"))
	world.enemy_action_audit.advance(world)
	_check(world.create_snapshot().enemy_observed_actions[-1].action == &"ENGAGING","visible actual shot supports firing observation",failures)
	enemy.position=Vector2(5000,300)
	world.current_tick+=100
	world._update_faction_knowledge()
	world.enemy_action_audit.advance(world)
	_check(JSON.stringify(world.create_snapshot().enemy_observed_actions[0].to_dictionary()) == previous,"hidden activity cannot update last seen outcome",failures)
	var public_text := JSON.stringify(copied.to_dictionary())
	_check(not public_text.contains("rule_id") and not public_text.contains("required_delay_ticks") and not public_text.contains("committed_strength"),"public review excludes internal rules timing and hidden strength",failures)

func _check(value: bool, label: String, failures: Array[String]) -> void:
	if not value: failures.append("Enemy audit: "+label)

func _test_escort_delay(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true,false,SimulationWorld.ScenarioKind.FOG_FOREST)
	world._is_advancing_tick=true
	world.current_tick=1000
	var formation := world.formations[1] as FormationState
	var knowledge := world.faction_knowledge[2] as FactionKnowledge
	var ids: Array[int] = []
	for index in range(2):
		var unit := world.units[formation.member_entity_ids[index]] as UnitState
		ids.append(unit.entity_id)
		var contact := KnowledgeContact.from_unit(unit,world.current_tick)
		contact.definition_id=&"supply_truck"
		knowledge.hostile_contacts[unit.entity_id]=contact
		knowledge.reveal(world.logic_grid.world_to_cell(unit.position),3)
	knowledge.visible_hostile_unit_ids=PackedInt32Array([ids[0]])
	world._advance_escort_interception()
	world.current_tick+=world.battle_definition.escort_intercept_delay_ticks-1
	knowledge.visible_hostile_unit_ids=PackedInt32Array([ids[1]])
	world._advance_escort_interception()
	var switched := world.current_tick
	_check(world.enemy_escort_observed_tick == switched,"escort target switch resets delay",failures)
	world.current_tick+=1
	world._advance_escort_interception()
	_check(world.enemy_escort_intercept_target_id == 0,"escort old deadline cannot intercept replacement",failures)
	world.current_tick=switched+world.battle_definition.escort_intercept_delay_ticks
	world._advance_escort_interception()
	_check(world.enemy_escort_intercept_target_id == ids[1],"escort new contact eventually receives actual order",failures)
	var audit := world.enemy_action_audit.records_for(2)[-1]
	_check(audit.rule_id == &"escort_intercept" and audit.observed_tick == switched,"escort audit preserves original observation tick",failures)

func _test_partial_intel(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true,false,SimulationWorld.ScenarioKind.GREY_RIDGE)
	var formation := world._enemy_formation_state(&"assault")
	var enemy := world.units[formation.leader_entity_id] as UnitState
	var player := world.units[1] as UnitState
	for id in formation.member_entity_ids:
		(world.units[id] as UnitState).position=Vector2(5500,200)
	enemy.position=player.position+Vector2(100,0)
	world._update_faction_knowledge()
	world.current_tick=1000
	# Isolate the new report from the separately tested historical estimate merger.
	world.intel_reports.clear()
	var rule := world.enemy_reaction_rules[3] as EnemyReactionRuleState
	rule.observed_tick=world.current_tick-rule.delay_ticks
	world._commit_enemy_reaction(rule,{"target_entity_id":player.entity_id,"target_position":player.position,"region_id":&"central_relay","reason":"visible_contact=1"},formation)
	var reports := world.create_snapshot().intel_reports
	var matched := false
	for report in reports:
		if report.target_category_key != &"INTEL_ENEMY_MANEUVER": continue
		matched=true
		_check(report.estimated_min == 1 and report.estimated_max == 1,"visible maneuver intel cannot disclose hidden formation strength",failures)
	_check(matched,"visible reaction produces legal maneuver report",failures)

func _test_strategic_child(failures: Array[String]) -> void:
	var world := SimulationWorld.new(true,false,SimulationWorld.ScenarioKind.GREY_RIDGE)
	var formation := world._enemy_formation_state(&"probe")
	var command := StrategicOrderCommand.new(world.allocate_command_id(),2,0,StrategicOrderCommand.OrderKind.SCOUT_AREA,formation.formation_id,0,formation.anchor_position+Vector2(256,0),64,GameCommand.IssuerKind.AGENT)
	command.agent_id=world.battle_definition.enemy_agent_id
	_check(world.submit_command(command).is_accepted(),"strategic audit fixture accepted",failures)
	world.advance_tick()
	var record := world.enemy_action_audit._by_command[command.command_id] as EnemyActionAuditRecord
	world.advance_tick()
	_check(record.status != &"SUPERSEDED" and record.task_id > 0 and world.tasks.has(record.task_id),"own task child order does not supersede its parent strategy",failures)
	var task := world.tasks[record.task_id] as TaskState
	task.set_lifecycle(TaskState.Lifecycle.COMPLETED,world.current_tick)
	world.enemy_action_audit.advance(world)
	_check(record.status == &"TASK_COMPLETED","strategic outcome follows real task lifecycle",failures)
