class_name Battlefield
extends Node2D

const GRID_SIZE := LogicGrid.CELL_SIZE

@export_enum("Legacy RTS", "Grey Ridge", "Broken Bridge", "Fog Forest", "Black Well") var scenario_kind: int = SimulationWorld.ScenarioKind.LEGACY_RTS

var logic_grid := LogicGrid.create_test_map()
var battle_definition: BattleDefinition
var _last_grid_revision: int = -1
var _last_grid_instance_id: int = 0
var _blocked_outline_batch: MultiMeshInstance2D
var _blocked_fill_batch: MultiMeshInstance2D
var _engineering_routes_root: Node2D
var _last_route_grid_revision: int = -1
var _last_route_battle_instance_id: int = 0


func _ready() -> void:
	_ensure_blocked_batches()
	_ensure_engineering_routes_root()
	_rebuild_blocked_batches()
	_rebuild_engineering_route_visuals()


func refresh_locale() -> void:
	_rebuild_engineering_route_visuals()
	queue_redraw()


func _process(_delta: float) -> void:
	if logic_grid != null and (logic_grid.get_instance_id() != _last_grid_instance_id or logic_grid.revision != _last_grid_revision):
		_rebuild_blocked_batches()
		_last_grid_revision = logic_grid.revision
		queue_redraw()
	var battle_instance_id := battle_definition.get_instance_id() if battle_definition != null else 0
	if logic_grid != null and (logic_grid.revision != _last_route_grid_revision or battle_instance_id != _last_route_battle_instance_id):
		_rebuild_engineering_route_visuals()


func _draw() -> void:
	var bounds := get_battlefield_bounds()
	draw_rect(bounds, Color("11181b"), true)
	draw_rect(bounds, Color("182328"), true)
	if SimulationWorld.is_card_battle_kind(scenario_kind):
		_draw_battle_landmarks()

	var grid_color := Color(0.22, 0.32, 0.34, 0.32)
	var x := bounds.position.x
	while x <= bounds.end.x:
		draw_line(Vector2(x, bounds.position.y), Vector2(x, bounds.end.y), grid_color, 1.0)
		x += GRID_SIZE
	var y := bounds.position.y
	while y <= bounds.end.y:
		draw_line(Vector2(bounds.position.x, y), Vector2(bounds.end.x, y), grid_color, 1.0)
		y += GRID_SIZE

	draw_rect(bounds, Color("789097"), false, 2.0)


func _ensure_blocked_batches() -> void:
	if _blocked_outline_batch != null:
		return
	_blocked_outline_batch = _create_blocked_batch(Vector2.ONE * (GRID_SIZE - 6.0), Color("779096"), 0)
	_blocked_fill_batch = _create_blocked_batch(Vector2.ONE * (GRID_SIZE - 10.0), Color("3f5155"), 1)


func _ensure_engineering_routes_root() -> void:
	if _engineering_routes_root != null:
		return
	_engineering_routes_root = Node2D.new()
	_engineering_routes_root.name = "EngineeringRoutes"
	_engineering_routes_root.z_index = 4
	add_child(_engineering_routes_root)


func _rebuild_engineering_route_visuals() -> void:
	_ensure_engineering_routes_root()
	for child in _engineering_routes_root.get_children():
		_engineering_routes_root.remove_child(child)
		child.queue_free()
	if battle_definition == null or logic_grid == null:
		_last_route_grid_revision = logic_grid.revision if logic_grid != null else -1
		_last_route_battle_instance_id = 0
		return
	for route in battle_definition.engineering_routes:
		if route == null:
			continue
		var opened := _engineering_route_is_open(route)
		for rect in route.cleared_rects:
			_add_engineering_route_visual(route, rect, opened)
	_last_route_grid_revision = logic_grid.revision
	_last_route_battle_instance_id = battle_definition.get_instance_id()


func _engineering_route_is_open(route: BattleEngineeringRouteDefinition) -> bool:
	if route == null or logic_grid == null:
		return false
	for rect in route.cleared_rects:
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				if logic_grid.is_blocked(Vector2i(x, y)):
					return false
	return true


func _add_engineering_route_visual(route: BattleEngineeringRouteDefinition, cells: Rect2i, opened: bool) -> void:
	var top_left := Vector2(cells.position) * GRID_SIZE
	var size := Vector2(cells.size) * GRID_SIZE
	var center := top_left + size * 0.5
	var route_root := Node2D.new()
	route_root.name = "%s_%d_%d" % [route.route_id, cells.position.x, cells.position.y]
	_engineering_routes_root.add_child(route_root)
	var deck := Polygon2D.new()
	deck.polygon = PackedVector2Array([
		top_left, top_left + Vector2(size.x, 0.0), top_left + size, top_left + Vector2(0.0, size.y),
	])
	deck.color = Color(0.16, 0.48, 0.44, 0.88) if opened else Color(0.34, 0.12, 0.1, 0.42)
	route_root.add_child(deck)
	var outline := Line2D.new()
	outline.points = PackedVector2Array([
		top_left, top_left + Vector2(size.x, 0.0), top_left + size,
		top_left + Vector2(0.0, size.y), top_left,
	])
	outline.width = 8.0
	outline.default_color = Color("6ee7c8") if opened else Color("e46b55")
	route_root.add_child(outline)
	if opened:
		for rail_index in range(1, 4):
			var rail := Line2D.new()
			var rail_x := top_left.x + size.x * float(rail_index) / 4.0
			rail.points = PackedVector2Array([Vector2(rail_x, top_left.y + 12.0), Vector2(rail_x, top_left.y + size.y - 12.0)])
			rail.width = 5.0
			rail.default_color = Color(0.65, 0.88, 0.78, 0.72)
			route_root.add_child(rail)
	else:
		for diagonal in [PackedVector2Array([top_left, top_left + size]), PackedVector2Array([top_left + Vector2(size.x, 0.0), top_left + Vector2(0.0, size.y)])]:
			var barrier := Line2D.new()
			barrier.points = diagonal
			barrier.width = 10.0
			barrier.default_color = Color(0.9, 0.28, 0.2, 0.74)
			route_root.add_child(barrier)
	var label := Label.new()
	label.text = GameText.t(&"ENGINEERING_ROUTE_OPEN_MAP" if opened else &"ENGINEERING_ROUTE_CLOSED_MAP")
	label.position = center + Vector2(-180.0, -size.y * 0.5 - 54.0)
	label.size = Vector2(360.0, 42.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", Color("b9ffe9") if opened else Color("ffb09b"))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.04, 0.96))
	label.add_theme_constant_override("outline_size", 7)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route_root.add_child(label)


func _create_blocked_batch(size: Vector2, color: Color, layer: int) -> MultiMeshInstance2D:
	var instance := MultiMeshInstance2D.new()
	instance.z_index = layer
	instance.modulate = color
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	var mesh := QuadMesh.new()
	mesh.size = size
	multimesh.mesh = mesh
	instance.multimesh = multimesh
	add_child(instance)
	return instance


func _rebuild_blocked_batches() -> void:
	if logic_grid == null:
		return
	_ensure_blocked_batches()
	var cells := logic_grid.get_blocked_cells()
	for batch in [_blocked_outline_batch, _blocked_fill_batch]:
		batch.multimesh.instance_count = cells.size()
		for index in range(cells.size()):
			batch.multimesh.set_instance_transform_2d(index, Transform2D(0.0, logic_grid.cell_to_world(cells[index])))
	_last_grid_instance_id = logic_grid.get_instance_id()
	_last_grid_revision = logic_grid.revision


func get_battlefield_bounds() -> Rect2:
	return battle_definition.battlefield_bounds if battle_definition != null else SimulationWorld.BATTLEFIELD_BOUNDS


func _draw_battle_landmarks() -> void:
	if battle_definition == null:
		_draw_grey_ridge_landmarks_compatibility()
		return
	var regions := battle_definition.strategic_regions
	var drawn_links: Dictionary = {}
	var region_by_id := battle_definition.region_dictionary()
	for region in regions:
		for adjacent_id in region.adjacent_region_ids:
			var link_ids: Array[StringName] = [region.region_id, adjacent_id]
			link_ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
			var link_key := "%s:%s" % [link_ids[0], link_ids[1]]
			if drawn_links.has(link_key):
				continue
			var adjacent := region_by_id.get(adjacent_id) as BattleRegionDefinition
			if adjacent != null:
				draw_line(region.position, adjacent.position, Color(0.48, 0.58, 0.56, 0.7), 20.0)
			drawn_links[link_key] = true
	for region in regions:
		var zone_size := Vector2(maxf(1120.0, region.radius * 2.45), maxf(660.0, region.radius * 1.55))
		var zone_rect := Rect2(region.position - zone_size * 0.5, zone_size)
		if not region.capturable:
			_draw_withdrawal_corridor(zone_rect)
		else:
			draw_rect(zone_rect, _terrain_color(region.terrain_key), true)
			_draw_terrain_texture(zone_rect, region.terrain_key)
			if scenario_kind == SimulationWorld.ScenarioKind.BLACK_WELL:
				_draw_black_well_industry(zone_rect, region.region_id)
			draw_rect(zone_rect, Color("9ab0a8"), false, 3.0)
		draw_circle(region.position, 42.0, Color("7f898e"), false, 5.0)
		draw_string(
			ThemeDB.fallback_font,
			region.position + Vector2(-180.0, -236.0),
			GameText.t(region.display_name_key),
			HORIZONTAL_ALIGNMENT_CENTER,
			360.0,
			28,
			Color("ead58a")
		)
		draw_string(
			ThemeDB.fallback_font,
			region.position + Vector2(-180.0, -198.0),
			GameText.t(region.terrain_key),
			HORIZONTAL_ALIGNMENT_CENTER,
			360.0,
			20,
			Color("c5d1c9")
		)


func _draw_withdrawal_corridor(zone_rect: Rect2) -> void:
	draw_rect(zone_rect, Color(0.08, 0.17, 0.17, 0.92), true)
	var stripe_color := Color(0.34, 0.88, 0.72, 0.34)
	var stripe_x := zone_rect.position.x - zone_rect.size.y
	while stripe_x < zone_rect.end.x:
		draw_line(Vector2(stripe_x, zone_rect.end.y), Vector2(stripe_x + zone_rect.size.y, zone_rect.position.y), stripe_color, 18.0)
		stripe_x += 92.0
	draw_rect(zone_rect, Color("54d3b4"), false, 7.0)
	var arrow_y := zone_rect.position.y + 120.0
	while arrow_y < zone_rect.end.y - 80.0:
		draw_line(Vector2(zone_rect.get_center().x, arrow_y), Vector2(zone_rect.get_center().x, arrow_y + 72.0), Color("b8f1df"), 12.0)
		draw_polyline(PackedVector2Array([
			Vector2(zone_rect.get_center().x - 34.0, arrow_y + 44.0),
			Vector2(zone_rect.get_center().x, arrow_y + 78.0),
			Vector2(zone_rect.get_center().x + 34.0, arrow_y + 44.0),
		]), Color("b8f1df"), 12.0)
		arrow_y += 170.0


func _draw_black_well_industry(zone_rect: Rect2, region_id: StringName) -> void:
	match region_id:
		&"slag_rail":
			for rail in range(3):
				var y := zone_rect.position.y + 150.0 + rail * 150.0
				draw_line(Vector2(zone_rect.position.x + 70.0, y), Vector2(zone_rect.end.x - 70.0, y), Color(0.68, 0.66, 0.58, 0.72), 10.0)
				for sleeper in range(12):
					var x := zone_rect.position.x + 90.0 + sleeper * (zone_rect.size.x - 180.0) / 11.0
					draw_line(Vector2(x, y - 24.0), Vector2(x, y + 24.0), Color(0.33, 0.25, 0.18, 0.9), 8.0)
		&"black_well_core":
			for row in range(2):
				for column in range(4):
					var tank_center := zone_rect.position + Vector2(165.0 + column * 255.0, 190.0 + row * 300.0)
					draw_circle(tank_center, 58.0, Color(0.20, 0.25, 0.24, 0.9))
					draw_circle(tank_center, 58.0, Color(0.66, 0.72, 0.67, 0.62), false, 8.0)
					draw_line(tank_center, tank_center + Vector2(0.0, -94.0), Color(0.58, 0.62, 0.59, 0.75), 12.0)
		&"pump_heights":
			for column in range(5):
				var base := zone_rect.position + Vector2(150.0 + column * 225.0, zone_rect.size.y * (0.38 if column % 2 == 0 else 0.68))
				draw_rect(Rect2(base - Vector2(54.0, 38.0), Vector2(108.0, 76.0)), Color(0.21, 0.28, 0.28, 0.92), true)
				draw_line(base + Vector2(-34.0, -38.0), base + Vector2(45.0, -112.0), Color(0.71, 0.65, 0.48, 0.72), 13.0)
				draw_circle(base + Vector2(45.0, -112.0), 18.0, Color(0.75, 0.67, 0.46, 0.8), false, 7.0)


func _draw_grey_ridge_landmarks_compatibility() -> void:
	var centers := [SimulationWorld.GREY_RIDGE_WEST_POSITION, SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, SimulationWorld.GREY_RIDGE_EAST_POSITION]
	var label_keys: Array[StringName] = [&"GREY_RIDGE_WEST", &"GREY_RIDGE_CENTRAL", &"GREY_RIDGE_EAST"]
	var terrain_keys: Array[StringName] = [&"TERRAIN_OPEN", &"TERRAIN_RUINS", &"TERRAIN_FOREST"]
	draw_line(centers[0], centers[2], Color(0.48, 0.58, 0.56, 0.7), 20.0)
	for index in range(centers.size()):
		var zone_rect := Rect2(centers[index] - Vector2(560.0, 330.0), Vector2(1120.0, 660.0))
		draw_rect(zone_rect, _terrain_color(terrain_keys[index]), true)
		_draw_terrain_texture(zone_rect, terrain_keys[index])
		draw_rect(zone_rect, Color("9ab0a8"), false, 3.0)
		draw_circle(centers[index], 42.0, Color("d1ad45"), false, 5.0)
		draw_string(ThemeDB.fallback_font, centers[index] + Vector2(-180.0, -236.0), GameText.t(label_keys[index]), HORIZONTAL_ALIGNMENT_CENTER, 360.0, 28, Color("ead58a"))
		draw_string(ThemeDB.fallback_font, centers[index] + Vector2(-180.0, -198.0), GameText.t(terrain_keys[index]), HORIZONTAL_ALIGNMENT_CENTER, 360.0, 20, Color("c5d1c9"))


func _terrain_color(terrain_key: StringName) -> Color:
	match terrain_key:
		&"TERRAIN_OPEN":
			return Color("493f2f")
		&"TERRAIN_FOREST":
			return Color("263f38")
	return Color("3e4144")


func _draw_terrain_texture(zone_rect: Rect2, terrain_key: StringName) -> void:
	match terrain_key:
		&"TERRAIN_OPEN":
			_draw_open_ground_texture(zone_rect)
		&"TERRAIN_FOREST":
			_draw_forest_texture(zone_rect)
		_:
			_draw_ruins_texture(zone_rect)


func _draw_open_ground_texture(zone_rect: Rect2) -> void:
	var track_color := Color(0.82, 0.67, 0.36, 0.34)
	for row in range(6):
		var y := zone_rect.position.y + zone_rect.size.y * float(row + 1) / 7.0
		draw_line(Vector2(zone_rect.position.x + 40.0, y), Vector2(zone_rect.end.x - 40.0, y + 28.0), track_color, 4.0)
	for column in range(10):
		var center := zone_rect.position + Vector2(
			zone_rect.size.x * float(column + 1) / 11.0,
			zone_rect.size.y * (0.78 - float(column % 2) * 0.1)
		)
		draw_circle(center, 20.0, Color(0.12, 0.15, 0.14, 0.58), false, 4.0)


func _draw_ruins_texture(zone_rect: Rect2) -> void:
	var wall_color := Color(0.65, 0.68, 0.66, 0.38)
	for row in range(5):
		for column in range(8):
			var origin := zone_rect.position + Vector2(
				zone_rect.size.x * float(column + 0.35) / 8.0,
				zone_rect.size.y * float(row + 0.4) / 5.0
			)
			var width := 76.0 + float((row + column) % 2) * 24.0
			draw_line(origin, origin + Vector2(width, 0.0), wall_color, 7.0)
			draw_line(origin, origin + Vector2(0.0, 58.0), wall_color, 7.0)
			draw_circle(origin + Vector2(width + 14.0, 24.0), 7.0, wall_color)


func _draw_forest_texture(zone_rect: Rect2) -> void:
	for row in range(7):
		for column in range(12):
			var offset_x := zone_rect.size.x * float(column + 0.55) / 12.0 + float(row % 2) * 18.0
			var offset_y := zone_rect.size.y * float(row + 0.55) / 7.0
			var center := zone_rect.position + Vector2(offset_x, offset_y)
			draw_line(center + Vector2(0.0, 14.0), center + Vector2(0.0, 34.0), Color(0.36, 0.28, 0.18, 0.7), 5.0)
			draw_circle(center, 21.0, Color(0.20, 0.49, 0.31, 0.48))
			draw_circle(center + Vector2(13.0, 7.0), 14.0, Color(0.31, 0.61, 0.38, 0.35))
