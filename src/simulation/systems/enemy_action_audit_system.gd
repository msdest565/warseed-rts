class_name EnemyActionAuditSystem
extends RefCounted

var _records: Array[EnemyActionAuditRecord] = []
var _by_command: Dictionary = {}
var _active_by_formation: Dictionary = {}
var _observed: Array[EnemyObservedAction] = []
var _last_observed: Dictionary = {}
var _visible_positions: Dictionary = {}
var _visible_members: Dictionary = {}
var _event_cursor: int = 0

func accepted(world: SimulationWorld, command: GameCommand) -> void:
	if world.battle_definition == null or command.issuer_id != 2 or _by_command.has(command.command_id): return
	if not (command is FormationMoveCommand or command is AttackCommand or command is StrategicOrderCommand or command is StopCommand): return
	var formation_id := 0
	if command is FormationMoveCommand or command is AttackCommand or command is StrategicOrderCommand or command is StopCommand: formation_id=command.formation_id
	var formation := world.formations.get(formation_id) as FormationState
	if formation == null: return
	var record := EnemyActionAuditRecord.new()
	record.command_id=command.command_id
	record.formation_id=formation_id
	record.task_id=command.task_id
	record.accepted_tick=world.current_tick
	record.changed_tick=world.current_tick
	record.observed_tick=world.current_tick
	record.rule_id=&"agent_task_execution"
	record.fact_source=&"LEGAL_AGENT_TASK"
	record.fact_detail="task=%d;own_formation=%d" % [command.task_id,formation_id]
	record.committed_until_tick=world.enemy_reaction_committed_until_tick
	for id in formation.member_entity_ids:
		var unit := world.units.get(id) as UnitState
		if unit != null and unit.enabled: record.committed_strength+=1
	if command is AttackCommand:
		record.command_kind=&"ATTACK"
		record.target_entity_id=command.attack_target_entity_id
		var knowledge := world.faction_knowledge.get(2) as FactionKnowledge
		var contact := knowledge.hostile_contacts.get(record.target_entity_id) as KnowledgeContact if knowledge != null else null
		if contact != null: record.target_position=contact.position
	elif command is StrategicOrderCommand:
		record.command_kind=&"STRATEGIC"
		record.target_entity_id=command.objective_entity_id
		record.target_position=command.target_position
	elif command is StopCommand:
		record.command_kind=&"STOP"
		record.target_position=formation.anchor_position
	else:
		record.command_kind=&"MOVE"
		record.target_position=command.target_position
	_records.append(record)
	_by_command[record.command_id]=record

func annotate(world: SimulationWorld, command: GameCommand, rule_id: StringName, source: StringName, fact: String, observed_tick: int, delay: int, commitment: int) -> void:
	accepted(world,command)
	var record := _by_command.get(command.command_id) as EnemyActionAuditRecord
	if record == null: return
	record.rule_id=rule_id
	record.fact_source=source
	record.fact_detail=fact
	record.observed_tick=observed_tick
	record.required_delay_ticks=delay
	record.committed_until_tick=commitment

func bind_task(command_id: int, task_id: int) -> void:
	var record := _by_command.get(command_id) as EnemyActionAuditRecord
	if record != null: record.task_id=task_id

func applied(world: SimulationWorld, command: GameCommand) -> void:
	var record := _by_command.get(command.command_id) as EnemyActionAuditRecord
	if record == null or record.status != &"ACCEPTED": return
	var formation := world.formations.get(record.formation_id) as FormationState
	var matches := formation != null
	if matches and record.command_kind == &"ATTACK": matches=formation.order_target_entity_id == record.target_entity_id
	if matches and record.command_kind == &"STOP": matches=not formation.is_moving and formation.order_target_entity_id == 0
	if matches and record.command_kind == &"MOVE": matches=formation.order_destination.is_equal_approx(record.target_position)
	if matches and record.command_kind == &"STRATEGIC":
		var task := world.tasks.get(record.task_id) as TaskState
		matches=task != null and task.target_position.is_equal_approx(record.target_position)
	if not matches:
		_change(record,&"NOT_APPLIED",world.current_tick)
		return
	var previous := _active_by_formation.get(record.formation_id) as EnemyActionAuditRecord
	if previous != null and previous.status == &"APPLIED" and not (previous.command_kind == &"STRATEGIC" and previous.task_id == record.task_id): _change(previous,&"SUPERSEDED",world.current_tick)
	record.applied_tick=world.current_tick
	_change(record,&"APPLIED",world.current_tick)
	_active_by_formation[record.formation_id]=record

func advance(world: SimulationWorld) -> void:
	var queued: Array[int] = []
	for command in world.command_queue.snapshot(): queued.append(command.command_id)
	for record in _records:
		if record.status == &"ACCEPTED" and world.current_tick > record.accepted_tick and not queued.has(record.command_id): _change(record,&"NOT_APPLIED",world.current_tick)
		if record.status != &"APPLIED": continue
		var formation := world.formations.get(record.formation_id) as FormationState
		var alive := 0
		if formation != null:
			for id in formation.member_entity_ids:
				var unit := world.units.get(id) as UnitState
				if unit != null and unit.enabled: alive+=1
		if alive == 0:
			_change(record,&"FORMATION_LOST",world.current_tick)
		elif world.battle_outcome.is_terminal(): _change(record,&"BATTLE_ENDED",world.current_tick)
		elif record.command_kind == &"STRATEGIC":
			var task := world.tasks.get(record.task_id) as TaskState
			if task == null: _change(record,&"TASK_UNAVAILABLE",world.current_tick)
			elif task.lifecycle in [TaskState.Lifecycle.COMPLETED,TaskState.Lifecycle.FAILED,TaskState.Lifecycle.CANCELLED]:
				_change(record,StringName("TASK_"+TaskState.Lifecycle.keys()[task.lifecycle]),world.current_tick)
		elif record.command_kind == &"STOP": _change(record,&"STOPPED",world.current_tick)
		elif record.target_entity_id != 0:
			var knowledge := world.faction_knowledge.get(2) as FactionKnowledge
			var contact := knowledge.hostile_contacts.get(record.target_entity_id) as KnowledgeContact if knowledge != null else null
			if contact != null and (knowledge.visible_hostile_unit_ids.has(record.target_entity_id) or knowledge.visible_hostile_building_ids.has(record.target_entity_id)) and not contact.enabled: _change(record,&"TARGET_DESTROYED_OBSERVED",world.current_tick)
			elif formation.order_target_entity_id == 0 and world.current_tick > record.applied_tick+1: _change(record,&"CONTACT_ENDED",world.current_tick)
		elif not formation.is_moving and formation.anchor_position.distance_to(record.target_position) <= 96.0:
			_change(record,&"AREA_REACHED",world.current_tick)
	_observe_visible(world)

func _observe_visible(world: SimulationWorld) -> void:
	# Independent player evidence: no hidden rule, command outcome, target or full strength.
	var visible: Dictionary = {}
	var positions: Dictionary = {}
	var members: Dictionary = {}
	var fired: Array[int] = []
	for index in range(_event_cursor,world.events.size()):
		var event := world.events[index]
		if event.kind == SimulationEvent.Kind.PROJECTILE_FIRED: fired.append(event.entity_id)
	_event_cursor=world.events.size()
	var ids := world.units.keys()
	ids.sort()
	for id in ids:
		var unit := world.units[id] as UnitState
		if unit.faction_id != 2 or not unit.enabled or not world.is_entity_visible_to_faction(id,1): continue
		var moved := _visible_positions.has(id) and not unit.position.is_equal_approx(_visible_positions[id])
		positions[id]=unit.position
		var key := unit.formation_id
		var member_ids: Array=members.get(key,[])
		member_ids.append(id)
		members[key]=member_ids
		var state: Array = visible.get(key,[0,&"SIGHTED"])
		state[0]+=1
		if fired.has(id): state[1]=&"ENGAGING"
		elif moved and state[1] != &"ENGAGING": state[1]=&"MOVING"
		elif _visible_positions.has(id) and state[1] == &"SIGHTED": state[1]=&"HOLDING"
		visible[key]=state
	_visible_positions=positions
	for key in _last_observed.keys():
		if not visible.has(key): _last_observed.erase(key)
	for key in visible:
		var state: Array=visible[key]
		var observation := _last_observed.get(key) as EnemyObservedAction
		if observation == null or observation.action != state[1] or _visible_members.get(key,[]) != members[key]:
			observation=EnemyObservedAction.new()
			observation.observation_id=_observed.size()+1
			observation.first_tick=world.current_tick
			observation.action=state[1]
			_observed.append(observation)
			_last_observed[key]=observation
		observation.last_tick=world.current_tick
		observation.visible_strength=state[0]
	_visible_members=members

func records_for(observer: int) -> Array[EnemyActionAuditRecord]:
	var result: Array[EnemyActionAuditRecord] = []
	if observer not in [0,2]: return result
	for record in _records: result.append(record.duplicate_value())
	return result

func observations_for(observer: int) -> Array[EnemyObservedAction]:
	var result: Array[EnemyObservedAction] = []
	if observer != 1: return result
	for entry in _observed: result.append(entry.duplicate_value())
	return result

func _change(record: EnemyActionAuditRecord, status: StringName, tick: int) -> void:
	record.status=status
	record.changed_tick=tick
