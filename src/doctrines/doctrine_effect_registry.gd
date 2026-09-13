class_name DoctrineEffectRegistry
extends RefCounted

var _executors: Dictionary = {}


func _init() -> void:
	_executors[DoctrineActionDefinition.Kind.STAGED_DEPARTURE] = StagedDepartureEffect.new()
	for kind in [DoctrineActionDefinition.Kind.REQUIRE_OBSERVED_CONTACT, DoctrineActionDefinition.Kind.CAUTIOUS_RECON, DoctrineActionDefinition.Kind.NARROW_FRONTAGE]:
		_executors[kind] = TacticalDoctrineEffect.new()


func find_effect(equipped_ids: Array[StringName], definitions: Dictionary, kind: DoctrineActionDefinition.Kind) -> DoctrineEffectDefinition:
	var ordered := equipped_ids.duplicate()
	ordered.sort()
	for id in ordered:
		var doctrine := definitions.get(id) as DoctrineDefinition
		if doctrine == null:
			continue
		for definition in doctrine.effects:
			if definition != null and definition.effect != null and definition.effect.kind == kind:
				return definition
	return null


func create_task_parameters(snapshot: WorldSnapshot, faction_id: int, commander_id: StringName, card_id: StringName, doctrines: Array[DoctrineDefinition]) -> DoctrineTaskParameters:
	var result := DoctrineTaskParameters.new()
	if snapshot == null:
		result.rejection_reason = &"SNAPSHOT_REQUIRED"
		return result
	if snapshot.is_true_state:
		result.rejection_reason = &"TRUE_STATE_FORBIDDEN"
		return result
	if snapshot.observer_faction_id != faction_id:
		result.rejection_reason = &"WRONG_OBSERVER_FACTION"
		return result
	if snapshot.knowledge == null or snapshot.knowledge.faction_id != faction_id:
		result.rejection_reason = &"FACTION_KNOWLEDGE_REQUIRED"
		return result
	var commander := snapshot.get_commander(commander_id)
	var card := snapshot.get_unit_card(card_id)
	if commander == null or card == null or commander.faction_id != faction_id or card.faction_id != faction_id or card.commander_definition_id != commander_id or not commander.subordinate_unit_card_ids.has(card_id):
		result.rejection_reason = &"COMMANDER_OR_CARD_REQUIRED"
		return result
	if card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or card.control_state in [UnitCardState.ControlState.PLAYER_OVERRIDDEN, UnitCardState.ControlState.RETURNING]:
		result.rejection_reason = &"CARD_NOT_ELIGIBLE"
		return result
	var ordered := doctrines.duplicate()
	for doctrine in ordered:
		if doctrine == null or not doctrine.validate().is_valid():
			result.rejection_reason = &"INVALID_EFFECT_DEFINITION"
			return result
	ordered.sort_custom(func(left: DoctrineDefinition, right: DoctrineDefinition) -> bool: return String(left.definition_id) < String(right.definition_id))
	for doctrine in ordered:
		if not commander.equipped_doctrine_ids.has(doctrine.definition_id):
			continue
		for definition in doctrine.effects:
			var executor: RefCounted = _executors.get(definition.effect.kind)
			if executor == null:
				result.rejection_reason = &"INVALID_EFFECT_DEFINITION"
				return result
			# The schema currently permits one timing action per doctrine. The first
			# equipped definition in stable ID order owns that task parameter.
			return executor.build(snapshot, commander, card, doctrine, definition)
	return result
