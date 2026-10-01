extends RefCounted
# 词库：从 res://data/words.tsv 读取。词实例按“词名”计数（同名词卡可互换）。

static var words: Dictionary = {}   # 词名 -> {id,name,cat,rarity,price,impl,weight,desc}
static var order: Array = []        # 词名，按编号
static var _loaded := false

const CAT_COLORS := {
	"动作": Color("c0504d"), "对象": Color("4a7fb5"), "范围": Color("8e6bb5"), "时间": Color("3f9a8c"),
	"触发": Color("d28a2e"), "结构": Color("7a8a99"), "引用": Color("5c9a4b"), "状态": Color("b5567f"),
	"关键词": Color("c7a13a"),
}
const RARITY_COLORS := {"基础": Color("9aa3ad"), "进阶": Color("5aa0e0"), "奇术": Color("e0a93a")}

static func load_all() -> void:
	if _loaded:
		return
	var f := FileAccess.open("res://data/words.tsv", FileAccess.READ)
	if f == null:
		push_error("无法读取词库")
		return
	f.get_line() # 表头
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var p := line.split("\t")
		if p.size() < 8:
			continue
		var w := {"id": p[0], "name": p[1], "cat": p[2], "rarity": p[3], "price": int(p[4]),
			"impl": int(p[5]) == 1, "weight": int(p[6]), "desc": p[7]}
		words[w.name] = w
		order.append(w.name)
	_loaded = true

static func get_word(name: String) -> Dictionary:
	load_all()
	return words.get(name, {})

static func price(name: String) -> int:
	load_all()
	return int(words[name].price) if words.has(name) else 0

static func cat_color(name: String) -> Color:
	load_all()
	if not words.has(name):
		return Color.GRAY
	return CAT_COLORS.get(words[name].cat, Color.GRAY)

static func rarity_color(name: String) -> Color:
	load_all()
	if not words.has(name):
		return Color.GRAY
	return RARITY_COLORS.get(words[name].rarity, Color.GRAY)

static func implemented() -> Array:
	load_all()
	var out: Array = []
	for n in order:
		if words[n].impl:
			out.append(n)
	return out

# 词袋：每袋25词，基础40% 进阶45% 奇术15%，同类内按权重；至少10个基础词（宁可不平衡，也不要平庸）。
static func draw_bag(rng: RandomNumberGenerator, size: int = 25) -> Array:
	load_all()
	var pools := {"基础": [], "进阶": [], "奇术": []}
	for n in order:
		var w: Dictionary = words[n]
		if not w.impl:
			continue
		for i in int(w.weight):
			pools[w.rarity].append(n)
	var bag: Array = []
	var guard := 0
	while true:
		bag.clear()
		for i in size:
			var r := rng.randf()
			var key := "基础" if r < 0.40 else ("进阶" if r < 0.85 else "奇术")
			var pool: Array = pools[key]
			bag.append(pool[rng.randi() % pool.size()])
		var basics := 0
		for n in bag:
			if words[n].rarity == "基础":
				basics += 1
		guard += 1
		if basics >= size * 2 / 5 or guard > 50:
			break
	bag.sort_custom(func(a, b): return words[a].id < words[b].id)
	return bag

# 开局12词：一套完整基础攻击句 + 一套应对句（自身治疗/自身减伤/受伤时转移给来源），其余基础词随机。
static func opening_words(rng: RandomNumberGenerator) -> Array:
	load_all()
	var attacks := [
		["造成", "伤害", "选择", "目标", "一个", "敌方", "随从"],
		["造成", "伤害", "最前", "敌方", "随从"],
		["造成", "伤害", "最低生命", "敌方", "随从"],
		["造成", "伤害", "随机", "敌方", "随从"],
	]
	var responses := [
		["恢复", "生命", "自身"],
		["减伤", "自身"],
		["当", "即将受到伤害", "自身", "转移", "来源"],
	]
	var out: Array = []
	out.append_array(attacks[rng.randi() % attacks.size()])
	out.append_array(responses[rng.randi() % responses.size()])
	var basics: Array = []
	for n in order:
		var w: Dictionary = words[n]
		if w.impl and w.rarity == "基础":
			for i in int(w.weight):
				basics.append(n)
	while out.size() < 18:
		out.append(basics[rng.randi() % basics.size()])
	return out
