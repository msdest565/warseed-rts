class_name AfterActionCardContribution
extends RefCounted

var unit_card_id: StringName
var authorized_strength: int
var initial_strength: int
var peak_strength: int
var final_strength: int
var losses: int
var damage_dealt: float
var damage_taken: float
var kills: int
var tasks_completed: int
var tasks_blocked: int
var final_deployment_state: StringName
var final_control_state: StringName


func _init(source: Dictionary) -> void:
	unit_card_id = StringName(source.get("card_id", ""))
	authorized_strength = int(source.get("authorized_strength", 0))
	initial_strength = int(source.get("initial_strength", 0))
	peak_strength = int(source.get("peak_strength", 0))
	final_strength = int(source.get("final_strength", 0))
	losses = int(source.get("losses", 0))
	damage_dealt = float(source.get("damage_dealt", 0.0))
	damage_taken = float(source.get("damage_taken", 0.0))
	kills = int(source.get("kills", 0))
	tasks_completed = int(source.get("tasks_completed", 0))
	tasks_blocked = int(source.get("tasks_blocked", 0))
	final_deployment_state = StringName(source.get("final_deployment_state", ""))
	final_control_state = StringName(source.get("final_control_state", ""))


func duplicate_entry() -> AfterActionCardContribution:
	return AfterActionCardContribution.new(to_dictionary())


func to_dictionary() -> Dictionary:
	return {
		"card_id": String(unit_card_id),
		"authorized_strength": authorized_strength,
		"initial_strength": initial_strength,
		"peak_strength": peak_strength,
		"final_strength": final_strength,
		"losses": losses,
		"damage_dealt": damage_dealt,
		"damage_taken": damage_taken,
		"kills": kills,
		"tasks_completed": tasks_completed,
		"tasks_blocked": tasks_blocked,
		"final_deployment_state": String(final_deployment_state),
		"final_control_state": String(final_control_state),
	}
