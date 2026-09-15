class_name GreyRidgeBaselineStrategy
extends RefCounted

const STRATEGY_IDS: Array[StringName] = [
	&"split_axis",
	&"concentrated_attack",
	&"recon_then_commit",
	&"reserve_policy",
	&"no_intervention",
]
const SPLIT_HEADQUARTERS_APPROACH := Vector2(2928.0, 480.0)
const CONCENTRATED_HEADQUARTERS_APPROACH := Vector2(3248.0, 480.0)

var last_rejection_reason := ""


func decide(strategy_id: StringName, observation: WorldSnapshot, issued_actions: Dictionary) -> Array[Dictionary]:
	last_rejection_reason = ""
	if not STRATEGY_IDS.has(strategy_id):
		last_rejection_reason = "UNKNOWN_STRATEGY_ID"
		return []
	if observation == null:
		last_rejection_reason = "NULL_OBSERVATION"
		return []
	if observation.is_true_state:
		last_rejection_reason = "TRUE_STATE_FORBIDDEN"
		return []
	if observation.observer_faction_id != SimulationWorld.LOCAL_PLAYER_ID:
		last_rejection_reason = "WRONG_OBSERVER_FACTION"
		return []
	match strategy_id:
		&"split_axis":
			return _split_axis(observation, issued_actions)
		&"concentrated_attack":
			return _concentrated_attack(observation, issued_actions)
		&"recon_then_commit":
			return _recon_then_commit(observation, issued_actions)
		&"reserve_policy":
			return _reserve_policy(observation, issued_actions)
	return []


func _split_axis(snapshot: WorldSnapshot, issued: Dictionary) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	_add_once(intents, issued, "deploy_thunder", _deploy_intent(&"thunder_fire_group", _headquarters_position(snapshot) + Vector2(-192.0, -64.0), "split_axis_fire_support"))
	_add_once(intents, issued, "fortify_ironwall", _support_intent(SupportOrderCommand.SupportKind.EMERGENCY_FORTIFY, &"ironwall_assault_group", "split_axis_holding_force_fortified"))
	_add_once(intents, issued, "di_central", _objective_intent(&"di_tian", &"central_relay", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, "split_axis_main_effort"))
	_add_once(intents, issued, "bai_west", _objective_intent(&"bai_jiuyang", &"west_mine", SimulationWorld.GREY_RIDGE_WEST_POSITION, "split_axis_flank"))
	if snapshot.tick >= 100:
		_add_once(intents, issued, "lin_central", _objective_intent(&"lin_mo", &"central_relay", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, "split_axis_support_commit"))
	if snapshot.tick >= 300 and _local_supply(snapshot) >= 2 and _card_can_be_reinforced(snapshot, &"ironwall_assault_group"):
		_add_once(intents, issued, "reinforce_ironwall", _support_intent(SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"ironwall_assault_group", "split_axis_holding_force_reinforced"))
	if snapshot.tick >= 400:
		_add_once(intents, issued, "di_rearguard", _posture_intent(&"di_tian", CommanderState.Posture.HOLD, "split_axis_rearguard_hold"))
	if snapshot.tick >= 401 and bool(issued.get("di_rearguard", false)) and _local_supply(snapshot) >= 4:
		_add_once(intents, issued, "deploy_armor_rearguard", _deploy_intent(&"armored_spearhead", _headquarters_position(snapshot) + Vector2(192.0, -64.0), "split_axis_rearguard_commit"))
	if snapshot.tick >= 430 and _card_is_deployed(snapshot, &"thunder_fire_group"):
		_add_once(intents, issued, "takeover_thunder", _card_control_intent(&"thunder_fire_group", UnitCardControlCommand.Action.TAKEOVER, "split_axis_exploitation_control"))
	if snapshot.tick >= 431 and bool(issued.get("takeover_thunder", false)) and _card_is_deployed(snapshot, &"thunder_fire_group"):
		_add_once(intents, issued, "advance_thunder", _formation_attack_move_intent(
			&"thunder_fire_group", SPLIT_HEADQUARTERS_APPROACH, _split_assault_route(),
			"split_axis_western_exploitation"
		))
		var headquarters_id := _visible_enemy_headquarters_id(snapshot)
		if headquarters_id != 0:
			_add_once(intents, issued, "attack_headquarters_thunder", _formation_attack_intent(
				&"thunder_fire_group", headquarters_id, "split_axis_headquarters_assault"
			))
	if snapshot.tick >= 2200 and _card_is_deployed(snapshot, &"armored_spearhead"):
		_add_once(intents, issued, "takeover_armor_exploitation", _card_control_intent(&"armored_spearhead", UnitCardControlCommand.Action.TAKEOVER, "split_axis_rearguard_released"))
	if snapshot.tick >= 2201 and bool(issued.get("takeover_armor_exploitation", false)) and _card_has_commandable_formation(snapshot, &"armored_spearhead"):
		_add_once(intents, issued, "advance_armor_exploitation", _formation_attack_move_intent(
			&"armored_spearhead", CONCENTRATED_HEADQUARTERS_APPROACH, _split_reserve_route(),
			"split_axis_eastern_exploitation"
		))
		var reserve_headquarters_id := _visible_enemy_headquarters_id(snapshot)
		if reserve_headquarters_id != 0:
			_add_once(intents, issued, "attack_headquarters_armor", _formation_attack_intent(
				&"armored_spearhead", reserve_headquarters_id, "split_axis_reserve_headquarters_assault"
			))
	return intents


func _concentrated_attack(snapshot: WorldSnapshot, issued: Dictionary) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	_add_once(intents, issued, "deploy_armor", _deploy_intent(&"armored_spearhead", _headquarters_position(snapshot) + Vector2(192.0, -64.0), "concentrated_reserve_commit"))
	_add_once(intents, issued, "di_aggressive", _posture_intent(&"di_tian", CommanderState.Posture.AGGRESSIVE, "concentrated_attack_posture"))
	_add_once(intents, issued, "di_central", _objective_intent(&"di_tian", &"central_relay", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, "concentrated_main_effort"))
	_add_once(intents, issued, "bai_central", _objective_intent(&"bai_jiuyang", &"central_relay", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION, "concentrated_recon_screen"))
	if snapshot.tick >= 100 and _card_is_deployed(snapshot, &"armored_spearhead"):
		_add_once(intents, issued, "takeover_armor", _card_control_intent(&"armored_spearhead", UnitCardControlCommand.Action.TAKEOVER, "concentrated_breakthrough_control"))
	if snapshot.tick >= 100 and _card_is_deployed(snapshot, &"ironwall_assault_group"):
		_add_once(intents, issued, "takeover_ironwall", _card_control_intent(&"ironwall_assault_group", UnitCardControlCommand.Action.TAKEOVER, "concentrated_vanguard_control"))
	if snapshot.tick >= 101 and bool(issued.get("takeover_armor", false)) and _card_has_commandable_formation(snapshot, &"armored_spearhead"):
		_add_once(intents, issued, "advance_armor", _formation_attack_move_intent(
			&"armored_spearhead", CONCENTRATED_HEADQUARTERS_APPROACH, _concentrated_assault_route(),
			"concentrated_headquarters_breakthrough"
		))
		var headquarters_id := _visible_enemy_headquarters_id(snapshot)
		if headquarters_id != 0:
			_add_once(intents, issued, "attack_headquarters_armor", _formation_attack_intent(
				&"armored_spearhead", headquarters_id, "concentrated_headquarters_assault"
			))
	if snapshot.tick >= 101 and bool(issued.get("takeover_ironwall", false)) and _card_has_commandable_formation(snapshot, &"ironwall_assault_group"):
		_add_once(intents, issued, "advance_ironwall", _formation_attack_move_intent(
			&"ironwall_assault_group", SPLIT_HEADQUARTERS_APPROACH, _concentrated_assault_route(),
			"concentrated_vanguard_breakthrough"
		))
		var vanguard_headquarters_id := _visible_enemy_headquarters_id(snapshot)
		if vanguard_headquarters_id != 0:
			_add_once(intents, issued, "attack_headquarters_ironwall", _formation_attack_intent(
				&"ironwall_assault_group", vanguard_headquarters_id, "concentrated_vanguard_headquarters_assault"
			))
	if snapshot.tick >= 200 and _support_ready(snapshot, SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT) and _local_supply(snapshot) >= 2 and _card_can_be_reinforced(snapshot, &"armored_spearhead"):
		_add_once(intents, issued, "reinforce_armor", _support_intent(SupportOrderCommand.SupportKind.FIELD_REINFORCEMENT, &"armored_spearhead", "concentrated_spearhead_reinforced"))
	# A retreating defender may no longer pull the vanguard into headquarters vision.
	# Search forward only after our own force reaches the authored approach unseen.
	if _visible_enemy_headquarters_id(snapshot) == 0:
		for card_id in [&"ironwall_assault_group", &"armored_spearhead"]:
			var card := snapshot.get_unit_card(card_id)
			if card == null or card.current_strength <= 0: continue
			var formation := snapshot.get_formation(card.formation_id)
			var approach := SPLIT_HEADQUARTERS_APPROACH if card_id == &"ironwall_assault_group" else CONCENTRATED_HEADQUARTERS_APPROACH
			if formation == null or formation.is_moving or formation.anchor_position.distance_to(approach) > 64.0: continue
			var search := _formation_attack_move_intent(card_id, approach + Vector2(0, -96), PackedVector2Array(), "concentrated_reconnoiter_unseen_objective")
			search["is_correction"] = true
			search["correction_reason"] = "approach_reached_without_objective_contact"
			_add_once(intents, issued, "search_objective_" + String(card_id), search)
	return intents


func _recon_then_commit(snapshot: WorldSnapshot, issued: Dictionary) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	_add_once(intents, issued, "air_recon", {
		"action": "air_recon",
		"category": "support",
		"primary_region_id": &"west_mine",
		"secondary_region_id": &"central_relay",
		"reason_key": "recon_before_commitment",
	})
	_add_once(intents, issued, "di_cautious", _posture_intent(&"di_tian", CommanderState.Posture.CAUTIOUS, "recon_screen_posture"))
	if snapshot.tick >= 60 and _has_current_intel(snapshot):
		var target_region := _highest_reported_region(snapshot)
		var target_position := _region_position(target_region)
		_add_once(intents, issued, "di_commit", _objective_intent(&"di_tian", target_region, target_position, "commit_after_visible_intel"))
		_add_once(intents, issued, "bai_commit", _objective_intent(&"bai_jiuyang", target_region, target_position, "recon_screen_after_visible_intel"))
	return intents


func _reserve_policy(snapshot: WorldSnapshot, issued: Dictionary) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	_add_once(intents, issued, "di_hold", _posture_intent(&"di_tian", CommanderState.Posture.HOLD, "preserve_reserve"))
	_add_once(intents, issued, "di_central", _objective_intent(&"di_tian", &"central_relay", SimulationWorld.GREY_RIDGE_CENTRAL_POSITION + Vector2(0.0, 320.0), "forward_defense_with_reserve"))
	_add_once(intents, issued, "bai_west", _objective_intent(&"bai_jiuyang", &"west_mine", SimulationWorld.GREY_RIDGE_WEST_POSITION + Vector2(0.0, 240.0), "reserve_early_warning"))
	if _visible_threat(snapshot) or _imminent_intel(snapshot):
		_add_once(intents, issued, "deploy_armor", _deploy_intent(&"armored_spearhead", _headquarters_position(snapshot) + Vector2(192.0, -64.0), "reserve_triggered_by_legal_observation"))
	return intents


func _add_once(intents: Array[Dictionary], issued: Dictionary, key: String, intent: Dictionary) -> void:
	if issued.has(key):
		return
	intent["action_key"] = key
	intents.append(intent)


func _deploy_intent(card_id: StringName, position: Vector2, reason: String) -> Dictionary:
	return {"action": "deploy", "category": "unit_card", "card_id": card_id, "position": position, "reason_key": reason}


func _objective_intent(commander_id: StringName, region_id: StringName, position: Vector2, reason: String) -> Dictionary:
	return {"action": "objective", "category": "commander", "actor_id": commander_id, "region_id": region_id, "position": position, "reason_key": reason}


func _posture_intent(commander_id: StringName, posture: CommanderState.Posture, reason: String) -> Dictionary:
	return {"action": "posture", "category": "commander", "actor_id": commander_id, "posture": posture, "reason_key": reason}


func _support_intent(kind: SupportOrderCommand.SupportKind, card_id: StringName, reason: String) -> Dictionary:
	return {
		"action": "support",
		"category": "support",
		"support_kind": kind,
		"card_id": card_id,
		"reason_key": reason,
	}


func _card_control_intent(card_id: StringName, control_action: UnitCardControlCommand.Action, reason: String) -> Dictionary:
	return {"action": "card_control", "category": "unit_card", "card_id": card_id, "control_action": control_action, "reason_key": reason}


func _formation_move_intent(card_id: StringName, position: Vector2, reason: String) -> Dictionary:
	return {
		"action": "formation_move",
		"category": "unit_card",
		"card_id": card_id,
		"position": position,
		"reason_key": reason,
		"is_correction": true,
		"correction_reason": "manual_breakthrough_adjustment",
	}


func _formation_attack_move_intent(card_id: StringName, position: Vector2, route: PackedVector2Array, reason: String) -> Dictionary:
	return {
		"action": "formation_attack_move",
		"category": "unit_card",
		"card_id": card_id,
		"position": position,
		"route_points": route.duplicate(),
		"reason_key": reason,
	}


func _formation_attack_intent(card_id: StringName, target_entity_id: int, reason: String) -> Dictionary:
	return {
		"action": "formation_attack",
		"category": "unit_card",
		"card_id": card_id,
		"target_entity_id": target_entity_id,
		"reason_key": reason,
	}


func _split_assault_route() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(2432.0, 1568.0),
		Vector2(2688.0, 832.0),
	])


func _concentrated_assault_route() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(3200.0, 1440.0),
		Vector2(3296.0, 800.0),
	])


func _split_reserve_route() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(3584.0, 1536.0),
		Vector2(3456.0, 832.0),
	])


func _headquarters_position(snapshot: WorldSnapshot) -> Vector2:
	for building in snapshot.buildings:
		if building.faction_id == snapshot.observer_faction_id and building.definition_id == &"command_center":
			return building.position
	return Vector2(3088.0, 3536.0)


func _card_is_deployed(snapshot: WorldSnapshot, card_id: StringName) -> bool:
	var card := snapshot.get_unit_card(card_id)
	return card != null and card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.current_strength > 0 and snapshot.get_formation(card.formation_id) != null


func _card_can_be_reinforced(snapshot: WorldSnapshot, card_id: StringName) -> bool:
	var card := snapshot.get_unit_card(card_id)
	return card != null and card.deployment_state == UnitCardState.DeploymentState.DEPLOYED and card.current_strength > 0 and card.current_strength < card.authorized_strength


func _card_has_commandable_formation(snapshot: WorldSnapshot, card_id: StringName) -> bool:
	var card := snapshot.get_unit_card(card_id)
	if card == null or card.deployment_state != UnitCardState.DeploymentState.DEPLOYED or card.current_strength <= 0:
		return false
	var formation := snapshot.get_formation(card.formation_id)
	if formation == null:
		return false
	var leader := snapshot.get_unit(formation.leader_entity_id)
	return leader != null and leader.enabled


func _local_supply(snapshot: WorldSnapshot) -> int:
	var faction := snapshot.get_faction(snapshot.observer_faction_id)
	return faction.supply if faction != null else 0


func _support_ready(snapshot: WorldSnapshot, kind: SupportOrderCommand.SupportKind) -> bool:
	var faction := snapshot.get_faction(snapshot.observer_faction_id)
	return faction != null and int(faction.support_cooldown_until_by_kind.get(kind, 0)) <= snapshot.tick


func _visible_enemy_headquarters_id(snapshot: WorldSnapshot) -> int:
	for building in snapshot.buildings:
		if building.faction_id != snapshot.observer_faction_id and building.definition_id == &"command_center" and building.enabled and building.is_visible:
			return building.entity_id
	return 0


func _commander_has_active_card(snapshot: WorldSnapshot, commander_id: StringName) -> bool:
	var commander := snapshot.get_commander(commander_id)
	if commander == null:
		return false
	for card_id in commander.subordinate_unit_card_ids:
		if _card_is_deployed(snapshot, card_id):
			return true
	return false


func _has_blocked_friendly_task(snapshot: WorldSnapshot) -> bool:
	for task in snapshot.tasks:
		if task.faction_id == snapshot.observer_faction_id and task.lifecycle == TaskState.Lifecycle.BLOCKED:
			return true
	return false


func _has_current_intel(snapshot: WorldSnapshot) -> bool:
	for report in snapshot.intel_reports:
		if not report.superseded and report.age_ticks <= 100:
			return true
	return false


func _highest_reported_region(snapshot: WorldSnapshot) -> StringName:
	var best_region: StringName = &"central_relay"
	var best_estimate := -1
	for report in snapshot.intel_reports:
		if report.superseded or not report.has_estimate:
			continue
		if report.estimated_max > best_estimate or report.estimated_max == best_estimate and String(report.region_id) < String(best_region):
			best_estimate = report.estimated_max
			best_region = report.region_id
	return best_region


func _region_position(region_id: StringName) -> Vector2:
	match region_id:
		&"west_mine": return SimulationWorld.GREY_RIDGE_WEST_POSITION
		&"east_supply": return SimulationWorld.GREY_RIDGE_EAST_POSITION
	return SimulationWorld.GREY_RIDGE_CENTRAL_POSITION


func _visible_threat(snapshot: WorldSnapshot) -> bool:
	for unit in snapshot.units:
		if unit.faction_id != snapshot.observer_faction_id and unit.enabled and unit.is_visible_to_local_player:
			return true
	return false


func _imminent_intel(snapshot: WorldSnapshot) -> bool:
	for report in snapshot.intel_reports:
		if not report.superseded and report.has_estimate and report.eta_min_ticks >= 0 and report.eta_min_ticks <= 80:
			return true
	return false
