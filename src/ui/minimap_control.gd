class_name MinimapControl
extends Control

const WORLD_RECT := Rect2(Vector2.ZERO, Vector2(3072.0, 2048.0))

var snapshot: WorldSnapshot
var camera_controller: CameraController
var selected_entity_ids: Array[int] = []
var logic_grid := LogicGrid.create_test_map()
var dragging_camera: bool = false
var _contact_pings: Array[Dictionary] = []
var _last_camera_rect := Rect2()

const CONTACT_PING_DURATION := 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
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


func get_content_rect() -> Rect2:
	var world_aspect := WORLD_RECT.size.x / WORLD_RECT.size.y
	var control_aspect := size.x / size.y if size.y > 0.0 else world_aspect
	var content_size := size
	if control_aspect > world_aspect:
		content_size.x = size.y * world_aspect
	else:
		content_size.y = size.x / world_aspect
	return Rect2((size - content_size) * 0.5, content_size)


func world_to_minimap(world_position: Vector2) -> Vector2:
	var content := get_content_rect()
	var normalized := (world_position - WORLD_RECT.position) / WORLD_RECT.size
	return content.position + normalized * content.size


func minimap_to_world(local_position: Vector2) -> Vector2:
	var content := get_content_rect()
	var clamped := local_position.clamp(content.position, content.end)
	var normalized := (clamped - content.position) / content.size
	return WORLD_RECT.position + normalized * WORLD_RECT.size


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
	for cell in logic_grid.get_blocked_cells():
		var cell_world_rect := Rect2(logic_grid.cell_to_world(cell) - Vector2.ONE * LogicGrid.CELL_SIZE * 0.5, Vector2.ONE * LogicGrid.CELL_SIZE)
		var top_left := world_to_minimap(cell_world_rect.position)
		var bottom_right := world_to_minimap(cell_world_rect.end)
		draw_rect(Rect2(top_left, bottom_right - top_left), Color("53676b"), true)
	if snapshot != null:
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
	for ping in _contact_pings:
		var progress := 1.0 - float(ping["remaining"]) / CONTACT_PING_DURATION
		var radius := lerpf(4.0, 16.0, progress)
		var alpha := 1.0 - progress
		draw_arc(world_to_minimap(ping["position"]), radius, 0.0, TAU, 32, Color(1.0, 0.76, 0.2, alpha), 2.0)
	if camera_controller != null:
		var camera_rect := camera_controller.get_visible_world_rect().intersection(WORLD_RECT)
		var camera_start := world_to_minimap(camera_rect.position)
		var camera_end := world_to_minimap(camera_rect.end)
		draw_rect(Rect2(camera_start, camera_end - camera_start), Color(0.96, 0.84, 0.38, 0.95), false, 1.5)
	draw_rect(content, Color("91a9ad"), false, 2.0)
