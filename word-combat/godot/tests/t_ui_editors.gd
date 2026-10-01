extends SceneTree
# 编辑器压力测试：遍历所有招式模板与所有节点类型，确认不报错、生成的技能合法。
const G = preload("res://scripts/core/grammar.gd")
const R = preload("res://scripts/core/recipes.gd")
const D = preload("res://scripts/core/deck.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const EditorPopup = preload("res://scripts/ui/editor_popup.gd")
const Complex = preload("res://scripts/ui/complex_editor.gd")

var fails := 0

func check(c: bool, msg: String) -> void:
	if not c:
		print("  FAIL ", msg)
		fails += 1

func _init() -> void:
	Lex.load_all()
	# 1. 所有模板：默认参数与若干极端参数，构造出的技能必须结构合法
	for t in R.catalog():
		var p := R.defaults(t.id)
		var sk := R.build(t.id, p)
		var pr := G.problems(sk)
		check(pr.is_empty(), "模板 %s 默认参数应合法：%s" % [t.id, str(pr)])
		check(sk.words.size() > 0, "模板 %s 应需要词" % t.id)
		# 每个枚举参数的每个取值
		for prm in t.params:
			if prm.kind == "enum":
				for o in prm.options:
					var p2 := p.duplicate()
					p2[prm.key] = o[0]
					var sk2 := R.build(t.id, p2)
					var pr2 := G.problems(sk2)
					check(pr2.is_empty(), "模板 %s 参数 %s=%s 合法：%s" % [t.id, prm.key, str(o[0]), str(pr2)])
			elif prm.kind == "int":
				for v in [prm.min, prm.max]:
					var p3 := p.duplicate()
					p3[prm.key] = v
					var sk3 := R.build(t.id, p3)
					check(G.problems(sk3).is_empty(), "模板 %s 参数 %s=%d 合法" % [t.id, prm.key, v])
	print("模板检查完成，失败 ", fails)
	# 2. 弹窗：对每个模板走一遍“选择 → 预览 → 装入”
	var pool := {}
	for w in Lex.implemented():
		pool[w] = 6
	var deck := D.new_deck()
	var popup := EditorPopup.new()
	root.add_child(popup)
	popup.open(deck, 0, pool, "initial")
	for t in R.catalog():
		popup._select_template(t.id, {})
		check(not popup.preview_skill.is_empty(), "弹窗预览 " + t.id)
		popup._install(popup.preview_skill)
	check(popup.work.skills.size() >= 1, "弹窗装入后有技能")
	# 3. 复杂编辑器：每种节点
	var cx = popup.complex_root
	cx._build()
	cx.avail = pool
	cx.points_other = 0
	for k in Complex.EFFECT_KINDS:
		cx.nodes = [cx._new_node(k)]
		cx._rerender()
		var sk4: Dictionary = cx._sk()
		var pr4 := G.problems(sk4)
		check(pr4.is_empty(), "复杂编辑器新建节点 %s 合法：%s" % [k, str(pr4)])
		check(sk4.words.size() > 0 and sk4.text != "", "节点 %s 有词与文字" % k)
	# 嵌套：监听器里装监听器、择一里放分流
	var nested := G.watch("damaged", G.T("self", "self"), G.watch("healed", G.T("self", "self"), G.dmg(G.T("source", "ref"), G.N(3))))
	cx.nodes = [nested]
	cx._rerender()
	check(G.problems(cx._sk()).is_empty(), "监听器嵌套监听器合法 " + str(G.problems(cx._sk())))
	# 取名：每个模板都能随机出名字；自定义名字被保留且不加序号
	var Namer = load("res://scripts/core/namer.gd")
	var nrng := RandomNumberGenerator.new()
	nrng.seed = 5
	for t in R.catalog():
		var nm: String = Namer.skill_name(R.build(t.id, R.defaults(t.id)), nrng)
		check(nm != "" and nm.length() <= 6, "模板 %s 随机名 %s" % [t.id, nm])
	var uname: String = Namer.minion_name({"glyph": "剑", "skills": [R.build("atk1", {})]}, nrng)
	check(uname != "", "随从随机名 " + uname)
	popup.tab = "simple"
	popup._select_template("atk1", {})
	popup.sel_name = "我的绝招"
	popup.slot = 0
	popup._install(popup.preview_skill)
	check(popup.work.skills[0].name == "我的绝招" and popup.work.skills[0].get("custom_name", false), "自定义技能名写入")
	var dk := D.new_deck()
	dk.units[0].skills = [popup.work.skills[0].duplicate(true), popup.work.skills[0].duplicate(true)]
	D.rename_skills(dk)
	check(dk.units[0].skills[1].name == "我的绝招", "自定义名不加序号")
	print("编辑器测试完成，失败数 ", fails)
	quit(fails)
