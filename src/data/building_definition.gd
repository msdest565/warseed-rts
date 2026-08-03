class_name BuildingDefinition
extends Resource

@export var definition_id: StringName
@export var display_name: String
@export var max_health: float = 1000.0
@export var build_cost: int = 0
@export var production_cost: int = 0
@export var production_ticks: int = 0
@export var provides_command_center: bool = false
@export var provides_factory: bool = false
@export var provides_support: bool = false
@export_range(0.0, 10000.0) var sight_range: float = 256.0
