extends SceneTree
# 模糊测试：随机拼出大量合法技能，随机对局，检查不变量（生命范围、行动点非负、不死循环）。
# 脚本错误会被 Godot 打印为 SCRIPT ERROR，外面用 grep 检查。用法： -- [局数] [种子]
const G = preload("res://scripts/core/grammar.gd")
const E = preload("res://scripts/core/engine.gd")
const D = preload("res://scripts/core/deck.gd")
const Ai = preload("res://scripts/ai/ai.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const Complex = preload("res://scripts/ui/complex_editor.gd")

var rng := RandomNumberGenerator.new()
var cx = null
var violations := 0
var invalid := 0
var valid := 0

func pick(a: Array):
	return a[rng.randi() % a.size()]

func rand_target(in_watch: bool, allow_choose: bool = true) -> Dictionary:
	var opts: Array = Complex.TARGET_OPTS.duplicate()
	if in_watch:
		opts = opts + Complex.WATCH_TARGET_OPTS
	for i in 8:
		var o: Array = pick(opts)
		if not allow_choose and (o[1] == "choose" or o[1] == "other"):
			continue
		var t := G.T(o[1], o[2])
		if o[1] == "adjacent":
			t["center"] = "recipient"
		return t
	return G.T("self", "self")

func rand_value(ctx: String, allow_prev: bool = false) -> Dictionary:
	var r := rng.randf()
	if r < 0.55:
		return G.N(rng.randi_range(1, 25))
	var refs: Array = cx._ref_opts(ctx, allow_prev)
	if r < 0.9:
		var ro: Array = pick(refs)
		var v := G.REF(ro[1])
		if ro[1] in ["cur_hp", "max_hp", "lost_hp"]:
			v["of"] = G.T("self", "self")
		elif ro[1] == "count":
			v["of"] = G.T("all", "enemy")
		return v
	return G.OP(pick(["max", "min", "sum", "diff"]), G.N(rng.randi_range(1, 10)), rand_value(ctx, allow_prev) if rng.randf() < 0.5 else G.N(5))

func mods(n: Dictionary) -> Dictionary:
	if rng.randf() < 0.12:
		n["sync"] = true
	if rng.randf() < 0.25:
		n["dbl"] = rng.randi_range(0, 2)
	if rng.randf() < 0.1:
		n["half"] = 1
	if rng.randf() < 0.2:
		n["rep"] = rng.randi_range(1, 2)
		if rng.randf() < 0.5:
			n["rep_gap"] = rng.randi_range(1, 4)
	if rng.randf() < 0.15:
		n["delay"] = rng.randi_range(1, 6)
	return n

func rand_node(depth: int, ctx: String, allow_prev: bool = false, simple_only: bool = false) -> Dictionary:
	var in_watch := ctx != ""
	var kinds := ["dmg", "dmg", "heal", "mit", "status", "remove", "time", "swap", "split"]
	if not simple_only and depth < 3:
		kinds += ["watch", "watch", "chain", "copy", "if", "choose", "until"]
	var k: String = pick(kinds)
	match k:
		"dmg":
			return mods(G.dmg(rand_target(in_watch), rand_value(ctx, allow_prev), {"alt": rng.randi_range(0, 1)}))
		"heal":
			return mods(G.heal(rand_target(in_watch), rand_value(ctx, allow_prev), {"alt": rng.randi_range(0, 1)}))
		"mit":
			return G.mit(rand_target(in_watch), pick(["pct", "fixed"]), rng.randi_range(1, 30), pick([0, 0, 3, 8]))
		"status":
			var st: String = pick(G.STATUSES)
			var link := {}
			var tgt := rand_target(in_watch)
			if st == "牵连":
				link = G.T("other", "ally")
			return G.status(st, tgt, pick([0, 0, 4, 10]), rng.randi_range(1, 20), link)
		"remove":
			return G.remove(pick(["限时效果", "状态"]), rand_target(in_watch))
		"time":
			var op: String = pick(["interrupt", "delay", "advance"])
			return G.time_op(op, "ally" if op == "advance" else "enemy", rng.randi_range(5, 40) if op == "interrupt" else rng.randi_range(1, 10))
		"swap":
			return G.swap(G.T("choose", "ally"))
		"split":
			var total := rng.randi_range(4, 30)
			var a := rng.randi_range(1, total - 1)
			return G.split(pick(["dmg", "heal"]), total, [
				{"target": rand_target(in_watch), "part": a, "delay": pick([0, 0, 2])},
				{"target": rand_target(in_watch), "part": total - a, "delay": 0}])
		"chain":
			var first := G.dmg(rand_target(in_watch), rand_value(ctx)) if rng.randf() < 0.6 else G.heal(rand_target(in_watch), rand_value(ctx))
			var then: Dictionary = pick([G.heal(rand_target(in_watch), G.REF("prev")), G.dmg(rand_target(in_watch), G.REF("prev"), {"dbl": 1}), G.status(pick(G.STATUSES), rand_target(in_watch), 0, 5)])
			return G.chain(first, then)
		"copy":
			return G.copy_to(G.dmg(rand_target(in_watch), rand_value(ctx)), rand_target(in_watch))
		"until":
			var uc := G.has_cond(rand_target(in_watch, false), pick(G.STATUSES)) if rng.randf() < 0.4 else G.cmp_cond(G.REF("cur_hp", G.T("lowest", "enemy")), "lt", G.N(rng.randi_range(1, 12)))
			return G.until_node(uc, pick([G.dmg(rand_target(in_watch), rand_value(ctx)), G.heal(rand_target(in_watch), rand_value(ctx)), G.mit(rand_target(in_watch), "pct", 8)]), pick([0, 1, 3]))
		"if":
			var cond := G.has_cond(rand_target(in_watch, false), pick(G.STATUSES)) if rng.randf() < 0.3 else {"left": rand_value(ctx), "cmp": pick(["lt", "ge"]), "right": rand_value(ctx)}
			var n := G.if_node(cond, rand_node(depth + 1, ctx, allow_prev, true))
			if rng.randf() < 0.5:
				n["else"] = rand_node(depth + 1, ctx, allow_prev, true)
			return n
		"choose":
			return G.pick_one(rand_node(depth + 1, ctx, allow_prev, true), rand_node(depth + 1, ctx, allow_prev, true))
		"watch":
			var events: Array = G.EVENT_TEXT.keys()
			var ev: String = pick(events)
			var child: Dictionary
			if ev == "pending_dmg" and rng.randf() < 0.7:
				child = G.redirect(rand_target(true), rng.randi_range(1, 30)) if rng.randf() < 0.6 else G.convert_heal(rng.randi_range(1, 30))
			else:
				child = rand_node(depth + 1, ev, false, rng.randf() < 0.5)
			var w := G.watch(ev, rand_target(false), child, {"freq": pick(["once", "every"]), "life": pick(["round", "dur"]), "dur": rng.randi_range(1, 12)})
			return w
	return G.dmg(G.T("choose", "enemy"), G.N(5))

func rand_skill() -> Dictionary:
	for attempt in 30:
		var nodes: Array = []
		for i in rng.randi_range(1, 3):
			nodes.append(rand_node(0, ""))
		var sk := G.finalize(G.skill("随机%d" % rng.randi_range(0, 9999), nodes))
		if G.problems(sk).is_empty():
			valid += 1
			return sk
		invalid += 1
	return G.finalize(G.skill("兜底", [G.dmg(G.T("choose", "enemy"), G.N(8))]))

func rand_deck() -> Dictionary:
	var d := D.new_deck()
	for i in 5:
		d.units[i].max_hp = rng.randi_range(5, 25)
		d.units[i].kw = pick(["", "", "首挡", "不屈", "回击", "回春", "同调", "免疫狂振"])
		for k in rng.randi_range(0, 2):
			d.units[i].skills.append(rand_skill())
	D.rename_skills(d)
	return d

func check_state(st: Dictionary, tag: String) -> void:
	for s in 2:
		if int(st.sides[s].ap) < 0 or int(st.sides[s].ap) > int(st.rules.ap_cap):
			print("!! 行动点越界 ", tag, " ", st.sides[s].ap)
			violations += 1
		for u in st.sides[s].units:
			if int(u.hp) < 0 or int(u.hp) > int(u.max_hp):
				print("!! 生命越界 ", tag, " ", u.name, " ", u.hp, "/", u.max_hp)
				violations += 1
			if u.down_round == -1 and int(u.hp) <= 0:
				print("!! 存活但生命为0 ", tag, " ", u.name)
				violations += 1
	if st.guard > 29000:
		print("!! 事件数逼近上限（疑似失控链）", tag, " guard=", st.guard)
		violations += 1

func _init() -> void:
	Lex.load_all()
	cx = Complex.new()
	var games := 300
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		games = int(args[0])
	rng.seed = int(args[1]) if args.size() > 1 else 20261001
	var t0 := Time.get_ticks_msec()
	var acts_run := 0
	var max_guard := 0
	var evc := {}
	for g in games:
		var st := E.make_state([rand_deck(), rand_deck()], g % 2, {}, rng.randi() & 0x7fffffff)
		for r in 8:
			E.begin_round(st)
			st.sides[0].ap = 60
			st.sides[1].ap = 60
			var first := E.first_side(st)
			var acts: Array = [{}, {}]
			var a1: Array = Ai.enumerate_actions(st, first, {}, 6)
			acts[first] = pick(a1)
			var a2: Array = Ai.enumerate_actions(st, 1 - first, acts[first], 6)
			acts[1 - first] = pick(a2)
			E.run_round(st, acts)
			acts_run += 1
			for e in st.events:
				evc[e.type] = int(evc.get(e.type, 0)) + 1
			max_guard = maxi(max_guard, int(st.guard))
			check_state(st, "对局%d轮%d" % [g, r])
			if st.winner != -1:
				break
	print("模糊测试：%d 局，%d 轮，随机技能 合法%d / 被拒%d，违例 %d，单轮最大事件数 %d，用时 %.1fs" % [games, acts_run, valid, invalid, violations, max_guard, (Time.get_ticks_msec() - t0) / 1000.0])
	var keys: Array = evc.keys()
	keys.sort()
	var line := ""
	for k in keys:
		line += "%s=%d " % [k, evc[k]]
	print("事件覆盖：", line)
	quit(violations)
