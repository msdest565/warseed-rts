class_name InputController
extends Node

enum CommandMode {
	NORMAL,
	ATTACK_MOVE_TARGETING,
	BUILD_FACTORY_TARGETING,
	BUILD_SUPPORT_TARGETING,
	REPAIR_TARGETING,
	HARVEST_TARGETING,
	DEFEND_TARGETING,
	SCOUT_TARGETING,
	RALLY_TARGETING,
	DEPLOY_UNIT_CARD_TARGETING,
	FORMATION_ROUTE_TARGETING,
	COMMANDER_ROUTE_TARGETING,
}

signal move_intent_changed(target_position: Vector2, intent_sequence: int)
signal pending_intent_cleared
signal build_preview_changed(build_position: Vector2, footprint_size: Vector2i, valid: bool, engineer_position: Vector2)
signal build_preview_cleared
signal attack_targeting_started
signal attack_preview_changed(target_position: Vector2, target_entity_id: int)
signal attack_preview_cleared
signal formation_plan_preview_changed(route_points: PackedVector2Array, line_start: Vector2, line_end: Vector2, drawing_line: bool)
signal formation_plan_preview_cleared
signal commander_intent_preview_changed(commander_id: StringName, target_position: Vector2)
signal commander_intent_preview_cleared
signal commander_plan_preview_changed(commander_id: StringName, route_points: PackedVector2Array, target_position: Vector2)
signal commander_plan_preview_cleared
signal command_mode_changed(mode: CommandMode)

const HIT_RADIUS_SCREEN := 34.0
const DRAG_THRESHOLD := 6.0
const FORMATION_HANDLE_HIT_RADIUS_SCREEN := 18.0
const COMMANDER_TASK_HANDLE_HIT_RADIUS_SCREEN := 20.0
const FORMATION_DRAG_NONE := -1
const FORMATION_DRAG_LINE_START := -2
const FORMATION_DRAG_LINE_END := -3

var selected_entity_id: int = 0
var selected_entity_ids: Array[int] = []
var selected_building_id: int = 0
var selected_unit_card_id: StringName
var selected_commander_id: StringName
var intent_sequence: int = 0
var pending_move_target: Vector2
var pending_move_active: bool = false
var coalesced_count: int = 0
var last_command_status: String = ""
var route_feedback_override: String = ""
var control_groups: Dictionary = {}
var drag_start_screen: Vector2
var drag_current_screen: Vector2
var left_dragging: bool = false
var command_mode: CommandMode = CommandMode.NORMAL
var diagnostic_individual_selection_enabled: bool = false
var formation_route_points: PackedVector2Array = PackedVector2Array()
var formation_line_start: Vector2
var formation_line_end: Vector2
var formation_line_drawing: bool = false
var formation_dragged_handle: int = FORMATION_DRAG_NONE
var commander_drag_active: bool = false
var commander_drag_id: StringName
var commander_drag_start_screen: Vector2
var commander_drag_current_screen: Vector2
var commander_route_points: PackedVector2Array = PackedVector2Array()

@export var simulation_host: SimulationHost
@export var world_presentation: WorldPresentation
@export var camera_controller: CameraController
@export var selection_overlay: SelectionOverlay


func _ready() -> void:
	refresh_locale_status()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_C and command_mode != CommandMode.NORMAL:
			cancel_command_mode()
			var route_viewport := get_viewport()
			if route_viewport != null:
				route_viewport.set_input_as_handled()
			return
	if not commander_drag_active or not _handle_commander_drag_input(event):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func refresh_locale_status() -> void:
	last_command_status = GameText.t(&"STATUS_READY")


func get_operation_guidance() -> String:
	var status := route_feedback_override if not route_feedback_override.is_empty() else last_command_status
	if status.is_empty():
		status = GameText.t(&"STATUS_READY")
	var guidance_key := _command_mode_guidance_key()
	if guidance_key.is_empty():
		return status
	var mode_guidance := GameText.t(guidance_key)
	if status == mode_guidance:
		return status
	return "%s\n%s" % [status, mode_guidance]


func _command_mode_guidance_key() -> StringName:
	match command_mode:
		CommandMode.ATTACK_MOVE_TARGETING:
			return &"STATUS_ATTACK_MOVE_TARGET"
		CommandMode.BUILD_FACTORY_TARGETING, CommandMode.BUILD_SUPPORT_TARGETING:
			return &"STATUS_BUILD_TARGET"
		CommandMode.REPAIR_TARGETING:
			return &"STATUS_REPAIR_TARGET"
		CommandMode.HARVEST_TARGETING:
			return &"STATUS_HARVEST_TARGET"
		CommandMode.DEFEND_TARGETING:
			return &"STATUS_DEFEND_TARGET"
		CommandMode.SCOUT_TARGETING:
			return &"STATUS_SCOUT_TARGET"
		CommandMode.RALLY_TARGETING:
			return &"STATUS_RALLY_TARGET"
		CommandMode.DEPLOY_UNIT_CARD_TARGETING:
			return &"GUIDANCE_DEPLOY_UNIT_CARD_TARGET"
		CommandMode.FORMATION_ROUTE_TARGETING:
			return &"STATUS_ROUTE_TARGETING"
		CommandMode.COMMANDER_ROUTE_TARGETING:
			return &"STATUS_COMMANDER_ROUTE_TARGETING"
	return &""


func _unhandled_input(event: InputEvent) -> void:
	if camera_controller != null and camera_controller.handle_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)
		return
	if _is_build_targeting() and event is InputEventMouseMotion:
		_update_build_preview(_screen_to_world((event as InputEventMouseMotion).position))
		return
	if command_mode == CommandMode.ATTACK_MOVE_TARGETING and event is InputEventMouseMotion:
		_update_attack_preview(_screen_to_world((event as InputEventMouseMotion).position))
		return
	if command_mode == CommandMode.ATTACK_MOVE_TARGETING and event is InputEventMouseButton:
		var targeting_mouse := event as InputEventMouseButton
		if targeting_mouse.pressed and targeting_mouse.button_index == MOUSE_BUTTON_RIGHT:
			cancel_command_mode()
			return
		if targeting_mouse.pressed and targeting_mouse.button_index == MOUSE_BUTTON_LEFT:
			attack_or_move_selected_at(_screen_to_world(targeting_mouse.position))
			return
	if command_mode == CommandMode.DEPLOY_UNIT_CARD_TARGETING and event is InputEventMouseButton:
		var deployment_mouse := event as InputEventMouseButton
		if deployment_mouse.pressed and deployment_mouse.button_index == MOUSE_BUTTON_RIGHT:
			cancel_command_mode()
			return
		if deployment_mouse.pressed and deployment_mouse.button_index == MOUSE_BUTTON_LEFT:
			deploy_selected_unit_card_at(_screen_to_world(deployment_mouse.position))
			return
	if command_mode == CommandMode.FORMATION_ROUTE_TARGETING:
		_handle_formation_route_input(event)
		return
	if command_mode == CommandMode.COMMANDER_ROUTE_TARGETING:
		_handle_commander_route_input(event)
		return
	if command_mode in [CommandMode.HARVEST_TARGETING, CommandMode.DEFEND_TARGETING, CommandMode.SCOUT_TARGETING, CommandMode.RALLY_TARGETING] and event is InputEventMouseButton:
		var target_mouse := event as InputEventMouseButton
		if target_mouse.pressed and target_mouse.button_index == MOUSE_BUTTON_RIGHT:
			cancel_command_mode()
			return
		if target_mouse.pressed and target_mouse.button_index == MOUSE_BUTTON_LEFT:
			var target_position := _screen_to_world(target_mouse.position)
			if command_mode == CommandMode.HARVEST_TARGETING:
				harvest_selected_at(target_position)
			elif command_mode == CommandMode.SCOUT_TARGETING:
				scout_selected_at(target_position)
			elif command_mode == CommandMode.RALLY_TARGETING:
				set_selected_rally_point(target_position)
			else:
				defend_selected_at(target_position)
			return
	if command_mode in [CommandMode.BUILD_FACTORY_TARGETING, CommandMode.BUILD_SUPPORT_TARGETING, CommandMode.REPAIR_TARGETING] and event is InputEventMouseButton:
		var work_mouse := event as InputEventMouseButton
		if work_mouse.pressed and work_mouse.button_index == MOUSE_BUTTON_RIGHT:
			cancel_command_mode()
			return
		if work_mouse.pressed and work_mouse.button_index == MOUSE_BUTTON_LEFT:
			var world_position := _screen_to_world(work_mouse.position)
			if command_mode == CommandMode.REPAIR_TARGETING:
				repair_selected_at(world_position)
			else:
				var definition_id: StringName = &"automated_factory" if command_mode == CommandMode.BUILD_FACTORY_TARGETING else &"forward_support_station"
				build_selected_at(definition_id, world_position)
			return
	if command_mode == CommandMode.NORMAL and event is InputEventMouseButton:
		var task_mouse := event as InputEventMouseButton
		if task_mouse.pressed and task_mouse.button_index == MOUSE_BUTTON_LEFT:
			var task_world_position := _screen_to_world(task_mouse.position)
			var task_commander_id := _find_commander_task_handle_at(task_world_position)
			if not task_commander_id.is_empty() and begin_commander_drag(task_commander_id, task_mouse.position):
				var commander := simulation_host.current_snapshot.get_commander(task_commander_id)
				commander_intent_preview_changed.emit(task_commander_id, commander.target_position)
				last_command_status = GameText.t(&"STATUS_COMMANDER_TASK_DRAG_TARGET") % GameText.t(commander.display_name_key)
				return
	if event is InputEventMouseMotion and left_dragging:
		drag_current_screen = (event as InputEventMouseMotion).position
		selection_overlay.update_drag(drag_current_screen)
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_LEFT:
		if mouse.pressed:
			left_dragging = true
			drag_start_screen = mouse.position
			drag_current_screen = mouse.position
			selection_overlay.begin_drag(mouse.position)
		elif left_dragging:
			left_dragging = false
			selection_overlay.end_drag()
			_finish_selection(mouse.position, mouse.shift_pressed, mouse.alt_pressed)
	elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		context_command_selected_at(_screen_to_world(mouse.position))


func _finish_selection(screen_position: Vector2, additive: bool, select_formation: bool = false) -> void:
	if drag_start_screen.distance_to(screen_position) <= DRAG_THRESHOLD:
		select_at(_screen_to_world(screen_position), additive, select_formation)
	else:
		var world_start := _screen_to_world(drag_start_screen)
		var world_end := _screen_to_world(screen_position)
		select_in_rect(Rect2(world_start, world_end - world_start).abs(), additive)


func select_at(world_position: Vector2, additive: bool = false, select_formation: bool = false) -> void:
	var snapshot := simulation_host.current_snapshot
	var best_id := 0
	var best_distance := INF
	var hit_radius := HIT_RADIUS_SCREEN / camera_controller.zoom.x if camera_controller != null else HIT_RADIUS_SCREEN
	if snapshot != null:
		for unit in snapshot.units:
			if not _is_selectable(unit):
				continue
			var distance := unit.position.distance_to(world_position)
			if distance <= hit_radius and (distance < best_distance or (is_equal_approx(distance, best_distance) and unit.entity_id < best_id)):
				best_id = unit.entity_id
				best_distance = distance
	if best_id == 0:
		var building_id := _find_friendly_building_at(world_position)
		if building_id != 0:
			_set_building_selection(building_id)
			last_command_status = GameText.t(&"STATUS_BUILDING_SELECTED") % GameText.building_name(snapshot.get_building(building_id).definition_id)
			return
		if not additive:
			_set_selection([])
			last_command_status = GameText.t(&"STATUS_SELECTION_CLEARED")
		return
	var atom: Array[int] = []
	if select_formation or _formal_card_selection_enabled():
		atom = _get_selection_atom(best_id)
	else:
		atom.append(best_id)
	if additive:
		var all_selected := true
		for entity_id in atom:
			if not selected_entity_ids.has(entity_id):
				all_selected = false
				break
		if all_selected:
			for entity_id in atom:
				selected_entity_ids.erase(entity_id)
		else:
			selected_entity_ids.append_array(atom)
		_set_selection(selected_entity_ids)
	else:
		_set_selection(atom)
	last_command_status = GameText.t(&"STATUS_SELECTED") % selected_entity_ids.size()


func select_in_rect(world_rect: Rect2, additive: bool = false) -> void:
	var matches: Array[int] = []
	var snapshot := simulation_host.current_snapshot
	if snapshot != null:
		for unit in snapshot.units:
			if _is_selectable(unit) and world_rect.has_point(unit.position):
				if _formal_card_selection_enabled():
					matches.append_array(_get_selection_atom(unit.entity_id))
				else:
					matches.append(unit.entity_id)
	if matches.is_empty() and additive:
		return
	if additive:
		matches.append_array(selected_entity_ids)
	_set_selection(matches)
	last_command_status = GameText.t(&"STATUS_SELECTED") % selected_entity_ids.size()


func select_unit_card(unit_card_id: StringName) -> void:
	var snapshot := simulation_host.current_snapshot
	var unit_card := snapshot.get_unit_card(unit_card_id) if snapshot != null else null
	if unit_card == null or unit_card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		last_command_status = GameText.t(&"STATUS_UNIT_CARD_UNAVAILABLE")
		return
	if command_mode == CommandMode.FORMATION_ROUTE_TARGETING and selected_unit_card_id != unit_card_id:
		cancel_command_mode()
	simulation_host.record_playtest_ui_event("unit_card_selected", unit_card_id)
	if unit_card.deployment_state == UnitCardState.DeploymentState.RESERVE:
		selected_entity_ids.clear()
		selected_entity_id = 0
		selected_building_id = 0
		selected_unit_card_id = unit_card_id
		selected_commander_id = unit_card.commander_definition_id
		command_mode = CommandMode.DEPLOY_UNIT_CARD_TARGETING
		command_mode_changed.emit(command_mode)
		world_presentation.set_selected_entities([], 0, 0)
		last_command_status = GameText.t(&"STATUS_DEPLOY_UNIT_CARD_TARGET") % [
			GameText.t(unit_card.display_name_key), unit_card.supply_cost,
		]
		return
	if unit_card.deployment_state == UnitCardState.DeploymentState.DEPLOYING:
		selected_unit_card_id = unit_card_id
		selected_commander_id = unit_card.commander_definition_id
		last_command_status = GameText.t(&"STATUS_UNIT_CARD_DEPLOYING") % (unit_card.deployment_ticks_remaining * SimulationWorld.TICK_SECONDS)
		return
	if unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED:
		last_command_status = GameText.t(&"STATUS_UNIT_CARD_UNAVAILABLE")
		return
	_set_selection(unit_card.active_member_entity_ids)
	selected_unit_card_id = unit_card_id
	selected_commander_id = unit_card.commander_definition_id
	last_command_status = GameText.t(&"STATUS_UNIT_CARD_SELECTED") % [
		GameText.t(unit_card.display_name_key), unit_card.current_strength,
	]


func deploy_selected_unit_card_at(world_position: Vector2) -> CommandValidationResult:
	if selected_unit_card_id.is_empty():
		last_command_status = GameText.t(&"STATUS_UNIT_CARD_UNAVAILABLE")
		return null
	var result := simulation_host.submit_command(
		simulation_host.create_deploy_unit_card_command(selected_unit_card_id, world_position, selected_commander_id)
	)
	last_command_status = GameText.t(&"STATUS_DEPLOY_UNIT_CARD") % GameText.command_result(result)
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
		command_mode_changed.emit(command_mode)
	return result


func begin_reserve_card_drag(unit_card_id: StringName) -> bool:
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	var unit_card := snapshot.get_unit_card(unit_card_id) if snapshot != null else null
	if unit_card == null or unit_card.faction_id != SimulationWorld.LOCAL_PLAYER_ID or unit_card.deployment_state != UnitCardState.DeploymentState.RESERVE:
		last_command_status = GameText.t(&"STATUS_UNIT_CARD_UNAVAILABLE")
		return false
	selected_entity_ids.clear()
	selected_entity_id = 0
	selected_building_id = 0
	selected_unit_card_id = unit_card_id
	selected_commander_id = unit_card.commander_definition_id
	command_mode = CommandMode.NORMAL
	world_presentation.set_selected_entities([], 0, 0)
	simulation_host.record_playtest_ui_event("reserve_card_drag_started", unit_card_id)
	last_command_status = GameText.t(&"STATUS_RESERVE_DRAG_TARGET") % GameText.t(unit_card.display_name_key)
	return true


func preview_reserve_card_drop(commander_id: StringName) -> void:
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	var unit_card := snapshot.get_unit_card(selected_unit_card_id) if snapshot != null else null
	if unit_card == null or unit_card.deployment_state != UnitCardState.DeploymentState.RESERVE:
		return
	if commander_id.is_empty():
		last_command_status = GameText.t(&"STATUS_RESERVE_DRAG_TARGET") % GameText.t(unit_card.display_name_key)
		return
	var hovered_commander := snapshot.get_commander(commander_id)
	var assigned_commander := snapshot.get_commander(unit_card.commander_definition_id)
	if hovered_commander == null or assigned_commander == null:
		return
	if commander_id == unit_card.commander_definition_id:
		last_command_status = GameText.t(&"STATUS_RESERVE_DROP_READY") % [
			GameText.t(unit_card.display_name_key), GameText.t(hovered_commander.display_name_key), unit_card.supply_cost,
		]
	else:
		last_command_status = GameText.t(&"STATUS_RESERVE_DROP_MISMATCH") % [
			GameText.t(unit_card.display_name_key), GameText.t(assigned_commander.display_name_key), GameText.t(hovered_commander.display_name_key),
		]


func cancel_reserve_card_drag() -> void:
	command_mode = CommandMode.NORMAL
	last_command_status = GameText.t(&"STATUS_RESERVE_DRAG_CANCELLED")


func deploy_reserve_card_to_commander(unit_card_id: StringName, commander_id: StringName) -> CommandValidationResult:
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	var unit_card := snapshot.get_unit_card(unit_card_id) if snapshot != null else null
	if unit_card == null:
		last_command_status = GameText.t(&"STATUS_UNIT_CARD_UNAVAILABLE")
		return null
	var commander := snapshot.get_commander(commander_id)
	var result := simulation_host.submit_command(
		simulation_host.create_deploy_unit_card_command(
			unit_card_id,
			_default_reserve_deployment_position(commander_id),
			commander_id
		)
	)
	var previous_mode := command_mode
	command_mode = CommandMode.NORMAL
	if previous_mode != command_mode:
		command_mode_changed.emit(command_mode)
	last_command_status = GameText.t(&"STATUS_RESERVE_DEPLOY_SUBMITTED") % [
		GameText.t(unit_card.display_name_key),
		GameText.t(commander.display_name_key) if commander != null else String(commander_id),
		GameText.command_result(result),
	]
	return result


func _default_reserve_deployment_position(commander_id: StringName) -> Vector2:
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	if snapshot == null:
		return Vector2.ZERO
	var headquarters := snapshot.get_building(SimulationWorld.PLAYER_COMMAND_CENTER_ID)
	if headquarters == null:
		return Vector2.ZERO
	var commander := snapshot.get_commander(commander_id)
	var direction := commander.target_position - headquarters.position if commander != null else Vector2.UP
	if direction.length_squared() < 4096.0:
		direction = Vector2.UP
	return headquarters.position + direction.normalized() * 192.0


func begin_unit_card_route(unit_card_id: StringName) -> void:
	if is_unit_card_route_planning(unit_card_id):
		cancel_command_mode()
		return
	var snapshot := simulation_host.current_snapshot
	var unit_card := snapshot.get_unit_card(unit_card_id) if snapshot != null else null
	if unit_card == null or unit_card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or unit_card.formation_id == 0:
		last_command_status = GameText.t(&"STATUS_UNIT_CARD_UNAVAILABLE")
		return
	select_unit_card(unit_card_id)
	route_feedback_override = ""
	command_mode = CommandMode.FORMATION_ROUTE_TARGETING
	command_mode_changed.emit(command_mode)
	var formation := snapshot.get_formation(unit_card.formation_id)
	formation_route_points = formation.planned_route.duplicate() if formation != null else PackedVector2Array()
	formation_line_start = formation.deployment_line_start if formation != null and formation.has_deployment_line else Vector2.ZERO
	formation_line_end = formation.deployment_line_end if formation != null and formation.has_deployment_line else Vector2.ZERO
	formation_line_drawing = false
	formation_dragged_handle = FORMATION_DRAG_NONE
	last_command_status = GameText.t(&"STATUS_ROUTE_EDITING" if formation != null and (not formation.planned_route.is_empty() or formation.has_deployment_line) else &"STATUS_ROUTE_TARGETING")
	formation_plan_preview_changed.emit(formation_route_points, formation_line_start, formation_line_end, formation != null and formation.has_deployment_line)


func is_unit_card_route_planning(unit_card_id: StringName = &"") -> bool:
	return command_mode == CommandMode.FORMATION_ROUTE_TARGETING and (unit_card_id.is_empty() or selected_unit_card_id == unit_card_id)


func submit_selected_formation_route() -> CommandValidationResult:
	if command_mode != CommandMode.FORMATION_ROUTE_TARGETING:
		return null
	return _submit_formation_plan()


func begin_commander_route(commander_id: StringName) -> void:
	if is_commander_route_planning(commander_id):
		cancel_commander_route_planning()
		return
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	var commander := snapshot.get_commander(commander_id) if snapshot != null else null
	if commander == null or commander.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		last_command_status = GameText.t(&"STATUS_COMMANDER_UNAVAILABLE")
		return
	select_commander_card(commander_id)
	route_feedback_override = ""
	command_mode = CommandMode.COMMANDER_ROUTE_TARGETING
	command_mode_changed.emit(command_mode)
	commander_route_points = commander.planned_route.duplicate()
	var preview_target := commander.target_position
	commander_plan_preview_changed.emit(commander_id, commander_route_points, preview_target)
	last_command_status = GameText.t(&"STATUS_COMMANDER_ROUTE_TARGETING")


func _handle_commander_route_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		commander_plan_preview_changed.emit(selected_commander_id, commander_route_points, _screen_to_world((event as InputEventMouseMotion).position))
		return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed:
		return
	var world_position := _screen_to_world(mouse.position)
	if mouse.button_index == MOUSE_BUTTON_LEFT:
		if commander_route_points.size() < 8:
			route_feedback_override = ""
			commander_route_points.append(world_position)
			commander_plan_preview_changed.emit(selected_commander_id, commander_route_points, world_position)
			last_command_status = GameText.t(&"STATUS_COMMANDER_ROUTE_WAYPOINT") % commander_route_points.size()
		return
	if mouse.button_index != MOUSE_BUTTON_RIGHT:
		return
	submit_commander_route(world_position)


func submit_commander_route(target_position: Vector2) -> CommandValidationResult:
	if command_mode != CommandMode.COMMANDER_ROUTE_TARGETING or selected_commander_id.is_empty():
		return null
	var result := simulation_host.submit_command(
		simulation_host.create_commander_objective_command(selected_commander_id, target_position, commander_route_points)
	)
	last_command_status = GameText.t(&"STATUS_COMMANDER_ROUTE_SUBMITTED") % GameText.command_result(result)
	route_feedback_override = "" if result.is_accepted() else last_command_status
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
		command_mode_changed.emit(command_mode)
		commander_route_points = PackedVector2Array()
		commander_plan_preview_cleared.emit()
	return result


func submit_selected_commander_route() -> CommandValidationResult:
	if command_mode != CommandMode.COMMANDER_ROUTE_TARGETING:
		return null
	if commander_route_points.is_empty():
		last_command_status = GameText.t(&"STATUS_COMMANDER_ROUTE_NEEDS_TARGET")
		return null
	return submit_commander_route(commander_route_points[-1])


func undo_commander_route_waypoint() -> bool:
	if command_mode != CommandMode.COMMANDER_ROUTE_TARGETING or commander_route_points.is_empty():
		return false
	commander_route_points.remove_at(commander_route_points.size() - 1)
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	var commander := snapshot.get_commander(selected_commander_id) if snapshot != null else null
	var target := commander.target_position if commander != null else Vector2.ZERO
	commander_plan_preview_changed.emit(selected_commander_id, commander_route_points, target)
	last_command_status = GameText.t(&"STATUS_COMMANDER_ROUTE_WAYPOINT") % commander_route_points.size()
	return true


func is_commander_route_planning(commander_id: StringName = &"") -> bool:
	return command_mode == CommandMode.COMMANDER_ROUTE_TARGETING and (commander_id.is_empty() or selected_commander_id == commander_id)


func cancel_commander_route_planning() -> void:
	if command_mode != CommandMode.COMMANDER_ROUTE_TARGETING:
		return
	cancel_command_mode()
	last_command_status = GameText.t(&"STATUS_COMMANDER_ROUTE_CANCELLED")


func undo_formation_route_waypoint() -> bool:
	if command_mode != CommandMode.FORMATION_ROUTE_TARGETING or formation_route_points.is_empty():
		return false
	formation_dragged_handle = FORMATION_DRAG_NONE
	formation_route_points.remove_at(formation_route_points.size() - 1)
	formation_plan_preview_changed.emit(formation_route_points, formation_line_start, formation_line_end, formation_line_start != formation_line_end)
	last_command_status = GameText.t(&"STATUS_ROUTE_WAYPOINT_REMOVED") % formation_route_points.size()
	return true


func clear_selected_formation_route() -> CommandValidationResult:
	if command_mode != CommandMode.FORMATION_ROUTE_TARGETING:
		return null
	var result := stop_selected()
	cancel_command_mode()
	last_command_status = GameText.t(&"STATUS_ROUTE_CLEARED") % GameText.command_result(result) if result != null else GameText.t(&"STATUS_NO_VALID_SELECTION")
	return result


func _handle_formation_route_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if formation_dragged_handle != FORMATION_DRAG_NONE:
			_move_formation_handle(_screen_to_world(motion.position))
			return
		if formation_line_drawing:
			formation_line_end = _screen_to_world(motion.position)
			_emit_formation_plan_preview()
			return
	if not event is InputEventMouseButton:
		return
	var mouse := event as InputEventMouseButton
	if mouse.button_index == MOUSE_BUTTON_LEFT:
		if mouse.pressed:
			route_feedback_override = ""
			formation_dragged_handle = _find_formation_handle(_screen_to_world(mouse.position))
			if formation_dragged_handle != FORMATION_DRAG_NONE:
				return
			if formation_route_points.size() < 8:
				formation_route_points.append(_screen_to_world(mouse.position))
				_emit_formation_plan_preview()
				last_command_status = GameText.t(&"STATUS_ROUTE_WAYPOINT_ADDED") % formation_route_points.size()
		elif formation_dragged_handle != FORMATION_DRAG_NONE:
			_move_formation_handle(_screen_to_world(mouse.position), true)
		return
	if mouse.button_index != MOUSE_BUTTON_RIGHT:
		return
	if mouse.pressed:
		formation_dragged_handle = FORMATION_DRAG_NONE
		formation_line_start = _screen_to_world(mouse.position)
		formation_line_end = formation_line_start
		formation_line_drawing = true
		_emit_formation_plan_preview()
		return
	if formation_line_drawing:
		formation_line_drawing = false
		formation_line_end = _screen_to_world(mouse.position)
		if formation_line_start.distance_to(formation_line_end) < 48.0:
			formation_line_start -= Vector2(0.0, 80.0)
			formation_line_end += Vector2(0.0, 80.0)
		_submit_formation_plan()


func _find_formation_handle(world_position: Vector2) -> int:
	var hit_radius := FORMATION_HANDLE_HIT_RADIUS_SCREEN / camera_controller.zoom.x if camera_controller != null else FORMATION_HANDLE_HIT_RADIUS_SCREEN
	var best_handle := FORMATION_DRAG_NONE
	var best_distance := hit_radius
	for index in range(formation_route_points.size()):
		var distance := formation_route_points[index].distance_to(world_position)
		if distance <= best_distance:
			best_handle = index
			best_distance = distance
	if formation_line_start != formation_line_end:
		var start_distance := formation_line_start.distance_to(world_position)
		if start_distance <= best_distance:
			best_handle = FORMATION_DRAG_LINE_START
			best_distance = start_distance
		var end_distance := formation_line_end.distance_to(world_position)
		if end_distance <= best_distance:
			best_handle = FORMATION_DRAG_LINE_END
	return best_handle


func _move_formation_handle(world_position: Vector2, finished: bool = false) -> void:
	route_feedback_override = ""
	if formation_dragged_handle >= 0 and formation_dragged_handle < formation_route_points.size():
		formation_route_points[formation_dragged_handle] = world_position
		last_command_status = GameText.t(&"STATUS_ROUTE_WAYPOINT_MOVED") % (formation_dragged_handle + 1)
	elif formation_dragged_handle == FORMATION_DRAG_LINE_START:
		formation_line_start = world_position
		last_command_status = GameText.t(&"STATUS_FORMATION_LINE_ADJUSTED")
	elif formation_dragged_handle == FORMATION_DRAG_LINE_END:
		formation_line_end = world_position
		last_command_status = GameText.t(&"STATUS_FORMATION_LINE_ADJUSTED")
	_emit_formation_plan_preview()
	if finished:
		formation_dragged_handle = FORMATION_DRAG_NONE


func _emit_formation_plan_preview() -> void:
	formation_plan_preview_changed.emit(
		formation_route_points,
		formation_line_start,
		formation_line_end,
		formation_line_start != formation_line_end
	)


func _submit_formation_plan() -> CommandValidationResult:
	var snapshot := simulation_host.current_snapshot
	var unit_card := snapshot.get_unit_card(selected_unit_card_id) if snapshot != null else null
	if unit_card == null or unit_card.formation_id == 0:
		cancel_command_mode()
		return null
	var has_deployment_line := formation_line_start.distance_to(formation_line_end) >= 48.0
	if formation_route_points.is_empty() and not has_deployment_line:
		last_command_status = GameText.t(&"STATUS_ROUTE_NEEDS_TARGET")
		return null
	var target_position := (formation_line_start + formation_line_end) * 0.5 if has_deployment_line else formation_route_points[-1]
	var result := simulation_host.submit_command(simulation_host.create_formation_move_command(
		unit_card.formation_id,
		target_position,
		GameCommand.IssuerKind.PLAYER,
		formation_route_points,
		formation_line_start,
		formation_line_end,
		has_deployment_line
	))
	last_command_status = GameText.t(&"STATUS_ROUTE_SUBMITTED") % GameText.command_result(result)
	route_feedback_override = "" if result.is_accepted() else last_command_status
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
		command_mode_changed.emit(command_mode)
		formation_route_points = PackedVector2Array()
		formation_line_start = Vector2.ZERO
		formation_line_end = Vector2.ZERO
		formation_dragged_handle = FORMATION_DRAG_NONE
		formation_plan_preview_cleared.emit()
	return result


func set_unit_card_control(unit_card_id: StringName, action: UnitCardControlCommand.Action) -> CommandValidationResult:
	var result := simulation_host.submit_command(
		simulation_host.create_unit_card_control_command(unit_card_id, action)
	)
	last_command_status = GameText.t(&"STATUS_UNIT_CARD_CONTROL") % [
		GameText.t(StringName("UNIT_CARD_CONTROL_%s" % UnitCardControlCommand.Action.keys()[action])),
		GameText.command_result(result),
	]
	return result


func select_commander_card(commander_id: StringName) -> void:
	var snapshot := simulation_host.current_snapshot
	var commander := snapshot.get_commander(commander_id) if snapshot != null else null
	if commander == null or commander.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		last_command_status = GameText.t(&"STATUS_COMMANDER_UNAVAILABLE")
		return
	simulation_host.record_playtest_ui_event("commander_card_selected", commander_id)
	var member_ids: Array[int] = []
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := snapshot.get_unit_card(unit_card_id)
		if unit_card != null:
			member_ids.append_array(unit_card.active_member_entity_ids)
	_set_selection(member_ids)
	selected_unit_card_id = &""
	selected_commander_id = commander_id
	last_command_status = GameText.t(&"STATUS_COMMANDER_SELECTED") % [
		GameText.t(commander.display_name_key), member_ids.size(),
	]


func begin_commander_drag(commander_id: StringName, start_screen_position: Vector2) -> bool:
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	var commander := snapshot.get_commander(commander_id) if snapshot != null else null
	if commander == null or commander.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		last_command_status = GameText.t(&"STATUS_COMMANDER_UNAVAILABLE")
		return false
	select_commander_card(commander_id)
	commander_drag_active = true
	commander_drag_id = commander_id
	commander_drag_start_screen = start_screen_position
	commander_drag_current_screen = start_screen_position
	last_command_status = GameText.t(&"STATUS_COMMANDER_DRAG_TARGET") % GameText.t(commander.display_name_key)
	return true


func complete_commander_drag(world_position: Vector2) -> CommandValidationResult:
	if not commander_drag_active or commander_drag_id.is_empty():
		return null
	var issued_commander_id := commander_drag_id
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	var commander := snapshot.get_commander(issued_commander_id) if snapshot != null else null
	var affected_cards := 0
	if commander != null:
		for unit_card_id in commander.subordinate_unit_card_ids:
			var card := snapshot.get_unit_card(unit_card_id)
			if card != null and card.deployment_state == UnitCardState.DeploymentState.DEPLOYED:
				affected_cards += 1
	var result := simulation_host.submit_command(
		simulation_host.create_commander_objective_command(issued_commander_id, world_position)
	)
	_clear_commander_drag()
	last_command_status = GameText.t(&"STATUS_COMMANDER_DRAG_SUBMITTED") % [
		GameText.t(commander.display_name_key) if commander != null else String(issued_commander_id),
		affected_cards,
		GameText.command_result(result),
	]
	return result


func cancel_commander_drag() -> void:
	if not commander_drag_active:
		return
	_clear_commander_drag()
	last_command_status = GameText.t(&"STATUS_COMMANDER_DRAG_CANCELLED")


func _handle_commander_drag_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_C:
			cancel_commander_drag()
			return true
		return false
	if event is InputEventMouseMotion:
		commander_drag_current_screen = (event as InputEventMouseMotion).position
		commander_intent_preview_changed.emit(commander_drag_id, _screen_to_world(commander_drag_current_screen))
		return true
	if not event is InputEventMouseButton:
		return false
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		cancel_commander_drag()
		return true
	if mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return false
	commander_drag_current_screen = mouse.position
	var viewport := get_viewport()
	var hovered := viewport.gui_get_hovered_control() if viewport != null else null
	if hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		cancel_commander_drag()
	else:
		complete_commander_drag(_screen_to_world(mouse.position))
	return true


func _clear_commander_drag() -> void:
	commander_drag_active = false
	commander_drag_id = &""
	commander_intent_preview_cleared.emit()


func _find_commander_task_handle_at(world_position: Vector2) -> StringName:
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	if snapshot == null:
		return &""
	var hit_radius := COMMANDER_TASK_HANDLE_HIT_RADIUS_SCREEN / camera_controller.zoom.x if camera_controller != null else COMMANDER_TASK_HANDLE_HIT_RADIUS_SCREEN
	if not selected_commander_id.is_empty():
		var selected_commander := snapshot.get_commander(selected_commander_id)
		if _is_draggable_commander_task(selected_commander) and _commander_task_hit_distance(selected_commander, world_position, snapshot) <= hit_radius:
			return selected_commander_id
	var closest_id: StringName
	var closest_distance := INF
	for commander in snapshot.commanders:
		if not _is_draggable_commander_task(commander):
			continue
		var distance := _commander_task_hit_distance(commander, world_position, snapshot)
		if distance <= hit_radius and distance < closest_distance:
			closest_id = commander.definition_id
			closest_distance = distance
	return closest_id


func _is_draggable_commander_task(commander: CommanderSnapshot) -> bool:
	return commander != null \
		and commander.faction_id == SimulationWorld.LOCAL_PLAYER_ID \
		and not commander.current_task_ids.is_empty() \
		and commander.target_position.is_finite()


func _commander_task_hit_distance(commander: CommanderSnapshot, world_position: Vector2, snapshot: WorldSnapshot) -> float:
	var target_distance := commander.target_position.distance_to(world_position)
	var origin := _commander_task_origin(commander, snapshot)
	if origin.distance_squared_to(commander.target_position) <= 1.0:
		return target_distance
	var closest_point := Geometry2D.get_closest_point_to_segment(world_position, origin, commander.target_position)
	return minf(target_distance, closest_point.distance_to(world_position))


func _commander_task_origin(commander: CommanderSnapshot, snapshot: WorldSnapshot) -> Vector2:
	var origin := Vector2.ZERO
	var formation_count := 0
	for unit_card_id in commander.subordinate_unit_card_ids:
		var unit_card := snapshot.get_unit_card(unit_card_id)
		if unit_card == null or unit_card.formation_id == 0:
			continue
		var formation := snapshot.get_formation(unit_card.formation_id)
		if formation != null:
			origin += formation.anchor_position
			formation_count += 1
	if formation_count > 0:
		return origin / float(formation_count)
	var headquarters := snapshot.get_building(SimulationWorld.PLAYER_COMMAND_CENTER_ID)
	return headquarters.position if headquarters != null else commander.target_position


func context_command_selected_at(world_position: Vector2) -> CommandValidationResult:
	if not selected_commander_id.is_empty() and selected_unit_card_id.is_empty():
		return issue_commander_objective(world_position)
	var enemy_id := _find_attack_target_at(world_position)
	if enemy_id != 0:
		return attack_selected_target(enemy_id)
	var ore_field_id := _find_ore_field_at(world_position)
	if ore_field_id != 0 and _selected_harvester_id() != 0:
		return _submit_harvest(_selected_harvester_id(), ore_field_id)
	return move_selected_to(world_position)


func issue_commander_objective(world_position: Vector2) -> CommandValidationResult:
	if selected_commander_id.is_empty():
		return null
	var result := simulation_host.submit_command(
		simulation_host.create_commander_objective_command(selected_commander_id, world_position)
	)
	last_command_status = GameText.t(&"STATUS_COMMANDER_OBJECTIVE") % GameText.command_result(result)
	return result


func set_commander_posture(commander_id: StringName, posture: CommanderState.Posture) -> CommandValidationResult:
	var result := simulation_host.submit_command(
		simulation_host.create_commander_posture_command(commander_id, posture)
	)
	last_command_status = GameText.t(&"STATUS_COMMANDER_POSTURE") % [
		GameText.t(StringName("COMMANDER_POSTURE_%s" % CommanderState.Posture.keys()[posture])),
		GameText.command_result(result),
	]
	return result


func equip_commander_doctrine(commander_id: StringName, doctrine_id: StringName, slot_index: int = 0) -> CommandValidationResult:
	var result := simulation_host.submit_command(
		simulation_host.create_equip_doctrine_command(commander_id, doctrine_id, slot_index)
	)
	last_command_status = GameText.t(&"STATUS_COMMANDER_DOCTRINE") % [
		GameText.t(_doctrine_display_key(doctrine_id)), GameText.command_result(result),
	]
	return result


func _doctrine_display_key(doctrine_id: StringName) -> StringName:
	return StringName("DOCTRINE_%s" % String(doctrine_id).to_upper())


func attack_selected_target(attack_target_entity_id: int) -> CommandValidationResult:
	if selected_entity_ids.is_empty():
		last_command_status = GameText.t(&"STATUS_SELECT_VEHICLE")
		return null
	var snapshot := simulation_host.current_snapshot
	var command_targets := _partition_selection_for_commands(snapshot)
	var formation_ids := command_targets["formations"] as Array[int]
	var standalone_ids := command_targets["units"] as Array[int]
	var last_result: CommandValidationResult
	for formation_id in formation_ids:
		last_result = simulation_host.submit_command(
			simulation_host.create_attack_command(0, attack_target_entity_id, formation_id)
		)
	for entity_id in standalone_ids:
		var attacker := snapshot.get_unit(entity_id)
		if attacker == null or not attacker.can_attack or not attacker.can_accept_attack_orders:
			continue
		last_result = simulation_host.submit_command(
			simulation_host.create_attack_command(entity_id, attack_target_entity_id)
		)
	if last_result != null and last_result.is_accepted():
		pending_move_active = false
		pending_intent_cleared.emit()
	if last_result == null:
		last_result = CommandValidationResult.new(
			CommandValidationResult.Status.REJECTED,
			CommandValidationResult.Reason.INVALID_DEFINITION
		)
	last_command_status = GameText.t(&"STATUS_ATTACK") % GameText.command_result(last_result)
	return last_result


func _find_attack_target_at(world_position: Vector2) -> int:
	var snapshot := simulation_host.current_snapshot
	if snapshot == null:
		return 0
	var best_id := 0
	var best_distance := INF
	var hit_radius := HIT_RADIUS_SCREEN / camera_controller.zoom.x if camera_controller != null else HIT_RADIUS_SCREEN
	for unit in snapshot.units:
		if not unit.enabled or unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID or not unit.is_visible_to_local_player:
			continue
		var distance := unit.position.distance_to(world_position)
		if distance <= hit_radius and (distance < best_distance or (is_equal_approx(distance, best_distance) and unit.entity_id < best_id)):
			best_id = unit.entity_id
			best_distance = distance
	for building in snapshot.buildings:
		if not building.enabled or building.faction_id == SimulationWorld.LOCAL_PLAYER_ID or not building.is_visible:
			continue
		var distance := building.position.distance_to(world_position)
		if distance <= hit_radius * 1.8 and (distance < best_distance or (is_equal_approx(distance, best_distance) and building.entity_id < best_id)):
			best_id = building.entity_id
			best_distance = distance
	return best_id


func begin_build_targeting(building_definition_id: StringName) -> void:
	var engineer_id := _selected_available_engineer_id()
	if engineer_id == 0:
		engineer_id = _first_available_engineer_id()
	if engineer_id == 0:
		last_command_status = GameText.t(&"STATUS_SELECT_ENGINEER")
		return
	if not selected_entity_ids.has(engineer_id) or selected_entity_ids.size() != 1:
		_set_selection([engineer_id])
	command_mode = CommandMode.BUILD_FACTORY_TARGETING if building_definition_id == &"automated_factory" else CommandMode.BUILD_SUPPORT_TARGETING
	last_command_status = GameText.t(&"STATUS_BUILD_TARGET")


func build_selected_at(building_definition_id: StringName, world_position: Vector2) -> CommandValidationResult:
	var engineer_id := _selected_engineer_id()
	if engineer_id == 0:
		last_command_status = GameText.t(&"STATUS_SELECT_ENGINEER")
		return null
	var preview := simulation_host.get_build_placement_preview(engineer_id, building_definition_id, world_position)
	var result := simulation_host.submit_command(simulation_host.create_build_building_command(engineer_id, building_definition_id, preview["position"]))
	last_command_status = GameText.t(&"STATUS_BUILD") % [GameText.building_name(building_definition_id), GameText.command_result(result)]
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
		build_preview_cleared.emit()
	else:
		_emit_build_preview(preview)
	return result


func begin_repair_targeting() -> void:
	if _selected_engineer_id() == 0:
		last_command_status = GameText.t(&"STATUS_SELECT_ENGINEER")
		return
	command_mode = CommandMode.REPAIR_TARGETING
	last_command_status = GameText.t(&"STATUS_REPAIR_TARGET")


func begin_defend_targeting() -> void:
	if _selected_strategic_unit_ids(false).is_empty():
		last_command_status = GameText.t(&"STATUS_SELECT_COMBAT_UNITS")
		return
	command_mode = CommandMode.DEFEND_TARGETING
	last_command_status = GameText.t(&"STATUS_DEFEND_TARGET")


func defend_selected_at(world_position: Vector2) -> CommandValidationResult:
	var participant_ids := _selected_strategic_unit_ids(false)
	if participant_ids.is_empty():
		last_command_status = GameText.t(&"STATUS_SELECT_COMBAT_UNITS")
		return null
	var formation_id := _complete_selected_formation_id(participant_ids, false)
	var result := simulation_host.submit_command(simulation_host.create_strategic_order_command(
		StrategicOrderCommand.OrderKind.DEFEND_AREA, formation_id, 0, world_position, 160.0, participant_ids
	))
	last_command_status = GameText.t(&"STATUS_DEFEND") % GameText.command_result(result)
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
	return result


func begin_scout_targeting() -> void:
	if _selected_strategic_unit_ids(true).is_empty():
		last_command_status = GameText.t(&"STATUS_SELECT_SCOUTS")
		return
	command_mode = CommandMode.SCOUT_TARGETING
	last_command_status = GameText.t(&"STATUS_SCOUT_TARGET")


func scout_selected_at(world_position: Vector2) -> CommandValidationResult:
	var participant_ids := _selected_strategic_unit_ids(true)
	if participant_ids.is_empty():
		last_command_status = GameText.t(&"STATUS_SELECT_SCOUTS")
		return null
	var formation_id := _complete_selected_formation_id(participant_ids, true)
	var result := simulation_host.submit_command(simulation_host.create_strategic_order_command(
		StrategicOrderCommand.OrderKind.SCOUT_AREA, formation_id, 0, world_position, 224.0, participant_ids
	))
	last_command_status = GameText.t(&"STATUS_SCOUT") % GameText.command_result(result)
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
	return result


func attack_selected_strategic_target(target_entity_id: int) -> CommandValidationResult:
	var participant_ids := _selected_strategic_unit_ids(false)
	if participant_ids.is_empty():
		last_command_status = GameText.t(&"STATUS_SELECT_COMBAT_UNITS")
		return null
	var target := simulation_host.current_snapshot.get_unit(target_entity_id)
	if target == null:
		last_command_status = GameText.t(&"ATTACK_NO_TARGET")
		return null
	var formation_id := _complete_selected_formation_id(participant_ids, false)
	var result := simulation_host.submit_command(simulation_host.create_strategic_order_command(
		StrategicOrderCommand.OrderKind.ATTACK_TARGET, formation_id, target_entity_id, target.position, 0.0, participant_ids
	))
	last_command_status = GameText.t(&"STATUS_ATTACK") % GameText.command_result(result)
	return result


func _selected_strategic_unit_ids(require_scout: bool) -> Array[int]:
	var result: Array[int] = []
	var snapshot := simulation_host.current_snapshot
	if snapshot == null:
		return result
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit == null or not _is_selectable(unit):
			continue
		if require_scout:
			if unit.definition_id == &"scout_vehicle":
				result.append(entity_id)
		elif unit.can_attack and unit.can_accept_attack_orders and not unit.can_harvest and not unit.can_construct:
			result.append(entity_id)
	result.sort()
	return result


func _complete_selected_formation_id(participant_ids: Array[int], require_scout: bool) -> int:
	if participant_ids.is_empty():
		return 0
	var snapshot := simulation_host.current_snapshot
	var first_unit := snapshot.get_unit(participant_ids[0])
	if first_unit == null or first_unit.formation_id == 0:
		return 0
	var formation := snapshot.get_formation(first_unit.formation_id)
	if formation == null:
		return 0
	var eligible_members: Array[int] = []
	for member_id in formation.member_entity_ids:
		var member := snapshot.get_unit(member_id)
		if member == null or not _is_selectable(member):
			continue
		if require_scout:
			if member.definition_id != &"scout_vehicle":
				return 0
			eligible_members.append(member_id)
		elif not require_scout and member.can_attack and member.can_accept_attack_orders and not member.can_harvest and not member.can_construct:
			eligible_members.append(member_id)
	eligible_members.sort()
	return formation.formation_id if eligible_members == participant_ids else 0


func repair_selected_at(world_position: Vector2) -> CommandValidationResult:
	var engineer_id := _selected_engineer_id()
	var building_id := _find_friendly_building_at(world_position)
	if engineer_id == 0 or building_id == 0:
		last_command_status = GameText.t(&"STATUS_REPAIR_SELECTION")
		return null
	var result := simulation_host.submit_command(simulation_host.create_repair_building_command(engineer_id, building_id))
	last_command_status = GameText.t(&"STATUS_REPAIR") % GameText.command_result(result)
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
	return result


func _selected_engineer_id() -> int:
	var snapshot := simulation_host.current_snapshot
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit != null and unit.enabled and unit.definition_id == &"engineer_vehicle":
			return entity_id
	return 0


func _selected_available_engineer_id() -> int:
	var snapshot := simulation_host.current_snapshot
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit != null and unit.enabled and unit.definition_id == &"engineer_vehicle" and unit.work_kind == UnitState.WorkKind.NONE:
			return entity_id
	return 0


func _first_available_engineer_id() -> int:
	var candidates: Array[int] = []
	for unit in simulation_host.current_snapshot.units:
		if unit.enabled and unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID and unit.definition_id == &"engineer_vehicle" and unit.work_kind == UnitState.WorkKind.NONE:
			candidates.append(unit.entity_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else 0


func _selected_harvester_id() -> int:
	var snapshot := simulation_host.current_snapshot
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit != null and unit.enabled and unit.can_harvest:
			return entity_id
	return 0


func _find_friendly_building_at(world_position: Vector2) -> int:
	var snapshot := simulation_host.current_snapshot
	var best_id := 0
	var best_distance := INF
	for building in snapshot.buildings:
		if not building.enabled or building.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
			continue
		var distance := building.position.distance_to(world_position)
		if distance <= HIT_RADIUS_SCREEN * 2.0 and distance < best_distance:
			best_id = building.entity_id
			best_distance = distance
	return best_id


func move_selected_to(world_position: Vector2) -> CommandValidationResult:
	if not selected_commander_id.is_empty() and selected_unit_card_id.is_empty():
		return issue_commander_objective(world_position)
	intent_sequence += 1
	if pending_move_active:
		coalesced_count += 1
	pending_move_target = world_position
	pending_move_active = true
	move_intent_changed.emit(world_position, intent_sequence)
	if selected_entity_ids.is_empty():
		last_command_status = GameText.t(&"STATUS_SELECT_VEHICLE")
		pending_move_active = false
		return null
	var snapshot := simulation_host.current_snapshot
	var command_targets := _partition_selection_for_commands(snapshot)
	var formation_ids := command_targets["formations"] as Array[int]
	var standalone_ids := command_targets["units"] as Array[int]
	var last_result: CommandValidationResult
	for formation_id in formation_ids:
		last_result = simulation_host.submit_command(simulation_host.create_formation_move_command(formation_id, world_position))
	for entity_id in standalone_ids:
		last_result = simulation_host.submit_command(simulation_host.create_move_command(entity_id, world_position))
	last_command_status = GameText.command_result(last_result) if last_result != null else GameText.t(&"STATUS_NO_VALID_SELECTION")
	if last_result == null or not last_result.is_accepted():
		pending_move_active = false
	return last_result


func stop_selected() -> CommandValidationResult:
	if selected_entity_ids.is_empty():
		last_command_status = GameText.t(&"STATUS_SELECT_VEHICLE")
		return null
	var snapshot := simulation_host.current_snapshot
	var command_targets := _partition_selection_for_commands(snapshot)
	var formation_ids := command_targets["formations"] as Array[int]
	var standalone_ids := command_targets["units"] as Array[int]
	var last_result: CommandValidationResult
	for formation_id in formation_ids:
		last_result = simulation_host.submit_command(simulation_host.create_stop_command(0, formation_id))
	for entity_id in standalone_ids:
		last_result = simulation_host.submit_command(simulation_host.create_stop_command(entity_id))
	if last_result != null and last_result.is_accepted():
		pending_move_active = false
		pending_intent_cleared.emit()
	last_command_status = GameText.t(&"STATUS_STOP") % GameText.command_result(last_result) if last_result != null else GameText.t(&"STATUS_NO_VALID_SELECTION")
	return last_result


func begin_attack_move_targeting() -> void:
	if not _selection_has_orderable_combat_unit():
		last_command_status = GameText.t(&"STATUS_SELECT_FORMATION")
		return
	command_mode = CommandMode.ATTACK_MOVE_TARGETING
	attack_targeting_started.emit()
	last_command_status = GameText.t(&"STATUS_ATTACK_MOVE_TARGET")


func cancel_command_mode() -> void:
	var previous_mode := command_mode
	var was_build_targeting := _is_build_targeting()
	var was_attack_targeting := command_mode == CommandMode.ATTACK_MOVE_TARGETING
	var was_formation_targeting := command_mode == CommandMode.FORMATION_ROUTE_TARGETING
	var was_commander_route_targeting := command_mode == CommandMode.COMMANDER_ROUTE_TARGETING
	command_mode = CommandMode.NORMAL
	route_feedback_override = ""
	if previous_mode != command_mode:
		command_mode_changed.emit(command_mode)
	last_command_status = GameText.t(&"STATUS_TARGETING_CANCELLED")
	if was_build_targeting:
		build_preview_cleared.emit()
	if was_attack_targeting:
		attack_preview_cleared.emit()
	if was_formation_targeting:
		formation_line_drawing = false
		formation_dragged_handle = FORMATION_DRAG_NONE
		formation_route_points = PackedVector2Array()
		formation_plan_preview_cleared.emit()
	if was_commander_route_targeting:
		commander_route_points = PackedVector2Array()
		commander_plan_preview_cleared.emit()


func _is_build_targeting() -> bool:
	return command_mode in [CommandMode.BUILD_FACTORY_TARGETING, CommandMode.BUILD_SUPPORT_TARGETING]


func _update_build_preview(world_position: Vector2) -> void:
	var engineer_id := _selected_engineer_id()
	if engineer_id == 0:
		build_preview_cleared.emit()
		return
	var definition_id: StringName = &"automated_factory" if command_mode == CommandMode.BUILD_FACTORY_TARGETING else &"forward_support_station"
	_emit_build_preview(simulation_host.get_build_placement_preview(engineer_id, definition_id, world_position))


func _emit_build_preview(preview: Dictionary) -> void:
	build_preview_changed.emit(preview["position"], preview["footprint_size"], preview["valid"], preview["engineer_position"])


func _update_attack_preview(world_position: Vector2) -> void:
	attack_preview_changed.emit(world_position, _find_attack_target_at(world_position))


func attack_or_move_selected_at(world_position: Vector2) -> CommandValidationResult:
	var target_id := _find_attack_target_at(world_position)
	var last_seen_contact := _find_last_seen_contact_at(world_position) if target_id == 0 else null
	var destination := last_seen_contact.position if last_seen_contact != null else world_position
	var result := attack_selected_target(target_id) if target_id != 0 else attack_move_selected_to(destination)
	if last_seen_contact != null and result != null:
		last_command_status = GameText.t(&"STATUS_ATTACK_MOVE_LAST_SEEN") % GameText.command_result(result)
	if result != null and result.is_accepted():
		command_mode = CommandMode.NORMAL
		attack_preview_cleared.emit()
	return result


func _find_last_seen_contact_at(world_position: Vector2) -> UnitSnapshot:
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	if snapshot == null:
		return null
	var hit_radius := HIT_RADIUS_SCREEN / camera_controller.zoom.x if camera_controller != null else HIT_RADIUS_SCREEN
	var nearest: UnitSnapshot
	var nearest_distance := INF
	for unit in snapshot.units:
		if not unit.enabled or unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID or unit.is_visible_to_local_player:
			continue
		var distance := unit.position.distance_to(world_position)
		if distance <= hit_radius and distance < nearest_distance:
			nearest = unit
			nearest_distance = distance
	return nearest


func attack_move_selected_to(world_position: Vector2) -> CommandValidationResult:
	var snapshot := simulation_host.current_snapshot
	var command_targets := _partition_selection_for_commands(snapshot)
	var formation_ids := command_targets["formations"] as Array[int]
	var standalone_ids := command_targets["units"] as Array[int]
	var last_result: CommandValidationResult
	for formation_id in formation_ids:
		last_result = simulation_host.submit_command(simulation_host.create_attack_move_command(formation_id, world_position))
	for entity_id in standalone_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit == null or not unit.can_attack or not unit.can_accept_attack_orders:
			continue
		last_result = simulation_host.submit_command(simulation_host.create_attack_move_command(0, world_position, entity_id))
	if last_result == null:
		last_command_status = GameText.t(&"STATUS_ATTACK_MOVE_FORMATION")
		return null
	if last_result != null and last_result.is_accepted():
		intent_sequence += 1
		pending_move_target = world_position
		pending_move_active = true
		move_intent_changed.emit(world_position, intent_sequence)
	last_command_status = GameText.t(&"STATUS_ATTACK_MOVE") % GameText.command_result(last_result)
	return last_result


func _selection_has_orderable_combat_unit() -> bool:
	var snapshot := simulation_host.current_snapshot
	if snapshot == null:
		return false
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit != null and unit.enabled and unit.can_attack and unit.can_accept_attack_orders:
			return true
	return false


func harvest_with_selected() -> CommandValidationResult:
	var harvester_id := _selected_harvester_id()
	if harvester_id == 0:
		last_command_status = GameText.t(&"STATUS_SELECT_HARVESTER")
		return null
	if selected_entity_ids.size() == 1:
		var ore_field_id := _single_available_ore_field_id()
		if ore_field_id != 0:
			return _submit_harvest(harvester_id, ore_field_id)
	command_mode = CommandMode.HARVEST_TARGETING
	last_command_status = GameText.t(&"STATUS_HARVEST_TARGET")
	return null


func harvest_selected_at(world_position: Vector2) -> CommandValidationResult:
	var harvester_id := _selected_harvester_id()
	var ore_field_id := _find_ore_field_at(world_position)
	if harvester_id == 0 or ore_field_id == 0:
		last_command_status = GameText.t(&"STATUS_HARVEST_SELECTION")
		return null
	return _submit_harvest(harvester_id, ore_field_id)


func _submit_harvest(harvester_id: int, ore_field_id: int) -> CommandValidationResult:
	var refinery_id := _closest_friendly_refinery(ore_field_id)
	if refinery_id == 0:
		last_command_status = GameText.t(&"STATUS_HARVEST_SELECTION")
		return null
	var result := simulation_host.submit_command(simulation_host.create_harvest_command(harvester_id, ore_field_id, refinery_id))
	last_command_status = GameText.t(&"STATUS_HARVEST") % GameText.command_result(result)
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
	return result


func _find_ore_field_at(world_position: Vector2) -> int:
	var snapshot := simulation_host.current_snapshot
	var best_id := 0
	var best_distance := INF
	for ore_field in snapshot.ore_fields:
		var distance := ore_field.position.distance_to(world_position)
		if ore_field.ore_remaining > 0 and distance <= HIT_RADIUS_SCREEN * 2.0 and distance < best_distance:
			best_id = ore_field.entity_id
			best_distance = distance
	return best_id


func _single_available_ore_field_id() -> int:
	var result := 0
	for ore_field in simulation_host.current_snapshot.ore_fields:
		if ore_field.ore_remaining <= 0:
			continue
		if result != 0:
			return 0
		result = ore_field.entity_id
	return result


func _closest_friendly_refinery(ore_field_id: int) -> int:
	var snapshot := simulation_host.current_snapshot
	var ore_field := snapshot.get_ore_field(ore_field_id)
	var best_id := 0
	var best_distance := INF
	if ore_field == null:
		return 0
	for building in snapshot.buildings:
		if building.enabled and building.operational and building.faction_id == SimulationWorld.LOCAL_PLAYER_ID and building.definition_id == &"command_center":
			var distance := building.position.distance_squared_to(ore_field.position)
			if distance < best_distance:
				best_id = building.entity_id
				best_distance = distance
	return best_id


func produce_unit(unit_definition_id: StringName) -> CommandValidationResult:
	if selected_building_id == 0:
		last_command_status = GameText.t(&"STATUS_SELECT_FACTORY")
		return null
	var result := simulation_host.submit_command(simulation_host.create_produce_unit_command(selected_building_id, unit_definition_id))
	last_command_status = GameText.t(&"STATUS_PRODUCE") % [GameText.unit_name(unit_definition_id), GameText.command_result(result)]
	return result


func cancel_selected_production() -> CommandValidationResult:
	if selected_building_id == 0:
		last_command_status = GameText.t(&"STATUS_SELECT_PRODUCTION_BUILDING")
		return null
	var result := simulation_host.submit_command(simulation_host.create_cancel_production_command(selected_building_id))
	last_command_status = GameText.t(&"STATUS_CANCEL_PRODUCTION") % GameText.command_result(result)
	return result


func begin_rally_targeting() -> void:
	if selected_building_id == 0:
		last_command_status = GameText.t(&"STATUS_SELECT_PRODUCTION_BUILDING")
		return
	var building := simulation_host.current_snapshot.get_building(selected_building_id)
	var definition := SimulationWorld.BUILDING_CATALOG.get_building(building.definition_id) if building != null else null
	if definition == null or definition.production_catalog.is_empty():
		last_command_status = GameText.t(&"STATUS_SELECT_PRODUCTION_BUILDING")
		return
	command_mode = CommandMode.RALLY_TARGETING
	last_command_status = GameText.t(&"STATUS_RALLY_TARGET")


func set_selected_rally_point(world_position: Vector2) -> CommandValidationResult:
	if selected_building_id == 0:
		last_command_status = GameText.t(&"STATUS_SELECT_PRODUCTION_BUILDING")
		return null
	var result := simulation_host.submit_command(simulation_host.create_set_rally_point_command(selected_building_id, world_position))
	last_command_status = GameText.t(&"STATUS_RALLY") % GameText.command_result(result)
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
	return result


func produce_scout() -> CommandValidationResult:
	var result := simulation_host.submit_command(simulation_host.create_produce_unit_command(SimulationWorld.PLAYER_FACTORY_ID, &"scout_vehicle"))
	last_command_status = GameText.t(&"STATUS_PRODUCE") % [GameText.unit_name(&"scout_vehicle"), GameText.command_result(result)]
	return result


func assign_control_group(group_number: int) -> void:
	control_groups[group_number] = selected_entity_ids.duplicate()
	last_command_status = GameText.t(&"STATUS_GROUP_ASSIGNED") % [group_number, selected_entity_ids.size()]


func recall_control_group(group_number: int, additive: bool = false) -> void:
	var stored: Array[int] = []
	stored.assign(control_groups.get(group_number, []))
	var recalled: Array[int] = []
	if additive:
		recalled.assign(selected_entity_ids)
	var snapshot := simulation_host.current_snapshot
	for entity_id in stored:
		var unit := snapshot.get_unit(entity_id)
		if unit != null and _is_selectable(unit):
			recalled.append(entity_id)
	_set_selection(recalled)
	last_command_status = GameText.t(&"STATUS_GROUP_RECALLED") % [group_number, selected_entity_ids.size()]


func set_selected_disposition(disposition: UnitDispositionCommand.Disposition, destination_formation_id: int = 0) -> CommandValidationResult:
	if not selected_unit_card_id.is_empty() and disposition == UnitDispositionCommand.Disposition.RETURN:
		return set_unit_card_control(selected_unit_card_id, UnitCardControlCommand.Action.RETURN_TO_COMMANDER)
	if selected_entity_ids.size() != 1:
		last_command_status = GameText.t(&"STATUS_ALT_SELECT")
		return null
	var result := simulation_host.submit_command(simulation_host.create_unit_disposition_command(selected_entity_id, disposition, destination_formation_id))
	last_command_status = GameText.t(&"STATUS_DISPOSITION") % [UnitDispositionCommand.Disposition.keys()[disposition], GameText.command_result(result)]
	return result


func _handle_key(event: InputEventKey) -> void:
	if command_mode == CommandMode.COMMANDER_ROUTE_TARGETING and event.keycode == KEY_BACKSPACE:
		undo_commander_route_waypoint()
		return
	if command_mode == CommandMode.COMMANDER_ROUTE_TARGETING and event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not commander_route_points.is_empty():
		submit_selected_commander_route()
		return
	if command_mode == CommandMode.FORMATION_ROUTE_TARGETING:
		if event.keycode == KEY_BACKSPACE:
			undo_formation_route_waypoint()
			return
		if event.keycode == KEY_DELETE:
			clear_selected_formation_route()
			return
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_submit_formation_plan()
			return
	if event.keycode == KEY_F3 and not event.echo:
		diagnostic_individual_selection_enabled = not diagnostic_individual_selection_enabled
		if diagnostic_individual_selection_enabled and simulation_host != null:
			simulation_host.record_playtest_ui_event("diagnostic_individual_mode_enabled")
		return
	if event.keycode == KEY_C:
		cancel_command_mode()
		return
	if event.keycode == KEY_R and not event.ctrl_pressed and not event.alt_pressed:
		set_selected_disposition(UnitDispositionCommand.Disposition.RETURN)
		return
	if event.keycode == KEY_Y and not event.ctrl_pressed and not event.alt_pressed:
		set_selected_disposition(UnitDispositionCommand.Disposition.STAY)
		return
	if event.keycode == KEY_J and not event.ctrl_pressed and not event.alt_pressed:
		set_selected_disposition(UnitDispositionCommand.Disposition.JOIN, SimulationWorld.DEFAULT_FORMATION_ID)
		return
	if event.keycode == KEY_M and not event.ctrl_pressed and not event.alt_pressed:
		set_selected_disposition(UnitDispositionCommand.Disposition.MANUAL)
		return
	if event.keycode == KEY_X and not event.ctrl_pressed and not event.alt_pressed:
		stop_selected()
		return
	if event.keycode in [KEY_Q, KEY_T] and not event.ctrl_pressed and not event.alt_pressed:
		begin_attack_move_targeting()
		return
	if event.keycode == KEY_H and not event.ctrl_pressed and not event.alt_pressed:
		harvest_with_selected()
		return
	if event.keycode == KEY_P and not event.ctrl_pressed and not event.alt_pressed:
		produce_scout()
		return
	if event.keycode == KEY_B and not event.ctrl_pressed and not event.alt_pressed:
		begin_build_targeting(&"automated_factory")
		return
	if event.keycode == KEY_N and not event.ctrl_pressed and not event.alt_pressed:
		begin_build_targeting(&"forward_support_station")
		return
	if event.keycode == KEY_V and not event.ctrl_pressed and not event.alt_pressed:
		begin_repair_targeting()
		return
	var group_number := _keycode_to_group(event.keycode)
	if group_number == 0:
		return
	if event.ctrl_pressed:
		assign_control_group(group_number)
	else:
		recall_control_group(group_number, event.shift_pressed)


func _keycode_to_group(keycode: Key) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return int(keycode - KEY_0)
	return 0


func _get_selection_atom(entity_id: int) -> Array[int]:
	var snapshot := simulation_host.current_snapshot
	var unit := snapshot.get_unit(entity_id)
	if unit == null or unit.formation_id == 0:
		return [entity_id]
	var formation := snapshot.get_formation(unit.formation_id)
	var result: Array[int] = []
	if formation != null:
		for member_id in formation.member_entity_ids:
			var member := snapshot.get_unit(member_id)
			if member != null and _is_selectable(member) and member.formation_id == unit.formation_id:
				result.append(member_id)
	return result


func _partition_selection_for_commands(snapshot: WorldSnapshot) -> Dictionary:
	var complete_formations: Array[int] = []
	var standalone_units: Array[int] = []
	var candidate_formations: Array[int] = []
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id) if snapshot != null else null
		if unit != null and _is_selectable(unit) and unit.formation_id != 0 and not candidate_formations.has(unit.formation_id):
			candidate_formations.append(unit.formation_id)
	for formation_id in candidate_formations:
		var formation := snapshot.get_formation(formation_id)
		if formation == null:
			continue
		var complete := true
		for member_id in formation.member_entity_ids:
			var member := snapshot.get_unit(member_id)
			if member == null or not _is_selectable(member) or member.formation_id != formation_id or not selected_entity_ids.has(member_id):
				complete = false
				break
		if complete:
			complete_formations.append(formation_id)
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id) if snapshot != null else null
		if unit != null and _is_selectable(unit) and not complete_formations.has(unit.formation_id):
			standalone_units.append(entity_id)
	complete_formations.sort()
	standalone_units.sort()
	return {"formations": complete_formations, "units": standalone_units}


func prune_selection() -> void:
	var valid_ids: Array[int] = []
	var snapshot := simulation_host.current_snapshot
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id) if snapshot != null else null
		if unit != null and _is_selectable(unit):
			valid_ids.append(entity_id)
	if valid_ids != selected_entity_ids:
		_set_selection(valid_ids)


func reset_for_new_scenario() -> void:
	if commander_drag_active:
		_clear_commander_drag()
	command_mode = CommandMode.NORMAL
	route_feedback_override = ""
	pending_move_active = false
	left_dragging = false
	formation_line_drawing = false
	formation_route_points = PackedVector2Array()
	control_groups.clear()
	selected_entity_ids.clear()
	selected_entity_id = 0
	selected_building_id = 0
	selected_unit_card_id = &""
	selected_commander_id = &""
	pending_intent_cleared.emit()
	build_preview_cleared.emit()
	attack_preview_cleared.emit()
	formation_plan_preview_cleared.emit()
	world_presentation.set_selected_entities([], 0, 0)
	refresh_locale_status()


func _set_selection(entity_ids: Array[int]) -> void:
	var unique: Dictionary = {}
	for entity_id in entity_ids:
		unique[entity_id] = true
	selected_entity_ids.assign(unique.keys())
	selected_entity_ids.sort()
	selected_entity_id = selected_entity_ids[0] if not selected_entity_ids.is_empty() else 0
	selected_building_id = 0
	_sync_army_card_selection()
	world_presentation.set_selected_entities(selected_entity_ids, selected_entity_id, selected_building_id)


func _set_building_selection(building_id: int) -> void:
	selected_entity_ids.clear()
	selected_entity_id = 0
	selected_building_id = building_id
	selected_unit_card_id = &""
	selected_commander_id = &""
	world_presentation.set_selected_entities([], 0, selected_building_id)


func _sync_army_card_selection() -> void:
	selected_unit_card_id = &""
	selected_commander_id = &""
	var snapshot := simulation_host.current_snapshot if simulation_host != null else null
	if snapshot == null or selected_entity_ids.is_empty():
		return
	for unit_card in snapshot.unit_cards:
		if unit_card.active_member_entity_ids == selected_entity_ids:
			selected_unit_card_id = unit_card.definition_id
			selected_commander_id = unit_card.commander_definition_id
			return


func _is_selectable(unit: UnitSnapshot) -> bool:
	return unit.enabled and unit.controller_id == SimulationWorld.LOCAL_PLAYER_ID


func _formal_card_selection_enabled() -> bool:
	return simulation_host != null and SimulationWorld.is_card_battle_kind(simulation_host.scenario_kind) and not diagnostic_individual_selection_enabled


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return camera_controller.screen_to_world(screen_position) if camera_controller != null else screen_position
