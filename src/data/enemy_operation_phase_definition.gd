class_name EnemyOperationPhaseDefinition
extends Resource

enum Kind { OPENING, REDIRECT, EXPLOIT, RESERVE }

@export var phase_id: StringName
@export var kind: Kind = Kind.OPENING
@export var formation_role_id: StringName
@export var target_region_id: StringName
# Authored map objective, frozen before play; never a hidden live entity position.
@export var target_position: Vector2
@export var route_points: PackedVector2Array = PackedVector2Array()
@export var earliest_tick: int = 0
@export var requires_idle: bool = true

func validate(battle: BattleDefinition) -> DataValidationResult:
	var result := DataValidationResult.new()
	if phase_id.is_empty() or formation_role_id.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, "enemy phase IDs required")
	if kind < Kind.OPENING or kind > Kind.RESERVE or earliest_tick < 0 or not target_position.is_finite() or not battle.battlefield_bounds.has_point(target_position):
		result.add(DataValidationResult.Reason.INVALID_VALUE, "enemy phase timing or target invalid")
	if kind == Kind.OPENING and earliest_tick != 0:
		result.add(DataValidationResult.Reason.INVALID_VALUE, "opening must start at tick zero")
	if battle.enemy_formation_by_role(formation_role_id) == null:
		result.add(DataValidationResult.Reason.INVALID_REFERENCE, "enemy phase formation missing")
	if not target_region_id.is_empty() and not battle.region_dictionary().has(target_region_id):
		result.add(DataValidationResult.Reason.INVALID_REFERENCE, "enemy phase region missing")
	for point in route_points:
		if not point.is_finite() or not battle.battlefield_bounds.has_point(point):
			result.add(DataValidationResult.Reason.INVALID_VALUE, "enemy phase route invalid")
	return result
