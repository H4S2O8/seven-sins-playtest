extends Control
# 抽词界面：两袋各25词，先手先选。

const Tut = preload("res://scripts/tutorial/tutorial.gd")
const K = preload("res://scripts/ui/kit.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const Sfx = preload("res://scripts/ui/sfx.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const Coach = preload("res://scripts/core/coach.gd")

signal picked(idx)
signal finished()

var m
var panels: Array = []
var info_label: Label
var continue_btn: Button
var chosen := -1
var can_pick := false
var _ai_idx := -1
var coach_box: VBoxContainer
var coach_info: Dictionary = {}
var rec_chips: Array = [null, null]

func setup(match_obj, ai_idx: int = -1) -> void:
	m = match_obj
	_ai_idx = ai_idx
	K.clear_children(self)
	var bg := ColorRect.new()
	bg.color = K.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 28)
	add_child(root)
	var v := K.vbox(8)
	root.add_child(v)
	var title := K.label("第 %d 轮 · 词袋" % m.st.round, 30, K.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(title)
	info_label = K.label("", 20, K.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(info_label)
	Settings.load_all()
	coach_info = Coach.analyze_draft(m.pools[0], m.decks[0], m.bags)
	coach_box = K.vbox(4)
	v.add_child(coach_box)
	var row := K.hbox(28)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	for i in 2:
		var p := _bag_panel(i)
		panels.append(p)
		row.add_child(p)
	# 已有词
	var pool_box := K.panel(K.PANEL, K.EDGE, 12, 1)
	var pv := K.vbox(6)
	pool_box.add_child(pv)
	pv.add_child(K.label("你目前持有的词（%d 张）" % _pool_total(), 15, K.MUTED))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 54)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 4)
	flow.custom_minimum_size.x = 1450
	var keys: Array = m.pools[0].keys()
	keys.sort_custom(func(a, b): return Lex.words[a].id < Lex.words[b].id)
	for w in keys:
		flow.add_child(K.word_tag(w, true, int(m.pools[0][w])))
	sc.add_child(flow)
	sc.custom_minimum_size = Vector2(0, 62)
	pv.add_child(sc)
	v.add_child(pool_box)
	var bottom := K.hbox(10)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	continue_btn = K.button("收下并继续  →", "primary", 22)
	continue_btn.custom_minimum_size = Vector2(260, 52)
	continue_btn.modulate.a = 0.0
	continue_btn.disabled = true
	continue_btn.pressed.connect(func():
		Tut.fire("draft_done")
		finished.emit())
	Tut.tag(continue_btn, "d:continue")
	bottom.add_child(continue_btn)
	v.add_child(bottom)
	_begin()
	_refresh_coach()
	Tut.fire("screen:draft")

func _bag_line(i: int) -> String:
	var b: Dictionary = coach_info.per_bag[i]
	var parts: Array = []
	if not b.done.is_empty():
		var names: Array = []
		for d in b.done.slice(0, 3):
			names.append("%s" % d.name)
		parts.append("新凑齐：" + "、".join(names))
	if not b.near.is_empty():
		var nn: Array = []
		for c in b.near.slice(0, 2):
			nn.append("%s（差 %d 个）" % [c.name, c.n])
		parts.append("接近：" + "、".join(nn))
	return "；".join(parts) if not parts.is_empty() else "对你现有的路线帮助不大"

func _refresh_coach() -> void:
	K.clear_children(coach_box)
	var head := K.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var tg := K.button("辅助轮：开" if Settings.coach else "辅助轮：关", "ghost", 15)
	tg.custom_minimum_size = Vector2(0, 30)
	tg.pressed.connect(func():
		Settings.coach = not Settings.coach
		Settings.save_all()
		_refresh_coach())
	head.add_child(tg)
	coach_box.add_child(head)
	for i in 2:
		if rec_chips[i] != null:
			rec_chips[i].visible = Settings.coach and m.human[m.picker] and continue_btn.disabled and int(coach_info.pick) == i
	if not Settings.coach:
		return
	var box := K.panel(Color("1f2a26"), K.GREEN.darkened(0.2), 10, 1)
	var col := K.vbox(3)
	box.add_child(col)
	var pick: int = coach_info.pick
	var mine := pick
	if m.human[m.picker]:
		col.add_child(K.wrap_label("教练推荐：%s袋 —— %s" % ["左" if pick == 0 else "右", coach_info.reason], 17, K.GREEN))
	else:
		mine = 1 - _ai_idx
		col.add_child(K.wrap_label("对手先选了%s袋，你拿到%s袋：%s" % [("左" if _ai_idx == 0 else "右"), ("左" if mine == 0 else "右"), _bag_line(mine)], 17, K.GREEN))
	var two := K.hbox(30)
	two.add_child(K.wrap_label("左袋 → " + _bag_line(0), 14, K.MUTED))
	two.add_child(K.wrap_label("右袋 → " + _bag_line(1), 14, K.MUTED))
	for c in two.get_children():
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(two)
	if not coach_info.watch.is_empty():
		col.add_child(K.wrap_label("接下来要留意：" + "；".join(coach_info.watch), 14, K.GOLD))
	coach_box.add_child(box)

func _pool_total() -> int:
	var n := 0
	for w in m.pools[0]:
		n += int(m.pools[0][w])
	return n

func _bag_panel(i: int) -> Control:
	var bag: Array = m.bags[i]
	var cnt := {}
	var basic := 0
	var adv := 0
	var rare := 0
	var price := 0
	for w in bag:
		cnt[w] = int(cnt.get(w, 0)) + 1
		var r: String = Lex.words[w].rarity
		if r == "基础":
			basic += 1
		elif r == "进阶":
			adv += 1
		else:
			rare += 1
		price += int(Lex.words[w].price)
	var p := K.panel(K.PANEL, K.EDGE, 16, 2, 10)
	p.name = "bag%d" % i
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(700, 0)
	var v := K.vbox(8)
	p.add_child(v)
	var head := K.hbox(8)
	head.add_child(K.label("左袋" if i == 0 else "右袋", 24, K.TEXT))
	head.add_child(K.spacer(1, 10))
	head.add_child(K.chip("基础 %d" % basic, Color("4a5260"), 14))
	head.add_child(K.chip("进阶 %d" % adv, Color("2f5f93"), 14))
	if rare > 0:
		head.add_child(K.chip("奇术 %d" % rare, Color("8a6a1f"), 14))
	head.add_child(K.chip("词价 %d" % price, Color("4a3f20"), 14))
	var rec := K.chip("教练推荐", Color("2c6a44"), 14)
	rec.visible = false
	head.add_child(rec)
	rec_chips[i] = rec
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var keys: Array = cnt.keys()
	keys.sort_custom(func(a, b): return Lex.words[a].id < Lex.words[b].id)
	var delay := 0.0
	for w in keys:
		var c := K.word_card(w, int(cnt[w]), -1, Vector2(92, 100))
		c.pivot_offset = Vector2(46, 50)
		c.scale = Vector2(0.4, 0.4)
		c.modulate.a = 0.0
		grid.add_child(c)
		var t := c.create_tween()
		t.tween_interval(delay)
		t.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(c, "modulate:a", 1.0, 0.15)
		delay += 0.03
	v.add_child(grid)
	p.gui_input.connect(func(ev): _on_panel_input(ev, i))
	p.mouse_entered.connect(func(): _hover(i, true))
	p.mouse_exited.connect(func(): _hover(i, false))
	return p

func _hover(i: int, on: bool) -> void:
	if not can_pick:
		return
	panels[i].add_theme_stylebox_override("panel", K.style(K.PANEL2 if on else K.PANEL, K.GOLD if on else K.EDGE, 16, 3 if on else 2, 10))

func _on_panel_input(ev: InputEvent, i: int) -> void:
	if can_pick and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		can_pick = false
		Sfx.play("pick")
		picked.emit(i)

func _begin() -> void:
	if m.human[m.picker]:
		can_pick = true
		info_label.text = "你是本轮先手：点击其中一袋收下，另一袋归对手。"
	else:
		# 电脑先选：演示其选择
		_show_choice(_ai_idx, false)

func _show_choice(idx: int, human_chose: bool) -> void:
	chosen = idx
	can_pick = false
	var mine := idx if human_chose else 1 - idx
	for i in 2:
		var good: bool = (i == mine)
		panels[i].add_theme_stylebox_override("panel", K.style(Color("1f3a2c") if good else Color("2a2228"), K.GREEN if good else Color("5a3a3f"), 16, 4 if good else 2, 10))
		panels[i].modulate = Color(1, 1, 1, 1) if good else Color(1, 1, 1, 0.55)
	_refresh_coach()
	if human_chose:
		info_label.text = "你收下了%s袋；对手得到另一袋。" % ("左" if idx == 0 else "右")
	else:
		info_label.text = "对手先选了%s袋，剩下的%s袋归你。" % [("左" if idx == 0 else "右"), ("右" if idx == 0 else "左")]
	continue_btn.modulate.a = 1.0
	continue_btn.disabled = false

func show_human_choice(idx: int) -> void:
	_show_choice(idx, true)
