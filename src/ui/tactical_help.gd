class_name TacticalHelp
extends RefCounted


static func posture(value: int) -> String:
	var posture_name: String = CommanderState.Posture.keys()[value]
	return GameText.t(&"COMMANDER_POSTURE_DETAIL") % [
		GameText.t(StringName("COMMANDER_POSTURE_%s" % posture_name)),
		GameText.t(StringName("COMMANDER_POSTURE_%s_TOOLTIP" % posture_name)),
	]


static func personality(key: StringName) -> String:
	return GameText.t(&"PREBATTLE_PERSONALITY_TOOLTIP") % [GameText.t(key), GameText.t(StringName("%s_TOOLTIP" % key))]
