class_name DoctrineActionDefinition
extends Resource

enum Kind { STAGED_DEPARTURE, REQUIRE_OBSERVED_CONTACT, CAUTIOUS_RECON, NARROW_FRONTAGE }

@export var kind: Kind = Kind.STAGED_DEPARTURE
@export var task_radius: float = 0.0
@export var formation_spacing: float = 0.0
@export var staging_distance: float = 0.0
@export var staging_fraction: float = 0.5
