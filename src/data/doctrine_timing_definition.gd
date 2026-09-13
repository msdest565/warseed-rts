class_name DoctrineTimingDefinition
extends Resource

enum Kind { DEPLOYED_CARD_ORDER, FIXED_PREPARATION, IMMEDIATE }

@export var kind: Kind = Kind.DEPLOYED_CARD_ORDER
@export var base_delay_ticks: int = 0
@export var interval_ticks: int = 20
