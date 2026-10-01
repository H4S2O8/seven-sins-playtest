extends Control
# 随从卡：战斗与构筑共用。根是 Control，里面一个 frame 和一层特效层。

const K = preload("res://scripts/ui/kit.gd")
const Icon = preload("res://scripts/ui/icon.gd")

signal clicked(card)
signal hovered(card, on)

const STATUS_COL := {"狂振": Color("c4483f"), "易伤": Color("d4832f"), "沉默": Color("6f7689"), "护盾": Color("4a8fd4"), "牵连": Color("8b5cc4"), "升华": Color("d0a73a")}
const GLYPH_HUE := {"剑": 0.0, "盾": 0.58, "咒": 0.76, "弓": 0.33, "魂": 0.92}

var uid := -1
var side := 0
var mode := "battle"
var unit: Dictionary = {}
var skills: Array = []
var frame: PanelContainer
var fx: Control
var hp_bar: ProgressBar
var hp_label: Label
var status_row: HBoxContainer
var down_cover: Control
var glyph_label: Control
var name_label: Label
var kw_row: HBoxContainer
var skill_box: VBoxContainer
var highlight := Color(0, 0, 0, 0)
var selectable := false
var shown_hp := 0.0
var anim_mode := false
var anim_hp := 0
var anim_down := false
var _tween: Tween

func _init(sz: Vector2 = Vector2(172, 250)) -> void:
	custom_minimum_size = sz
	pivot_offset = sz / 2.0
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(u: Dictionary, sk: Array, which_side: int, m: String = "battle") -> void:
	unit = u
	skills = sk
	side = which_side
	mode = m
	uid = int(u.get("uid", -1))
	K.clear_children(self)
	frame = PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_build_contents()
	fx = Control.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	refresh(u, sk)
	if not is_connected("mouse_entered", _on_enter):
		mouse_entered.connect(_on_enter)
		mouse_exited.connect(_on_exit)

func _on_enter() -> void:
	hovered.emit(self, true)
	if selectable or mode == "build":
		var t := create_tween()
		t.tween_property(self, "scale", Vector2(1.03, 1.03), 0.08)

func _on_exit() -> void:
	hovered.emit(self, false)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1, 1), 0.08)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)

func _glyph_color(g: String) -> Color:
	var h: float = GLYPH_HUE.get(g, 0.1)
	return Color.from_hsv(h, 0.45, 0.55)

func _build_contents() -> void:
	var big := mode == "build"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	frame.add_child(v)
	# 头
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	name_label = K.label("", 18 if big else 16, K.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	v.add_child(head)
	# 画像
	var portrait := PanelContainer.new()
	portrait.custom_minimum_size = Vector2(0, 92 if big else 56)
	var ps := K.style(_glyph_color(unit.get("glyph", "剑")), _glyph_color(unit.get("glyph", "剑")).lightened(0.3), 8, 1)
	portrait.add_theme_stylebox_override("panel", ps)
	var cc := CenterContainer.new()
	glyph_label = Icon.make(str(unit.get("glyph", "?")), 66 if big else 40, Color(1, 1, 1, 0.9))
	cc.add_child(glyph_label)
	portrait.add_child(cc)
	v.add_child(portrait)
	# 生命条
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 20)
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("background", K.style(Color("0c0e14"), K.EDGE, 6, 1))
	hp_bar.add_theme_stylebox_override("fill", K.style(K.GREEN, Color(0, 0, 0, 0), 6, 0))
	hp_label = K.label("", 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_bar.add_child(hp_label)
	v.add_child(hp_bar)
	status_row = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 3)
	status_row.custom_minimum_size = Vector2(0, 22)
	v.add_child(status_row)
	kw_row = HBoxContainer.new()
	v.add_child(kw_row)
	skill_box = VBoxContainer.new()
	skill_box.add_theme_constant_override("separation", 3)
	v.add_child(skill_box)
	# 倒下遮罩
	down_cover = PanelContainer.new()
	down_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	down_cover.add_theme_stylebox_override("panel", K.style(Color(0, 0, 0, 0.66), Color(0, 0, 0, 0), 12, 0))
	down_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dc := CenterContainer.new()
	var dl := K.label("修整中", 24, Color("d8d0c0"), HORIZONTAL_ALIGNMENT_CENTER)
	dc.add_child(dl)
	down_cover.add_child(dc)
	down_cover.visible = false
	add_child(down_cover)

func refresh(u: Dictionary, sk: Array) -> void:
	unit = u
	skills = sk
	var is_down: bool = int(u.get("down_round", -1)) != -1
	if anim_mode:
		is_down = anim_down
	var accent: Color = K.BLUE if side == 0 else K.RED
	var border := accent.darkened(0.2)
	var bw := 2
	if highlight.a > 0.0:
		border = highlight
		bw = 4
	frame.add_theme_stylebox_override("panel", K.style(Color("1d2233"), border, 12, bw, 8))
	name_label.text = "%s" % u.get("name", "?")
	var maxhp := int(u.get("max_hp", 1))
	var hp := int(u.get("hp", maxhp))
	if anim_mode:
		hp = anim_hp
	hp_bar.max_value = maxhp
	if not anim_mode:
		shown_hp = hp
	hp_bar.value = shown_hp
	_hp_text(hp, maxhp)
	_color_hp()
	# 状态
	K.clear_children(status_row)
	for s in u.get("statuses", []):
		var txt: String = s.name
		if s.name == "护盾":
			txt += " %d" % int(s.value)
		status_row.add_child(K.chip(txt, STATUS_COL.get(s.name, K.MUTED), 12))
	K.clear_children(kw_row)
	var kw: String = u.get("kw", "")
	if kw != "":
		var kc := K.chip("◆ " + kw + ("（已用）" if u.get("kw_spent", false) else ""), Color("6b5a22") if not u.get("kw_spent", false) else Color("3a3a40"), 13)
		kc.tooltip_text = "被动关键词：" + kw
		kw_row.add_child(kc)
	# 技能
	K.clear_children(skill_box)
	for s in sk:
		skill_box.add_child(_skill_line(s))
	down_cover.visible = is_down
	modulate = Color(1, 1, 1, 1)

func _skill_line(s: Dictionary) -> Control:
	var tag: String = s.get("kind_tag", "atk")
	var col: Color = {"atk": Color("8a3a36"), "def": Color("2f5a8a"), "heal": Color("2f7a55"), "trap": Color("7a4aa0"), "ctl": Color("2f7a7a"), "buff": Color("8a6a2a")}.get(tag, Color("444a5c"))
	var p := PanelContainer.new()
	var st := K.style(col, col.lightened(0.25), 6, 1)
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	st.content_margin_left = 6
	st.content_margin_right = 6
	p.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var nm := K.label(s.get("name", "技能"), 14 if mode == "battle" else 15, Color.WHITE)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	row.add_child(nm)
	row.add_child(K.label("%d" % int(s.get("cost", 0)), 14, K.GOLD))
	p.add_child(row)
	p.tooltip_text = "%s  费用%d  起手≥%d秒\n%s" % [s.get("name", ""), int(s.get("cost", 0)), int(s.get("windup", 0)), s.get("text", "")]
	return p

func _hp_text(hp: int, maxhp: int) -> void:
	hp_label.text = "%d / %d" % [hp, maxhp]

func _color_hp() -> void:
	var r: float = hp_bar.value / maxf(1.0, hp_bar.max_value)
	var col: Color = K.GREEN if r > 0.5 else (Color("d8b23a") if r > 0.25 else K.RED)
	hp_bar.add_theme_stylebox_override("fill", K.style(col, Color(0, 0, 0, 0), 6, 0))

# 血条动画到某个值
func animate_hp(to_hp: int, dur: float = 0.35) -> void:
	var maxhp := int(unit.get("max_hp", 1))
	anim_hp = to_hp
	var t := create_tween()
	t.tween_method(func(v: float):
		shown_hp = v
		hp_bar.value = v
		_hp_text(int(round(v)), maxhp)
		_color_hp(), shown_hp, float(to_hp), dur)

func begin_anim(hp: int, down: bool) -> void:
	anim_mode = true
	anim_hp = hp
	anim_down = down
	shown_hp = hp
	refresh(unit, skills)

func end_anim() -> void:
	anim_mode = false
	refresh(unit, skills)

func set_highlight(col: Color) -> void:
	highlight = col
	if frame != null:
		refresh(unit, skills)

func float_text(text: String, col: Color, size: int = 30) -> void:
	var l := K.label(text, size, col, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.size = Vector2(custom_minimum_size.x, 40)
	l.position = Vector2(0, custom_minimum_size.y * 0.35)
	l.z_index = 20
	fx.add_child(l)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 70, 0.9).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.45)
	t.chain().tween_callback(l.queue_free)

func shake() -> void:
	var t := create_tween()
	var p0 := position
	for i in 5:
		t.tween_property(self, "position:x", p0.x + (8 if i % 2 == 0 else -8), 0.04)
	t.tween_property(self, "position:x", p0.x, 0.04)

func flash(col: Color) -> void:
	var r := ColorRect.new()
	r.color = Color(col.r, col.g, col.b, 0.0)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(r)
	var t := create_tween()
	t.tween_property(r, "color:a", 0.5, 0.08)
	t.tween_property(r, "color:a", 0.0, 0.3)
	t.tween_callback(r.queue_free)
