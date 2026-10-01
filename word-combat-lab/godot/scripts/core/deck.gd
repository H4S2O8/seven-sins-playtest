extends RefCounted
# 牌组：五张随从卡。每张卡：名字、生命、至多一个关键词、至多两个技能。
# 构筑预算100点 = 五张卡的生命 + 所有技能的填入数字（含持续秒数）。

const G = preload("res://scripts/core/grammar.gd")
const Lex = preload("res://scripts/core/lexicon.gd")

const BUDGET := 100
const MAX_SKILLS := 1      # 一个随从一招（招里可以用“并”连多个效果）
const NAMES := ["剑灵", "盾卫", "咒师", "弓手", "魂使"]
const GLYPHS := ["剑", "盾", "咒", "弓", "魂"]
const KEYWORDS := ["首挡", "不屈", "回击", "回春", "同调", "免疫狂振", "免疫牵连", "免疫升华"]

static func new_deck() -> Dictionary:
	var units: Array = []
	for i in 5:
		units.append({"name": NAMES[i], "glyph": GLYPHS[i], "max_hp": 12, "kw": "", "skills": []})
	return {"units": units}

static func clone(deck: Dictionary) -> Dictionary:
	return deck.duplicate(true)

static func used_words(deck: Dictionary) -> Array:
	var out: Array = []
	for u in deck.units:
		if u.kw != "":
			out.append(u.kw)
		for sk in u.skills:
			out.append_array(sk.words)
	return out

static func budget_used(deck: Dictionary) -> Dictionary:
	var hp := 0
	var nums := 0
	for u in deck.units:
		hp += int(u.max_hp)
		for sk in u.skills:
			nums += int(sk.budget)
	return {"hp": hp, "nums": nums, "total": hp + nums}

static func validate(deck: Dictionary, pool: Dictionary) -> Dictionary:
	var errors: Array = []
	var b := budget_used(deck)
	if b.total > BUDGET:
		errors.append("点数超出：已用%d / %d" % [b.total, BUDGET])
	for u in deck.units:
		if int(u.max_hp) < 1:
			errors.append("%s 的生命至少为1" % u.name)
		if u.skills.size() > MAX_SKILLS:
			errors.append("%s 最多装%d个技能" % [u.name, MAX_SKILLS])
		for sk in u.skills:
			var pr := G.problems(sk)
			for p in pr:
				errors.append("%s【%s】：%s" % [u.name, sk.name, p])
	var miss := G.missing(used_words(deck), pool)
	for w in miss:
		errors.append("缺词：%s ×%d" % [w, miss[w]])
	return {"ok": errors.is_empty(), "errors": errors, "budget": b, "missing": miss}

# 每个词的已用数量
static func used_counts(deck: Dictionary) -> Dictionary:
	return G.count_words(used_words(deck))

# 与旧牌组相比，变化了几张卡（用于“调整”次数）
static func changed_units(old: Dictionary, new: Dictionary) -> Array:
	var out: Array = []
	for i in new.units.size():
		if _sig(old.units[i]) != _sig(new.units[i]):
			out.append(i)
	return out

static func _sig(u: Dictionary) -> String:
	var parts: Array = [str(u.max_hp), u.kw]
	for sk in u.skills:
		parts.append(JSON.stringify(sk.nodes))
	return "|".join(parts)

# 给技能指派名字，便于区分（同名技能加序号）
static func rename_skills(deck: Dictionary) -> void:
	var seen := {}
	for u in deck.units:
		for sk in u.skills:
			var base: String = sk.get("base_name", sk.name)
			sk["base_name"] = base
			if sk.get("custom_name", false):
				sk["name"] = base # 玩家自己起的名字，不加序号
				continue
			seen[base] = int(seen.get(base, 0)) + 1
			sk["name"] = base if seen[base] == 1 else "%s·%d" % [base, seen[base]]
