extends SceneTree
# 打印一局电脑对电脑的完整过程，便于检查玩法是否有趣。用法：-- 种子
const Match = preload("res://scripts/game/match.gd")
const E = preload("res://scripts/core/engine.gd")
const Lex = preload("res://scripts/core/lexicon.gd")

func hpline(m, s: int) -> String:
	var out := ""
	for u in m.st.sides[s].units:
		out += ("×" if u.down_round != -1 else str(u.hp)) + "/" + str(u.max_hp) + " "
	return out

func _init() -> void:
	Lex.load_all()
	var seed_val := 1000
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_val = int(args[0])
	var m := Match.new()
	m.fast_ai = true
	m.start(false, seed_val, false)
	print("性格：", m.personas)
	var printed_deck := false
	var guard := 0
	while guard < 500:
		guard += 1
		if m.phase == "declare" and not printed_deck:
			printed_deck = true
			for s in 2:
				print("=== 牌组 ", s, "（", m.personas[s], "）")
				for u in m.st.sides[s].units:
					var names: Array = []
					for sid in u.skill_ids:
						var sk := E.skill_of(m.st, sid)
						names.append("%s[%d]%s" % [sk.name, int(sk.cost), sk.text])
					print("  ", u.name, " hp", u.max_hp, " ", u.kw, " ", names)
		if not m.step_auto():
			break
		if m.phase == "resolved" or m.phase == "over":
			print("--- 第%d轮 AP %d/%d" % [m.st.round, int(m.st.sides[0].ap), int(m.st.sides[1].ap)])
			for s in 2:
				var a: Dictionary = m.last_declared[s]
				if a.is_empty():
					print("  ", s, " 不行动")
				else:
					var sk := E.skill_of(m.st, a.sid)
					print("  ", s, " ", sk.name, " @", a.start, "s 选择=", a.choices)
			var kinds := {}
			for e in m.last_events:
				if e.type in ["dmg", "heal", "redirect", "convert", "interrupt", "delay", "fizzle", "down", "block", "trigger", "status", "mit", "shield", "keyword"]:
					kinds[e.type] = int(kinds.get(e.type, 0)) + 1
			print("    事件 ", kinds)
			print("    你方 ", hpline(m, 0), " 分", m.st.sides[0].score)
			print("    对方 ", hpline(m, 1), " 分", m.st.sides[1].score)
			if m.phase == "over":
				break
	print("胜者 ", m.winner)
	quit(0)
