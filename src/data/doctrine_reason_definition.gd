class_name DoctrineReasonDefinition
extends Resource

enum Kind { LOCALIZED_TASK_REASON }

@export var kind: Kind = Kind.LOCALIZED_TASK_REASON
@export var waiting_reason_key: StringName
@export var description_key: StringName
