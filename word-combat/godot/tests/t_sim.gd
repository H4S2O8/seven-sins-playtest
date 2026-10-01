extends SceneTree
const Match = preload("res://scripts/game/match.gd")
const Lex = preload("res://scripts/core/lexicon.gd")

func _init() -> void:
	Lex.load_all()
	var n := 6
	var t0 := Time.get_ticks_msec()
	var wins := [0, 0, 0]
	for g in n:
		var m := Match.new()
		m.fast_ai = true
		m.start(false, 100 + g, false)
		var t1 := Time.get_ticks_msec()
		m.run_to_end()
		var w: int = m.winner
		wins[w if w >= 0 else 2] += 1
		print("局%d  性格 %s vs %s  胜者=%d  轮数=%d  分数 %d:%d  用时%dms" % [g, m.personas[0], m.personas[1], w, m.st.round, m.st.sides[0].score, m.st.sides[1].score, Time.get_ticks_msec() - t1])
	print("合计 先=", wins, " 总用时 ", Time.get_ticks_msec() - t0, "ms")
	quit(0)
