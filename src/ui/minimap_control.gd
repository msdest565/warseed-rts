class_name MinimapControl
extends Control

const WORLD_RECT := SimulationWorld.BATTLEFIELD_BOUNDS

var snapshot: WorldSnapshot
var camera_controller: CameraController
var selected_entity_ids: Array[int] = []
var logic_grid := LogicGrid.create_test_map()
var dragging_camera: bool = false
var _contact_pings: Array[Dictionary] = []
var _last_camera_rect := Rect2()
var world_rect: Rect2 = WORLD_RECT
var situation: BattlefieldSituationSnapshot
var show_frontlines := true
var show_tasks := true
var show_threats := true
var show_intelligence := true
var _terrain_grid: LogicGrid
var _terrain_revision := -1
var _terrain_texture: ImageTexture

const CONTACT_PING_DURATION := 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)


func _process(delta: float) -> void:
	var needs_redraw := false
	for ping in _contact_pings:
		ping["remaining"] = float(ping["remaining"]) - delta
		needs_redraw = true
	_contact_pings = _contact_pings.filter(func(ping: Dictionary) -> bool: return float(ping["remaining"]) > 0.0)
	if camera_controller != null:
		var camera_rect := camera_controller.get_visible_world_rect()
		if camera_rect != _last_camera_rect:
			_last_camera_rect = camera_rect
			needs_redraw = true
	if needs_redraw:
		queue_redraw()


func add_contact_ping(world_position: Vector2) -> void:
	_contact_pings.append({"position": world_position, "remaining": CONTACT_PING_DURATION})
	queue_redraw()


func get_contact_ping_count() -> int:
	return _contact_pings.size()


func set_state(
	new_snapshot: WorldSnapshot,
	new_camera_controller: CameraController,
	new_selected_entity_ids: Array[int]
) -> void:
	snapshot = new_snapshot
	camera_controller = new_camera_controller
	selected_entity_ids = new_selected_entity_ids.duplicate()
	queue_redraw()


func set_world_rect(value: Rect2) -> void:
	world_rect = value if value.size.x > 0.0 and value.size.y > 0.0 else WORLD_RECT
	queue_redraw()


func set_situation(new_situation: BattlefieldSituationSnapshot) -> void:
	situation = new_situation
	queue_redraw()


func set_layer_visibility(frontlines: bool, tasks: bool, threats: bool, intelligence: bool) -> void:
	show_frontlines = frontlines
	show_tasks = tasks
	show_threats = threats
	show_intelligence = intelligence
	queue_redraw()


func get_content_rect() -> Rect2:
	var world_aspect := world_rect.size.x / world_rect.size.y
	var control_aspect := size.x / size.y if size.y > 0.0 else world_aspect
	var content_size := size
	if control_aspect > world_aspect:
		content_size.x = size.y * world_aspect
	else:
		content_size.y = size.x / world_aspect
	return Rect2((size - content_size) * 0.5, content_size)


func world_to_minimap(world_position: Vector2) -> Vector2:
	var content := get_content_rect()
	var normalized := (world_position - world_rect.position) / world_rect.size
	return content.position + normalized * content.size


func minimap_to_world(local_position: Vector2) -> Vector2:
	var content := get_content_rect()
	var clamped := local_position.clamp(content.position, content.end)
	var normalized := (clamped - content.position) / content.size
	return world_rect.position + normalized * world_rect.size


func navigate_camera(local_position: Vector2) -> void:
	if camera_controller != null:
		camera_controller.center_on_world_position(minimap_to_world(local_position))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			dragging_camera = mouse.pressed
			if mouse.pressed:
				navigate_camera(mouse.position)
			accept_event()
	elif event is InputEventMouseMotion and dragging_camera:
		navigate_camera((event as InputEventMouseMotion).position)
		accept_event()


func _draw() -> void:
	var content := get_content_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.035, 0.04, 0.94), true)
	draw_rect(content, Color("162326"), true)
	_update_terrain_texture()
	var terrain_origin := logic_grid.cell_to_world(Vector2i.ZERO) - Vector2.ONE * LogicGrid.CELL_SIZE * 0.5
	var terrain_start := world_to_minimap(terrain_origin)
	var terrain_end := world_to_minimap(terrain_origin + Vector2(logic_grid.grid_size) * LogicGrid.CELL_SIZE)
	draw_texture_rect(_terrain_texture, Rect2(terrain_start, terrain_end - terrain_start), false)
	if snapshot != null:
		for region in snapshot.strategic_regions:
			if not region.capturable:
				continue
			var region_color := Color("7f898e")
			if region.contested:
				region_color = Color("f3c44e")
			elif region.controller_faction_id == SimulationWorld.LOCAL_PLAYER_ID:
				region_color = Color("3b8eea")
			elif region.controller_faction_id != 0:
				region_color = Color("d95c5c")
			var point := world_to_minimap(region.position)
			draw_circle(point, 6.0, Color(region_color, 0.45), true)
			draw_circle(point, 6.0, region_color, false, 2.0)
			if region.capture_faction_id != 0 and region.capture_faction_id != region.controller_faction_id and region.capture_progress > 0.0:
				var capture_color := Color("3b8eea") if region.capture_faction_id == SimulationWorld.LOCAL_PLAYER_ID else Color("d95757")
				draw_arc(point, 8.5, -PI * 0.5, -PI * 0.5 + TAU * region.capture_progress, 24, capture_color, 2.5)
		for unit in snapshot.units:
			if not unit.enabled:
				continue
			var is_local := unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID
			var point := world_to_minimap(unit.position)
			if not is_local and not unit.is_visible_to_local_player:
				draw_rect(Rect2(point - Vector2.ONE * 2.0, Vector2.ONE * 4.0), Color(0.85, 0.36, 0.36, 0.34), false, 1.0)
				continue
			var color := Color.WHITE if selected_entity_ids.has(unit.entity_id) else (Color("42b7ad") if is_local else Color("d95c5c"))
			draw_circle(point, 3.5 if selected_entity_ids.has(unit.entity_id) else 2.5, color)
	_draw_situation()
	for ping in _contact_pings:
		var progress := 1.0 - float(ping["remaining"]) / CONTACT_PING_DURATION
		var radius := lerpf(4.0, 16.0, progress)
		var alpha := 1.0 - progress
		draw_arc(world_to_minimap(ping["position"]), radius, 0.0, TAU, 32, Color(1.0, 0.76, 0.2, alpha), 2.0)
	if camera_controller != null:
		var camera_rect := camera_controller.get_visible_world_rect().intersection(world_rect)
		var camera_start := world_to_minimap(camera_rect.position)
		var camera_end := world_to_minimap(camera_rect.end)
		draw_rect(Rect2(camera_start, camera_end - camera_start), Color(0.96, 0.84, 0.38, 0.95), false, 1.5)
	draw_rect(content, Color("91a9ad"), false, 2.0)


func _update_terrain_texture() -> void:
	if _terrain_grid == logic_grid and _terrain_revision == logic_grid.revision:
		return
	var terrain := Image.create(logic_grid.grid_size.x, logic_grid.grid_size.y, false, Image.FORMAT_RGBA8)
	terrain.fill(Color.TRANSPARENT)
	for cell in logic_grid.get_blocked_cells():
		terrain.set_pixelv(cell, Color("53676b"))
	_terrain_texture = ImageTexture.create_from_image(terrain)
	_terrain_grid = logic_grid
	_terrain_revision = logic_grid.revision


func _draw_situation() -> void:
	if situation == null:
		return
	if show_intelligence:
		for zone in situation.uncertainty_zones:
			if int(zone["state"]) != FactionKnowledge.CellState.UNEXPLORED:
				continue
			var world_zone := zone["rect"] as Rect2
			var top_left := world_to_minimap(world_zone.position)
			var bottom_right := world_to_minimap(world_zone.end)
			draw_rect(Rect2(top_left, bottom_right - top_left), Color(0.01, 0.018, 0.02, 0.16), true)
	if show_tasks:
		for axis in situation.task_axes:
			var route := axis["route"] as PackedVector2Array
			var points := PackedVector2Array()
			for world_point in route:
				points.append(world_to_minimap(world_point))
			if points.size() >= 2:
				draw_polyline(points, Color("52d1c8"), 1.5)
	if show_frontlines:
		for segment in situation.frontline_segments:
			draw_line(world_to_minimap(segment["start"]), world_to_minimap(segment["end"]), Color("f1c75b"), 2.0)
	if show_threats:
		for threat in situation.threat_zones:
			var point := world_to_minimap(threat["position"])
			var radius := maxf(4.0, float(threat["radius"]) / world_rect.size.x * get_content_rect().size.x)
			var color := Color("ef6758") if bool(threat["known_threat"]) else Color("9aa7a2")
			draw_circle(point, radius, Color(color, 0.12))
			draw_arc(point, radius, 0.0, TAU, 20, Color(color, 0.8), 1.5)
