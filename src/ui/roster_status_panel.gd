class_name RosterStatusPanel
extends VBoxContainer

var host: SimulationHost
var message: Label
var retry_button: Button


func configure(new_host: SimulationHost) -> void:
	host = new_host
	if message == null:
		message = Label.new()
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
		message.add_theme_font_size_override("font_size", 12)
		add_child(message)
		retry_button = Button.new()
		retry_button.custom_minimum_size.y = 32
		retry_button.pressed.connect(func() -> void: host.retry_campaign_save())
		add_child(retry_button)
	if not host.campaign_persistence_changed.is_connected(refresh):
		host.campaign_persistence_changed.connect(refresh)
	refresh()


func refresh() -> void:
	visible = host != null and host.has_campaign_error()
	if not visible:
		return
	message.text = GameText.t(host.campaign_error_key)
	message.tooltip_text = host.campaign_error_detail
	retry_button.text = GameText.t(&"ROSTER_RETRY_SAVE")
	retry_button.visible = host.campaign_error_key == &"ROSTER_SAVE_FAILED"
