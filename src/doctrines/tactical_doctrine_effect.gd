class_name TacticalDoctrineEffect
extends RefCounted


func build(snapshot: WorldSnapshot, commander: CommanderSnapshot, card: UnitCardSnapshot, doctrine: DoctrineDefinition, definition: DoctrineEffectDefinition) -> DoctrineTaskParameters:
	var kind := definition.effect.kind
	if kind == DoctrineActionDefinition.Kind.REQUIRE_OBSERVED_CONTACT and card.role_key != &"UNIT_CARD_ROLE_FIREPOWER":
		return DoctrineTaskParameters.new()
	if kind == DoctrineActionDefinition.Kind.CAUTIOUS_RECON and card.role_key != &"UNIT_CARD_ROLE_RECON":
		return DoctrineTaskParameters.new()
	var result := StagedDepartureEffect.new().build(snapshot, commander, card, doctrine, definition)
	if result.applied:
		result.action_kind = kind
		result.activation_tick = snapshot.tick + definition.timing.base_delay_ticks
		result.requires_observed_contact = kind == DoctrineActionDefinition.Kind.REQUIRE_OBSERVED_CONTACT
	return result
