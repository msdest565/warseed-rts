class_name BattlefieldSituationSnapshot
extends RefCounted

const SCHEMA_ID := "warseed.battlefield-situation.v1"

var source_tick: int
var observer_faction_id: int
var battlefield_bounds: Rect2
var frontline_segments: Array[Dictionary]
var task_axes: Array[Dictionary]
var threat_zones: Array[Dictionary]
var uncertainty_zones: Array[Dictionary]
var card_statuses: Array[Dictionary]
var supply: Dictionary


func _init(
	new_source_tick: int,
	new_observer_faction_id: int,
	new_battlefield_bounds: Rect2,
	new_frontline_segments: Array[Dictionary],
	new_task_axes: Array[Dictionary],
	new_threat_zones: Array[Dictionary],
	new_uncertainty_zones: Array[Dictionary],
	new_card_statuses: Array[Dictionary],
	new_supply: Dictionary
) -> void:
	source_tick = new_source_tick
	observer_faction_id = new_observer_faction_id
	battlefield_bounds = new_battlefield_bounds
	frontline_segments.assign(new_frontline_segments.duplicate(true))
	task_axes.assign(new_task_axes.duplicate(true))
	threat_zones.assign(new_threat_zones.duplicate(true))
	uncertainty_zones.assign(new_uncertainty_zones.duplicate(true))
	card_statuses.assign(new_card_statuses.duplicate(true))
	supply = new_supply.duplicate(true)


func to_dictionary() -> Dictionary:
	return {
		"schema_id": SCHEMA_ID,
		"source_tick": source_tick,
		"observer_faction_id": observer_faction_id,
		"battlefield_bounds": _rect_array(battlefield_bounds),
		"frontline_segments": _serialize_array(frontline_segments),
		"task_axes": _serialize_array(task_axes),
		"threat_zones": _serialize_array(threat_zones),
		"uncertainty_zones": _serialize_array(uncertainty_zones),
		"card_statuses": _serialize_array(card_statuses),
		"supply": _serialize_dictionary(supply),
	}


func canonical_json() -> String:
	return JSON.stringify(to_dictionary())


func fingerprint() -> String:
	return canonical_json().sha256_text()


static func _serialize_array(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(_serialize_variant(value))
	return result


static func _serialize_dictionary(values: Dictionary) -> Dictionary:
	var result := {}
	var keys := values.keys()
	keys.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
	for key in keys:
		result[str(key)] = _serialize_variant(values[key])
	return result


static func _serialize_variant(value: Variant) -> Variant:
	if value is Dictionary:
		return _serialize_dictionary(value)
	if value is Array:
		return _serialize_array(value)
	if value is PackedVector2Array:
		var points: Array = []
		for point in value:
			points.append(_vector_array(point))
		return points
	if value is Vector2:
		return _vector_array(value)
	if value is Rect2:
		return _rect_array(value)
	if value is StringName:
		return String(value)
	return value


static func _vector_array(value: Vector2) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001)]


static func _rect_array(value: Rect2) -> Array:
	return [
		snappedf(value.position.x, 0.001),
		snappedf(value.position.y, 0.001),
		snappedf(value.size.x, 0.001),
		snappedf(value.size.y, 0.001),
	]
