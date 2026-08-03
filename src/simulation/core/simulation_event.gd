class_name SimulationEvent
extends RefCounted

enum Kind {
	COMMAND_ACCEPTED,
	COMMAND_REJECTED,
	UNIT_ARRIVED,
	UNIT_STUCK,
	ATTACK_STARTED,
	DAMAGE_APPLIED,
	UNIT_DESTROYED,
	TARGET_LOST,
	PROJECTILE_FIRED,
	PROJECTILE_IMPACTED,
	PROJECTILE_EXPIRED,
	ORE_DELIVERED,
	PRODUCTION_STARTED,
	UNIT_PRODUCED,
	FACTION_DEFEATED,
	FACTION_VICTORIOUS,
	TASK_STATE_CHANGED,
	UNIT_CONTROL_CHANGED,
	UNIT_REJOIN_STARTED,
	UNIT_REJOIN_COMPLETED,
}

var tick: int
var kind: Kind
var entity_id: int
var detail: String


func _init(new_tick: int, new_kind: Kind, new_entity_id: int, new_detail: String = "") -> void:
	tick = new_tick
	kind = new_kind
	entity_id = new_entity_id
	detail = new_detail
