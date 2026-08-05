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


static func unit_description(definition_id: StringName) -> String:
	return t(StringName("UNIT_DESCRIPTION_%s" % String(definition_id).to_upper()))


static func building_description(definition_id: StringName) -> String:
	return t(StringName("BUILDING_DESCRIPTION_%s" % String(definition_id).to_upper()))


static func unit_tooltip(definition_id: StringName) -> String:
	var definition := SimulationWorld.UNIT_CATALOG.get_unit(definition_id)
	if definition == null:
		return unit_name(definition_id)
	var combat := definition.combat
	return t(&"UNIT_TOOLTIP") % [
		unit_name(definition_id), unit_description(definition_id), definition.production_cost,
		definition.production_ticks * SimulationWorld.TICK_SECONDS, combat.max_health,
		combat.attack_power, combat.attack_range, definition.move_speed,
	]


static func building_tooltip(definition_id: StringName) -> String:
	var definition := SimulationWorld.BUILDING_CATALOG.get_building(definition_id)
	if definition == null:
		return building_name(definition_id)
	return t(&"BUILDING_TOOLTIP") % [
		building_name(definition_id), building_description(definition_id), definition.build_cost,
		definition.build_ticks * SimulationWorld.TICK_SECONDS, definition.max_health,
		definition.armor,
	]


static func faction_name(faction_id: int) -> String:
	return t(&"FACTION_PLAYER") if faction_id == SimulationWorld.LOCAL_PLAYER_ID else t(&"FACTION_ENEMY")


static func enum_name(prefix: String, enum_value: String) -> String:
	return t(StringName("%s_%s" % [prefix, enum_value]))
