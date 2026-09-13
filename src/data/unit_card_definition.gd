class_name UnitCardDefinition
extends Resource

@export var definition_id: StringName
@export var display_name_key: StringName
@export var role_key: StringName
@export var commander_definition_id: StringName
@export var command_cost: int = 1
@export var authorized_strength: int = 1
@export var unit_definition_id: StringName
@export var composition: Array[UnitCardCompositionEntry] = []
@export var tactical_ability: TacticalAbilityDefinition
@export var tactical_weapon_override: TacticalWeaponDefinition
@export var enforce_organization_rules: bool = false
@export var supply_cost: int = 0
@export var deployment_ticks: int = 0
@export var starts_in_reserve: bool = false
