class_name UnitSnapshot
extends RefCounted

var entity_id: int
var position: Vector2
var move_target: Vector2
var path: PackedVector2Array
var is_moving: bool
var controller_id: int
var enabled: bool
var formation_id: int
var formation_slot_id: int
var desired_position: Vector2
var is_recovering: bool
var ticks_without_progress: int
var is_attack_moving: bool
var faction_id: int
var max_health: float
var health: float
var attack_range: float
var attack_damage: float
var attack_cooldown_ticks: int
var attack_cooldown_remaining_ticks: int
var attack_target_entity_id: int
var is_attacking: bool
var armor: float
var attacks_per_second: float
var projectile_speed: float
var sight_range: float
var is_visible_to_local_player: bool
var last_seen_tick: int
var last_seen_position: Vector2
var definition_id: StringName
var can_attack: bool
var can_harvest: bool
var can_construct: bool
var can_repair: bool
var death_tick: int
var harvest_ore_field_entity_id: int
var harvest_refinery_entity_id: int
var harvest_ticks_remaining: int
var harvest_phase: UnitState.HarvestPhase
var cargo_ore: int
var work_kind: UnitState.WorkKind
var work_target_building_id: int
var control_state: UnitState.ControlState
var assigned_agent_id: int
var assigned_task_id: int
var original_formation_id: int
var return_task_id: int
var takeover_reason: String
var last_command_id: int
var last_command_tick: int
var rejoin_formation_id: int
var rejoin_slot_id: int
var rejoin_pending: bool


func _init(unit: UnitState = null, contact: KnowledgeContact = null) -> void:
	if contact != null:
		_apply_contact(contact)
		return
	entity_id = unit.entity_id
	position = unit.position
	move_target = unit.move_target
	path = unit.path.duplicate()
	if unit.has_move_target and not path.is_empty():
		var snapshot_path_index := clampi(unit.path_index - 1, 0, path.size() - 1)
		path = path.slice(snapshot_path_index)
		if not path.is_empty():
			path[0] = unit.position
	is_moving = unit.has_move_target
	controller_id = unit.controller_id
	enabled = unit.enabled
	formation_id = unit.formation_id
	formation_slot_id = unit.formation_slot_id
	desired_position = unit.desired_position
	is_recovering = unit.is_recovering
	ticks_without_progress = unit.ticks_without_progress
	is_attack_moving = unit.is_attack_moving
	faction_id = unit.faction_id
	max_health = unit.max_health
	health = unit.health
	attack_range = unit.attack_range
	attack_damage = unit.attack_damage
	attack_cooldown_ticks = unit.attack_cooldown_ticks
	attack_cooldown_remaining_ticks = unit.attack_cooldown_remaining_ticks
	attack_target_entity_id = unit.attack_target_entity_id
	is_attacking = unit.attack_target_entity_id != 0
	armor = unit.armor
	attacks_per_second = unit.attacks_per_second
	projectile_speed = unit.projectile_speed
	sight_range = unit.sight_range
	is_visible_to_local_player = unit.is_visible_to_local_player
	last_seen_tick = unit.last_seen_tick
	last_seen_position = unit.last_seen_position
	definition_id = unit.definition_id
	can_attack = unit.can_attack
	can_harvest = unit.can_harvest
	can_construct = unit.can_construct
	can_repair = unit.can_repair
	death_tick = unit.death_tick
	harvest_ore_field_entity_id = unit.harvest_ore_field_entity_id
	harvest_refinery_entity_id = unit.harvest_refinery_entity_id
	harvest_ticks_remaining = unit.harvest_ticks_remaining
	harvest_phase = unit.harvest_phase
	cargo_ore = unit.cargo_ore
	work_kind = unit.work_kind
	work_target_building_id = unit.work_target_building_id
	control_state = unit.control_state
	assigned_agent_id = unit.assigned_agent_id
	assigned_task_id = unit.assigned_task_id
	original_formation_id = unit.original_formation_id
	return_task_id = unit.return_task_id
	takeover_reason = unit.takeover_reason
	last_command_id = unit.last_command_id
	last_command_tick = unit.last_command_tick
	rejoin_formation_id = unit.rejoin_formation_id
	rejoin_slot_id = unit.rejoin_slot_id
	rejoin_pending = unit.rejoin_pending


func _apply_contact(contact: KnowledgeContact) -> void:
	entity_id = contact.entity_id
	position = contact.position
	move_target = contact.position
	path = PackedVector2Array()
	is_moving = false
	controller_id = contact.faction_id
	enabled = contact.enabled
	formation_id = 0
	formation_slot_id = -1
	desired_position = contact.position
	is_recovering = false
	ticks_without_progress = 0
	is_attack_moving = false
	faction_id = contact.faction_id
	max_health = contact.max_health
	health = contact.health
	attack_range = 0.0
	attack_damage = 0.0
	attack_cooldown_ticks = 0
	attack_cooldown_remaining_ticks = 0
	attack_target_entity_id = 0
	is_attacking = false
	armor = 0.0
	attacks_per_second = 0.0
	projectile_speed = 0.0
	sight_range = 0.0
	is_visible_to_local_player = false
	last_seen_tick = contact.last_seen_tick
	last_seen_position = contact.position
	definition_id = contact.definition_id
	can_attack = false
	can_harvest = false
	can_construct = false
	can_repair = false
	death_tick = contact.last_seen_tick if not contact.enabled else -1
	harvest_ore_field_entity_id = 0
	harvest_refinery_entity_id = 0
	harvest_ticks_remaining = 0
	harvest_phase = UnitState.HarvestPhase.IDLE
	cargo_ore = 0
	work_kind = UnitState.WorkKind.NONE
	work_target_building_id = 0
	control_state = UnitState.ControlState.DISABLED if not contact.enabled else UnitState.ControlState.UNASSIGNED
	assigned_agent_id = 0
	assigned_task_id = 0
	original_formation_id = 0
	return_task_id = 0
	takeover_reason = ""
	last_command_id = 0
	last_command_tick = -1
	rejoin_formation_id = 0
	rejoin_slot_id = -1
	rejoin_pending = false
