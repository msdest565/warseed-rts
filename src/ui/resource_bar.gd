class_name ResourceBar
extends PanelContainer

@onready var label: Label = $Label
var situation: BattlefieldSituationSnapshot


func update_snapshot(snapshot: WorldSnapshot) -> void:
	if snapshot == null or label == null:
		return
	var faction := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	if situation != null and situation.source_tick == snapshot.tick and faction != null and faction.supply_capacity > 0:
		_update_situation_text()
	elif faction != null and faction.supply_capacity > 0:
		label.text = GameText.t(&"RESOURCE_BATTLE") % [
			faction.supply, faction.supply_capacity,
			faction.population, faction.population_capacity,
		]
	else:
		label.text = GameText.t(&"RESOURCE_GOLD") % (faction.ore if faction != null else 0)


func refresh_locale() -> void:
	if label != null:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		if situation != null:
			_update_situation_text()


func update_situation(new_situation: BattlefieldSituationSnapshot) -> void:
	situation = new_situation
	if label != null and situation != null:
		_update_situation_text()


func _update_situation_text() -> void:
	var supply := situation.supply
	var recovery_sources := supply.get("recovery_sources", []) as Array
	var next_amount := 0
	var next_ticks := 0
	var next_source := GameText.t(&"SUPPLY_RECOVERY_NONE")
	if not recovery_sources.is_empty():
		var recovery := recovery_sources[0] as Dictionary
		next_amount = int(recovery.get("amount", 0))
		next_ticks = int(recovery.get("remaining_ticks", 0))
		var display_name_key := recovery.get("display_name_key", &"") as StringName
		next_source = GameText.t(display_name_key) if not display_name_key.is_empty() else GameText.t(&"SUPPLY_RECOVERY_BASE")
	label.text = GameText.t(&"RESOURCE_BATTLE_SITUATION") % [
		int(supply.get("available", 0)), int(supply.get("committed", 0)), int(supply.get("capacity", 0)),
		next_source, next_amount, ceili(float(next_ticks) * SimulationWorld.TICK_SECONDS),
		int(supply.get("population", 0)), int(supply.get("population_capacity", 0)),
	]
	var detail_lines := PackedStringArray([label.text])
	for commitment_variant in supply.get("commitments", []):
		var commitment := commitment_variant as Dictionary
		detail_lines.append(GameText.t(&"SUPPLY_COMMITMENT_DETAIL") % [
			String(commitment.get("subject_id", "")), int(commitment.get("supply", 0)),
			ceili(float(commitment.get("remaining_ticks", 0)) * SimulationWorld.TICK_SECONDS),
		])
	for recovery_variant in recovery_sources:
		var recovery := recovery_variant as Dictionary
		var display_name_key := recovery.get("display_name_key", &"") as StringName
		var source_name := GameText.t(display_name_key) if not display_name_key.is_empty() else GameText.t(&"SUPPLY_RECOVERY_BASE")
		detail_lines.append(GameText.t(&"SUPPLY_RECOVERY_DETAIL") % [
			source_name, int(recovery.get("amount", 0)),
			ceili(float(recovery.get("remaining_ticks", 0)) * SimulationWorld.TICK_SECONDS),
		])
	label.tooltip_text = "\n".join(detail_lines)
