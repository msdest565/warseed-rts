class_name GrowthCatalog
extends Resource

@export var definitions: Array[Resource] = []


func get_growth(definition_id: StringName):
	for definition_variant in definitions:
		var definition: Variant = definition_variant
		if definition != null and definition.definition_id == definition_id:
			return definition
	return null


func get_by_kind(kind: int) -> Array:
	var result: Array = []
	for definition_variant in definitions:
		var definition: Variant = definition_variant
		if definition != null and definition.kind == kind:
			result.append(definition)
	return result


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	var seen: Dictionary = {}
	for index in range(definitions.size()):
		var definition: Variant = definitions[index]
		if definition == null:
			result.add(DataValidationResult.Reason.NULL_REFERENCE, "growth definitions[%d]" % index)
			continue
		if seen.has(definition.definition_id):
			result.add(DataValidationResult.Reason.DUPLICATE_ID, "growth '%s'" % definition.definition_id)
		seen[definition.definition_id] = true
		for issue in definition.validate().issues:
			result.issues.append(issue)
	return result
