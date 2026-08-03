class_name GameRoot
extends Node

@onready var simulation_host: SimulationHost = $SimulationHost
@onready var world_presentation: WorldPresentation = $WorldPresentation
@onready var input_controller: InputController = $InputController
@onready var camera_controller: CameraController = $CameraController
@onready var selection_overlay: SelectionOverlay = $SelectionLayer/SelectionOverlay
@onready var minimap: MinimapControl = $HUDLayer/Minimap
@onready var task_panel: TaskPanel = $HUDLayer/TaskPanel
@onready var debug_layer: DebugLayer = $DebugLayer


func _ready() -> void:
	input_controller.simulation_host = simulation_host
	input_controller.world_presentation = world_presentation
	input_controller.camera_controller = camera_controller
	input_controller.selection_overlay = selection_overlay
	input_controller.move_intent_changed.connect(_on_move_intent_changed)
	input_controller.pending_intent_cleared.connect(world_presentation.clear_pending_move_target)
	task_panel.simulation_host = simulation_host


func _on_move_intent_changed(target_position: Vector2, _intent_sequence: int) -> void:
	world_presentation.set_pending_move_target(target_position)


func _process(_delta: float) -> void:
	input_controller.prune_selection()
	world_presentation.set_snapshots(
		simulation_host.previous_snapshot,
		simulation_host.current_snapshot,
		simulation_host.get_interpolation_alpha()
	)
	if input_controller.pending_move_active and simulation_host.get_queue_size() == 0:
		world_presentation.clear_pending_move_target()
	minimap.set_state(
		simulation_host.current_snapshot,
		camera_controller,
		input_controller.selected_entity_ids
	)
	task_panel.update_snapshot(simulation_host.current_snapshot)
	debug_layer.update_status(
		simulation_host.current_snapshot,
		input_controller.selected_entity_id,
		simulation_host.get_queue_size(),
		input_controller.last_command_status,
		simulation_host.get_tick_timing_snapshot(),
		simulation_host.get_true_state_snapshot_for_debug()
	)
