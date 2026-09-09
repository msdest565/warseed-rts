class_name BattleRegionDefinition
extends Resource

@export var region_id: StringName
@export var display_name_key: StringName
@export var terrain_key: StringName
@export var position: Vector2
@export var radius: float = 220.0
@export var supply_per_settlement: int = 0
@export var adjacent_region_ids: Array[StringName] = []
@export var support_cooldown_ticks: int = 300
@export var capturable: bool = true
@export_range(1, 600, 1) var capture_ticks: int = 60
