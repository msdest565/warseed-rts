class_name BattleContentLoader
extends RefCounted

const DEFAULT_CATALOG_PATH := "res://data/battles/battle_catalog.tres"
const UNIT_CATALOG: UnitDefinitionCatalog = preload("res://data/units/unit_catalog.tres")


static func load_battle(scenario_id: StringName, catalog_path: String = DEFAULT_CATALOG_PATH) -> BattleContentLoadResult:
	var result := BattleContentLoadResult.new()
	if not ResourceLoader.exists(catalog_path):
		result.validation.add(DataValidationResult.Reason.RESOURCE_NOT_FOUND, catalog_path)
		return result
	var resource := ResourceLoader.load(catalog_path)
	if not resource is BattleContentCatalog:
		result.validation.add(DataValidationResult.Reason.INVALID_RESOURCE_TYPE, catalog_path)
		return result
	result.catalog = resource as BattleContentCatalog
	result.validation = result.catalog.validate(UNIT_CATALOG)
	result.battle = result.catalog.get_battle(scenario_id)
	if result.battle == null:
		result.validation.add(DataValidationResult.Reason.INVALID_REFERENCE, "scenario_id='%s'" % scenario_id)
	return result
