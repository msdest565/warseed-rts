class_name GameText
extends RefCounted


static func t(key: StringName) -> String:
	return TranslationServer.translate(key)


static func command_result(result: CommandValidationResult) -> String:
	if result == null:
		return t(&"RESULT_NO_COMMAND")
	if result.is_accepted():
		return t(&"RESULT_ACCEPTED")
	var reason_key := StringName("REASON_%s" % CommandValidationResult.Reason.keys()[result.reason])
	return "%s: %s" % [t(&"RESULT_REJECTED"), t(reason_key)]


static func unit_name(definition_id: StringName) -> String:
	return t(StringName("UNIT_%s" % String(definition_id).to_upper()))


static func building_name(definition_id: StringName) -> String:
	return t(StringName("BUILDING_%s" % String(definition_id).to_upper()))


static func faction_name(faction_id: int) -> String:
	return t(&"FACTION_PLAYER") if faction_id == SimulationWorld.LOCAL_PLAYER_ID else t(&"FACTION_ENEMY")


static func enum_name(prefix: String, enum_value: String) -> String:
	return t(StringName("%s_%s" % [prefix, enum_value]))

