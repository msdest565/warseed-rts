class_name WorldPresentation
extends Node2D

var selected_entity_id: int = 0
var previous_snapshot: WorldSnapshot
var current_snapshot: WorldSnapshot
var interpolation_alpha: float = 0.0
var _proxies: Dictionary = {}

@onready var units_root: Node2D = $Units


func set_snapshots(previous: WorldSnapshot, current: WorldSnapshot, alpha: float) -> void:
	previous_snapshot = previous
	current_snapshot = current
	interpolation_alpha = clampf(alpha, 0.0, 1.0)
	_sync_proxies()
	queue_redraw()


func set_selected_entity(entity_id: int) -> void:
	selected_entity_id = entity_id
	for proxy_variant in _proxies.values():
		var proxy := proxy_variant as UnitProxy
		proxy.selected = proxy.entity_id == selected_entity_id


func _process(_delta: float) -> void:
	if current_snapshot == null:
		return
	_update_proxy_positions()
	queue_redraw()


func _sync_proxies() -> void:
	if current_snapshot == null:
		return
	var active_ids: Dictionary = {}
	for unit in current_snapshot.units:
		active_ids[unit.entity_id] = true
		if not _proxies.has(unit.entity_id):
			var proxy := UnitProxy.new()
			proxy.configure(unit.entity_id)
			units_root.add_child(proxy)
			_proxies[unit.entity_id] = proxy
	for entity_id in _proxies.keys():
		if not active_ids.has(entity_id):
			(_proxies[entity_id] as UnitProxy).queue_free()
			_proxies.erase(entity_id)
	set_selected_entity(selected_entity_id)
	_update_proxy_positions()


func _update_proxy_positions() -> void:
	for unit in current_snapshot.units:
		var from_position := unit.position
		if previous_snapshot != null:
			var previous_unit := previous_snapshot.get_unit(unit.entity_id)
			if previous_unit != null:
				from_position = previous_unit.position
		(_proxies[unit.entity_id] as UnitProxy).position = from_position.lerp(
			unit.position,
			interpolation_alpha
		)


func _draw() -> void:
	if current_snapshot == null or selected_entity_id == 0:
		return
	var unit := current_snapshot.get_unit(selected_entity_id)
	if unit == null or not unit.is_moving:
		return
	draw_dashed_line(unit.position, unit.move_target, Color(0.95, 0.78, 0.28, 0.8), 2.0, 8.0)
	draw_circle(unit.move_target, 9.0, Color(0.95, 0.78, 0.28, 0.18))
	draw_arc(unit.move_target, 9.0, 0.0, TAU, 24, Color("f2c94c"), 2.0)
