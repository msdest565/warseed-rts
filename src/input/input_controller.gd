class_name InputController
extends Node

enum CommandMode {
	NORMAL,
	ATTACK_MOVE_TARGETING,
}

signal move_intent_changed(target_position: Vector2, intent_sequence: int)
signal pending_intent_cleared

const HIT_RADIUS_SCREEN := 34.0
const DRAG_THRESHOLD := 6.0

var selected_entity_id: int = 0
var selected_entity_ids: Array[int] = []
var intent_sequence: int = 0
var pending_move_target: Vector2
var pending_move_active: bool = false
var coalesced_count: int = 0
var last_command_status: String = "Ready - select a vehicle"
var control_groups: Dictionary = {}
var drag_start_screen: Vector2
var drag_current_screen: Vector2
var left_dragging: bool = false
var command_mode: CommandMode = CommandMode.NORMAL

@export var simulation_host: SimulationHost
@export var world_presentation: WorldPresentation
@export var camera_controller: CameraController
@export var selection_overlay: SelectionOverlay


func _unhandled_input(event: InputEvent) -> void:
	if camera_controller != null and camera_controller.handle_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)
		return
	if command_mode == CommandMode.ATTACK_MOVE_TARGETING and event is InputEventMouseButton:
		var targeting_mouse := event as InputEventMouseButton
		if targeting_mouse.pressed and targeting_mouse.button_index == MOUSE_BUTTON_RIGHT:
			cancel_command_mode()
			return
		if targeting_mouse.pressed and targeting_mouse.button_index == MOUSE_BUTTON_LEFT:
			attack_move_selected_to(_screen_to_world(targeting_mouse.position))
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


func _finish_selection(screen_position: Vector2, additive: bool, single_unit: bool = false) -> void:
	if drag_start_screen.distance_to(screen_position) <= DRAG_THRESHOLD:
		select_at(_screen_to_world(screen_position), additive, single_unit)
	else:
		var world_start := _screen_to_world(drag_start_screen)
		var world_end := _screen_to_world(screen_position)
		select_in_rect(Rect2(world_start, world_end - world_start).abs(), additive)


func select_at(world_position: Vector2, additive: bool = false, single_unit: bool = false) -> void:
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
		if not additive:
			_set_selection([])
			last_command_status = "Selection cleared"
		return
	var atom: Array[int] = [best_id] if single_unit else _get_selection_atom(best_id)
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
	last_command_status = "Selected %d unit(s)" % selected_entity_ids.size()


func select_in_rect(world_rect: Rect2, additive: bool = false) -> void:
	var matches: Array[int] = []
	var snapshot := simulation_host.current_snapshot
	if snapshot != null:
		for unit in snapshot.units:
			if _is_selectable(unit) and world_rect.has_point(unit.position):
				matches.append_array(_get_selection_atom(unit.entity_id))
	if matches.is_empty() and additive:
		return
	if additive:
		matches.append_array(selected_entity_ids)
	_set_selection(matches)
	last_command_status = "Selected %d unit(s)" % selected_entity_ids.size()


func context_command_selected_at(world_position: Vector2) -> CommandValidationResult:
	var enemy_id := _find_attack_target_at(world_position)
	if enemy_id != 0:
		return attack_selected_target(enemy_id)
	return move_selected_to(world_position)


func attack_selected_target(attack_target_entity_id: int) -> CommandValidationResult:
	if selected_entity_ids.is_empty():
		last_command_status = "Rejected: select a vehicle first"
		return null
	var snapshot := simulation_host.current_snapshot
	var formation_ids: Array[int] = []
	var standalone_ids: Array[int] = []
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit == null or not _is_selectable(unit):
			continue
		if unit.formation_id != 0:
			if not formation_ids.has(unit.formation_id):
				formation_ids.append(unit.formation_id)
		else:
			standalone_ids.append(entity_id)
	formation_ids.sort()
	standalone_ids.sort()
	var last_result: CommandValidationResult
	for formation_id in formation_ids:
		last_result = simulation_host.submit_command(
			simulation_host.create_attack_command(0, attack_target_entity_id, formation_id)
		)
	for entity_id in standalone_ids:
		last_result = simulation_host.submit_command(
			simulation_host.create_attack_command(entity_id, attack_target_entity_id)
		)
	if last_result != null and last_result.is_accepted():
		pending_move_active = false
		pending_intent_cleared.emit()
	last_command_status = "Attack: %s" % last_result.describe() if last_result != null else "Rejected: no valid selection"
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
	return best_id


func move_selected_to(world_position: Vector2) -> CommandValidationResult:
	intent_sequence += 1
	if pending_move_active:
		coalesced_count += 1
	pending_move_target = world_position
	pending_move_active = true
	move_intent_changed.emit(world_position, intent_sequence)
	if selected_entity_ids.is_empty():
		last_command_status = "Rejected: select a vehicle first"
		pending_move_active = false
		return null
	var formation_ids: Array[int] = []
	var standalone_ids: Array[int] = []
	var snapshot := simulation_host.current_snapshot
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit == null:
			continue
		if unit.formation_id != 0:
			if not formation_ids.has(unit.formation_id):
				formation_ids.append(unit.formation_id)
		else:
			standalone_ids.append(entity_id)
	formation_ids.sort()
	standalone_ids.sort()
	var last_result: CommandValidationResult
	for formation_id in formation_ids:
		last_result = simulation_host.submit_command(simulation_host.create_formation_move_command(formation_id, world_position))
	for entity_id in standalone_ids:
		last_result = simulation_host.submit_command(simulation_host.create_move_command(entity_id, world_position))
	last_command_status = last_result.describe() if last_result != null else "Rejected: no valid selection"
	if last_result == null or not last_result.is_accepted():
		pending_move_active = false
	return last_result


func stop_selected() -> CommandValidationResult:
	if selected_entity_ids.is_empty():
		last_command_status = "Rejected: select a vehicle first"
		return null
	var snapshot := simulation_host.current_snapshot
	var formation_ids: Array[int] = []
	var standalone_ids: Array[int] = []
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit == null:
			continue
		if unit.formation_id != 0:
			if not formation_ids.has(unit.formation_id):
				formation_ids.append(unit.formation_id)
		else:
			standalone_ids.append(entity_id)
	formation_ids.sort()
	standalone_ids.sort()
	var last_result: CommandValidationResult
	for formation_id in formation_ids:
		last_result = simulation_host.submit_command(simulation_host.create_stop_command(0, formation_id))
	for entity_id in standalone_ids:
		last_result = simulation_host.submit_command(simulation_host.create_stop_command(entity_id))
	if last_result != null and last_result.is_accepted():
		pending_move_active = false
		pending_intent_cleared.emit()
	last_command_status = "Stop: %s" % last_result.describe() if last_result != null else "Rejected: no valid selection"
	return last_result


func begin_attack_move_targeting() -> void:
	if selected_entity_ids.is_empty():
		last_command_status = "Rejected: select a formation first"
		return
	command_mode = CommandMode.ATTACK_MOVE_TARGETING
	last_command_status = "Attack-move: left click target, RMB/Esc cancel"


func cancel_command_mode() -> void:
	command_mode = CommandMode.NORMAL
	last_command_status = "Attack-move cancelled"


func attack_move_selected_to(world_position: Vector2) -> CommandValidationResult:
	var snapshot := simulation_host.current_snapshot
	var formation_ids: Array[int] = []
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit != null and unit.formation_id != 0 and not formation_ids.has(unit.formation_id):
			formation_ids.append(unit.formation_id)
	if formation_ids.is_empty():
		last_command_status = "Rejected: AttackMove requires a formation"
		return null
	formation_ids.sort()
	var last_result: CommandValidationResult
	for formation_id in formation_ids:
		last_result = simulation_host.submit_command(simulation_host.create_attack_move_command(formation_id, world_position))
	if last_result != null and last_result.is_accepted():
		intent_sequence += 1
		pending_move_target = world_position
		pending_move_active = true
		move_intent_changed.emit(world_position, intent_sequence)
		command_mode = CommandMode.NORMAL
	last_command_status = "AttackMove: %s" % last_result.describe() if last_result != null else "Rejected"
	return last_result


func harvest_with_selected() -> CommandValidationResult:
	var harvester_id := 0
	var snapshot := simulation_host.current_snapshot
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id)
		if unit != null and unit.definition_id == &"harvester":
			harvester_id = entity_id
			break
	if harvester_id == 0:
		last_command_status = "Rejected: select the harvester"
		return null
	var result := simulation_host.submit_command(simulation_host.create_harvest_command(harvester_id, SimulationWorld.DEFAULT_ORE_FIELD_ID, SimulationWorld.PLAYER_COMMAND_CENTER_ID))
	last_command_status = "Harvest: %s" % result.describe()
	return result


func produce_scout() -> CommandValidationResult:
	var result := simulation_host.submit_command(simulation_host.create_produce_unit_command(SimulationWorld.PLAYER_FACTORY_ID, &"scout_vehicle"))
	last_command_status = "Produce Scout: %s" % result.describe()
	return result


func assign_control_group(group_number: int) -> void:
	control_groups[group_number] = selected_entity_ids.duplicate()
	last_command_status = "Assigned group %d (%d units)" % [group_number, selected_entity_ids.size()]


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
			recalled.append_array(_get_selection_atom(entity_id))
	_set_selection(recalled)
	last_command_status = "Recalled group %d (%d units)" % [group_number, selected_entity_ids.size()]


func set_selected_disposition(disposition: UnitDispositionCommand.Disposition, destination_formation_id: int = 0) -> CommandValidationResult:
	if selected_entity_ids.size() != 1:
		last_command_status = "Rejected: Alt-select one unit first"
		return null
	var result := simulation_host.submit_command(simulation_host.create_unit_disposition_command(selected_entity_id, disposition, destination_formation_id))
	last_command_status = "Disposition %s: %s" % [UnitDispositionCommand.Disposition.keys()[disposition], result.describe()]
	return result


func _handle_key(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
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
	if event.keycode == KEY_T and not event.ctrl_pressed and not event.alt_pressed:
		begin_attack_move_targeting()
		return
	if event.keycode == KEY_H and not event.ctrl_pressed and not event.alt_pressed:
		harvest_with_selected()
		return
	if event.keycode == KEY_P and not event.ctrl_pressed and not event.alt_pressed:
		produce_scout()
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
			if member != null and _is_selectable(member):
				result.append(member_id)
	return result


func prune_selection() -> void:
	var valid_ids: Array[int] = []
	var snapshot := simulation_host.current_snapshot
	for entity_id in selected_entity_ids:
		var unit := snapshot.get_unit(entity_id) if snapshot != null else null
		if unit != null and _is_selectable(unit):
			valid_ids.append(entity_id)
	if valid_ids != selected_entity_ids:
		_set_selection(valid_ids)


func _set_selection(entity_ids: Array[int]) -> void:
	var unique: Dictionary = {}
	for entity_id in entity_ids:
		unique[entity_id] = true
	selected_entity_ids.assign(unique.keys())
	selected_entity_ids.sort()
	selected_entity_id = selected_entity_ids[0] if not selected_entity_ids.is_empty() else 0
	world_presentation.set_selected_entities(selected_entity_ids, selected_entity_id)


func _is_selectable(unit: UnitSnapshot) -> bool:
	return unit.enabled and unit.controller_id == SimulationWorld.LOCAL_PLAYER_ID


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return camera_controller.screen_to_world(screen_position) if camera_controller != null else screen_position
