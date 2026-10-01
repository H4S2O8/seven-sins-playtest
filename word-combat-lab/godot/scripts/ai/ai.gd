extends RefCounted
# 电脑对手：按“性格”构筑牌组、挑词袋、在对局中用模拟选择行动。
# 只读取公开信息：自己的词、双方公开的牌组与数字、已宣告的行动。

const G = preload("res://scripts/core/grammar.gd")
const E = preload("res://scripts/core/engine.gd")
const R = preload("res://scripts/core/recipes.gd")
const D = preload("res://scripts/core/deck.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const Coach = preload("res://scripts/core/coach.gd")

# 性格：技能优先序。每项 [模板, [参数变体，从强到弱], 默认填数]
const PERSONAS := {
	"狂攻": [
		["atkA", [{"dbl": 2, "rep": 1}, {"dbl": 1, "rep": 1}, {"dbl": 1}, {"rep": 1}, {}], 14],
		["atk1", [{"dbl": 2, "rep": 1}, {"dbl": 1, "rep": 1}, {"dbl": 1}, {"rep": 1}, {}], 16],
		["heal", [{"tgt": "self"}], 10],
		["copy", [{}], 12],
		["status", [{"st": "易伤"}, {"st": "狂振", "allyside": true, "tgt": "choose"}], 0],
		["mit", [{"tgt": "self"}], 20],
		["split", [{}], 18],
	],
	"守反": [
		["redirect", [{"obs": "all", "to": "source", "freq": "every"}, {"obs": "self", "to": "source", "freq": "every"}, {"obs": "self", "to": "source", "freq": "once"}], 0],
		["reflect", [{"obs": "all", "mult": 1, "freq": "every"}, {"obs": "self", "mult": 1, "freq": "every"}, {"obs": "self", "mult": 0, "freq": "every"}], 0],
		["atk1", [{"dbl": 1}, {}], 14],
		["convert", [{"obs": "all", "freq": "every"}, {"obs": "self", "freq": "every"}], 0],
		["mit", [{"tgt": "all"}, {"tgt": "self"}], 20],
		["heal", [{"tgt": "all"}, {"tgt": "self"}], 10],
		["shield", [{"tgt": "self"}], 15],
	],
	"控场": [
		["time", [{"op": "interrupt"}], 0],
		["atk1", [{"dbl": 1}, {}], 14],
		["status", [{"st": "沉默"}, {"st": "易伤"}], 0],
		["time", [{"op": "delay", "sec": 6}], 0],
		["remove", [{"what": "限时效果"}], 0],
		["tax", [{}], 10],
		["heal", [{"tgt": "self"}], 10],
	],
	"连锁": [
		["engine", [{"to": "all"}, {"to": "lowest"}], 10],
		["burst", [{}], 15],
		["atkA", [{"dbl": 1}, {}], 12],
		["tax", [{}], 10],
		["regen", [{}], 6],
		["atk1", [{}], 14],
		["heal", [{"tgt": "self"}], 10],
	],
	"均衡": [
		["atk1", [{"dbl": 1, "rep": 1}, {"dbl": 1}, {"rep": 1}, {}], 15],
		["redirect", [{"obs": "self", "to": "source", "freq": "every"}, {"obs": "self", "to": "source", "freq": "once"}], 0],
		["atkA", [{"dbl": 1}, {}], 12],
		["heal", [{"tgt": "self"}], 12],
		["mit", [{"tgt": "self"}], 20],
		["time", [{"op": "interrupt"}], 0],
		["status", [{"st": "易伤"}], 0],
	],
}
const KW_PREF := {
	"狂攻": ["不屈", "回击", "首挡"], "守反": ["首挡", "不屈", "回击", "回春"], "控场": ["不屈", "首挡", "回击"],
	"连锁": ["回春", "不屈", "首挡"], "均衡": ["首挡", "不屈", "回击", "回春"],
}
const PREFER_WORDS := {
	"狂攻": ["双倍", "重复", "全部", "每个", "复制"], "守反": ["转移", "来源", "当", "即将受到伤害", "转为", "受到伤害"],
	"控场": ["打断", "延后", "沉默", "易伤", "移除"], "连锁": ["恢复生命", "每次", "倒下", "发动技能", "回合结束"],
	"均衡": ["转移", "双倍", "打断", "全部"],
}

const PERSONA_LABEL := {
	"狂攻": "狂攻流：放大的大招先手压制，赌对手拆不掉",
	"守反": "守反流：设伏改道、回敬，让对手的大招反噬自己",
	"控场": "控场流：打断、沉默、拖节奏，让对手出不了招",
	"连锁": "连锁流：治疗引爆、遗志、收税，把对方的行动变成代价",
	"均衡": "均衡流：攻守兼备，稳扎稳打",
}
const PERSONA_ORDER := ["均衡", "狂攻", "守反", "控场", "连锁"]

static func pick_persona(rng: RandomNumberGenerator) -> String:
	var keys: Array = PERSONAS.keys()
	return keys[rng.randi() % keys.size()]

static func _avail(pool: Dictionary, used: Dictionary) -> Dictionary:
	var a := {}
	for w in pool:
		a[w] = int(pool[w]) - int(used.get(w, 0))
	return a

static func _add_used(used: Dictionary, words: Array) -> void:
	for w in words:
		used[w] = int(used.get(w, 0)) + 1

static func _has_param(tid: String, key: String) -> bool:
	for p in R.template(tid).get("params", []):
		if p.key == key:
			return true
	return false

static func _params_for(tid: String, variant: Dictionary, n: int) -> Dictionary:
	var p := variant.duplicate()
	if n > 0 and _has_param(tid, "n") and not p.has("n"):
		p["n"] = n
	return p

# ------------------------------------------------------------ 构筑
static func build_deck(pool: Dictionary, persona: String, rng: RandomNumberGenerator, num_cap: int = 42) -> Dictionary:
	var deck := D.new_deck()
	var used := {}
	var chosen: Array = []
	for entry in PERSONAS[persona]:
		if chosen.size() >= 5 * D.MAX_SKILLS:
			break
		var placed := false
		for v in entry[1]:
			var sk := R.build(entry[0], _params_for(entry[0], v, entry[2]))
			if G.missing(sk.words, _avail(pool, used)).is_empty():
				chosen.append(sk)
				_add_used(used, sk.words)
				placed = true
				break
		if not placed and entry[0] == "atk1":
			pass
	# 保底：至少一个攻击
	var has_atk := false
	for sk in chosen:
		if sk.kind_tag == "atk":
			has_atk = true
	if not has_atk:
		for tgt in ["choose", "lowest", "first", "last", "random", "highest"]:
			var sk2 := R.build("atk1", {"tgt": tgt, "n": 14})
			if G.missing(sk2.words, _avail(pool, used)).is_empty():
				if chosen.size() >= 5 * D.MAX_SKILLS:
					chosen.pop_back()
				chosen.append(sk2)
				_add_used(used, sk2.words)
				break
	_fit_and_place(deck, chosen, num_cap)
	_place_keywords(deck, pool, used, persona)
	_spread_hp(deck, chosen)
	_fill_empty_units(deck, pool)
	D.rename_skills(deck)
	return deck

# 让没有技能的卡也能“跑”起来：用剩下的词给它配一个便宜的自保/攻击技能
static func _fill_empty_units(deck: Dictionary, pool: Dictionary) -> void:
	var fallbacks := [
		["heal", {"tgt": "self", "n": 6}], ["mit", {"tgt": "self", "n": 10}], ["shield", {"tgt": "self", "n": 8}],
		["atk1", {"n": 6}], ["tax", {"n": 6}],
	]
	for i in 5:
		if not deck.units[i].skills.is_empty():
			continue
		for fb in fallbacks:
			var avail := Coach.free_words(pool, deck)
			var f := Coach.fit(["", fb[0], fb[1], "", 0.0, ""], avail)
			if int(f.n) != 0:
				continue
			var sk: Dictionary = f.skill
			var free: int = D.BUDGET - int(D.budget_used(deck).total)
			var need := int(sk.budget)
			if need > free:
				var can: int = maxi(0, int(deck.units[i].max_hp) - 6)
				var take: int = mini(can, need - free)
				deck.units[i].max_hp -= take
				free += take
			if need > free:
				continue
			deck.units[i].skills.append(sk)
			break

static func _fit_and_place(deck: Dictionary, chosen: Array, num_cap: int) -> void:
	var total := 0
	for sk in chosen:
		total += int(sk.budget)
	var f := 1.0
	if total > num_cap and total > 0:
		f = float(num_cap) / float(total)
	var skills: Array = []
	for sk in chosen:
		if f < 1.0 and sk.params.has("n"):
			var p: Dictionary = sk.params.duplicate()
			p["n"] = maxi(1, int(round(float(p.n) * f)))
			skills.append(R.build(sk.template, p))
		else:
			skills.append(sk)
	# 指派到卡：依次放到还有空槽的卡（每卡至多 MAX_SKILLS 个），放不下的丢弃
	for i in skills.size():
		var idx := -1
		for k in 5:
			var j: int = (i + k) % 5
			if deck.units[j].skills.size() < D.MAX_SKILLS:
				idx = j
				break
		if idx == -1:
			break
		deck.units[idx].skills.append(skills[i])

static func _place_keywords(deck: Dictionary, pool: Dictionary, used: Dictionary, persona: String) -> void:
	var avail := _avail(pool, used)
	var slot := 4
	for kw in KW_PREF[persona]:
		while int(avail.get(kw, 0)) > 0 and slot >= 0:
			deck.units[slot].kw = kw
			avail[kw] -= 1
			slot -= 1

static func _spread_hp(deck: Dictionary, chosen: Array) -> void:
	var nums := 0
	for u in deck.units:
		for sk in u.skills:
			nums += int(sk.budget)
	var hp_pool: int = D.BUDGET - nums
	var weights: Array = []
	var wsum := 0.0
	for u in deck.units:
		var w := 1.0
		for sk in u.skills:
			w += 0.45
			if sk.kind_tag == "trap" or sk.kind_tag == "def":
				w += 0.35
		weights.append(w)
		wsum += w
	var left := hp_pool
	for i in 5:
		var hp: int = maxi(1, int(floor(float(hp_pool) * weights[i] / wsum)))
		deck.units[i].max_hp = hp
		left -= hp
	var i2 := 0
	while left > 0:
		deck.units[i2 % 5].max_hp += 1
		left -= 1
		i2 += 1
	while left < 0:
		var big := 0
		for j in 5:
			if deck.units[j].max_hp > deck.units[big].max_hp:
				big = j
		deck.units[big].max_hp -= 1
		left += 1

# ------------------------------------------------------------ 调整（每次最多改一张卡）
static func adjust_step(deck: Dictionary, pool: Dictionary, persona: String, rng: RandomNumberGenerator) -> Dictionary:
	var used := D.used_counts(deck)
	var avail := _avail(pool, used)
	var have_sig := {}
	for u in deck.units:
		for sk in u.skills:
			have_sig[JSON.stringify(sk.get("params", {})) + sk.get("template", "")] = true
	var b := D.budget_used(deck)
	for entry in PERSONAS[persona]:
		for v in entry[1]:
			var params := _params_for(entry[0], v, entry[2])
			var sk := R.build(entry[0], params)
			var sig: String = JSON.stringify(sk.params) + sk.template
			if have_sig.has(sig):
				break # 已有这一条（更强的变体已装）
			if not G.missing(sk.words, avail).is_empty():
				continue
			# 找槽位：先找有空位的卡，否则替换本系列里优先级最低的技能
			var new_deck := D.clone(deck)
			var target := -1
			for i in 5:
				if new_deck.units[i].skills.size() < D.MAX_SKILLS:
					target = i
					break
			var replaced := -1
			if target == -1:
				var worst_rank := -1
				for i in 5:
					for k in new_deck.units[i].skills.size():
						var rank := _rank_of(persona, new_deck.units[i].skills[k])
						if rank > worst_rank:
							worst_rank = rank
							target = i
							replaced = k
				var my_rank := _rank_of_entry(persona, entry[0])
				if worst_rank <= my_rank:
					continue # 现有的都更重要
				new_deck.units[target].skills.remove_at(replaced)
			# 预算：放不下就从这张卡的生命里挤一点（不低于原来的60%，也不低于8），再不够就缩小填数
			var free: int = D.BUDGET - D.budget_used(new_deck).total
			var need := int(sk.budget)
			if need > free:
				var hp_now: int = int(new_deck.units[target].max_hp)
				var floor_hp: int = maxi(8, int(ceil(hp_now * 0.6)))
				var take: int = mini(maxi(0, hp_now - floor_hp), need - free)
				new_deck.units[target].max_hp -= take
				free += take
			if need > free and sk.params.has("n"):
				var p2: Dictionary = sk.params.duplicate()
				p2["n"] = maxi(4, int(p2.n) - (need - free))
				sk = R.build(sk.template, p2)
			if int(sk.budget) > free:
				continue
			if D.budget_used(new_deck).nums + int(sk.budget) > 50:
				continue
			new_deck.units[target].skills.append(sk)
			D.rename_skills(new_deck)
			if D.validate(new_deck, pool).ok:
				return new_deck
			break
	# 没有新技能可装：把空余点数加到最低血的卡
	return {}

static func _rank_of(persona: String, sk: Dictionary) -> int:
	return _rank_of_entry(persona, sk.get("template", ""))

static func _rank_of_entry(persona: String, tid: String) -> int:
	var list: Array = PERSONAS[persona]
	for i in list.size():
		if list[i][0] == tid:
			return i
	return 99

# ------------------------------------------------------------ 选词袋
static func pick_bag(bags: Array, pool: Dictionary, persona: String) -> int:
	var scores: Array = []
	for bag in bags:
		var s := 0.0
		var cnt := G.count_words(bag)
		for w in cnt:
			var info: Dictionary = Lex.get_word(w)
			var base: float = {"基础": 1.0, "进阶": 2.4, "奇术": 4.0}.get(info.rarity, 1.0)
			var have := int(pool.get(w, 0))
			var need_factor := 1.6 if have == 0 else (1.0 if have < 3 else 0.45)
			var pref := 1.0
			if w in PREFER_WORDS[persona]:
				pref = 1.8
			s += base * need_factor * pref * minf(float(cnt[w]), 2.0)
		scores.append(s)
	return 0 if scores[0] >= scores[1] else 1

# ------------------------------------------------------------ 战斗决策
static func _starts(ms: int, enemy_list: Array) -> Array:
	var out := [ms]
	var cand := [ms + 3, 10]
	for ea in enemy_list:
		if ea.is_empty():
			continue
		cand.append(int(ea.start))
		cand.append(int(ea.start) - 1)
		cand.append(int(ea.start) + 1)
	for c in cand:
		if c >= ms and c <= 19 and not (c in out):
			out.append(c)
	return out

static func _slot_options(st: Dictionary, side: int, slot: Dictionary, all_declared: Array) -> Array:
	var cands := E.slot_candidates(st, side, slot, all_declared)
	if slot.kind == "branch":
		return cands
	if slot.kind == "action":
		return cands.slice(0, 3)
	if slot.kind == "remove":
		var keep: Array = []
		for c in cands:
			# 优先：对方阵营的效果
			if str(c).begins_with("%d:" % (1 - side)):
				keep.append(c)
		if keep.is_empty():
			keep = cands
		return keep.slice(0, 3)
	# target：按生命排序挑代表
	var units: Array = []
	for uid in cands:
		units.append(E._u(st, uid))
	units.sort_custom(func(a, b): return a.hp < b.hp)
	var out: Array = []
	if not units.is_empty():
		out.append(units[0].uid)
		if units.size() > 1:
			out.append(units[units.size() - 1].uid)
		if units.size() > 2:
			out.append(units[units.size() / 2].uid)
	# 敌方：持有技能的随从更有价值
	if slot.spec.get("side", "enemy") == "enemy":
		for u in units:
			if not u.skill_ids.is_empty() and not (u.uid in out) and out.size() < 4:
				out.append(u.uid)
	return out

# enemy：对方已宣告的行动（单个字典或数组）；mine_declared：本方此前已宣告的行动
static func enumerate_actions(st: Dictionary, side: int, enemy, max_per_skill: int = 8, mine_declared: Array = []) -> Array:
	var enemy_list: Array = []
	if enemy is Dictionary:
		if not enemy.is_empty():
			enemy_list = [enemy]
	else:
		enemy_list = enemy
	var all_declared: Array = enemy_list + mine_declared
	var out: Array = [{}]
	var avail: int = E.available_ap(st, side, mine_declared)
	for u in E.alive_units(st, side):
		for sid in u.skill_ids:
			var sk := E.skill_of(st, sid)
			if int(sk.cost) > avail and not _has_choose(sk):
				continue
			var slots := G.choice_slots(sk)
			var combos: Array = [{}]
			for slot in slots:
				var opts := _slot_options(st, side, slot, all_declared)
				if opts.is_empty():
					if slot.kind == "action":
						continue # 没有对方行动可指：缺省作用于第一个，也允许
					combos = []
					break
				var nxt: Array = []
				for c in combos:
					for o in opts:
						var c2: Dictionary = c.duplicate()
						c2[slot.key] = o
						nxt.append(c2)
				combos = nxt
				if combos.size() > 24:
					combos = combos.slice(0, 24)
			var count := 0
			for ch in combos:
				var act := {"side": side, "sid": sid, "choices": ch, "start": 0}
				var ms := E.min_start(st, act)
				for s in _starts(ms, enemy_list):
					act.start = s
					if E.can_declare(st, act, mine_declared) == "":
						out.append(act.duplicate(true))
						count += 1
				if count >= max_per_skill * 3:
					break
	return out

static func _has_choose(sk: Dictionary) -> bool:
	for s in G.choice_slots(sk):
		if s.kind == "branch":
			return true
	return false

static func evaluate(st: Dictionary, side: int) -> float:
	if st.winner == side:
		return 1.0e6
	if st.winner == 1 - side:
		return -1.0e6
	if st.winner == -2:
		return 0.0
	var me: Dictionary = st.sides[side]
	var op: Dictionary = st.sides[1 - side]
	var v := float(me.score - op.score) * 1.5
	v += (_power(st, side) - _power(st, 1 - side))
	v += float(me.ap - op.ap) * 0.45
	return v

static func _power(st: Dictionary, s: int) -> float:
	var p := 0.0
	for u in st.sides[s].units:
		if u.down_round == -1:
			p += float(u.hp) + 6.0
			if not u.skill_ids.is_empty():
				p += 2.0
	return p

static func _sim(st: Dictionary, acts: Array) -> Dictionary:
	var c := E.clone_state(st)
	E.run_round(c, acts)
	return c

# 在“已宣告若干行动”的基础上，决定本方下一个行动；返回空字典表示不再宣告。
static func choose_action(st: Dictionary, side: int, enemy_list: Array, mine_declared: Array, rng: RandomNumberGenerator, fast: bool = false, epsilon: float = 0.0) -> Dictionary:
	var mine := enumerate_actions(st, side, enemy_list, 8, mine_declared)
	if mine.size() == 1:
		return {}
	# 失误：以 epsilon 的概率随手出一招（含不再宣告），用于“简单/普通”难度
	if epsilon > 0.0 and rng.randf() < epsilon:
		return mine[rng.randi() % mine.size()]
	var second: bool = not enemy_list.is_empty() or E.first_side(st) != side
	var best: Dictionary = {}
	if second:
		# 先手已把行动宣告完：逐个看“再加一个行动”是否比现在就停下更好
		var base_acts: Array = enemy_list + mine_declared
		var best_v := evaluate(_sim(st, base_acts), side) + 0.5
		for a in mine:
			if a.is_empty():
				continue
			var v := evaluate(_sim(st, base_acts + [a]), side) + rng.randf() * 1.5
			if v > best_v:
				best_v = v
				best = a
		return best
	# 先手：对“对方的若干应对”取折中；只有明显优于“现在就停下”才追加
	var replies := enumerate_actions(st, 1 - side, mine_declared, 8)
	var rep_scored: Array = []
	for r in replies:
		rep_scored.append({"a": r, "v": evaluate(_sim(st, mine_declared + [r]), 1 - side)})
	rep_scored.sort_custom(func(x, y): return x.v > y.v)
	var reps: Array = []
	for i in mini(3 if fast else 6, rep_scored.size()):
		reps.append(rep_scored[i].a)
	reps.append({})
	var pass_score := _blend(st, side, mine_declared, reps, rng)
	var pre: Array = []
	for a in mine:
		if a.is_empty():
			continue
		pre.append({"a": a, "v": evaluate(_sim(st, mine_declared + [a]), side)})
	pre.sort_custom(func(x, y): return x.v > y.v)
	var best_v2 := pass_score + 0.5
	for i in mini(4 if fast else 8, pre.size()):
		var cand: Dictionary = pre[i].a
		var sc := _blend(st, side, mine_declared + [cand], reps, rng)
		if sc > best_v2:
			best_v2 = sc
			best = cand
	return best

static func _blend(st: Dictionary, side: int, mine_acts: Array, reps: Array, rng: RandomNumberGenerator) -> float:
	var worst := INF
	var sum := 0.0
	for r in reps:
		var acts: Array = mine_acts.duplicate()
		if not r.is_empty():
			acts.append(_retime(st, r, mine_acts))
		var v := evaluate(_sim(st, acts), side)
		worst = minf(worst, v)
		sum += v
	return 0.65 * worst + 0.35 * (sum / float(reps.size())) + rng.randf() * 1.5

# 对方看见我的宣告后会在合法范围内调整起手：若我方在第t秒落地，对方倾向于同刻或更早
static func _retime(st: Dictionary, r: Dictionary, mine_acts: Array) -> Dictionary:
	if r.is_empty() or mine_acts.is_empty():
		return r
	var out: Dictionary = r.duplicate(true)
	var ms := E.min_start(st, out)
	var last: Dictionary = mine_acts[mine_acts.size() - 1]
	out.start = maxi(ms, mini(int(last.start), 19))
	return out

# 二手方式：宣告后把起手对齐到对方之前（若能）
static func describe_action(st: Dictionary, act: Dictionary) -> String:
	if act.is_empty():
		return "不行动"
	var sk := E.skill_of(st, act.sid)
	return "%s（第%d秒）" % [sk.name, act.start]
