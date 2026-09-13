class_name CardActionSnapshot
extends RefCounted

# A value-only, local-faction UI decision. Never an authoritative command.
const DEPLOY := -1
const TACTICAL := 100

var decision_id: StringName
var unit_card_id: StringName
var commander_id: StringName
var card_name_key: StringName
var commander_name_key: StringName
var action_kind: int
var target_id: StringName
var target_name_key: StringName
var position: Vector2
var radius: float = 54.0
var route := PackedVector2Array()
var current_strength: int
var authorized_strength: int
var supply_cost: int
var available_supply: int
var population: int
var population_capacity: int
var population_required: int
var cooldown_ticks: int
var target_entity_id: int = 0
var identification_ticks: int = 0
var tactical_name_key: StringName
var tactical_help_key: StringName
var reason: CommandValidationResult.Reason = CommandValidationResult.Reason.NONE


func action_key() -> StringName:
	if action_kind >= TACTICAL:
		return tactical_name_key
	match action_kind:
		DEPLOY: return &"CARD_DECISION_DEPLOY"
		SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT: return &"CARD_ACTION_REINFORCE"
		SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY: return &"CARD_ACTION_FORTIFY"
		SupportOrderCommand.SupportKind.ENGINEERING_ROUTE: return &"CARD_ACTION_ENGINEERING"
		SupportOrderCommand.SupportKind.RAPID_MOBILITY: return &"CARD_ACTION_MOBILITY"
		SupportOrderCommand.SupportKind.FRONTLINE_LOGISTICS: return &"CARD_ACTION_LOGISTICS"
	return &""
