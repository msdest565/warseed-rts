class_name OreFieldProxy
extends Node2D

var ore_remaining: int


func apply_snapshot(ore_field: OreFieldSnapshot) -> void:
	position = ore_field.position
	ore_remaining = ore_field.ore_remaining
	queue_redraw()


func _draw() -> void:
	var radius := 30.0 if ore_remaining > 0 else 12.0
	draw_circle(Vector2.ZERO, radius, Color("d8a83e"))
	draw_circle(Vector2(-16.0, 8.0), radius * 0.55, Color("f2c94c"))
	draw_string(ThemeDB.fallback_font, Vector2(-28.0, 48.0), "ORE %d" % ore_remaining, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("f8e7ae"))
