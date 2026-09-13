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
var commanders: Array[CommanderSnapshot]
var unit_cards: Array[UnitCardSnapshot]
var strategic_regions: Array[StrategicRegionSnapshot]
var intel_reports: Array[IntelReportSnapshot]
var enemy_reactions: Array[EnemyReactionSnapshot]
var objectives: Array[ObjectiveSnapshot]
var outcome: BattleOutcome
var staff_plan_decisions: Array[StaffPlanDecisionSnapshot] = []
var commander_task_graphs: Array[CommanderTaskGraphSnapshot] = []


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
	new_mission: MissionSnapshot = null,
	new_commanders: Array[CommanderSnapshot] = [],
	new_unit_cards: Array[UnitCardSnapshot] = [],
	new_strategic_regions: Array[StrategicRegionSnapshot] = [],
	new_intel_reports: Array[IntelReportSnapshot] = [],
	new_enemy_reactions: Array[EnemyReactionSnapshot] = [],
	new_objectives: Array[ObjectiveSnapshot] = [],
	new_outcome: BattleOutcome = null,
	new_staff_plan_decisions: Array[StaffPlanDecisionSnapshot] = [],
	new_commander_task_graphs: Array[CommanderTaskGraphSnapshot] = []
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
	commanders = new_commanders
	unit_cards = new_unit_cards
	strategic_regions = new_strategic_regions
	intel_reports = new_intel_reports
	enemy_reactions = new_enemy_reactions
	objectives = new_objectives
	outcome = new_outcome.duplicate_value() if new_outcome != null else BattleOutcome.new()
	for decision in new_staff_plan_decisions:
		staff_plan_decisions.append(decision.duplicate_value())
	for graph in new_commander_task_graphs:
		commander_task_graphs.append(graph.duplicate_value())


func get_objective(objective_id: StringName) -> ObjectiveSnapshot:
	for objective in objectives:
		if objective.objective_id == objective_id:
			return objective
	return null


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


func get_commander(definition_id: StringName) -> CommanderSnapshot:
	for commander in commanders:
		if commander.definition_id == definition_id:
			return commander
	return null


func get_unit_card(definition_id: StringName) -> UnitCardSnapshot:
	for unit_card in unit_cards:
		if unit_card.definition_id == definition_id:
			return unit_card
	return null


func get_strategic_region(region_id: StringName) -> StrategicRegionSnapshot:
	for region in strategic_regions:
		if region.region_id == region_id:
			return region
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
