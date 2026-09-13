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
var formation_plan_route: PackedVector2Array = PackedVector2Array()
var formation_plan_line_start: Vector2
var formation_plan_line_end: Vector2
var formation_plan_active: bool = false
var formation_plan_drawing_line: bool = false
var commander_intent_active: bool = false
var commander_intent_commander_id: StringName
var commander_intent_origin: Vector2
var commander_intent_target: Vector2
var commander_plan_active: bool = false
var commander_plan_commander_id: StringName
var commander_plan_route: PackedVector2Array = PackedVector2Array()
var commander_plan_target: Vector2
var _proxies: Dictionary = {}
var _building_proxies: Dictionary = {}
var _ore_field_proxies: Dictionary = {}
var _previous_unit_positions: Dictionary = {}
var _previous_visible_unit_ids: Dictionary = {}
var _previous_projectile_positions: Dictionary = {}
var _synced_snapshot_tick: int = -1
var _full_sync_count: int = 0
var _unit_bodies_batch: MultiMeshInstance2D
var _projectile_batch: MultiMeshInstance2D
var _unit_body_buffer: PackedFloat32Array = PackedFloat32Array()
var _projectile_buffer: PackedFloat32Array = PackedFloat32Array()
var _unit_labels_visible: bool = true
var _combat_effects: Array[Dictionary] = []
var _last_batch_update_frame: int = -1

const MULTIMESH_TRANSFORM_COLOR_STRIDE := 12
const DETAILED_UNIT_LIMIT := 56
const MUZZLE_FLASH_DURATION := 0.16
const IMPACT_FLASH_DURATION := 0.32
const DESTRUCTION_EFFECT_DURATION := 0.72

var _detailed_units_enabled: bool = true

@onready var units_root: Node2D = $Units
@onready var buildings_root: Node2D = $Buildings
@onready var ore_fields_root: Node2D = $OreFields


func refresh_locale() -> void:
	for proxy in _building_proxies.values():
		(proxy as BuildingProxy).queue_redraw()
	for proxy in _ore_field_proxies.values():
		(proxy as OreFieldProxy).queue_redraw()
	queue_redraw()


func set_unit_labels_visible(labels_visible: bool) -> void:
	if labels_visible == _unit_labels_visible:
		return
	_unit_labels_visible = labels_visible
	for proxy_variant in _proxies.values():
		var proxy := proxy_variant as UnitProxy
		proxy.scale = Vector2.ONE
		proxy.show_labels = _unit_labels_visible
	queue_redraw()


func set_snapshots(previous: WorldSnapshot, current: WorldSnapshot, alpha: float) -> void:
	previous_snapshot = previous
	current_snapshot = current
	interpolation_alpha = clampf(alpha, 0.0, 1.0)
	if current_snapshot == null or current_snapshot.tick == _synced_snapshot_tick:
		return
	_synced_snapshot_tick = current_snapshot.tick
	_full_sync_count += 1
	_cache_previous_interpolation_state()
	_sync_proxies()
	_sync_building_proxies()
	_sync_ore_field_proxies()
	_sync_combat_feedback()
	queue_redraw()


func _cache_previous_interpolation_state() -> void:
	_previous_unit_positions.clear()
	_previous_visible_unit_ids.clear()
	_previous_projectile_positions.clear()
	if previous_snapshot == null:
		return
	for unit in previous_snapshot.units:
		_previous_unit_positions[unit.entity_id] = unit.position
		if unit.is_visible_to_local_player:
			_previous_visible_unit_ids[unit.entity_id] = true
	for projectile in previous_snapshot.projectiles:
		_previous_projectile_positions[projectile.projectile_id] = projectile.position


func get_full_sync_count() -> int:
	return _full_sync_count


func set_selected_entity(entity_id: int) -> void:
	set_selected_entities([entity_id] if entity_id != 0 else [], entity_id, 0)


func set_selected_entities(entity_ids: Array[int], primary_entity_id: int, building_id: int = 0) -> void:
	selected_entity_ids = entity_ids.duplicate()
	selected_entity_id = primary_entity_id
	selected_building_id = building_id
	var selected_lookup: Dictionary = {}
	for entity_id in selected_entity_ids:
		selected_lookup[entity_id] = true
	var selected_formation_id := 0
	if current_snapshot != null:
		var selected_unit := current_snapshot.get_unit(selected_entity_id)
		if selected_unit != null:
			selected_formation_id = selected_unit.formation_id
	for proxy_variant in _proxies.values():
		var proxy := proxy_variant as UnitProxy
		proxy.selected = selected_lookup.has(proxy.entity_id)
		if selected_formation_id == 0:
			proxy.formation_member = false
		else:
			var unit := current_snapshot.get_unit(proxy.entity_id) if current_snapshot != null else null
			proxy.formation_member = unit != null and unit.formation_id == selected_formation_id
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


func set_formation_plan_preview(route_points: PackedVector2Array, line_start: Vector2, line_end: Vector2, drawing_line: bool) -> void:
	formation_plan_route = route_points.duplicate()
	formation_plan_line_start = line_start
	formation_plan_line_end = line_end
	formation_plan_active = true
	formation_plan_drawing_line = drawing_line
	queue_redraw()


func clear_formation_plan_preview() -> void:
	formation_plan_active = false
	formation_plan_drawing_line = false
	formation_plan_route = PackedVector2Array()
	queue_redraw()


func set_commander_intent_preview(commander_id: StringName, target_position: Vector2) -> void:
	commander_intent_active = true
	commander_intent_commander_id = commander_id
	commander_intent_target = target_position
	commander_intent_origin = _commander_intent_origin(commander_id, target_position)
	queue_redraw()


func clear_commander_intent_preview() -> void:
	commander_intent_active = false
	commander_intent_commander_id = &""
	queue_redraw()


func set_commander_plan_preview(commander_id: StringName, route_points: PackedVector2Array, target_position: Vector2) -> void:
	commander_plan_active = true
	commander_plan_commander_id = commander_id
	commander_plan_route = route_points.duplicate()
	commander_plan_target = target_position
	queue_redraw()


func clear_commander_plan_preview() -> void:
	commander_plan_active = false
	commander_plan_commander_id = &""
	commander_plan_route = PackedVector2Array()
	queue_redraw()


func _process(_delta: float) -> void:
	if current_snapshot == null:
		return
	_update_proxy_positions(false)
	_update_combat_effects(_delta)
	if not current_snapshot.projectiles.is_empty() or not _combat_effects.is_empty() or _selected_overlay_needs_interpolation():
		queue_redraw()


func get_active_combat_effect_count() -> int:
	return _combat_effects.size()


func _update_combat_effects(delta: float) -> void:
	for index in range(_combat_effects.size() - 1, -1, -1):
		var effect := _combat_effects[index]
		effect["elapsed"] = float(effect.get("elapsed", 0.0)) + delta
		if float(effect["elapsed"]) >= float(effect["duration"]):
			_combat_effects.remove_at(index)


func _sync_combat_feedback() -> void:
	if previous_snapshot == null or current_snapshot == null or previous_snapshot.tick == current_snapshot.tick:
		return
	var previous_projectiles: Dictionary = {}
	for projectile in previous_snapshot.projectiles:
		previous_projectiles[projectile.projectile_id] = projectile
	var current_projectiles: Dictionary = {}
	for projectile in current_snapshot.projectiles:
		current_projectiles[projectile.projectile_id] = projectile
		if previous_projectiles.has(projectile.projectile_id):
			continue
		var source_position := _snapshot_entity_position(current_snapshot, projectile.source_entity_id, projectile.position)
		var target_position := _snapshot_entity_position(current_snapshot, projectile.target_entity_id, projectile.position)
		_spawn_combat_effect(&"muzzle", source_position, target_position - source_position, MUZZLE_FLASH_DURATION, projectile.faction_id, projectile.source_entity_id)
	for projectile_id in previous_projectiles:
		if current_projectiles.has(projectile_id):
			continue
		var projectile := previous_projectiles[projectile_id] as ProjectileSnapshot
		if not _snapshot_entity_took_damage(projectile.target_entity_id):
			continue
		var impact_position := _snapshot_entity_position(current_snapshot, projectile.target_entity_id, projectile.position)
		var destroyed := not _snapshot_entity_enabled(current_snapshot, projectile.target_entity_id)
		_spawn_combat_effect(&"destroyed" if destroyed else &"impact", impact_position, Vector2.ZERO, DESTRUCTION_EFFECT_DURATION if destroyed else IMPACT_FLASH_DURATION, projectile.faction_id, projectile.target_entity_id)
		var proxy := _proxies.get(projectile.target_entity_id) as UnitProxy
		if proxy != null:
			proxy.play_hit_feedback(destroyed)
		var building_proxy := _building_proxies.get(projectile.target_entity_id) as BuildingProxy
		if building_proxy != null:
			building_proxy.play_hit_feedback(destroyed)


func _spawn_combat_effect(kind: StringName, effect_position: Vector2, direction: Vector2, duration: float, faction_id: int, entity_id: int, label_key: StringName = &"") -> void:
	_combat_effects.append({
		"kind": kind,
		"position": effect_position,
		"direction": direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT,
		"duration": duration,
		"elapsed": 0.0,
		"faction_id": faction_id,
		"entity_id": entity_id,
		"label_key": label_key,
	})


func play_battle_feedback_effect(kind: StringName, effect_position: Vector2, faction_id: int, entity_id: int) -> void:
	var duration := 1.2
	if kind == &"headquarters":
		duration = 1.8
	elif kind == &"reinforcement":
		duration = 1.5
	elif kind in [&"engineering_route", &"deployment_started", &"deployment_complete", &"recon_support", &"fortify", &"fire_support", &"mobility", &"logistics", &"supply_node", &"region_secured", &"region_enemy", &"region_contested", &"region_capture", &"capture_interrupted", &"organization", &"withdrawal", &"effect_ended"]:
		duration = 3.2
	_spawn_combat_effect(kind, effect_position, Vector2.RIGHT, duration, faction_id, entity_id, _map_effect_label_key(kind))
	queue_redraw()


func _map_effect_label_key(kind: StringName) -> StringName:
	match kind:
		&"engagement": return &"MAP_FEEDBACK_ENGAGEMENT"
		&"focus": return &"MAP_FEEDBACK_FOCUS"
		&"pressure": return &"MAP_FEEDBACK_PRESSURE"
		&"reinforcement": return &"MAP_FEEDBACK_REINFORCEMENT"
		&"headquarters": return &"MAP_FEEDBACK_HEADQUARTERS"
		&"engineering_route": return &"MAP_FEEDBACK_ENGINEERING_ROUTE"
		&"deployment_started": return &"MAP_FEEDBACK_DEPLOYMENT_STARTED"
		&"deployment_complete": return &"MAP_FEEDBACK_DEPLOYMENT_COMPLETE"
		&"recon_support": return &"MAP_FEEDBACK_RECON"
		&"fortify": return &"MAP_FEEDBACK_FORTIFY"
		&"fire_support": return &"MAP_FEEDBACK_FIRE_SUPPORT"
		&"mobility": return &"MAP_FEEDBACK_MOBILITY"
		&"logistics": return &"MAP_FEEDBACK_LOGISTICS"
		&"effect_ended": return &"MAP_FEEDBACK_EFFECT_ENDED"
		&"supply_node": return &"MAP_FEEDBACK_SUPPLY_NODE"
		&"region_secured": return &"MAP_FEEDBACK_REGION_SECURED"
		&"region_enemy": return &"MAP_FEEDBACK_REGION_ENEMY"
		&"region_contested": return &"MAP_FEEDBACK_REGION_CONTESTED"
		&"region_capture": return &"MAP_FEEDBACK_REGION_CAPTURE"
		&"capture_interrupted": return &"MAP_FEEDBACK_CAPTURE_INTERRUPTED"
		&"organization": return &"MAP_FEEDBACK_ORGANIZATION"
		&"withdrawal": return &"MAP_FEEDBACK_WITHDRAWAL"
	return &""


func _snapshot_entity_position(snapshot: WorldSnapshot, entity_id: int, fallback: Vector2) -> Vector2:
	var unit := snapshot.get_unit(entity_id)
	if unit != null:
		return unit.position
	var building := snapshot.get_building(entity_id)
	return building.position if building != null else fallback


func _snapshot_entity_enabled(snapshot: WorldSnapshot, entity_id: int) -> bool:
	var unit := snapshot.get_unit(entity_id)
	if unit != null:
		return unit.enabled
	var building := snapshot.get_building(entity_id)
	return building != null and building.enabled


func _snapshot_entity_took_damage(entity_id: int) -> bool:
	var previous_unit := previous_snapshot.get_unit(entity_id)
	var current_unit := current_snapshot.get_unit(entity_id)
	if previous_unit != null and current_unit != null:
		return current_unit.health < previous_unit.health
	var previous_building := previous_snapshot.get_building(entity_id)
	var current_building := current_snapshot.get_building(entity_id)
	return previous_building != null and current_building != null and current_building.health < previous_building.health


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
	_detailed_units_enabled = current_snapshot.units.size() <= DETAILED_UNIT_LIMIT
	var active_ids: Dictionary = {}
	var proxies_changed := false
	for unit in current_snapshot.units:
		active_ids[unit.entity_id] = true
		if not _proxies.has(unit.entity_id):
			var proxy := UnitProxy.new()
			proxy.configure(unit.entity_id)
			proxy.z_index = 2
			proxy.scale = Vector2.ONE
			proxy.show_labels = _unit_labels_visible
			units_root.add_child(proxy)
			_proxies[unit.entity_id] = proxy
			proxies_changed = true
		var existing_proxy := _proxies[unit.entity_id] as UnitProxy
		if existing_proxy.visible != _detailed_units_enabled:
			existing_proxy.visible = _detailed_units_enabled
	for entity_id in _proxies.keys():
		if not active_ids.has(entity_id):
			(_proxies[entity_id] as UnitProxy).queue_free()
			_proxies.erase(entity_id)
			proxies_changed = true
	if proxies_changed or not selected_entity_ids.is_empty():
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
	for proxy_variant in _building_proxies.values():
		var building_proxy := proxy_variant as BuildingProxy
		building_proxy.selected = building_proxy.snapshot != null and building_proxy.snapshot.entity_id == selected_building_id


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
		var proxy := _proxies.get(unit.entity_id) as UnitProxy
		if proxy == null:
			continue
		var proxy_needs_detail := _detailed_units_enabled or proxy.selected or proxy.formation_member
		if apply_snapshot_data and proxy_needs_detail:
			proxy.apply_snapshot(unit)
		if proxy_needs_detail:
			if unit.is_visible_to_local_player and _previous_visible_unit_ids.has(unit.entity_id):
				from_position = _previous_unit_positions.get(unit.entity_id, unit.position) as Vector2
			proxy.position = from_position.lerp(
				unit.position,
				interpolation_alpha
			)
	var process_frame := Engine.get_process_frames()
	if apply_snapshot_data or process_frame != _last_batch_update_frame:
		_update_unit_batches()
		_update_projectile_batch()
		_last_batch_update_frame = process_frame


func _ensure_unit_batches() -> void:
	if _unit_bodies_batch != null:
		return
	_unit_bodies_batch = _create_batch(Vector2(46.0, 30.0), 2)
	_projectile_batch = _create_batch(Vector2(11.0, 5.0), 4)


func _create_batch(size: Vector2, layer: int) -> MultiMeshInstance2D:
	var instance := MultiMeshInstance2D.new()
	instance.z_index = layer
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var mesh := QuadMesh.new()
	mesh.size = size
	multimesh.mesh = mesh
	instance.multimesh = multimesh
	add_child(instance)
	return instance


func _update_unit_batches() -> void:
	if current_snapshot == null:
		return
	_ensure_unit_batches()
	_unit_bodies_batch.visible = not _detailed_units_enabled
	var count := current_snapshot.units.size()
	_resize_batch(_unit_bodies_batch, count)
	var required_buffer_size := count * MULTIMESH_TRANSFORM_COLOR_STRIDE
	if _unit_body_buffer.size() != required_buffer_size:
		_unit_body_buffer.resize(required_buffer_size)
	for index in range(count):
		var unit := current_snapshot.units[index]
		var from_position := unit.position
		if unit.is_visible_to_local_player and _previous_visible_unit_ids.has(unit.entity_id):
			from_position = _previous_unit_positions.get(unit.entity_id, unit.position) as Vector2
		var position := from_position.lerp(unit.position, interpolation_alpha)
		var remembered := unit.faction_id != SimulationWorld.LOCAL_PLAYER_ID and not unit.is_visible_to_local_player
		var body_color := UnitProxy.BODY_COLOR if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID else UnitProxy.ENEMY_COLOR
		var body_scale := Vector2.ONE
		match unit.tactical_role:
			UnitState.TacticalRole.SCOUT:
				body_scale = Vector2(0.72, 0.65)
			UnitState.TacticalRole.FIREPOWER:
				body_scale = Vector2(1.12, 0.62)
			UnitState.TacticalRole.ARMOR:
				body_scale = Vector2(1.16, 0.94)
			UnitState.TacticalRole.ASSAULT:
				body_scale = Vector2(0.92, 0.88)
		if not unit.enabled:
			body_color = UnitProxy.WRECK_COLOR
		elif remembered:
			body_color = Color(UnitProxy.LAST_SEEN_COLOR, 0.22)
		elif unit.max_health > 0.0:
			var health_ratio := clampf(unit.health / unit.max_health, 0.0, 1.0)
			body_color = body_color.darkened((1.0 - health_ratio) * 0.55)
			if unit.terrain_kind == UnitState.TerrainKind.OPEN:
				body_color = body_color.lerp(Color("d7b34c"), 0.12)
			elif unit.terrain_kind == UnitState.TerrainKind.RUINS:
				body_color = body_color.lerp(Color("9aa6a6"), 0.12)
			elif unit.terrain_kind == UnitState.TerrainKind.FOREST:
				body_color = body_color.lerp(Color("5fa36f"), 0.14)
		_write_batch_instance(_unit_body_buffer, index, position, body_scale, body_color)
	_unit_bodies_batch.multimesh.set_buffer(_unit_body_buffer)


func _update_projectile_batch() -> void:
	if current_snapshot == null:
		return
	_ensure_unit_batches()
	var count := current_snapshot.projectiles.size()
	_resize_batch(_projectile_batch, count)
	var required_buffer_size := count * MULTIMESH_TRANSFORM_COLOR_STRIDE
	if _projectile_buffer.size() != required_buffer_size:
		_projectile_buffer.resize(required_buffer_size)
	for index in range(count):
		var projectile := current_snapshot.projectiles[index]
		var position := projectile.position
		if _previous_projectile_positions.has(projectile.projectile_id):
			var previous_position := _previous_projectile_positions[projectile.projectile_id] as Vector2
			position = previous_position.lerp(projectile.position, interpolation_alpha)
		var color := Color("fff0a1") if projectile.faction_id == SimulationWorld.LOCAL_PLAYER_ID else Color("ff8a75")
		var visual_scale := 1.0
		_write_batch_instance(_projectile_buffer, index, position, Vector2.ONE * visual_scale, color)
	_projectile_batch.multimesh.set_buffer(_projectile_buffer)


func _resize_batch(batch: MultiMeshInstance2D, count: int) -> void:
	if batch.multimesh.instance_count != count:
		batch.multimesh.instance_count = count


func _write_batch_instance(
	buffer: PackedFloat32Array,
	index: int,
	position: Vector2,
	scale: Vector2,
	color: Color
) -> void:
	var offset := index * MULTIMESH_TRANSFORM_COLOR_STRIDE
	buffer[offset] = scale.x
	buffer[offset + 1] = 0.0
	buffer[offset + 2] = 0.0
	buffer[offset + 3] = position.x
	buffer[offset + 4] = 0.0
	buffer[offset + 5] = scale.y
	buffer[offset + 6] = 0.0
	buffer[offset + 7] = position.y
	buffer[offset + 8] = color.r
	buffer[offset + 9] = color.g
	buffer[offset + 10] = color.b
	buffer[offset + 11] = color.a


func _draw() -> void:
	_draw_projectile_trails()
	_draw_strategic_region_control()
	_draw_combat_effects()
	if build_preview_active:
		_draw_build_preview()
	if attack_targeting_active:
		_draw_attack_targeting()
	if formation_plan_active:
		_draw_formation_plan()
	if current_snapshot != null:
		_draw_commander_task_arrows()
		_draw_unit_selection_overlays()
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
	if commander_intent_active:
		_draw_commander_intent_preview()
	if commander_plan_active:
		_draw_commander_plan_preview()
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
		if formation != null:
			if formation.is_moving:
				var route_color := Color("ed704b") if unit.is_attack_moving else Color(0.95, 0.78, 0.28, 0.8)
				if formation.path.size() >= 2:
					draw_polyline(formation.path, route_color, 2.0)
				for member_id in formation.member_entity_ids:
					var member := current_snapshot.get_unit(member_id)
					if member != null:
						draw_circle(member.desired_position, 5.0, Color(0.41, 0.72, 0.77, 0.45))
				draw_arc(formation.target_position, 10.0, 0.0, TAU, 24, Color("f2c94c"), 2.0)
			if formation.has_deployment_line:
				var approach_origin := formation.anchor_position
				if formation.path.size() >= 2:
					approach_origin = formation.path[-2]
				_draw_deployment_envelope(
					formation.deployment_line_start,
					formation.deployment_line_end,
					approach_origin,
					_selected_formation_attack_range()
				)
		return
	if not unit.is_moving:
		return
	if unit.path.size() >= 2:
		draw_polyline(unit.path, Color(0.95, 0.78, 0.28, 0.8), 2.0)
	draw_circle(unit.move_target, 9.0, Color(0.95, 0.78, 0.28, 0.18))
	draw_arc(unit.move_target, 9.0, 0.0, TAU, 24, Color("f2c94c"), 2.0)


func _draw_projectile_trails() -> void:
	if current_snapshot == null:
		return
	var trail_scale := 1.0
	for projectile in current_snapshot.projectiles:
		var head := projectile.position
		var previous_position := _previous_projectile_positions.get(projectile.projectile_id, head) as Vector2
		head = previous_position.lerp(projectile.position, interpolation_alpha)
		var travel_direction := (projectile.position - previous_position).normalized()
		if travel_direction.is_zero_approx():
			var target_position := _snapshot_entity_position(current_snapshot, projectile.target_entity_id, head)
			travel_direction = (target_position - head).normalized()
		var color := Color("ffd75e") if projectile.faction_id == SimulationWorld.LOCAL_PLAYER_ID else Color("ff6b55")
		draw_line(head - travel_direction * 24.0 * trail_scale, head, Color(color, 0.26), 7.0 * trail_scale)
		draw_line(head - travel_direction * 18.0 * trail_scale, head, Color(color, 0.92), 2.2 * trail_scale)


func _draw_combat_effects() -> void:
	var visual_scale := 1.0
	for effect in _combat_effects:
		var duration := float(effect["duration"])
		var progress := clampf(float(effect["elapsed"]) / duration, 0.0, 1.0)
		var position_value := effect["position"] as Vector2
		var kind := effect["kind"] as StringName
		var faction_id := int(effect["faction_id"])
		var color := Color("ffd75e") if faction_id == SimulationWorld.LOCAL_PLAYER_ID else Color("ff725f")
		if kind == &"muzzle":
			var direction := effect["direction"] as Vector2
			var perpendicular := direction.orthogonal()
			var length := (22.0 + progress * 12.0) * visual_scale
			var width := (9.0 * (1.0 - progress) + 2.0) * visual_scale
			draw_colored_polygon(PackedVector2Array([
				position_value,
				position_value + direction * length + perpendicular * width,
				position_value + direction * length * 1.45,
				position_value + direction * length - perpendicular * width,
			]), Color(color, 1.0 - progress))
			draw_circle(position_value, (8.0 + progress * 8.0) * visual_scale, Color(1.0, 0.95, 0.7, (1.0 - progress) * 0.7))
		elif kind == &"impact":
			var fade := 1.0 - progress
			draw_circle(position_value, (7.0 + progress * 14.0) * visual_scale, Color(1.0, 0.88, 0.58, fade * 0.65))
			draw_arc(position_value, (10.0 + progress * 24.0) * visual_scale, 0.0, TAU, 28, Color(color, fade), 3.0 * visual_scale)
			for ray_index in range(6):
				var ray := Vector2.RIGHT.rotated(float(ray_index) * TAU / 6.0)
				draw_line(position_value + ray * 8.0 * visual_scale, position_value + ray * (18.0 + progress * 18.0) * visual_scale, Color(color, fade), 2.0 * visual_scale)
		elif kind == &"engagement":
			var fade := 1.0 - progress
			var radius := (20.0 + progress * 44.0) * visual_scale
			draw_arc(position_value, radius, 0.0, TAU, 36, Color(0.35, 0.95, 0.86, fade), 4.0 * visual_scale)
			for marker_index in range(4):
				var direction := Vector2.RIGHT.rotated(float(marker_index) * TAU / 4.0)
				draw_line(position_value + direction * (radius - 10.0 * visual_scale), position_value + direction * (radius + 8.0 * visual_scale), Color(0.7, 1.0, 0.94, fade), 4.0 * visual_scale)
		elif kind == &"focus":
			var fade := 1.0 - progress
			draw_arc(position_value, (34.0 - progress * 16.0) * visual_scale, 0.0, TAU, 36, Color(1.0, 0.82, 0.28, fade), 3.0 * visual_scale)
			for arrow_index in range(3):
				var direction := Vector2.RIGHT.rotated(float(arrow_index) * TAU / 3.0)
				var outer := position_value + direction * (54.0 - progress * 26.0) * visual_scale
				var inner := position_value + direction * 18.0 * visual_scale
				draw_line(outer, inner, Color(1.0, 0.82, 0.28, fade), 4.0 * visual_scale)
		elif kind == &"pressure":
			var fade := 1.0 - progress
			var radius := (28.0 + sin(progress * TAU * 3.0) * 7.0 + progress * 16.0) * visual_scale
			for segment in range(8):
				var start := float(segment) * TAU / 8.0
				draw_arc(position_value, radius, start, start + TAU / 16.0, 5, Color(1.0, 0.35, 0.22, fade), 4.0 * visual_scale)
		elif kind == &"reinforcement":
			var fade := 1.0 - progress
			var radius := (18.0 + progress * 54.0) * visual_scale
			draw_arc(position_value, radius, 0.0, TAU, 40, Color(0.35, 0.95, 0.72, fade), 4.0 * visual_scale)
			draw_line(position_value + Vector2(0.0, 18.0) * visual_scale, position_value + Vector2(0.0, -18.0) * visual_scale, Color(0.65, 1.0, 0.84, fade), 4.0 * visual_scale)
			draw_line(position_value + Vector2(-18.0, 0.0) * visual_scale, position_value + Vector2(18.0, 0.0) * visual_scale, Color(0.65, 1.0, 0.84, fade), 4.0 * visual_scale)
		elif kind == &"engineering_route":
			var fade := 1.0 - progress * 0.65
			var half_width := (62.0 + progress * 24.0) * visual_scale
			for rail_index in range(3):
				var y_offset := float(rail_index - 1) * 16.0 * visual_scale
				draw_line(position_value + Vector2(-half_width, y_offset), position_value + Vector2(half_width, y_offset), Color(0.28, 0.95, 0.84, fade), 6.0 * visual_scale)
			draw_arc(position_value, (42.0 + progress * 50.0) * visual_scale, 0.0, TAU, 40, Color(0.45, 1.0, 0.9, fade), 4.0 * visual_scale)
		elif kind == &"recon_support":
			var fade := 1.0 - progress
			for ring_index in range(3):
				var ring_progress := fposmod(progress + float(ring_index) / 3.0, 1.0)
				draw_arc(position_value, (24.0 + ring_progress * 96.0) * visual_scale, 0.0, TAU, 48, Color(0.34, 0.9, 1.0, fade), 3.0 * visual_scale)
		elif kind in [&"deployment_started", &"deployment_complete", &"fortify", &"mobility", &"logistics", &"effect_ended", &"supply_node", &"region_secured", &"region_enemy", &"region_contested", &"region_capture", &"capture_interrupted", &"organization", &"withdrawal", &"fire_support"]:
			var fade := 1.0 - progress * 0.75
			var operational_color := Color(0.35, 0.95, 0.72, fade)
			if kind in [&"fire_support", &"region_enemy", &"region_contested", &"organization", &"withdrawal"]:
				operational_color = Color(1.0, 0.52, 0.22, fade)
			elif kind == &"effect_ended":
				operational_color = Color(0.68, 0.72, 0.7, fade)
			draw_arc(position_value, (28.0 + progress * 54.0) * visual_scale, 0.0, TAU, 40, operational_color, 4.0 * visual_scale)
			var marker_size := 22.0 * visual_scale
			draw_line(position_value + Vector2(-marker_size, 0.0), position_value + Vector2(marker_size, 0.0), operational_color, 4.0 * visual_scale)
			draw_line(position_value + Vector2(0.0, -marker_size), position_value + Vector2(0.0, marker_size), operational_color, 4.0 * visual_scale)
		elif kind == &"headquarters":
			var pulse := 0.65 + sin(progress * TAU * 5.0) * 0.25
			var fade := 1.0 - progress * 0.5
			var half_size := (64.0 + progress * 14.0) * visual_scale
			draw_rect(Rect2(position_value - Vector2.ONE * half_size, Vector2.ONE * half_size * 2.0), Color(1.0, 0.22, 0.16, pulse * fade), false, 6.0 * visual_scale)
			draw_line(position_value + Vector2(0.0, -38.0) * visual_scale, position_value + Vector2(0.0, 14.0) * visual_scale, Color(1.0, 0.82, 0.58, fade), 7.0 * visual_scale)
			draw_circle(position_value + Vector2(0.0, 30.0) * visual_scale, 5.0 * visual_scale, Color(1.0, 0.82, 0.58, fade))
		else:
			var fade := 1.0 - progress
			draw_circle(position_value, (12.0 + progress * 30.0) * visual_scale, Color(1.0, 0.42, 0.12, fade * 0.42))
			draw_arc(position_value, (18.0 + progress * 46.0) * visual_scale, 0.0, TAU, 36, Color(1.0, 0.72, 0.2, fade), 4.0 * visual_scale)
			var seed_angle := float(int(effect["entity_id"]) % 17) * 0.19
			for shard_index in range(8):
				var shard := Vector2.RIGHT.rotated(seed_angle + float(shard_index) * TAU / 8.0)
				draw_line(position_value + shard * 10.0 * visual_scale, position_value + shard * (24.0 + progress * 48.0) * visual_scale, Color(color, fade), 3.0 * visual_scale)
		_draw_effect_label(effect, position_value, progress, visual_scale)


func _draw_effect_label(effect: Dictionary, position_value: Vector2, progress: float, visual_scale: float) -> void:
	var label_key := effect.get("label_key", &"") as StringName
	if label_key.is_empty():
		return
	var text_value := GameText.t(label_key)
	var font := ThemeDB.fallback_font
	var font_size := maxi(18, roundi(18.0 * visual_scale))
	var text_size := font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var label_center := position_value + Vector2(0.0, -78.0 * visual_scale)
	var padding := Vector2(12.0, 7.0) * visual_scale
	var label_rect := Rect2(label_center - Vector2(text_size.x * 0.5, text_size.y) - padding, text_size + padding * 2.0)
	var fade := clampf((1.0 - progress) * 1.7, 0.0, 1.0)
	draw_rect(label_rect, Color(0.025, 0.04, 0.04, 0.86 * fade), true)
	draw_rect(label_rect, Color(0.44, 0.9, 0.78, fade), false, maxf(2.0, 2.0 * visual_scale))
	draw_string(font, Vector2(label_rect.position.x + padding.x, label_rect.end.y - padding.y), text_value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.93, 1.0, 0.96, fade))


func _draw_strategic_region_control() -> void:
	if current_snapshot == null:
		return
	var visual_scale := 1.0
	for region in current_snapshot.strategic_regions:
		if not region.capturable:
			continue
		var owner_color := _region_faction_color(region.controller_faction_id)
		var center := region.position
		var point_radius := 52.0 * visual_scale
		draw_circle(center, point_radius, Color(owner_color, 0.28))
		draw_arc(center, point_radius, 0.0, TAU, 48, Color(owner_color, 0.96), 7.0 * visual_scale)
		draw_circle(center, 14.0 * visual_scale, Color(owner_color, 0.9))
		if region.contested:
			for segment in range(8):
				var start := float(segment) * TAU / 8.0
				draw_arc(center, point_radius + 10.0 * visual_scale, start, start + TAU / 18.0, 6, Color("f3c44e"), 5.0 * visual_scale)
		var capture_active := region.capture_faction_id != 0 and region.capture_faction_id != region.controller_faction_id and region.capture_progress > 0.0
		var bar_ratio := region.capture_progress if capture_active else (1.0 if region.controller_faction_id != 0 else 0.0)
		var bar_color := _region_faction_color(region.capture_faction_id if capture_active else region.controller_faction_id)
		var bar_size := Vector2(176.0, 16.0) * visual_scale
		var bar_position := center + Vector2(-bar_size.x * 0.5, 78.0 * visual_scale)
		draw_rect(Rect2(bar_position, bar_size), Color(0.025, 0.04, 0.045, 0.94), true)
		if bar_ratio > 0.0:
			draw_rect(Rect2(bar_position + Vector2.ONE * 3.0 * visual_scale, Vector2((bar_size.x - 6.0 * visual_scale) * bar_ratio, bar_size.y - 6.0 * visual_scale)), bar_color, true)
		draw_rect(Rect2(bar_position, bar_size), Color("f3c44e") if region.contested else Color(0.72, 0.79, 0.8, 0.9), false, 3.0 * visual_scale)
		var status_text := _region_status_text(region)
		var font := ThemeDB.fallback_font
		var font_size := maxi(18, roundi(18.0 * visual_scale))
		var text_size := font.get_string_size(status_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var text_position := center + Vector2(-text_size.x * 0.5, 122.0 * visual_scale)
		var text_background := Rect2(text_position + Vector2(-8.0, -text_size.y), text_size + Vector2(16.0, 8.0))
		draw_rect(text_background, Color(0.015, 0.025, 0.03, 0.84), true)
		draw_string(font, text_position, status_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.94, 0.97, 0.98))


func _region_faction_color(faction_id: int) -> Color:
	if faction_id == SimulationWorld.LOCAL_PLAYER_ID:
		return Color("3b8eea")
	if faction_id == SimulationWorld.ENEMY_PLAYER_ID:
		return Color("d95757")
	return Color("7f898e")


func _region_status_text(region: StrategicRegionSnapshot) -> String:
	if region.contested:
		return GameText.t(&"MAP_REGION_CONTESTED")
	if region.capture_faction_id != 0 and region.capture_faction_id != region.controller_faction_id and region.capture_progress > 0.0:
		var key := &"MAP_REGION_CAPTURING_LOCAL" if region.capture_faction_id == SimulationWorld.LOCAL_PLAYER_ID else &"MAP_REGION_CAPTURING_ENEMY"
		return GameText.t(key) % roundi(region.capture_progress * 100.0)
	if region.controller_faction_id == SimulationWorld.LOCAL_PLAYER_ID:
		return GameText.t(&"MAP_REGION_CONTROLLED_LOCAL")
	if region.controller_faction_id == SimulationWorld.ENEMY_PLAYER_ID:
		return GameText.t(&"MAP_REGION_CONTROLLED_ENEMY")
	return GameText.t(&"MAP_REGION_NEUTRAL")


func _draw_unit_selection_overlays() -> void:
	var visual_scale := 1.0
	for proxy_variant in _proxies.values():
		var proxy := proxy_variant as UnitProxy
		if proxy.formation_member and not proxy.selected:
			draw_arc(proxy.position, 28.0 * visual_scale, 0.0, TAU, 32, UnitProxy.FORMATION_COLOR, 1.5 * visual_scale)
		if proxy.selected:
			draw_arc(proxy.position, 30.0 * visual_scale, 0.0, TAU, 40, UnitProxy.SELECT_COLOR, 3.0 * visual_scale)
			var health_ratio := proxy.health_ratio
			draw_rect(
				Rect2(proxy.position + Vector2(-24.0, -35.0) * visual_scale, Vector2(48.0, 5.0) * visual_scale),
				UnitProxy.TRACK_COLOR,
				true
			)
			draw_rect(
				Rect2(
					proxy.position + Vector2(-23.0, -34.0) * visual_scale,
					Vector2(46.0 * health_ratio, 3.0) * visual_scale
				),
				Color("65c466") if health_ratio > 0.35 else Color("e35d5d"), true
			)


func _draw_commander_intent_preview() -> void:
	var direction := commander_intent_target - commander_intent_origin
	if direction.length_squared() <= 1.0:
		return
	direction = direction.normalized()
	var perpendicular := direction.orthogonal()
	var color := Color("6ee7c8")
	var endpoint := commander_intent_target - direction * 14.0
	draw_line(commander_intent_origin, endpoint, Color(color, 0.86), 4.0)
	draw_line(endpoint, endpoint - direction * 18.0 + perpendicular * 10.0, color, 4.0)
	draw_line(endpoint, endpoint - direction * 18.0 - perpendicular * 10.0, color, 4.0)
	draw_circle(commander_intent_origin, 7.0, Color(color, 0.25))
	draw_arc(commander_intent_target, 14.0, 0.0, TAU, 32, color, 3.0)


func _draw_commander_plan_preview() -> void:
	var points := PackedVector2Array([
		_commander_intent_origin(commander_plan_commander_id, commander_plan_target),
	])
	for waypoint in commander_plan_route:
		points.append(waypoint)
	if points.is_empty() or not points[-1].is_equal_approx(commander_plan_target):
		points.append(commander_plan_target)
	var color := _commander_task_color(commander_plan_commander_id)
	if points.size() >= 2:
		draw_polyline(points, Color(color, 0.92), 4.0)
	for index in range(1, points.size()):
		var point := points[index]
		draw_circle(point, 9.0, Color(color, 0.2))
		draw_arc(point, 9.0, 0.0, TAU, 24, color, 2.5)
		if index < points.size() - 1:
			draw_string(ThemeDB.fallback_font, point + Vector2(11.0, -8.0), str(index), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)


func _draw_commander_task_arrows() -> void:
	for commander in current_snapshot.commanders:
		if commander.faction_id != SimulationWorld.LOCAL_PLAYER_ID or commander.current_task_ids.is_empty():
			continue
		var origin := _commander_intent_origin(commander.definition_id, commander.target_position)
		var delta := commander.target_position - origin
		if delta.length_squared() <= 256.0:
			continue
		var direction := delta.normalized()
		var perpendicular := direction.orthogonal()
		var color := _commander_task_color(commander.definition_id)
		var endpoint := commander.target_position - direction * 11.0
		draw_line(origin, endpoint, Color(color, 0.48), 2.0)
		draw_line(endpoint, endpoint - direction * 13.0 + perpendicular * 7.0, Color(color, 0.72), 2.0)
		draw_line(endpoint, endpoint - direction * 13.0 - perpendicular * 7.0, Color(color, 0.72), 2.0)
		draw_circle(commander.target_position, 5.0, Color(color, 0.28))
		draw_arc(commander.target_position, 11.0, 0.0, TAU, 28, Color(color, 0.86), 2.0)


func _commander_task_color(commander_id: StringName) -> Color:
	match commander_id:
		&"bai_jiuyang":
			return Color("58c6d0")
		&"di_tian":
			return Color("e3b341")
		&"lin_mo":
			return Color("e56a54")
		_:
			return Color("8fe4df")


func _commander_intent_origin(commander_id: StringName, fallback: Vector2) -> Vector2:
	if current_snapshot == null:
		return fallback
	var commander := current_snapshot.get_commander(commander_id)
	if commander == null:
		return fallback
	var origin := Vector2.ZERO
	var formation_count := 0
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := current_snapshot.get_unit_card(unit_card_id)
		if unit_card == null or unit_card.formation_id == 0:
			continue
		var formation := current_snapshot.get_formation(unit_card.formation_id)
		if formation != null:
			origin += formation.anchor_position
			formation_count += 1
	if formation_count > 0:
		return origin / float(formation_count)
	var headquarters := current_snapshot.get_building(SimulationWorld.PLAYER_COMMAND_CENTER_ID)
	return headquarters.position if headquarters != null else fallback


func _draw_formation_plan() -> void:
	var points := PackedVector2Array()
	if current_snapshot != null and selected_entity_id != 0:
		var unit := current_snapshot.get_unit(selected_entity_id)
		var formation := current_snapshot.get_formation(unit.formation_id) if unit != null and unit.formation_id != 0 else null
		if formation != null:
			points.append(formation.anchor_position)
	for point in formation_plan_route:
		points.append(point)
	if formation_plan_drawing_line:
		points.append((formation_plan_line_start + formation_plan_line_end) * 0.5)
	if points.size() >= 2:
		draw_polyline(points, Color("f2c94c"), 3.0)
	for index in range(formation_plan_route.size()):
		var point := formation_plan_route[index]
		draw_circle(point, 9.0, Color(0.95, 0.78, 0.28, 0.16))
		draw_arc(point, 9.0, 0.0, TAU, 24, Color("f2c94c"), 2.0)
		draw_circle(point, 3.0, Color("f2c94c"))
	if formation_plan_drawing_line:
		var midpoint := (formation_plan_line_start + formation_plan_line_end) * 0.5
		var approach_origin := formation_plan_route[-1] if not formation_plan_route.is_empty() else _selected_formation_anchor(midpoint)
		_draw_deployment_envelope(
			formation_plan_line_start,
			formation_plan_line_end,
			approach_origin,
			_selected_formation_attack_range()
		)


func _selected_formation_anchor(fallback: Vector2) -> Vector2:
	if current_snapshot == null or selected_entity_id == 0:
		return fallback
	var selected := current_snapshot.get_unit(selected_entity_id)
	var formation := current_snapshot.get_formation(selected.formation_id) if selected != null and selected.formation_id != 0 else null
	return formation.anchor_position if formation != null else fallback


func _selected_formation_attack_range() -> float:
	if current_snapshot == null:
		return 0.0
	var maximum_range := 0.0
	for entity_id in selected_entity_ids:
		var member := current_snapshot.get_unit(entity_id)
		if member != null and member.enabled and member.can_attack:
			maximum_range = maxf(maximum_range, member.attack_range)
	return maximum_range


func _draw_deployment_envelope(line_start: Vector2, line_end: Vector2, approach_origin: Vector2, attack_range: float) -> void:
	var line_delta := line_end - line_start
	if line_delta.length_squared() < 1.0:
		return
	var midpoint := (line_start + line_end) * 0.5
	var tangent := line_delta.normalized()
	var facing := Vector2(-tangent.y, tangent.x)
	var approach := midpoint - approach_origin
	if not approach.is_zero_approx() and facing.dot(approach) < 0.0:
		facing = -facing
	draw_line(line_start, line_end, Color("58c6d0"), 5.0)
	for handle in [line_start, line_end]:
		draw_circle(handle, 10.0, Color(0.35, 0.78, 0.82, 0.16))
		draw_arc(handle, 10.0, 0.0, TAU, 24, Color("58c6d0"), 2.0)
	var arrow_tip := midpoint + facing * 66.0
	draw_line(midpoint, arrow_tip, Color("8fe4df"), 3.0)
	draw_colored_polygon(PackedVector2Array([
		arrow_tip,
		arrow_tip - facing.rotated(0.55) * 18.0,
		arrow_tip - facing.rotated(-0.55) * 18.0,
	]), Color("8fe4df"))
	if attack_range <= 0.0:
		return
	var facing_angle := facing.angle()
	var half_arc := deg_to_rad(38.0)
	var envelope_color := Color(0.35, 0.78, 0.72, 0.55)
	draw_arc(midpoint, attack_range, facing_angle - half_arc, facing_angle + half_arc, 36, envelope_color, 2.0)
	draw_dashed_line(midpoint, midpoint + facing.rotated(-half_arc) * attack_range, Color(envelope_color, 0.38), 1.5, 9.0)
	draw_dashed_line(midpoint, midpoint + facing.rotated(half_arc) * attack_range, Color(envelope_color, 0.38), 1.5, 9.0)


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
