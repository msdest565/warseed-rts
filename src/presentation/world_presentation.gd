class_name WorldPresentation
extends Node2D

var selected_entity_id: int = 0
var selected_entity_ids: Array[int] = []
var selected_building_id: int = 0
var previous_snapshot: WorldSnapshot
var current_snapshot: WorldSnapshot
var interpolation_alpha: float = 0.0
var pending_move_target: Vector2
var pending_move_active: bool = false
var build_preview_position: Vector2
var build_preview_footprint_size: Vector2i = Vector2i.ONE
var build_preview_engineer_position: Vector2
var build_preview_valid: bool = false
var build_preview_active: bool = false
var attack_targeting_active: bool = false
var attack_preview_active: bool = false
var attack_preview_position: Vector2
var attack_preview_target_entity_id: int = 0
var _proxies: Dictionary = {}
var _building_proxies: Dictionary = {}
var _ore_field_proxies: Dictionary = {}
var _projectile_positions: Dictionary = {}
var _synced_snapshot_tick: int = -1
var _full_sync_count: int = 0

@onready var units_root: Node2D = $Units
@onready var buildings_root: Node2D = $Buildings
@onready var ore_fields_root: Node2D = $OreFields


func refresh_locale() -> void:
	for proxy in _proxies.values():
		(proxy as UnitProxy).queue_redraw()
	for proxy in _building_proxies.values():
		(proxy as BuildingProxy).queue_redraw()
	for proxy in _ore_field_proxies.values():
		(proxy as OreFieldProxy).queue_redraw()
	queue_redraw()


func set_snapshots(previous: WorldSnapshot, current: WorldSnapshot, alpha: float) -> void:
	previous_snapshot = previous
	current_snapshot = current
	interpolation_alpha = clampf(alpha, 0.0, 1.0)
	if current_snapshot == null or current_snapshot.tick == _synced_snapshot_tick:
		return
	_synced_snapshot_tick = current_snapshot.tick
	_full_sync_count += 1
	_sync_proxies()
	_sync_building_proxies()
	_sync_ore_field_proxies()
	_projectile_positions.clear()
	for projectile in current_snapshot.projectiles:
		_projectile_positions[projectile.projectile_id] = projectile.position
	queue_redraw()


func get_full_sync_count() -> int:
	return _full_sync_count


func set_selected_entity(entity_id: int) -> void:
	set_selected_entities([entity_id] if entity_id != 0 else [], entity_id, 0)


func set_selected_entities(entity_ids: Array[int], primary_entity_id: int, building_id: int = 0) -> void:
	selected_entity_ids = entity_ids.duplicate()
	selected_entity_id = primary_entity_id
	selected_building_id = building_id
	var selected_formation_id := 0
	if current_snapshot != null:
		var selected_unit := current_snapshot.get_unit(selected_entity_id)
		if selected_unit != null:
			selected_formation_id = selected_unit.formation_id
	for proxy_variant in _proxies.values():
		var proxy := proxy_variant as UnitProxy
		proxy.selected = selected_entity_ids.has(proxy.entity_id)
		var unit := current_snapshot.get_unit(proxy.entity_id) if current_snapshot != null else null
		proxy.formation_member = selected_formation_id != 0 and unit != null and unit.formation_id == selected_formation_id
	for proxy_variant in _building_proxies.values():
		var building_proxy := proxy_variant as BuildingProxy
		building_proxy.selected = building_proxy.snapshot != null and building_proxy.snapshot.entity_id == selected_building_id


func set_pending_move_target(target_position: Vector2) -> void:
	pending_move_target = target_position
	pending_move_active = true
	queue_redraw()


func clear_pending_move_target() -> void:
	pending_move_active = false
	queue_redraw()


func set_build_preview(build_position: Vector2, footprint_size: Vector2i, valid: bool, engineer_position: Vector2) -> void:
	build_preview_position = build_position
	build_preview_footprint_size = footprint_size
	build_preview_valid = valid
	build_preview_engineer_position = engineer_position
	build_preview_active = true
	queue_redraw()


func clear_build_preview() -> void:
	build_preview_active = false
	queue_redraw()


func begin_attack_targeting() -> void:
	attack_targeting_active = true
	attack_preview_active = false
	attack_preview_target_entity_id = 0
	queue_redraw()


func set_attack_preview(target_position: Vector2, target_entity_id: int) -> void:
	attack_targeting_active = true
	attack_preview_active = true
	attack_preview_position = target_position
	attack_preview_target_entity_id = target_entity_id
	queue_redraw()


func clear_attack_preview() -> void:
	attack_targeting_active = false
	attack_preview_active = false
	attack_preview_target_entity_id = 0
	queue_redraw()


func _process(_delta: float) -> void:
	if current_snapshot == null:
		return
	_update_proxy_positions(false)
	if not current_snapshot.projectiles.is_empty() or _selected_overlay_needs_interpolation():
		queue_redraw()


func _selected_overlay_needs_interpolation() -> bool:
	if selected_entity_id == 0:
		return false
	var unit := current_snapshot.get_unit(selected_entity_id)
	if unit == null:
		return false
	if unit.is_moving or unit.attack_target_entity_id != 0:
		return true
	var formation := current_snapshot.get_formation(unit.formation_id) if unit.formation_id != 0 else null
	return formation != null and formation.is_moving


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
	set_selected_entities(selected_entity_ids, selected_entity_id, selected_building_id)
	_update_proxy_positions(true)


func _sync_building_proxies() -> void:
	var active_ids: Dictionary = {}
	for building in current_snapshot.buildings:
		active_ids[building.entity_id] = true
		if not _building_proxies.has(building.entity_id):
			var proxy := BuildingProxy.new()
			var parent := buildings_root if buildings_root != null else self
			parent.add_child(proxy)
			_building_proxies[building.entity_id] = proxy
		(_building_proxies[building.entity_id] as BuildingProxy).apply_snapshot(building)
	for entity_id in _building_proxies.keys():
		if not active_ids.has(entity_id):
			(_building_proxies[entity_id] as BuildingProxy).queue_free()
			_building_proxies.erase(entity_id)
	set_selected_entities(selected_entity_ids, selected_entity_id, selected_building_id)


func _sync_ore_field_proxies() -> void:
	var active_ids: Dictionary = {}
	for ore_field in current_snapshot.ore_fields:
		active_ids[ore_field.entity_id] = true
		if not _ore_field_proxies.has(ore_field.entity_id):
			var proxy := OreFieldProxy.new()
			var parent := ore_fields_root if ore_fields_root != null else self
			parent.add_child(proxy)
			_ore_field_proxies[ore_field.entity_id] = proxy
		(_ore_field_proxies[ore_field.entity_id] as OreFieldProxy).apply_snapshot(ore_field)
	for entity_id in _ore_field_proxies.keys():
		if not active_ids.has(entity_id):
			(_ore_field_proxies[entity_id] as OreFieldProxy).queue_free()
			_ore_field_proxies.erase(entity_id)


func _update_proxy_positions(apply_snapshot_data: bool) -> void:
	for unit in current_snapshot.units:
		var from_position := unit.position
		var proxy := _proxies[unit.entity_id] as UnitProxy
		if apply_snapshot_data:
			proxy.apply_snapshot(unit)
		if previous_snapshot != null:
			var previous_unit := previous_snapshot.get_unit(unit.entity_id)
			if previous_unit != null and unit.is_visible_to_local_player and previous_unit.is_visible_to_local_player:
				from_position = previous_unit.position
		proxy.position = from_position.lerp(
			unit.position,
			interpolation_alpha
		)


func _draw() -> void:
	if build_preview_active:
		_draw_build_preview()
	if attack_targeting_active:
		_draw_attack_targeting()
	if current_snapshot != null:
		for task in current_snapshot.tasks:
			if task.kind == TaskState.Kind.FORMATION_MOVE_TEST or task.lifecycle in [TaskState.Lifecycle.COMPLETED, TaskState.Lifecycle.FAILED, TaskState.Lifecycle.CANCELLED]:
				continue
			var task_color := Color("58c6d0")
			if task.kind == TaskState.Kind.DEVELOP_RESOURCE:
				task_color = Color("e3b341")
			elif task.kind == TaskState.Kind.ATTACK_TARGET:
				task_color = Color("e56a54")
			if task.route.size() >= 2:
				draw_polyline(task.route, task_color, 3.0)
			draw_circle(task.target_position, 10.0, Color(task_color, 0.2))
			draw_arc(task.target_position, 10.0, 0.0, TAU, 28, task_color, 2.0)
			if task.kind == TaskState.Kind.DEFEND_AREA and task.target_radius > 0.0:
				draw_arc(task.target_position, task.target_radius, 0.0, TAU, 64, Color(task_color, 0.7), 2.0)
		for projectile in current_snapshot.projectiles:
			var position := projectile.position
			var previous := previous_snapshot.get_projectile(projectile.projectile_id) if previous_snapshot != null else null
			if previous != null:
				position = previous.position.lerp(projectile.position, interpolation_alpha)
			var color := Color("f7d154") if projectile.faction_id == SimulationWorld.LOCAL_PLAYER_ID else Color("ef6a62")
			draw_line(position - Vector2(10.0, 0.0), position, color.darkened(0.25), 3.0)
			draw_circle(position, 4.0, color)
	if pending_move_active:
		draw_circle(pending_move_target, 12.0, Color(0.95, 0.78, 0.28, 0.16))
		draw_arc(pending_move_target, 12.0, 0.0, TAU, 24, Color("f2c94c"), 2.0)
	if current_snapshot == null or selected_entity_id == 0:
		return
	var unit := current_snapshot.get_unit(selected_entity_id)
	if unit == null:
		return
	if unit.attack_target_entity_id != 0:
		var attack_target := current_snapshot.get_unit(unit.attack_target_entity_id)
		var target_position := attack_target.position if attack_target != null else Vector2.ZERO
		if attack_target == null:
			var target_building := current_snapshot.get_building(unit.attack_target_entity_id)
			if target_building != null:
				target_position = target_building.position
		if target_position != Vector2.ZERO:
			draw_line(unit.position, target_position, Color(0.92, 0.27, 0.22, 0.85), 2.0)
			draw_arc(target_position, 34.0, 0.0, TAU, 40, Color("ed5b4f"), 2.0)
	if unit.formation_id != 0:
		var formation := current_snapshot.get_formation(unit.formation_id)
		if formation != null and formation.is_moving:
			var route_color := Color("ed704b") if unit.is_attack_moving else Color(0.95, 0.78, 0.28, 0.8)
			if formation.path.size() >= 2:
				draw_polyline(formation.path, route_color, 2.0)
			for member_id in formation.member_entity_ids:
				var member := current_snapshot.get_unit(member_id)
				if member != null:
					draw_circle(member.desired_position, 5.0, Color(0.41, 0.72, 0.77, 0.45))
			draw_arc(formation.target_position, 10.0, 0.0, TAU, 24, Color("f2c94c"), 2.0)
		return
	if not unit.is_moving:
		return
	if unit.path.size() >= 2:
		draw_polyline(unit.path, Color(0.95, 0.78, 0.28, 0.8), 2.0)
	draw_circle(unit.move_target, 9.0, Color(0.95, 0.78, 0.28, 0.18))
	draw_arc(unit.move_target, 9.0, 0.0, TAU, 24, Color("f2c94c"), 2.0)


func _draw_build_preview() -> void:
	var grid := LogicGrid.new()
	var footprint := grid.get_footprint_cells(build_preview_position, build_preview_footprint_size)
	var color := Color("55d6a9") if build_preview_valid else Color("ef6258")
	for cell in footprint:
		var cell_rect := Rect2(Vector2(cell) * LogicGrid.CELL_SIZE, Vector2.ONE * LogicGrid.CELL_SIZE)
		draw_rect(cell_rect, Color(color, 0.22), true)
		draw_rect(cell_rect.grow(-1.0), Color(color, 0.95), false, 2.0)
	var footprint_lookup: Dictionary = {}
	for cell in footprint:
		footprint_lookup[cell] = true
	var work_cells: Array[Vector2i] = []
	for cell in footprint:
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var work_cell: Vector2i = cell + offset
			if not footprint_lookup.has(work_cell) and not work_cells.has(work_cell):
				work_cells.append(work_cell)
	for cell in work_cells:
		draw_circle(grid.cell_to_world(cell), 4.0, Color(color, 0.75))
	var range_radius := maxf(build_preview_footprint_size.x, build_preview_footprint_size.y) * LogicGrid.CELL_SIZE * 0.5 + LogicGrid.CELL_SIZE
	draw_arc(build_preview_position, range_radius, 0.0, TAU, 48, Color(color, 0.8), 2.0)
	draw_dashed_line(build_preview_engineer_position, build_preview_position, Color(color, 0.7), 2.0, 8.0)


func _draw_attack_targeting() -> void:
	if current_snapshot == null:
		return
	var combat_units: Array[UnitSnapshot] = []
	for entity_id in selected_entity_ids:
		var unit := current_snapshot.get_unit(entity_id)
		if unit == null or not unit.enabled or not unit.can_attack or not unit.can_accept_attack_orders:
			continue
		combat_units.append(unit)
		draw_circle(unit.position, unit.attack_range, Color(0.22, 0.78, 0.72, 0.055))
		draw_arc(unit.position, unit.attack_range, 0.0, TAU, 72, Color(0.32, 0.86, 0.78, 0.78), 2.0)
	if not attack_preview_active or combat_units.is_empty():
		return
	var marker_color := Color("ed5b4f") if attack_preview_target_entity_id != 0 else Color("f2c94c")
	var marker_radius := 30.0 if attack_preview_target_entity_id != 0 else 12.0
	for unit in combat_units:
		draw_dashed_line(unit.position, attack_preview_position, Color(marker_color, 0.58), 1.5, 9.0)
	draw_circle(attack_preview_position, marker_radius, Color(marker_color, 0.14))
	draw_arc(attack_preview_position, marker_radius, 0.0, TAU, 40, marker_color, 2.5)
	draw_line(attack_preview_position + Vector2(-8.0, 0.0), attack_preview_position + Vector2(8.0, 0.0), marker_color, 2.0)
	draw_line(attack_preview_position + Vector2(0.0, -8.0), attack_preview_position + Vector2(0.0, 8.0), marker_color, 2.0)
