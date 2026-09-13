class_name FactionSnapshot
extends RefCounted

var faction_id: int
var controller_id: int
var ore: int
var defeated: bool
var victorious: bool
var supply: int
var supply_capacity: int
var population: int
var population_capacity: int
var air_recon_cooldown_until_tick: int
var fortify_cooldown_until_tick: int
var reinforcement_cooldown_until_tick: int
var support_cooldown_until_by_kind: Dictionary
var opened_engineering_route_ids: Array[StringName] = []


func _init(faction: FactionState, include_private_economy: bool = true) -> void:
	faction_id = faction.faction_id
	controller_id = faction.controller_id
	ore = faction.ore if include_private_economy else 0
	defeated = faction.defeated
	victorious = faction.victorious
	supply = faction.supply if include_private_economy else 0
	supply_capacity = faction.supply_capacity if include_private_economy else 0
	population = faction.population if include_private_economy else 0
	population_capacity = faction.population_capacity if include_private_economy else 0
	air_recon_cooldown_until_tick = faction.air_recon_cooldown_until_tick if include_private_economy else 0
	fortify_cooldown_until_tick = faction.fortify_cooldown_until_tick if include_private_economy else 0
	reinforcement_cooldown_until_tick = faction.reinforcement_cooldown_until_tick if include_private_economy else 0
	support_cooldown_until_by_kind = faction.support_cooldown_until_by_kind.duplicate() if include_private_economy else {}
	if include_private_economy:
		opened_engineering_route_ids.assign(faction.opened_engineering_route_ids)
