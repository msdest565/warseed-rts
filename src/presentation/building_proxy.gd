class_name BuildingProxy
extends Node2D

var snapshot: BuildingSnapshot


func apply_snapshot(building: BuildingSnapshot) -> void:
	snapshot = building
	position = building.position
	queue_redraw()


func _draw() -> void:
	if snapshot == null:
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
	var health_ratio := snapshot.health / snapshot.max_health if snapshot.max_health > 0.0 else 0.0
	draw_rect(Rect2(-size.x * 0.5, -size.y * 0.5 - 10.0, size.x, 5.0), Color("172126"), true)
	draw_rect(Rect2(-size.x * 0.5 + 1.0, -size.y * 0.5 - 9.0, (size.x - 2.0) * health_ratio, 3.0), Color("65c466"), true)
	draw_string(ThemeDB.fallback_font, Vector2(-size.x * 0.5, size.y * 0.5 + 18.0), str(snapshot.definition_id), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("dce8e8"))
	if not snapshot.production_definition_id.is_empty():
		draw_arc(Vector2.ZERO, size.x * 0.32, 0.0, TAU, 30, Color("f2c94c"), 3.0)
