class_name BattleEnemyPlanDefinition
extends Resource

@export var plan_id: StringName
@export var action_key: StringName
@export var assault_formation_role_id: StringName = &"assault"
@export var assault_target_region_id: StringName
@export var assault_target_position: Vector2
@export var assault_route_region_ids: Array[StringName] = []
@export var probe_formation_role_id: StringName = &"probe"
@export var probe_target_region_id: StringName
@export var probe_target_position: Vector2
@export var commitment_ticks: int = 180
@export var followup_tick: int = -1
@export var followup_formation_role_id: StringName
@export var followup_target_region_id: StringName
@export var followup_target_position: Vector2
