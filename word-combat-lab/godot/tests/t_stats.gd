extends SceneTree
# 批量电脑对电脑：统计胜率、局长、各类事件频率。用法：--script res://tests/t_stats.gd -- N
const Match = preload("res://scripts/game/match.gd")
const Lex = preload("res://scripts/core/lexicon.gd")

func _init() -> void:
	Lex.load_all()
	var n := 60
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	var t0 := Time.get_ticks_msec()
	var wins := {"side0": 0, "side1": 0, "draw": 0}
	var rounds_sum := 0
	var ended_by := {"wipe": 0, "score": 0, "limit": 0}
	var ev_count := {}
	var per_persona := {}
	var acted := 0
	var passed := 0
	var words_total := 0
	var think_max := 0
	for g in n:
		var m := Match.new()
		m.fast_ai = (OS.get_cmdline_user_args().size() < 2)
		m.start(false, 1000 + g, false)
		var guard := 0
		while guard < 500:
			guard += 1
			if not m.step_auto():
				break
			if m.phase == "resolved" or m.phase == "over":
				for e in m.last_events:
					ev_count[e.type] = int(ev_count.get(e.type, 0)) + 1
				for s in 2:
					if m.last_declared[s].is_empty():
						passed += 1
					else:
						acted += 1
				if m.phase == "over":
					break
		think_max = maxi(think_max, m.max_think_ms)
		var w: int = m.winner
		if w == 0:
			wins.side0 += 1
		elif w == 1:
			wins.side1 += 1
		else:
			wins.draw += 1
		rounds_sum += int(m.st.round)
		var e0 := true
		for u in m.st.sides[0].units:
			if u.down_round == -1:
				e0 = false
		var e1 := true
		for u in m.st.sides[1].units:
			if u.down_round == -1:
				e1 = false
		if e0 or e1:
			ended_by.wipe += 1
		elif int(m.st.sides[0].score) >= int(m.st.rules.win_score) or int(m.st.sides[1].score) >= int(m.st.rules.win_score):
			ended_by.score += 1
		else:
			ended_by.limit += 1
		var key: String = "%s vs %s" % [m.personas[0], m.personas[1]]
		if not per_persona.has(key):
			per_persona[key] = [0, 0, 0]
		per_persona[key][0 if w == 0 else (1 if w == 1 else 2)] += 1
		for s in 2:
			for p in m.pools[s]:
				words_total += int(m.pools[s][p])
	print("电脑单次思考最长 %d ms" % think_max)
	print("局数 %d  用时 %.1fs  平均轮数 %.1f" % [n, (Time.get_ticks_msec() - t0) / 1000.0, float(rounds_sum) / n])
	print("胜者：0号位 %d · 1号位 %d · 平局 %d" % [wins.side0, wins.side1, wins.draw])
	print("结束方式：", ended_by)
	print("行动 / 不行动：%d / %d" % [acted, passed])
	var keys: Array = ev_count.keys()
	keys.sort()
	var line := ""
	for k in keys:
		line += "%s=%d  " % [k, ev_count[k]]
	print("事件：", line)
	var pk: Array = per_persona.keys()
	pk.sort()
	for k in pk:
		print("  ", k, " → ", per_persona[k])
	quit(0)
