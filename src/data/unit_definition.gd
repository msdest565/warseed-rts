class_name UnitDefinition
extends Resource

@export var definition_id: StringName
@export var display_name: String
@export_range(0.01, 10000.0) var move_speed: float = 180.0
@export var production_cost: int = 100
@export var production_ticks: int = 30
@export var cargo_capacity: int = 0
@export var can_repair: bool = false
@export_range(0.0, 10000.0) var sight_range: float = 224.0
@export var combat: CombatDefinition
