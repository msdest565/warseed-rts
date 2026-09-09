class_name ScenarioStatus
extends PanelContainer

@onready var title_label: Label = $Margin/Layout/Title
@onready var objective_label: Label = $Margin/Layout/Objective
var simulation_host: SimulationHost


func configure(host: SimulationHost) -> void:
	simulation_host = host


func update_snapshot(snapshot: WorldSnapshot) -> void:
	if snapshot == null or not visible:
		return
	var faction := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	var battle := simulation_host.world.battle_definition if simulation_host != null else null
	var time_limit := battle.time_limit_ticks if battle != null else SimulationWorld.GREY_RIDGE_TIME_LIMIT_TICKS
	var remaining_ticks := maxi(0, time_limit - snapshot.tick)
	var remaining_seconds := ceili(remaining_ticks * SimulationWorld.TICK_SECONDS)
	var state_key: StringName = &"GREY_RIDGE_ACTIVE"
	if snapshot.outcome != null and snapshot.outcome.result == BattleOutcome.Result.ORDERED_WITHDRAWAL:
		state_key = &"BATTLE_OUTCOME_ORDERED_WITHDRAWAL"
	elif faction != null and faction.victorious:
		state_key = &"GREY_RIDGE_VICTORY"
	elif faction != null and faction.defeated:
		state_key = &"GREY_RIDGE_DEFEAT"
	var battle_name := GameText.t(battle.display_name_key) if battle != null else GameText.t(&"GREY_RIDGE_TITLE")
	title_label.text = "%s / %s / %02d:%02d" % [battle_name, GameText.t(state_key), remaining_seconds / 60, remaining_seconds % 60]
	title_label.tooltip_text = title_label.text
	var local_regions := 0
	var hostile_regions := 0
	var neutral_regions := 0
	var contested_regions := 0
	var region_definitions := battle.region_dictionary() if battle != null else {}
	for region in snapshot.strategic_regions:
		var definition := region_definitions.get(region.region_id) as BattleRegionDefinition
		if definition != null and not definition.capturable:
			continue
		if region.contested:
			contested_regions += 1
		elif region.controller_faction_id == SimulationWorld.LOCAL_PLAYER_ID:
			local_regions += 1
		elif region.controller_faction_id == 0:
			neutral_regions += 1
		else:
			hostile_regions += 1
	var objective_lines := PackedStringArray()
	for objective in snapshot.objectives:
		var marker := GameText.t(objective_status_marker_key(objective.status))
		objective_lines.append("%s %s" % [marker, GameText.t(objective.display_name_key)])
	if not objective_lines.is_empty():
		objective_label.text = "   ".join(objective_lines)
	else:
		objective_label.text = GameText.t(&"GREY_RIDGE_OBJECTIVE_REGIONS") % [
			local_regions, hostile_regions, neutral_regions, contested_regions,
		]
	var region_status := GameText.t(&"GREY_RIDGE_OBJECTIVE_REGIONS") % [
		local_regions, hostile_regions, neutral_regions, contested_regions,
	]
	objective_label.text = "%s   %s" % [objective_label.text, region_status]
	if battle != null and battle.scenario_id == &"black_well":
		var withdrawn_cards := 0
		var low_organization_cards := 0
		for card in snapshot.unit_cards:
			if card.faction_id != SimulationWorld.LOCAL_PLAYER_ID:
				continue
			if card.deployment_state == UnitCardState.DeploymentState.WITHDRAWN:
				withdrawn_cards += 1
			elif card.deployment_state == UnitCardState.DeploymentState.DEPLOYED \
					and card.organization_enabled and card.organization < 30.0:
				low_organization_cards += 1
		objective_label.text = "%s   %s" % [
			objective_label.text,
			GameText.t(&"BLACK_WELL_WITHDRAWAL_STATUS") % [withdrawn_cards, low_organization_cards],
		]
	if battle != null and not battle.escort_unit_card_id.is_empty():
		var destination := snapshot.get_strategic_region(battle.escort_destination_region_id)
		var node_state := GameText.t(&"FOG_FOREST_NODE_ACTIVE") if destination != null and destination.supply_node_active else GameText.t(&"FOG_FOREST_NODE_INACTIVE")
		objective_label.text = "%s   %s" % [objective_label.text, node_state]
	objective_label.tooltip_text = objective_label.text


func refresh_locale() -> void:
	if title_label != null:
		title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if objective_label != null:
		objective_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


static func objective_status_marker_key(status: ObjectiveState.Status) -> StringName:
	match status:
		ObjectiveState.Status.COMPLETED:
			return &"OBJECTIVE_STATUS_COMPLETE"
		ObjectiveState.Status.FAILED:
			return &"OBJECTIVE_STATUS_FAILED"
	return &"OBJECTIVE_STATUS_ACTIVE"
