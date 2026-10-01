extends RefCounted
# 界面基础件：配色、样式、词卡、小标签。全部用代码构造，不依赖外部资源。

const Lex = preload("res://scripts/core/lexicon.gd")
const Sfx = preload("res://scripts/ui/sfx.gd")

const BG := Color("10121a")
const PANEL := Color("1b2030")
const PANEL2 := Color("242b40")
const EDGE := Color("3b4562")
const GOLD := Color("e0b85c")
const GOLD_D := Color("8d7032")
const TEXT := Color("ece8da")
const MUTED := Color("9aa2b8")
const RED := Color("e0605a")
const GREEN := Color("62c483")
const BLUE := Color("5fa0e0")
const PURPLE := Color("a279d6")

static func style(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 10, bw: int = 0, shadow: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow / 2.0)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

static func panel(bg: Color = PANEL, border: Color = EDGE, radius: int = 12, bw: int = 1, shadow: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(bg, border, radius, bw, shadow))
	return p

static func label(text: String, size: int = 18, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align as HorizontalAlignment
	return l

static func wrap_label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 40
	return l

static func button(text: String, kind: String = "normal", size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	var base := PANEL2
	var edge := EDGE
	var fg := TEXT
	if kind == "primary":
		base = GOLD
		edge = Color("fff0c0")
		fg = Color("20180a")
	elif kind == "danger":
		base = Color("8a3a36")
		edge = RED
	elif kind == "ghost":
		base = Color(1, 1, 1, 0.04)
	b.add_theme_stylebox_override("normal", style(base, edge, 10, 1, 4))
	b.add_theme_stylebox_override("hover", style(base.lightened(0.14), edge.lightened(0.2), 10, 2, 6))
	b.add_theme_stylebox_override("pressed", style(base.darkened(0.15), edge, 10, 1, 2))
	b.add_theme_stylebox_override("disabled", style(base.darkened(0.4), Color(0.3, 0.3, 0.35), 10, 1, 0))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(func(): Sfx.play("click"))
	return b

static func chip(text: String, color: Color, size: int = 13, fg: Color = Color.WHITE) -> PanelContainer:
	var p := PanelContainer.new()
	var s := style(color, color.lightened(0.25), 8, 1)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.add_child(label(text, size, fg))
	return p

static func spacer(h: int = 8, w: int = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

# ------------------------------------------------------------------ 词卡
static func word_card(word: String, count: int = 1, used: int = -1, size: Vector2 = Vector2(84, 110), dim: bool = false) -> Control:
	var info: Dictionary = Lex.get_word(word)
	var cat_col: Color = Lex.cat_color(word)
	var rar_col: Color = Lex.rarity_color(word)
	var root := Control.new()
	root.custom_minimum_size = size
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	var bw := 2
	if info.get("rarity", "") == "奇术":
		bw = 3
	card.add_theme_stylebox_override("panel", style(Color("202638"), rar_col, 9, bw, 4))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	card.add_child(v)
	# 顶带：类别
	var head := PanelContainer.new()
	var hs := style(cat_col.darkened(0.25), cat_col, 6, 0)
	hs.content_margin_top = 1
	hs.content_margin_bottom = 1
	head.add_theme_stylebox_override("panel", hs)
	head.add_child(label(info.get("cat", "?"), 11, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(head)
	# 词
	var n := word.length()
	var avail_w: float = size.x - 22.0
	var fs := 28
	while fs > 12 and float(n * fs) > avail_w:
		fs -= 1
	if fs < 17 and n >= 4:
		# 放不下一行就分两行
		var per: int = int(ceil(n / 2.0))
		fs = 26
		while fs > 12 and float(per * fs) > avail_w:
			fs -= 1
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var wl := label(word, fs, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	wl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	wl.custom_minimum_size.x = size.x - 20
	center.add_child(wl)
	v.add_child(center)
	# 底：价格宝石
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	var price := int(info.get("price", 0))
	var gems := ""
	for i in price:
		gems += "◆"
	if gems == "":
		gems = "·"
	foot.add_child(label(gems, 12, GOLD if price > 0 else MUTED))
	v.add_child(foot)
	if not info.get("impl", true):
		root.modulate = Color(1, 1, 1, 0.45)
	if dim:
		root.modulate = Color(1, 1, 1, 0.4)
	# 数量角标（放在容器之外，不参与排版）
	if count > 1 or used >= 0:
		var txt: String = ("%d/%d" % [used, count]) if used >= 0 else ("×%d" % count)
		var bcol := Color("3a4263")
		if used >= 0:
			bcol = Color("7a3a36") if used > count else (Color("2c5c44") if used < count else Color("4a4f66"))
		var badge := chip(txt, bcol, 12)
		badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		badge.offset_right = 4
		badge.offset_bottom = 6
		root.add_child(badge)
	root.tooltip_text = "%s〔%s·%s〕
%s" % [word, info.get("cat", ""), info.get("rarity", ""), info.get("desc", "")]
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	return root

# 小词条（用于“所需词”条）：有货绿，缺货红
static func word_tag(word: String, ok: bool, n: int = 1) -> Control:
	var col := Color("2b5a43") if ok else Color("7d3430")
	var t := chip(word + (("×%d" % n) if n > 1 else ""), col, 14)
	var info: Dictionary = Lex.get_word(word)
	t.tooltip_text = "%s〔%s〕%s" % [word, info.get("cat", ""), info.get("desc", "")]
	return t

static func clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
