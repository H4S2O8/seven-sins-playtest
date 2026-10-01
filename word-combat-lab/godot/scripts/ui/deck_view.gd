extends Control
# 只读的牌组一览：对手的牌组在调整与宣告阶段是公开的。

const K = preload("res://scripts/ui/kit.gd")
const Icon = preload("res://scripts/ui/icon.gd")

signal closed()

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and visible:
		get_viewport().set_input_as_handled()
		closed.emit()

func open(title: String, units: Array, extra: String = "") -> void:
	K.clear_children(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var win := K.panel(Color("171b29"), K.GOLD_D, 18, 2, 18)
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.offset_left = 80
	win.offset_right = -80
	win.offset_top = 50
	win.offset_bottom = -50
	add_child(win)
	var v := K.vbox(10)
	win.add_child(v)
	var head := K.hbox(10)
	head.add_child(K.label(title, 28, K.GOLD))
	if extra != "":
		head.add_child(K.label(extra, 15, K.MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := K.button("关闭", "normal", 18)
	close.pressed.connect(func(): closed.emit())
	head.add_child(close)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(grid)
	for u in units:
		grid.add_child(_unit_block(u))
	v.add_child(sc)

func _unit_block(u: Dictionary) -> Control:
	var p := K.panel(K.PANEL, K.EDGE, 12, 1)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := K.vbox(6)
	p.add_child(v)
	var head := K.hbox(10)
	head.add_child(Icon.make(str(u.get("glyph", "")), 36, Color("c9b27a")))
	head.add_child(K.label(u.name, 22, K.TEXT))
	head.add_child(K.chip("生命 %s" % (str(u.get("hp")) + "/" + str(u.max_hp) if u.has("hp") else str(u.max_hp)), Color("2c5c44"), 15))
	if u.get("kw", "") != "":
		head.add_child(K.chip("◆ " + u.kw, Color("6b5a22"), 15))
	v.add_child(head)
	var skills: Array = u.get("skills", [])
	if skills.is_empty():
		v.add_child(K.label("（没有技能）", 15, K.MUTED))
	for s in skills:
		var sp := K.panel(K.PANEL2, K.EDGE, 8, 1)
		var sv := K.vbox(2)
		sp.add_child(sv)
		var row := K.hbox(8)
		row.add_child(K.label(s.name, 17, K.TEXT))
		row.add_child(K.chip("费用 %d" % int(s.cost), Color("6b5a22"), 13))
		row.add_child(K.chip("起手≥%d秒" % int(s.windup), Color("2f5f93"), 13))
		sv.add_child(row)
		sv.add_child(K.wrap_label(s.text, 14, K.MUTED))
		v.add_child(sp)
	return p
