extends RefCounted
# 出招预判（辅助轮）：只用“自己确定知道的信息”回答两个问题——
#   1. 这招打出去，预计会怎样（假设对手什么都不做）
#   2. 怕什么（只来自桌面公开信息：关键词、状态、自己的血量和时间）
# 不读对手没有公开的东西，也不替后手模拟“对手的行动会怎样改写结果”：先后手一视同仁。

const E = preload("res://scripts/core/engine.gd")
const G = preload("res://scripts/core/grammar.gd")

const KW_NOTE := {
	"首挡": "有【首挡】：第一次受到的伤害会被完全挡掉",
	"不屈": "有【不屈】：会扛住致命的一击（每场一次）",
	"回击": "有【回击】：打到它，它会还手一下",
	"回春": "有【回春】：被治疗时，会顺带治疗一名队友",
	"同调": "有【同调】：被施加状态时，会同时传给一名队友",
	"免疫狂振": "对【狂振】免疫", "免疫牵连": "对【牵连】免疫", "免疫升华": "对【升华】免疫",
}

static func _name(st: Dictionary, uid: int) -> String:
	var u := E._u(st, uid)
	if u.is_empty():
		return "?"
	return "你的" + u.name if u.side == 0 else "对手的" + u.name

# 返回 {"cost": [..], "effects": [..], "fears": [..], "facts": [..]}
static func analyze(st: Dictionary, side: int, act: Dictionary, declared_mine: Array, enemy_declared: Array) -> Dictionary:
	var out := {"cost": [], "effects": [], "fears": [], "facts": [], "data": {}}
	var sk: Dictionary = E.skill_of(st, act.sid)
	if sk.is_empty():
		return out
	var host := E._u(st, E.host_of(st, act.sid))
	var cost := E.action_cost(st, act)
	var ap_left := E.available_ap(st, side, declared_mine) - cost
	var nums: int = int(G.skill_nums(sk, act.get("choices", {})).ap)
	out.cost.append("花费 %d 行动点 = 起步 %d + 数字 %d + 词语 %d；用完还剩 %d。越强的招越贵。" % [cost, G.START_FEE, nums, int(sk.price), ap_left])
	out.cost.append("第 %d 秒起效（起手至少要 %d 秒）。" % [int(act.start), E.min_start(st, act)])
	# ---------- 1. 预计效果：只模拟这一个行动，对手不动
	var c := E.clone_state(st)
	var one := act.duplicate(true)
	E.run_round(c, [one])
	var dmg := {}
	var heal := {}
	var downs := {}
	var blocks := {}
	var stat := {}
	var shields := {}
	var other := false
	for e in c.events:
		match e.type:
			"dmg":
				dmg[int(e.tgt)] = int(dmg.get(int(e.tgt), 0)) + int(e.actual)
			"heal":
				heal[int(e.tgt)] = int(heal.get(int(e.tgt), 0)) + int(e.actual)
			"down":
				downs[int(e.tgt)] = int(e.score)
			"block":
				blocks[int(e.tgt)] = true
			"shield":
				shields[int(e.tgt)] = int(shields.get(int(e.tgt), 0)) + int(e.absorbed)
			"status":
				if not stat.has(int(e.tgt)):
					stat[int(e.tgt)] = []
				stat[int(e.tgt)].append(str(e.status))
			"watch_install", "time", "redirect", "swap", "mit":
				other = true
	for uid in dmg:
		var before := int(E._u(st, uid).hp)
		var after := int(E._u(c, uid).hp)
		var line := "%s：受到 %d 点伤害（生命 %d → %d）" % [_name(st, uid), int(dmg[uid]), before, after]
		if blocks.has(uid):
			line += "；被首挡挡掉"
		if shields.has(uid):
			line += "；护盾吸收了 %d" % int(shields[uid])
		if downs.has(uid):
			line += "；被打倒！" + ("你得 %d 分" % int(downs[uid]) if E._u(st, uid).side != side else "对手得 %d 分" % int(downs[uid]))
		out.effects.append(line)
	for uid in blocks:
		if not dmg.has(uid):
			out.effects.append("%s：伤害被首挡挡掉了" % _name(st, uid))
	for uid in heal:
		out.effects.append("%s：恢复 %d 点（生命 %d → %d）" % [_name(st, uid), int(heal[uid]), int(E._u(st, uid).hp), int(E._u(c, uid).hp)])
	for uid in stat:
		out.effects.append("%s：获得【%s】" % [_name(st, uid), "】【".join(stat[uid])])
	var data := {"kills": [], "score": 0, "dmg": 0, "heal": 0, "status": [], "cost": cost, "ap_left": ap_left}
	for uid in dmg:
		if int(E._u(st, uid).side) != side:
			data.dmg += int(dmg[uid])
	for uid in heal:
		if int(E._u(st, uid).side) == side:
			data.heal += int(heal[uid])
	for uid in downs:
		if int(E._u(st, uid).side) != side:
			data.kills.append(str(E._u(st, uid).name))
			data.score += int(downs[uid])
	for uid in stat:
		for sn in stat[uid]:
			data.status.append({"name": str(E._u(st, uid).name), "status": sn})
	out.data = data
	if out.effects.is_empty():
		out.effects.append("这招不会直接改变生命：它是设伏、改时间或需要“条件满足/对手出招”才起作用的类型。")
	elif other:
		out.effects.append("另外它还带有设伏/时间/防护类效果，需要对手出招时才会起作用。")
	out.effects.append("（以上假设对手这一轮什么都不做。）")
	# ---------- 2. 怕什么：只用公开信息
	var landing := int(act.start)
	if not host.is_empty():
		if int(host.hp) * 2 <= int(host.max_hp) or int(host.hp) <= 8:
			out.fears.append("%s 现在只有 %d 点生命。招式要到第 %d 秒才起效，期间它若被打倒，这一招就落空。" % [_name(st, host.uid), int(host.hp), landing])
		if landing >= 8:
			out.fears.append("起效在第 %d 秒，比较晚：对手有更长的时间让它倒下或把它打断。" % landing)
		for s in host.statuses:
			if s.name == "沉默":
				out.fears.append("%s 被沉默了，压住了费用不超过 %d 的技能。" % [_name(st, host.uid), G.silence_limit(int(s.value))])
	var seen := {}
	for uid in dmg.keys() + stat.keys():
		if seen.has(uid):
			continue
		seen[uid] = true
		var t := E._u(st, uid)
		if t.is_empty() or int(t.side) == side:
			continue
		if KW_NOTE.has(t.kw) and not t.kw_spent:
			out.fears.append("目标 %s %s。" % [_name(st, uid), KW_NOTE[t.kw]])
		for s in t.statuses:
			if s.name == "护盾":
				out.fears.append("目标 %s 有护盾，会先吸收 %d 点伤害。" % [_name(st, uid), int(s.value)])
	# ---------- 3. 对手已宣告的行动：只摆事实
	if not enemy_declared.is_empty():
		for a in enemy_declared:
			var es := E.skill_of(st, a.sid)
			out.facts.append("对手的【%s】第 %d 秒起效：%s" % [es.name, int(a.start), es.text])
		var ea := int(enemy_declared[0].start)
		if landing < ea:
			out.facts.append("你的招式（第 %d 秒）比对手最早的行动（第 %d 秒）先起效。" % [landing, ea])
		elif landing == ea:
			out.facts.append("你和对手最早的行动是同一秒起效。")
		else:
			out.facts.append("你的招式（第 %d 秒）比对手最早的行动（第 %d 秒）晚起效。" % [landing, ea])
	else:
		out.fears.append("你是先手宣告：对手会看到你的全部行动再决定怎么应对。起效越晚、越贵的招越容易被针对。")
	return out

# 一个已宣告行动“写在牌面上的意图”：假设没有任何其他行动时，它会打谁、打多少（只是把牌面文字算清楚，不模拟双方交锋）
static func intent_of(st: Dictionary, act: Dictionary) -> Dictionary:
	var sk := E.skill_of(st, int(act.sid))
	var host := E.host_of(st, int(act.sid))
	var out := {"host": host, "side": int(act.side), "start": int(act.start), "name": str(sk.get("name", "")), "hits": [], "tags": []}
	var c := E.clone_state(st)
	var one: Dictionary = act.duplicate(true)
	E.run_round(c, [one])
	var by := {}
	for e in c.events:
		if not e.has("tgt") or int(e.get("src", host)) != host:
			continue
		var uid := int(e.tgt)
		if not by.has(uid):
			by[uid] = {"uid": uid, "dmg": 0, "heal": 0, "status": [], "t": int(e.t)}
		match e.type:
			"dmg": by[uid].dmg += int(e.amount)
			"heal": by[uid].heal += int(e.amount)
			"status": by[uid].status.append(str(e.status))
			"mit": by[uid].status.append("减伤")
	for uid in by:
		var h: Dictionary = by[uid]
		if h.dmg > 0 or h.heal > 0 or not h.status.is_empty():
			out.hits.append(h)
	for n in sk.get("nodes", []):
		_tags(n, out.tags)
	return out

static func _tags(n: Dictionary, tags: Array) -> void:
	match n.get("kind", ""):
		"watch":
			if not ("设伏" in tags):
				tags.append("设伏")
		"time":
			var t: String = {"delay": "延后", "advance": "提前", "interrupt": "打断"}.get(n.op, "时间术")
			if not (t in tags):
				tags.append(t)
		"swap":
			if not ("换位" in tags):
				tags.append("换位")
	for key in ["child", "first", "then", "else", "a", "b"]:
		if n.has(key) and n[key] is Dictionary and not n[key].is_empty():
			_tags(n[key], tags)
