extends RefCounted
# 用户设置（难度、静音），存在 user://settings.cfg。

const PATH := "user://settings.cfg"
static var level := 1      # 0 简单  1 普通  2 困难
static var muted := false
static var coach := true        # 辅助轮（教练提示与自动组合）
static var tutorial_done := false
static var pet := true            # 桌宠“小词”
static var _loaded := false

const LEVEL_NAMES := ["简单", "普通", "困难"]
const LEVEL_DESC := [
	"电脑经常随手出招，适合熟悉规则",
	"电脑大多数时候按模拟选最优，偶尔失误",
	"电脑每次都做完整搜索，不留余地",
]

static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		level = clampi(int(cf.get_value("game", "level", 1)), 0, 2)
		muted = bool(cf.get_value("audio", "muted", false))
		coach = bool(cf.get_value("game", "coach", true))
		tutorial_done = bool(cf.get_value("game", "tutorial_done", false))
		pet = bool(cf.get_value("game", "pet", true))

static func save_all() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "level", level)
	cf.set_value("audio", "muted", muted)
	cf.set_value("game", "coach", coach)
	cf.set_value("game", "tutorial_done", tutorial_done)
	cf.set_value("game", "pet", pet)
	cf.save(PATH)
