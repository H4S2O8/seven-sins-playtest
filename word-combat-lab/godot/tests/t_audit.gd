extends SceneTree
# 强组合 × 反制 审计（真实引擎，一轮对决）。
# 进攻方先手锁定，防守方看见后在全部合法行动（目标/起手时间）里选对自己最好的应对。
# 对每个反制族，逐档加大投入，找到“最小有效投入”，并换算成相对进攻操作费的比例（目标≥80%）。
# 用法： --script res://tests/t_audit.gd -- [ap] [out.json]
const G = preload("res://scripts/core/grammar.gd")
const R = preload("res://scripts/core/recipes.gd")
const Defs = preload("res://tests/audit_defs.gd")
const Lex = preload("res://scripts/core/lexicon.gd")

var AP := 60

# 把主数值调到“操作费不超过上限”的最大值
func fit_attack(a: Dictionary, cap: int) -> Dictionary:
	var best: Dictionary = {}
	for n in range(1, 61):
		var p: Dictionary = a.params.duplicate()
		p["n"] = n
		var sk := R.build(a.tid, p)
		if int(sk.cost) <= cap:
			best = sk
		else:
			break
	return best

func fit_custom(kind: String, cap: int) -> Dictionary:
	var best: Dictionary = {}
	for n in range(1, 61):
		var sk := Defs.custom_attack(kind, n)
		if int(sk.cost) > cap:
			break
		best = sk
	return best

func _init() -> void:
	Lex.load_all()
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		AP = int(args[0])
	var out_path := "res://audit_result.json"
	if args.size() > 1:
		out_path = args[1]
	var attacks: Array = []
	for t in Defs.attack_specs():
		var sk := fit_attack(t, AP)
		if not sk.is_empty():
			sk["name"] = t.name
			attacks.append(sk)
	for k in Defs.custom_kinds():
		var sk2 := fit_custom(k, AP)
		if not sk2.is_empty():
			attacks.append(sk2)
	var fams := Defs.counter_specs()
	var results: Array = []
	var t0 := Time.get_ticks_msec()
	for att in attacks:
		var base := Defs.best_attack(att, AP)
		if base.is_empty():
			continue
		var row := {"attack": att.name, "text": att.text, "cost": int(att.cost), "windup": int(att.windup), "base_v": base.v, "base_score": base.score, "counters": []}
		print("== 进攻 %s 操作费%d 起手%d  基线：得分%d" % [att.name, int(att.cost), int(att.windup), int(base.score)])
		for fam in fams:
			var found := false
			var tried: Array = []
			for p in fam.powers:
				var cs := Defs.build_counter(fam, p)
				if int(cs.cost) > AP:
					break
				var r := Defs.best_response(att, cs, base.uid, AP)
				if r.is_empty():
					continue
				var neutral: bool = (r.v <= 0.25 * base.v) if base.v > 0 else (r.v <= base.v)
				var reversed: bool = r.v < 0
				var trade: bool = r.att_score > 0 and r.def_score > 0
				tried.append({"power": p, "cost": int(cs.cost), "frac": float(cs.cost) / float(att.cost), "v": r.v, "att_score": r.att_score, "def_score": r.def_score, "neutral": neutral, "reversed": reversed, "trade": trade, "start": r.start})
				if neutral:
					found = true
					break
			var best_try: Dictionary = tried[tried.size() - 1] if not tried.is_empty() else {}
			row.counters.append({"name": fam.name, "neutralized": found, "tries": tried})
			var tag := "—"
			if found:
				tag = "✓ 最小有效：力度%s 费%d（占进攻%.0f%%）攻%d:守%d%s%s" % [str(best_try.power), best_try.cost, best_try.frac * 100.0, best_try.att_score, best_try.def_score, " 反打" if best_try.reversed else "", " 交换" if best_try.trade else ""]
			elif not tried.is_empty():
				tag = "✗ 最强档仍不足（剩余优势%.0f）" % best_try.v
			print("   %-30s %s" % [fam.name, tag])
		results.append(row)
	print("用时 %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"ap": AP, "results": results}, "  "))
	f.close()
	quit(0)
