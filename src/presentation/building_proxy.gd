class_name BuildingProxy
extends Node2D

var snapshot: BuildingSnapshot
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()


func apply_snapshot(building: BuildingSnapshot) -> void:
	snapshot = building
	position = building.position
	queue_redraw()


func _draw() -> void:
	if snapshot == null:
		return
	if snapshot.faction_id != SimulationWorld.LOCAL_PLAYER_ID and not snapshot.is_visible:
		var marker_size := Vector2(72.0, 52.0)
		draw_rect(Rect2(-marker_size * 0.5, marker_size), Color(0.65, 0.25, 0.25, 0.12), true)
		draw_rect(Rect2(-marker_size * 0.5, marker_size), Color(0.85, 0.36, 0.36, 0.34), false, 2.0)
		return
	var color := Color("3b8f87") if snapshot.faction_id == SimulationWorld.LOCAL_PLAYER_ID else Color("a74747")
	if not snapshot.enabled:
		color = Color("4a5558")
	var size := Vector2(86.0, 62.0)
	if snapshot.definition_id == &"command_center":
		size = Vector2(110.0, 82.0)
	elif snapshot.definition_id == &"forward_support_station":
		size = Vector2(72.0, 54.0)
	draw_rect(Rect2(-size * 0.5, size), color, true)
	draw_rect(Rect2(-size * 0.5, size), Color("d7e3bb"), false, 3.0)
	if selected:
		draw_rect(Rect2(-size * 0.5 - Vector2(6.0, 6.0), size + Vector2(12.0, 12.0)), Color("f2c94c"), false, 3.0)
	var health_ratio := snapshot.health / snapshot.max_health if snapshot.max_health > 0.0 else 0.0
	draw_rect(Rect2(-size.x * 0.5, -size.y * 0.5 - 10.0, size.x, 5.0), Color("172126"), true)
	draw_rect(Rect2(-size.x * 0.5 + 1.0, -size.y * 0.5 - 9.0, (size.x - 2.0) * health_ratio, 3.0), Color("65c466"), true)
	draw_string(ThemeDB.fallback_font, Vector2(-size.x * 0.75, size.y * 0.5 + 17.0), GameText.building_name(snapshot.definition_id), HORIZONTAL_ALIGNMENT_CENTER, size.x * 1.5, 11, Color("dce8e8"))
	draw_string(ThemeDB.fallback_font, Vector2(-size.x * 0.75, size.y * 0.5 + 31.0), GameText.faction_name(snapshot.faction_id), HORIZONTAL_ALIGNMENT_CENTER, size.x * 1.5, 10, Color("9fb4b5"))
	if snapshot.under_construction:
		var progress := 1.0 - float(snapshot.construction_ticks_remaining) / maxf(1.0, snapshot.construction_ticks_total)
		draw_rect(Rect2(-size.x * 0.5, size.y * 0.5 + 35.0, size.x, 4.0), Color("172126"), true)
		draw_rect(Rect2(-size.x * 0.5, size.y * 0.5 + 35.0, size.x * progress, 4.0), Color("f2c94c"), true)
	if not snapshot.production_definition_id.is_empty():
		draw_arc(Vector2.ZERO, size.x * 0.32, 0.0, TAU, 30, Color("f2c94c"), 3.0)
