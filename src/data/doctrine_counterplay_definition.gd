class_name DoctrineCounterplayDefinition
extends Resource

enum Kind { DEFEAT_IN_DETAIL, DENY_CONTACT, FORCE_RECON_EXIT, FLANK_CONCENTRATION }
enum ExitCondition { PLAYER_OVERRIDE_OR_TASK_END }

@export var kind: Kind = Kind.DEFEAT_IN_DETAIL
@export var exit_condition: ExitCondition = ExitCondition.PLAYER_OVERRIDE_OR_TASK_END
@export var explanation_key: StringName
