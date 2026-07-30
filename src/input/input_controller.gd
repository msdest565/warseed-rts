class_name InputController
extends Node

const HIT_RADIUS := 34.0

var selected_entity_id: int = 0
var last_command_status: String = "Ready - left click the vehicle"

@export var simulation_host: SimulationHost
@export var world_presentation: WorldPresentation


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		select_at(mouse_event.position)
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		move_selected_to(mouse_event.position)


func select_at(world_position: Vector2) -> void:
	selected_entity_id = 0
	var snapshot := simulation_host.current_snapshot
	if snapshot != null:
		for unit in snapshot.units:
			if unit.enabled and unit.position.distance_to(world_position) <= HIT_RADIUS:
				selected_entity_id = unit.entity_id
				last_command_status = "Selected E%d" % unit.entity_id
				break
	world_presentation.set_selected_entity(selected_entity_id)
	if selected_entity_id == 0:
		last_command_status = "Selection cleared"


func move_selected_to(world_position: Vector2) -> CommandValidationResult:
	if selected_entity_id == 0:
		last_command_status = "Rejected: select a vehicle first"
		return null
	var command := simulation_host.create_move_command(selected_entity_id, world_position)
	var result := simulation_host.submit_command(command)
	last_command_status = result.describe()
	return result
