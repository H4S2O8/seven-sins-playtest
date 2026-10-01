extends Control
# 构筑 / 调整界面：五张随从卡 + 词库。点击卡牌进入编辑器。

const K = preload("res://scripts/ui/kit.gd")
const Icon = preload("res://scripts/ui/icon.gd")
const D = preload("res://scripts/core/deck.gd")
const G = preload("res://scripts/core/grammar.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const EditorPopup = preload("res://scripts/ui/editor_popup.gd")
const DeckView = preload("res://scripts/ui/deck_view.gd")
const Ai = preload("res://scripts/ai/ai.gd")
const Coach = preload("res://scripts/core/coach.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const Tut = preload("res://scripts/tutorial/tutorial.gd")

signal finished()                      # 构筑完成 / 结束调整
signal adjusted(unit_idx, unit)        # 调整模式下确认了一张卡的修改

var m
var mode := "initial"
var wd: Dictionary
var card_row: HBoxContainer
var pool_row: HBoxContainer
var budget_bar: HBoxContainer
var budget_label: Label
var msg_label: Label
var finish_btn: Button
var popup: Control
var overlay_layer: Control
var coach_box: VBoxContainer
var persona_i := -1
var archetype_note := ""
var suggest_nd: Dictionary = {}

func setup(match_obj, m_mode: String) -> void:
	m = match_obj
	mode = m_mode
	wd = D.clone(m.decks[0])
	_build()
	refresh()
	Tut.fire("screen:adjust" if mode == "adjust" else "screen:build")

func _build() -> void:
	K.clear_children(self)
	var bg := ColorRect.new()
	bg.color = K.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 24)
	add_child(root)
	var v := K.vbox(10)
	root.add_child(v)
	# 顶栏
	var top := K.hbox(14)
	var title := K.label("初始构筑" if mode == "initial" else "第 %d 轮 · 调整" % m.st.round, 34, K.GOLD)
	top.add_child(title)
	var sub := K.label("", 16, K.MUTED)
	sub.name = "sub"
	top.add_child(sub)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	if mode == "adjust":
		var peek := K.button("查看对手牌组", "normal", 17)
		peek.pressed.connect(_peek_enemy)
		top.add_child(peek)
	Settings.load_all()
	var tgc := K.button("辅助轮：开" if Settings.coach else "辅助轮：关", "ghost", 16)
	tgc.pressed.connect(func():
		Settings.coach = not Settings.coach
		Settings.save_all()
		tgc.text = "辅助轮：开" if Settings.coach else "辅助轮：关"
		refresh())
	top.add_child(tgc)
	finish_btn = K.button("开始对战  →" if mode == "initial" else "结束调整  →", "primary", 21)
	finish_btn.custom_minimum_size = Vector2(230, 48)
	Tut.tag(finish_btn, "b:finish")
	finish_btn.pressed.connect(_on_finish)
	top.add_child(finish_btn)
	v.add_child(top)
	# 点数条
	var bb := K.hbox(10)
	bb.add_child(K.label("构筑点数", 16, K.MUTED))
	budget_bar = HBoxContainer.new()
	budget_bar.add_theme_constant_override("separation", 0)
	budget_bar.custom_minimum_size = Vector2(700, 26)
	Tut.tag(budget_bar, "b:budget")
	bb.add_child(budget_bar)
	budget_label = K.label("", 18, K.TEXT)
	bb.add_child(budget_label)
	msg_label = K.label("", 15, K.RED)
	bb.add_child(msg_label)
	v.add_child(bb)
	coach_box = K.vbox(4)
	v.add_child(coach_box)
	if mode == "adjust":
		var recent: Array = m.log_lines.slice(maxi(0, m.log_lines.size() - 3))
		var box := K.panel(Color("1f2738"), K.EDGE, 8, 1)
		var lv := K.vbox(2)
		box.add_child(lv)
		lv.add_child(K.label("近期公开动态", 13, K.MUTED))
		for ln in recent:
			lv.add_child(K.label(str(ln), 14, K.TEXT))
		v.add_child(box)
	# 五张卡
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_row = K.hbox(14)
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Tut.tag(card_row, "b:cards")
	scroll.add_child(card_row)
	v.add_child(scroll)
	# 词库
	var pool_panel := K.panel(K.PANEL, K.EDGE, 12, 1)
	Tut.tag(pool_panel, "b:pool")
	var pv := K.vbox(4)
	pool_panel.add_child(pv)
	pv.add_child(K.label("你的词库（已用 / 拥有）", 15, K.MUTED))
	var ps := ScrollContainer.new()
	ps.custom_minimum_size = Vector2(0, 140)
	ps.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pool_row = K.hbox(8)
	ps.add_child(pool_row)
	pv.add_child(ps)
	v.add_child(pool_panel)
	overlay_layer = Control.new()
	overlay_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_layer)

func _deck() -> Dictionary:
	return wd if mode == "initial" else m.decks[0]

func refresh() -> void:
	var deck := _deck()
	var b := D.budget_used(deck)
	K.clear_children(budget_bar)
	for part in [[int(b.hp), K.GREEN.darkened(0.25)], [int(b.nums), K.GOLD.darkened(0.2)], [maxi(0, D.BUDGET - int(b.total)), Color("20263a")]]:
		var r := ColorRect.new()
		r.color = part[1]
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.size_flags_stretch_ratio = maxf(0.001, float(part[0]))
		r.custom_minimum_size = Vector2(0, 24)
		budget_bar.add_child(r)
	budget_label.text = "生命 %d + 数字 %d = %d / %d" % [b.hp, b.nums, b.total, D.BUDGET]
	budget_label.add_theme_color_override("font_color", K.RED if b.total > D.BUDGET else K.TEXT)
	# 卡
	K.clear_children(card_row)
	for i in 5:
		card_row.add_child(_unit_panel(i, deck.units[i]))
	# 词库
	K.clear_children(pool_row)
	var used := D.used_counts(deck)
	var keys: Array = m.pools[0].keys()
	keys.sort_custom(func(a, b):
		var ca: String = Lex.words[a].cat
		var cb: String = Lex.words[b].cat
		return ca < cb or (ca == cb and Lex.words[a].id < Lex.words[b].id))
	for w in keys:
		var total: int = int(m.pools[0][w])
		var u: int = int(used.get(w, 0))
		pool_row.add_child(K.word_card(w, total, u, Vector2(76, 100), u >= total))
	# 状态
	var sub: Label = find_child("sub", true, false)
	if sub != null:
		if mode == "initial":
			sub.text = "①点「编辑」  ②选招式、调数值（绿=有词，红=缺词）  ③装入技能槽并确认。点数 = 生命 + 技能数字，共 100；至少装一个技能。"
		else:
			sub.text = "你还有 %d 次调整，对手 %d 次。每次只能改一张卡。" % [m.adjust_left(0), m.adjust_left(1)]
	_refresh_coach(deck)
	var v := D.validate(deck, m.pools[0])
	var has_skill := false
	for u2 in deck.units:
		if not u2.skills.is_empty():
			has_skill = true
	if mode == "initial":
		finish_btn.disabled = not (v.ok and has_skill)
		msg_label.text = "" if v.ok and has_skill else ("至少装一个技能" if v.ok else str(v.errors[0]))
	else:
		msg_label.text = ""

# ---------------------------------------------------------------- 辅助轮
func _refresh_coach(deck: Dictionary) -> void:
	K.clear_children(coach_box)
	if not Settings.coach:
		return
	var box := K.panel(Color("1f2a26"), K.GREEN.darkened(0.2), 10, 1)
	var col := K.vbox(3)
	box.add_child(col)
	col.add_child(K.label("教练", 14, K.GREEN))
	for ln in Coach.describe_build(m.pools[0], deck):
		col.add_child(K.wrap_label("· " + ln, 15, K.TEXT))
	if archetype_note != "":
		col.add_child(K.wrap_label("当前配法：" + archetype_note, 15, K.GOLD))
	var row := K.hbox(10)
	if mode == "initial":
		var auto := K.button("自动组合", "primary", 17)
		auto.tooltip_text = "用你现有的词一键配出五张能跑的牌，之后仍可逐张修改"
		auto.pressed.connect(func(): _auto_compose(false))
		row.add_child(auto)
		var nxt := K.button("换一批", "normal", 17)
		nxt.tooltip_text = "换一种打法再配一遍（均衡 → 狂攻 → 守反 → 控场 → 连锁）"
		nxt.pressed.connect(func(): _auto_compose(true))
		row.add_child(nxt)
	else:
		var aa := K.button("自动调整（用掉一次）", "primary", 17)
		aa.disabled = m.adjust_side() != 0 or m.adjust_left(0) <= 0
		aa.pressed.connect(func(): _auto_adjust(false))
		row.add_child(aa)
	col.add_child(row)
	coach_box.add_child(box)

func _auto_compose(next: bool) -> void:
	var tried := 0
	var old := wd
	var found := false
	while tried < Ai.PERSONA_ORDER.size():
		persona_i = (persona_i + 1) % Ai.PERSONA_ORDER.size() if (next or tried > 0 or persona_i < 0) else persona_i
		tried += 1
		var persona: String = Ai.PERSONA_ORDER[persona_i]
		var nd := Ai.build_deck(m.pools[0], persona, m.rng)
		if D.changed_units(old, nd).is_empty() and (next or tried > 1):
			continue # 和现在一样，换下一种
		wd = nd
		archetype_note = Ai.PERSONA_LABEL[persona]
		found = true
		break
	if not found:
		archetype_note = "你的词暂时只够这一种配法；多凑些词再来。"
	refresh()

func _auto_adjust(next: bool) -> void:
	if m.adjust_side() != 0 or m.adjust_left(0) <= 0:
		return
	var tried := 0
	while tried < Ai.PERSONA_ORDER.size():
		persona_i = (persona_i + 1) % Ai.PERSONA_ORDER.size()
		tried += 1
		var persona: String = Ai.PERSONA_ORDER[persona_i]
		var nd := Ai.adjust_step(m.decks[0], m.pools[0], persona, m.rng)
		if nd.is_empty():
			continue
		var changed := D.changed_units(m.decks[0], nd)
		if changed.size() != 1:
			continue
		_show_suggestion(changed[0], nd, persona)
		return
	archetype_note = "暂时没有能自动装上的新招；多凑些词，或自己编辑。"
	refresh()

func _show_suggestion(idx: int, nd: Dictionary, persona: String) -> void:
	suggest_nd = nd
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var win := K.panel(Color("171b29"), K.GREEN, 16, 2, 16)
	win.custom_minimum_size = Vector2(760, 0)
	win.position = Vector2(420, 220)
	var v := K.vbox(8)
	win.add_child(v)
	v.add_child(K.label("自动调整建议（%s）" % persona, 24, K.GOLD))
	var u: Dictionary = nd.units[idx]
	v.add_child(K.label("修改【%s】：生命 %d，关键词 %s" % [u.name, int(u.max_hp), u.kw if u.kw != "" else "无"], 17, K.TEXT))
	for sk in u.skills:
		v.add_child(K.wrap_label("· %s（操作费 %d）：%s" % [sk.name, int(sk.cost), sk.text], 15, K.MUTED))
	var row := K.hbox(10)
	var ok := K.button("采用（用掉一次调整）", "primary", 18)
	var other := K.button("换一个建议", "normal", 18)
	var cancel := K.button("取消", "ghost", 18)
	row.add_child(ok)
	row.add_child(other)
	row.add_child(cancel)
	v.add_child(row)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(dim)
	holder.add_child(win)
	overlay_layer.add_child(holder)
	var close := func():
		holder.queue_free()
		overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ok.pressed.connect(func():
		close.call()
		adjusted.emit(idx, suggest_nd.units[idx]))
	other.pressed.connect(func():
		close.call()
		_auto_adjust(true))
	cancel.pressed.connect(close)

func _unit_panel(i: int, u: Dictionary) -> Control:
	var p := K.panel(Color("1d2233"), K.BLUE.darkened(0.3), 14, 2, 8)
	p.custom_minimum_size = Vector2(290, 0)
	if i == 0:
		Tut.tag(p, "b:unit0")
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := K.vbox(6)
	p.add_child(v)
	var head := K.hbox(8)
	var col := K.vbox(0)
	col.add_child(K.label(u.name, 24, K.TEXT))
	col.add_child(K.label("第 %d 位" % (i + 1), 13, K.MUTED))
	head.add_child(col)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(K.chip("生命 %d" % int(u.max_hp), Color("2c5c44"), 20))
	v.add_child(head)
	var hue: float = {"剑": 0.0, "盾": 0.58, "咒": 0.76, "弓": 0.33, "魂": 0.92}.get(u.glyph, 0.1)
	var pcol := Color.from_hsv(hue, 0.45, 0.55)
	var portrait := PanelContainer.new()
	portrait.custom_minimum_size = Vector2(0, 120)
	portrait.add_theme_stylebox_override("panel", K.style(pcol, pcol.lightened(0.3), 10, 1))
	var cc := CenterContainer.new()
	cc.add_child(Icon.make(u.glyph, 96, Color(1, 1, 1, 0.9)))
	portrait.add_child(cc)
	v.add_child(portrait)
	if u.kw != "":
		v.add_child(K.chip("◆ " + u.kw, Color("6b5a22"), 15))
	else:
		v.add_child(K.label("◇ 无关键词", 14, K.MUTED))
	for k in D.MAX_SKILLS:
		if k < u.skills.size():
			var s: Dictionary = u.skills[k]
			var sp2 := K.panel(K.PANEL2, K.EDGE, 8, 1)
			var sv := K.vbox(2)
			sp2.add_child(sv)
			var r := K.hbox(6)
			r.add_child(K.label(s.name, 17, K.TEXT))
			r.add_child(K.chip("%d" % int(s.cost), Color("6b5a22"), 14))
			sv.add_child(r)
			sv.add_child(K.wrap_label(s.text, 13, K.MUTED))
			v.add_child(sp2)
		else:
			var e := K.panel(Color(1, 1, 1, 0.03), K.EDGE, 8, 1)
			e.add_child(K.label("＋ 空技能槽", 15, K.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
			v.add_child(e)
	var sp3 := Control.new()
	sp3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp3)
	var edit := K.button("编辑", "primary", 18)
	edit.pressed.connect(func(): _open_editor(i))
	edit.disabled = mode == "adjust" and m.adjust_side() != 0
	if i == 0:
		Tut.tag(edit, "b:edit0")
	v.add_child(edit)
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return p

func _open_editor(i: int) -> void:
	if mode == "adjust" and (m.adjust_side() != 0 or m.adjust_left(0) <= 0):
		return
	Tut.fire("editor_open")
	var pop := EditorPopup.new()
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_layer.add_child(pop)
	pop.open(_deck(), i, m.pools[0], mode)
	pop.cancelled.connect(func(): _close_popup(pop))
	pop.committed.connect(func(unit):
		Tut.fire("committed")
		_close_popup(pop)
		if mode == "initial":
			wd.units[i] = unit
			D.rename_skills(wd)
			refresh()
		else:
			adjusted.emit(i, unit))
	popup = pop

func _close_popup(pop: Control) -> void:
	pop.queue_free()
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _peek_enemy() -> void:
	var dv := DeckView.new()
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_layer.add_child(dv)
	var units: Array = []
	for u in m.decks[1].units:
		units.append(u)
	dv.open("对手的牌组（公开）", units, "对手性格：" + str(m.personas[1]))
	dv.closed.connect(func():
		dv.queue_free()
		overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE)

func _on_finish() -> void:
	Tut.fire("build_finish")
	finished.emit()

func show_error(text: String) -> void:
	msg_label.text = text
