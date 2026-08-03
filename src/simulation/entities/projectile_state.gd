class_name ProjectileState
extends RefCounted

var projectile_id: int
var source_entity_id: int
var target_entity_id: int
var faction_id: int
var position: Vector2
var speed: float
var attack_power: float
var spawn_tick: int


func _init(
	new_projectile_id: int,
	new_source_entity_id: int,
	new_target_entity_id: int,
	new_faction_id: int,
	new_position: Vector2,
	new_speed: float,
	new_attack_power: float,
	new_spawn_tick: int
) -> void:
	projectile_id = new_projectile_id
	source_entity_id = new_source_entity_id
	target_entity_id = new_target_entity_id
	faction_id = new_faction_id
	position = new_position
	speed = new_speed
	attack_power = new_attack_power
	spawn_tick = new_spawn_tick
