extends Control
# 卡牌编辑器弹窗：一张随从卡的生命、关键词、两个技能槽。
# 两个标签页共用同一份数据：
#   简单版 —— 选一个“招式模板”，填空（参数），立刻预览费用与所需词；
#   复杂版 —— 直接拼节点树（见 complex_editor.gd）。

const Tut = preload("res://scripts/tutorial/tutorial.gd")
const K = preload("res://scripts/ui/kit.gd")
const Appraise = preload("res://scripts/game/appraise.gd")
const Pet = preload("res://scripts/ui/pet.gd")
const Icon = preload("res://scripts/ui/icon.gd")
const G = preload("res://scripts/core/grammar.gd")
const R = preload("res://scripts/core/recipes.gd")
const D = preload("res://scripts/core/deck.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const Complex = preload("res://scripts/ui/complex_editor.gd")
const Namer = preload("res://scripts/core/namer.gd")

signal committed(unit)
signal cancelled()

var base_deck: Dictionary
var pool: Dictionary
var unit_idx := 0
var work: Dictionary          # 正在编辑的这张卡
var slot := 0
var mode := "initial"
var tab := "complex"

var hp_label: Label
var kw_option: OptionButton
var slot_box: VBoxContainer
var info_box: VBoxContainer
var tab_hint: Label
var _ap_token := 0
var _last_ap_sig := ""
var tab_holder: Control
var simple_root: Control
var complex_root
var btn_commit: Button
var budget_label: Label

# 简单版状态
var sel_tid := "atk1"
var sel_params := {}
var preview_skill: Dictionary = {}
var param_box: VBoxContainer
var preview_box: VBoxContainer
var sel_name := ""            # 玩家给当前技能起的名字（空=用模板名）
var skill_name_edit: LineEdit
var unit_name_edit: LineEdit
var _rng := RandomNumberGenerator.new()
var tpl_buttons := {}

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and visible:
		get_viewport().set_input_as_handled()
		cancelled.emit()

func open(deck: Dictionary, idx: int, pool_words: Dictionary, m: String) -> void:
	base_deck = deck
	unit_idx = idx
	pool = pool_words
	mode = m
	work = D.clone(deck).units[idx]
	slot = 0
	_build()
	_load_slot()

# ---------------------------------------------------------------- 可用性计算
func _other_used() -> Dictionary:
	# 除“当前正在编辑的技能槽”以外，牌组其余部分用掉的词
	var used := {}
	for i in base_deck.units.size():
		if i == unit_idx:
			continue
		for w in D.used_words({"units": [base_deck.units[i]]}):
			used[w] = int(used.get(w, 0)) + 1
	if work.kw != "":
		used[work.kw] = int(used.get(work.kw, 0)) + 1
	for k in work.skills.size():
		if k == slot:
			continue
		for w in work.skills[k].words:
			used[w] = int(used.get(w, 0)) + 1
	return used

func avail_for_slot() -> Dictionary:
	var used := _other_used()
	var a := {}
	for w in pool:
		a[w] = int(pool[w]) - int(used.get(w, 0))
	return a

func _points_other() -> int:
	var total := 0
	for i in base_deck.units.size():
		if i == unit_idx:
			continue
		total += int(base_deck.units[i].max_hp)
		for sk in base_deck.units[i].skills:
			total += int(sk.budget)
	total += int(work.max_hp)
	for k in work.skills.size():
		if k != slot:
			total += int(work.skills[k].budget)
	return total

# ---------------------------------------------------------------- 构建界面
func _build() -> void:
	K.clear_children(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var win := K.panel(Color("171b29"), K.GOLD_D, 18, 2, 18)
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.offset_left = 40
	win.offset_right = -40
	win.offset_top = 28
	win.offset_bottom = -28
	add_child(win)
	var root := K.vbox(10)
	win.add_child(root)
	# 标题栏
	var head := K.hbox(12)
	head.add_child(K.label("编辑【%s】" % work.name, 28, K.GOLD))
	head.add_child(K.label("改动将写入牌组" if mode == "initial" else "本次调整只能改这一张卡（消耗1次调整）", 15, K.MUTED))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	budget_label = K.label("", 18, K.TEXT)
	head.add_child(budget_label)
	root.add_child(head)
	var body := K.hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	# 左栏
	var left := K.panel(K.PANEL, K.EDGE, 12, 1)
	left.custom_minimum_size = Vector2(380, 0)
	Tut.tag(left, "e:left")
	body.add_child(left)
	var lv := K.vbox(10)
	left.add_child(lv)
	var glyph_c := CenterContainer.new()
	glyph_c.add_child(Icon.make(work.glyph, 76, Color("c9b27a")))
	lv.add_child(glyph_c)
	var nrow := K.hbox(6)
	nrow.add_child(K.label("卡名", 18, K.MUTED))
	unit_name_edit = LineEdit.new()
	unit_name_edit.max_length = 8
	unit_name_edit.text = work.name
	unit_name_edit.custom_minimum_size = Vector2(170, 34)
	unit_name_edit.text_changed.connect(func(t): work.name = t if t.strip_edges() != "" else work.name)
	nrow.add_child(unit_name_edit)
	var dice := K.button("随机", "normal", 18)
	dice.custom_minimum_size = Vector2(44, 34)
	dice.tooltip_text = "按这张卡装的技能随机取一个名字"
	dice.pressed.connect(func():
		_rng.randomize()
		work.name = Namer.minion_name(work, _rng)
		unit_name_edit.text = work.name)
	nrow.add_child(dice)
	lv.add_child(nrow)
	var hp_row := K.hbox(6)
	hp_row.add_child(K.label("生命", 18, K.MUTED))
	for d in [-5, -1]:
		var b := K.button(str(d), "normal", 16)
		b.custom_minimum_size = Vector2(44, 34)
		b.pressed.connect(func(): _hp(d))
		hp_row.add_child(b)
	hp_label = K.label("", 26, K.GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	hp_label.custom_minimum_size.x = 60
	hp_row.add_child(hp_label)
	for d in [1, 5]:
		var b2 := K.button("+%d" % d, "normal", 16)
		b2.custom_minimum_size = Vector2(44, 34)
		b2.pressed.connect(func(): _hp(d))
		hp_row.add_child(b2)
	lv.add_child(hp_row)
	var kw_row := K.hbox(6)
	kw_row.add_child(K.label("关键词", 18, K.MUTED))
	kw_option = OptionButton.new()
	kw_option.add_theme_font_size_override("font_size", 16)
	kw_option.custom_minimum_size.x = 200
	kw_option.item_selected.connect(_on_kw)
	kw_row.add_child(kw_option)
	lv.add_child(kw_row)
	lv.add_child(K.label("这张卡的技能（在右侧编辑）", 15, K.MUTED))
	slot_box = K.vbox(8)
	lv.add_child(slot_box)
	var sp2 := Control.new()
	sp2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sp2)
	# 右栏
	var right := K.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var tabs := K.hbox(8)
	var b_complex := K.button("自由拼词（自己组合）", "primary", 18)
	var b_simple := K.button("备选模板（现成的招式）", "normal", 18)
	Tut.tag(b_simple, "e:tab_simple")
	b_simple.pressed.connect(func():
		tab = "simple"
		_show_tab(b_simple, b_complex)
		Tut.fire("tab:simple"))
	b_complex.pressed.connect(func():
		tab = "complex"
		_show_tab(b_simple, b_complex))
	tabs.add_child(b_complex)
	tabs.add_child(b_simple)
	tab_hint = K.label("", 14, K.MUTED)
	tabs.add_child(tab_hint)
	Tut.tag(tabs, "e:tabs")
	right.add_child(tabs)
	tab_holder = Control.new()
	tab_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(tab_holder)
	simple_root = _build_simple()
	tab_holder.add_child(simple_root)
	complex_root = Complex.new()
	complex_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	complex_root.changed.connect(_on_complex_changed)
	complex_root.appraise_host = self
	tab_holder.add_child(complex_root)
	Tut.tag(complex_root, "e:complex")
	_show_tab(b_simple, b_complex)
	# 底栏
	var foot := K.hbox(12)
	info_box = K.vbox(2)
	info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(info_box)
	var cancel := K.button("取消", "normal", 20)
	cancel.custom_minimum_size = Vector2(130, 46)
	cancel.pressed.connect(func(): cancelled.emit())
	foot.add_child(cancel)
	btn_commit = K.button("确认修改", "primary", 20)
	btn_commit.custom_minimum_size = Vector2(180, 46)
	Tut.tag(btn_commit, "e:commit")
	btn_commit.pressed.connect(func(): committed.emit(work))
	foot.add_child(btn_commit)
	root.add_child(foot)
	_refresh_left()

func _show_tab(b_simple: Button, b_complex: Button) -> void:
	for pair in [[b_simple, "simple"], [b_complex, "complex"]]:
		var b: Button = pair[0]
		var active: bool = tab == pair[1]
		var base: Color = K.GOLD if active else K.PANEL2
		b.add_theme_stylebox_override("normal", K.style(base, K.EDGE if not active else Color("fff0c0"), 10, 1, 4))
		b.add_theme_color_override("font_color", Color("20180a") if active else K.TEXT)
		b.add_theme_color_override("font_hover_color", Color("20180a") if active else K.TEXT)
	simple_root.visible = tab == "simple"
	complex_root.visible = tab == "complex"
	tab_hint.text = "你可以像搭积木一样自己组合效果；没灵感就看看右边的「备选模板」。" if tab == "complex" else "这些只是现成的备选招式，省事用的；想要更自由的组合，回到「自由拼词」。"
	if tab == "complex":
		complex_root.load_skill(_current_skill(), avail_for_slot(), _points_other())
	else:
		_update_preview()

func _current_skill() -> Dictionary:
	if slot < work.skills.size():
		return work.skills[slot]
	return {}

# ---------------------------------------------------------------- 左栏
func _hp(d: int) -> void:
	var nv: int = maxi(1, int(work.max_hp) + d)
	if d > 0 and _points_other() - int(work.max_hp) + nv > D.BUDGET:
		nv = D.BUDGET - (_points_other() - int(work.max_hp))
	work.max_hp = maxi(1, nv)
	_refresh_left()
	_update_preview()

func _on_kw(i: int) -> void:
	work.kw = "" if i == 0 else kw_option.get_item_text(i).split(" ")[0]
	_refresh_left()
	_update_preview()

func _refresh_left() -> void:
	hp_label.text = str(work.max_hp)
	# 关键词
	var used := _other_used_no_kw()
	kw_option.clear()
	kw_option.add_item("（无）")
	var sel := 0
	for kw in D.KEYWORDS:
		var have := int(pool.get(kw, 0)) - int(used.get(kw, 0))
		if have > 0 or work.kw == kw:
			kw_option.add_item("%s 〔%s〕" % [kw, Lex.get_word(kw).desc.substr(0, 14)])
			if work.kw == kw:
				sel = kw_option.item_count - 1
	kw_option.select(sel)
	# 技能槽
	K.clear_children(slot_box)
	for k in D.MAX_SKILLS:
		var p := K.panel(K.PANEL2 if k != slot else Color("33405f"), K.GOLD if k == slot else K.EDGE, 10, 2 if k == slot else 1)
		var v := K.vbox(4)
		p.add_child(v)
		var row := K.hbox(6)
		row.add_child(K.label(("技能槽 %d" % (k + 1)) if D.MAX_SKILLS > 1 else "技能", 16, K.GOLD if k == slot else K.MUTED))
		var spc := Control.new()
		spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spc)
		if k < work.skills.size():
			row.add_child(K.label("费用 %d" % int(work.skills[k].cost), 15, K.GOLD))
			var clr := K.button("清空", "ghost", 14)
			clr.custom_minimum_size = Vector2(56, 26)
			clr.pressed.connect(func():
				work.skills.remove_at(k)
				slot = mini(slot, maxi(0, work.skills.size()))
				_refresh_left()
				_load_slot())
			row.add_child(clr)
		v.add_child(row)
		if k < work.skills.size():
			v.add_child(K.label(work.skills[k].name, 18, K.TEXT))
			v.add_child(K.wrap_label(work.skills[k].text, 14, K.MUTED))
		else:
			v.add_child(K.label("（空）", 15, K.MUTED))
		Tut.tag(p, "e:slot%d" % k)
		p.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				slot = k
				_refresh_left()
				_load_slot()
				Tut.fire("slot:%d" % k))
		slot_box.add_child(p)
	# 点数
	var pts := _points_other()
	budget_label.text = "点数 %d / %d" % [pts, D.BUDGET]
	budget_label.add_theme_color_override("font_color", K.RED if pts > D.BUDGET else K.TEXT)

func _other_used_no_kw() -> Dictionary:
	var used := {}
	for i in base_deck.units.size():
		if i == unit_idx:
			continue
		for w in D.used_words({"units": [base_deck.units[i]]}):
			used[w] = int(used.get(w, 0)) + 1
	for k in work.skills.size():
		for w in work.skills[k].words:
			used[w] = int(used.get(w, 0)) + 1
	return used

# ---------------------------------------------------------------- 简单版
func _build_simple() -> Control:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	# 模板网格
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(520, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	for t in R.catalog():
		var b := _template_card(t)
		grid.add_child(b)
	root.add_child(sc)
	# 参数与预览
	var right := K.panel(K.PANEL, K.EDGE, 12, 1)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := K.vbox(8)
	right.add_child(rv)
	param_box = K.vbox(6)
	rv.add_child(param_box)
	rv.add_child(HSeparator.new())
	preview_box = K.vbox(6)
	preview_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(preview_box)
	root.add_child(right)
	return root

func _template_card(t: Dictionary) -> Control:
	var fam_col: Color = {"攻": Color("8a3a36"), "守": Color("2f7a55"), "控": Color("2f7a7a"), "反": Color("7a4aa0")}.get(t.family, K.EDGE)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(158, 124)
	p.add_theme_stylebox_override("panel", K.style(Color("1f2538"), fam_col, 10, 2, 3))
	p.name = "tpl_" + t.id
	Tut.tag(p, "e:tpl:" + t.id)
	var v := K.vbox(2)
	p.add_child(v)
	var top := K.hbox(6)
	top.add_child(Icon.make(str(t.glyph), 38, fam_col.lightened(0.45)))
	var col := K.vbox(0)
	col.add_child(K.label(t.title, 17, K.TEXT))
	col.add_child(K.chip(t.family, fam_col, 11))
	top.add_child(col)
	v.add_child(top)
	var bl := K.wrap_label(t.blurb, 12, K.MUTED)
	bl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bl)
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_select_template(t.id, {})
			Tut.fire("tpl:" + str(t.id)))
	tpl_buttons[t.id] = p
	return p

# 缺词总数（用于“自动凑词”）
func _missing_total(tid: String, p: Dictionary) -> int:
	var sk := R.build(tid, p)
	var miss := G.missing(sk.words, avail_for_slot())
	var n := 0
	for w in miss:
		n += int(miss[w])
	return n

# 新选一个模板时：若默认参数凑不出词，就在各个“选项型”参数里挑缺词最少的取值
func _auto_fit(tid: String, p: Dictionary) -> Dictionary:
	var cur := p.duplicate()
	var best := _missing_total(tid, cur)
	if best == 0:
		return cur
	for prm in R.template(tid).params:
		if prm.kind != "enum":
			continue
		for o in prm.options:
			var trial := cur.duplicate()
			trial[prm.key] = o[0]
			var m := _missing_total(tid, trial)
			if m < best:
				best = m
				cur = trial
		if best == 0:
			break
	return cur

func _select_template(tid: String, params: Dictionary) -> void:
	sel_tid = tid
	sel_params = R.defaults(tid)
	for k in params:
		sel_params[k] = params[k]
	if params.is_empty():
		sel_params = _auto_fit(tid, sel_params)
	for id in tpl_buttons:
		var t: Dictionary = R.template(id)
		var fam_col: Color = {"攻": Color("8a3a36"), "守": Color("2f7a55"), "控": Color("2f7a7a"), "反": Color("7a4aa0")}.get(t.family, K.EDGE)
		tpl_buttons[id].add_theme_stylebox_override("panel", K.style(Color("2c3552") if id == tid else Color("1f2538"), K.GOLD if id == tid else fam_col, 10, 3 if id == tid else 2, 3))
	_rebuild_params()
	_update_preview()

func _load_slot() -> void:
	var sk := _current_skill()
	sel_name = str(sk.get("name", "")) if sk.get("custom_name", false) else ''
	if sk.is_empty():
		_select_template(sel_tid if sel_tid != "" else "atk1", {})
	elif sk.has("template"):
		_select_template(sk.template, sk.params)
	else:
		_select_template(sel_tid, {})
	if tab == "complex":
		complex_root.load_skill(sk, avail_for_slot(), _points_other())

func _rebuild_params() -> void:
	K.clear_children(param_box)
	var t: Dictionary = R.template(sel_tid)
	param_box.add_child(K.label("%s  ·  %s" % [t.title, t.family], 22, K.GOLD))
	param_box.add_child(K.wrap_label(t.blurb, 15, K.MUTED))
	var nm := K.hbox(8)
	nm.add_child(K.label("技能名", 16, K.TEXT))
	skill_name_edit = LineEdit.new()
	skill_name_edit.max_length = 10
	skill_name_edit.placeholder_text = String(t.title)
	skill_name_edit.text = sel_name
	skill_name_edit.custom_minimum_size = Vector2(170, 32)
	skill_name_edit.text_changed.connect(func(tx): sel_name = tx.strip_edges())
	nm.add_child(skill_name_edit)
	var sdice := K.button("随机", "normal", 16)
	sdice.custom_minimum_size = Vector2(44, 32)
	sdice.tooltip_text = "按这个技能的效果随机取一个名字"
	sdice.pressed.connect(func():
		_rng.randomize()
		sel_name = Namer.skill_name(preview_skill, _rng)
		skill_name_edit.text = sel_name
		Tut.fire("dice"))
	nm.add_child(sdice)
	Tut.tag(nm, "e:name")
	param_box.add_child(nm)
	for prm in t.params:
		var row := K.hbox(8)
		var lab := K.label(prm.label, 16, K.TEXT)
		lab.custom_minimum_size.x = 150
		row.add_child(lab)
		match prm.kind:
			"enum":
				var ob := OptionButton.new()
				ob.add_theme_font_size_override("font_size", 16)
				var sel := 0
				for i in prm.options.size():
					ob.add_item(prm.options[i][1])
					ob.set_item_metadata(i, prm.options[i][0])
					if str(prm.options[i][0]) == str(sel_params[prm.key]):
						sel = i
				ob.select(sel)
				ob.item_selected.connect(func(i):
					sel_params[prm.key] = ob.get_item_metadata(i)
					_update_preview()
					Tut.fire("param:%s:%s" % [prm.key, str(ob.get_item_metadata(i))]))
				ob.custom_minimum_size.x = 220
				row.add_child(ob)
			"int":
				var sl := HSlider.new()
				sl.min_value = prm.min
				sl.max_value = prm.max
				sl.step = 1
				sl.value = int(sel_params[prm.key])
				sl.custom_minimum_size = Vector2(240, 28)
				var val := K.label(str(int(sel_params[prm.key])), 20, K.GOLD)
				val.custom_minimum_size.x = 40
				sl.value_changed.connect(func(v):
					sel_params[prm.key] = int(v)
					val.text = str(int(v))
					_update_preview()
					Tut.fire("param:%s:%d" % [prm.key, int(v)]))
				row.add_child(sl)
				row.add_child(val)
			"bool":
				var cb := CheckBox.new()
				cb.button_pressed = bool(sel_params[prm.key])
				cb.toggled.connect(func(on):
					sel_params[prm.key] = on
					_update_preview())
				row.add_child(cb)
		Tut.tag(row, "e:param:" + str(prm.key))
		param_box.add_child(row)

func _update_preview() -> void:
	if preview_box == null:
		return
	K.clear_children(preview_box)
	preview_skill = R.build(sel_tid, sel_params)
	Tut.vars["cost"] = int(preview_skill.cost)
	Tut.vars["nums"] = int(preview_skill.ap_nums)
	Tut.vars["price"] = int(preview_skill.price)
	Tut.vars["windup"] = int(preview_skill.windup)
	Tut.tag(preview_box, "e:preview")
	_render_skill_preview(preview_box, preview_skill, ("装入技能槽 %d" % (slot + 1)) if D.MAX_SKILLS > 1 else "装上这个技能", func():
		_install(preview_skill))
	_refresh_info()

func _render_skill_preview(box: VBoxContainer, sk: Dictionary, btn_text: String, on_install: Callable) -> void:
	var avail := avail_for_slot()
	box.add_child(K.label("预览", 15, K.MUTED))
	box.add_child(K.wrap_label(sk.text, 19, K.TEXT))
	var stats := K.hbox(8)
	stats.add_child(K.chip("操作费 %d" % int(sk.cost), Color("6b5a22"), 16))
	stats.add_child(K.chip("起手 ≥ %d 秒" % int(sk.windup), Color("2f5f93"), 16))
	stats.add_child(K.chip("占用点数 %d" % int(sk.budget), Color("4a4f66"), 16))
	box.add_child(stats)
	box.add_child(K.label("所需词（绿=有，红=缺）", 15, K.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var cnt := G.count_words(sk.words)
	var keys: Array = cnt.keys()
	keys.sort_custom(func(a, b): return Lex.words[a].id < Lex.words[b].id)
	var miss := G.missing(sk.words, avail)
	for w in keys:
		flow.add_child(K.word_tag(w, not miss.has(w), int(cnt[w])))
	box.add_child(flow)
	var probs := G.problems(sk)
	var over: bool = _points_other() - _slot_budget() + int(sk.budget) > D.BUDGET
	var ok := miss.is_empty() and probs.is_empty() and not over
	if probs.is_empty():
		var rb := K.vbox(3)
		box.add_child(rb)
		appraise_into(rb, sk)
	if not miss.is_empty():
		var t := "缺少："
		for w in miss:
			t += "%s×%d  " % [w, miss[w]]
		box.add_child(K.wrap_label(t, 15, K.RED))
	for pr in probs:
		box.add_child(K.wrap_label("× " + str(pr), 15, K.RED))
	if over:
		box.add_child(K.wrap_label("点数超出预算：请减少生命或填入的数字", 15, K.RED))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sp)
	var b := K.button(btn_text, "primary" if ok else "normal", 20)
	b.disabled = not ok
	b.pressed.connect(on_install)
	Tut.tag(b, "e:install")
	box.add_child(b)

func _slot_budget() -> int:
	return int(work.skills[slot].budget) if slot < work.skills.size() else 0

func _install(sk: Dictionary) -> void:
	var copy: Dictionary = sk.duplicate(true)
	if tab == "simple" and sel_name != "":
		copy["name"] = sel_name
		copy["base_name"] = sel_name
		copy["custom_name"] = true
	if slot < work.skills.size():
		work.skills[slot] = copy
	else:
		work.skills.append(copy)
		slot = work.skills.size() - 1
	_refresh_left()
	_update_preview()
	Tut.fire("installed")

func _on_complex_changed(sk: Dictionary) -> void:
	# 复杂版点“装入”时给出完整技能
	_install(sk)

func _refresh_info() -> void:
	K.clear_children(info_box)
	var pts := _points_other()
	var v := D.validate({"units": _merged_units()}, pool)
	if v.ok:
		info_box.add_child(K.label("当前牌组合法。", 16, K.GREEN))
	else:
		for e in v.errors.slice(0, 3):
			info_box.add_child(K.label("· " + str(e), 15, K.RED))
	btn_commit.disabled = not v.ok
	btn_commit.tooltip_text = "" if v.ok else "牌组还不合法，无法确认"

func _merged_units() -> Array:
	var units: Array = []
	for i in base_deck.units.size():
		units.append(work if i == unit_idx else base_deck.units[i])
	return units

# ---------------------------------------------------------------- 强度回执（两个编辑页共用）
func appraise_into(box: VBoxContainer, sk: Dictionary) -> void:
	box.add_child(K.label("强度回执：计算中…", 14, K.MUTED))
	_ap_token += 1
	var tok := _ap_token
	if is_inside_tree():
		await get_tree().create_timer(0.3).timeout
	if tok != _ap_token or not is_instance_valid(box):
		return
	var work_copy: Dictionary = work.duplicate(true)
	var info: Dictionary = Appraise.appraise(sk, base_deck, unit_idx, work_copy)
	if not is_instance_valid(box):
		return
	K.clear_children(box)
	var panel := K.panel(Color("2a2414") if info.big else Color("17202e"), K.GOLD if info.big else Color("2f5f93"), 8, 2 if info.big else 1)
	var v := K.vbox(3)
	panel.add_child(v)
	v.add_child(K.label("★ 超级厉害的技能！" if info.big else "强度回执", 16, K.GOLD))
	if info.summary != "":
		v.add_child(K.wrap_label("预计（对手不动时）：" + str(info.summary) + "。", 14, K.TEXT))
	if info.ok and int(info.best.get("dmg", 0)) + int(info.best.get("score", 0)) > 0:
		if info.counters.is_empty():
			v.add_child(K.wrap_label("对手现在公开的牌里：没有能拆它的招！", 14, K.GREEN))
		else:
			var names: Array = []
			for c in info.counters:
				names.append("【%s】" % c.name)
			v.add_child(K.wrap_label("对手现在公开的牌里能削弱它的：" + "、".join(names), 14, Color("e8b0aa")))
	for w in info.weak.slice(0, 3):
		v.add_child(K.wrap_label("· 怕：" + str(w), 13, K.MUTED))
	box.add_child(panel)
	var sig := "%s|%d|%s" % [sk.get("text", ""), int(work.max_hp), str(info.summary)]
	if sig != _last_ap_sig and str(info.line) != "":
		_last_ap_sig = sig
		Pet.chat(str(info.line), "excited" if info.big else "talk", 7.0)
