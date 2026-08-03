class_name FactionSnapshot
extends RefCounted

var faction_id: int
var controller_id: int
var ore: int
var defeated: bool
var victorious: bool


func _init(faction: FactionState, include_private_economy: bool = true) -> void:
	faction_id = faction.faction_id
	controller_id = faction.controller_id
	ore = faction.ore if include_private_economy else 0
	defeated = faction.defeated
	victorious = faction.victorious
