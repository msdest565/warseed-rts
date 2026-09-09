class_name EnemyReactionSnapshot
extends RefCounted

var rule_id: StringName
var priority: int
var trigger_kind: EnemyReactionRuleState.TriggerKind
var action_kind: EnemyReactionRuleState.ActionKind
var delay_ticks: int
var commitment_ticks: int
var observed_tick: int
var last_fired_tick: int
var fired_count: int
var last_target_entity_id: int
var last_target_position: Vector2
var last_reason: String


func _init(state: EnemyReactionRuleState) -> void:
	rule_id = state.rule_id
	priority = state.priority
	trigger_kind = state.trigger_kind
	action_kind = state.action_kind
	delay_ticks = state.delay_ticks
	commitment_ticks = state.commitment_ticks
	observed_tick = state.observed_tick
	last_fired_tick = state.last_fired_tick
	fired_count = state.fired_count
	last_target_entity_id = state.last_target_entity_id
	last_target_position = state.last_target_position
	last_reason = state.last_reason
