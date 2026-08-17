extends Node
## Procedural sound (autoload "Sfx").
##
## Every effect is synthesised into an AudioStreamWAV at startup rather than
## shipped as a file. A solid-state cabinet's whole voice is decaying tones and
## bursts of noise, which is about twenty lines of arithmetic -- and it keeps
## the repo free of binary assets that cannot be diffed or tuned in a PR.

const SAMPLE_RATE := 22050
const VOICES := 8  ## a bumper nest can easily want six at once

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _bank := {}


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -9.0
		add_child(p)
		_players.append(p)

	#                        from    to    secs  noise decay
	_bank["bumper"] = _tone(660.0, 220.0, 0.10, 0.10, 2.5)
	_bank["sling"] = _tone(880.0, 300.0, 0.07, 0.25, 3.0)
	_bank["target"] = _tone(1200.0, 900.0, 0.05, 0.05, 3.0)
	_bank["drop"] = _tone(500.0, 140.0, 0.09, 0.35, 2.0)
	_bank["bank"] = _tone(300.0, 1400.0, 0.35, 0.02, 1.2)
	_bank["spinner"] = _tone(1600.0, 400.0, 0.18, 0.45, 1.5)
	_bank["lane"] = _tone(1400.0, 1800.0, 0.06, 0.0, 2.0)
	_bank["plunge"] = _tone(180.0, 900.0, 0.16, 0.15, 1.0)
	_bank["drain"] = _tone(320.0, 60.0, 0.45, 0.05, 1.4)
	_bank["nudge"] = _tone(120.0, 80.0, 0.08, 0.6, 2.5)
	_bank["tilt"] = _tone(90.0, 90.0, 0.70, 0.8, 0.6)
	_bank["buy"] = _tone(700.0, 1400.0, 0.12, 0.0, 1.5)
	_bank["win"] = _tone(400.0, 1600.0, 0.60, 0.0, 0.8)
	_bank["lose"] = _tone(500.0, 70.0, 0.90, 0.1, 1.0)


func play(id: String) -> void:
	var stream: AudioStreamWAV = _bank.get(id)
	if stream == null:
		return
	# Round-robin rather than "find a free player": a stolen voice is far less
	# noticeable than a dropped one when the ball is in the bumpers.
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.play()


func _tone(from_hz: float, to_hz: float, secs: float, noise: float, decay: float) -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * secs)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		phase += TAU * lerpf(from_hz, to_hz, t) / float(SAMPLE_RATE)
		var env := pow(1.0 - t, decay)
		var sample := sin(phase) * (1.0 - noise) + randf_range(-1.0, 1.0) * noise
		data.encode_s16(i * 2, int(clampf(sample * env, -1.0, 1.0) * 32000.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
