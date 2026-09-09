class_name BattleIntelDefinition
extends Resource

@export var source_key: StringName
@export var target_category_key: StringName
@export var estimated_min: int = 0
@export var estimated_max: int = 0
@export var region_id: StringName
@export var direction_key: StringName
@export var confidence_key: StringName
@export var eta_min_ticks: int = -1
@export var eta_max_ticks: int = -1
@export var has_estimate: bool = true
