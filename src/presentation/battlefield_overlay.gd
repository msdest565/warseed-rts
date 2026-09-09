class_name BattlefieldOverlay
extends Node2D

const COLOR_FRONTLINE := Color("f1c75b")
const COLOR_TASK := Color("52d1c8")
const COLOR_THREAT := Color("ef6758")
const COLOR_STALE := Color("c78b6a")
const COLOR_UNKNOWN := Color(0.015, 0.025, 0.027, 0.34)
const COLOR_EXPLORED := Color(0.08, 0.12, 0.12, 0.10)
const COLOR_DECISION := Color("ffe07a")

var situation: BattlefieldSituationSnapshot
var selected_unit_card_id: StringName
var show_frontlines := true
var show_tasks := true
var show_threats := true
var show_intelligence := true
var decision_preview_route := PackedVector2Array()
var decision_preview_target := Vector2.ZERO
var decision_preview_radius := 0.0
var decision_preview_label := ""


func set_situation(new_situation: BattlefieldSituationSnapshot) -> void:
	situation = new_situation
	queue_redraw()


func set_selected_unit_card(unit_card_id: StringName) -> void:
	if selected_unit_card_id == unit_card_id:
		return
	selected_unit_card_id = unit_card_id
	queue_redraw()


func set_layer_visibility(frontlines: bool, tasks: bool, threats: bool, intelligence: bool) -> void:
	show_frontlines = frontlines
	show_tasks = tasks
	show_threats = threats
	show_intelligence = intelligence
	queue_redraw()


func set_decision_preview(route: PackedVector2Array, target_position: Vector2, radius: float, label: String) -> void:
	decision_preview_route = route.duplicate()
	decision_preview_target = target_position
	decision_preview_radius = maxf(radius, 20.0)
	decision_preview_label = label
	queue_redraw()


func clear_decision_preview() -> void:
	if decision_preview_route.is_empty() and decision_preview_target.is_zero_approx() and decision_preview_label.is_empty():
		return
	decision_preview_route.clear()
	decision_preview_target = Vector2.ZERO
	decision_preview_radius = 0.0
	decision_preview_label = ""
	queue_redraw()


func _draw() -> void:
	if situation == null:
		return
	if show_intelligence:
		_draw_uncertainty()
	if show_threats:
		_draw_threats()
	if show_frontlines:
		_draw_frontlines()
	if show_tasks:
		_draw_task_axes()
	_draw_selection_highlight()
	_draw_decision_preview()


func _draw_uncertainty() -> void:
	for zone in situation.uncertainty_zones:
		var rect := zone["rect"] as Rect2
		var unexplored := int(zone["state"]) == FactionKnowledge.CellState.UNEXPLORED
		draw_rect(rect, COLOR_UNKNOWN if unexplored else COLOR_EXPLORED, true)
		if unexplored and rect.size.x >= LogicGrid.CELL_SIZE * 3.0:
			var hatch_y := rect.position.y + rect.size.y * 0.5
			draw_line(Vector2(rect.position.x, hatch_y), Vector2(rect.end.x, hatch_y), Color(0.23, 0.31, 0.31, 0.16), 1.0)


func _draw_threats() -> void:
	for threat in situation.threat_zones:
		var position := threat["position"] as Vector2
		var radius := float(threat["radius"])
		var known := bool(threat["known_threat"])
		var stale := int(threat["age_ticks"]) >= BattlefieldSituationProjector.CONTACT_RECENT_TICKS
		var color := COLOR_STALE if stale else COLOR_THREAT
		if not known:
			color = Color("9aa7a2")
			draw_arc(position, radius, 0.0, TAU, 48, Color(color, 0.48), 3.0)
			for spoke in range(4):
				var direction := Vector2.RIGHT.rotated(float(spoke) * PI * 0.5)
				draw_line(position + direction * radius * 0.72, position + direction * radius, Color(color, 0.45), 2.0)
			continue
		draw_circle(position, radius, Color(color, 0.07))
		var segment_count := 8 if stale else 1
		if segment_count == 1:
			draw_arc(position, radius, 0.0, TAU, 48, Color(color, 0.82), 4.0)
		else:
			for segment in range(segment_count):
				var start := float(segment) * TAU / segment_count
				draw_arc(position, radius, start, start + TAU / segment_count * 0.55, 6, Color(color, 0.72), 4.0)
		var label := "%d-%d" % [int(threat["estimated_min"]), int(threat["estimated_max"])]
		if int(threat["visible_count"]) > 0:
			label = "! %d" % int(threat["visible_count"])
		_draw_world_label(position + Vector2(radius + 12.0, -8.0), label, color)


func _draw_frontlines() -> void:
	for segment in situation.frontline_segments:
		var start := segment["start"] as Vector2
		var end := segment["end"] as Vector2
		var hostile := segment["threat_anchor"] as Vector2
		draw_line(start, end, Color(COLOR_FRONTLINE, 0.35), 12.0)
		draw_line(start, end, Color(COLOR_FRONTLINE, 0.94), 3.0)
		var midpoint := start.lerp(end, 0.5)
		_draw_arrow(midpoint, midpoint.lerp(hostile, 0.3), COLOR_THREAT, 3.0)


func _draw_task_axes() -> void:
	for axis in situation.task_axes:
		var route := axis["route"] as PackedVector2Array
		if route.size() < 2:
			continue
		var selected: bool = selected_unit_card_id == axis["card_id"]
		var color := Color("8ff4e8") if selected else COLOR_TASK
		var width := 6.0 if selected else 3.0
		draw_polyline(route, Color(color, 0.85), width)
		for index in range(1, route.size()):
			_draw_arrow(route[index - 1], route[index], color, width)
		var target := axis["target_position"] as Vector2
		draw_circle(target, 18.0 if selected else 13.0, Color(color, 0.14))
		draw_arc(target, 18.0 if selected else 13.0, 0.0, TAU, 24, color, width)
		_draw_world_label(route[0] + Vector2(20.0, -18.0), GameText.t(axis["display_name_key"]), color)


func _draw_selection_highlight() -> void:
	if selected_unit_card_id.is_empty():
		return


func _draw_decision_preview() -> void:
	if decision_preview_target.is_zero_approx() and decision_preview_route.is_empty():
		return
	if decision_preview_route.size() >= 2:
		draw_polyline(decision_preview_route, Color(COLOR_DECISION, 0.28), 13.0)
		draw_polyline(decision_preview_route, Color(COLOR_DECISION, 0.96), 4.0)
		for index in range(1, decision_preview_route.size()):
			_draw_arrow(decision_preview_route[index - 1], decision_preview_route[index], COLOR_DECISION, 4.0)
	var target := decision_preview_target
	if target.is_zero_approx() and not decision_preview_route.is_empty():
		target = decision_preview_route[-1]
	if target.is_zero_approx():
		return
	var radius := maxf(decision_preview_radius, 20.0)
	draw_circle(target, radius, Color(COLOR_DECISION, 0.13))
	draw_arc(target, radius, 0.0, TAU, 48, COLOR_DECISION, 5.0)
	draw_line(target - Vector2(radius * 0.45, 0.0), target + Vector2(radius * 0.45, 0.0), COLOR_DECISION, 3.0)
	draw_line(target - Vector2(0.0, radius * 0.45), target + Vector2(0.0, radius * 0.45), COLOR_DECISION, 3.0)
	_draw_world_label(target + Vector2(radius + 12.0, -10.0), decision_preview_label, COLOR_DECISION)
	for card in situation.card_statuses:
		if card["card_id"] != selected_unit_card_id:
			continue
		var position := card["position"] as Vector2
		if position.is_zero_approx():
			return
		draw_circle(position, 54.0, Color(0.98, 0.86, 0.34, 0.10))
		draw_arc(position, 54.0, 0.0, TAU, 40, Color("f8d957"), 5.0)
		return


func _draw_arrow(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var direction := (to - from).normalized()
	if direction.is_zero_approx():
		return
	var tip := to
	var side := direction.orthogonal()
	var length := clampf(from.distance_to(to) * 0.16, 18.0, 42.0)
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip - direction * length + side * length * 0.48,
		tip - direction * length - side * length * 0.48,
	]), Color(color, 0.88))


func _draw_world_label(position: Vector2, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null or text.is_empty():
		return
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.01, 0.02, 0.02, 0.92))
	draw_string(font, position + Vector2(-1.0, -1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)
