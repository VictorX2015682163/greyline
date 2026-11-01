class_name RaidAudio
extends Node

var sounds: Dictionary = {}
var voices: Dictionary = {}

func _ready() -> void:
	for key in ["shot", "heavy", "sniper", "hit", "loot", "reload", "hurt", "extract", "footstep"]:
		sounds[key] = synth(key)
		var voice:=AudioStreamPlayer.new()
		voice.max_polyphony=6
		voice.stream=sounds[key]
		add_child(voice)
		voices[key]=voice

func play_sound(key: String, volume: float = -13.0) -> void:
	if DisplayServer.get_name()=="headless": return
	var voice: AudioStreamPlayer=voices.get(key,voices.shot)
	voice.volume_db = volume
	voice.pitch_scale = randf_range(0.93, 1.07)
	voice.play()

func _exit_tree() -> void:
	for voice in voices.values():
		voice.stop()
		voice.stream=null
	voices.clear()
	sounds.clear()

func synth(key: String) -> AudioStreamWAV:
	var rate := 22050
	var duration := 0.16
	if key in ["sniper", "extract"]:
		duration = 0.4
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var filtered := 0.0
	for i in range(count):
		var t := float(i) / rate
		var envelope := exp(-t * 32.0)
		var sample := 0.0
		filtered = lerpf(filtered, randf_range(-1.0, 1.0), 0.55)
		match key:
			"shot", "heavy", "sniper":
				var decay := 18.0 if key == "sniper" else 32.0
				sample = (filtered * 0.65 + sin(t * (420.0 - 500.0 * t)) * 0.35) * exp(-t * decay)
			"loot", "extract":
				sample = sin(TAU * (880.0 if t < 0.08 else 1320.0) * t) * exp(-t * 13.0) * 0.22
			"hit": sample = sin(TAU * 1700.0 * t) * envelope * 0.25
			"footstep": sample = (filtered*0.24+sin(TAU*85*t)*0.6)*exp(-t*40)
			"reload": sample = filtered * envelope * 0.45
			"hurt": sample = (filtered * 0.4 + sin(t * 150.0) * 0.5) * envelope
		var value := int(clampf(sample, -1, 1) * 30000)
		bytes.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
