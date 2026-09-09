class_name UnitProxy
extends Node2D

const BODY_COLOR := Color("3aa7a3")
const ACCENT_COLOR := Color("d7e3bb")
const TRACK_COLOR := Color("172126")
const SELECT_COLOR := Color("f2c94c")
const FORMATION_COLOR := Color("69b7c4")
const ENEMY_COLOR := Color("d95c5c")
const WRECK_COLOR := Color("4a5558")
const LAST_SEEN_COLOR := Color(0.95, 0.68, 0.28, 0.62)

var entity_id: int
var faction_id: int = SimulationWorld.LOCAL_PLAYER_ID
var health_ratio: float = 1.0
var enabled: bool = true
var attack_target_entity_id: int = 0
var definition_id: StringName = &"scout_vehicle"
var cargo_ore: int = 0
var work_kind: UnitState.WorkKind = UnitState.WorkKind.NONE
var currently_visible: bool = true
var terrain_kind: UnitState.TerrainKind = UnitState.TerrainKind.NONE
var intel_freshness: float = 1.0
var hit_flash_remaining: float = 0.0
var destruction_flash_remaining: float = 0.0
var selected: bool = false:
	set(value):
		if selected == value:
			return
		selected = value
		queue_redraw()
var formation_member: bool = false:
	set(value):
		if formation_member == value:
			return
		formation_member = value
		queue_redraw()
var show_labels: bool = true:
	set(value):
		if show_labels == value:
			return
		show_labels = value
		queue_redraw()


func configure(new_entity_id: int) -> void:
	entity_id = new_entity_id
	queue_redraw()


func apply_snapshot(unit: UnitSnapshot) -> void:
	var next_health_ratio := clampf(unit.health / unit.max_health, 0.0, 1.0) if unit.max_health > 0.0 else 0.0
	var redraw_needed := faction_id != unit.faction_id \
		or not is_equal_approx(health_ratio, next_health_ratio) \
		or enabled != unit.enabled \
		or definition_id != unit.definition_id \
		or cargo_ore != unit.cargo_ore \
		or work_kind != unit.work_kind \
		or currently_visible != (unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID or unit.is_visible_to_local_player) \
		or terrain_kind != unit.terrain_kind \
		or not is_equal_approx(intel_freshness, unit.intel_freshness)
	faction_id = unit.faction_id
	health_ratio = next_health_ratio
	enabled = unit.enabled
	attack_target_entity_id = unit.attack_target_entity_id
	definition_id = unit.definition_id
	cargo_ore = unit.cargo_ore
	work_kind = unit.work_kind
	currently_visible = unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID or unit.is_visible_to_local_player
	terrain_kind = unit.terrain_kind
	intel_freshness = unit.intel_freshness
	if redraw_needed:
		queue_redraw()


func play_hit_feedback(destroyed: bool = false) -> void:
	hit_flash_remaining = 0.18
	if destroyed:
		destruction_flash_remaining = 0.5
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if hit_flash_remaining <= 0.0 and destruction_flash_remaining <= 0.0:
		set_process(false)
		return
	hit_flash_remaining = maxf(0.0, hit_flash_remaining - delta)
	destruction_flash_remaining = maxf(0.0, destruction_flash_remaining - delta)
	queue_redraw()


func _draw() -> void:
	if is_last_seen_contact():
		_draw_last_seen_marker()
		return
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
		_draw_faction_marker()
		if definition_id == &"missile_vehicle":
			draw_line(Vector2(-8.0, -6.0), Vector2(25.0, -10.0), Color("f2c94c"), 5.0)
			draw_line(Vector2(-8.0, 6.0), Vector2(25.0, 10.0), Color("f2c94c"), 5.0)
		elif definition_id == &"scout_vehicle":
			draw_line(Vector2(-4.0, 0.0), Vector2(22.0, 0.0), Color("7fd5cc"), 3.0)
			draw_arc(Vector2(5.0, 0.0), 13.0, -0.8, 0.8, 12, Color("7fd5cc"), 3.0)
		elif definition_id == &"harvester":
			draw_rect(Rect2(-18.0, -10.0, 18.0, 20.0), Color("d8a83e"), true)
			if cargo_ore > 0:
				draw_circle(Vector2(-9.0, 0.0), 6.0, Color("f2c94c"))
		elif definition_id == &"engineer_vehicle":
			draw_line(Vector2(-6.0, 10.0), Vector2(18.0, -12.0), Color("7fd5cc"), 5.0)
			if work_kind != UnitState.WorkKind.NONE:
				draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 28, Color("f2c94c"), 2.0)
		elif definition_id == &"supply_truck":
			draw_rect(Rect2(-16.0, -10.0, 27.0, 20.0), Color("d6b74c"), true)
			draw_line(Vector2(-11.0, -5.0), Vector2(6.0, -5.0), Color("f3e7a2"), 3.0)
			draw_line(Vector2(-11.0, 5.0), Vector2(6.0, 5.0), Color("f3e7a2"), 3.0)
		else:
			draw_line(Vector2.ZERO, Vector2(23.0, 0.0), ACCENT_COLOR, 4.0)
		draw_rect(Rect2(-24.0, -28.0, 48.0, 5.0), Color("172126"), true)
		draw_rect(Rect2(-23.0, -27.0, 46.0 * health_ratio, 3.0), Color("65c466") if health_ratio > 0.35 else Color("e35d5d"), true)
		if terrain_kind != UnitState.TerrainKind.NONE:
			var terrain_color := Color("d7b34c")
			if terrain_kind == UnitState.TerrainKind.RUINS:
				terrain_color = Color("9aa6a6")
			elif terrain_kind == UnitState.TerrainKind.FOREST:
				terrain_color = Color("5fa36f")
			draw_rect(Rect2(17.0, -28.0, 7.0, 7.0), terrain_color, true)
	if show_labels or selected:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(-13.0, 43.0),
			"E%d" % entity_id,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			16,
			Color("dce8e8")
		)
		draw_string(ThemeDB.fallback_font, Vector2(-44.0, 58.0), GameText.unit_name(definition_id), HORIZONTAL_ALIGNMENT_CENTER, 88.0, 13, Color("d2e1e1"))
	if hit_flash_remaining > 0.0:
		var flash_alpha := clampf(hit_flash_remaining / 0.18, 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-24.0, -17.0), Vector2(17.0, -17.0), Vector2(26.0, 0.0),
			Vector2(17.0, 17.0), Vector2(-24.0, 17.0),
		]), Color(1.0, 0.92, 0.7, flash_alpha * 0.72))
	if destruction_flash_remaining > 0.0:
		var destruction_progress := 1.0 - destruction_flash_remaining / 0.5
		draw_arc(Vector2.ZERO, 22.0 + destruction_progress * 34.0, 0.0, TAU, 32, Color(1.0, 0.35, 0.12, (1.0 - destruction_progress) * 0.8), 4.0)


func _draw_faction_marker() -> void:
	if faction_id == SimulationWorld.LOCAL_PLAYER_ID:
		draw_circle(Vector2.ZERO, 8.0, ACCENT_COLOR, false, 3.0)
		return
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -9.0),
		Vector2(9.0, 7.0),
		Vector2(-9.0, 7.0),
	]), ACCENT_COLOR)


func is_last_seen_contact() -> bool:
	return enabled and faction_id != SimulationWorld.LOCAL_PLAYER_ID and not currently_visible


func _draw_last_seen_marker() -> void:
	var marker_color := LAST_SEEN_COLOR
	marker_color.a *= clampf(intel_freshness, 0.18, 1.0)
	for segment in range(8):
		var start_angle := float(segment) * TAU / 8.0
		draw_arc(Vector2.ZERO, 24.0, start_angle, start_angle + TAU / 16.0, 5, marker_color, 2.5)
	draw_polyline(PackedVector2Array([
		Vector2(0.0, -15.0), Vector2(15.0, 0.0), Vector2(0.0, 15.0),
		Vector2(-15.0, 0.0), Vector2(0.0, -15.0),
	]), marker_color, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(-5.0, 6.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, marker_color.lightened(0.25))
	draw_string(ThemeDB.fallback_font, Vector2(-34.0, 43.0), GameText.t(&"INTEL_CONTACT_MARKER"), HORIZONTAL_ALIGNMENT_CENTER, 68.0, 12, marker_color)
