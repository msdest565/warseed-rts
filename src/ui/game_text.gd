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
	return t(&"RESULT_REJECTED_WITH_RECOVERY") % [t(reason_key), command_recovery(result.reason)]


static func command_recovery(reason: CommandValidationResult.Reason) -> String:
	var key: StringName
	match reason:
		CommandValidationResult.Reason.INVALID_TARGET, CommandValidationResult.Reason.INVALID_POSITION:
			key = &"RECOVERY_VALID_TARGET"
		CommandValidationResult.Reason.NOT_CONTROLLER:
			key = &"RECOVERY_TAKE_CONTROL"
		CommandValidationResult.Reason.ENTITY_DISABLED, CommandValidationResult.Reason.INVALID_DEPLOYMENT_STATE:
			key = &"RECOVERY_AVAILABLE_ENTITY"
		CommandValidationResult.Reason.PATH_UNAVAILABLE:
			key = &"RECOVERY_ADJUST_ROUTE"
		CommandValidationResult.Reason.FRIENDLY_TARGET:
			key = &"RECOVERY_HOSTILE_TARGET"
		CommandValidationResult.Reason.INSUFFICIENT_ORE:
			key = &"RECOVERY_GAIN_ORE"
		CommandValidationResult.Reason.PRODUCTION_BUSY, CommandValidationResult.Reason.PRODUCTION_QUEUE_FULL:
			key = &"RECOVERY_PRODUCTION_QUEUE"
		CommandValidationResult.Reason.INVALID_DEFINITION:
			key = &"RECOVERY_COMPATIBLE_UNIT"
		CommandValidationResult.Reason.INVALID_BUILDING:
			key = &"RECOVERY_OPERATIONAL_BUILDING"
		CommandValidationResult.Reason.INVALID_RESOURCE:
			key = &"RECOVERY_KNOWN_RESOURCE"
		CommandValidationResult.Reason.HIDDEN_TARGET:
			key = &"RECOVERY_RECON_OR_LAST_SEEN"
		CommandValidationResult.Reason.AGENT_OVERRIDE_BLOCKED:
			key = &"RECOVERY_RETURN_AGENT_CONTROL"
		CommandValidationResult.Reason.INVALID_TASK:
			key = &"RECOVERY_ACTIVE_TASK"
		CommandValidationResult.Reason.INVALID_DISPOSITION:
			key = &"RECOVERY_VALID_DISPOSITION"
		CommandValidationResult.Reason.TASK_CONFLICT:
			key = &"RECOVERY_RESOLVE_TASK_CONFLICT"
		CommandValidationResult.Reason.BUILDING_OCCUPIED:
			key = &"RECOVERY_OPEN_PLACEMENT"
		CommandValidationResult.Reason.CONSTRUCTION_BUSY:
			key = &"RECOVERY_IDLE_ENGINEER"
		CommandValidationResult.Reason.BUILDING_FULL_HEALTH:
			key = &"RECOVERY_DAMAGED_BUILDING"
		CommandValidationResult.Reason.AGENT_NOT_AUTHORIZED:
			key = &"RECOVERY_AI_AUTHORIZATION"
		CommandValidationResult.Reason.INSUFFICIENT_SUPPLY:
			key = &"RECOVERY_GAIN_SUPPLY"
		CommandValidationResult.Reason.POPULATION_FULL:
			key = &"RECOVERY_FREE_POPULATION"
		CommandValidationResult.Reason.SUPPORT_COOLDOWN:
			key = &"RECOVERY_WAIT_COOLDOWN"
		CommandValidationResult.Reason.SCENARIO_NOT_STARTED:
			key = &"RECOVERY_START_BATTLE"
		CommandValidationResult.Reason.COMMANDER_MISMATCH:
			key = &"RECOVERY_ASSIGNED_COMMANDER"
		CommandValidationResult.Reason.UNIT_CARD_FULL_STRENGTH:
			key = &"RECOVERY_DAMAGED_CARD"
		CommandValidationResult.Reason.BATTLE_CONCLUDED:
			key = &"RECOVERY_RETURN_TO_OPERATIONS"
		_:
			key = &"RECOVERY_RETRY_SELECTION"
	return t(key)


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


static func intel_contact_tooltip(definition_id: StringName) -> String:
	return t(&"INTEL_CONTACT_TOOLTIP") % unit_name(definition_id)


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
