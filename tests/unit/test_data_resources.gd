class_name TestDataResources
extends RefCounted


func run() -> Array[String]:
	var failures: Array[String] = []
	_test_committed_catalog_loads(failures)
	_test_structured_validation(failures)
	return failures


func _test_committed_catalog_loads(failures: Array[String]) -> void:
	var resource := ResourceLoader.load("res://data/units/unit_catalog.tres")
	_expect(resource is UnitDefinitionCatalog, "unit catalog .tres should load as typed catalog", failures)
	if not resource is UnitDefinitionCatalog:
		return
	var catalog := resource as UnitDefinitionCatalog
	_expect(catalog.validate().is_valid(), "committed unit catalog should validate", failures)
	var scout := catalog.get_unit(&"scout_vehicle")
	_expect(scout is UnitDefinition, "typed external unit reference should resolve", failures)
	if scout != null:
		_expect(is_equal_approx(scout.move_speed, 180.0), "loaded typed definition should retain move speed", failures)


func _test_structured_validation(failures: Array[String]) -> void:
	var catalog := UnitDefinitionCatalog.new()
	catalog.units.append(null)
	var invalid := UnitDefinition.new()
	invalid.definition_id = &""
	invalid.display_name = " "
	invalid.move_speed = -1.0
	catalog.units.append(invalid)
	var duplicate_a := UnitDefinition.new()
	duplicate_a.definition_id = &"duplicate"
	duplicate_a.display_name = "A"
	var duplicate_b := UnitDefinition.new()
	duplicate_b.definition_id = &"duplicate"
	duplicate_b.display_name = "B"
	catalog.units.append(duplicate_a)
	catalog.units.append(duplicate_b)
	var result := catalog.validate()
	_expect(result.has_reason(DataValidationResult.Reason.NULL_REFERENCE), "catalog should report null references", failures)
	_expect(result.has_reason(DataValidationResult.Reason.EMPTY_ID), "catalog should report empty IDs", failures)
	_expect(result.has_reason(DataValidationResult.Reason.EMPTY_DISPLAY_NAME), "catalog should report empty display names", failures)
	_expect(result.has_reason(DataValidationResult.Reason.INVALID_MOVE_SPEED), "catalog should report invalid speeds", failures)
	_expect(result.has_reason(DataValidationResult.Reason.DUPLICATE_ID), "catalog should report duplicate IDs", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
