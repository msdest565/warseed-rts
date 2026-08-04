class_name CameraController
extends Camera2D

const WORLD_RECT := Rect2(Vector2.ZERO, Vector2(3072.0, 2048.0))
const MIN_ZOOM := 1.0
const MAX_ZOOM := 2.5
const ZOOM_STEP := 0.2
const PAN_SPEED := 600.0
const OVERSCROLL_LEFT_SCREEN := 96.0
const OVERSCROLL_TOP_SCREEN := 72.0
const OVERSCROLL_RIGHT_SCREEN := 96.0
const OVERSCROLL_BOTTOM_SCREEN := 260.0

var middle_dragging: bool = false


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
			middle_dragging = mouse.pressed
			return true
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at_screen_position(mouse.position, ZOOM_STEP)
			return true
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at_screen_position(mouse.position, -ZOOM_STEP)
			return true
	elif event is InputEventMouseMotion and middle_dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		clamp_to_bounds()
		return true
	return false


func screen_to_world(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position


func world_to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position


func zoom_at_screen_position(screen_position: Vector2, delta_zoom: float) -> void:
	var world_before := screen_to_world(screen_position)
	var next_zoom := clampf(zoom.x + delta_zoom, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2.ONE * next_zoom
	force_update_scroll()
	var world_after := screen_to_world(screen_position)
	position += world_before - world_after
	clamp_to_bounds()


func center_on_world_position(world_position: Vector2) -> void:
	position = world_position
	clamp_to_bounds()


func get_visible_world_rect() -> Rect2:
	var visible_size := get_viewport_rect().size / zoom
	return Rect2(position - visible_size * 0.5, visible_size)


func clamp_to_bounds() -> void:
	var limits := get_center_limits(get_viewport_rect().size)
	position.x = WORLD_RECT.get_center().x if limits.size.x < 0.0 else clampf(position.x, limits.position.x, limits.end.x)
	position.y = WORLD_RECT.get_center().y if limits.size.y < 0.0 else clampf(position.y, limits.position.y, limits.end.y)


func get_center_limits(viewport_size: Vector2) -> Rect2:
	var half_visible := viewport_size * 0.5 / zoom
	var minimum := WORLD_RECT.position + half_visible - Vector2(OVERSCROLL_LEFT_SCREEN, OVERSCROLL_TOP_SCREEN) / zoom
	var maximum := WORLD_RECT.end - half_visible + Vector2(OVERSCROLL_RIGHT_SCREEN, OVERSCROLL_BOTTOM_SCREEN) / zoom
	return Rect2(minimum, maximum - minimum)
