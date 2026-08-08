class_name GameRoot
extends Node

@onready var simulation_host: SimulationHost = $SimulationHost
@onready var world_presentation: WorldPresentation = $WorldPresentation
@onready var input_controller: InputController = $InputController
@onready var camera_controller: CameraController = $CameraController
@onready var selection_overlay: SelectionOverlay = $SelectionLayer/SelectionOverlay
@onready var minimap: MinimapControl = $HUDLayer/Minimap
@onready var task_panel: TaskPanel = $HUDLayer/TaskPanel
@onready var resource_bar = $HUDLayer/ResourceBar
@onready var workflow_panel: WorkflowPanel = $HUDLayer/WorkflowPanel
@onready var debug_layer: DebugLayer = $DebugLayer
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var hover_tooltip: HoverTooltip = $HoverTooltip
@onready var contact_alert: ContactAlert = $HUDLayer/ContactAlert

var _last_ui_snapshot_tick: int = -1
var _visible_hostile_ids: Dictionary = {}
var _last_contact_alert_tick: Dictionary = {}

const CONTACT_ALERT_COOLDOWN_TICKS := 50


func _ready() -> void:
	input_controller.simulation_host = simulation_host
	input_controller.world_presentation = world_presentation
	input_controller.camera_controller = camera_controller
	input_controller.selection_overlay = selection_overlay
	input_controller.move_intent_changed.connect(_on_move_intent_changed)
	input_controller.pending_intent_cleared.connect(world_presentation.clear_pending_move_target)
	input_controller.build_preview_changed.connect(world_presentation.set_build_preview)
	input_controller.build_preview_cleared.connect(world_presentation.clear_build_preview)
	input_controller.attack_targeting_started.connect(world_presentation.begin_attack_targeting)
	input_controller.attack_preview_changed.connect(world_presentation.set_attack_preview)
	input_controller.attack_preview_cleared.connect(world_presentation.clear_attack_preview)
	task_panel.simulation_host = simulation_host
	task_panel.input_controller = input_controller
	if not task_panel.headquarters_settings_changed.is_connected(_on_headquarters_settings_changed):
		task_panel.headquarters_settings_changed.connect(_on_headquarters_settings_changed)
	workflow_panel.simulation_host = simulation_host
	pause_menu.language_changed.connect(_on_language_changed)
	pause_menu.enemy_difficulty_changed.connect(simulation_host.set_enemy_difficulty)
	pause_menu.agent_authorization_changed.connect(simulation_host.set_agent_authorization)
	pause_menu.set_ai_settings(
		simulation_host.get_enemy_difficulty(),
		simulation_host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID),
		simulation_host.get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID)
	)
	_on_language_changed(TranslationServer.get_locale())


func _on_move_intent_changed(target_position: Vector2, _intent_sequence: int) -> void:
	world_presentation.set_pending_move_target(target_position)


func _on_language_changed(_locale: String) -> void:
	task_panel.refresh_locale()
	resource_bar.refresh_locale()
	workflow_panel.refresh_locale()
	contact_alert.refresh_locale()
	input_controller.refresh_locale_status()
	world_presentation.refresh_locale()


func _on_headquarters_settings_changed() -> void:
	pause_menu.set_ai_settings(
		simulation_host.get_enemy_difficulty(),
		simulation_host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID),
		simulation_host.get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID)
	)


func _process(delta: float) -> void:
	input_controller.prune_selection()
	world_presentation.set_snapshots(
		simulation_host.previous_snapshot,
		simulation_host.current_snapshot,
		simulation_host.get_interpolation_alpha()
	)
	if input_controller.pending_move_active and simulation_host.get_queue_size() == 0:
		world_presentation.clear_pending_move_target()
	var snapshot := simulation_host.current_snapshot
	if snapshot != null and snapshot.tick != _last_ui_snapshot_tick:
		_last_ui_snapshot_tick = snapshot.tick
		_process_new_contacts(snapshot)
		minimap.set_state(snapshot, camera_controller, input_controller.selected_entity_ids)
		task_panel.update_snapshot(snapshot)
		resource_bar.update_snapshot(snapshot)
		workflow_panel.update_snapshot(snapshot)
		if debug_layer.visible:
			debug_layer.update_status(
			simulation_host.current_snapshot,
			input_controller.selected_entity_id,
			simulation_host.get_queue_size(),
			input_controller.last_command_status,
			simulation_host.get_tick_timing_snapshot(),
			simulation_host.get_true_state_snapshot_for_debug(),
			simulation_host.get_enemy_phase_name(),
			simulation_host.get_enemy_difficulty_name(),
			simulation_host.get_enemy_decision_summary(),
			simulation_host.get_agent_authorization(StrategicTaskSystem.INDUSTRIAL_AGENT_ID),
			simulation_host.get_agent_authorization(StrategicTaskSystem.BATTLEFIELD_AGENT_ID)
			)
	_update_hover_tooltip(delta)


func _process_new_contacts(snapshot: WorldSnapshot) -> void:
	var currently_visible: Dictionary = {}
	for unit in snapshot.units:
		if unit.faction_id == SimulationWorld.LOCAL_PLAYER_ID or not unit.enabled or not unit.is_visible_to_local_player:
			continue
		currently_visible[unit.entity_id] = true
		if not _visible_hostile_ids.has(unit.entity_id) and snapshot.tick - int(_last_contact_alert_tick.get(unit.entity_id, -CONTACT_ALERT_COOLDOWN_TICKS)) >= CONTACT_ALERT_COOLDOWN_TICKS:
			minimap.add_contact_ping(unit.position)
			contact_alert.show_contact(unit.definition_id)
			_last_contact_alert_tick[unit.entity_id] = snapshot.tick
	for building in snapshot.buildings:
		if building.faction_id == SimulationWorld.LOCAL_PLAYER_ID or not building.enabled or not building.is_visible:
			continue
		currently_visible[building.entity_id] = true
		if not _visible_hostile_ids.has(building.entity_id) and snapshot.tick - int(_last_contact_alert_tick.get(building.entity_id, -CONTACT_ALERT_COOLDOWN_TICKS)) >= CONTACT_ALERT_COOLDOWN_TICKS:
			minimap.add_contact_ping(building.position)
			contact_alert.show_contact(building.definition_id, true)
			_last_contact_alert_tick[building.entity_id] = snapshot.tick
	_visible_hostile_ids = currently_visible


func _update_hover_tooltip(delta: float) -> void:
	if pause_menu.backdrop.visible:
		hover_tooltip.clear()
		return
	var mouse_position := get_viewport().get_mouse_position()
	var context := task_panel.get_hover_context(mouse_position)
	if context.is_empty() and task_panel.get_global_rect().has_point(mouse_position):
		hover_tooltip.clear()
		return
	if context.is_empty():
		context = _world_hover_context(input_controller._screen_to_world(mouse_position))
	hover_tooltip.update_candidate(
		String(context.get("key", "")), String(context.get("text", "")), mouse_position, delta
	)


func _world_hover_context(world_position: Vector2) -> Dictionary:
	var snapshot := simulation_host.current_snapshot
	if snapshot == null:
		return {}
	var hit_radius := InputController.HIT_RADIUS_SCREEN / camera_controller.zoom.x
	var nearest_unit: UnitSnapshot
	var nearest_distance := INF
	for unit in snapshot.units:
		if not unit.enabled or unit.faction_id != SimulationWorld.LOCAL_PLAYER_ID and not unit.is_visible_to_local_player:
			continue
		var distance := unit.position.distance_to(world_position)
		if distance <= hit_radius and distance < nearest_distance:
			nearest_unit = unit
			nearest_distance = distance
	if nearest_unit != null:
		return {"key": "world-unit:%d" % nearest_unit.entity_id, "text": GameText.unit_tooltip(nearest_unit.definition_id)}
	for building in snapshot.buildings:
		if building.enabled and building.position.distance_to(world_position) <= 72.0:
			return {"key": "world-building:%d" % building.entity_id, "text": GameText.building_tooltip(building.definition_id)}
	for ore_field in snapshot.ore_fields:
		if ore_field.position.distance_to(world_position) <= 52.0:
			return {
				"key": "ore:%d" % ore_field.entity_id,
				"text": GameText.t(&"ORE_TOOLTIP") % ore_field.ore_remaining,
			}
	return {}
