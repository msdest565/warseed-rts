class_name DoctrineTaskParameters
extends RefCounted

var rejection_reason: StringName
var applied: bool = false
var activation_tick: int = 0
var trigger_tick: int = -1
var doctrine_id: StringName
var effect_id: StringName
var action_kind: DoctrineActionDefinition.Kind = DoctrineActionDefinition.Kind.STAGED_DEPARTURE
var requires_observed_contact: bool = false
var waiting_reason_key: StringName
var description_key: StringName
var cost_key: StringName
var counterplay_key: StringName
var exit_condition: DoctrineCounterplayDefinition.ExitCondition = DoctrineCounterplayDefinition.ExitCondition.PLAYER_OVERRIDE_OR_TASK_END


func duplicate_value() -> DoctrineTaskParameters:
	var copy := DoctrineTaskParameters.new()
	copy.rejection_reason = rejection_reason
	copy.applied = applied
	copy.activation_tick = activation_tick
	copy.trigger_tick = trigger_tick
	copy.doctrine_id = doctrine_id
	copy.effect_id = effect_id
	copy.action_kind = action_kind
	copy.requires_observed_contact = requires_observed_contact
	copy.waiting_reason_key = waiting_reason_key
	copy.description_key = description_key
	copy.cost_key = cost_key
	copy.counterplay_key = counterplay_key
	copy.exit_condition = exit_condition
	return copy
