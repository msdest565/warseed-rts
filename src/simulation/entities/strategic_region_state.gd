class_name StrategicRegionState
extends RefCounted

var region_id: StringName
var display_name_key: StringName
var terrain_key: StringName
var position: Vector2
var radius: float
var supply_per_settlement: int
var adjacent_region_ids: Array[StringName] = []
var support_cooldown_ticks: int = 300
var capturable: bool = true
var capture_required_ticks: int = 60
var controller_faction_id: int = 0
var contested: bool = false
var capture_faction_id: int = 0
var capture_progress_ticks: int = 0
var last_settlement_tick: int = 0
var supply_node_active: bool = false


func _init(
	new_region_id: StringName,
	new_display_name_key: StringName,
	new_terrain_key: StringName,
	new_position: Vector2,
	new_radius: float,
	new_supply_per_settlement: int,
	new_adjacent_region_ids: Array[StringName] = [],
	new_support_cooldown_ticks: int = 300,
	new_capturable: bool = true,
	new_capture_required_ticks: int = 60
) -> void:
	region_id = new_region_id
	display_name_key = new_display_name_key
	terrain_key = new_terrain_key
	position = new_position
	radius = new_radius
	supply_per_settlement = new_supply_per_settlement
	adjacent_region_ids.assign(new_adjacent_region_ids)
	support_cooldown_ticks = new_support_cooldown_ticks
	capturable = new_capturable
	capture_required_ticks = maxi(1, new_capture_required_ticks)


func capture_ratio() -> float:
	return clampf(float(capture_progress_ticks) / float(capture_required_ticks), 0.0, 1.0)
