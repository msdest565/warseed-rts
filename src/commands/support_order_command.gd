class_name SupportOrderCommand
extends GameCommand

enum SupportKind {
	AIR_RECON,
	EMERGENCY_FORTIFY,
	FIELD_REINFORCEMENT,
	ENGINEERING_ROUTE,
	FIRE_SUPPORT,
	RAPID_MOBILITY,
	FRONTLINE_LOGISTICS,
}

var support_kind: SupportKind
var primary_region_id: StringName
var secondary_region_id: StringName
var unit_card_id: StringName


func _init(
	new_command_id: int,
	new_issuer_id: int,
	new_issuer_kind: IssuerKind,
	new_issued_tick: int,
	new_support_kind: SupportKind,
	new_primary_region_id: StringName = &"",
	new_secondary_region_id: StringName = &"",
	new_unit_card_id: StringName = &""
) -> void:
	super(new_command_id, new_issuer_id, new_issuer_kind, new_issued_tick, 0)
	support_kind = new_support_kind
	primary_region_id = new_primary_region_id
	secondary_region_id = new_secondary_region_id
	unit_card_id = new_unit_card_id
