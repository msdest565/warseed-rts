class_name EnemyReservePolicy
extends Resource

@export var policy_id: StringName = &"measured_reserve"
@export var minimum_hold_ticks: int = 120
@export_range(0.0, 1.0) var release_loss_ratio: float = 0.75
@export var visible_contact_radius: float = 384.0
@export var max_release_strength: int = 4
@export var release_on_objective_reached: bool = true
@export var release_phase_id: StringName = &"opening_assault"


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()

	if policy_id.is_empty():
		result.add(
			DataValidationResult.Reason.EMPTY_ID,
			"policy_id must not be empty."
		)

	if minimum_hold_ticks < 0:
		result.add(
			DataValidationResult.Reason.INVALID_VALUE,
			"minimum_hold_ticks must be non-negative."
		)

	if not is_finite(release_loss_ratio) or release_loss_ratio < 0.0 or release_loss_ratio > 1.0:
		result.add(
			DataValidationResult.Reason.INVALID_VALUE,
			"release_loss_ratio must be finite and within [0, 1]."
		)

	if not is_finite(visible_contact_radius) or visible_contact_radius <= 0.0:
		result.add(
			DataValidationResult.Reason.INVALID_VALUE,
			"visible_contact_radius must be finite and greater than zero."
		)

	if max_release_strength <= 0:
		result.add(
			DataValidationResult.Reason.INVALID_VALUE,
			"max_release_strength must be greater than zero."
		)

	return result
