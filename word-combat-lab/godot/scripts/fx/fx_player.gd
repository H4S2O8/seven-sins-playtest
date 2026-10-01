extends Node
# 特效播放器：战斗里所有“打击感”都从这里走。
#   · 参数（震屏、顿帧、大字、飞分、桌宠台词……）在 data/fx.json，改数字不用动代码；
#   · 素材（粒子、闪光、音效）放进 res://assets/ 对应位置就会自动替换代码做的占位效果；
#   · 接口说明见 docs/素材与特效接口.md。
# 用法：fx.play("kill", {"uid": 12, "who": "mine", "score": 12, "name": "稻草人甲"})

const K = preload("res://scripts/ui/kit.gd")
const Sfx = preload("res://scripts/ui/sfx.gd")
const Pet = preload("res://scripts/ui/pet.gd")

static var cfg: Dictionary = {}

var host: Control            # 战斗界面（提供 _screen_of / table）
var layer: Control           # 2D 特效层
var table: Node3D            # 3D 牌桌（2D 模式为 null）
var score_label: Control     # 分数飞去的位置
var speed := 1.0
var _chain_n := 0
var _chain_t := -10

static func load_cfg() -> Dictionary:
	if cfg.is_empty():
		var f := FileAccess.open("res://data/fx.json", FileAccess.READ)
		if f != null:
			var p = JSON.parse_string(f.get_as_text())
			if p is Dictionary:
				cfg = p
	return cfg

func setup(h: Control, fx_layer: Control, t: Node3D, score: Control) -> void:
	host = h
	layer = fx_layer
	table = t
	score_label = score
	load_cfg()

func reset_round() -> void:
	_chain_n = 0
	_chain_t = -10

# 合并出某个事件的最终参数（按 ctx.who 套用 variants）
func event_cfg(name: String, ctx: Dictionary = {}) -> Dictionary:
	var ev: Dictionary = load_cfg().get("events", {}).get(name, {})
	if ev.is_empty():
		return {}
	var out := ev.duplicate(true)
	var who: String = str(ctx.get("who", ""))
	if ev.has("variants") and ev.variants.has(who):
		for k in ev.variants[who]:
			out[k] = ev.variants[who][k]
	out.erase("variants")
	return out

func _fmt(t: String, ctx: Dictionary) -> String:
	for k in ctx:
		t = t.replace("{%s}" % k, str(ctx[k]))
	return t

# 自动补全位置：屏幕坐标 screen、牌桌世界坐标 world
func _fill_pos(ctx: Dictionary) -> Dictionary:
	var c := ctx.duplicate()
	if c.has("uid"):
		if not c.has("screen") and host != null and host.has_method("_screen_of"):
			c["screen"] = host._screen_of(int(c.uid))
		if not c.has("world") and table != null and table.minions.has(int(c.uid)):
			c["world"] = (table.minions[int(c.uid)] as Node3D).global_position + Vector3(0, 0.15, 0)
	return c

# ------------------------------------------------------------ 主入口
func play(name: String, ctx: Dictionary = {}) -> void:
	var c := event_cfg(name, ctx)
	if c.is_empty():
		return
	var x := _fill_pos(ctx)
	var amount := float(x.get("amount", 0))
	var n := int(x.get("n", 0))
	if c.has("sound"):
		Sfx.play(str(c.sound))
	if float(c.get("hitstop", 0.0)) > 0.0:
		_hitstop(float(c.hitstop))
	if c.has("shake") and table != null and table.has_method("shake"):
		var amp: float = float(c.shake[0]) + float(c.get("shake_per_amount", 0.0)) * minf(amount, float(c.get("amount_cap", 25))) + float(c.get("shake_per_n", 0.0)) * n
		if amp > 0.0:
			table.shake(amp, float(c.shake[1]))
	if c.has("big_text"):
		big_text(_fmt(str(c.big_text), x), Color(str(c.get("color", "#e0b85c"))), int(c.get("big_size", 60)) + int(c.get("size_per_n", 0)) * mini(n, 6))
	if bool(c.get("fly", false)) and x.has("screen") and score_label != null:
		_fly(_fmt(str(c.get("fly_text", "+{score}")), x), Color(str(c.get("color", "#e0b85c"))), x.screen, str(x.get("who", "mine")) == "mine")
	if c.has("asset"):
		_spawn(str(c.asset), x, float(c.get("lifetime", 1.5)))
	if c.has("pet"):
		var lines: Array = c.pet
		if not lines.is_empty():
			Pet.chat(_fmt(str(lines[randi() % lines.size()]), x), str(c.get("pet_mood", "talk")), float(c.get("pet_dur", 3.5)))

# 连锁：短时间里接连触发（监听、关键词）就累加层数
func trigger(t: int, ctx: Dictionary = {}) -> void:
	play("trigger", ctx)
	var c := event_cfg("chain")
	if c.is_empty():
		return
	if t - _chain_t <= int(c.get("window", 1)):
		_chain_n += 1
	else:
		_chain_n = 1
	_chain_t = t
	if _chain_n >= int(c.get("min", 2)):
		var x := ctx.duplicate()
		x["n"] = _chain_n
		play("chain", x)

# 伤害：够大就走 big_hit，否则 hit
func hit(amount: int, ctx: Dictionary = {}) -> void:
	var x := ctx.duplicate()
	x["amount"] = amount
	var big := event_cfg("big_hit")
	if not big.is_empty() and amount >= int(big.get("min_amount", 10)):
		play("big_hit", x)
	else:
		play("hit", x)

# ------------------------------------------------------------ 默认（代码做的）效果
func _hitstop(dur: float) -> void:
	Engine.time_scale = 0.06
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = 1.0

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func big_text(text: String, col: Color, size: int = 72) -> void:
	if layer == null:
		return
	var l := K.label(text, size, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)
	var vp := layer.get_viewport_rect().size
	l.size = Vector2(vp.x, size * 1.6)
	l.position = Vector2(0, vp.y * 0.22)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(2.2, 2.2)
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.22 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.5 / speed)
	t.tween_property(l, "modulate:a", 0.0, 0.3 / speed)
	t.tween_callback(l.queue_free)

func _fly(text: String, col: Color, from: Vector2, mine: bool) -> void:
	var to := score_label.get_global_rect().get_center() + Vector2(-60 if mine else 60, 0)
	var f := K.label(text, 40, col)
	f.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	f.add_theme_constant_override("outline_size", 10)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(f)
	f.position = from
	var t := f.create_tween()
	t.tween_property(f, "position", to, 0.55 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		f.queue_free()
		if is_instance_valid(score_label):
			score_label.pivot_offset = score_label.size * 0.5
			var p := score_label.create_tween()
			p.tween_property(score_label, "scale", Vector2(1.35, 1.35), 0.08)
			p.tween_property(score_label, "scale", Vector2.ONE, 0.2))

# 素材：res://assets/<asset>。Node3D 放到牌桌上（world 坐标），2D 节点放到特效层（screen 坐标）。
# 场景根节点如果有 play(ctx) 方法会被调用；lifetime 秒后自动删除。
func _spawn(asset: String, ctx: Dictionary, lifetime: float) -> void:
	var path := "res://assets/" + asset
	if asset == "" or not ResourceLoader.exists(path):
		return
	var res = load(path)
	if not (res is PackedScene):
		return
	var n: Node = res.instantiate()
	if n is Node3D:
		if table == null or not ctx.has("world"):
			n.queue_free()
			return
		table.add_child(n)
		(n as Node3D).global_position = ctx.world
	elif n is CanvasItem:
		layer.add_child(n)
		if n is Control:
			(n as Control).position = ctx.get("screen", Vector2.ZERO)
		elif n is Node2D:
			(n as Node2D).position = ctx.get("screen", Vector2.ZERO)
	else:
		add_child(n)
	if n.has_method("play"):
		n.play(ctx)
	get_tree().create_timer(lifetime, true, false, true).timeout.connect(func():
		if is_instance_valid(n):
			n.queue_free())
