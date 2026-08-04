class_name UnitState
extends RefCounted

enum ControlState {
	PLAYER_CONTROLLED,
	AGENT_ASSIGNED,
	TEMPORARILY_OVERRIDDEN,
	UNASSIGNED,
	DISABLED,
}

enum HarvestPhase {
	IDLE,
	TO_FIELD,
	LOADING,
	TO_REFINERY,
	UNLOADING,
}

enum WorkKind {
	NONE,
	CONSTRUCT,
	REPAIR,
}

var entity_id: int
var position: Vector2
var move_target: Vector2
var path: PackedVector2Array = PackedVector2Array()
var path_index: int = 0
var has_move_target: bool = false
var move_speed: float
var controller_id: int
var enabled: bool = true
var formation_id: int = 0
var formation_slot_id: int = -1
var following_formation: bool = false
var desired_position: Vector2
var ticks_without_progress: int = 0
var recovery_attempts: int = 0
var is_recovering: bool = false
var recovery_path: PackedVector2Array = PackedVector2Array()
var recovery_path_index: int = 0
var is_attack_moving: bool = false
var faction_id: int
var max_health: float = 100.0
var health: float = 100.0
var attack_range: float = 180.0
var attack_damage: float = 20.0
var attack_cooldown_ticks: int = 10
var attack_cooldown_remaining_ticks: int = 0
var attack_target_entity_id: int = 0
var armor: float = 0.0
var attacks_per_second: float = 1.0
var projectile_speed: float = 480.0
var sight_range: float = 224.0
var is_visible_to_local_player: bool = true
var last_seen_tick: int = 0
var last_seen_position: Vector2
var definition_id: StringName = &"scout_vehicle"
var can_attack: bool = true
var can_harvest: bool = false
var can_construct: bool = false
var can_repair: bool = false
var death_tick: int = -1
var harvest_ore_field_entity_id: int = 0
var harvest_refinery_entity_id: int = 0
var harvest_ticks_remaining: int = 0
var harvest_phase: HarvestPhase = HarvestPhase.IDLE
var cargo_ore: int = 0
var work_kind: WorkKind = WorkKind.NONE
var work_target_building_id: int = 0
var control_state: ControlState = ControlState.PLAYER_CONTROLLED
var assigned_agent_id: int = 0
var assigned_task_id: int = 0
var original_formation_id: int = 0
var return_task_id: int = 0
var takeover_reason: String = ""
var last_command_id: int = 0
var last_command_tick: int = -1
var rejoin_formation_id: int = 0
var rejoin_slot_id: int = -1
var rejoin_pending: bool = false


func _init(
	new_entity_id: int,
	new_position: Vector2,
	new_move_speed: float,
	new_controller_id: int
) -> void:
	entity_id = new_entity_id
	position = new_position
	move_target = new_position
	desired_position = new_position
	move_speed = new_move_speed
	controller_id = new_controller_id
	faction_id = new_controller_id
	last_seen_position = new_position
