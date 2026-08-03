class_name WorldSnapshot
extends RefCounted

var tick: int
var units: Array[UnitSnapshot]
var formations: Array[FormationSnapshot]
var projectiles: Array[ProjectileSnapshot]
var factions: Array[FactionSnapshot]
var buildings: Array[BuildingSnapshot]
var ore_fields: Array[OreFieldSnapshot]
var metrics: SimulationMetricsSnapshot
var observer_faction_id: int = 0
var knowledge: FactionKnowledgeSnapshot
var is_true_state: bool = false
var tasks: Array[TaskSnapshot]
var mission: MissionSnapshot


func _init(
	new_tick: int,
	new_units: Array[UnitSnapshot],
	new_formations: Array[FormationSnapshot] = [],
	new_projectiles: Array[ProjectileSnapshot] = [],
	new_metrics: SimulationMetricsSnapshot = null,
	new_factions: Array[FactionSnapshot] = [],
	new_buildings: Array[BuildingSnapshot] = [],
	new_ore_fields: Array[OreFieldSnapshot] = [],
	new_observer_faction_id: int = 0,
	new_knowledge: FactionKnowledgeSnapshot = null,
	new_is_true_state: bool = false,
	new_tasks: Array[TaskSnapshot] = [],
	new_mission: MissionSnapshot = null
) -> void:
	tick = new_tick
	units = new_units
	formations = new_formations
	projectiles = new_projectiles
	metrics = new_metrics
	factions = new_factions
	buildings = new_buildings
	ore_fields = new_ore_fields
	observer_faction_id = new_observer_faction_id
	knowledge = new_knowledge
	is_true_state = new_is_true_state
	tasks = new_tasks
	mission = new_mission


func get_task(task_id: int) -> TaskSnapshot:
	for task in tasks:
		if task.task_id == task_id:
			return task
	return null


func get_unit(entity_id: int) -> UnitSnapshot:
	for unit in units:
		if unit.entity_id == entity_id:
			return unit
	return null


func get_projectile(projectile_id: int) -> ProjectileSnapshot:
	for projectile in projectiles:
		if projectile.projectile_id == projectile_id:
			return projectile
	return null


func get_formation(formation_id: int) -> FormationSnapshot:
	for formation in formations:
		if formation.formation_id == formation_id:
			return formation
	return null


func get_faction(faction_id: int) -> FactionSnapshot:
	for faction in factions:
		if faction.faction_id == faction_id:
			return faction
	return null


func get_building(entity_id: int) -> BuildingSnapshot:
	for building in buildings:
		if building.entity_id == entity_id:
			return building
	return null


func get_ore_field(entity_id: int) -> OreFieldSnapshot:
	for ore_field in ore_fields:
		if ore_field.entity_id == entity_id:
			return ore_field
	return null
