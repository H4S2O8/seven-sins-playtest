extends SceneTree
# 描述可读性检查：从模板（随机参数）和随机复杂技能树生成上万条描述，按规则找“不像人话”的句子。
# 用法： -- [条数] [种子] [打印样例数]
const G = preload("res://scripts/core/grammar.gd")
const R = preload("res://scripts/core/recipes.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
var rng := RandomNumberGenerator.new()
func pick(a: Array):
	return a[rng.randi() % a.size()]
func rand_target_enemy() -> Dictionary:
	var o: Array = pick([["choose", "enemy"], ["all", "enemy"], ["all", "enemy"], ["each", "enemy"], ["lowest", "enemy"], ["highest", "enemy"], ["random", "enemy"], ["first", "enemy"], ["last", "enemy"]])
	return G.T(o[0], o[1])

func rand_attack() -> Dictionary:
	var nodes: Array = []
	var n_nodes := rng.randi_range(1, 3)
	for i in n_nodes:
		var r := rng.randf()
		if r < 0.45:
			var d := G.dmg(rand_target_enemy(), G.N(rng.randi_range(4, 30)))
			if rng.randf() < 0.5:
				d["dbl"] = rng.randi_range(1, 2)
			if rng.randf() < 0.35:
				d["rep"] = rng.randi_range(1, 2)
			if rng.randf() < 0.15:
				d["delay"] = rng.randi_range(1, 5)
			if rng.randf() < 0.25:
				d["sync"] = true
			nodes.append(d)
		elif r < 0.5:
			var low := G.T("lowest", "enemy")
			nodes.append(G.until_node(G.cmp_cond(G.REF("cur_hp", low), "lt", G.N(rng.randi_range(2, 8))), G.dmg(low, G.N(rng.randi_range(4, 12)))))
		elif r < 0.55:
			var total := rng.randi_range(8, 40)
			var a := rng.randi_range(2, total - 2)
			nodes.append(G.split("dmg", total, [{"target": rand_target_enemy(), "part": a, "delay": 0}, {"target": rand_target_enemy(), "part": total - a, "delay": rng.randi_range(0, 3)}]))
		elif r < 0.65:
			nodes.append(G.copy_to(G.dmg(rand_target_enemy(), G.N(rng.randi_range(5, 25))), rand_target_enemy()))
		elif r < 0.73:
			nodes.append(G.chain(G.dmg(rand_target_enemy(), G.N(rng.randi_range(5, 25))), G.dmg(rand_target_enemy(), G.REF("prev"), {"dbl": rng.randi_range(0, 1)})))
		elif r < 0.85:
			nodes.append(G.status(pick(["易伤", "狂振", "沉默"]), rand_target_enemy(), pick([0, 0, 6]), rng.randi_range(5, 30)))
		elif r < 0.92:
			nodes.append(G.time_op(pick(["delay", "interrupt"]), "enemy", rng.randi_range(5, 40)))
		else:
			# 监听型：受到伤害就反击 / 发动技能就惩罚
			var ev: String = pick(["damaged", "cast", "healed", "down"])
			var child := G.dmg(pick([G.T("source", "ref"), G.T("all", "enemy")]), G.N(rng.randi_range(5, 25)) if ev != "damaged" else G.REF("event_damage"), {"dbl": rng.randi_range(0, 1)})
			nodes.append(G.watch(ev, G.T("all", "ally") if ev != "cast" else G.T("all", "enemy"), child, {"freq": "every"}))
	return G.finalize(G.skill("随机进攻", nodes))

func rand_params(tid: String) -> Dictionary:
	var p := {}
	for prm in R.template(tid).params:
		match prm.kind:
			"enum": p[prm.key] = pick(prm.options)[0]
			"int": p[prm.key] = rng.randi_range(int(prm.min), int(prm.max))
			"bool": p[prm.key] = rng.randf() < 0.4
	return p

const BAD := ["×", "÷", "?", "(", ")", "【【", "】】", "较高者(", "实际数值，", "压制", "力度", "被保护者", "重新付", "逐个", "。。"]

func lint(t: String) -> Array:
	var out: Array = []
	for b in BAD:
		if t.find(b) >= 0 and not (b == "(" or b == ")") :
			out.append("含“%s”" % b)
	if t.find("(") >= 0:
		out.append("含半角括号")
	# 嵌套：【】里再出现【
	var depth := 0
	var maxd := 0
	for ch in t:
		if ch == "【": depth += 1; maxd = maxi(maxd, depth)
		elif ch == "】": depth -= 1
	if maxd > 1:
		out.append("【】嵌套")
	for part in t.split("；另外，"):
		if part.length() > 75:
			out.append("单句过长")
	if t.split("；另外，").size() > 3:
		out.append("效果过多")
	# 同一长短语重复出现 3 次以上
	for part2 in t.split("；另外，"):
		for ph in ["你选的一个敌方随从", "每一个敌方随从", "全部敌方随从", "你选的一个友方随从"]:
			if part2.count(ph) >= 3:
				out.append("重复“%s”" % ph)
	return out

func _init() -> void:
	Lex.load_all()
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 6000
	rng.seed = int(args[1]) if args.size() > 1 else 1
	var show := int(args[2]) if args.size() > 2 else 0
	var tids: Array = []
	for t in R.catalog():
		tids.append(t.id)
	var bad := 0
	var kinds := {}
	var samples: Array = []
	for i in n:
		var sk: Dictionary
		var src := "树"
		if i % 2 == 0:
			var tid: String = pick(tids)
			sk = R.build(tid, rand_params(tid))
			src = tid
		else:
			sk = rand_attack()
		var t: String = G.describe(sk)
		var pr := lint(t)
		if not pr.is_empty():
			bad += 1
			for k in pr:
				kinds[k] = int(kinds.get(k, 0)) + 1
			if samples.size() < 14:
				samples.append("[%s] %s  ⇒ %s" % [src, t, ",".join(pr)])
		elif show > 0 and i % int(maxf(1.0, n / float(show))) == 0:
			print("  ✓ [", src, "] ", t)
	print("共 %d 条，违规 %d（%.1f%%）" % [n, bad, 100.0 * bad / n])
	for k in kinds: print("  ", k, "：", kinds[k])
	for s in samples: print("  样例：", s)
	quit(1 if bad > n / 50 else 0)
