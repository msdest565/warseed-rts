extends "res://tests/scenarios/grey_ridge_decision_matrix.gd"

class PreviousManualResponse extends SimulationWorld:
	func _update_shared_formation_responses() -> void:
		var restored := {}
		for card in unit_cards.values():
			if card.control_state in [UnitCardState.ControlState.PLAYER_CONTROLLED, UnitCardState.ControlState.PLAYER_OVERRIDDEN]:
				restored[card.definition.definition_id] = card.control_state
				card.control_state = UnitCardState.ControlState.UNASSIGNED
		super._update_shared_formation_responses()
		for id in restored:
			unit_cards[id].control_state = restored[id]


func _initialize() -> void:
	var failures: Array[String] = []
	for previous in [true, false, false]:
		var world := PreviousManualResponse.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, &"western_feint") if previous else SimulationWorld.new(true, false, SimulationWorld.ScenarioKind.GREY_RIDGE, {}, &"western_feint")
		_issue_opening(world, &"b_split_armor", failures)
		for tick in range(MATRIX_TICKS):
			_issue_followup(world, &"b_split_armor", tick, failures)
			world.advance_tick()
		print("MANUAL_MATRIX previous_response=%s fingerprint=%s" % [previous, _fingerprint(world)])
		var card := world.unit_cards[&"armored_spearhead"] as UnitCardState
		var autonomous_shots := 0
		for event in world.events:
			if event.entity_id in card.member_entity_ids and event.kind == SimulationEvent.Kind.ATTACK_STARTED and event.detail.contains("autonomous=1"):
				autonomous_shots += 1
		print("MANUAL_MATRIX armor_reactions=%d" % autonomous_shots)
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
