extends Control
# 复杂版编辑器：直接编辑技能的节点树。每个节点都是“一句话”，词由所选内容自动需要；
# 任何节点都能嵌套（监听器里可以再装监听器），层数不设上限。

const K = preload("res://scripts/ui/kit.gd")
const G = preload("res://scripts/core/grammar.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const D = preload("res://scripts/core/deck.gd")

signal changed(skill)

var nodes: Array = []
var avail: Dictionary = {}
var points_other := 0
var slot_old_budget := 0
var tree_box: VBoxContainer
var sum_box: VBoxContainer
var name_edit: LineEdit
var skill_name := "自拟招式"
var name_custom := false
const Namer = preload("res://scripts/core/namer.gd")

const TARGET_OPTS := [
	["自身", "self", "self"],
	["所选一个敌方", "choose", "enemy"], ["所选一个友方", "choose", "ally"],
	["全部敌方", "all", "enemy"], ["全部友方", "all", "ally"],
	["逐个敌方", "each", "enemy"], ["逐个友方", "each", "ally"],
	["最低生命敌方", "lowest", "enemy"], ["最低生命友方", "lowest", "ally"],
	["最高生命敌方", "highest", "enemy"], ["最高生命友方", "highest", "ally"],
	["最前敌方", "first", "enemy"], ["最前友方", "first", "ally"],
	["最后敌方", "last", "enemy"], ["最后友方", "last", "ally"],
	["随机敌方", "random", "enemy"], ["随机友方", "random", "ally"],
	["另一个友方", "other", "ally"],
]
const WATCH_TARGET_OPTS := [
	["来源", "source", "ref"], ["接受者", "recipient", "ref"],
	["与接受者相邻的友方", "adjacent", "ally"], ["与接受者相邻的敌方", "adjacent", "enemy"],
]
const KIND_TITLES := {
	"dmg": "造成伤害", "heal": "恢复生命", "mit": "减伤", "status": "施加状态", "remove": "移除", "watch": "当…就…（监听）",
	"time": "时间术", "swap": "换位", "split": "分流", "chain": "接续", "copy": "复制", "if": "若…否则…", "choose": "择一", "until": "直到…（重复）",
	"redirect": "转移", "convert": "转为治疗",
}
const EFFECT_KINDS := ["dmg", "heal", "mit", "status", "remove", "watch", "time", "swap", "split", "chain", "copy", "if", "choose", "until"]
const TIMED_KINDS := ["dmg", "heal"]
const KIND_COL := {
	"dmg": Color("8a3a36"), "heal": Color("2f7a55"), "mit": Color("2f5a8a"), "status": Color("8a6a2a"), "remove": Color("2f7a7a"),
	"watch": Color("7a4aa0"), "time": Color("2f7a7a"), "swap": Color("4a5a7a"), "split": Color("8a3a36"), "chain": Color("8a4a36"),
	"copy": Color("8a4a36"), "if": Color("5a6a3a"), "choose": Color("5a6a3a"), "until": Color("5a6a3a"), "redirect": Color("7a4aa0"), "convert": Color("7a4aa0"),
}

func _ready() -> void:
	_build()

func _build() -> void:
	if tree_box != null:
		return
	var v := K.hbox(12)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	# 左：树
	var left := K.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(left)
	var bar := K.hbox(8)
	bar.add_child(K.label("技能名", 16, K.MUTED))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(200, 34)
	name_edit.max_length = 10
	name_edit.text_changed.connect(func(t):
		skill_name = t
		name_custom = t.strip_edges() != "")
	bar.add_child(name_edit)
	var dice := K.button("随机", "normal", 16)
	dice.custom_minimum_size = Vector2(44, 34)
	dice.tooltip_text = "按这个技能的效果随机取一个名字"
	dice.pressed.connect(func():
		if nodes.is_empty():
			return
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		skill_name = Namer.skill_name(_sk(), rng)
		name_custom = true
		name_edit.text = skill_name
		_rerender())
	bar.add_child(dice)
	var add := MenuButton.new()
	add.text = "＋ 添加节点"
	add.flat = false
	add.add_theme_font_size_override("font_size", 17)
	add.add_theme_stylebox_override("normal", K.style(K.PANEL2, K.EDGE, 10, 1))
	var pop := add.get_popup()
	for k in EFFECT_KINDS:
		pop.add_item(KIND_TITLES[k])
	pop.id_pressed.connect(func(i):
		nodes.append(_new_node(EFFECT_KINDS[i]))
		_rerender())
	bar.add_child(add)
	var hint := K.label("多个节点用「并」连在同一个技能里，自动计词", 14, K.MUTED)
	bar.add_child(hint)
	left.add_child(bar)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tree_box = K.vbox(8)
	tree_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(tree_box)
	left.add_child(sc)
	# 右：汇总
	var right := K.panel(K.PANEL, K.EDGE, 12, 1)
	right.custom_minimum_size = Vector2(380, 0)
	sum_box = K.vbox(8)
	right.add_child(sum_box)
	v.add_child(right)

func load_skill(sk: Dictionary, avail_words: Dictionary, pts_other: int) -> void:
	_build()
	avail = avail_words
	points_other = pts_other
	nodes = sk.nodes.duplicate(true) if sk.has("nodes") else []
	skill_name = sk.get("name", "自拟招式") if sk.has("nodes") else "自拟招式"
	name_custom = bool(sk.get("custom_name", false))
	slot_old_budget = int(sk.get("budget", 0))
	name_edit.text = skill_name
	_rerender()

# ------------------------------------------------------------ 新节点
func _new_node(kind: String) -> Dictionary:
	match kind:
		"dmg": return G.dmg(G.T("choose", "enemy"), G.N(10))
		"heal": return G.heal(G.T("self", "self"), G.N(10))
		"mit": return G.mit(G.T("self", "self"), "pct", 20, 0)
		"status": return G.status("易伤", G.T("choose", "enemy"))
		"remove": return G.remove("限时效果", G.T("choose", "enemy"))
		"watch": return G.watch("damaged", G.T("self", "self"), G.dmg(G.T("source", "ref"), G.REF("event_damage")), {"freq": "every"})
		"time": return G.time_op("interrupt", "enemy", 30)
		"swap": return G.swap(G.T("choose", "ally"))
		"split": return G.split("dmg", 20, [{"target": G.T("choose", "enemy"), "part": 12, "delay": 0}, {"target": G.T("lowest", "enemy"), "part": 8, "delay": 0}])
		"chain": return G.chain(G.dmg(G.T("choose", "enemy"), G.N(10)), G.heal(G.T("self", "self"), G.REF("prev")))
		"copy": return G.copy_to(G.dmg(G.T("choose", "enemy"), G.N(10)), G.T("lowest", "enemy"))
		"if": return G.if_node({"left": G.REF("cur_hp", G.T("self", "self")), "cmp": "lt", "right": G.N(10)}, G.heal(G.T("self", "self"), G.N(10)))
		"until": return G.until_node(G.cmp_cond(G.REF("cur_hp", G.T("lowest", "enemy")), "lt", G.N(5)), G.dmg(G.T("lowest", "enemy"), G.N(8)))
		"choose": return G.pick_one(G.dmg(G.T("choose", "enemy"), G.N(10)), G.heal(G.T("self", "self"), G.N(10)))
		"redirect": return G.redirect(G.T("source", "ref"))
		"convert": return G.convert_heal()
	return {}

# ------------------------------------------------------------ 渲染
func _rerender() -> void:
	K.clear_children(tree_box)
	for i in nodes.size():
		var idx := i
		tree_box.add_child(_node_card(nodes[i], "", false, func(): _rerender(), func():
			nodes.remove_at(idx)
			_rerender()))
	if nodes.is_empty():
		tree_box.add_child(K.label("还没有节点。点「＋ 添加节点」开始拼一个技能。", 17, K.MUTED))
	_render_summary()

func _sk() -> Dictionary:
	var sk := G.skill(skill_name if skill_name.strip_edges() != "" else "自拟招式", nodes.duplicate(true))
	if name_custom:
		sk["custom_name"] = true
		sk["base_name"] = sk.name
	return G.finalize(sk)

func _render_summary() -> void:
	K.clear_children(sum_box)
	sum_box.add_child(K.label("技能汇总", 20, K.GOLD))
	if nodes.is_empty():
		sum_box.add_child(K.label("（空）", 16, K.MUTED))
		return
	var sk := _sk()
	sum_box.add_child(K.wrap_label(sk.text, 17, K.TEXT))
	var stats := K.hbox(6)
	stats.add_child(K.chip("操作费 %d" % int(sk.cost), Color("6b5a22"), 15))
	stats.add_child(K.chip("起手≥%d秒" % int(sk.windup), Color("2f5f93"), 15))
	stats.add_child(K.chip("点数 %d" % int(sk.budget), Color("4a4f66"), 15))
	sum_box.add_child(stats)
	sum_box.add_child(K.label("所需词", 15, K.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	var cnt := G.count_words(sk.words)
	var keys: Array = cnt.keys()
	keys.sort_custom(func(a, b): return Lex.words[a].id < Lex.words[b].id)
	var miss := G.missing(sk.words, avail)
	for w in keys:
		flow.add_child(K.word_tag(w, not miss.has(w), int(cnt[w])))
	sum_box.add_child(flow)
	var probs := G.problems(sk)
	for p in probs:
		sum_box.add_child(K.wrap_label("× " + str(p), 14, K.RED))
	if not miss.is_empty():
		var t := "缺："
		for w in miss:
			t += "%s×%d " % [w, miss[w]]
		sum_box.add_child(K.wrap_label(t, 14, K.RED))
	var over: bool = points_other - 0 + int(sk.budget) > D.BUDGET
	if over:
		sum_box.add_child(K.wrap_label("点数超出预算", 14, K.RED))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sum_box.add_child(sp)
	var ok := probs.is_empty() and miss.is_empty() and not over
	var b := K.button("装入技能槽", "primary" if ok else "normal", 20)
	b.disabled = not ok
	b.pressed.connect(func(): changed.emit(_sk()))
	sum_box.add_child(b)

# 节点卡片。ctx：所在监听器的事件名（空串=顶层）。
func _node_card(node: Dictionary, ctx: String, nested: bool, on_change: Callable, on_delete: Callable, allow_prev: bool = false) -> Control:
	var kind: String = node.kind
	var col: Color = KIND_COL.get(kind, K.EDGE)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", K.style(Color("1e2436") if not nested else Color("232b40"), col, 10, 2))
	var v := K.vbox(6)
	p.add_child(v)
	var head := K.hbox(8)
	head.add_child(K.chip(KIND_TITLES[kind], col, 15))
	var ptxt := K.label(_short(node), 14, K.MUTED)
	ptxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ptxt.clip_text = true
	head.add_child(ptxt)
	if on_delete.is_valid():
		var del := K.button("×", "ghost", 14)
		del.custom_minimum_size = Vector2(32, 26)
		del.pressed.connect(on_delete)
		head.add_child(del)
	v.add_child(head)
	var in_watch := ctx != ""
	var chg := on_change
	if kind in TIMED_KINDS and not nested:
		v.add_child(_timing_row(node, true, chg))
	match kind:
		"dmg", "heal":
			v.add_child(_row("写法", _enum(["造成伤害" if kind == "dmg" else "恢复生命", "减少当前生命" if kind == "dmg" else "增加当前生命"], int(node.get("alt", 0)), func(i):
				node["alt"] = i
				chg.call())))
			v.add_child(_row("目标", _target(node.target, in_watch, chg)))
			v.add_child(_row("数值", _value(node.value, ctx, chg, allow_prev)))
			var r2 := K.hbox(12)
			r2.add_child(_row("双倍", _spin(int(node.get("dbl", 0)), 0, 4, func(x):
				node["dbl"] = x
				chg.call())))
			r2.add_child(_row("一半", _spin(int(node.get("half", 0)), 0, 3, func(x):
				node["half"] = x
				chg.call())))
			r2.add_child(_row("重复", _spin(int(node.get("rep", 0)), 0, 4, func(x):
				node["rep"] = x
				chg.call())))
			v.add_child(r2)
			var r3 := K.hbox(12)
			r3.add_child(_row("重复间隔(秒,0=默认2)", _spin(int(node.get("rep_gap", 0)), 0, 9, func(x):
				node["rep_gap"] = x
				chg.call())))
			r3.add_child(_row("延后(秒)", _spin(int(node.get("delay", 0)), 0, 19, func(x):
				node["delay"] = x
				chg.call())))
			v.add_child(r3)
		"mit":
			v.add_child(_row("目标", _target(node.target, in_watch, chg)))
			v.add_child(_row("方式", _enum(["按比例", "每次固定"], 0 if node.mode == "pct" else 1, func(i):
				node["mode"] = "pct" if i == 0 else "fixed"
				chg.call())))
			var r := K.hbox(12)
			r.add_child(_row("投入", _spin(int(node.value.n), 1, 80, func(x):
				node.value["n"] = x
				chg.call())))
			r.add_child(_row("持续(秒,0=本轮)", _spin(int(node.dur), 0, 20, func(x):
				node["dur"] = x
				chg.call())))
			r.add_child(_row("双倍", _spin(int(node.get("dbl", 0)), 0, 3, func(x):
				node["dbl"] = x
				chg.call())))
			v.add_child(r)
		"status":
			v.add_child(_row("状态", _enum(G.STATUSES, G.STATUSES.find(node.status), func(i):
				node["status"] = G.STATUSES[i]
				if node.status == "牵连" and not node.has("link"):
					node["link"] = G.T("other", "ally")
				elif node.status != "牵连":
					node.erase("link")
				chg.call())))
			v.add_child(_row("目标", _target(node.target, in_watch, chg)))
			if node.status == "牵连":
				v.add_child(_row("牵连对象", _target(node.get("link", G.T("other", "ally")), in_watch, chg)))
			var r4 := K.hbox(12)
			r4.add_child(_row("持续(秒,0=本轮)", _spin(int(node.dur), 0, 20, func(x):
				node["dur"] = x
				chg.call())))
			if node.status == "护盾" or node.status == "沉默":
				r4.add_child(_row("吸收" if node.status == "护盾" else "力度", _spin(int(node.value.n), 1, 80, func(x):
					node.value["n"] = x
					chg.call())))
				r4.add_child(_row("双倍", _spin(int(node.get("dbl", 0)), 0, 3, func(x):
					node["dbl"] = x
					chg.call())))
			v.add_child(r4)
		"remove":
			v.add_child(_row("移除", _enum(["限时效果", "状态"], 0 if node.what == "限时效果" else 1, func(i):
				node["what"] = "限时效果" if i == 0 else "状态"
				chg.call())))
			v.add_child(_row("目标", _target(node.target, in_watch, chg)))
		"watch":
			var events: Array = G.EVENT_TEXT.keys()
			var labels: Array = []
			for e in events:
				labels.append(G.EVENT_TEXT[e])
			v.add_child(_row("当", _enum(labels, events.find(node.event), func(i):
				node["event"] = events[i]
				if node.child.kind in ["redirect", "convert"] and events[i] != "pending_dmg":
					node["child"] = G.dmg(G.T("source", "ref"), G.REF("event_damage")) if events[i] in ["damaged", "dealt", "lost"] else G.dmg(G.T("source", "ref"), G.N(10))
				chg.call())))
			if not (node.event in G.NO_OBSERVE):
				v.add_child(_row("监听对象", _target(node.observe, in_watch, chg)))
			var r5 := K.hbox(12)
			r5.add_child(_row("次数", _enum(["第一次", "每次"], 1 if node.freq == "every" else 0, func(i):
				node["freq"] = "every" if i == 1 else "once"
				chg.call())))
			r5.add_child(_row("有效期", _enum(["到本轮结束", "限定秒数（不跨轮）"], ["round", "dur"].find(node.life), func(i):
				node["life"] = ["round", "dur"][i]
				if node.life == "dur" and int(node.dur) < 1:
					node["dur"] = 10
				chg.call())))
			if node.life == "dur":
				r5.add_child(_row("秒", _spin(int(node.dur), 1, 20, func(x):
					node["dur"] = x
					chg.call())))
			v.add_child(r5)
			v.add_child(_row("延后(秒)", _spin(int(node.get("delay", 0)), 0, 19, func(x):
				node["delay"] = x
				chg.call())))
			v.add_child(K.label("就：", 15, K.GOLD))
			v.add_child(_child_slot(node, "child", node.event, chg, node.event == "pending_dmg"))
		"redirect":
			v.add_child(_row("转给", _target(node.target, true, chg)))
			v.add_child(_row("每个被保护者至多转移", _spin(int(node.value.n), 1, 80, func(x):
				node.value["n"] = x
				chg.call())))
			v.add_child(_row("双倍", _spin(int(node.get("dbl", 0)), 0, 3, func(x):
				node["dbl"] = x
				chg.call())))
		"convert":
			v.add_child(K.label("把这次伤害改写成等量治疗（词：转为 恢复 生命）", 14, K.MUTED))
			v.add_child(_row("每个被保护者至多转换", _spin(int(node.value.n), 1, 80, func(x):
				node.value["n"] = x
				chg.call())))
			v.add_child(_row("双倍", _spin(int(node.get("dbl", 0)), 0, 3, func(x):
				node["dbl"] = x
				chg.call())))
		"time":
			v.add_child(_row("方式", _enum(["打断", "延后", "提前"], ["interrupt", "delay", "advance"].find(node.op), func(i):
				node["op"] = ["interrupt", "delay", "advance"][i]
				node["side"] = "ally" if node.op == "advance" else "enemy"
				if node.op == "interrupt":
					node.value["n"] = maxi(int(node.value.n), 20)
				elif int(node.value.n) < 1 or int(node.value.n) > 19:
					node.value["n"] = 3
				chg.call())))
			v.add_child(_row("对象", _enum(["对方技能", "己方技能"], 0 if node.side == "enemy" else 1, func(i):
				node["side"] = "enemy" if i == 0 else "ally"
				chg.call())))
			v.add_child(_row("打断力度" if node.op == "interrupt" else "秒数", _spin(int(node.value.n), 1, 80 if node.op == "interrupt" else 19, func(x):
				node.value["n"] = x
				chg.call())))
			if node.op == "interrupt":
				v.add_child(_row("双倍", _spin(int(node.get("dbl", 0)), 0, 3, func(x):
					node["dbl"] = x
					chg.call())))
			v.add_child(_row("延后(秒)", _spin(int(node.get("delay", 0)), 0, 19, func(x):
				node["delay"] = x
				chg.call())))
		"swap":
			v.add_child(_row("与谁换位", _target(node.target, in_watch, chg)))
		"split":
			v.add_child(_row("类型", _enum(["伤害", "治疗"], 0 if node.verb == "dmg" else 1, func(i):
				node["verb"] = "dmg" if i == 0 else "heal"
				chg.call())))
			v.add_child(_row("总额", _spin(int(node.total), 2, 80, func(x):
				node["total"] = x
				var first: int = int(ceil(x * 0.6))
				node.branches[0]["part"] = first
				node.branches[1]["part"] = x - first
				chg.call())))
			for bi in 2:
				var b: Dictionary = node.branches[bi]
				var rr := K.hbox(8)
				rr.add_child(K.label("分支%d" % (bi + 1), 15, K.GOLD))
				rr.add_child(_target(b.target, in_watch, chg))
				rr.add_child(_row("份额", _spin(int(b.part), 0, int(node.total), func(x):
					b["part"] = x
					var other: int = 1 - bi
					node.branches[other]["part"] = int(node.total) - x
					chg.call())))
				rr.add_child(_row("延后", _spin(int(b.get("delay", 0)), 0, 19, func(x):
					b["delay"] = x
					chg.call())))
				v.add_child(rr)
		"chain":
			v.add_child(K.label("先：", 15, K.GOLD))
			v.add_child(_child_slot(node, "first", ctx, chg, false, ["dmg", "heal"]))
			v.add_child(K.label("再以其实际数值：", 15, K.GOLD))
			v.add_child(_child_slot(node, "then", ctx, chg, false, ["dmg", "heal", "status"]))
		"copy":
			v.add_child(K.label("先：", 15, K.GOLD))
			v.add_child(_child_slot(node, "first", ctx, chg, false, ["dmg", "heal"]))
			v.add_child(_row("把实际数值复制给", _target(node.target, in_watch, chg)))
		"until":
			v.add_child(K.label("反复执行下面的效果（每次重新付数字，至多再重复 %d 次），直到：" % G.UNTIL_MAX, 15, K.GOLD))
			v.add_child(_cond_editor(node.cond, ctx, chg, allow_prev))
			v.add_child(_row("间隔(秒,0=默认2)", _spin(int(node.get("gap", 0)), 0, 9, func(x):
				node["gap"] = x
				chg.call())))
			v.add_child(_child_slot(node, "child", ctx, chg, false, ["dmg", "heal", "mit", "status", "split", "chain", "copy"]))
		"if":
			v.add_child(K.label("若：", 15, K.GOLD))
			v.add_child(_cond_editor(node.cond, ctx, chg, allow_prev))
			v.add_child(K.label("则：", 15, K.GOLD))
			v.add_child(_child_slot(node, "then", ctx, chg, false))
			var has_else: bool = node.has("else")
			var cb := CheckBox.new()
			cb.text = "否则…"
			cb.button_pressed = has_else
			cb.toggled.connect(func(on):
				if on:
					node["else"] = G.heal(G.T("self", "self"), G.N(5))
				else:
					node.erase("else")
				chg.call())
			v.add_child(cb)
			if has_else:
				v.add_child(_child_slot(node, "else", ctx, chg, false))
		"choose":
			v.add_child(K.label("宣告时二选一（只付所选的数字）：", 15, K.GOLD))
			v.add_child(K.label("分支 A：", 15, K.GOLD))
			v.add_child(_child_slot(node, "a", ctx, chg, false))
			v.add_child(K.label("分支 B：", 15, K.GOLD))
			v.add_child(_child_slot(node, "b", ctx, chg, false))
	return p

# 同时：重复/逐个一起落下（落点的时间由宣告时的“起效时间”决定，不由词决定）
func _timing_row(node: Dictionary, with_sync: bool, chg: Callable) -> Control:
	var r := K.hbox(10)
	if with_sync:
		var cs := CheckBox.new()
		cs.text = "同时（重复/逐个一起落）"
		cs.button_pressed = bool(node.get("sync", false))
		cs.toggled.connect(func(on):
			if on:
				node["sync"] = true
			else:
				node.erase("sync")
			chg.call())
		r.add_child(cs)
	return r

# 条件：比较，或“已生效”（目标身上有某状态）
func _cond_editor(c: Dictionary, ctx: String, chg: Callable, allow_prev: bool) -> Control:
	var box := K.vbox(4)
	var is_has: bool = c.has("has")
	box.add_child(_row("条件类型", _enum(["比较两个数", "已生效（有某状态）"], 1 if is_has else 0, func(i):
		if i == 1 and not c.has("has"):
			c.clear()
			c["has"] = {"target": G.T("self", "self"), "status": "易伤"}
		elif i == 0 and c.has("has"):
			c.clear()
			c["left"] = G.REF("cur_hp", G.T("self", "self"))
			c["cmp"] = "lt"
			c["right"] = G.N(10)
		chg.call())))
	if is_has:
		box.add_child(_row("目标", _target(c.has.target, ctx != "", chg)))
		box.add_child(_row("状态", _enum(G.STATUSES, G.STATUSES.find(c.has.status), func(i):
			c.has["status"] = G.STATUSES[i]
			chg.call())))
	else:
		box.add_child(_row("左值", _value(c.left, ctx, chg, allow_prev)))
		box.add_child(_row("比较", _enum(["小于", "不小于"], 0 if c.cmp == "lt" else 1, func(i):
			c["cmp"] = "lt" if i == 0 else "ge"
			chg.call())))
		box.add_child(_row("右值", _value(c.right, ctx, chg, allow_prev)))
	return box

func _child_slot(parent: Dictionary, key: String, ctx: String, chg: Callable, allow_rewrite: bool, kinds: Array = []) -> Control:
	var child_ctx := ctx
	if parent.kind == "watch":
		child_ctx = parent.event
	var allowed: Array = kinds if not kinds.is_empty() else EFFECT_KINDS.duplicate()
	if allow_rewrite:
		allowed = allowed + ["redirect", "convert"]
	var holder := K.vbox(4)
	var node: Dictionary = parent[key]
	var card := _node_card(node, child_ctx, true, chg, Callable(), parent.kind == "chain" and key == "then")
	# 换类型
	var mb := MenuButton.new()
	mb.text = "换成其他类型…"
	mb.add_theme_font_size_override("font_size", 14)
	mb.add_theme_stylebox_override("normal", K.style(K.PANEL2, K.EDGE, 8, 1))
	var pop := mb.get_popup()
	for k in allowed:
		pop.add_item(KIND_TITLES[k])
	pop.id_pressed.connect(func(i):
		var nn := _new_node(allowed[i])
		if parent.kind == "chain" and key == "then" and nn.kind in ["dmg", "heal"]:
			nn["value"] = G.REF("prev")
		if parent.kind == "watch" and nn.kind in ["dmg", "heal"] and parent.event in ["damaged", "dealt", "lost", "pending_dmg"] and nn.kind == "dmg":
			nn["value"] = G.REF("event_damage")
		parent[key] = nn
		chg.call())
	holder.add_child(card)
	holder.add_child(mb)
	return holder

func _short(node: Dictionary) -> String:
	if node.kind in ["redirect", "convert", "time", "swap", "remove", "status", "mit", "dmg", "heal"]:
		return G.node_text(node)
	return ""

# ------------------------------------------------------------ 小控件
func _row(label: String, ctrl: Control) -> Control:
	var h := K.hbox(6)
	h.add_child(K.label(label, 15, K.MUTED))
	h.add_child(ctrl)
	return h

func _enum(labels: Array, sel: int, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.add_theme_font_size_override("font_size", 15)
	for l in labels:
		ob.add_item(str(l))
	ob.select(maxi(sel, 0))
	ob.item_selected.connect(on_pick)
	return ob

func _spin(v: int, lo: int, hi: int, on_change: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = v
	s.custom_minimum_size.x = 90
	s.value_changed.connect(func(x): on_change.call(int(x)))
	return s

func _target(spec: Dictionary, in_watch: bool, on_change: Callable) -> OptionButton:
	var opts: Array = TARGET_OPTS.duplicate()
	if in_watch:
		opts = WATCH_TARGET_OPTS + opts
	var sel := 0
	var labels: Array = []
	for i in opts.size():
		labels.append(opts[i][0])
		if opts[i][1] == spec.get("pick", "") and opts[i][2] == spec.get("side", ""):
			sel = i
	var ob := _enum(labels, sel, func(i):
		spec["pick"] = opts[i][1]
		spec["side"] = opts[i][2]
		spec.erase("center")
		if opts[i][1] == "adjacent":
			spec["center"] = "recipient"
		on_change.call())
	return ob

func _ref_opts(ctx: String, allow_prev: bool) -> Array:
	var out: Array = []
	if ctx in ["damaged", "dealt", "lost", "pending_dmg"]:
		out += [["该次伤害", "event_damage"], ["实际数值", "actual"], ["原始数值", "raw"]]
	if ctx == "healed":
		out += [["该次治疗", "event_heal"], ["溢出", "overflow"]]
	if ctx != "":
		out.append(["次数", "times"])
	if allow_prev:
		out.append(["前一效果的实际数值", "prev"])
	out += [["当前生命", "cur_hp"], ["生命上限", "max_hp"], ["失去的生命", "lost_hp"], ["人数", "count"],
		["可用行动点", "ap"], ["支付的行动点", "paid"], ["已投入数字", "invested"],
		["本轮（累计受到的伤害）", "round_taken"], ["剩余（护盾量）", "remaining"]]
	return out

func _value(v: Dictionary, ctx: String, on_change: Callable, allow_prev: bool = false) -> Control:
	var h := K.hbox(6)
	var refs := _ref_opts(ctx, allow_prev)
	var labels: Array = ["填入数字"]
	for r in refs:
		labels.append(r[0])
	labels.append("运算")
	var sel := 0
	if v.k == "ref":
		for i in refs.size():
			if refs[i][1] == v.ref:
				sel = i + 1
	elif v.k == "op":
		sel = labels.size() - 1
	var ob := _enum(labels, sel, func(i):
		var keep_n: int = int(v.n) if v.k == "num" else 10
		for k in v.keys():
			v.erase(k)
		if i == 0:
			v["k"] = "num"
			v["n"] = keep_n
		elif i == labels.size() - 1:
			v["k"] = "op"
			v["op"] = "max"
			v["a"] = G.N(10)
			v["b"] = G.N(5)
		else:
			v["k"] = "ref"
			v["ref"] = refs[i - 1][1]
			if v.ref in ["cur_hp", "max_hp", "lost_hp", "round_taken", "remaining"]:
				v["of"] = G.T("self", "self")
			elif v.ref == "count":
				v["of"] = G.T("all", "enemy")
		on_change.call())
	h.add_child(ob)
	if v.k == "num":
		h.add_child(_spin(int(v.n), 0, 99, func(x):
			v["n"] = x
			on_change.call()))
	elif v.k == "ref" and v.has("of"):
		h.add_child(_target(v.of, ctx != "", on_change))
	elif v.k == "op":
		var col := K.vbox(4)
		col.add_child(_enum(["较高者", "较低者", "合计", "差值"], ["max", "min", "sum", "diff"].find(v.op), func(i):
			v["op"] = ["max", "min", "sum", "diff"][i]
			on_change.call()))
		col.add_child(_value(v.a, ctx, on_change, allow_prev))
		col.add_child(_value(v.b, ctx, on_change, allow_prev))
		h.add_child(col)
	return h
