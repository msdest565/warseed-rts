class_name ResourceBar
extends PanelContainer

@onready var label: Label = $Label


func update_snapshot(snapshot: WorldSnapshot) -> void:
	if snapshot == null or label == null:
		return
	var faction := snapshot.get_faction(SimulationWorld.LOCAL_PLAYER_ID)
	label.text = GameText.t(&"RESOURCE_GOLD") % (faction.ore if faction != null else 0)


func refresh_locale() -> void:
	if label != null:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
