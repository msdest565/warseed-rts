class_name BattleObjectiveDefinition
extends Resource

enum Kind {
	DESTROY_ENTITY,
	TIME_LIMIT_REACHED,
	ESCORT_UNIT_CARD_TO_REGION,
	WITHDRAW_UNIT_CARD,
}

@export var objective_id: StringName
@export var display_name_key: StringName
@export var kind: Kind = Kind.DESTROY_ENTITY
@export var target_entity_id: int = 0
@export var target_tick: int = 0
@export var unit_card_id: StringName
@export var region_id: StringName
@export var arrival_radius: float = 0.0
@export var minimum_strength: int = 1


func validate() -> DataValidationResult:
	var result := DataValidationResult.new()
	if objective_id.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "battle objective requires objective_id")
	if display_name_key.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_DISPLAY_NAME, "battle objective '%s' requires display_name_key" % objective_id)
	match kind:
		Kind.DESTROY_ENTITY:
			if target_entity_id <= 0:
				result.add(DataValidationResult.Reason.INVALID_VALUE, "destroy objective '%s' requires target_entity_id" % objective_id)
		Kind.TIME_LIMIT_REACHED:
			if target_tick < 0:
				result.add(DataValidationResult.Reason.INVALID_VALUE, "time objective '%s' cannot use a negative target_tick" % objective_id)
		Kind.ESCORT_UNIT_CARD_TO_REGION, Kind.WITHDRAW_UNIT_CARD:
			if unit_card_id.is_empty() or region_id.is_empty():
				result.add(DataValidationResult.Reason.INVALID_REFERENCE, "card objective '%s' requires unit_card_id and region_id" % objective_id)
			if minimum_strength <= 0:
				result.add(DataValidationResult.Reason.INVALID_VALUE, "card objective '%s' requires positive minimum_strength" % objective_id)
			if kind == Kind.ESCORT_UNIT_CARD_TO_REGION and arrival_radius <= 0.0:
				result.add(DataValidationResult.Reason.INVALID_VALUE, "escort objective '%s' requires positive arrival_radius" % objective_id)
	return result
