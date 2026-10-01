extends SceneTree
const G = preload("res://scripts/core/grammar.gd")
const E = preload("res://scripts/core/engine.gd")
const Lex = preload("res://scripts/core/lexicon.gd")

var fails := 0
func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		print("  FAIL ", msg)
		fails += 1

func deck(skills0: Array, hps := [20,20,20,20,20], kws := ["","","","",""]) -> Dictionary:
	var units: Array = []
	for i in 5:
		units.append({"name": "卡%d" % i, "max_hp": hps[i], "kw": kws[i], "skills": skills0 if i == 0 else []})
	return {"units": units}

func _init() -> void:
	Lex.load_all()
	print("词数 ", Lex.words.size())
	# 1. 全体伤害 20
	var aoe := G.finalize(G.skill("全体", [G.dmg(G.T("all","enemy"), G.N(20))]))
	print("全体技能：", aoe.text, " 费用", aoe.cost, " 词", aoe.words)
	check(aoe.cost == 5 + 20 + G.words_price(aoe.words), "费用=启动+数字+词价")
	check(G.problems(aoe).is_empty(), "全体伤害合法")
	var st := E.make_state([deck([aoe]), deck([])], 0)
	E.begin_round(st)
	st.sides[0].ap = 60
	var res := E.run_round(st, [{"side":0,"sid": st.sides[0].units[0].skill_ids[0], "choices":{}, "start": 3}, {}])
	var hp: Array = []
	for u in st.sides[1].units: hp.append(u.hp)
	print("  敌方hp ", hp, " winner ", res.winner, " 分数 ", st.sides[0].score)
	check(hp == [0,0,0,0,0], "每人受20全灭")
	check(st.sides[0].score == 100, "击倒得分=生命上限之和")
	# 2. 改道监听：敌方攻击被转移回来源
	var atk := G.finalize(G.skill("全体", [G.dmg(G.T("all","enemy"), G.N(10))]))
	var redir := G.finalize(G.skill("改道", [G.watch("pending_dmg", G.T("all","ally"), G.redirect(G.T("source","ref")), {"freq":"every"})]))
	check(G.problems(redir).is_empty(), "改道合法: " + str(G.problems(redir)))
	print("  改道：", redir.text, " 费用", redir.cost, " 词", redir.words)
	st = E.make_state([deck([atk]), deck([redir])], 0)
	E.begin_round(st)
	st.sides[0].ap = 60
	st.sides[1].ap = 60
	res = E.run_round(st, [{"side":0,"sid": st.sides[0].units[0].skill_ids[0], "choices":{}, "start": 3}, {"side":1,"sid": st.sides[1].units[0].skill_ids[0], "choices":{}, "start": 1}])
	hp = []
	for u in st.sides[0].units: hp.append(u.hp)
	var hp1: Array = []
	for u in st.sides[1].units: hp1.append(u.hp)
	print("  攻方hp ", hp, " 守方hp ", hp1)
	check(hp1 == [20,20,20,20,20], "守方全队不受伤")
	check(hp[0] == 0 or hp[0] < 20, "伤害被改回攻方随从")
	# 3. 时间：打断
	var intr := G.finalize(G.skill("打断", [G.time_op("interrupt","enemy")]))
	check(G.problems(intr).is_empty(), "打断合法")
	st = E.make_state([deck([aoe]), deck([intr])], 0)
	E.begin_round(st)
	st.sides[0].ap = 60
	st.sides[1].ap = 60
	var ms := E.min_start(st, {"sid": st.sides[0].units[0].skill_ids[0], "choices":{}, "side":0})
	print("  全体技能最早起手 ", ms)
	res = E.run_round(st, [{"side":0,"sid": st.sides[0].units[0].skill_ids[0], "choices":{}, "start": 5}, {"side":1,"sid": st.sides[1].units[0].skill_ids[0], "choices":{}, "start": 1}])
	hp1 = []
	for u in st.sides[1].units: hp1.append(u.hp)
	check(hp1 == [20,20,20,20,20], "打断使全体攻击落空")
	print(fails, " 个失败")
	quit(fails)
