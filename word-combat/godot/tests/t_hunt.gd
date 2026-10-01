extends SceneTree
# 猎杀“无解的进攻”：随机生成大量进攻技能树，挑出得分高的，用反制库逐个去试；
# 记录所有“反制库里没有一个能化解”的结构。用法： -- [候选数] [种子] [输出json]
const G = preload("res://scripts/core/grammar.gd")
const E = preload("res://scripts/core/engine.gd")
const Defs = preload("res://tests/audit_defs.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const Complex = preload("res://scripts/ui/complex_editor.gd")

var rng := RandomNumberGenerator.new()
var cx = null
var AP := 60

func pick(a: Array):
	return a[rng.randi() % a.size()]

# ---------------------------------------------------------------- 随机进攻
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

# ---------------------------------------------------------------- 反制库（按档位）
func counter_library() -> Array:
	var out: Array = []
	for spec in Defs.counter_specs():
		var powers: Array = spec.powers
		var chosen: Array = []
		if powers.size() <= 3:
			chosen = powers
		else:
			chosen = [powers[1], powers[powers.size() / 2], powers[powers.size() - 1]]
		for p in chosen:
			var sk := Defs.build_counter(spec, p)
			if int(sk.cost) <= AP:
				out.append({"name": spec.name, "power": p, "skill": sk})
	return out

func _init() -> void:
	Lex.load_all()
	cx = Complex.new()
	var args := OS.get_cmdline_user_args()
	var cands := 1500
	if args.size() > 0:
		cands = int(args[0])
	rng.seed = int(args[1]) if args.size() > 1 else 7
	var out_path := "res://hunt.json"
	if args.size() > 2:
		out_path = args[2]
	if args.size() > 3:
		AP = int(args[3])
	var lib := counter_library()
	print("反制库：%d 个（含不同档位）" % lib.size())
	var strong := 0
	var unanswered: Array = []
	var answered := 0
	var t0 := Time.get_ticks_msec()
	for i in cands:
		var att := rand_attack()
		if G.problems(att).size() > 0 or int(att.cost) > AP or int(att.cost) < 15:
			continue
		var base := Defs.best_attack(att, AP)
		if base.is_empty() or base.score < 40:
			continue
		strong += 1
		var found := false
		var best_frac := 9.0
		var best_name := ""
		for c in lib:
			var r := Defs.best_response(att, c.skill, base.uid, AP)
			if r.is_empty():
				continue
			if r.att_score <= 0.25 * base.score:
				found = true
				var frac := float(c.skill.cost) / float(att.cost)
				if frac < best_frac:
					best_frac = frac
					best_name = "%s(%s)" % [c.name, str(c.power)]
		if found:
			answered += 1
		else:
			unanswered.append({"text": att.text, "cost": int(att.cost), "windup": int(att.windup), "score": base.score, "words": att.words})
			print("无解候选：费%d 起手%d 基线%d  %s" % [int(att.cost), int(att.windup), base.score, att.text])
	print("随机进攻 %d 个，强势（基线≥40分）%d 个，其中被反制库化解 %d 个，未被化解 %d 个；用时 %.0fs" % [cands, strong, answered, unanswered.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"candidates": cands, "strong": strong, "answered": answered, "unanswered": unanswered}, "  "))
	f.close()
	quit(0)
