class_name UIFeedbackAudio
extends RefCounted

const MIX_RATE := 22050


static func create_tone(
	frequencies: PackedFloat32Array,
	segment_seconds: float = 0.065,
	volume: float = 0.18
) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	if frequencies.is_empty() or segment_seconds <= 0.0:
		stream.data = PackedByteArray()
		return stream
	var samples_per_segment := maxi(1, roundi(segment_seconds * MIX_RATE))
	var data := PackedByteArray()
	data.resize(samples_per_segment * frequencies.size() * 2)
	for segment_index in range(frequencies.size()):
		var frequency := frequencies[segment_index]
		for sample_index in range(samples_per_segment):
			var phase := float(sample_index) / float(MIX_RATE)
			var progress := float(sample_index) / float(samples_per_segment)
			var envelope := minf(1.0, progress * 12.0) * minf(1.0, (1.0 - progress) * 10.0)
			var sample := clampi(roundi(sin(TAU * frequency * phase) * volume * envelope * 32767.0), -32768, 32767)
			var byte_offset := (segment_index * samples_per_segment + sample_index) * 2
			data.encode_s16(byte_offset, sample)
	stream.data = data
	return stream


static func create_combat_cue(
	frequencies: PackedFloat32Array,
	segment_seconds: float,
	volume: float,
	noise_mix: float = 0.0
) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	if frequencies.is_empty() or segment_seconds <= 0.0:
		stream.data = PackedByteArray()
		return stream
	var samples_per_segment := maxi(1, roundi(segment_seconds * MIX_RATE))
	var data := PackedByteArray()
	data.resize(samples_per_segment * frequencies.size() * 2)
	var noise_state: int = 0x13579B
	for segment_index in range(frequencies.size()):
		var frequency := frequencies[segment_index]
		for sample_index in range(samples_per_segment):
			var phase := float(sample_index) / float(MIX_RATE)
			var progress := float(sample_index) / float(samples_per_segment)
			var envelope := minf(1.0, progress * 18.0) * pow(maxf(0.0, 1.0 - progress), 1.7)
			noise_state = int((noise_state * 1103515245 + 12345) & 0x7fffffff)
			var noise := (float(noise_state % 65536) / 32767.5 - 1.0) * noise_mix
			var fundamental := sin(TAU * frequency * phase)
			var harmonic := sin(TAU * frequency * 2.03 * phase) * 0.28
			var sample_value := (fundamental * (1.0 - noise_mix) + harmonic + noise) * volume * envelope
			var sample := clampi(roundi(sample_value * 32767.0), -32768, 32767)
			var byte_offset := (segment_index * samples_per_segment + sample_index) * 2
			data.encode_s16(byte_offset, sample)
	stream.data = data
	return stream
