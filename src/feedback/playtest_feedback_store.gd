class_name PlaytestFeedbackStore
extends RefCounted

const FORMAT_VERSION := 1
const FEEDBACK_URL_ARGUMENT := "--feedback-url"
const DEFAULT_ROOT := "user://feedback"
const MAX_TEXT_LENGTH := 4000


static func endpoint_from_arguments(arguments: PackedStringArray) -> String:
	for argument in arguments:
		var value := String(argument)
		if value.begins_with(FEEDBACK_URL_ARGUMENT + "="):
			return normalize_endpoint(value.trim_prefix(FEEDBACK_URL_ARGUMENT + "="))
	return ""


static func normalize_endpoint(value: String) -> String:
	var endpoint := value.strip_edges()
	if not endpoint.begins_with("http://") and not endpoint.begins_with("https://"):
		return ""
	if endpoint.contains("\n") or endpoint.contains("\r") or endpoint.contains(" "):
		return ""
	return endpoint.left(512)


static func create_submission(context: Dictionary, responses: Dictionary) -> Dictionary:
	var unix_time := int(Time.get_unix_time_from_system())
	var random_part := String.num_uint64(randi()).pad_zeros(10)
	var feedback_id := "%d-%s" % [unix_time, random_part]
	return {
		"format_version": FORMAT_VERSION,
		"feedback_id": feedback_id,
		"submitted_utc": Time.get_datetime_string_from_system(true),
		"build_id": String(context.get("build_id", "unknown")).left(128),
		"anonymous_session_id": ArmyRosterStore.normalize_playtest_session_id(String(context.get("anonymous_session_id", "anonymous"))),
		"scenario_id": String(context.get("scenario_id", "unknown")).left(64),
		"outcome": String(context.get("outcome", "unknown")).left(64),
		"battle_count": maxi(0, int(context.get("battle_count", 0))),
		"locale": String(context.get("locale", "unknown")).left(32),
		"viewport": _normalize_viewport(context.get("viewport", {})),
		"responses": normalize_responses(responses),
	}


static func normalize_responses(responses: Dictionary) -> Dictionary:
	return {
		"overall_rating": clampi(int(responses.get("overall_rating", 0)), 0, 5),
		"objective_clarity": clampi(int(responses.get("objective_clarity", 0)), 0, 5),
		"controls_clarity": clampi(int(responses.get("controls_clarity", 0)), 0, 5),
		"agent_usefulness": clampi(int(responses.get("agent_usefulness", 0)), 0, 5),
		"priority_area": _bounded_text(responses.get("priority_area", ""), 64),
		"best_part": _bounded_text(responses.get("best_part", ""), MAX_TEXT_LENGTH),
		"biggest_problem": _bounded_text(responses.get("biggest_problem", ""), MAX_TEXT_LENGTH),
		"suggestions": _bounded_text(responses.get("suggestions", ""), MAX_TEXT_LENGTH),
		"encountered_bug": bool(responses.get("encountered_bug", false)),
		"bug_details": _bounded_text(responses.get("bug_details", ""), MAX_TEXT_LENGTH),
	}


static func validate_submission(payload: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(payload.get("format_version", 0)) != FORMAT_VERSION:
		errors.append("unsupported format_version")
	if String(payload.get("feedback_id", "")).is_empty():
		errors.append("feedback_id is required")
	var responses := payload.get("responses", {}) as Dictionary
	if not int(responses.get("overall_rating", 0)) in range(1, 6):
		errors.append("overall_rating must be 1-5")
	if String(responses.get("priority_area", "")).is_empty():
		errors.append("priority_area is required")
	if String(responses.get("biggest_problem", "")).strip_edges().is_empty():
		errors.append("biggest_problem is required")
	return errors


static func feedback_root(session_id: String, root_override: String = "") -> String:
	if not root_override.is_empty():
		return root_override.trim_suffix("/")
	if session_id.is_empty():
		return DEFAULT_ROOT
	return "%s/%s/feedback" % [ArmyRosterStore.ISOLATED_PLAYTEST_ROOT, ArmyRosterStore.normalize_playtest_session_id(session_id)]


static func save_pending(payload: Dictionary, root_override: String = "") -> String:
	if not validate_submission(payload).is_empty():
		return ""
	var root := feedback_root(String(payload.get("anonymous_session_id", "")), root_override)
	var directory := "%s/pending" % root
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return ""
	var path := "%s/%s.json" % [directory, _safe_feedback_id(String(payload.get("feedback_id", "")))]
	return path if _write_json_atomic(path, payload) else ""


static func mark_sent(payload: Dictionary, root_override: String = "") -> bool:
	var root := feedback_root(String(payload.get("anonymous_session_id", "")), root_override)
	var directory := "%s/sent" % root
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return false
	var filename := "%s.json" % _safe_feedback_id(String(payload.get("feedback_id", "")))
	if not _write_json_atomic("%s/%s" % [directory, filename], payload):
		return false
	var pending_path := "%s/pending/%s" % [root, filename]
	if FileAccess.file_exists(pending_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))
	return true


static func load_pending(session_id: String, root_override: String = "") -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var directory_path := "%s/pending" % feedback_root(session_id, root_override)
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return records
	var filenames := directory.get_files()
	filenames.sort()
	for filename in filenames:
		if not filename.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [directory_path, filename]))
		if parsed is Dictionary and validate_submission(parsed as Dictionary).is_empty():
			records.append((parsed as Dictionary).duplicate(true))
	return records


static func _write_json_atomic(path: String, payload: Dictionary) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := absolute_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file = null
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)
	return DirAccess.rename_absolute(temporary_path, absolute_path) == OK


static func _normalize_viewport(value: Variant) -> Dictionary:
	var viewport := value as Dictionary if value is Dictionary else {}
	return {
		"width": clampi(int(viewport.get("width", 0)), 0, 16384),
		"height": clampi(int(viewport.get("height", 0)), 0, 16384),
	}


static func _bounded_text(value: Variant, limit: int) -> String:
	return String(value).strip_edges().left(limit)


static func _safe_feedback_id(value: String) -> String:
	var normalized := ""
	for character in value:
		if character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			normalized += character.to_lower()
	return normalized.left(96)
