class_name CameraController
extends Camera2D

const WORLD_RECT := SimulationWorld.BATTLEFIELD_BOUNDS
const MIN_ZOOM := 0.05
const MAX_ZOOM := 2.5
const ZOOM_STEP := 0.1
const PAN_SPEED := 600.0
const OVERSCROLL_LEFT_SCREEN := 96.0
const OVERSCROLL_TOP_SCREEN := 72.0
const OVERSCROLL_RIGHT_SCREEN := 96.0
const OVERSCROLL_BOTTOM_SCREEN := 260.0

var middle_dragging: bool = false
var active_screen_rect: Rect2
var world_rect: Rect2 = WORLD_RECT


func _process(delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_physical_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		direction.y += 1.0
	if not direction.is_zero_approx():
		position += direction.normalized() * PAN_SPEED * delta / zoom.x
		clamp_to_bounds()


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_MIDDLE:
			if mouse.pressed:
				if not is_screen_position_over_map(mouse.position):
					return false
				middle_dragging = true
				return true
			var was_dragging := middle_dragging
			middle_dragging = false
			return was_dragging
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			if not is_screen_position_over_map(mouse.position):
				return false
			zoom_at_screen_position(mouse.position, ZOOM_STEP)
			return true
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not is_screen_position_over_map(mouse.position):
				return false
			zoom_at_screen_position(mouse.position, -ZOOM_STEP)
			return true
	elif event is InputEventMouseMotion and middle_dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		clamp_to_bounds()
		return true
	return false


func is_screen_position_over_map(screen_position: Vector2) -> bool:
	return _effective_screen_rect().has_point(screen_position)


func screen_to_world(screen_position: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport != null:
		return viewport.get_canvas_transform().affine_inverse() * screen_position
	return _active_world_center() + (screen_position - _effective_screen_rect().get_center()) / zoom


func world_to_screen(world_position: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport != null:
		return viewport.get_canvas_transform() * world_position
	return _effective_screen_rect().get_center() + (world_position - _active_world_center()) * zoom


func zoom_at_screen_position(screen_position: Vector2, delta_zoom: float) -> void:
	var world_before := screen_to_world(screen_position)
	var next_zoom := clampf(zoom.x + delta_zoom, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2.ONE * next_zoom
	force_update_scroll()
	var world_after := screen_to_world(screen_position)
	position += world_before - world_after
	clamp_to_bounds()


func center_on_world_position(world_position: Vector2) -> void:
	position = world_position - _active_screen_offset_world()
	clamp_to_bounds()


func get_visible_world_rect() -> Rect2:
	var screen_rect := _effective_screen_rect()
	var visible_size := screen_rect.size / zoom
	return Rect2(_active_world_center() - visible_size * 0.5, visible_size)


func set_active_screen_rect(screen_rect: Rect2) -> void:
	active_screen_rect = screen_rect


func clear_active_screen_rect() -> void:
	active_screen_rect = Rect2()


func fit_world_in_screen_rect(screen_rect: Rect2, padding: float = 0.94) -> void:
	set_active_screen_rect(screen_rect)
	if screen_rect.size.x <= 0.0 or screen_rect.size.y <= 0.0:
		return
	var fit_zoom := minf(
		screen_rect.size.x / world_rect.size.x,
		screen_rect.size.y / world_rect.size.y
	) * clampf(padding, 0.5, 1.0)
	zoom = Vector2.ONE * clampf(fit_zoom, MIN_ZOOM, MAX_ZOOM)
	position = world_rect.get_center() - _active_screen_offset_world()
	force_update_scroll()
	clamp_to_bounds()


func set_world_rect(value: Rect2) -> void:
	if value.size.x <= 0.0 or value.size.y <= 0.0:
		world_rect = WORLD_RECT
	else:
		world_rect = value
	clamp_to_bounds()


func get_world_rect() -> Rect2:
	return world_rect


func clamp_to_bounds() -> void:
	if active_screen_rect.size.x <= 0.0 or active_screen_rect.size.y <= 0.0:
		var limits := get_center_limits(_viewport_size())
		position.x = world_rect.get_center().x if limits.size.x < 0.0 else clampf(position.x, limits.position.x, limits.end.x)
		position.y = world_rect.get_center().y if limits.size.y < 0.0 else clampf(position.y, limits.position.y, limits.end.y)
		return
	var half_visible := active_screen_rect.size * 0.5 / zoom
	var minimum := world_rect.position + half_visible
	var maximum := world_rect.end - half_visible
	var current_center := _active_world_center()
	var target_center := current_center
	target_center.x = world_rect.get_center().x if maximum.x < minimum.x else clampf(current_center.x, minimum.x, maximum.x)
	target_center.y = world_rect.get_center().y if maximum.y < minimum.y else clampf(current_center.y, minimum.y, maximum.y)
	position += target_center - current_center


func get_center_limits(viewport_size: Vector2) -> Rect2:
	var half_visible := viewport_size * 0.5 / zoom
	var minimum := world_rect.position + half_visible - Vector2(OVERSCROLL_LEFT_SCREEN, OVERSCROLL_TOP_SCREEN) / zoom
	var maximum := world_rect.end - half_visible + Vector2(OVERSCROLL_RIGHT_SCREEN, OVERSCROLL_BOTTOM_SCREEN) / zoom
	return Rect2(minimum, maximum - minimum)


func _effective_screen_rect() -> Rect2:
	if active_screen_rect.size.x > 0.0 and active_screen_rect.size.y > 0.0:
		return active_screen_rect
	return Rect2(Vector2.ZERO, _viewport_size())


func _active_screen_offset_world() -> Vector2:
	var viewport_center := _viewport_size() * 0.5
	return (_effective_screen_rect().get_center() - viewport_center) / zoom


func _active_world_center() -> Vector2:
	return position + _active_screen_offset_world()


func _viewport_size() -> Vector2:
	if is_inside_tree():
		return get_viewport_rect().size
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	)
