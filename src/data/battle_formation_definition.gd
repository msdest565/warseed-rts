class_name BattleFormationDefinition
extends Resource

@export var formation_id: int
@export var role_id: StringName
@export var faction_id: int = 2
@export var unit_definition_id: StringName
@export var strength: int = 1
@export var spawn_position: Vector2
@export var first_entity_id: int
@export var facing: Vector2 = Vector2.DOWN
@export var agent_id: int
@export var task_id: int
@export var tactical_role: int
