extends RefCounted
# 辅助轮（教练）：分析“拿哪一袋词更有利”“现在能凑出什么、还差什么”。
# 只读公开信息：玩家自己的词库与牌组。不改任何状态。

const G = preload("res://scripts/core/grammar.gd")
const R = preload("res://scripts/core/recipes.gd")
const D = preload("res://scripts/core/deck.gd")
const Lex = preload("res://scripts/core/lexicon.gd")

# 路线：名字、模板、固定参数、定位、权重（越大越值得追）、一句话说明
const ROUTES := [
	["单点打击", "atk1", {}, "攻", 1.0, "打一个敌人，最基础的输出"],
	["单点·双倍", "atk1", {"dbl": 1}, "攻", 1.6, "单体伤害翻倍，用来斩杀"],
	["单点·双倍·重复", "atk1", {"dbl": 1, "rep": 1}, "攻", 2.4, "翻倍再打两次，单体爆发"],
	["追击", "chase", {}, "攻", 2.0, "反复打最低生命的敌人，直到它快死"],
	["范围打击", "atkA", {}, "攻", 2.0, "一次打全场，每个敌人都吃满数值"],
	["范围·双倍", "atkA", {"dbl": 1}, "攻", 3.0, "全场翻倍，先手大招"],
	["范围·重复", "atkA", {"rep": 1}, "攻", 3.0, "全场打两轮"],
	["范围·双倍·重复", "atkA", {"dbl": 1, "rep": 1}, "攻", 4.0, "全场翻倍再打两轮，惊艳大招"],
	["分流打击", "split", {}, "攻", 2.0, "总伤害拆给两个目标"],
	["复制打击", "copy", {}, "攻", 2.5, "打一个，再把伤害复制给另一个"],
	["汲取", "drain", {}, "攻", 1.5, "打人并按伤害回血"],
	["治疗·全队", "heal", {"tgt": "all"}, "守", 1.2, "给全队回血"],
	["减伤·全队", "mit", {"tgt": "all", "mode": "pct"}, "守", 1.4, "全队受伤降低一截"],
	["护盾·全队", "shield", {"tgt": "all"}, "守", 1.4, "给全队套护盾吸收伤害"],
	["护盾·全队·双倍", "shield", {"tgt": "all", "dbl": 1}, "守", 2.2, "全队双倍护盾，扛范围大招"],
	["改道·全队→来源", "redirect", {"obs": "all", "to": "source", "freq": "every"}, "反", 2.4, "把打向我方的伤害转给出招的人，大招反噬"],
	["改道·全队·双倍", "redirect", {"obs": "all", "to": "source", "freq": "every", "dbl": 1}, "反", 3.2, "双倍上限的全队改道"],
	["转伤为疗·全队", "convert", {"obs": "all", "freq": "every"}, "反", 2.4, "把对方的伤害变成我方的治疗"],
	["回敬·全队", "reflect", {"obs": "all", "mult": 0, "freq": "every"}, "反", 2.0, "挨打后按该次伤害回敬来源"],
	["回敬·双倍", "reflect", {"obs": "all", "mult": 1, "freq": "every"}, "反", 2.5, "挨打后双倍奉还"],
	["见招收税", "tax", {}, "反", 1.6, "对手每发动一个技能就让施法者掉血"],
	["遗志", "burst", {}, "反", 1.6, "倒下时对全场造成伤害"],
	["治疗引爆", "engine", {}, "反", 2.4, "每次回血都转成对敌伤害"],
	["打断", "time", {"op": "interrupt"}, "控", 2.6, "取消对方还没起效的技能"],
	["打断·双倍力度", "time", {"op": "interrupt", "dbl": 1}, "控", 3.0, "更省数字的打断"],
	["延后", "time", {"op": "delay"}, "控", 1.2, "把对方的技能往后推"],
	["沉默", "status", {"st": "沉默", "tgt": "choose"}, "控", 2.4, "让对方施法者出不了招"],
	["驱散", "remove", {"what": "限时效果"}, "控", 1.5, "拆掉对方布下的监听或减伤"],
]

# 当前“空闲词”（词库减去已装在牌组里的词）
static func free_words(pool: Dictionary, deck: Dictionary) -> Dictionary:
	var used := D.used_counts(deck)
	var out := {}
	for w in pool:
		out[w] = int(pool[w]) - int(used.get(w, 0))
	return out

static func _missing(words: Array, avail: Dictionary) -> Dictionary:
	return G.missing(words, avail)

static func _count(miss: Dictionary) -> int:
	var n := 0
	for w in miss:
		n += int(miss[w])
	return n

# 对一条路线，在“选项型参数”里挑缺词最少的取值（目标的写法有很多种）
static func fit(route: Array, avail: Dictionary) -> Dictionary:
	var tid: String = route[1]
	var p: Dictionary = R.defaults(tid)
	for k in route[2]:
		p[k] = route[2][k]
	var best := _count(_missing(R.build(tid, p).words, avail))
	for prm in R.template(tid).params:
		if prm.kind != "enum" or route[2].has(prm.key):
			continue
		for o in prm.options:
			var trial := p.duplicate()
			trial[prm.key] = o[0]
			var m := _count(_missing(R.build(tid, trial).words, avail))
			if m < best:
				best = m
				p = trial
		if best == 0:
			break
	var sk := R.build(tid, p)
	return {"params": p, "skill": sk, "missing": _missing(sk.words, avail), "n": best}

static func route_status(avail: Dictionary) -> Array:
	var out: Array = []
	for r in ROUTES:
		var f := fit(r, avail)
		out.append({"name": r[0], "role": r[3], "w": float(r[4]), "desc": r[5], "tid": r[1], "route": r,
			"missing": f.missing, "n": f.n, "params": f.params, "skill": f.skill})
	return out

static func _bag_free(avail: Dictionary, bag: Array) -> Dictionary:
	var a := avail.duplicate()
	for w in bag:
		a[w] = int(a.get(w, 0)) + 1
	return a

static func _missing_text(miss: Dictionary) -> String:
	var parts: Array = []
	for w in miss:
		parts.append("%s%s" % [w, ("×%d" % int(miss[w])) if int(miss[w]) > 1 else ""])
	return "、".join(parts)

# ------------------------------------------------------------ 抽词建议
# 返回 {pick, per_bag:[{gain, done:[名], near:[{name,missing}] }], reason, watch:[文字]}
static func analyze_draft(pool: Dictionary, deck: Dictionary, bags: Array) -> Dictionary:
	var avail := free_words(pool, deck)
	var base := route_status(avail)
	var per: Array = []
	for bag in bags:
		var after := route_status(_bag_free(avail, bag))
		var done: Array = []
		var near: Array = []
		var gain := 0.0
		for i in base.size():
			var b: Dictionary = base[i]
			var a: Dictionary = after[i]
			if b.n > 0 and a.n == 0:
				done.append({"name": a.name, "role": a.role, "w": a.w})
				gain += a.w * 2.0
			elif a.n < b.n and a.n <= 2:
				near.append({"name": a.name, "role": a.role, "w": a.w, "missing": a.missing, "n": a.n})
				gain += a.w * (float(b.n - a.n) / float(maxi(b.n, 1))) * 1.2
			elif a.n < b.n:
				gain += a.w * 0.1 * float(b.n - a.n)
		done.sort_custom(func(x, y): return x.w > y.w)
		near.sort_custom(func(x, y): return x.w > y.w)
		per.append({"gain": gain, "done": done, "near": near, "after": after})
	var pick := 0 if per[0].gain >= per[1].gain else 1
	var chosen: Dictionary = per[pick]
	var reason := ""
	if not chosen.done.is_empty():
		var names: Array = []
		for d in chosen.done.slice(0, 3):
			names.append("【%s】" % d.name)
		reason = "拿这袋能新凑齐 %s" % "、".join(names)
		if not chosen.near.is_empty():
			reason += "，还让【%s】只差一点" % chosen.near[0].name
	elif not chosen.near.is_empty():
		reason = "拿这袋能让【%s】只差 %d 个词（%s）" % [chosen.near[0].name, chosen.near[0].n, _missing_text(chosen.near[0].missing)]
	else:
		reason = "两袋对现有路线的帮助都不大，选词更多、更基础的一袋稳妥"
	# 接下来要留意：选中后最有价值、还没凑齐、差得最少的路线
	var watch: Array = []
	var cand: Array = []
	for a in chosen.after:
		if a.n > 0 and a.n <= 4:
			cand.append(a)
	cand.sort_custom(func(x, y): return (x.w / float(x.n)) > (y.w / float(y.n)))
	for c in cand.slice(0, 3):
		watch.append("【%s】（%s）还缺：%s" % [c.name, c.role, _missing_text(c.missing)])
	return {"pick": pick, "per_bag": per, "reason": reason, "watch": watch}

# ------------------------------------------------------------ 构筑/调整建议
# 现在凑得出但还没装的路线，加上最值得追的缺词路线
static func analyze_build(pool: Dictionary, deck: Dictionary) -> Dictionary:
	var avail := free_words(pool, deck)
	var st := route_status(avail)
	var ready: Array = []
	var chase: Array = []
	for r in st:
		if r.n == 0:
			ready.append(r)
		elif r.n <= 4:
			chase.append(r)
	ready.sort_custom(func(x, y): return x.w > y.w)
	chase.sort_custom(func(x, y): return (x.w / float(x.n)) > (y.w / float(y.n)))
	# 放进哪张卡：技能槽有空、生命较高的卡
	var target := -1
	var best_free := -1
	for i in deck.units.size():
		var free_slots: int = D.MAX_SKILLS - deck.units[i].skills.size()
		if free_slots > 0 and (free_slots > best_free or (free_slots == best_free and deck.units[i].max_hp > deck.units[target].max_hp)):
			best_free = free_slots
			target = i
	return {"ready": ready, "chase": chase, "target_unit": target}

static func describe_build(pool: Dictionary, deck: Dictionary) -> Array:
	var info := analyze_build(pool, deck)
	var lines: Array = []
	if info.ready.is_empty():
		lines.append("你现有的空闲词暂时凑不出新的招式，先看下面“再凑什么”。")
	else:
		var names: Array = []
		for r in info.ready.slice(0, 4):
			names.append("【%s】" % r.name)
		lines.append("现在就能做、但还没装上的：%s" % "、".join(names))
		if info.target_unit >= 0:
			lines.append("建议：编辑【%s】，装入【%s】（%s）：%s" % [deck.units[info.target_unit].name, info.ready[0].name, info.ready[0].role, info.ready[0].desc])
		else:
			lines.append("五张卡的技能槽都满了；想装新招，先在某张卡里清空一个技能槽。")
	for c in info.chase.slice(0, 2):
		lines.append("再凑 %d 个词就能做【%s】（%s）：%s" % [c.n, c.name, c.role, _missing_text(c.missing)])
	return lines
