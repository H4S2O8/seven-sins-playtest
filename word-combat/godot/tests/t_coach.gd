extends SceneTree
const Coach = preload("res://scripts/core/coach.gd")
const Ai = preload("res://scripts/ai/ai.gd")
const D = preload("res://scripts/core/deck.gd")
const Lex = preload("res://scripts/core/lexicon.gd")
func _init() -> void:
	Lex.load_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var pool := {}
	for w in Lex.opening_words(rng): pool[w] = int(pool.get(w, 0)) + 1
	var deck := D.new_deck()
	var bags := [Lex.draw_bag(rng), Lex.draw_bag(rng)]
	var info := Coach.analyze_draft(pool, deck, bags)
	print("推荐袋：", info.pick, "  理由：", info.reason)
	for w in info.watch: print("  留意：", w)
	for l in Coach.describe_build(pool, deck): print("  构筑：", l)
	# 自动组合：五张都应当有技能或至少合法
	var bad := 0
	for g in 40:
		var r2 := RandomNumberGenerator.new(); r2.seed = 100 + g
		var p2 := {}
		for k in 3:
			for w in (Lex.opening_words(r2) if k == 0 else Lex.draw_bag(r2)): p2[w] = int(p2.get(w, 0)) + 1
		for persona in Ai.PERSONA_ORDER:
			var d := Ai.build_deck(p2, persona, r2)
			var v := D.validate(d, p2)
			if not v.ok: bad += 1; print("非法：", persona, v.errors)
	print("自动组合非法次数：", bad)
	quit(bad)
