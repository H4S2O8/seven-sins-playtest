extends RefCounted
# 结算引擎：20秒时间轴。纯规则，不含界面与随机发牌。
# 同一时刻顺序：时间改动 → 建立监听/减伤 → 移除/状态/换位 → 直接伤害治疗（深度优先，含触发）→ 净值结算 → 倒下。
# 一个直接事件开启一条因果链；链上同一监听器最多触发一次。

const G = preload("res://scripts/core/grammar.gd")

const TICKS := 20          # 0..19 为时间轴，20 为回合结束阶段
const STRIDE := 21         # 每轮占的绝对时间刻数
const DEFAULT_RULES := {"win_score": 100, "max_rounds": 10, "ap_gain": 15, "ap_cap": 60, "start_ap": 15}

# ================================================================ 状态创建
# deck: {units:[{name,max_hp,kw,skills:[skill…]}×5]}
static func make_state(decks: Array, first: int = 0, rules: Dictionary = {}, seed_val: int = 4242) -> Dictionary:
	var st := {
		"round": 0, "first": first, "sides": [], "effects": [], "next_eid": 1, "lib": {}, "seed": seed_val,
		"winner": -1, "rules": DEFAULT_RULES.duplicate(), "events": [], "acts": [], "items": [], "ledger": {},
		"guard": 0, "root_ctr": 0, "used": {}, "cur_t": 0, "abs_now": 0, "sid_ctr": 0, "log": [], "round_taken": {},
	}
	for k in rules:
		st.rules[k] = rules[k]
	for s in 2:
		var side := {"ap": int(st.rules.start_ap), "score": 0, "units": []}
		st.sides.append(side)
		set_deck(st, s, decks[s], true)
	return st

# 更新一方的牌组（构筑/调整）。
static func set_deck(st: Dictionary, s: int, deck: Dictionary, fresh: bool = false) -> void:
	var side: Dictionary = st.sides[s]
	for i in deck.units.size():
		var d: Dictionary = deck.units[i]
		var u: Dictionary
		if fresh:
			u = {"uid": s * 10 + i, "side": s, "name": d.name, "max_hp": int(d.max_hp), "hp": int(d.max_hp), "down_round": -1,
				"statuses": [], "kw": d.get("kw", ""), "kw_spent": false, "bonus": 0, "skill_ids": [], "glyph": d.get("glyph", "")}
			side.units.append(u)
		else:
			u = _u(st, s * 10 + i)
			var was_full: bool = u.hp == u.max_hp
			u.name = d.name
			u.max_hp = int(d.max_hp)
			u.hp = u.max_hp if was_full else mini(u.hp, u.max_hp)
			if u.kw != d.get("kw", ""):
				u.kw = d.get("kw", "")
				u.kw_spent = false
			u.skill_ids = []
		for sk in d.skills:
			st.sid_ctr += 1
			var sid: int = st.sid_ctr
			var copy: Dictionary = sk
			copy["sid"] = sid
			st.lib[sid] = copy
			u.skill_ids.append(sid)

static func clone_state(st: Dictionary) -> Dictionary:
	var c := st.duplicate(false)
	c.sides = []
	for s in st.sides:
		var ns: Dictionary = s.duplicate(false)
		ns.units = []
		for u in s.units:
			var nu: Dictionary = u.duplicate(true)
			ns.units.append(nu)
		c.sides.append(ns)
	c.effects = []
	for e in st.effects:
		c.effects.append(e.duplicate(false))
	c.round_taken = st.round_taken.duplicate()
	c.events = []
	c.items = []
	c.acts = []
	c.ledger = {}
	c.used = {}
	return c

# ================================================================ 查询
static func _u(st: Dictionary, uid: int) -> Dictionary:
	if uid < 0:
		return {}
	for u in st.sides[uid / 10].units:
		if u.uid == uid:
			return u
	return {}

static func _alive(u: Dictionary) -> bool:
	return not u.is_empty() and u.down_round == -1

static func alive_units(st: Dictionary, s: int) -> Array:
	var out: Array = []
	for u in st.sides[s].units:
		if u.down_round == -1:
			out.append(u)
	return out

static func _vhp(st: Dictionary, u: Dictionary) -> int:
	var L: Dictionary = st.ledger.get(u.uid, {})
	return int(L.v) if not L.is_empty() else int(u.hp)

static func position_of(st: Dictionary, uid: int) -> int:
	var units: Array = st.sides[uid / 10].units
	for i in units.size():
		if units[i].uid == uid:
			return i
	return -1

static func has_status(u: Dictionary, name: String) -> bool:
	for s in u.statuses:
		if s.name == name:
			return true
	return false

static func skill_of(st: Dictionary, sid: int) -> Dictionary:
	return st.lib.get(sid, {})

static func host_of(st: Dictionary, sid: int) -> int:
	for s in 2:
		for u in st.sides[s].units:
			if sid in u.skill_ids:
				return u.uid
	return -1

static func _rand(st: Dictionary, n: int) -> int:
	st.seed = (int(st.seed) * 1103515245 + 12345) & 0x7fffffff
	return ((int(st.seed) >> 8) % maxi(n, 1))

static func _active(st: Dictionary, eff: Dictionary) -> bool:
	return st.abs_now >= eff.from and st.abs_now < eff.until

# ================================================================ 回合
# 开始新的一轮：行动点、复出。返回复出的随从uid列表。
static func begin_round(st: Dictionary) -> Array:
	st.round += 1
	st.events = []
	st.used = {}
	st.round_taken = {}
	var revived: Array = []
	# 每一轮都是干净的：监听、减伤、状态、护盾、已存的升华增量都不跨轮
	st.effects = []
	for s in 2:
		var side: Dictionary = st.sides[s]
		side.ap = mini(int(side.ap) + int(st.rules.ap_gain), int(st.rules.ap_cap))
		for u in side.units:
			u.statuses = []
			u.bonus = 0
			if u.down_round != -1 and st.round >= u.down_round + 2:
				u.down_round = -1
				u.hp = u.max_hp
				u.statuses = []
				u.bonus = 0
				revived.append(u.uid)
	return revived

static func first_side(st: Dictionary) -> int:
	return (int(st.first) + (st.round - 1)) % 2

static func action_cost(st: Dictionary, act: Dictionary) -> int:
	var sk: Dictionary = skill_of(st, act.sid)
	if sk.is_empty():
		return 0
	return G.cost_with_choices(sk, act.get("choices", {}))

static func min_start(st: Dictionary, act: Dictionary) -> int:
	return mini(int(action_cost(st, act) / 10), 19)

# ================================================================ 宣告合法性
const MAX_ACTIONS := 8

# 本方在已宣告若干行动之后还剩多少行动点
static func available_ap(st: Dictionary, side: int, declared: Array) -> int:
	var ap: int = int(st.sides[side].ap)
	for d in declared:
		if not d.is_empty() and d.get("side", side) == side:
			ap -= action_cost(st, d)
	return ap

# declared：本方此前已宣告的行动（用于扣除行动点、禁止同一技能重复宣告）
static func can_declare(st: Dictionary, act: Dictionary, declared: Array = []) -> String:
	if act.is_empty() or act.get("sid", -1) < 0:
		return ""
	var mine_n := 0
	for d in declared:
		if d.is_empty() or d.get("side", act.side) != act.side:
			continue
		mine_n += 1
		if d.sid == act.sid:
			return "这个技能本轮已经宣告过了（想再来一次要用“重复”）"
	if mine_n >= MAX_ACTIONS:
		return "一轮最多宣告%d个行动" % MAX_ACTIONS
	var sk: Dictionary = skill_of(st, act.sid)
	if sk.is_empty():
		return "技能不存在"
	var host := _u(st, host_of(st, act.sid))
	if not _alive(host):
		return "持有者已倒下"
	var cost := action_cost(st, act)
	if _silenced_for(host, cost):
		return "持有者被沉默（压制操作费 ≤ %d 的技能）" % _silence_cap(host)
	if cost > available_ap(st, act.side, declared):
		return "行动点不足（需要%d，还剩%d）" % [cost, available_ap(st, act.side, declared)]
	if int(act.start) < min_start(st, act):
		return "起手需要至少%d秒" % min_start(st, act)
	for slot in G.choice_slots(sk):
		if slot.kind == "target" and not act.get("choices", {}).has(slot.key):
			return "还没有选择：" + slot.label
		if slot.kind == "branch" and not act.get("choices", {}).has(slot.key):
			return "还没有选择择一分支"
	return ""

# 某个选择槽的候选（uid 或 origin 字符串）
static func slot_candidates(st: Dictionary, side: int, slot: Dictionary, acts_declared: Array = []) -> Array:
	var out: Array = []
	if slot.kind == "target":
		var spec: Dictionary = slot.spec
		var s: int = side if spec.get("side", "enemy") == "ally" else 1 - side
		for u in alive_units(st, s):
			out.append(u.uid)
	elif slot.kind == "branch":
		out = [0, 1]
	elif slot.kind == "remove":
		for e in st.effects:
			if _active(st, e) or e.from > st.abs_now:
				out.append(e.origin)
		for a in acts_declared:
			if a.is_empty():
				continue
			var sk2 := skill_of(st, a.sid)
			_collect_installs(sk2, out, "%d:%d" % [a.side, a.sid])
	return out

static func _collect_installs(sk: Dictionary, out: Array, prefix: String) -> void:
	for n in sk.nodes:
		_collect_installs_node(n, out, prefix)

static func _collect_installs_node(n: Dictionary, out: Array, prefix: String) -> void:
	if n.kind in ["watch", "mit"]:
		out.append("%s:%d" % [prefix, n.id])
	for key in ["child", "first", "then", "else", "a", "b"]:
		if n.has(key) and n[key] is Dictionary and not n[key].is_empty():
			_collect_installs_node(n[key], out, prefix)

# ================================================================ 执行一轮
# acts：两个元素（按双方索引0/1），空字典表示不行动。act={side,sid,choices,start}
static func run_round(st: Dictionary, acts: Array) -> Dictionary:
	st.events = []
	st.items = []
	st.acts = []
	st.ledger = {}
	st.guard = 0
	st.winner = -1
	# 支付与排程
	var paid_by: Array = [[], []]
	for i in acts.size():
		var a: Dictionary = acts[i]
		if a.is_empty() or a.get("sid", -1) < 0:
			continue
		if can_declare(st, a, paid_by[a.side]) == "":
			var cost := action_cost(st, a)
			var rec := {"side": a.side, "active": true, "sid": a.sid, "choices": a.get("choices", {}), "start": int(a.start), "host": host_of(st, a.sid),
				"paid": cost, "cancelled": false, "idx": st.acts.size()}
			st.acts.append(rec)
			paid_by[a.side].append(a)
			_log(st, int(a.start), "declare", {"side": a.side, "sid": a.sid, "start": int(a.start), "cost": cost})
	# 行动点在全部校验完之后统一扣除（校验时已按累计算过）
	for sd in 2:
		for d in paid_by[sd]:
			st.sides[sd].ap -= action_cost(st, d)
	for ai in st.acts.size():
		var rec2: Dictionary = st.acts[ai]
		var sk2 := skill_of(st, rec2.sid)
		var ctx0 := {"side": rec2.side, "host": rec2.host, "choices": rec2.choices, "act": ai, "paid": rec2.paid,
			"invested": int(sk2.budget), "origin_prefix": "%d:%d" % [rec2.side, rec2.sid]}
		st.items.append({"t": rec2.start, "kind": "start", "act": ai, "ctx": ctx0, "node": {}})
		for n in sk2.nodes:
			_schedule(st, _node_tick(n, int(rec2.start)), n, ctx0)
	# 时间轴
	for t in TICKS:
		st.cur_t = t
		st.abs_now = (st.round - 1) * STRIDE + t
		_run_tick(st, t)
		if st.winner != -1:
			break
	if st.winner == -1:
		st.cur_t = TICKS
		st.abs_now = (st.round - 1) * STRIDE + TICKS
		_end_phase(st)
	_check_score_win(st)
	return {"events": st.events, "winner": st.winner}

static func _check_score_win(st: Dictionary) -> void:
	if st.winner != -1:
		return
	var w: int = st.rules.win_score
	var s0: int = st.sides[0].score
	var s1: int = st.sides[1].score
	if s0 >= w or s1 >= w:
		if s0 > s1:
			st.winner = 0
		elif s1 > s0:
			st.winner = 1

static func _log(st: Dictionary, t: int, type: String, data: Dictionary) -> void:
	var e := {"t": t, "type": type}
	for k in data:
		e[k] = data[k]
	st.events.append(e)

# 顶层节点落在时间轴的哪一秒：技能起点（由玩家在宣告时选的“起效时间”决定）；时间术另加“之后”的延后
static func _node_tick(n: Dictionary, start: int) -> int:
	var t := start
	if n.kind == "time":
		t += int(n.get("delay", 0))
	return t

static func _schedule(st: Dictionary, t: int, node: Dictionary, ctx: Dictionary) -> void:
	if t > TICKS - 1:
		_log(st, st.cur_t, "fizzle", {"why": "超出时间轴", "host": ctx.get("host", -1)})
		return
	st.items.append({"t": t, "kind": "node", "node": node, "ctx": ctx, "act": int(ctx.get("act", -1))})

static func _phase_of(item: Dictionary) -> int:
	if item.kind == "start":
		return -2
	var k: String = item.node.kind
	match k:
		"time": return -1
		"watch", "mit": return 0
		"remove", "status", "swap": return 1
	return 2

static func _run_tick(st: Dictionary, t: int) -> void:
	# 1. 状态到期
	_expire(st)
	# 2. 时间改动：先于一切，且双方同时生效
	var ops: Array = []
	var rest: Array = []
	for it in st.items:
		if it.t == t and it.kind == "node" and it.node.kind == "time":
			ops.append(it)
		else:
			rest.append(it)
	st.items = rest
	var live_ops: Array = []
	for it in ops:
		if not _cancelled(st, it):
			live_ops.append(it)
	if not live_ops.is_empty():
		_apply_time_ops(st, live_ops, t)
	# 3. 同刻施加的状态先于起手检查（沉默因此能挡住同一秒起手的技能）；双方对称
	var status_now: Array = []
	rest = []
	for it in st.items:
		if it.t == t and it.kind == "node" and it.node.kind == "status":
			status_now.append(it)
		else:
			rest.append(it)
	st.items = rest
	for it in status_now:
		if _cancelled(st, it):
			continue
		st.cur_t = t
		_exec(st, it.node, it.ctx)
	# 4. 起手：倒下/沉默检查，发动技能事件
	var starts: Array = []
	rest = []
	for it in st.items:
		if it.t == t and it.kind == "start":
			starts.append(it)
		else:
			rest.append(it)
	st.items = rest
	for it in starts:
		_start_action(st, it.act, t)
	# 4. 本刻的效果项目：阶段 → 宣告顺序
	var now: Array = []
	rest = []
	for it in st.items:
		if it.t == t and it.kind == "node":
			now.append(it)
		else:
			rest.append(it)
	st.items = rest
	var keyed: Array = []
	for i in now.size():
		keyed.append({"p": _phase_of(now[i]), "i": i, "it": now[i]})
	keyed.sort_custom(func(a, b): return a.p < b.p or (a.p == b.p and a.i < b.i))
	for k in keyed:
		if _cancelled(st, k.it):
			continue
		st.cur_t = t
		_exec(st, k.it.node, k.it.ctx)
	st.cur_t = t
	_settle(st, t)

static func _cancelled(st: Dictionary, it: Dictionary) -> bool:
	var a: int = it.get("act", -1)
	return a >= 0 and a < st.acts.size() and st.acts[a].cancelled

static func _start_action(st: Dictionary, ai: int, t: int) -> void:
	var rec: Dictionary = st.acts[ai]
	if rec.cancelled:
		return
	var host := _u(st, rec.host)
	if not _alive(host):
		rec.cancelled = true
		_log(st, t, "fizzle", {"why": "持有者已倒下", "host": rec.host})
		return
	if _silenced_for(host, int(rec.paid)):
		rec.cancelled = true
		_log(st, t, "fizzle", {"why": "被沉默", "host": rec.host})
		return
	_log(st, t, "start", {"side": rec.side, "sid": rec.sid, "host": rec.host})
	_fire(st, "cast", {"subject": rec.host, "src": rec.host, "recipient": rec.host, "amount": 0, "root": _new_root(st)}, false)

static func _apply_time_ops(st: Dictionary, ops: Array, t: int) -> void:
	# 先为每个操作确定目标行动，再同时应用。
	var shifts: Array = []
	for it in ops:
		var n: Dictionary = it.node
		var my: int = it.ctx.side
		var target_side: int = 1 - my if n.side == "enemy" else my
		var target_act := -1
		# 作用于“这一秒之后（含这一秒）第一个起效的行动”：按起效时间最早者，同秒取先宣告的；不含自己所在的行动
		var best_t := 999
		for si in st.items:
			if si.kind != "start" or si.t < t:
				continue
			var cand: Dictionary = st.acts[si.act]
			if cand.side != target_side or cand.cancelled or si.act == int(it.ctx.get("act", -1)):
				continue
			if si.t < best_t or (si.t == best_t and si.act < target_act):
				best_t = si.t
				target_act = si.act
		if target_act == -1 or st.acts[target_act].cancelled:
			_log(st, t, "time_fail", {"side": my, "why": "对方没有宣告技能"})
			continue
		var sec_v: int = _apply_mods(n, int(n.value.n)) if n.op == "interrupt" else int(n.value.n)
		shifts.append({"op": n.op, "sec": sec_v, "act": target_act, "by": my})
	for s in shifts:
		var moved: Array = []
		var kept: Array = []
		for it in st.items:
			if it.get("act", -1) == s.act and it.t >= t:
				moved.append(it)
			else:
				kept.append(it)
		# 同刻且尚未取出的项目：从 keyed 已取出的部分在下面补充处理
		st.items = kept
		var rec: Dictionary = st.acts[s.act]
		match s.op:
			"interrupt":
				if int(rec.paid) <= G.silence_limit(int(s.sec)):
					rec.cancelled = true
					_log(st, t, "interrupt", {"side": s.by, "target_side": rec.side, "lost": moved.size()})
				else:
					# 力度不足：对方的技能原样进行
					for it in moved:
						st.items.append(it)
					_log(st, t, "time_fail", {"side": s.by, "why": "打断力度不足（对方操作费 %d > %d）" % [int(rec.paid), G.silence_limit(int(s.sec))]})
			"delay":
				for it in moved:
					it.t = mini(it.t + int(s.sec), TICKS - 1)
					st.items.append(it)
				_log(st, t, "delay", {"side": s.by, "target_side": rec.side, "sec": s.sec})
			"advance":
				for it in moved:
					var minimum := maxi(t, _windup_of(st, rec))
					it.t = maxi(it.t - s.sec, minimum)
					st.items.append(it)
				_log(st, t, "advance", {"side": s.by, "target_side": rec.side, "sec": s.sec})

static func _silence_cap(u: Dictionary) -> int:
	var cap := 0
	for s in u.statuses:
		if s.name == "沉默":
			cap = maxi(cap, G.silence_limit(int(s.value)))
	return cap

static func _silenced_for(u: Dictionary, cost: int) -> bool:
	return has_status(u, "沉默") and cost <= _silence_cap(u)

static func _windup_of(st: Dictionary, rec: Dictionary) -> int:
	return mini(int(rec.paid / 10), 19)

# ================================================================ 目标与数值
static func _targets(st: Dictionary, spec: Dictionary, ctx: Dictionary, key: String = "") -> Array:
	var side: int = ctx.side if spec.get("side", "enemy") == "ally" else 1 - int(ctx.side)
	var out: Array = []
	match spec.pick:
		"self":
			var h := _u(st, ctx.host)
			if _alive(h):
				out.append(h.uid)
		"source":
			if _alive(_u(st, ctx.get("source", -1))):
				out.append(ctx.source)
		"recipient":
			if _alive(_u(st, ctx.get("recipient", -1))):
				out.append(ctx.recipient)
		"choose", "other":
			var uid: int = int(ctx.get("choices", {}).get(key, -1))
			if _alive(_u(st, uid)):
				out.append(uid)
		"all", "each":
			for u in alive_units(st, side):
				out.append(u.uid)
		"lowest", "highest":
			var best: Dictionary = {}
			for u in alive_units(st, side):
				if best.is_empty():
					best = u
				elif spec.pick == "lowest" and _vhp(st, u) < _vhp(st, best):
					best = u
				elif spec.pick == "highest" and _vhp(st, u) > _vhp(st, best):
					best = u
			if not best.is_empty():
				out.append(best.uid)
		"first":
			var al := alive_units(st, side)
			if not al.is_empty():
				out.append(al[0].uid)
		"last":
			var al2 := alive_units(st, side)
			if not al2.is_empty():
				out.append(al2[al2.size() - 1].uid)
		"random":
			var al3 := alive_units(st, side)
			if not al3.is_empty():
				out.append(al3[_rand(st, al3.size())].uid)
		"adjacent":
			var center: int = int(ctx.get(spec.get("center", "recipient"), ctx.get("recipient", -1)))
			var pos := position_of(st, center)
			if pos >= 0:
				var units: Array = st.sides[center / 10].units
				for d in [-1, 1]:
					var j: int = pos + d
					if j >= 0 and j < units.size() and _alive(units[j]):
						out.append(units[j].uid)
	return out

static func _value(st: Dictionary, v: Dictionary, ctx: Dictionary) -> int:
	match v.k:
		"num":
			return int(v.n)
		"ref":
			match v.ref:
				"event_damage", "event_heal": return int(ctx.get("ev_amount", 0))
				"actual": return int(ctx.get("actual", ctx.get("ev_amount", 0)))
				"raw": return int(ctx.get("raw", ctx.get("ev_amount", 0)))
				"overflow": return int(ctx.get("overflow", 0))
				"prev": return int(ctx.get("prev", 0))
				"ap": return int(st.sides[ctx.side].ap)
				"paid": return int(ctx.get("paid", 0))
				"invested": return int(ctx.get("invested", 0))
				"times": return int(ctx.get("times", 1))
				"count":
					var spec: Dictionary = v.get("of", G.T("all", "enemy"))
					return _targets(st, spec, ctx).size()
				"cur_hp", "max_hp", "lost_hp", "round_taken", "remaining":
					var spec2: Dictionary = v.get("of", G.T("self", "self"))
					var ts := _targets(st, spec2, ctx)
					if ts.is_empty():
						return 0
					var u := _u(st, ts[0])
					if v.ref == "round_taken":
						return int(st.round_taken.get(u.uid, 0))
					if v.ref == "remaining":
						var sh := 0
						for ss in u.statuses:
							if ss.name == "护盾":
								sh += int(ss.value)
						return sh
					if v.ref == "cur_hp":
						return _vhp(st, u)
					if v.ref == "max_hp":
						return int(u.max_hp)
					return int(u.max_hp) - _vhp(st, u)
			return 0
		"op":
			var a := _value(st, v.a, ctx)
			var b := _value(st, v.b, ctx)
			match v.op:
				"max": return maxi(a, b)
				"min": return mini(a, b)
				"sum": return a + b
				"diff": return absi(a - b)
	return 0

# 条件：比较，或“已生效”（目标身上有某状态）
static func _cond(st: Dictionary, c: Dictionary, ctx: Dictionary) -> bool:
	if c.has("has"):
		var ts := _targets(st, c.has.target, ctx)
		if ts.is_empty():
			return false
		return has_status(_u(st, ts[0]), c.has.status)
	var l := _value(st, c.left, ctx)
	var r := _value(st, c.right, ctx)
	return l < r if c.cmp == "lt" else l >= r

static func _apply_mods(node: Dictionary, amt: int) -> int:
	for i in int(node.get("dbl", 0)):
		amt *= 2
	for i in int(node.get("half", 0)):
		amt = (amt + 1) / 2
	return amt

static func _new_root(st: Dictionary) -> int:
	st.root_ctr += 1
	return st.root_ctr

static func _used(st: Dictionary, root: int) -> Dictionary:
	if not st.used.has(root):
		st.used[root] = {}
	return st.used[root]

# ================================================================ 节点执行
static func _exec(st: Dictionary, node: Dictionary, ctx: Dictionary) -> void:
	var t: int = st.cur_t
	var dl := int(node.get("delay", 0))
	if dl > 0 and not ctx.get("delayed", false):
		var c := ctx.duplicate()
		c["delayed"] = true
		_schedule(st, t + dl, node, c)
		return
	match node.kind:
		"dmg", "heal":
			_exec_effect(st, node, ctx)
		"mit":
			var pts := _apply_mods(node, _value(st, node.value, ctx))
			for uid in _targets(st, node.target, ctx, "t%d" % node.id):
				_install(st, {"type": "mit", "unit": uid, "mode": node.mode, "value": pts}, node, ctx, int(node.dur), "round")
				_log(st, t, "mit", {"tgt": uid, "mode": node.mode, "value": pts, "dur": int(node.dur)})
		"status":
			var val := _apply_mods(node, _value(st, node.value, ctx))
			for uid in _targets(st, node.target, ctx, "t%d" % node.id):
				var link := -1
				if node.has("link"):
					var ls := _targets(st, node.link, ctx, "l%d" % node.id)
					if not ls.is_empty():
						link = ls[0]
				_emit(st, {"kind": "status", "src": ctx.host, "tgt": uid, "status": node.status, "dur": int(node.dur), "value": val, "link": link,
					"root": int(ctx.get("root", _new_root(st)))})
		"remove":
			if node.what == "状态":
				for uid in _targets(st, node.target, ctx, "t%d" % node.id):
					var u := _u(st, uid)
					for s in u.statuses.duplicate():
						_remove_status(st, u, s)
					_log(st, t, "cleanse", {"tgt": uid})
			else:
				var origin: String = str(ctx.get("choices", {}).get("r%d" % node.id, ""))
				var tgts := _targets(st, node.target, ctx, "t%d" % node.id)
				var removed := 0
				var keep: Array = []
				for e in st.effects:
					if e.origin == origin and (e.host in tgts or e.get("unit", -2) in tgts):
						removed += 1
						_log(st, t, "effect_removed", {"eid": e.eid, "host": e.host})
					else:
						keep.append(e)
				st.effects = keep
				# 同刻尚未建立的（已排程但还没轮到）不能被移除：只清掉已经建立的效果。
				if removed == 0:
					_log(st, t, "remove_fail", {"why": "该效果尚未建立或不存在"})
		"watch":
			var cap := 0
			if node.child.kind in ["redirect", "convert"]:
				cap = _apply_mods(node.child, int(node.child.value.n))
			_install(st, {"type": "watch", "event": node.event, "freq": node.freq, "observe": node.observe, "child": node.child,
				"times": 0, "spent": false, "cap": cap, "caps": {}}, node, ctx, int(node.dur), node.life)
			_log(st, t, "watch_install", {"host": ctx.host, "side": ctx.side, "event": node.event, "text": G.node_text(node)})
		"time":
			# 顶层的时间改动由 _run_tick 统一处理；嵌在触发器/分支里的到这里按“立即生效”处理
			_apply_time_ops(st, [{"node": node, "ctx": ctx}], t)
		"swap":
			var ts2 := _targets(st, node.target, ctx, "t%d" % node.id)
			if not ts2.is_empty() and _alive(_u(st, ctx.host)) and ts2[0] != ctx.host:
				var units: Array = st.sides[ctx.side].units
				var a := position_of(st, ctx.host)
				var b := position_of(st, ts2[0])
				if a >= 0 and b >= 0:
					var tmp = units[a]
					units[a] = units[b]
					units[b] = tmp
					_log(st, t, "swap", {"a": ctx.host, "b": ts2[0]})
		"split":
			for i in node.branches.size():
				var br: Dictionary = node.branches[i]
				var c2 := ctx.duplicate()
				c2["delayed"] = true
				var tgts2 := _targets(st, br.target, ctx, "s%d_%d" % [node.id, i])
				var when := t + int(br.get("delay", 0))
				var fake := {"kind": node.verb, "alt": int(node.get("alt", 0)), "target": br.target, "value": G.N(int(br.part)), "id": node.id, "_fixed_targets": tgts2}
				if when == t:
					_exec_effect(st, fake, c2)
				else:
					_schedule(st, when, fake, c2)
		"chain":
			var c3 := ctx.duplicate()
			c3["on_actual"] = {"node": node.then, "ctx": ctx}
			_exec_effect(st, node.first, c3)
		"copy":
			var c4 := ctx.duplicate()
			c4["on_copy"] = {"spec": node.target, "key": "t%d" % node.id, "ctx": ctx}
			_exec_effect(st, node.first, c4)
		"if":
			if _cond(st, node.cond, ctx):
				_exec(st, node.then, ctx)
			elif node.has("else"):
				_exec(st, node["else"], ctx)
		"until":
			var it: int = int(ctx.get("iter", 0))
			if _cond(st, node.cond, ctx):
				return
			var c5 := ctx.duplicate()
			c5.erase("delayed")
			c5.erase("iter")
			_exec(st, node.child, c5)
			if it < G.UNTIL_MAX:
				var c6 := ctx.duplicate()
				c6["iter"] = it + 1
				c6["delayed"] = true
				_schedule(st, t + (int(node.get("gap", 0)) if int(node.get("gap", 0)) > 0 else 2), node, c6)
		"choose":
			var which: int = int(ctx.get("choices", {}).get("b%d" % node.id, 0))
			_exec(st, node.b if which == 1 else node.a, ctx)
		"redirect", "convert":
			pass # 只在“即将受到伤害”的待结算阶段由 _apply 处理

static func _exec_effect(st: Dictionary, node: Dictionary, ctx: Dictionary) -> void:
	var t: int = st.cur_t
	var targets: Array
	if node.has("_fixed_targets"):
		targets = node._fixed_targets
	else:
		targets = _targets(st, node.target, ctx, "t%d" % node.id)
	if ctx.has("only"):
		targets = [ctx.only] if ctx.only in targets else []
	# 逐个：每个目标错开一秒
	if node.target.pick == "each" and not ctx.has("only") and targets.size() > 1 and not node.get("sync", false):
		for i in targets.size():
			var c := ctx.duplicate()
			c["only"] = targets[i]
			c["delayed"] = true
			if i == 0:
				_exec_effect(st, node, c)
			else:
				_schedule(st, t + i, node, c)
		return
	# 重复
	var reps := int(node.get("rep", 0))
	if reps > 0 and not ctx.get("is_rep", false) and not node.get("sync", false):
		var gap: int = int(node.get("rep_gap", 0)) if int(node.get("rep_gap", 0)) > 0 else 2
		for k in range(1, reps + 1):
			var c2 := ctx.duplicate()
			c2["is_rep"] = true
			c2["delayed"] = true
			_schedule(st, t + gap * k, node, c2)
	var amt := _apply_mods(node, _value(st, node.value, ctx))
	for uid in targets:
		var e := {"kind": node.kind, "src": ctx.host, "tgt": uid, "amount": amt, "root": int(ctx.get("root", _new_root(st)))}
		if ctx.has("on_actual"):
			e["on_actual"] = ctx.on_actual
		if ctx.has("on_copy"):
			e["on_copy"] = ctx.on_copy
		_emit(st, e)
	# 同时：重复的各次在同一秒一起落下
	if reps > 0 and not ctx.get("is_rep", false) and node.get("sync", false):
		for k in reps:
			var c3 := ctx.duplicate()
			c3["is_rep"] = true
			c3["delayed"] = true
			_exec_effect(st, node, c3)

static func _emit(st: Dictionary, e: Dictionary) -> void:
	_fire(st, "targeted", {"subject": e.tgt, "src": e.src, "recipient": e.tgt, "amount": int(e.get("amount", 0)), "root": e.root}, false)
	_apply(st, e)

# ================================================================ 效果建立
static func _install(st: Dictionary, eff: Dictionary, node: Dictionary, ctx: Dictionary, dur: int, life: String) -> void:
	eff["eid"] = st.next_eid
	st.next_eid += 1
	eff["side"] = ctx.side
	eff["host"] = ctx.host
	eff["choices"] = ctx.get("choices", {})
	eff["paid"] = ctx.get("paid", 0)
	eff["invested"] = ctx.get("invested", 0)
	eff["origin"] = "%s:%d" % [ctx.get("origin_prefix", "%d:0" % ctx.side), node.id]
	eff["node_id"] = node.id
	eff["from"] = st.abs_now
	var round_end: int = st.round * STRIDE
	var until := round_end
	if life == "dur" or (eff.type != "watch" and dur > 0):
		until = mini(st.abs_now + maxi(dur, 1), round_end)
	eff["until"] = until
	st.effects.append(eff)

static func _remove_status(st: Dictionary, u: Dictionary, s: Dictionary) -> void:
	u.statuses.erase(s)
	_log(st, st.cur_t, "status_end", {"tgt": u.uid, "status": s.name})
	_fire(st, "status_end", {"subject": u.uid, "src": u.uid, "recipient": u.uid, "amount": 0, "root": _new_root(st)}, false)

static func _expire(st: Dictionary) -> void:
	for s in 2:
		for u in st.sides[s].units:
			for status in u.statuses.duplicate():
				if status.until <= st.abs_now:
					_remove_status(st, u, status)
	var keep: Array = []
	for e in st.effects:
		if e.until > st.abs_now:
			keep.append(e)
	st.effects = keep

# ================================================================ 监听触发
static func _observed(st: Dictionary, eff: Dictionary, subject: int) -> bool:
	var spec: Dictionary = eff.observe
	var sub := _u(st, subject)
	if sub.is_empty():
		return false
	var side: int = eff.side if spec.get("side", "enemy") == "ally" else 1 - int(eff.side)
	match spec.pick:
		"self":
			return subject == eff.host
		"all", "each":
			return sub.side == side
		"choose", "other":
			return subject == int(eff.choices.get("o%d" % int(eff.get("node_id", 0)), -1))
		"first":
			var al := alive_units(st, side)
			return not al.is_empty() and al[0].uid == subject
		"last":
			var al2 := alive_units(st, side)
			return not al2.is_empty() and al2[al2.size() - 1].uid == subject
		"lowest", "highest":
			var best: Dictionary = {}
			for u in alive_units(st, side):
				if best.is_empty() or (spec.pick == "lowest" and u.hp < best.hp) or (spec.pick == "highest" and u.hp > best.hp):
					best = u
			return not best.is_empty() and best.uid == subject
		"random":
			return sub.side == side
	return false

static func _node_id_of(eff: Dictionary) -> int:
	var parts: PackedStringArray = str(eff.origin).split(":")
	return int(parts[parts.size() - 1])

# defer=true：效果排到下一秒执行（倒下、复出等）
static func _fire(st: Dictionary, event: String, info: Dictionary, defer: bool) -> void:
	for eff in st.effects.duplicate():
		if eff.type != "watch" or eff.event != event:
			continue
		if not _active(st, eff) or eff.spent:
			continue
		var ck: String = eff.child.kind
		if ck == "redirect" or ck == "convert":
			continue
		match event:
			"ally_down":
				if _u(st, info.subject).side != eff.side:
					continue
			"enemy_down":
				if _u(st, info.subject).side == eff.side:
					continue
			"round_end":
				pass
			_:
				if not _observed(st, eff, info.subject):
					continue
		var used := _used(st, info.root)
		if used.has(eff.eid):
			continue
		used[eff.eid] = true
		if eff.freq == "once":
			eff.spent = true
		eff.times += 1
		var ctx := {"side": eff.side, "host": eff.host, "choices": eff.choices, "paid": eff.paid, "invested": eff.invested,
			"source": info.get("src", -1), "recipient": info.get("recipient", -1), "ev_amount": int(info.get("amount", 0)),
			"raw": int(info.get("raw", info.get("amount", 0))), "actual": int(info.get("amount", 0)), "overflow": int(info.get("overflow", 0)),
			"times": eff.times, "root": info.root, "act": -1, "origin_prefix": str(eff.origin).substr(0, str(eff.origin).rfind(":"))}
		_log(st, st.cur_t, "trigger", {"eid": eff.eid, "host": eff.host, "side": eff.side, "event": event, "subject": info.subject})
		if defer:
			_schedule(st, st.cur_t + 1, eff.child, ctx)
		else:
			_exec(st, eff.child, ctx)

# ================================================================ 事件结算
static func _ledger(st: Dictionary, u: Dictionary) -> Dictionary:
	if not st.ledger.has(u.uid):
		st.ledger[u.uid] = {"dmg": 0, "heal": 0, "v": int(u.hp)}
	return st.ledger[u.uid]

static func _apply(st: Dictionary, e: Dictionary) -> void:
	st.guard += 1
	if st.guard > 30000:
		return
	var tgt := _u(st, e.tgt)
	if not _alive(tgt):
		return
	var t: int = st.cur_t
	_fire(st, "hit", {"subject": e.tgt, "src": e.src, "recipient": e.tgt, "amount": int(e.get("amount", 0)), "root": e.root}, false)
	match e.kind:
		"dmg": _apply_damage(st, e, tgt, t)
		"heal": _apply_heal(st, e, tgt, t)
		"status": _apply_status(st, e, tgt, t)

static func _apply_damage(st: Dictionary, e: Dictionary, tgt: Dictionary, t: int) -> void:
	var used := _used(st, e.root)
	# 1. 待结算阶段：转移 / 转为 / 其他“即将受到伤害”监听
	for hop in 16:
		var rw: Dictionary = {}
		for eff in st.effects:
			if eff.type != "watch" or eff.event != "pending_dmg" or eff.spent or not _active(st, eff):
				continue
			if eff.child.kind != "redirect" and eff.child.kind != "convert":
				continue
			if used.has(eff.eid) or not _observed(st, eff, e.tgt):
				continue
			rw = eff
			break
		if rw.is_empty():
			break
		used[rw.eid] = true
		var used_cap: int = int(rw.caps.get(e.tgt, 0))
		var room: int = int(rw.cap) - used_cap
		if room <= 0:
			continue
		if rw.freq == "once":
			rw.spent = true
		rw.times += 1
		var moved: int = mini(room, int(e.amount))
		rw.caps[e.tgt] = used_cap + moved
		if rw.child.kind == "redirect":
			var ctx := {"side": rw.side, "host": rw.host, "choices": rw.choices, "source": e.src, "recipient": e.tgt}
			var to := _targets(st, rw.child.target, ctx, "t%d" % rw.child.id)
			if to.is_empty():
				rw.caps[e.tgt] = used_cap
				_log(st, t, "redirect_fail", {"tgt": e.tgt})
			else:
				_log(st, t, "redirect", {"from": e.tgt, "to": to[0], "amount": moved, "host": rw.host})
				_apply(st, {"kind": "dmg", "src": e.src, "tgt": to[0], "amount": moved, "root": e.root})
				e["amount"] = int(e.amount) - moved
				if int(e.amount) <= 0:
					return
				tgt = _u(st, e.tgt)
		else:
			_log(st, t, "convert", {"tgt": e.tgt, "amount": moved, "host": rw.host})
			_apply_heal(st, {"kind": "heal", "src": e.src, "tgt": e.tgt, "amount": moved, "root": e.root}, tgt, t)
			e["amount"] = int(e.amount) - moved
			if int(e.amount) <= 0:
				return
	_fire(st, "pending_dmg", {"subject": e.tgt, "src": e.src, "recipient": e.tgt, "amount": int(e.amount), "raw": int(e.amount), "root": e.root}, false)
	tgt = _u(st, e.tgt)
	if not _alive(tgt):
		return
	var amount: int = int(e.amount)
	e["raw"] = amount
	var src := _u(st, e.src)
	# 2. 状态修正（每个事件只算一次）
	if not e.get("mods_done", false):
		e["mods_done"] = true
		if not src.is_empty() and src.bonus > 0:
			amount += int(src.bonus)
			src.bonus = 0
		if not src.is_empty() and has_status(src, "狂振"):
			amount = (amount * 5 + 3) / 4
		if has_status(tgt, "狂振"):
			amount = (amount * 5 + 3) / 4
		if has_status(tgt, "易伤"):
			amount = (amount * 3 + 1) / 2
		# 牵连：先平分，再各自减伤
		for s in tgt.statuses:
			if s.name == "牵连" and s.link >= 0 and not e.get("no_link", false):
				var partner := _u(st, s.link)
				if _alive(partner):
					var half: int = amount / 2
					amount -= half
					if half > 0:
						var e2 := {"kind": "dmg", "src": e.src, "tgt": partner.uid, "amount": half, "root": e.root, "no_link": true, "mods_done": true}
						_log(st, t, "link_split", {"tgt": tgt.uid, "partner": partner.uid, "amount": half})
						_apply(st, e2)
				break
	# 3. 减伤窗口
	var fixed_cut := 0
	var keep_frac := 1.0
	for eff in st.effects:
		if eff.type == "mit" and eff.unit == tgt.uid and _active(st, eff):
			if eff.mode == "fixed":
				fixed_cut += int(eff.value) / 2
			else:
				keep_frac *= 1.0 - float(eff.value) / (float(eff.value) + 20.0)
	var dmg := maxi(0, amount - fixed_cut)
	dmg = int(ceil(float(dmg) * keep_frac - 0.0001))
	# 4. 护盾
	for s in tgt.statuses.duplicate():
		if s.name == "护盾" and dmg > 0:
			var ab := mini(int(s.value), dmg)
			s.value -= ab
			dmg -= ab
			_log(st, t, "shield", {"tgt": tgt.uid, "absorbed": ab})
			if s.value <= 0:
				_remove_status(st, tgt, s)
	# 5. 首挡
	if dmg > 0 and tgt.kw == "首挡" and not tgt.kw_spent:
		tgt.kw_spent = true
		dmg = 0
		_log(st, t, "block", {"tgt": tgt.uid})
	var L := _ledger(st, tgt)
	var actual := mini(dmg, int(L.v))
	if dmg > 0:
		st.round_taken[tgt.uid] = int(st.round_taken.get(tgt.uid, 0)) + dmg
	L.dmg += dmg
	L.v = maxi(0, int(L.v) - dmg)
	_log(st, t, "dmg", {"src": e.src, "tgt": tgt.uid, "amount": dmg, "raw": int(e.raw), "actual": actual})
	# 6. 实际失血后的触发
	if dmg > 0:
		var info := {"src": e.src, "recipient": tgt.uid, "amount": dmg, "raw": int(e.raw), "root": e.root}
		var i1 := info.duplicate()
		i1["subject"] = tgt.uid
		_fire(st, "damaged", i1, false)
		_fire(st, "lost", i1, false)
		var i2 := info.duplicate()
		i2["subject"] = e.src
		_fire(st, "dealt", i2, false)
		if tgt.kw == "回击" and not tgt.kw_spent and _alive(_u(st, e.src)) and e.src != tgt.uid:
			tgt.kw_spent = true
			_log(st, t, "keyword", {"tgt": tgt.uid, "kw": "回击"})
			_apply(st, {"kind": "dmg", "src": tgt.uid, "tgt": e.src, "amount": 1, "root": e.root})
	_after_actual(st, e, dmg, tgt)

static func _apply_heal(st: Dictionary, e: Dictionary, tgt: Dictionary, t: int) -> void:
	var amount: int = int(e.amount)
	if has_status(tgt, "升华"):
		tgt.bonus += amount
		_log(st, t, "bank", {"tgt": tgt.uid, "amount": amount})
		_after_actual(st, e, 0, tgt)
		return
	var L := _ledger(st, tgt)
	var act := mini(amount, int(tgt.max_hp) - int(L.v))
	act = maxi(act, 0)
	var overflow := amount - act
	L.heal += amount
	L.v = mini(int(tgt.max_hp), int(L.v) + amount)
	_log(st, t, "heal", {"src": e.src, "tgt": tgt.uid, "amount": amount, "actual": act})
	if act > 0:
		_fire(st, "healed", {"subject": tgt.uid, "src": e.src, "recipient": tgt.uid, "amount": act, "overflow": overflow, "root": e.root}, false)
		if tgt.kw == "回春" and not tgt.kw_spent:
			var low: Dictionary = {}
			for u in alive_units(st, tgt.side):
				if u.uid != tgt.uid and (low.is_empty() or _vhp(st, u) < _vhp(st, low)):
					low = u
			if not low.is_empty():
				tgt.kw_spent = true
				_log(st, t, "keyword", {"tgt": tgt.uid, "kw": "回春"})
				_apply(st, {"kind": "heal", "src": tgt.uid, "tgt": low.uid, "amount": 1, "root": e.root})
	_after_actual(st, e, act, tgt, overflow)

static func _apply_status(st: Dictionary, e: Dictionary, tgt: Dictionary, t: int) -> void:
	var name: String = e.status
	if tgt.kw == "免疫" + name:
		_log(st, t, "immune", {"tgt": tgt.uid, "status": name})
		return
	var until: int = st.round * STRIDE
	if int(e.get("dur", 0)) > 0:
		until = mini(st.abs_now + int(e.dur), until)
	for s in tgt.statuses.duplicate():
		if s.name == name:
			tgt.statuses.erase(s)
	var entry := {"name": name, "value": int(e.get("value", 0)), "link": int(e.get("link", -1)), "until": until, "src": e.src}
	tgt.statuses.append(entry)
	_log(st, t, "status", {"tgt": tgt.uid, "status": name, "dur": int(e.get("dur", 0)), "value": entry.value})
	_fire(st, "status_applied", {"subject": tgt.uid, "src": e.src, "recipient": tgt.uid, "amount": 0, "root": e.root}, false)
	if tgt.kw == "同调" and not tgt.kw_spent and not e.get("echo", false):
		for u in alive_units(st, tgt.side):
			if u.uid != tgt.uid:
				tgt.kw_spent = true
				_log(st, t, "keyword", {"tgt": tgt.uid, "kw": "同调"})
				_apply(st, {"kind": "status", "src": e.src, "tgt": u.uid, "status": name, "dur": int(e.get("dur", 0)), "value": entry.value,
					"link": -1, "root": e.root, "echo": true})
				break

# 接续 / 复制：读取实际数值后继续
static func _after_actual(st: Dictionary, e: Dictionary, actual: int, tgt: Dictionary, overflow: int = 0) -> void:
	if e.has("on_actual") and actual > 0:
		var oa: Dictionary = e.on_actual
		var c: Dictionary = oa.ctx.duplicate()
		c["prev"] = actual
		c["root"] = e.root
		c["recipient"] = tgt.uid
		c["source"] = e.src
		c["delayed"] = true
		_exec(st, oa.node, c)
	if e.has("on_copy") and actual > 0:
		var oc: Dictionary = e.on_copy
		var c2: Dictionary = oc.ctx.duplicate()
		c2["recipient"] = tgt.uid
		for uid in _targets(st, oc.spec, c2, oc.key):
			_emit(st, {"kind": e.kind, "src": e.src, "tgt": uid, "amount": actual, "root": e.root})

# ================================================================ 净值结算
static func _settle(st: Dictionary, t: int) -> void:
	var downs: Array = []
	for s in 2:
		for u in st.sides[s].units:
			if u.down_round != -1 or not st.ledger.has(u.uid):
				continue
			var L: Dictionary = st.ledger[u.uid]
			var hp: int = clampi(int(u.hp) - int(L.dmg) + int(L.heal), 0, int(u.max_hp))
			if hp == 0 and u.kw == "不屈" and not u.kw_spent:
				u.kw_spent = true
				hp = 1
				_log(st, t, "keyword", {"tgt": u.uid, "kw": "不屈"})
			u.hp = hp
			if hp == 0:
				downs.append(u)
			_log(st, t, "hp", {"tgt": u.uid, "hp": hp})
	st.ledger = {}
	for u in downs:
		u.down_round = st.round
		u.statuses = []
		st.sides[1 - u.side].score += int(u.max_hp)
		_log(st, t, "down", {"tgt": u.uid, "score_side": 1 - u.side, "score": int(u.max_hp)})
	for u in downs:
		var root := _new_root(st)
		var info := {"subject": u.uid, "src": u.uid, "recipient": u.uid, "amount": 0, "root": root}
		_fire(st, "down", info, true)
		_fire(st, "ally_down", info, true)
		_fire(st, "enemy_down", info, true)
	# 全灭只给对方满额分数与一整轮的行动真空，不直接结束比赛；胜负按分数在回合结束时判定

static func _wiped(st: Dictionary, s: int) -> bool:
	for u in st.sides[s].units:
		if u.down_round == -1:
			return false
	return true

static func _end_phase(st: Dictionary) -> void:
	_expire(st)
	# 回合结束监听：每个监听器各开一条链
	for eff in st.effects.duplicate():
		if eff.type == "watch" and eff.event == "round_end" and _active(st, eff) and not eff.spent:
			_fire(st, "round_end", {"subject": eff.host, "src": eff.host, "recipient": eff.host, "amount": 0, "root": _new_root(st)}, false)
	# 处理此阶段排入的项目
	var guard := 0
	while guard < 50:
		guard += 1
		var batch: Array = []
		var rest: Array = []
		for it in st.items:
			if it.t >= TICKS - 1 and it.t <= TICKS:
				batch.append(it)
			else:
				rest.append(it)
		st.items = rest
		if batch.is_empty():
			break
		for it in batch:
			_exec(st, it.node, it.ctx)
	_settle(st, TICKS)
