extends Control
# 标题画面：漂浮的词卡作背景。

const K = preload("res://scripts/ui/kit.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const Settings = preload("res://scripts/ui/settings.gd")
const Sfx = preload("res://scripts/ui/sfx.gd")

signal start_game()
signal watch_demo()
signal start_tutorial()

var rules_panel: Control

func _ready() -> void:
	Lex.load_all()
	var bg := ColorRect.new()
	bg.color = K.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var float_layer := Control.new()
	float_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(float_layer)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var words: Array = Lex.implemented()
	for i in 26:
		var w: String = words[rng.randi() % words.size()]
		var c := K.word_card(w, 1, -1, Vector2(84, 110))
		c.modulate.a = rng.randf_range(0.10, 0.28)
		c.position = Vector2(rng.randf_range(0, 1500), rng.randf_range(0, 820))
		c.rotation = rng.randf_range(-0.4, 0.4)
		c.scale = Vector2.ONE * rng.randf_range(0.7, 1.4)
		float_layer.add_child(c)
		var t := c.create_tween().set_loops()
		var dy := rng.randf_range(-60, 60)
		t.tween_property(c, "position:y", c.position.y + dy, rng.randf_range(3.0, 6.0)).set_trans(Tween.TRANS_SINE)
		t.tween_property(c, "position:y", c.position.y - dy, rng.randf_range(3.0, 6.0)).set_trans(Tween.TRANS_SINE)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := K.vbox(14)
	v.custom_minimum_size = Vector2(520, 0)
	center.add_child(v)
	var title := K.label("词　战", 120, K.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_outline_color", Color("3a2d10"))
	title.add_theme_constant_override("outline_size", 12)
	v.add_child(title)
	v.add_child(K.label("拼　词　·　设　伏　·　见　招　拆　招", 26, K.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(K.spacer(24))
	var b1 := K.button("开始对局", "primary", 30)
	b1.custom_minimum_size = Vector2(0, 68)
	b1.pressed.connect(func(): start_game.emit())
	v.add_child(b1)
	Settings.load_all()
	var bt := K.button("新手教学（从头教起，约10分钟）" + ("" if Settings.tutorial_done else "  ← 第一次玩点这里"), "primary" if not Settings.tutorial_done else "normal", 22)
	bt.custom_minimum_size = Vector2(0, 52)
	bt.pressed.connect(func(): start_tutorial.emit())
	v.add_child(bt)
	var lv_row := K.hbox(8)
	lv_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var desc := K.label("", 15, K.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var lv_btns: Array = []
	var refresh_lv := func():
		for i in lv_btns.size():
			var b: Button = lv_btns[i]
			var active: bool = i == Settings.level
			b.add_theme_stylebox_override("normal", K.style(K.GOLD if active else K.PANEL2, Color("fff0c0") if active else K.EDGE, 10, 1, 4))
			b.add_theme_color_override("font_color", Color("20180a") if active else K.TEXT)
			b.add_theme_color_override("font_hover_color", Color("20180a") if active else K.TEXT)
		desc.text = "难度：" + Settings.LEVEL_DESC[Settings.level]
	for i in 3:
		var b := K.button(Settings.LEVEL_NAMES[i], "normal", 18)
		b.custom_minimum_size = Vector2(110, 38)
		lv_btns.append(b)
		lv_row.add_child(b)
		b.pressed.connect(func():
			Settings.level = i
			Settings.save_all()
			refresh_lv.call())
	var snd := K.button("音效：开" if not Settings.muted else "音效：关", "ghost", 16)
	snd.pressed.connect(func():
		Settings.muted = not Settings.muted
		Sfx.muted = Settings.muted
		Settings.save_all()
		snd.text = "音效：关" if Settings.muted else "音效：开")
	lv_row.add_child(snd)
	var cbtn := K.button("辅助轮：开" if Settings.coach else "辅助轮：关", "ghost", 16)
	cbtn.tooltip_text = "抽词/构筑时给出路线提示，并提供“自动组合”“换一批”。纯新手建议打开。"
	cbtn.pressed.connect(func():
		Settings.coach = not Settings.coach
		Settings.save_all()
		cbtn.text = "辅助轮：开" if Settings.coach else "辅助轮：关")
	lv_row.add_child(cbtn)
	v.add_child(lv_row)
	v.add_child(desc)
	refresh_lv.call()
	var b2 := K.button("玩法说明", "normal", 24)
	b2.custom_minimum_size = Vector2(0, 54)
	b2.pressed.connect(_show_rules)
	v.add_child(b2)
	var b3 := K.button("观战演示（电脑对电脑）", "ghost", 20)
	b3.pressed.connect(func(): watch_demo.emit())
	v.add_child(b3)
	var ver := K.label("原型 · Godot 4.7 · 词库 %d 词" % Lex.words.size(), 14, K.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(ver)
	rules_panel = Control.new()
	rules_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rules_panel.visible = false
	add_child(rules_panel)

func _show_rules() -> void:
	K.clear_children(rules_panel)
	rules_panel.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rules_panel.add_child(dim)
	var win := K.panel(Color("171b29"), K.GOLD_D, 18, 2, 18)
	win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win.offset_left = 150
	win.offset_right = -150
	win.offset_top = 40
	win.offset_bottom = -40
	rules_panel.add_child(win)
	var v := K.vbox(8)
	win.add_child(v)
	v.add_child(K.label("玩法说明", 34, K.GOLD))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var t := K.vbox(10)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(t)
	v.add_child(sc)
	var lines := [
		["目标", "双方各五张随从。每打倒一个敌人，得到它的生命上限那么多分；先到 100 分就赢（最多 10 轮，到时比分数）。倒下的随从休整一整轮后满血复出。全队同时倒下会一次性送给对手满额分数，还让你整整一轮无人可用，但不会直接结束比赛。"],
		["词就是资源", "技能不是固定的：你用抽到的词拼出来。每个词卡只能用在一个地方。每轮公开两袋词（各20张），先手先选一袋，另一袋归对手。"],
		["构筑点数", "100 点在五张卡的生命和技能里填入的数字之间分配。数字越大效果越强，但生命就少了。"],
		["操作费", "每次宣告技能要付行动点：5 点启动费 + 填入的数字 + 所用词卡的价格（词卡右下角的 ◆）。行动点每轮 +15，最多存 60。"],
		["起手", "操作费每 10 点需要 1 秒起手：大招慢，小招快。快招能抢在大招前面落地——打断它、延后它，或者先把减伤、改道布好。"],
		["先手与应对", "每轮各方可以宣告多个行动，只要付得起行动点（每个技能一轮一次）。先手先把行动宣告完，后手看见全部之后再宣告，然后双方行动沿同一条 20 秒时间轴一起结算。下一轮交换先手。每一轮都是干净的：监听、状态、护盾、减伤都只持续到本轮结束。"],
		["见招拆招", "对方的招式是公开的，卡面写多少就是多少，没有隐藏修正。想拆招就拼词：把伤害转移回去、转成治疗、按该次伤害回敬、打断、延后、沉默、易伤……任何组合都合法，放大也没有上限。"],
		["每轮调整", "每轮抽词后，双方交替公开地调整三次（每次改一张卡），用新词换掉旧技能。"],
		["两种编辑器", "简单版：选一个招式模板，像填空一样调参数。复杂版：自由拼节点树，监听里还能再装监听。两者做出的卡牌是同一种东西，可以互相接着改。"],
	]
	for l in lines:
		var row := K.hbox(14)
		var h := K.label(l[0], 20, K.GOLD)
		h.custom_minimum_size.x = 130
		row.add_child(h)
		var b := K.wrap_label(l[1], 18, K.TEXT)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		t.add_child(row)
	var close := K.button("明白了", "primary", 22)
	close.custom_minimum_size = Vector2(0, 48)
	close.pressed.connect(func(): rules_panel.visible = false)
	v.add_child(close)
