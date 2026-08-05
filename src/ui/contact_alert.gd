class_name ContactAlert
extends PanelContainer

const DISPLAY_SECONDS := 3.0

@onready var message_label: Label = $Message

var _remaining: float = 0.0
var _contact_definition_id: StringName = &""
var _is_building: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		visible = false


func show_contact(definition_id: StringName, is_building: bool = false) -> void:
	_contact_definition_id = definition_id
	_is_building = is_building
	_remaining = DISPLAY_SECONDS
	refresh_locale()
	visible = true


func refresh_locale() -> void:
	if message_label == null or _contact_definition_id.is_empty():
		return
	var contact_name := GameText.building_name(_contact_definition_id) if _is_building else GameText.unit_name(_contact_definition_id)
	message_label.text = GameText.t(&"CONTACT_ALERT") % contact_name
