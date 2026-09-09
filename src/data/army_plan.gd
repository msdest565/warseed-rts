class_name ArmyPlan
extends RefCounted

const COMMANDER_IDS: Array[StringName] = [&"bai_jiuyang", &"di_tian", &"lin_mo"]
const UNIT_CARD_IDS: Array[StringName] = [
	&"falcon_recon_group",
	&"ironwall_assault_group",
	&"armored_spearhead",
	&"thunder_fire_group",
]
const STARTING_CARD_COUNT := 2

var commander_by_unit_card: Dictionary = {}
var doctrine_by_commander: Dictionary = {}
var posture_by_commander: Dictionary = {}
var starting_unit_card_ids: Array[StringName] = []


static func grey_ridge_default() -> ArmyPlan:
	var content_result := BattleContentLoader.load_battle(&"grey_ridge")
	if content_result.is_valid():
		return content_result.battle.create_default_army_plan()
	push_error("Cannot create the Grey Ridge default army plan: %s" % [content_result.validation.issues])
	return ArmyPlan.new()


func duplicate_plan() -> ArmyPlan:
	var copy := ArmyPlan.new()
	copy.commander_by_unit_card = commander_by_unit_card.duplicate()
	copy.doctrine_by_commander = doctrine_by_commander.duplicate()
	copy.posture_by_commander = posture_by_commander.duplicate()
	copy.starting_unit_card_ids = starting_unit_card_ids.duplicate()
	return copy


func set_unit_card_commander(unit_card_id: StringName, commander_id: StringName) -> void:
	commander_by_unit_card[unit_card_id] = commander_id


func set_commander_doctrine(commander_id: StringName, doctrine_id: StringName) -> void:
	doctrine_by_commander[commander_id] = doctrine_id


func set_commander_posture(commander_id: StringName, posture: CommanderState.Posture) -> void:
	posture_by_commander[commander_id] = posture


func set_unit_card_starting(unit_card_id: StringName, starts_deployed: bool) -> void:
	if starts_deployed:
		if not starting_unit_card_ids.has(unit_card_id):
			starting_unit_card_ids.append(unit_card_id)
	else:
		starting_unit_card_ids.erase(unit_card_id)


func is_unit_card_starting(unit_card_id: StringName) -> bool:
	return starting_unit_card_ids.has(unit_card_id)


func validation_errors(
	commander_definitions: Dictionary,
	unit_card_definitions: Dictionary,
	doctrine_definitions: Dictionary,
	allowed_commander_ids: Array[StringName] = COMMANDER_IDS,
	allowed_unit_card_ids: Array[StringName] = UNIT_CARD_IDS,
	expected_starting_card_count: int = STARTING_CARD_COUNT
) -> Array[StringName]:
	var errors: Array[StringName] = []
	if starting_unit_card_ids.size() != expected_starting_card_count:
		errors.append(&"ARMY_PLAN_ERROR_STARTING_COUNT")
	var starting_seen: Dictionary = {}
	for unit_card_id in starting_unit_card_ids:
		if not allowed_unit_card_ids.has(unit_card_id) or starting_seen.has(unit_card_id):
			_append_error(errors, &"ARMY_PLAN_ERROR_STARTING_CARDS")
		starting_seen[unit_card_id] = true
	var used_capacity: Dictionary = {}
	for commander_id in allowed_commander_ids:
		used_capacity[commander_id] = 0
		var definition := commander_definitions.get(commander_id) as CommanderDefinition
		var doctrine_id := doctrine_by_commander.get(commander_id, &"") as StringName
		if definition == null or not doctrine_definitions.has(doctrine_id) or not definition.available_doctrine_ids.has(doctrine_id):
			_append_error(errors, &"ARMY_PLAN_ERROR_DOCTRINE")
		var posture := int(posture_by_commander.get(commander_id, -1))
		if posture < CommanderState.Posture.CAUTIOUS or posture > CommanderState.Posture.DISENGAGE:
			_append_error(errors, &"ARMY_PLAN_ERROR_POSTURE")
	for unit_card_id in allowed_unit_card_ids:
		var card_definition := unit_card_definitions.get(unit_card_id) as UnitCardDefinition
		var commander_id := commander_by_unit_card.get(unit_card_id, &"") as StringName
		if card_definition == null or not commander_definitions.has(commander_id):
			_append_error(errors, &"ARMY_PLAN_ERROR_ASSIGNMENT")
			continue
		used_capacity[commander_id] = int(used_capacity.get(commander_id, 0)) + card_definition.command_cost
	for commander_id in allowed_commander_ids:
		var commander_definition := commander_definitions.get(commander_id) as CommanderDefinition
		if commander_definition != null and int(used_capacity.get(commander_id, 0)) > commander_definition.capacity:
			_append_error(errors, &"ARMY_PLAN_ERROR_CAPACITY")
	return errors


func _append_error(errors: Array[StringName], error_key: StringName) -> void:
	if not errors.has(error_key):
		errors.append(error_key)
