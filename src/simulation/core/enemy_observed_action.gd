class_name EnemyObservedAction
extends RefCounted

var observation_id: int
var first_tick: int
var last_tick: int
var visible_strength: int
var action: StringName

func duplicate_value() -> EnemyObservedAction:
	var copy := EnemyObservedAction.new()
	copy.observation_id=observation_id
	copy.first_tick=first_tick
	copy.last_tick=last_tick
	copy.visible_strength=visible_strength
	copy.action=action
	return copy

func to_dictionary() -> Dictionary:
	return {"observation_id":observation_id,"first_tick":first_tick,"last_tick":last_tick,"visible_strength":visible_strength,"action":String(action),"source":"CURRENT_VISIBLE_UNITS"}

static func from_dictionary(value: Dictionary) -> EnemyObservedAction:
	if value.get("source","") != "CURRENT_VISIBLE_UNITS" or value.get("action","") not in ["MOVING","ENGAGING","HOLDING","SIGHTED"]: return null
	var result := EnemyObservedAction.new()
	result.observation_id=int(value.get("observation_id",0))
	result.first_tick=int(value.get("first_tick",0))
	result.last_tick=int(value.get("last_tick",0))
	result.visible_strength=int(value.get("visible_strength",0))
	result.action=StringName(value["action"])
	if result.visible_strength <= 0 or result.first_tick < 0 or result.last_tick < result.first_tick: return null
	return result
