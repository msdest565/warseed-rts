class_name UnitProxy
extends Node2D

const BODY_COLOR := Color("3aa7a3")
const ACCENT_COLOR := Color("d7e3bb")
const TRACK_COLOR := Color("172126")
const SELECT_COLOR := Color("f2c94c")
const FORMATION_COLOR := Color("69b7c4")
const ENEMY_COLOR := Color("d95c5c")
const WRECK_COLOR := Color("4a5558")

var entity_id: int
var faction_id: int = SimulationWorld.LOCAL_PLAYER_ID
var health_ratio: float = 1.0
var enabled: bool = true
var attack_target_entity_id: int = 0
var definition_id: StringName = &"scout_vehicle"
var selected: bool = false:
	set(value):
		selected = value
		queue_redraw()
var formation_member: bool = false:
	set(value):
		formation_member = value
		queue_redraw()


func configure(new_entity_id: int) -> void:
	entity_id = new_entity_id
	queue_redraw()


func apply_snapshot(unit: UnitSnapshot) -> void:
	faction_id = unit.faction_id
	health_ratio = clampf(unit.health / unit.max_health, 0.0, 1.0) if unit.max_health > 0.0 else 0.0
	enabled = unit.enabled
	attack_target_entity_id = unit.attack_target_entity_id
	definition_id = unit.definition_id
	queue_redraw()


func _draw() -> void:
	if formation_member and not selected:
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 40, FORMATION_COLOR, 1.5)
	if selected:
		draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 48, SELECT_COLOR, 3.0)

	if not enabled:
		draw_rect(Rect2(-22.0, -13.0, 44.0, 26.0), WRECK_COLOR, true)
		draw_line(Vector2(-16.0, -9.0), Vector2(16.0, 9.0), TRACK_COLOR, 4.0)
		draw_line(Vector2(-16.0, 9.0), Vector2(16.0, -9.0), TRACK_COLOR, 4.0)
	else:
		draw_rect(Rect2(-24.0, -18.0, 48.0, 8.0), TRACK_COLOR, true)
		draw_rect(Rect2(-24.0, 10.0, 48.0, 8.0), TRACK_COLOR, true)
		var body_color := BODY_COLOR if faction_id == SimulationWorld.LOCAL_PLAYER_ID else ENEMY_COLOR
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(-20.0, -13.0),
				Vector2(14.0, -13.0),
				Vector2(23.0, 0.0),
				Vector2(14.0, 13.0),
				Vector2(-20.0, 13.0),
			]),
			body_color
		)
		draw_circle(Vector2(0.0, 0.0), 8.0, ACCENT_COLOR)
		if definition_id == &"missile_vehicle":
			draw_line(Vector2(-8.0, -6.0), Vector2(25.0, -10.0), Color("f2c94c"), 5.0)
			draw_line(Vector2(-8.0, 6.0), Vector2(25.0, 10.0), Color("f2c94c"), 5.0)
		elif definition_id == &"harvester":
			draw_rect(Rect2(-18.0, -10.0, 18.0, 20.0), Color("d8a83e"), true)
		elif definition_id == &"engineer_vehicle":
			draw_line(Vector2(-6.0, 10.0), Vector2(18.0, -12.0), Color("7fd5cc"), 5.0)
		else:
			draw_line(Vector2.ZERO, Vector2(23.0, 0.0), ACCENT_COLOR, 4.0)
		draw_rect(Rect2(-24.0, -28.0, 48.0, 5.0), Color("172126"), true)
		draw_rect(Rect2(-23.0, -27.0, 46.0 * health_ratio, 3.0), Color("65c466") if health_ratio > 0.35 else Color("e35d5d"), true)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-10.0, 42.0),
		"E%d" % entity_id,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		14,
		Color("dce8e8")
	)
