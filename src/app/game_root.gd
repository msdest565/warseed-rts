class_name GameRoot
extends Node

@onready var simulation_host: SimulationHost = $SimulationHost
@onready var world_presentation: WorldPresentation = $WorldPresentation
@onready var input_controller: InputController = $InputController
@onready var debug_layer: DebugLayer = $DebugLayer


func _ready() -> void:
	input_controller.simulation_host = simulation_host
	input_controller.world_presentation = world_presentation


func _process(_delta: float) -> void:
	world_presentation.set_snapshots(
		simulation_host.previous_snapshot,
		simulation_host.current_snapshot,
		simulation_host.get_interpolation_alpha()
	)
	debug_layer.update_status(
		simulation_host.current_snapshot,
		input_controller.selected_entity_id,
		simulation_host.get_queue_size(),
		input_controller.last_command_status
	)
