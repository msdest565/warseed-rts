class_name EnemyActionAuditRecord
extends RefCounted

var command_id: int
var formation_id: int
var task_id: int
var rule_id: StringName
var fact_source: StringName
var fact_detail: String
var command_kind: StringName
var observed_tick: int = -1
var accepted_tick: int = -1
var applied_tick: int = -1
var changed_tick: int = -1
var required_delay_ticks: int = 0
var committed_until_tick: int = 0
var committed_strength: int = 0
var supply_cost: int = 0
var target_entity_id: int = 0
var target_position: Vector2
var status: StringName = &"ACCEPTED"

func duplicate_value() -> EnemyActionAuditRecord:
	var copy := EnemyActionAuditRecord.new()
	copy.command_id = command_id
	copy.formation_id = formation_id
	copy.task_id = task_id
	copy.rule_id = rule_id
	copy.fact_source = fact_source
	copy.fact_detail = fact_detail
	copy.command_kind = command_kind
	copy.observed_tick = observed_tick
	copy.accepted_tick = accepted_tick
	copy.applied_tick = applied_tick
	copy.changed_tick = changed_tick
	copy.required_delay_ticks = required_delay_ticks
	copy.committed_until_tick = committed_until_tick
	copy.committed_strength = committed_strength
	copy.supply_cost = supply_cost
	copy.target_entity_id = target_entity_id
	copy.target_position = target_position
	copy.status = status
	return copy

func to_dictionary() -> Dictionary:
	return {
		"command_id": command_id,
		"formation_id": formation_id,
		"task_id": task_id,
		"rule_id": String(rule_id),
		"fact_source": String(fact_source),
		"fact_detail": fact_detail,
		"command_kind": String(command_kind),
		"observed_tick": observed_tick,
		"accepted_tick": accepted_tick,
		"applied_tick": applied_tick,
		"changed_tick": changed_tick,
		"required_delay_ticks": required_delay_ticks,
		"committed_until_tick": committed_until_tick,
		"committed_strength": committed_strength,
		"supply_cost": supply_cost,
		"target_entity_id": target_entity_id,
		"target_position": [target_position.x, target_position.y],
		"status": String(status)
	}