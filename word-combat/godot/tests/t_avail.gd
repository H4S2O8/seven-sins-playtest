extends SceneTree
# 词袋可得率：有针对性地抽词（每轮在两袋里选补缺更多的一袋；后手轮随机得一袋），
# 统计各进攻组合/反制族在第 r 轮结束时“词已凑齐”的概率。
# 用法： --script res://tests/t_avail.gd -- [局数] [输出json]
const G = preload("res://scripts/core/grammar.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
const Defs = preload("res://tests/audit_defs.gd")
const R = preload("res://scripts/core/recipes.gd")

func missing_count(words: Array, pool: Dictionary) -> int:
	return G.missing(words, pool).size() if false else _miss(words, pool)

func _miss(words: Array, pool: Dictionary) -> int:
	var need := {}
	for w in words:
		need[w] = int(need.get(w, 0)) + 1
	var n := 0
	for w in need:
		n += maxi(0, int(need[w]) - int(pool.get(w, 0)))
	return n

func gain(words: Array, pool: Dictionary, bag: Array) -> int:
	# 这袋词能补上多少缺口
	var before := _miss(words, pool)
	var p2 := pool.duplicate()
	for w in bag:
		p2[w] = int(p2.get(w, 0)) + 1
	return before - _miss(words, p2)

func simulate(words: Array, games: int, rounds: int, rng: RandomNumberGenerator) -> Array:
	var ready := []
	for r in rounds:
		ready.append(0)
	for g in games:
		var pool := {}
		for w in Lex.opening_words(rng):
			pool[w] = int(pool.get(w, 0)) + 1
		var done_at := -1
		for r in rounds:
			var a := Lex.draw_bag(rng)
			var b := Lex.draw_bag(rng)
			var chosen: Array
			if r % 2 == 0: # 先手轮：自己选
				chosen = a if gain(words, pool, a) >= gain(words, pool, b) else b
			else: # 后手轮：对手先选，这里按随机
				chosen = a if rng.randf() < 0.5 else b
			for w in chosen:
				pool[w] = int(pool.get(w, 0)) + 1
			if done_at == -1 and _miss(words, pool) == 0:
				done_at = r
		if done_at != -1:
			for r in range(done_at, rounds):
				ready[r] += 1
	var out: Array = []
	for r in rounds:
		out.append(float(ready[r]) / float(games))
	return out

func _init() -> void:
	Lex.load_all()
	var args := OS.get_cmdline_user_args()
	var games := 1500
	if args.size() > 0:
		games = int(args[0])
	var out_path := "res://avail.json"
	if args.size() > 1:
		out_path = args[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261001
	var rounds := 8
	var rows: Array = []
	for spec in Defs.attack_specs():
		var sk := R.build(spec.tid, spec.params)
		rows.append({"kind": "攻", "name": spec.name, "words": sk.words, "ready": simulate(sk.words, games, rounds, rng)})
	for k in Defs.custom_kinds():
		var sk2 := Defs.custom_attack(k, 10)
		rows.append({"kind": "攻", "name": k, "words": sk2.words, "ready": simulate(sk2.words, games, rounds, rng)})
	for spec in Defs.counter_specs():
		var sk3 := Defs.build_counter(spec, spec.powers[0])
		rows.append({"kind": "守", "name": spec.name, "words": sk3.words, "ready": simulate(sk3.words, games, rounds, rng)})
	for r in rows:
		var line := ""
		for i in [0, 1, 2, 3, 5, 7]:
			line += "%3.0f%% " % (r.ready[i] * 100.0)
		print("%s %-26s 词数%2d  第1/2/3/4/6/8轮：%s" % [r.kind, r.name, r.words.size(), line])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"games": games, "rounds": rounds, "rows": rows}, "  "))
	f.close()
	quit(0)
