extends RefCounted
# 外观解析：随从卡（技能、关键词）→ 该挂哪些配件。数据来自 data/appearance.json。
# 解析结果只是“清单”，具体模型由 minion_builder.gd 决定（优先用 assets/ 里的 glTF，没有就用代码占位件）。

static var cfg: Dictionary = {}

static func load_cfg() -> Dictionary:
	if not cfg.is_empty():
		return cfg
	var f := FileAccess.open("res://data/appearance.json", FileAccess.READ)
	if f == null:
		push_error("缺少 data/appearance.json")
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		cfg = parsed
	return cfg

static func _nodes_kinds(node: Dictionary, out: Dictionary) -> void:
	out[node.get("kind", "")] = true
	for key in ["child", "first", "then", "else", "a", "b"]:
		if node.has(key) and node[key] is Dictionary and not node[key].is_empty():
			_nodes_kinds(node[key], out)

# 规则的条件是否成立。unit：随从（需要 kw）；skills：该随从的技能字典数组
static func _matches(when: Dictionary, unit: Dictionary, skills: Array, words: Dictionary, kinds: Dictionary, tags: Dictionary, templates: Dictionary) -> bool:
	for key in when:
		var v: String = str(when[key])
		match key:
			"kw":
				if str(unit.get("kw", "")) != v:
					return false
			"word":
				if not words.has(v):
					return false
			"node":
				if not kinds.has(v):
					return false
			"tag":
				if not tags.has(v):
					return false
			"template":
				if not templates.has(v):
					return false
			_:
				return false
	return true

# 返回 [{slot, asset, proc, color, priority}]：每个挂点只留优先级最高的一件
static func resolve(unit: Dictionary, skills: Array) -> Array:
	var c := load_cfg()
	var words := {}
	var kinds := {}
	var tags := {}
	var templates := {}
	for sk in skills:
		for w in sk.get("words", []):
			words[w] = true
		for n in sk.get("nodes", []):
			_nodes_kinds(n, kinds)
		tags[str(sk.get("kind_tag", ""))] = true
		if sk.has("template"):
			templates[str(sk.template)] = true
	var best := {}
	for r in c.get("rules", []):
		if not _matches(r.when, unit, skills, words, kinds, tags, templates):
			continue
		var slot: String = r.slot
		if not best.has(slot) or int(r.get("priority", 0)) > int(best[slot].get("priority", 0)):
			best[slot] = r
	var out: Array = []
	for slot in c.get("slots", []):
		if best.has(slot):
			out.append(best[slot])
	return out

static func body_for(glyph: String) -> Dictionary:
	var c := load_cfg()
	return c.get("bodies", {}).get(glyph, c.get("bodies", {}).get("剑", {}))

# 体型：生命越高越壮
static func scale_for(max_hp: int) -> float:
	var s: Dictionary = load_cfg().get("scale", {})
	return clampf(1.0 + (float(max_hp) - float(s.get("hp_ref", 14))) * float(s.get("per_hp", 0.012)), float(s.get("min", 0.82)), float(s.get("max", 1.3)))

static func status_fx(name: String) -> Dictionary:
	return load_cfg().get("status_fx", {}).get(name, {})
