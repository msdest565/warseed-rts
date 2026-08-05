class_name EnemyDifficultyProfile
extends Resource

enum Difficulty {
	EASY,
	NORMAL,
	HARD,
	EXPERT,
}

@export var difficulty: Difficulty = Difficulty.NORMAL
@export_range(1, 100) var strategic_decision_interval_ticks: int = 35
@export_range(1, 30) var tactical_decision_interval_ticks: int = 5
@export_range(0, 100) var reaction_delay_ticks: int = 12
@export_range(1, 2000) var memory_half_life_ticks: int = 240
@export_range(0.0, 0.5) var target_score_noise: float = 0.06
@export_range(1, 4) var max_combat_tasks: int = 1
@export_range(1, 4) var production_planning_depth: int = 2
@export_range(0.0, 2.0) var route_threat_weight: float = 0.65
@export_range(0.0, 1.0) var focus_fire_quality: float = 0.65
@export_range(0.05, 0.95) var retreat_enter_ratio: float = 0.42
@export_range(0.05, 1.0) var retreat_exit_ratio: float = 0.68
@export_range(0.5, 3.0) var required_attack_power_ratio: float = 1.05
@export_range(128.0, 1600.0) var base_defense_radius: float = 640.0
@export_range(128.0, 2400.0) var chase_distance: float = 960.0
@export_range(10, 1200) var chase_duration_ticks: int = 260
@export_range(0.0, 1.0) var target_switch_margin: float = 0.12
@export_range(0.0, 2.0) var composition_reaction_weight: float = 0.65
@export_range(0, 600) var opening_delay_ticks: int = 120
@export_range(1, 4) var target_harvester_count: int = 2
@export_range(2, 12) var raid_force_size: int = 4
@export_range(2, 16) var combat_reserve_size: int = 6


func difficulty_name() -> String:
	return Difficulty.keys()[difficulty]


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if strategic_decision_interval_ticks < tactical_decision_interval_ticks:
		errors.append("strategic decision interval must not be faster than the tactical interval")
	if retreat_exit_ratio <= retreat_enter_ratio:
		errors.append("retreat exit ratio must be greater than the entry ratio")
	if chase_duration_ticks < tactical_decision_interval_ticks:
		errors.append("chase duration must cover at least one tactical decision interval")
	if memory_half_life_ticks <= reaction_delay_ticks:
		errors.append("contact memory must outlive the configured reaction delay")
	if combat_reserve_size < raid_force_size:
		errors.append("combat reserve must be at least as large as the raid force")
	return errors
