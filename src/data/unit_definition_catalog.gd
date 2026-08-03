class_name UnitDefinitionCatalog
extends Resource

@export var units: Array[UnitDefinition] = []


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	var seen: Dictionary = {}
	for index in range(units.size()):
		var unit := units[index]
		if unit == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "units[%d] is null" % index)
			continue
		if unit.definition_id.is_empty():
			result.add(DataValidationResult.Reason.EMPTY_ID, "units[%d] has empty definition_id" % index)
		elif seen.has(unit.definition_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "duplicate definition_id: %s" % unit.definition_id)
		else:
			seen[unit.definition_id] = true
		if unit.display_name.strip_edges().is_empty():
			result.add(DataValidationResult.Reason.EMPTY_DISPLAY_NAME, "units[%d] has empty display_name" % index)
		if not is_finite(unit.move_speed) or unit.move_speed <= 0.0:
			result.add(DataValidationResult.Reason.INVALID_MOVE_SPEED, "units[%d] has invalid move_speed" % index)
		if unit.production_cost < 0 or unit.production_ticks <= 0 or unit.cargo_capacity < 0:
			result.add(DataValidationResult.Reason.INVALID_COST, "units[%d] has invalid economy values" % index)
		if unit.combat == null:
			result.add(DataValidationResult.Reason.INVALID_COMBAT, "units[%d] has no combat definition" % index)
			continue
		if not is_finite(unit.combat.max_health) or unit.combat.max_health <= 0.0:
			result.add(DataValidationResult.Reason.INVALID_MAX_HEALTH, "units[%d] has invalid max_health" % index)
		if not is_finite(unit.combat.armor) or unit.combat.armor < 0.0:
			result.add(DataValidationResult.Reason.INVALID_ARMOR, "units[%d] has invalid armor" % index)
		if not is_finite(unit.combat.attack_power) or unit.combat.attack_power < 0.0:
			result.add(DataValidationResult.Reason.INVALID_ATTACK_POWER, "units[%d] has invalid attack_power" % index)
		if not is_finite(unit.combat.attack_range) or unit.combat.attack_range <= 0.0:
			result.add(DataValidationResult.Reason.INVALID_ATTACK_RANGE, "units[%d] has invalid attack_range" % index)
		if not is_finite(unit.combat.attacks_per_second) or unit.combat.attacks_per_second <= 0.0:
			result.add(DataValidationResult.Reason.INVALID_ATTACK_SPEED, "units[%d] has invalid attacks_per_second" % index)
		if not is_finite(unit.combat.projectile_speed) or unit.combat.projectile_speed <= 0.0:
			result.add(DataValidationResult.Reason.INVALID_PROJECTILE_SPEED, "units[%d] has invalid projectile_speed" % index)
	return result


func get_unit(definition_id: StringName) -> UnitDefinition:
	for unit in units:
		if unit != null and unit.definition_id == definition_id:
			return unit
	return null
