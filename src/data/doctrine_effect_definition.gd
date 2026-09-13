class_name DoctrineEffectDefinition
extends Resource

const SCHEMA_VERSION := 1
const MAX_TIMING_TICKS := 3600

@export var schema_version: int = SCHEMA_VERSION
@export var effect_id: StringName
@export var trigger: DoctrineTriggerDefinition
@export var selector: DoctrineSelectorDefinition
@export var effect: DoctrineActionDefinition
@export var cost: DoctrineCostDefinition
@export var timing: DoctrineTimingDefinition
@export var counterplay: DoctrineCounterplayDefinition
@export var reason: DoctrineReasonDefinition


func validate(path: String = "doctrine_effect") -> DataValidationResult:
	var result := DataValidationResult.new()
	validate_id(result, effect_id, path + ".effect_id")
	if schema_version != SCHEMA_VERSION:
		result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".schema_version is unsupported")
	_validate_kind(result, trigger, DoctrineTriggerDefinition.Kind.COMMANDER_TASK_CREATED, path + ".trigger")
	_validate_kind(result, selector, DoctrineSelectorDefinition.Kind.COMMANDER_DEPLOYED_CARDS, path + ".selector")
	if effect == null:
		result.add(DataValidationResult.Reason.NULL_REFERENCE, path + ".effect is required")
	else:
		match effect.kind:
			DoctrineActionDefinition.Kind.STAGED_DEPARTURE:
				_validate_combination(result, path, cost, timing, counterplay, DoctrineCostDefinition.Kind.DELAYED_COMMITMENT, DoctrineTimingDefinition.Kind.DEPLOYED_CARD_ORDER, DoctrineCounterplayDefinition.Kind.DEFEAT_IN_DETAIL)
			DoctrineActionDefinition.Kind.REQUIRE_OBSERVED_CONTACT:
				_validate_combination(result, path, cost, timing, counterplay, DoctrineCostDefinition.Kind.OBSERVATION_REQUIREMENT, DoctrineTimingDefinition.Kind.FIXED_PREPARATION, DoctrineCounterplayDefinition.Kind.DENY_CONTACT)
			DoctrineActionDefinition.Kind.CAUTIOUS_RECON:
				_validate_combination(result, path, cost, timing, counterplay, DoctrineCostDefinition.Kind.SLOW_RECON, DoctrineTimingDefinition.Kind.IMMEDIATE, DoctrineCounterplayDefinition.Kind.FORCE_RECON_EXIT)
				if not is_finite(effect.staging_distance) or effect.staging_distance <= 0.0 or not is_finite(effect.staging_fraction) or effect.staging_fraction <= 0.0 or effect.staging_fraction >= 1.0:
					result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".effect has invalid reconnaissance staging")
			DoctrineActionDefinition.Kind.NARROW_FRONTAGE:
				_validate_combination(result, path, cost, timing, counterplay, DoctrineCostDefinition.Kind.CONCENTRATED_FORCE, DoctrineTimingDefinition.Kind.IMMEDIATE, DoctrineCounterplayDefinition.Kind.FLANK_CONCENTRATION)
				if not is_finite(effect.formation_spacing) or effect.formation_spacing <= 0.0:
					result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".effect requires positive formation spacing")
			_:
				result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".effect.kind is unsupported")
		if effect.kind in [DoctrineActionDefinition.Kind.CAUTIOUS_RECON, DoctrineActionDefinition.Kind.NARROW_FRONTAGE] and (not is_finite(effect.task_radius) or effect.task_radius <= 0.0):
			result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".effect requires positive task radius")
	_validate_kind(result, reason, DoctrineReasonDefinition.Kind.LOCALIZED_TASK_REASON, path + ".reason")
	if cost != null:
		validate_text_key(result, cost.explanation_key, path + ".cost.explanation_key")
	if timing != null:
		if timing.base_delay_ticks < 0 or timing.base_delay_ticks > MAX_TIMING_TICKS:
			result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".timing.base_delay_ticks must be 0..3600")
		if timing.kind == DoctrineTimingDefinition.Kind.DEPLOYED_CARD_ORDER and (timing.interval_ticks <= 0 or timing.interval_ticks > MAX_TIMING_TICKS):
			result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".timing.interval_ticks must be 1..3600")
		if timing.kind != DoctrineTimingDefinition.Kind.DEPLOYED_CARD_ORDER and timing.interval_ticks != 0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".timing.interval_ticks must be zero for non-ordinal effects")
		if timing.kind == DoctrineTimingDefinition.Kind.IMMEDIATE and timing.base_delay_ticks != 0:
			result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".timing immediate effects cannot delay activation")
	if counterplay != null:
		if counterplay.exit_condition != DoctrineCounterplayDefinition.ExitCondition.PLAYER_OVERRIDE_OR_TASK_END:
			result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".counterplay.exit_condition is unsupported")
		validate_text_key(result, counterplay.explanation_key, path + ".counterplay.explanation_key")
	if reason != null:
		validate_text_key(result, reason.waiting_reason_key, path + ".reason.waiting_reason_key")
		validate_text_key(result, reason.description_key, path + ".reason.description_key")
	return result


func _validate_combination(result: DataValidationResult, path: String, cost: DoctrineCostDefinition, timing: DoctrineTimingDefinition, counterplay: DoctrineCounterplayDefinition, cost_kind: int, timing_kind: int, counterplay_kind: int) -> void:
	_validate_kind(result, cost, cost_kind, path + ".cost")
	_validate_kind(result, timing, timing_kind, path + ".timing")
	_validate_kind(result, counterplay, counterplay_kind, path + ".counterplay")


static func validate_id(result: DataValidationResult, value: StringName, path: String) -> void:
	if value.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_ID, path + " is required")
	elif String(value).length() > 64 or not _matches(value, "^[a-z][a-z0-9_]*$"):
		result.add(DataValidationResult.Reason.INVALID_VALUE, path + " must be a stable lowercase ID (maximum 64 characters)")


static func validate_text_key(result: DataValidationResult, value: StringName, path: String) -> void:
	if value.is_empty():
		result.add(DataValidationResult.Reason.EMPTY_DISPLAY_NAME, path + " is required")
	elif String(value).length() > 128 or not _matches(value, "^[A-Z][A-Z0-9_]*$"):
		result.add(DataValidationResult.Reason.INVALID_VALUE, path + " must be a localization key")


static func _matches(value: StringName, pattern: String) -> bool:
	var expression := RegEx.new()
	expression.compile(pattern)
	return expression.search(String(value)) != null


static func _validate_kind(result: DataValidationResult, part: Resource, supported_kind: int, path: String) -> void:
	if part == null:
		result.add(DataValidationResult.Reason.NULL_REFERENCE, path + " is required")
	elif int(part.get("kind")) != supported_kind:
		result.add(DataValidationResult.Reason.INVALID_VALUE, path + ".kind is unsupported")
