class_name CommandValidator
extends RefCounted


func validate(command: GameCommand, units: Dictionary, battlefield_bounds: Rect2) -> CommandValidationResult:
	if not units.has(command.target_entity_id):
		return CommandValidationResult.new(
			CommandValidationResult.Status.REJECTED,
			CommandValidationResult.Reason.INVALID_TARGET
		)

	var unit: UnitState = units[command.target_entity_id]
	if not unit.enabled:
		return CommandValidationResult.new(
			CommandValidationResult.Status.REJECTED,
			CommandValidationResult.Reason.ENTITY_DISABLED
		)
	if unit.controller_id != command.issuer_id:
		return CommandValidationResult.new(
			CommandValidationResult.Status.REJECTED,
			CommandValidationResult.Reason.NOT_CONTROLLER
		)

	if command is MoveCommand:
		var move_command := command as MoveCommand
		if not move_command.target_position.is_finite() or not battlefield_bounds.has_point(move_command.target_position):
			return CommandValidationResult.new(
				CommandValidationResult.Status.REJECTED,
				CommandValidationResult.Reason.INVALID_POSITION
			)
		return CommandValidationResult.new(CommandValidationResult.Status.ACCEPTED)

	return CommandValidationResult.new(
		CommandValidationResult.Status.REJECTED,
		CommandValidationResult.Reason.INVALID_TARGET
	)
