class_name BuildingDefinitionCatalog
extends Resource

@export var buildings: Array[BuildingDefinition] = []


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	var seen: Dictionary = {}
	for index in range(buildings.size()):
		var building := buildings[index]
		if building == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "buildings[%d] is null" % index)
			continue
		if building.definition_id.is_empty():
			result.add(DataValidationResult.Reason.EMPTY_ID, "buildings[%d] has empty definition_id" % index)
		elif seen.has(building.definition_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "duplicate definition_id: %s" % building.definition_id)
		else:
			seen[building.definition_id] = true
		if building.display_name.strip_edges().is_empty():
			result.add(DataValidationResult.Reason.EMPTY_DISPLAY_NAME, "buildings[%d] has empty display_name" % index)
		if not is_finite(building.max_health) or building.max_health <= 0.0:
			result.add(DataValidationResult.Reason.INVALID_MAX_HEALTH, "buildings[%d] has invalid max_health" % index)
		if building.build_cost < 0 or building.build_ticks <= 0 or building.production_cost < 0 or building.production_ticks < 0:
			result.add(DataValidationResult.Reason.INVALID_COST, "buildings[%d] has invalid economy values" % index)
		if building.footprint_size.x <= 0 or building.footprint_size.y <= 0:
			result.add(DataValidationResult.Reason.INVALID_COST, "buildings[%d] has invalid footprint" % index)
	return result


func get_building(definition_id: StringName) -> BuildingDefinition:
	for building in buildings:
		if building != null and building.definition_id == definition_id:
			return building
	return null
