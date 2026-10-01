extends RefCounted
# 取名：按技能的效果随机一个像样的名字；按卡的定位随机一个随从名。纯装饰，不影响规则。

const ATK_SINGLE := ["斩", "刺", "裂空", "贯星", "破军", "追魂", "穿云", "断岳", "一闪"]
const ATK_AOE := ["崩", "天倾", "烈风暴", "星陨", "焚野", "雷海", "万刃", "碎界", "怒潮"]
const HEAL := ["回春", "愈光", "生息", "圣露", "续命", "暖阳"]
const DEF := ["磐壁", "不动", "玄甲", "结界", "金钟", "守心"]
const REDIR := ["借力", "逆流", "转嫁", "回旋", "偷天", "移山"]
const REFLECT := ["镜返", "奉还", "反噬", "还施", "回响"]
const CONVERT := ["点化", "逆转", "涅槃", "化敌为友"]
const TIME := ["截断", "止戈", "锁时", "迟滞"]
const SILENCE := ["缄默", "封口", "噤声"]
const STATUS := ["破绽", "狂乱", "标记", "咒印"]
const TRAP := ["伏兵", "陷阱", "暗哨", "天罗"]
const DRAIN := ["噬", "汲取", "夺命"]
const SWAP := ["挪移", "换影", "错位"]
const CLEANSE := ["破咒", "清场", "拆解"]
const PRE_DBL := ["重", "倍", "叠", "双"]
const PRE_REP := ["连环", "接踵", "绵延", "九重"]
const PRE_COPY := ["分身", "回声", "影"]
const PRE_SPLIT := ["分光", "双生"]

static func _pick(a: Array, rng: RandomNumberGenerator) -> String:
	return a[rng.randi() % a.size()]

static func _scan(node: Dictionary, f: Dictionary) -> void:
	var k: String = node.kind
	f[k] = true
	if node.has("target") and node.target is Dictionary and node.target.get("pick", "") in ["all", "each"]:
		f["aoe"] = true
	if int(node.get("dbl", 0)) > 0:
		f["dbl"] = true
	if int(node.get("rep", 0)) > 0:
		f["rep"] = true
	if k == "status":
		f["st_" + str(node.status)] = true
	if k == "time":
		f["time"] = true
	if k == "watch":
		f["watch"] = true
		if node.child.kind == "redirect":
			f["redirect"] = true
		elif node.child.kind == "convert":
			f["convert"] = true
		elif node.child.kind == "dmg" and node.child.target.get("pick", "") == "source":
			f["reflect"] = true
	for key in ["child", "first", "then", "else", "a", "b"]:
		if node.has(key) and node[key] is Dictionary and not node[key].is_empty():
			_scan(node[key], f)

static func skill_name(sk: Dictionary, rng: RandomNumberGenerator) -> String:
	var f := {}
	for n in sk.nodes:
		_scan(n, f)
	var noun: String
	if f.has("redirect"):
		noun = _pick(REDIR, rng)
	elif f.has("reflect"):
		noun = _pick(REFLECT, rng)
	elif f.has("convert"):
		noun = _pick(CONVERT, rng)
	elif f.has("watch"):
		noun = _pick(TRAP, rng)
	elif f.has("time"):
		noun = _pick(TIME, rng)
	elif f.has("st_沉默"):
		noun = _pick(SILENCE, rng)
	elif f.has("remove"):
		noun = _pick(CLEANSE, rng)
	elif f.has("swap"):
		noun = _pick(SWAP, rng)
	elif f.has("chain") and f.has("heal"):
		noun = _pick(DRAIN, rng)
	elif f.has("dmg") or f.has("split") or f.has("copy") or f.has("chain") or f.has("until"):
		noun = _pick(ATK_AOE if f.has("aoe") else ATK_SINGLE, rng)
	elif f.has("status"):
		noun = _pick(STATUS, rng)
	elif f.has("mit") or f.has("st_护盾"):
		noun = _pick(DEF, rng)
	elif f.has("heal"):
		noun = _pick(HEAL, rng)
	else:
		noun = _pick(ATK_SINGLE, rng)
	var pre := ""
	if f.has("rep") or f.has("until"):
		pre = _pick(PRE_REP, rng)
	elif f.has("dbl"):
		pre = _pick(PRE_DBL, rng)
	elif f.has("copy"):
		pre = _pick(PRE_COPY, rng)
	elif f.has("split"):
		pre = _pick(PRE_SPLIT, rng)
	var name := pre + noun
	if pre == "" and rng.randf() < 0.4:
		name = _pick(["赤", "苍", "玄", "烈", "霜", "雷", "幽", "曜"], rng) + noun
	if name.length() > 6:
		name = noun
	return name

const MINION_PRE := {
	"atk": ["烈", "锋", "赤", "雷"], "heal": ["磐", "青", "暖", "春"], "def": ["磐", "玄", "守", "岩"],
	"trap": ["逆", "镜", "暗", "幽"], "ctl": ["缄", "止", "霜", "寂"], "buff": ["咒", "曜", "狂", "烬"], "none": ["无", "初", "游", "野"],
}
const MINION_NOUN := {
	"剑": ["剑灵", "剑客", "剑魂", "剑侍"], "盾": ["盾卫", "盾将", "壁垒", "守卫"], "咒": ["咒师", "咒者", "术士", "巫"],
	"弓": ["弓手", "箭灵", "猎手", "射星"], "魂": ["魂使", "魂引", "幽魂", "魂灯"],
}

# 随从名：看这张卡主要装了什么类型的技能
static func minion_name(unit: Dictionary, rng: RandomNumberGenerator) -> String:
	var tag := "none"
	if not unit.skills.is_empty():
		tag = str(unit.skills[0].get("kind_tag", "atk"))
	var pre: Array = MINION_PRE.get(tag, MINION_PRE["none"])
	var nouns: Array = MINION_NOUN.get(unit.get("glyph", "剑"), ["勇士"])
	var name: String = _pick(pre, rng) + _pick(nouns, rng)
	if name.length() > 5:
		name = _pick(nouns, rng)
	return name
