class_name CommandFeedback
extends AudioStreamPlayer

enum Cue {
	NONE,
	ACCEPTED,
	REJECTED,
}

var last_cue: Cue = Cue.NONE
var play_count: int = 0
var audio_enabled: bool = true
var _accepted_stream: AudioStreamWAV
var _rejected_stream: AudioStreamWAV


func _ready() -> void:
	volume_db = -13.0
	_accepted_stream = UIFeedbackAudio.create_tone(PackedFloat32Array([520.0, 720.0]))
	_rejected_stream = UIFeedbackAudio.create_tone(PackedFloat32Array([330.0, 230.0]), 0.08, 0.2)


func play_result(result: CommandValidationResult) -> void:
	if result == null:
		return
	if _accepted_stream == null or _rejected_stream == null:
		_ready()
	last_cue = Cue.ACCEPTED if result.is_accepted() else Cue.REJECTED
	stream = _accepted_stream if result.is_accepted() else _rejected_stream
	if not audio_enabled:
		return
	play_count += 1
	if is_inside_tree():
		play()


func set_audio_enabled(enabled: bool) -> void:
	audio_enabled = enabled
	if not enabled:
		stop()
