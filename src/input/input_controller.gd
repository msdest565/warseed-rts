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
}

signal move_intent_changed(target_position: Vector2, intent_sequence: int)
signal pending_intent_cleared
signal build_preview_changed(build_position: Vector2, footprint_size: Vector2i, valid: bool, engineer_position: Vector2)
signal build_preview_cleared
signal attack_targeting_started
signal attack_preview_changed(target_position: Vector2, target_entity_id: int)
signal attack_preview_cleared

const HIT_RADIUS_SCREEN := 34.0
const DRAG_THRESHOLD := 6.0

var selected_entity_id: int = 0
var selected_entity_ids: Array[int] = []
var selected_building_id: int = 0
var intent_sequence: int = 0
var pending_move_target: Vector2
var pending_move_active: bool = false
var coalesced_count: int = 0
var last_command_status: String = ""
var control_groups: Dictionary = {}
var drag_start_screen: Vector2
var drag_current_screen: Vector2
var left_dragging: bool = false
var command_mode: CommandMode = CommandMode.NORMAL

@export var simulation_host: SimulationHost
@export var world_presentation: WorldPresentation
@export var camera_controller: CameraController
@export var selection_overlay: SelectionOverlay


func _ready() -> void:
	refresh_locale_status()


func refresh_locale_status() -> void:
	last_command_status = GameText.t(&"STATUS_READY")


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
	if command_mode in [CommandMode.HARVEST_TARGETING, CommandMode.DEFEND_TARGETING] and event is InputEventMouseButton:
		var target_mouse := event as InputEventMouseButton
		if target_mouse.pressed and target_mouse.button_index == MOUSE_BUTTON_RIGHT:
			cancel_command_mode()
			return
		if target_mouse.pressed and target_mouse.button_index == MOUSE_BUTTON_LEFT:
			var target_position := _screen_to_world(target_mouse.position)
			if command_mode == CommandMode.HARVEST_TARGETING:
				harvest_selected_at(target_position)
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
	if select_formation:
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
				matches.append(unit.entity_id)
	if matches.is_empty() and additive:
		return
	if additive:
		matches.append_array(selected_entity_ids)
	_set_selection(matches)
	last_command_status = GameText.t(&"STATUS_SELECTED") % selected_entity_ids.size()


func context_command_selected_at(world_position: Vector2) -> CommandValidationResult:
	var enemy_id := _find_attack_target_at(world_position)
	if enemy_id != 0:
		return attack_selected_target(enemy_id)
	var ore_field_id := _find_ore_field_at(world_position)
	if ore_field_id != 0 and _selected_harvester_id() != 0:
		return _submit_harvest(_selected_harvester_id(), ore_field_id)
	return move_selected_to(world_position)


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
	last_command_status = GameText.t(&"STATUS_ATTACK") % GameText.command_result(last_result) if last_result != null else GameText.t(&"STATUS_NO_VALID_SELECTION")
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
	var formation := simulation_host.current_snapshot.get_formation(SimulationWorld.DEFAULT_FORMATION_ID)
	if formation == null:
		last_command_status = GameText.t(&"DEFENSE_NO_FORMATION")
		return
	command_mode = CommandMode.DEFEND_TARGETING
	last_command_status = GameText.t(&"STATUS_DEFEND_TARGET")


func defend_selected_at(world_position: Vector2) -> CommandValidationResult:
	var formation := simulation_host.current_snapshot.get_formation(SimulationWorld.DEFAULT_FORMATION_ID)
	if formation == null:
		last_command_status = GameText.t(&"DEFENSE_NO_FORMATION")
		return null
	var result := simulation_host.submit_command(simulation_host.create_strategic_order_command(
		StrategicOrderCommand.OrderKind.DEFEND_AREA, formation.formation_id, 0, world_position, 160.0
	))
	last_command_status = GameText.t(&"STATUS_DEFEND") % GameText.command_result(result)
	if result.is_accepted():
		command_mode = CommandMode.NORMAL
	return result


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
	var was_build_targeting := _is_build_targeting()
	var was_attack_targeting := command_mode == CommandMode.ATTACK_MOVE_TARGETING
	command_mode = CommandMode.NORMAL
	last_command_status = GameText.t(&"STATUS_TARGETING_CANCELLED")
	if was_build_targeting:
		build_preview_cleared.emit()
	if was_attack_targeting:
		attack_preview_cleared.emit()


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
	var result := attack_selected_target(target_id) if target_id != 0 else attack_move_selected_to(world_position)
	if result != null and result.is_accepted():
		command_mode = CommandMode.NORMAL
		attack_preview_cleared.emit()
	return result


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
	if selected_entity_ids.size() != 1:
		last_command_status = GameText.t(&"STATUS_ALT_SELECT")
		return null
	var result := simulation_host.submit_command(simulation_host.create_unit_disposition_command(selected_entity_id, disposition, destination_formation_id))
	last_command_status = GameText.t(&"STATUS_DISPOSITION") % [UnitDispositionCommand.Disposition.keys()[disposition], GameText.command_result(result)]
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


func _set_selection(entity_ids: Array[int]) -> void:
	var unique: Dictionary = {}
	for entity_id in entity_ids:
		unique[entity_id] = true
	selected_entity_ids.assign(unique.keys())
	selected_entity_ids.sort()
	selected_entity_id = selected_entity_ids[0] if not selected_entity_ids.is_empty() else 0
	selected_building_id = 0
	world_presentation.set_selected_entities(selected_entity_ids, selected_entity_id, selected_building_id)


func _set_building_selection(building_id: int) -> void:
	selected_entity_ids.clear()
	selected_entity_id = 0
	selected_building_id = building_id
	world_presentation.set_selected_entities([], 0, selected_building_id)


func _is_selectable(unit: UnitSnapshot) -> bool:
	return unit.enabled and unit.controller_id == SimulationWorld.LOCAL_PLAYER_ID


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return camera_controller.screen_to_world(screen_position) if camera_controller != null else screen_position
