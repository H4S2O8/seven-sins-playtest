extends Control
# 桌宠“小词”：一直待在屏幕上的小家伙。新手引导用它的气泡说话；平时拼技能、准备出招时它会感叹一句。
# 形象是代码画的占位：把 res://assets/pet/pet.png 放进去就会改用图片（动画仍由代码驱动）。

const K = preload("res://scripts/ui/kit.gd")
const Settings = preload("res://scripts/ui/settings.gd")

static var inst: Control = null

const BODY := Vector2(104, 104)
const BUBBLE_W := 460.0

var body: Control
var tex: TextureRect
var mood_tex := {}           # 心情 → 图片（res://assets/pet/pet_<心情>.png）
var base_tex: Texture2D
var bubble: PanelContainer
var tail: Control
var title_l: Label
var text_l: Label
var btn_row: HBoxContainer
var home := Vector2(-1, -1)
var pos_target := Vector2.ZERO
var mood := "normal"         # normal / talk / excited / sad
var tut_mode := false
var _t := 0.0
var _blink := 3.0
var _hop := 0.0
var _hide_at := -1.0
var _last_line := ""
var _drag := false
var _drag_off := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _anchor := Rect2()
var _anchor_hint := ""

func _ready() -> void:
	inst = self
	Settings.load_all()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	body = Control.new()
	body.size = BODY
	body.custom_minimum_size = BODY
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	body.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	body.tooltip_text = "小词：拖动可以挪位置，点一下再说一遍"
	body.draw.connect(_draw_body)
	body.gui_input.connect(_on_body_input)
	add_child(body)
	for md in ["normal", "talk", "excited", "sad"]:
		var mp := "res://assets/pet/pet_%s.png" % md
		if ResourceLoader.exists(mp):
			mood_tex[md] = load(mp)
	if ResourceLoader.exists("res://assets/pet/pet.png") or not mood_tex.is_empty():
		tex = TextureRect.new()
		tex.texture = load("res://assets/pet/pet.png") if ResourceLoader.exists("res://assets/pet/pet.png") else mood_tex.values()[0]
		base_tex = tex.texture
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.size = BODY
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(tex)
	bubble = K.panel(Color("fbf3dc"), Color("c9a54a"), 16, 3, 12)
	bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := K.vbox(6)
	bubble.add_child(v)
	title_l = K.label("", 20, Color("8a5a12"))
	v.add_child(title_l)
	text_l = K.wrap_label("", 19, Color("2a2216"))
	text_l.custom_minimum_size.x = BUBBLE_W - 28
	v.add_child(text_l)
	btn_row = K.hbox(8)
	v.add_child(btn_row)
	bubble.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if text_l.visible_ratio < 1.0:
				text_l.visible_ratio = 1.0
			elif not tut_mode:
				_hide_bubble())
	add_child(bubble)
	tail = Control.new()
	tail.size = Vector2(28, 18)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.draw.connect(func():
		tail.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(28, 0), Vector2(6, 18)]), Color("fbf3dc"))
		tail.draw_polyline(PackedVector2Array([Vector2(0, 0), Vector2(6, 18), Vector2(28, 0)]), Color("c9a54a"), 3.0))
	add_child(tail)
	bubble.visible = false
	tail.visible = false
	visible = Settings.pet

func _exit_tree() -> void:
	if inst == self:
		inst = null

# ------------------------------------------------------------ 对外
static func chat(text: String, m: String = "talk", dur: float = 6.0) -> void:
	if inst != null and is_instance_valid(inst):
		inst.say(text, m, dur)

func say(text: String, m: String = "talk", dur: float = 6.0) -> void:
	if tut_mode or not Settings.pet:
		return
	if text == _last_line and bubble.visible:
		return
	_last_line = text
	visible = true
	K.clear_children(btn_row)
	_open_bubble("", text, false)
	mood = m
	if m == "excited":
		_hop = 1.0
	_hide_at = _t + dur + text.length() / 30.0

# 新手引导：持续显示的气泡（带按钮），小词跳到高亮目标旁边
# buttons：[{id, label, style, cb}]；返回 {id: Button}
func tutorial_show(title: String, text: String, buttons: Array, anchor: Rect2, hint: String = "") -> Dictionary:
	tut_mode = true
	visible = true
	_anchor = anchor
	_anchor_hint = hint
	var made := {}
	K.clear_children(btn_row)
	for b in buttons:
		var bt := K.button(str(b.label), str(b.get("style", "normal")), int(b.get("size", 16)))
		bt.custom_minimum_size = Vector2(0, 38)
		bt.pressed.connect(b.cb)
		if b.get("expand", false):
			bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_row.add_child(bt)
		made[str(b.get("id", b.label))] = bt
	_open_bubble(title, text, not buttons.is_empty())
	mood = "talk"
	_hop = 0.6
	_hide_at = -1.0
	return made

func tutorial_anchor(anchor: Rect2) -> void:
	_anchor = anchor

func tutorial_end() -> void:
	tut_mode = false
	_hide_bubble()
	K.clear_children(btn_row)
	visible = Settings.pet

func _open_bubble(title: String, text: String, has_buttons: bool) -> void:
	title_l.text = title
	title_l.visible = title != ""
	text_l.text = text
	text_l.visible_ratio = 0.0
	btn_row.visible = has_buttons
	bubble.visible = true
	tail.visible = true
	bubble.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(bubble, "modulate:a", 1.0, 0.15)

func _hide_bubble() -> void:
	bubble.visible = false
	tail.visible = false
	if mood != "sad":
		mood = "normal"

# ------------------------------------------------------------ 输入：拖动 / 点一下重说
func _on_body_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_drag = true
			_press_pos = ev.global_position
			_drag_off = ev.global_position - body.position
		else:
			_drag = false
			if ev.global_position.distance_to(_press_pos) < 6.0:
				_hop = 0.7
				if not tut_mode:
					if bubble.visible:
						_hide_bubble()
					elif _last_line != "":
						var l := _last_line
						_last_line = ""
						say(l, "talk")
					else:
						say("我是小词！拼技能、准备出招的时候，我会帮你看看这招厉不厉害。拖我可以换位置。", "talk")
	elif ev is InputEventMouseMotion and _drag and not tut_mode:
		home = ev.global_position - _drag_off
		body.position = home
		pos_target = home

# ------------------------------------------------------------ 布局与动画
func _vp() -> Vector2:
	return get_viewport_rect().size

func _default_home() -> Vector2:
	var vp := _vp()
	return Vector2(14, vp.y - BODY.y - 10)

func _bubble_size() -> Vector2:
	var ms := bubble.get_combined_minimum_size()
	return Vector2(maxf(ms.x, 200.0), ms.y)

# 引导时：找一个不挡住目标的位置放“小词+气泡”（返回整块的左上角）
func _tut_place(bs: Vector2) -> Vector2:
	var vp := _vp()
	var block := Vector2(maxf(bs.x, BODY.x), bs.y + BODY.y + 4)
	var a := _anchor
	var cands: Array = []
	if a.size.x > 2.0:
		var g := 18.0
		cands.append(Vector2(a.end.x + g, a.position.y + a.size.y * 0.5 - block.y * 0.5))
		cands.append(Vector2(a.position.x - g - block.x, a.position.y + a.size.y * 0.5 - block.y * 0.5))
		cands.append(Vector2(a.position.x + a.size.x * 0.5 - block.x * 0.5, a.end.y + g))
		cands.append(Vector2(a.position.x + a.size.x * 0.5 - block.x * 0.5, a.position.y - g - block.y))
		cands.append(Vector2(14, vp.y - block.y - 10))
		cands.append(Vector2(vp.x - block.x - 14, vp.y - block.y - 10))
		cands.append(Vector2(14, 10))
		cands.append(Vector2(vp.x - block.x - 14, 10))
	else:
		var y := vp.y - block.y - 30.0
		if _anchor_hint == "center":
			y = (vp.y - block.y) * 0.5
		elif _anchor_hint == "top":
			y = 20.0
		cands.append(Vector2((vp.x - block.x) * 0.5, y))
	var best := Vector2(14, vp.y - block.y - 10)
	var best_bad := INF
	for c in cands:
		var cc: Vector2 = c
		cc.x = clampf(cc.x, 6.0, maxf(6.0, vp.x - block.x - 6.0))
		cc.y = clampf(cc.y, 6.0, maxf(6.0, vp.y - block.y - 6.0))
		var r := Rect2(cc, block)
		var bad := 0.0
		if a.size.x > 2.0:
			bad = r.intersection(a.grow(6)).get_area()
		bad += cc.distance_to(c) * 0.5
		if bad < best_bad - 0.01:
			best_bad = bad
			best = cc
	return best

func _process(delta: float) -> void:
	_t += delta
	var vp := _vp()
	if home.x < 0:
		home = _default_home()
		body.position = home
		pos_target = home
	home.x = clampf(home.x, 0, vp.x - BODY.x)
	home.y = clampf(home.y, 0, vp.y - BODY.y)
	# 打字机
	if bubble.visible and text_l.visible_ratio < 1.0:
		var n := maxi(1, text_l.text.length())
		text_l.visible_ratio = minf(1.0, text_l.visible_ratio + delta * 42.0 / float(n))
	if _hide_at > 0 and _t > _hide_at and not tut_mode:
		_hide_at = -1.0
		_hide_bubble()
	# 位置
	var bs := _bubble_size() if bubble.visible else Vector2.ZERO
	if tut_mode:
		var bp0 := _tut_place(bs)
		pos_target = bp0 + Vector2(0, bs.y + 4 if bubble.visible else 0)
	else:
		pos_target = home
	if not _drag:
		body.position = body.position.lerp(pos_target, minf(1.0, delta * 9.0))
	if bubble.visible:
		var bp := body.position - Vector2(0, bs.y + 4)
		if bp.y < 6:
			bp.y = body.position.y + BODY.y + 4
		bp.x = clampf(bp.x, 6, maxf(6.0, vp.x - bs.x - 6))
		bp.y = clampf(bp.y, 6, maxf(6.0, vp.y - bs.y - 6))
		bubble.position = bp
		bubble.size = bs
		tail.position = Vector2(clampf(body.position.x + 30, bp.x + 10, bp.x + bs.x - 40), bp.y + bs.y - 3)
		tail.visible = bp.y + bs.y < body.position.y + 10
		tail.queue_redraw()
	# 眨眼 / 蹦跳
	_blink -= delta
	if _blink < -0.12:
		_blink = randf_range(2.0, 4.5)
	_hop = maxf(0.0, _hop - delta * 1.6)
	if mood == "excited" and _hide_at < 0 and not tut_mode:
		mood = "normal"
	body.queue_redraw()

func _talking() -> bool:
	return bubble.visible and text_l.visible_ratio < 1.0

func _draw_body() -> void:
	var s := BODY
	var bob := sin(_t * 2.2) * 3.0
	var hop := -sin(_hop * PI) * 22.0 if _hop > 0.0 else 0.0
	if tex != null:
		var want: String = "talk" if _talking() and mood == "normal" else mood
		tex.texture = mood_tex.get(want, base_tex)
		tex.position = Vector2(0, bob + hop)
		return
	var squash := 1.0 + (sin(_t * 18.0) * 0.03 if _talking() else 0.0)
	var c := Vector2(s.x * 0.5, s.y * 0.58 + bob + hop)
	var ink := Color("2f3b66")
	var paper := Color("fbf3dc")
	# 影子
	body.draw_set_transform(Vector2(s.x * 0.5, s.y - 6), 0, Vector2(1.0, 0.25))
	body.draw_circle(Vector2.ZERO, 30.0 + hop * 0.3, Color(0, 0, 0, 0.35))
	body.draw_set_transform(c, 0, Vector2(1.0 / squash, squash))
	# 身体：纸色团子，头顶一滴墨
	body.draw_circle(Vector2.ZERO, 38, Color("c9a54a"))
	body.draw_circle(Vector2.ZERO, 35, paper)
	body.draw_colored_polygon(PackedVector2Array([Vector2(-13, -30), Vector2(0, -60), Vector2(13, -30)]), ink)
	body.draw_circle(Vector2(0, -29), 13, ink)
	# 腮红
	body.draw_circle(Vector2(-22, 10), 6, Color(1.0, 0.55, 0.55, 0.45))
	body.draw_circle(Vector2(22, 10), 6, Color(1.0, 0.55, 0.55, 0.45))
	# 眼睛
	for ex in [-13.0, 13.0]:
		if mood == "excited":
			_star(Vector2(ex, 0), 8.5, Color("e0a020"))
		elif _blink < 0.0:
			body.draw_line(Vector2(ex - 6, 0), Vector2(ex + 6, 0), ink, 3)
		elif mood == "sad":
			body.draw_arc(Vector2(ex, 3), 6, PI * 1.1, PI * 1.9, 8, ink, 3)
		else:
			body.draw_circle(Vector2(ex, 0), 6.5, ink)
			body.draw_circle(Vector2(ex + 2, -2.5), 2.2, Color.WHITE)
	# 嘴
	if mood == "excited":
		body.draw_circle(Vector2(0, 17), 8, Color("8a2a2a"))
	elif _talking():
		var o := 3.0 + absf(sin(_t * 14.0)) * 4.0
		body.draw_set_transform(c + Vector2(0, 17), 0, Vector2(1.0, o / 6.0))
		body.draw_circle(Vector2.ZERO, 6, Color("8a2a2a"))
		body.draw_set_transform(c, 0, Vector2(1.0 / squash, squash))
	elif mood == "sad":
		body.draw_arc(Vector2(0, 22), 7, PI * 1.15, PI * 1.85, 8, ink, 3)
	else:
		body.draw_arc(Vector2(0, 12), 7, PI * 0.15, PI * 0.85, 8, ink, 3)
	# 小手
	var wave := sin(_t * 9.0) * 7.0 if mood == "excited" else 0.0
	body.draw_circle(Vector2(-38, 14 - wave), 7, paper)
	body.draw_circle(Vector2(38, 14 + wave), 7, paper)
	body.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _star(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(p + Vector2(cos(TAU * i / 10.0 - PI / 2), sin(TAU * i / 10.0 - PI / 2)) * rr)
	body.draw_colored_polygon(pts, col)
