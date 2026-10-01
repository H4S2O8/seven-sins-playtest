extends RefCounted
# 审计用的进攻组合与反制族定义（t_audit.gd 与 t_avail.gd 共用）。
const G = preload("res://scripts/core/grammar.gd")
const R = preload("res://scripts/core/recipes.gd")
const E = preload("res://scripts/core/engine.gd")
const D = preload("res://scripts/core/deck.gd")
const Ai = preload("res://scripts/ai/ai.gd")

# 进攻：模板 + 参数；主数值 n 由审计按“操作费上限”拟合
static func attack_specs() -> Array:
	return [
		{"name": "单点", "tid": "atk1", "params": {}},
		{"name": "单点·双倍", "tid": "atk1", "params": {"dbl": 1}},
		{"name": "单点·双倍×2", "tid": "atk1", "params": {"dbl": 2}},
		{"name": "单点·双倍·重复", "tid": "atk1", "params": {"dbl": 1, "rep": 1}},
		{"name": "单点·重复×3", "tid": "atk1", "params": {"rep": 3}},
		{"name": "全体", "tid": "atkA", "params": {}},
		{"name": "全体·双倍", "tid": "atkA", "params": {"dbl": 1}},
		{"name": "全体·重复", "tid": "atkA", "params": {"rep": 1}},
		{"name": "全体·双倍·重复", "tid": "atkA", "params": {"dbl": 1, "rep": 1}},
		{"name": "逐个全体·双倍", "tid": "atkA", "params": {"scope": "each", "dbl": 1}},
		{"name": "分流", "tid": "split", "params": {}},
		{"name": "复制", "tid": "copy", "params": {}},
		{"name": "汲取", "tid": "drain", "params": {}},
	]

# 自拟组合（多节点）：按 n 逐步加大，取操作费不超上限的最大者
static func custom_attack(kind: String, n: int) -> Dictionary:
	match kind:
		"易伤+双倍打击":
			return G.finalize(G.skill(kind, [
				G.status("易伤", G.T("choose", "enemy")),
				G.dmg(G.T("choose", "enemy"), G.N(n), {"dbl": 1, "rep": 1})]))
		"狂振+全体·双倍":
			return G.finalize(G.skill(kind, [
				G.status("狂振", G.T("all", "enemy")),
				G.dmg(G.T("all", "enemy"), G.N(n), {"dbl": 1})]))
		"沉默+全体":
			return G.finalize(G.skill(kind, [
				G.status("沉默", G.T("all", "enemy"), 0, 25),
				G.dmg(G.T("all", "enemy"), G.N(n), {"dbl": 1})]))
	return {}

static func custom_kinds() -> Array:
	return ["易伤+双倍打击", "狂振+全体·双倍", "沉默+全体"]

# 反制族：tid + 固定参数 + 可递增的参数名与档位
static func counter_specs() -> Array:
	var d := func(name, tid, params, pkey, powers): return {"name": name, "tid": tid, "params": params, "pkey": pkey, "powers": powers}
	return [
		d.call("改道·全队·每次→来源", "redirect", {"obs": "all", "to": "source", "freq": "every"}, "n", [10, 20, 30, 40, 50, 60]),
		d.call("改道·自身·首次→来源", "redirect", {"obs": "self", "to": "source", "freq": "once"}, "n", [10, 20, 30, 40, 50, 60]),
		d.call("改道·全队·每次→敌方最高生命", "redirect", {"obs": "all", "to": "highest", "freq": "every"}, "n", [10, 20, 30, 40, 50, 60]),
		d.call("转伤为疗·全队·每次", "convert", {"obs": "all", "freq": "every"}, "n", [10, 20, 30, 40, 50, 60]),
		d.call("回敬·全队·等量·每次", "reflect", {"obs": "all", "mult": 0, "freq": "every"}, "", [0]),
		d.call("回敬·全队·双倍·每次", "reflect", {"obs": "all", "mult": 1, "freq": "every"}, "", [0]),
		d.call("减伤·全队·按比例", "mit", {"tgt": "all", "mode": "pct"}, "n", [10, 20, 30, 40, 60]),
		d.call("护盾·全队", "shield", {"tgt": "all"}, "n", [10, 20, 30, 40, 50, 60]),
		d.call("治疗·全队", "heal", {"tgt": "all"}, "n", [10, 20, 30, 40, 50, 60]),
		d.call("护盾·全队·双倍", "shield", {"tgt": "all", "dbl": 1}, "n", [5, 10, 15, 20, 25, 30]),
		d.call("改道·全队·每次→来源·双倍", "redirect", {"obs": "all", "to": "source", "freq": "every", "dbl": 1}, "n", [5, 10, 15, 20, 25, 30]),
		d.call("转伤为疗·全队·每次·双倍", "convert", {"obs": "all", "freq": "every", "dbl": 1}, "n", [5, 10, 15, 20, 25, 30]),
		d.call("护盾·全队·双倍×2", "shield", {"tgt": "all", "dbl": 2}, "n", [3, 5, 8, 10, 15]),
		d.call("改道·全队·每次→来源·双倍×2", "redirect", {"obs": "all", "to": "source", "freq": "every", "dbl": 2}, "n", [3, 5, 8, 10, 15]),
		d.call("转伤为疗·全队·每次·双倍×2", "convert", {"obs": "all", "freq": "every", "dbl": 2}, "n", [3, 5, 8, 10, 15]),
		d.call("打断·双倍力度", "time", {"op": "interrupt", "dbl": 1}, "power", [5, 10, 15, 20, 25, 30]),
		d.call("打断", "time", {"op": "interrupt"}, "power", [10, 20, 30, 40, 50, 60]),
		d.call("延后", "time", {"op": "delay"}, "sec", [4, 8, 12, 16, 19]),
		d.call("沉默攻击者", "status", {"st": "沉默", "tgt": "choose"}, "n", [10, 20, 30, 40, 50, 60]),
		d.call("见招收税", "tax", {}, "n", [10, 20, 30, 45]),
		d.call("遗志", "burst", {}, "n", [10, 20, 30, 45]),
		d.call("反击·全体打击", "atkA", {}, "n", [10, 20, 30, 45]),
		d.call("反击·单点打击", "atk1", {}, "n", [10, 20, 30, 45]),
	]

static func build_counter(spec: Dictionary, power: int) -> Dictionary:
	var p: Dictionary = spec.params.duplicate()
	if spec.pkey != "":
		p[spec.pkey] = power
	return R.build(spec.tid, p)


# ------------------------------------------------------------ 一轮对决的公共函数
static func make_deck(skill: Dictionary, host: int) -> Dictionary:
	var d := D.new_deck()
	var nums := int(skill.budget) if not skill.is_empty() else 0
	var hp_total := maxi(5, D.BUDGET - nums)
	var each := int(hp_total / 5)
	for i in 5:
		d.units[i].max_hp = each
	d.units[0].max_hp += hp_total - each * 5
	if not skill.is_empty():
		d.units[host].skills.append(skill.duplicate(true))
	return d

static func scenario(att: Dictionary, deff: Dictionary, ap: int) -> Dictionary:
	var st := E.make_state([make_deck(att, 0), make_deck(deff, 1)], 0, {"start_ap": 0})
	E.begin_round(st)
	st.sides[0].ap = ap
	st.sides[1].ap = ap
	return st

static func att_action(st: Dictionary, choice_uid: int) -> Dictionary:
	var sid: int = st.sides[0].units[0].skill_ids[0]
	var sk := E.skill_of(st, sid)
	var ch := {}
	for slot in G.choice_slots(sk):
		if slot.kind == "target":
			ch[slot.key] = choice_uid if slot.spec.get("side", "enemy") == "enemy" else 0
		elif slot.kind == "branch":
			ch[slot.key] = 0
		elif slot.kind == "remove":
			ch[slot.key] = ""
	var act := {"side": 0, "sid": sid, "choices": ch, "start": 0}
	act.start = E.min_start(st, act)
	return act

static func value_of(st: Dictionary) -> float:
	return float(st.sides[0].score - st.sides[1].score)

static func run(st: Dictionary, a0: Dictionary, a1: Dictionary) -> Dictionary:
	var c := E.clone_state(st)
	E.run_round(c, [a0, a1])
	return c

static func best_attack(att: Dictionary, ap: int) -> Dictionary:
	var st := scenario(att, {}, ap)
	var best: Dictionary = {}
	var best_v := -INF
	for uid in [10, 11, 12, 13, 14]:
		var a := att_action(st, uid)
		if E.can_declare(st, a) != "":
			continue
		var r := run(st, a, {})
		var v := value_of(r)
		if v > best_v:
			best_v = v
			best = {"uid": uid, "v": v, "score": int(r.sides[0].score), "cost": E.action_cost(st, a), "windup": E.min_start(st, a)}
	return best

static func best_response(att: Dictionary, deff: Dictionary, uid: int, ap: int) -> Dictionary:
	var st := scenario(att, deff, ap)
	var a0 := att_action(st, uid)
	var acts := Ai.enumerate_actions(st, 1, a0, 8)
	var worst := INF
	var res: Dictionary = {}
	for a in acts:
		if a.is_empty():
			continue
		var r := run(st, a0, a)
		var v := value_of(r)
		if v < worst:
			worst = v
			res = {"v": v, "att_score": int(r.sides[0].score), "def_score": int(r.sides[1].score), "start": int(a.start), "cost": E.action_cost(st, a)}
	return res
