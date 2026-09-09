extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dialog := PlaytestFeedbackDialog.new()
	root.add_child(dialog)
	await process_frame
	dialog.open_feedback({
		"last_scenario_id": "grey_ridge",
		"last_result": "victory",
		"battle_count": 1,
	})
	dialog.overall_rating.select(4)
	dialog.objective_clarity.select(4)
	dialog.controls_clarity.select(3)
	dialog.agent_usefulness.select(4)
	dialog.priority_area.select(2)
	dialog.best_part.text = "Authoritative card command flow"
	dialog.biggest_problem.text = "Map landmarks need clearer identities"
	dialog.suggestions.text = "Add stronger terrain landmarks"
	dialog._on_submit_pressed()
	var delivered := false
	for _attempt in range(200):
		await create_timer(0.05).timeout
		if dialog.status_label.text == GameText.t(&"FEEDBACK_SENT"):
			delivered = true
			break
	var session_id := ArmyRosterStore.active_playtest_session_id()
	var pending := PlaytestFeedbackStore.load_pending(session_id)
	if not delivered or not pending.is_empty():
		push_error(
			"FEEDBACK DELIVERY SELFPLAY: delivery failed endpoint=%s status=%s pending=%d" % [
				PlaytestFeedbackStore.endpoint_from_arguments(OS.get_cmdline_user_args()),
				dialog.status_label.text,
				pending.size(),
			]
		)
		_cleanup_session(session_id)
		quit(1)
		return
	print("WARSEED feedback delivery selfplay passed: local-first persistence and HTTP acknowledgement")
	_cleanup_session(session_id)
	quit(0)


func _cleanup_session(session_id: String) -> void:
	if session_id.is_empty():
		return
	var root_path := PlaytestFeedbackStore.feedback_root(session_id)
	for directory_name in ["pending", "sent"]:
		var directory_path := "%s/%s" % [root_path, directory_name]
		var directory := DirAccess.open(directory_path)
		if directory != null:
			for filename in directory.get_files():
				if filename.ends_with(".json"):
					DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [directory_path, filename]))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root_path))
