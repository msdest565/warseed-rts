class_name TacticalAbilityDefinition
extends Resource

enum Kind { OBSERVE, OPEN_ROUTE, SUPPRESS, BREAKTHROUGH, RESUPPLY }

@export var ability_id: StringName
@export var kind: Kind = Kind.OBSERVE
@export var name_key: StringName
@export var help_key: StringName
@export var required_unit_id: StringName
@export var supply_cost: int = 1
@export var preparation_ticks: int = 20
@export var duration_ticks: int = 80
@export var cooldown_ticks: int = 150
@export var range: float = 300.0
@export var organization_cost: float = 0.0


func validate(catalog: UnitDefinitionCatalog) -> DataValidationResult:
	var result := DataValidationResult.new()
	if ability_id.is_empty() or name_key.is_empty() or help_key.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "tactical ability requires stable ID and localized name/help")
	if kind < Kind.OBSERVE or kind > Kind.RESUPPLY:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "unsupported tactical ability kind")
	if catalog == null or catalog.get_unit(required_unit_id) == null:
		result.add(DataValidationResult.Reason.INVALID_REFERENCE, "tactical ability requires a known capability unit")
	if supply_cost <= 0 or preparation_ticks <= 0 or duration_ticks <= 0 or cooldown_ticks < preparation_ticks + duration_ticks:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "tactical cost/timing is invalid")
	if not is_finite(range) or range <= 0.0 or not is_finite(organization_cost) or organization_cost < 0.0 or organization_cost > 100.0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "tactical range/organization cost is invalid")
	return result
