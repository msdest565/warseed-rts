class_name CommandSituationSnapshot
extends RefCounted

const SCHEMA_ID := "warseed.command-situation.v1"

var source_tick: int
var observer_faction_id: int
var intents: Array[HighLevelIntentSnapshot]
var exceptions: Array[CommandExceptionSnapshot]


func _init(
	new_source_tick: int,
	new_observer_faction_id: int,
	new_intents: Array[HighLevelIntentSnapshot],
	new_exceptions: Array[CommandExceptionSnapshot]
) -> void:
	source_tick = new_source_tick
	observer_faction_id = new_observer_faction_id
	intents.assign(new_intents)
	exceptions.assign(new_exceptions)


func to_dictionary() -> Dictionary:
	var intent_values: Array[Dictionary] = []
	for intent in intents:
		intent_values.append(intent.to_dictionary())
	var exception_values: Array[Dictionary] = []
	for exception in exceptions:
		exception_values.append(exception.to_dictionary())
	return {
		"schema_id": SCHEMA_ID,
		"source_tick": source_tick,
		"observer_faction_id": observer_faction_id,
		"intents": intent_values,
		"exceptions": exception_values,
	}


func canonical_json() -> String:
	return JSON.stringify(to_dictionary())


func fingerprint() -> String:
	return canonical_json().sha256_text()


func get_exception(exception_id: StringName) -> CommandExceptionSnapshot:
	for exception in exceptions:
		if exception.exception_id == exception_id:
			return exception
	return null
