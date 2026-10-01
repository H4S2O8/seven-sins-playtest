extends RefCounted
# 技能语法：节点树 → 所需词 / 费用 / 合法性 / 人话。
# 词按词名计数；同名词卡可互换。所有玩家与AI建出的技能都是这里的节点树。

const Lex = preload("res://scripts/core/lexicon.gd")

const START_FEE := 5
const SIDE_WORD := {"ally": "友方", "enemy": "敌方"}
const SIDE_TEXT := {"ally": "友方", "enemy": "敌方"}

const EVENT_WORD := {
	"pending_dmg": "即将受到伤害", "damaged": "受到伤害", "dealt": "造成伤害", "healed": "恢复生命",
	"lost": "失去生命", "targeted": "被选为目标", "cast": "发动技能", "hit": "技能命中",
	"status_applied": "状态施加", "status_end": "状态结束", "down": "倒下", "ally_down": "队友倒下",
	"enemy_down": "敌人倒下", "round_end": "回合结束",
}
const EVENT_TEXT := {
	"pending_dmg": "即将受到伤害", "damaged": "受到伤害", "dealt": "造成伤害", "healed": "恢复生命",
	"lost": "失去生命", "targeted": "被选为目标", "cast": "发动技能", "hit": "被技能命中",
	"status_applied": "被施加状态", "status_end": "状态结束", "down": "倒下", "ally_down": "有友方倒下",
	"enemy_down": "有敌方倒下", "round_end": "本轮结束",
}
const NO_OBSERVE := ["ally_down", "enemy_down", "round_end"]
const REF_WORD := {
	"event_damage": "该次伤害", "event_heal": "该次治疗", "actual": "实际数值", "raw": "原始数值",
	"cur_hp": "当前生命", "max_hp": "生命上限", "lost_hp": "失去的生命", "count": "人数", "times": "次数",
	"ap": "可用行动点", "paid": "支付的行动点", "invested": "已投入数字", "overflow": "溢出", "prev": "",
	"round_taken": "本轮", "remaining": "剩余",
}
const UNTIL_MAX := 4       # “直到”最多重复执行的次数（首次之外），每次重新付数字
const REF_TEXT := {
	"event_damage": "这次伤害", "event_heal": "这次治疗", "actual": "实际数值", "raw": "原始数值",
	"cur_hp": "当前生命", "max_hp": "生命上限", "lost_hp": "已损失生命", "count": "人数", "times": "本轮已触发的次数",
	"ap": "剩余行动点", "paid": "已支付的行动点", "invested": "这个技能投入的数字", "overflow": "溢出的治疗", "prev": "上一步的实际数值",
	"round_taken": "本轮累计受到的伤害", "remaining": "剩余护盾量",
}
const OP_WORD := {"max": "较高者", "min": "较低者", "sum": "合计", "diff": "差值"}
const OP_TEXT := {"max": "较高者", "min": "较低者", "sum": "合计", "diff": "差值"}
const STATUSES := ["狂振", "牵连", "升华", "护盾", "易伤", "沉默"]
const STATUS_DESC := {
	"狂振": "造成与受到的伤害各+25%", "牵连": "与另一名友方平分受到的伤害", "升华": "受到的治疗不回血，转为下次造成伤害的增量",
	"护盾": "吸收所填数值的伤害", "易伤": "受到的伤害+50%", "沉默": "压制操作费不超过 1.25×力度 的技能",
}

# ---------------------------------------------------------------- 目标式
static func T(pick: String, side: String = "enemy", extra: Dictionary = {}) -> Dictionary:
	var t := {"pick": pick, "side": side}
	for k in extra:
		t[k] = extra[k]
	return t

static func target_words(t: Dictionary) -> Array:
	var s: String = SIDE_WORD.get(t.get("side", ""), "")
	match t.pick:
		"self": return ["自身"]
		"source": return ["来源"]
		"recipient": return ["接受者"]
		"choose": return ["选择", "目标", "一个", s, "随从"]
		"all": return ["全部", s, "随从"]
		"each": return ["每个", s, "随从"]
		"lowest": return ["最低生命", s, "随从"]
		"highest": return ["最高生命", s, "随从"]
		"first": return ["最前", s, "随从"]
		"last": return ["最后", s, "随从"]
		"random": return ["随机", s, "随从"]
		"other": return ["另一个", s, "随从"]
		"adjacent": return ["相邻", s, "随从"]
	return []

static func target_text(t: Dictionary) -> String:
	var s: String = SIDE_TEXT.get(t.get("side", ""), "")
	match t.pick:
		"self": return "自身"
		"source": return "来源随从"
		"recipient": return "被作用的随从"
		"choose": return "你选的一个" + s + "随从"
		"all": return "全部" + s + "随从"
		"each": return "每一个" + s + "随从"
		"lowest": return "生命最低的" + s + "随从"
		"highest": return "生命最高的" + s + "随从"
		"first": return "最前面的" + s + "随从"
		"last": return "最后面的" + s + "随从"
		"random": return "随机一个" + s + "随从"
		"other": return "另一个" + s + "随从"
		"adjacent": return "相邻的" + s + "随从"
	return "?"

static func is_single_pick(t: Dictionary) -> bool:
	return not (t.pick in ["all", "each", "adjacent"])

static func needs_choice(t: Dictionary) -> bool:
	return t.pick == "choose" or t.pick == "other"

# ---------------------------------------------------------------- 数值式
static func N(n: int) -> Dictionary:
	return {"k": "num", "n": n}

static func REF(ref: String, of: Dictionary = {}) -> Dictionary:
	var v := {"k": "ref", "ref": ref}
	if not of.is_empty():
		v["of"] = of
	return v

static func OP(op: String, a: Dictionary, b: Dictionary) -> Dictionary:
	return {"k": "op", "op": op, "a": a, "b": b}

static func value_words(v: Dictionary) -> Array:
	match v.k:
		"num": return []
		"ref":
			var out: Array = []
			if REF_WORD[v.ref] != "":
				out.append(REF_WORD[v.ref])
			if v.has("of"):
				out.append_array(target_words(v.of))
			return out
		"op":
			var out2: Array = [OP_WORD[v.op]]
			out2.append_array(value_words(v.a))
			out2.append_array(value_words(v.b))
			return out2
	return []

static func value_nums(v: Dictionary) -> int:
	match v.k:
		"num": return int(v.n)
		"op": return value_nums(v.a) + value_nums(v.b)
	return 0

static func value_text(v: Dictionary) -> String:
	match v.k:
		"num": return str(int(v.n))
		"ref":
			var s: String = REF_TEXT[v.ref]
			if v.has("of"):
				s = target_text(v.of) + "的" + s
			return s
		"op":
			var a := value_text(v.a)
			var b := value_text(v.b)
			match v.op:
				"max": return "%s 与 %s 中较大的" % [a, b]
				"min": return "%s 与 %s 中较小的" % [a, b]
				"sum": return "%s 加 %s" % [a, b]
				"diff": return "%s 与 %s 的差" % [a, b]
	return "?"

# 数值套上 双倍/一半 之后的人话：数字直接给最终值；非数字（引用）写“2倍的…”
static func _num_text(node: Dictionary, v: Dictionary) -> String:
	if v.k == "num":
		return str(effective_num(node))
	var suf := ""
	var d := int(node.get("dbl", 0))
	var h := int(node.get("half", 0))
	if d > 0:
		suf += "的 %d 倍" % (1 << d)
	if h > 0:
		suf += ("的一半" if h == 1 else "的 1/%d" % (1 << h))
	return value_text(v) + suf

static func _after_text(node: Dictionary) -> String:
	var d := int(node.get("delay", 0))
	return ("%d 秒后，" % d) if d > 0 else ""

static func _dur_text(dur: int) -> String:
	return "，持续 %d 秒" % dur if dur > 0 else "，持续到本轮结束"

# ---------------------------------------------------------------- 节点构造
static func dmg(target: Dictionary, value: Dictionary, o: Dictionary = {}) -> Dictionary:
	var n := {"kind": "dmg", "alt": 0, "target": target, "value": value}
	for k in o:
		n[k] = o[k]
	return n

static func heal(target: Dictionary, value: Dictionary, o: Dictionary = {}) -> Dictionary:
	var n := {"kind": "heal", "alt": 0, "target": target, "value": value}
	for k in o:
		n[k] = o[k]
	return n

static func mit(target: Dictionary, mode: String, value: int, dur: int = 0) -> Dictionary:
	return {"kind": "mit", "target": target, "mode": mode, "value": N(value), "dur": dur}

static func status(name: String, target: Dictionary, dur: int = 0, value: int = 0, link: Dictionary = {}) -> Dictionary:
	var n := {"kind": "status", "status": name, "target": target, "dur": dur, "value": N(value)}
	if not link.is_empty():
		n["link"] = link
	return n

static func remove(what: String, target: Dictionary) -> Dictionary:
	return {"kind": "remove", "what": what, "target": target}

static func watch(event: String, observe: Dictionary, child: Dictionary, o: Dictionary = {}) -> Dictionary:
	var n := {"kind": "watch", "event": event, "observe": observe, "child": child, "freq": "once", "life": "round", "dur": 0}
	for k in o:
		n[k] = o[k]
	return n

static func redirect(target: Dictionary, cap: int = 20) -> Dictionary:
	return {"kind": "redirect", "target": target, "value": N(cap)}

static func convert_heal(cap: int = 20) -> Dictionary:
	return {"kind": "convert", "value": N(cap)}

static func time_op(op: String, side: String, seconds: int = 0) -> Dictionary:
	return {"kind": "time", "op": op, "side": side, "value": N(seconds)}

static func swap(target: Dictionary) -> Dictionary:
	return {"kind": "swap", "target": target}

static func split(verb: String, total: int, branches: Array, alt: int = 0) -> Dictionary:
	return {"kind": "split", "verb": verb, "alt": alt, "total": total, "branches": branches}

static func chain(first: Dictionary, then: Dictionary) -> Dictionary:
	return {"kind": "chain", "first": first, "then": then}

static func copy_to(first: Dictionary, target: Dictionary) -> Dictionary:
	return {"kind": "copy", "first": first, "target": target}

static func if_node(cond: Dictionary, then: Dictionary, els: Dictionary = {}) -> Dictionary:
	var n := {"kind": "if", "cond": cond, "then": then}
	if not els.is_empty():
		n["else"] = els
	return n

static func pick_one(a: Dictionary, b: Dictionary) -> Dictionary:
	return {"kind": "choose", "a": a, "b": b}

static func until_node(cond: Dictionary, child: Dictionary, gap: int = 0) -> Dictionary:
	return {"kind": "until", "cond": cond, "child": child, "gap": gap}

static func has_cond(target: Dictionary, status_name: String) -> Dictionary:
	return {"has": {"target": target, "status": status_name}}

static func cmp_cond(left: Dictionary, cmp: String, right: Dictionary) -> Dictionary:
	return {"left": left, "cmp": cmp, "right": right}

static func cond_words(c: Dictionary) -> Array:
	if c.has("has"):
		var w: Array = ["已生效", c.has.status]
		w.append_array(target_words(c.has.target))
		return w
	var out: Array = value_words(c.left)
	out.append_array(value_words(c.right))
	return out

static func cond_nums(c: Dictionary) -> int:
	if c.has("has"):
		return 0
	return value_nums(c.left) + value_nums(c.right)

static func cond_text(c: Dictionary) -> String:
	if c.has("has"):
		return "%s身上有【%s】" % [target_text(c.has.target), c.has.status]
	return "%s %s %s" % [value_text(c.left), "低于" if c.cmp == "lt" else "不低于", value_text(c.right)]

static func cond_check(c: Dictionary, out: Array, ctx: String) -> void:
	if c.has("has"):
		if not (c.has.status in STATUSES):
			out.append("未知状态：" + str(c.has.status))
		_check_target(c.has.target, out, ctx != "")
	else:
		_check_value(c.left, out, ctx)
		_check_value(c.right, out, ctx)

static func skill(name: String, nodes: Array) -> Dictionary:
	return {"name": name, "nodes": nodes}

# ---------------------------------------------------------------- 词与数字
static func verb_words(kind: String, alt: int) -> Array:
	if kind == "dmg":
		return ["造成", "伤害"] if alt == 0 else ["减少", "当前生命"]
	return ["恢复", "生命"] if alt == 0 else ["增加", "当前生命"]

static func _rep(word: String, n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(word)
	return out

static func words_of(node: Dictionary) -> Array:
	var w := _words_core(node)
	if node.get("sync", false):
		w.append("同时")
	return w

static func _words_core(node: Dictionary) -> Array:
	var w: Array = []
	match node.kind:
		"dmg", "heal":
			w.append_array(verb_words(node.kind, int(node.get("alt", 0))))
			w.append_array(target_words(node.target))
			w.append_array(value_words(node.value))
			w.append_array(_rep("双倍", int(node.get("dbl", 0))))
			w.append_array(_rep("一半", int(node.get("half", 0))))
			w.append_array(_rep("重复", int(node.get("rep", 0))))
			if int(node.get("rep_gap", 0)) > 0:
				w.append("间隔")
			if int(node.get("delay", 0)) > 0:
				w.append("之后")
		"mit":
			w.append("减伤")
			w.append_array(target_words(node.target))
			w.append_array(_rep("双倍", int(node.get("dbl", 0))))
			if int(node.dur) > 0:
				w.append("持续")
			if int(node.get("delay", 0)) > 0:
				w.append("之后")
		"status":
			w.append("施加")
			w.append(node.status)
			w.append_array(target_words(node.target))
			w.append_array(_rep("双倍", int(node.get("dbl", 0))))
			if node.has("link"):
				w.append_array(target_words(node.link))
			if int(node.dur) > 0:
				w.append("持续")
			if int(node.get("delay", 0)) > 0:
				w.append("之后")
		"remove":
			w.append("移除")
			w.append(node.what)
			w.append_array(target_words(node.target))
			if int(node.get("delay", 0)) > 0:
				w.append("之后")
		"watch":
			w.append("当")
			w.append(EVENT_WORD[node.event])
			if node.freq == "every":
				w.append("每次")
			if not (node.event in NO_OBSERVE):
				w.append_array(target_words(node.observe))
			if node.life == "dur":
				w.append("持续")
			w.append_array(words_of(node.child))
			if int(node.get("delay", 0)) > 0:
				w.append("之后")
		"redirect":
			w.append("转移")
			w.append_array(target_words(node.target))
			w.append_array(_rep("双倍", int(node.get("dbl", 0))))
		"convert":
			w.append("转为")
			w.append_array(["恢复", "生命"])
			w.append_array(_rep("双倍", int(node.get("dbl", 0))))
		"time":
			w.append({"delay": "延后", "advance": "提前", "interrupt": "打断"}[node.op])
			w.append(SIDE_WORD[node.side])
			w.append("技能")
			w.append_array(_rep("双倍", int(node.get("dbl", 0))))
			if int(node.get("delay", 0)) > 0:
				w.append("之后")
		"swap":
			w.append("换位")
			w.append_array(target_words(node.target))
			if int(node.get("delay", 0)) > 0:
				w.append("之后")
		"split":
			w.append("分流")
			w.append_array(verb_words(node.verb, int(node.get("alt", 0))))
			var any_delay := false
			for b in node.branches:
				w.append_array(target_words(b.target))
				if int(b.get("delay", 0)) > 0:
					any_delay = true
			if any_delay:
				w.append("间隔")
		"chain":
			w.append("接续")
			w.append_array(words_of(node.first))
			w.append_array(words_of(node.then))
		"copy":
			w.append("复制")
			w.append_array(words_of(node.first))
			w.append_array(target_words(node.target))
		"until":
			w.append("直到")
			w.append_array(cond_words(node.cond))
			w.append_array(words_of(node.child))
			if int(node.get("gap", 0)) > 0:
				w.append("间隔")
		"if":
			w.append("若")
			w.append_array(cond_words(node.cond))
			w.append_array(words_of(node.then))
			if node.has("else"):
				w.append("否则")
				w.append_array(words_of(node["else"]))
		"choose":
			w.append("择一")
			w.append_array(words_of(node.a))
			w.append_array(words_of(node.b))
	return w

# 技能的全部词（含“并”）
static func skill_words(sk: Dictionary) -> Array:
	var w: Array = []
	for n in sk.nodes:
		w.append_array(words_of(n))
	if sk.nodes.size() > 1:
		w.append_array(_rep("并", sk.nodes.size() - 1))
	return w

# 构筑数字与行动点数字： {budget, ap}
static func nums_of(node: Dictionary, choices: Dictionary = {}) -> Dictionary:
	var b := 0
	var ap := 0
	match node.kind:
		"dmg", "heal":
			var v := value_nums(node.value)
			var times := 1 + int(node.get("rep", 0))
			b += v
			ap += v * times
		"mit":
			b += int(node.value.n) + int(node.dur)
			ap += int(node.value.n) + int(node.dur)
		"status":
			b += int(node.value.n) + int(node.dur)
			ap += int(node.value.n) + int(node.dur)
		"watch":
			var c := nums_of(node.child, choices)
			var d := int(node.dur) if node.life == "dur" else 0
			b += c.budget + d
			ap += c.ap + d
		"redirect", "convert":
			b += int(node.value.n)
			ap += int(node.value.n)
		"remove", "swap":
			pass
		"time":
			b += int(node.value.n)
			ap += int(node.value.n)
		"split":
			b += int(node.total)
			ap += int(node.total)
		"chain":
			var a1 := nums_of(node.first, choices)
			var a2 := nums_of(node.then, choices)
			b += a1.budget + a2.budget
			ap += a1.ap + a2.ap
		"copy":
			var a3 := nums_of(node.first, choices)
			b += a3.budget
			ap += a3.ap
		"until":
			var uc := nums_of(node.child, choices)
			b += uc.budget + cond_nums(node.cond)
			ap += uc.ap * (1 + UNTIL_MAX) + cond_nums(node.cond)
		"if":
			b += cond_nums(node.cond)
			ap += cond_nums(node.cond)
			var t1 := nums_of(node.then, choices)
			b += t1.budget
			ap += t1.ap
			if node.has("else"):
				var t2 := nums_of(node["else"], choices)
				b += t2.budget
				ap += t2.ap
		"choose":
			var c1 := nums_of(node.a, choices)
			var c2 := nums_of(node.b, choices)
			b += c1.budget + c2.budget
			# 宣告时只选一棵，只付所选；未传入选择时显示较贵的一棵作为上界
			if choices.has("b%d" % node.id):
				ap += c2.ap if int(choices["b%d" % node.id]) == 1 else c1.ap
			else:
				ap += maxi(c1.ap, c2.ap)
	return {"budget": b, "ap": ap}

static func skill_nums(sk: Dictionary, choices: Dictionary = {}) -> Dictionary:
	var b := 0
	var ap := 0
	for n in sk.nodes:
		var r := nums_of(n, choices)
		b += r.budget
		ap += r.ap
	return {"budget": b, "ap": ap}

static func cost_with_choices(sk: Dictionary, choices: Dictionary) -> int:
	return START_FEE + int(skill_nums(sk, choices).ap) + int(sk.price)

static func words_price(words: Array) -> int:
	var p := 0
	for w in words:
		p += Lex.price(w)
	return p

# 补全技能的派生字段：编号、词、价格、费用、起手、文字。
static func finalize(sk: Dictionary) -> Dictionary:
	var counter := [0]
	for n in sk.nodes:
		_assign_ids(n, counter)
	sk["words"] = skill_words(sk)
	sk["price"] = words_price(sk.words)
	var nums := skill_nums(sk)
	sk["budget"] = nums.budget
	sk["ap_nums"] = nums.ap
	sk["cost"] = START_FEE + nums.ap + sk.price
	sk["windup"] = int(sk.cost / 10)
	sk["text"] = describe(sk)
	sk["kind_tag"] = kind_tag(sk)
	return sk

static func _assign_ids(node: Dictionary, counter: Array) -> void:
	counter[0] += 1
	node["id"] = counter[0]
	for key in ["child", "first", "then", "else", "a", "b"]:
		if node.has(key) and node[key] is Dictionary and not node[key].is_empty():
			_assign_ids(node[key], counter)

# 宣告时必须作出的选择： [{key, kind:'target'|'remove'|'branch', node_id, spec, label}]
static func choice_slots(sk: Dictionary) -> Array:
	var out: Array = []
	for n in sk.nodes:
		_collect_choices(n, out, false)
	return out

static func _collect_choices(node: Dictionary, out: Array, in_watch: bool) -> void:
	match node.kind:
		"dmg", "heal", "mit", "status", "swap", "remove":
			if needs_choice(node.target):
				out.append({"key": "t%d" % node.id, "kind": "target", "node_id": node.id, "spec": node.target, "label": target_text(node.target)})
			if node.kind == "status" and node.has("link") and needs_choice(node.link):
				out.append({"key": "l%d" % node.id, "kind": "target", "node_id": node.id, "spec": node.link, "label": "牵连对象：" + target_text(node.link)})
			if node.kind == "remove" and node.what == "限时效果":
				out.append({"key": "r%d" % node.id, "kind": "remove", "node_id": node.id, "label": "要移除的限时效果"})
		"split":
			for i in node.branches.size():
				var b: Dictionary = node.branches[i]
				if needs_choice(b.target):
					out.append({"key": "s%d_%d" % [node.id, i], "kind": "target", "node_id": node.id, "spec": b.target, "label": target_text(b.target)})
		"watch":
			if not (node.event in NO_OBSERVE) and needs_choice(node.observe):
				out.append({"key": "o%d" % node.id, "kind": "target", "node_id": node.id, "spec": node.observe, "label": "监听对象：" + target_text(node.observe)})
			_collect_choices(node.child, out, true)
			if node.child.kind == "redirect" and needs_choice(node.child.target):
				out.append({"key": "t%d" % node.child.id, "kind": "target", "node_id": node.child.id, "spec": node.child.target, "label": "转移给：" + target_text(node.child.target)})
		"chain":
			_collect_choices(node.first, out, in_watch)
			_collect_choices(node.then, out, in_watch)
		"copy":
			_collect_choices(node.first, out, in_watch)
			if needs_choice(node.target):
				out.append({"key": "t%d" % node.id, "kind": "target", "node_id": node.id, "spec": node.target, "label": target_text(node.target)})
		"until":
			_collect_choices(node.child, out, in_watch)
		"if":
			_collect_choices(node.then, out, in_watch)
			if node.has("else"):
				_collect_choices(node["else"], out, in_watch)
		"choose":
			out.append({"key": "b%d" % node.id, "kind": "branch", "node_id": node.id, "label": "择一：哪一棵"})
			_collect_choices(node.a, out, in_watch)
			_collect_choices(node.b, out, in_watch)
	# 监听器子树里的 choose 目标在监听器安装时选定（宣告时），故同样收集。

# ---------------------------------------------------------------- 合法性
# 返回问题文字数组；空数组表示结构合法。
static func problems(sk: Dictionary) -> Array:
	var out: Array = []
	if sk.nodes.is_empty():
		out.append("技能是空的")
	for n in sk.nodes:
		_check(n, out, "")
	return out

static func _check(node: Dictionary, out: Array, ctx: String) -> void:
	# ctx: "" 顶层；否则为所在监听器的事件名
	var in_watch := ctx != ""
	match node.kind:
		"dmg", "heal":
			_check_target(node.target, out, in_watch)
			_check_value(node.value, out, ctx)
			if int(node.get("rep", 0)) > 0 and int(node.get("rep_gap", 0)) < 0:
				out.append("重复间隔不合法")
		"mit", "status", "remove", "swap":
			_check_target(node.target, out, in_watch)
			if node.has("link"):
				_check_target(node.link, out, in_watch)
			if node.kind == "status" and not (node.status in STATUSES):
				out.append("未知状态：" + str(node.status))
			if node.kind in ["mit", "status"] and (int(node.dur) < 0 or int(node.dur) > 20):
				out.append("持续秒数须在1到20")
			if node.kind == "swap" and node.target.side != "ally":
				out.append("换位只能与己方随从")
		"watch":
			if node.has("dur") and node.life == "dur" and (int(node.dur) < 1 or int(node.dur) > 20):
				out.append("持续秒数须在1到20")
			if not (node.event in NO_OBSERVE):
				_check_target(node.observe, out, in_watch)
			var ck: String = node.child.kind
			if ck == "redirect" or ck == "convert":
				if node.event != "pending_dmg":
					out.append("转移/转为只能用于“即将受到伤害”")
				if int(node.child.get("value", {"n": 0}).n) < 1:
					out.append("转移/转为要填入每个被保护者的上限（至少1）")
				if ck == "redirect":
					_check_target(node.child.target, out, true)
			else:
				_check(node.child, out, node.event)
			if ck == "watch":
				pass # 允许监听器里再装监听器（嵌套合法，层数不设上限）
		"redirect", "convert":
			out.append("转移/转为必须直接放在“当 即将受到伤害”之下")
		"time":
			if node.op == "interrupt":
				if int(node.value.n) < 1:
					out.append("打断要填入力度（至少1）")
			elif int(node.value.n) < 1 or int(node.value.n) > 19:
				out.append("时间改动须填1到19秒")
		"split":
			var sum := 0
			for b in node.branches:
				sum += int(b.part)
				_check_target(b.target, out, in_watch)
			if sum != int(node.total):
				out.append("分流各段之和必须等于总填数")
			if node.branches.size() != 2:
				out.append("分流必须有两条分支")
		"chain":
			_check(node.first, out, ctx)
			_check(node.then, out, ctx)
			if not (node.first.kind in ["dmg", "heal"]):
				out.append("接续的前一效果必须是伤害或治疗")
			if node.then.has("target") and not is_single_pick(node.then.target):
				out.append("接续的后一效果只能作用于单个随从（否则前一效果每个结果都会各自触发一遍，数值会被成倍放大）")
		"copy":
			_check(node.first, out, ctx)
			_check_target(node.target, out, in_watch)
			if not (node.first.kind in ["dmg", "heal"]):
				out.append("复制只能复制伤害或治疗")
			if not is_single_pick(node.target):
				out.append("复制的目标只能是单个随从（每个结果各复制一份，给多个目标会成平方放大）")
		"until":
			cond_check(node.cond, out, ctx)
			_check(node.child, out, ctx)
			if not (node.child.kind in ["dmg", "heal", "mit", "status", "split", "chain", "copy"]):
				out.append("“直到”只能重复伤害、治疗、减伤、状态、分流、接续或复制")
		"if":
			cond_check(node.cond, out, ctx)
			_check(node.then, out, ctx)
			if node.has("else"):
				_check(node["else"], out, ctx)
		"choose":
			_check(node.a, out, ctx)
			_check(node.b, out, ctx)

static func _check_target(t: Dictionary, out: Array, in_watch: bool) -> void:
	if (t.pick == "source" or t.pick == "recipient" or t.pick == "adjacent") and not in_watch:
		out.append("“%s”只能在监听器的效果里使用" % target_text(t))

static func _check_value(v: Dictionary, out: Array, ctx: String) -> void:
	match v.k:
		"ref":
			if v.ref in ["event_damage", "actual", "raw"] and not (ctx in ["damaged", "dealt", "lost", "pending_dmg"]):
				out.append("“%s”只能在伤害类监听器里使用" % REF_TEXT[v.ref])
			if v.ref == "event_heal" and ctx != "healed":
				out.append("“该次治疗”只能在“恢复生命”监听器里使用")
			if v.ref == "overflow" and ctx != "healed":
				out.append("“溢出”只能在“恢复生命”监听器里使用")
			if v.ref == "times" and ctx == "":
				out.append("“次数”只能在监听器里使用")
			if v.has("of"):
				_check_target(v.of, out, ctx != "")
		"op":
			_check_value(v.a, out, ctx)
			_check_value(v.b, out, ctx)

# 对照词库存量：返回缺的词 {词名: 缺几张}
static func missing(words: Array, pool: Dictionary) -> Dictionary:
	var need := {}
	for w in words:
		need[w] = int(need.get(w, 0)) + 1
	var miss := {}
	for w in need:
		var have := int(pool.get(w, 0))
		if have < need[w]:
			miss[w] = need[w] - have
	return miss

static func count_words(words: Array) -> Dictionary:
	var c := {}
	for w in words:
		c[w] = int(c.get(w, 0)) + 1
	return c

# ---------------------------------------------------------------- 人话
static func verb_text(kind: String, alt: int, target: String, value: String, is_num: bool = true) -> String:
	if kind == "dmg":
		if alt == 0:
			return ("对%s造成 %s 点伤害" % [target, value]) if is_num else ("对%s造成与 %s 相等的伤害" % [target, value])
		return "使%s的当前生命减少 %s" % [target, value]
	if alt == 0:
		return ("使%s恢复 %s 点生命" % [target, value]) if is_num else ("使%s恢复与 %s 相等的生命" % [target, value])
	return "使%s的当前生命增加 %s" % [target, value]

static func node_text(node: Dictionary) -> String:
	var t := _node_text_core(node)
	if node.get("sync", false):
		t += "（各次同时落下）"
	return t

static func _event_phrase(node: Dictionary) -> String:
	var who: String = ""
	if not (node.event in NO_OBSERVE):
		var ob: Dictionary = node.observe
		if ob.pick in ["all", "each"]:
			who = "任何一个" + SIDE_TEXT.get(ob.get("side", ""), "") + "随从"
		else:
			who = target_text(ob)
	return who + EVENT_TEXT[node.event]

static func _node_text_core(node: Dictionary) -> String:
	match node.kind:
		"dmg", "heal":
			var t := verb_text(node.kind, int(node.get("alt", 0)), target_text(node.target), _num_text(node, node.value), node.value.k == "num")
			if int(node.get("rep", 0)) > 0:
				var gap := int(node.get("rep_gap", 0)) if int(node.get("rep_gap", 0)) > 0 else 2
				t += "；之后每隔 %d 秒再来一次，共再来 %d 次" % [gap, int(node.rep)]
			return _after_text(node) + t
		"mit":
			var s: String = "使%s受到的伤害%s" % [target_text(node.target), ("每次减少 %d 点" % (int(node.value.n) / 2)) if node.mode == "fixed" else ("降低 %d%%" % pct_of(int(node.value.n)))]
			return s + _dur_text(int(node.dur))
		"status":
			var s2: String = "给%s施加【%s】" % [target_text(node.target), node.status]
			if node.status == "护盾":
				s2 += "，可吸收 %d 点伤害" % effective_num(node)
			elif node.status == "沉默":
				s2 += "，使其无法发动费用不超过 %d 的技能" % silence_limit(effective_num(node))
			elif STATUS_DESC.has(node.status) and node.status != "牵连":
				s2 += "（%s）" % STATUS_DESC[node.status]
			if node.status == "牵连" and node.has("link"):
				s2 = "给%s施加【牵连】：与%s平分受到的伤害" % [target_text(node.target), target_text(node.link)]
			return s2 + _dur_text(int(node.dur))
		"remove":
			return "移除%s身上的%s" % [target_text(node.target), node.what]
		"watch":
			if node.event == "round_end":
				return "本轮结束时，" + node_text(node.child)
			var when := "本轮内，" if node.life != "dur" else "接下来 %d 秒内，" % int(node.dur)
			var f := "每当" if node.freq == "every" else "第一次"
			return "%s%s%s时，%s" % [when, f, _event_phrase(node), node_text(node.child)]
		"redirect":
			return "改由%s承受这次伤害（每个被保护的随从最多转移 %d 点）" % [target_text(node.target), effective_num(node)]
		"convert":
			return "把这次伤害变成等量的治疗（每个被保护的随从最多转换 %d 点）" % effective_num(node)
		"time":
			var who: String = SIDE_TEXT[node.side] + "接下来第一个起效的技能"
			match node.op:
				"delay": return "把%s推迟 %d 秒" % [who, effective_num(node)]
				"advance": return "把%s提前 %d 秒" % [who, effective_num(node)]
				_: return "打断%s（只对费用不超过 %d 的技能有效）" % [who, silence_limit(effective_num(node))]
		"swap":
			return "自身与%s交换位置" % target_text(node.target)
		"split":
			var parts: Array = []
			for b in node.branches:
				parts.append("%s 分到 %d" % [target_text(b.target), int(b.part)])
			return "把总共 %d 点%s分配出去：%s" % [int(node.total), "伤害" if node.verb == "dmg" else "治疗", "；".join(parts)]
		"chain":
			return node_text(node.first) + "；然后" + node_text(node.then)
		"copy":
			return node_text(node.first) + "；同样的数值也对" + target_text(node.target) + "生效"
		"until":
			var gap2 := int(node.get("gap", 0)) if int(node.get("gap", 0)) > 0 else 2
			return "%s；每隔 %d 秒再来一次，直到 %s 为止（最多再来 %d 次）" % [node_text(node.child), gap2, cond_text(node.cond), UNTIL_MAX]
		"if":
			var s3 := "如果%s，就%s" % [cond_text(node.cond), node_text(node.then)]
			if node.has("else"):
				s3 += "；否则%s" % node_text(node["else"])
			return s3
		"choose":
			return "二选一，宣告时决定：%s，或者%s" % [node_text(node.a), node_text(node.b)]
	return "?"

static func effective_num(node: Dictionary) -> int:
	var v := int(node.value.n)
	for i in int(node.get("dbl", 0)):
		v *= 2
	for i in int(node.get("half", 0)):
		v = (v + 1) / 2
	return v

# 打断/沉默的力度换算：力度P能压制操作费不超过 1.25×P 的技能
static func silence_limit(p: int) -> int:
	return int(p * 5 / 4)

static func pct_of(points: int) -> int:
	return int(round(100.0 * points / (points + 20.0)))

static func describe(sk: Dictionary) -> String:
	var parts: Array = []
	for n in sk.nodes:
		parts.append(node_text(n))
	return "；另外，".join(parts)

# 技能的粗分类，用于界面图标与AI：atk / def / heal / ctl / buff
static func kind_tag(sk: Dictionary) -> String:
	return _node_tag(sk.nodes[0]) if not sk.nodes.is_empty() else "atk"


static func _node_tag(n: Dictionary) -> String:
	match n.kind:
		"dmg", "split", "copy", "chain", "until": return "atk"
		"heal": return "heal"
		"mit": return "def"
		"watch": return "trap"
		"time", "remove", "swap": return "ctl"
		"status": return "buff"
	return "atk"
