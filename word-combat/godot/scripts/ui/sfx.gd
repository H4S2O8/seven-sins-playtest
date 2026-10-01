extends Node
# 音效：全部由代码合成（没有音频素材）。Sfx.play("名字")；Sfx.muted 可静音。

static var instance: Node = null
static var muted := false
static var _bank := {}

var _players: Array = []
var _next := 0

func _ready() -> void:
	instance = self
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	_bank = {
		"click": _tone([[880.0, 0.05]], 0.35),
		"pick": _tone([[660.0, 0.06], [990.0, 0.09]], 0.4),
		"declare": _tone([[220.0, 0.12], [330.0, 0.08]], 0.5),
		"cast": _sweep(300.0, 700.0, 0.16, 0.35),
		"hit": _noise_thud(0.16),
		"heal": _tone([[660.0, 0.07], [830.0, 0.07], [990.0, 0.12]], 0.35),
		"block": _tone([[1400.0, 0.04], [1000.0, 0.09]], 0.4, true),
		"magic": _sweep(250.0, 950.0, 0.25, 0.3),
		"interrupt": _sweep(900.0, 200.0, 0.22, 0.4, true),
		"down": _sweep(320.0, 70.0, 0.5, 0.55),
		"win": _tone([[523.0, 0.12], [659.0, 0.12], [784.0, 0.12], [1046.0, 0.3]], 0.45),
		"lose": _tone([[392.0, 0.18], [330.0, 0.18], [262.0, 0.18], [196.0, 0.4]], 0.45),
	}

static func play(name: String) -> void:
	if muted or instance == null or not _bank.has(name):
		return
	var self_node: Node = instance
	var p: AudioStreamPlayer = self_node._players[self_node._next % self_node._players.size()]
	self_node._next += 1
	p.stream = _bank[name]
	p.play()

# ---------------------------------------------------------------- 合成
static func _to_wav(samples: PackedFloat32Array, rate: int = 22050) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

# 依次播放若干 [频率, 时长] 的音；square=true 用方波
static func _tone(notes: Array, vol: float, square: bool = false) -> AudioStreamWAV:
	var rate := 22050
	var out := PackedFloat32Array()
	for n in notes:
		var count := int(rate * float(n[1]))
		for i in count:
			var t := float(i) / float(rate)
			var env: float = 1.0 - float(i) / float(count)
			var ph := TAU * float(n[0]) * t
			var v := sin(ph)
			if square:
				v = 1.0 if v > 0.0 else -1.0
				v *= 0.6
			out.append(v * env * env * vol)
	return _to_wav(out, rate)

static func _sweep(f0: float, f1: float, dur: float, vol: float, square: bool = false) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * dur)
	var out := PackedFloat32Array()
	var phase := 0.0
	for i in count:
		var k := float(i) / float(count)
		var f := lerpf(f0, f1, k)
		phase += TAU * f / float(rate)
		var v := sin(phase)
		if square:
			v = (1.0 if v > 0.0 else -1.0) * 0.6
		out.append(v * (1.0 - k) * vol)
	return _to_wav(out, rate)

static func _noise_thud(dur: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * dur)
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in count:
		var k := float(i) / float(count)
		var n := rng.randf_range(-1.0, 1.0)
		lp += (n - lp) * 0.25
		var thump := sin(TAU * 110.0 * float(i) / float(rate))
		out.append((lp * 0.8 + thump * 0.6) * pow(1.0 - k, 2.0) * 0.6)
	return _to_wav(out, rate)
