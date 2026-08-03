class_name ProjectileSnapshot
extends RefCounted

var projectile_id: int
var source_entity_id: int
var target_entity_id: int
var faction_id: int
var position: Vector2
var speed: float
var attack_power: float


func _init(projectile: ProjectileState) -> void:
	projectile_id = projectile.projectile_id
	source_entity_id = projectile.source_entity_id
	target_entity_id = projectile.target_entity_id
	faction_id = projectile.faction_id
	position = projectile.position
	speed = projectile.speed
	attack_power = projectile.attack_power
