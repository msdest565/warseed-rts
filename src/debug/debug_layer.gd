class_name DebugLayer
extends CanvasLayer

@onready var status_label: Label = $Panel/Status


func update_status(
	snapshot: WorldSnapshot,
	selected_entity_id: int,
	queue_size: int,
	command_status: String
) -> void:
	if snapshot == null:
		status_label.text = "Initializing simulation..."
		return
	var lines: PackedStringArray = [
		"WARSEED / AUTHORITATIVE MOVEMENT SLICE",
		"Tick: %d    Queue: %d" % [snapshot.tick, queue_size],
		"Selected: %s" % ("E%d" % selected_entity_id if selected_entity_id != 0 else "None"),
		"Command: %s" % command_status,
	]
	if selected_entity_id != 0:
		var unit := snapshot.get_unit(selected_entity_id)
		if unit != null:
			lines.append("Position: (%.1f, %.1f)" % [unit.position.x, unit.position.y])
			lines.append("Target: (%.1f, %.1f)" % [unit.move_target.x, unit.move_target.y])
			lines.append("State: %s" % ("MOVING" if unit.is_moving else "IDLE"))
	status_label.text = "\n".join(lines)
