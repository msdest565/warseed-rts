class_name EnemyRaidAgent
extends RefCounted

const AGENT_ID := 301
const TASK_ID := 9001
const RAID_UNIT_ID := 1002
const RAID_SPAWN_TICK := 600
const ORDER_INTERVAL_TICKS := 10

var spawned: bool = false
var last_order_tick: int = -ORDER_INTERVAL_TICKS


func advance(world: SimulationWorld) -> void:
	if not spawned and world.current_tick >= RAID_SPAWN_TICK:
		world.spawn_enemy_raid_unit(RAID_UNIT_ID, AGENT_ID, TASK_ID)
		spawned = true
	if not spawned or not world.units.has(RAID_UNIT_ID):
		return
	var raider := world.units[RAID_UNIT_ID] as UnitState
	if not raider.enabled or world.current_tick - last_order_tick < ORDER_INTERVAL_TICKS:
		return
	var knowledge_snapshot := world.create_faction_snapshot(SimulationWorld.ENEMY_PLAYER_ID)
	var visible_target: UnitSnapshot
	var stale_target: UnitSnapshot
	for contact in knowledge_snapshot.units:
		if contact.faction_id == SimulationWorld.ENEMY_PLAYER_ID or not contact.enabled:
			continue
		if contact.is_visible_to_local_player:
			if visible_target == null or _target_precedes(contact, visible_target, raider.position):
				visible_target = contact
		elif stale_target == null or contact.last_seen_tick > stale_target.last_seen_tick or (contact.last_seen_tick == stale_target.last_seen_tick and contact.entity_id < stale_target.entity_id):
			stale_target = contact
	if visible_target != null:
		_submit_attack(raider, visible_target.entity_id, world)
	elif stale_target != null:
		_submit_move(raider, stale_target.last_seen_position, world)
	else:
		var ore_field := world.ore_fields.get(SimulationWorld.DEFAULT_ORE_FIELD_ID) as OreFieldState
		if ore_field != null:
			_submit_move(raider, ore_field.position, world)


func _target_precedes(candidate: UnitSnapshot, current: UnitSnapshot, origin: Vector2) -> bool:
	var candidate_is_harvester := candidate.definition_id == &"harvester"
	var current_is_harvester := current.definition_id == &"harvester"
	if candidate_is_harvester != current_is_harvester:
		return candidate_is_harvester
	var candidate_distance := candidate.position.distance_squared_to(origin)
	var current_distance := current.position.distance_squared_to(origin)
	return candidate_distance < current_distance or (is_equal_approx(candidate_distance, current_distance) and candidate.entity_id < current.entity_id)


func _submit_attack(raider: UnitState, target_entity_id: int, world: SimulationWorld) -> void:
	if raider.attack_target_entity_id == target_entity_id:
		return
	var command := AttackCommand.new(
		world.allocate_command_id(),
		SimulationWorld.ENEMY_PLAYER_ID,
		GameCommand.IssuerKind.AGENT,
		world.current_tick,
		raider.entity_id,
		target_entity_id
	)
	_set_context(command)
	if world.submit_command(command).is_accepted():
		last_order_tick = world.current_tick


func _submit_move(raider: UnitState, destination: Vector2, world: SimulationWorld) -> void:
	if raider.has_move_target and raider.move_target.is_equal_approx(destination):
		return
	var command := MoveCommand.new(
		world.allocate_command_id(),
		SimulationWorld.ENEMY_PLAYER_ID,
		GameCommand.IssuerKind.AGENT,
		world.current_tick,
		raider.entity_id,
		destination
	)
	_set_context(command)
	if world.submit_command(command).is_accepted():
		last_order_tick = world.current_tick


func _set_context(command: GameCommand) -> void:
	command.agent_id = AGENT_ID
	command.task_id = TASK_ID
