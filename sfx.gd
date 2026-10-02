extends Node
## Autoload "Sfx": tiny procedurally generated sound effects (no audio files, no copyright issues).

const RATE = 22050
var _cache: Dictionary = {}
var _players: Array = []
var _next: int = 0


func _ready() -> void:
	for i in range(4):
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_cache["click"] = _seq([[660.0, 0.05]], 0.25)
	_cache["move"] = _seq([[330.0, 0.05], [392.0, 0.06]], 0.25)
	_cache["battle"] = _noise(0.25, 0.4)
	_cache["win"] = _seq([[523.0, 0.14], [659.0, 0.14], [784.0, 0.14], [1047.0, 0.35]], 0.35)
	_cache["lose"] = _seq([[392.0, 0.2], [330.0, 0.2], [262.0, 0.2], [196.0, 0.45]], 0.35)
	_cache["event"] = _seq([[440.0, 0.1], [554.0, 0.18]], 0.3)


func play(sound_name: String) -> void:
	if not bool(Game.settings.get("sound", true)):
		return
	if not _cache.has(sound_name) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _cache[sound_name]
	p.play()


## notes: [[frequency_hz, seconds], ...]
func _seq(notes: Array, vol: float) -> AudioStreamWAV:
	var samples: Array = []
	for n in notes:
		var count: int = int(RATE * float(n[1]))
		for i in range(count):
			var t: float = float(i) / RATE
			var env: float = 1.0 - float(i) / float(count)
			samples.append(sin(TAU * float(n[0]) * t) * env * vol)
	return _to_wav(samples)


func _noise(seconds: float, vol: float) -> AudioStreamWAV:
	var samples: Array = []
	var count: int = int(RATE * seconds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in range(count):
		var env: float = pow(1.0 - float(i) / float(count), 2.0)
		samples.append(rng.randf_range(-1.0, 1.0) * env * vol)
	return _to_wav(samples)


func _to_wav(samples: Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(float(samples[i]), -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
