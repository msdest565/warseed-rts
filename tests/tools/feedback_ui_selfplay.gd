extends SceneTree

const VIEWPORTS := [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1600),
	Vector2i(640, 800),
	Vector2i(480, 800),
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var dialog := PlaytestFeedbackDialog.new()
	root.add_child(dialog)
	await process_frame
	await process_frame
	dialog.open_feedback({
		"last_scenario_id": "grey_ridge",
		"last_result": "victory",
		"battle_count": 1,
	})
	for locale in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		dialog.refresh_locale()
		for viewport_size in VIEWPORTS:
			root.content_scale_size = viewport_size
			await process_frame
			await process_frame
			dialog._apply_responsive_layout()
			_check_layout(dialog, Vector2i(root.get_visible_rect().size), locale, failures)
	dialog.overall_rating.select(4)
	dialog.priority_area.select(1)
	dialog.biggest_problem.text = ""
	dialog._on_submit_pressed()
	if dialog.status_label.text != GameText.t(&"FEEDBACK_VALIDATION_ERROR"):
		failures.append("required-field validation should be visible without closing the feedback form")
	if failures.is_empty():
		print("WARSEED feedback UI selfplay passed: bilingual form, required fields, and five responsive viewports")
		quit(0)
		return
	for failure in failures:
		push_error("FEEDBACK UI SELFPLAY FAILED: %s" % failure)
	quit(1)


func _check_layout(dialog: PlaytestFeedbackDialog, viewport_size: Vector2i, locale: String, failures: Array[String]) -> void:
	var panel_rect := dialog.panel.get_global_rect()
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
	if not viewport_rect.encloses(panel_rect):
		failures.append("%s %s panel should remain inside viewport: %s" % [locale, viewport_size, panel_rect])
	if panel_rect.size.x < 440.0 or panel_rect.size.y < 680.0:
		failures.append("%s %s panel should retain a usable responsive size" % [locale, viewport_size])
	for control in [
		dialog.overall_rating,
		dialog.objective_clarity,
		dialog.controls_clarity,
		dialog.agent_usefulness,
		dialog.priority_area,
		dialog.submit_button,
		dialog.retry_button,
		dialog.close_button,
	]:
		if not control.is_visible_in_tree() or control.size.x < 80.0 or control.size.y < 30.0:
			failures.append("%s %s control %s should remain visible and actionable" % [locale, viewport_size, control.name])
	var title := dialog.panel.get_node("Margin/Layout/Title") as Label
	var intro := dialog.panel.get_node("Margin/Layout/Intro") as Label
	if title.text.is_empty() or intro.text.is_empty() or title.text == "FEEDBACK_TITLE":
		failures.append("%s feedback copy should resolve through localization" % locale)
