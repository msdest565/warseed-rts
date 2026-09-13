class_name DoctrineCostDefinition
extends Resource

enum Kind { DELAYED_COMMITMENT, OBSERVATION_REQUIREMENT, SLOW_RECON, CONCENTRATED_FORCE }

@export var kind: Kind = Kind.DELAYED_COMMITMENT
@export var explanation_key: StringName
