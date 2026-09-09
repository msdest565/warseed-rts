class_name BattleContentLoadResult
extends RefCounted

var catalog: BattleContentCatalog
var battle: BattleDefinition
var validation := DataValidationResult.new()


func is_valid() -> bool:
	return catalog != null and battle != null and validation.is_valid()
