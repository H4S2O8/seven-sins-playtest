extends RefCounted
# 强度回执：拼好一个技能时，告诉玩家“这招有多强”。
#   · 预计效果：把这招放到当前牌桌上（对手什么都不做），能打倒谁、打多少；
#   · 对手现在能不能拆：只用对手**公开的牌组**和公开的行动点，逐个试它能宣告的行动；
#   · 它怕什么：从招式结构推出（起手时间、能被多大力度的打断/沉默压住、对手公开的关键词）。
# 同时给桌宠“小词”准备一句感叹。

const E = preload("res://scripts/core/engine.gd")
const G = preload("res://scripts/core/grammar.gd")
const D = preload("res://scripts/core/deck.gd")
const Ai = preload("res://scripts/ai/ai.gd")

# 由构筑界面在打开编辑器前设置：{"foe": 对手牌组, "foe_ap": 对手行动点}
static var ctx: Dictionary = {}

const KW_NOTE := {
	"首挡": "有【首挡】，第一下会被完全挡掉",
	"不屈": "有【不屈】，能扛住一次致命伤害",
	"回击": "有【回击】，打它会被还手",
}

static func _state(my_deck: Dictionary, unit_idx: int, unit: Dictionary, sk: Dictionary) -> Dictionary:
	var mine := D.clone(my_deck)
	var u: Dictionary = unit.duplicate(true)
	u["skills"] = [sk.duplicate(true)]
	mine.units[unit_idx] = u
	var foe: Dictionary = D.clone(ctx.get("foe", D.new_deck()))
	var st := E.make_state([mine, foe], 0, {}, 7)
	E.begin_round(st)
	st.sides[0].ap = int(st.rules.ap_cap)
	st.sides[1].ap = maxi(int(ctx.get("foe_ap", 0)), int(st.rules.start_ap))
	return st

static func _acts(st: Dictionary, sid: int) -> Array:
	var sk := E.skill_of(st, sid)
	var combos: Array = [{}]
	for slot in G.choice_slots(sk):
		var opts: Array = []
		if slot.kind == "target":
			opts = E.slot_candidates(st, 0, slot)
			if slot.spec.get("side", "enemy") != "enemy" and not opts.is_empty():
				opts = [opts[0]]
		elif slot.kind == "branch":
			opts = [0, 1]
		else:
			opts = [""]
		if opts.is_empty():
			return []
		var nxt: Array = []
		for c in combos:
			for o in opts:
				var c2: Dictionary = c.duplicate()
				c2[slot.key] = o
				nxt.append(c2)
		combos = nxt.slice(0, 12)
	var out: Array = []
	for ch in combos:
		var act := {"side": 0, "sid": sid, "choices": ch, "start": 0}
		act.start = E.min_start(st, act)
		out.append(act)
	return out

# 跑一轮，量出“我方从这轮拿到了什么”
static func _measure(st: Dictionary, acts: Array) -> Dictionary:
	var c := E.clone_state(st)
	E.run_round(c, acts)
	var r := {"score": int(c.sides[0].score) - int(st.sides[0].score), "dmg": 0, "heal": 0, "kills": [], "status": [], "lost": int(c.sides[1].score) - int(st.sides[1].score)}
	for e in c.events:
		match e.type:
			"dmg":
				if int(E._u(st, int(e.tgt)).side) == 1:
					r.dmg += int(e.actual)
			"heal":
				if int(E._u(st, int(e.tgt)).side) == 0:
					r.heal += int(e.actual)
			"down":
				if int(E._u(st, int(e.tgt)).side) == 1:
					r.kills.append(str(E._u(st, int(e.tgt)).name))
			"status":
				var u := E._u(st, int(e.tgt))
				r.status.append({"name": str(u.name), "status": str(e.status), "foe": int(u.side) == 1})
	return r

static func _value(r: Dictionary) -> float:
	return float(r.score) * 3.0 + float(r.dmg) + float(r.heal) * 0.6 + float(r.status.size()) * 2.0 - float(r.lost) * 3.0

static func appraise(sk: Dictionary, my_deck: Dictionary, unit_idx: int, unit: Dictionary) -> Dictionary:
	var out := {"ok": false, "cost": int(sk.get("cost", 0)), "windup": int(sk.get("windup", 0)), "big": false, "pricey": false,
		"best": {}, "counters": [], "weak": [], "summary": "", "line": ""}
	if sk.is_empty() or not sk.has("nodes") or sk.nodes.is_empty():
		return out
	var st := _state(my_deck, unit_idx, unit, sk)
	var sid: int = int(st.sides[0].units[unit_idx].skill_ids[0])
	var cap: int = int(st.rules.ap_cap)
	if int(out.cost) > cap:
		out.weak.append("费用 %d 超过了行动点上限 %d：这招永远放不出来！" % [out.cost, cap])
		out.line = "呃……这招要 %d 行动点，可行动点最多只有 %d，根本放不出来呀！" % [out.cost, cap]
		return out
	out.ok = true
	var best_act: Dictionary = {}
	var best: Dictionary = {}
	var best_v := -INF
	for act in _acts(st, sid):
		if E.can_declare(st, act) != "":
			continue
		var r := _measure(st, [act])
		var v := _value(r)
		if v > best_v:
			best_v = v
			best = r
			best_act = act
	out.best = best
	if best_act.is_empty():
		out.weak.append("现在没有合法的出手方式（比如没有能选的目标）。")
		return out
	# ---- 对手现在能不能拆（只看对手公开的牌组和行动点）
	var seen := {}
	if not best.is_empty() and (int(best.score) > 0 or int(best.dmg) > 0):
		for fa in Ai.enumerate_actions(st, 1, [best_act], 2, []):
			if fa.is_empty():
				continue
			var nm: String = str(E.skill_of(st, int(fa.sid)).name)
			if seen.has(nm):
				continue
			var r2 := _measure(st, [best_act, fa])
			if int(r2.score) < int(best.score) or int(r2.dmg) * 10 < int(best.dmg) * 6:
				seen[nm] = true
				out.counters.append({"name": nm, "left_dmg": int(r2.dmg), "left_score": int(r2.score)})
			if out.counters.size() >= 3:
				break
	# ---- 它怕什么（结构 + 公开信息）
	out.weak.append("起手要 %d 秒：这期间施法者倒下，这招就落空。" % int(out.windup))
	out.weak.append("力度 ≥ %d 的【打断】或【沉默】能整招压掉它。" % int(ceil(float(out.cost) / 1.25)))
	if int(best.get("dmg", 0)) > 0:
		out.weak.append("对手的减伤、护盾、改道会削弱它。")
		for fu in ctx.get("foe", D.new_deck()).units:
			var kw: String = str(fu.get("kw", ""))
			if KW_NOTE.has(kw):
				out.weak.append("对手的%s%s。" % [fu.name, KW_NOTE[kw]])
	# ---- 评级
	var kills: Array = best.get("kills", [])
	out.big = kills.size() >= 2 or int(best.get("score", 0)) >= 25 or int(best.get("dmg", 0)) >= 40 or (kills.size() >= 1 and out.counters.is_empty())
	out.pricey = int(out.cost) >= 40
	out.summary = outcome_text(best)
	out.line = pet_line(sk, best, out.big, out.pricey, int(out.cost), out.counters.is_empty() and (int(best.get("dmg", 0)) > 0))
	return out

static func outcome_text(best: Dictionary) -> String:
	var kills: Array = best.get("kills", [])
	if not kills.is_empty():
		return "能打倒对手的%s，拿下 %d 分" % ["、".join(kills), int(best.score)]
	if int(best.get("dmg", 0)) > 0:
		return "让对手一共掉 %d 点血" % int(best.dmg)
	if int(best.get("heal", 0)) > 0:
		return "给自己人回 %d 点血" % int(best.heal)
	for s in best.get("status", []):
		return "让%s带上【%s】" % [s.name, s.status]
	return "要等对手出手、或者条件满足时才会起作用"

# ------------------------------------------------------------ 小词的台词
static func _short_target(t: Dictionary) -> String:
	var foe: bool = t.get("side", "") == "enemy"
	var who := "敌人" if foe else "队友"
	match t.get("pick", ""):
		"self": return "自己"
		"source": return "出手的家伙"
		"recipient": return "被打的那位"
		"choose": return "你选的" + who
		"all": return "所有" + who
		"each": return "每个" + who
		"lowest": return "血最少的" + who
		"highest": return "血最多的" + who
		"first": return "最前面的" + who
		"last": return "最后面的" + who
		"random": return "随机一个" + who
		"other": return "另一个队友"
		"adjacent": return "旁边的" + who
	return who

static func _num(node: Dictionary) -> String:
	if node.has("value") and node.value.get("k", "") == "num":
		return str(G.effective_num(node))
	return "相应的"

static func clause(node: Dictionary) -> String:
	match node.get("kind", ""):
		"dmg":
			var s := "对%s造成 %s 点伤害" % [_short_target(node.target), _num(node)]
			if int(node.get("rep", 0)) > 0:
				s += "，连打 %d 下" % (int(node.rep) + 1)
			return s
		"heal": return "给%s回 %s 点血" % [_short_target(node.target), _num(node)]
		"mit": return "让%s少受伤害" % _short_target(node.target)
		"status": return "给%s挂上【%s】" % [_short_target(node.target), node.status]
		"remove": return "清掉%s身上的%s" % [_short_target(node.target), node.what]
		"watch": return "悄悄布下埋伏，等对手动手"
		"redirect": return "把伤害甩给%s" % _short_target(node.target)
		"convert": return "把伤害变成治疗"
		"time":
			match node.op:
				"delay": return "把对手的招往后推 %d 秒" % G.effective_num(node)
				"advance": return "让自己的招提前 %d 秒" % G.effective_num(node)
				_: return "打断对手的招"
		"swap": return "和%s换位置" % _short_target(node.target)
		"split": return "把 %d 点伤害分给好几个敌人" % int(node.total)
		"copy": return clause(node.first) + "，再复制给%s" % _short_target(node.target)
		"until": return "反复%s，直到目标倒下或条件达成" % clause(node.child)
		"if": return "看情况" + clause(node.then)
		"choose": return "在两招里挑一招"
	return "做点什么"

static func clauses(sk: Dictionary) -> Array:
	var out: Array = []
	for n in sk.get("nodes", []):
		if n.get("kind", "") == "chain":
			out.append(clause(n.first))
			out.append(clause(n.then))
		else:
			out.append(clause(n))
	return out

static func pet_line(sk: Dictionary, best: Dictionary, big: bool, pricey: bool, cost: int, uncounterable: bool) -> String:
	var cs := clauses(sk)
	var body: String = "你这个技能将会" + (str(cs[0]) if not cs.is_empty() else "做点什么")
	if cs.size() >= 2:
		body += "，然后" + cs[1]
	if cs.size() >= 3:
		body += "，再" + cs[2]
	body += "，预计" + outcome_text(best) + "！"
	var pre := ""
	if big:
		pre = ["哇！你要发动超级厉害的技能了！", "大招！这是大招！", "这一下下去，对面要哭了！"][randi() % 3]
		if uncounterable:
			pre += "而且对手现在的牌里没有能拆它的招！"
	elif pricey:
		pre = "好贵！要花 %d 行动点——" % cost
	return pre + body
