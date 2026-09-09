class_name GrowthDefinition
extends Resource

enum Kind {
	HONOR,
	EQUIPMENT,
}

@export var definition_id: StringName
@export var kind: Kind = Kind.HONOR
@export var display_name_key: StringName
@export var benefit_key: StringName
@export var tradeoff_key: StringName
@export var merit_cost: int = 0
@export var replacement_cost: int = 0
@export var refit_days: int = 0
@export var attack_multiplier: float = 1.0
@export var armor_bonus: float = 0.0
@export var move_speed_multiplier: float = 1.0
@export var sight_range_multiplier: float = 1.0
@export var attack_range_multiplier: float = 1.0
@export var organization_recovery_multiplier: float = 1.0
@export var deployment_supply_cost_modifier: int = 0
@export var replacement_cost_modifier: int = 0


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if definition_id.is_empty() or display_name_key.is_empty() or benefit_key.is_empty() or tradeoff_key.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "growth definition requires ID and localized text keys")
	if merit_cost < 0 or replacement_cost < 0 or refit_days < 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "growth '%s' has a negative cost" % definition_id)
	if attack_multiplier <= 0.0 or move_speed_multiplier <= 0.0 or sight_range_multiplier <= 0.0 or attack_range_multiplier <= 0.0 or organization_recovery_multiplier <= 0.0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "growth '%s' has a non-positive multiplier" % definition_id)
	if kind == Kind.HONOR and merit_cost <= 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "honor '%s' requires merit" % definition_id)
	if kind == Kind.EQUIPMENT and replacement_cost <= 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "equipment '%s' requires replacement points" % definition_id)
	return result
