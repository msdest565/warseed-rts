class_name EnemyReactionRuleState
extends RefCounted

enum TriggerKind {
	VISIBLE_HQ_THREAT,
	VISIBLE_CENTRAL_FORCE,
	VISIBLE_FLANK_FORCE,
	OWN_FORCE_DEPLETED,
}

enum ActionKind {
	DEFEND_HEADQUARTERS,
	COUNTERATTACK_CENTRAL,
	INTERCEPT_FLANK,
	WITHDRAW_TO_HEADQUARTERS,
}

var rule_id: StringName
var priority: int
var trigger_kind: TriggerKind
var action_kind: ActionKind
var delay_ticks: int
var commitment_ticks: int
var observed_tick: int = -1
var last_fired_tick: int = -1
var fired_count: int = 0
var last_target_entity_id: int = 0
var last_target_position: Vector2
var last_reason: String = ""


func _init(
	new_rule_id: StringName,
	new_priority: int,
	new_trigger_kind: TriggerKind,
	new_action_kind: ActionKind,
	new_delay_ticks: int,
	new_commitment_ticks: int
) -> void:
	rule_id = new_rule_id
	priority = new_priority
	trigger_kind = new_trigger_kind
	action_kind = new_action_kind
	delay_ticks = new_delay_ticks
	commitment_ticks = new_commitment_ticks
