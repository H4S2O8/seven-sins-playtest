extends SceneTree

const Rules = preload("res://core/rules/victory_rules.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_vc01()
	_test_vc02()
	_test_vc03()
	_test_vc04()
	_test_vc05()
	_test_vc06()
	_test_vc07()
	_test_vc08()
	_test_vc09()
	_test_vc10()
	_test_vc11()
	_test_vc12()
	_test_vc13()
	_test_vc14()
	_test_vc15()
	_test_vc16()
	_test_vc17()
	_test_vc18()
	_test_vc19()
	_test_vc20()
	_test_vc21()
	_test_vc22()
	_test_vc23()
	_test_vc24()
	_test_vc25()
	_test_vc26()
	_test_vc27()
	_test_vc28()
	_test_vc29()
	_test_vc30()
	_test_arithmetic_and_contract()
	if failures.is_empty():
		print("PASS: %d victory-rule assertions; VC01-VC30; exact arithmetic; real headless execution" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		printerr("FAIL: %d/%d assertions failed" % [failures.size(), checks])
		quit(1)


func _unit(slot: int, hp: int = 1000, max_hp: int = 1000, departed: bool = false,
		base_h: int = 100, base_a: int = 10, base_t: int = 20, base_r: int = 1,
		first_attack = null) -> Dictionary:
	return {"slot":slot, "base_H":base_h, "base_A":base_a, "base_T_ticks":base_t,
		"base_R":base_r, "hp_tenths":hp, "initial_max_hp_tenths":max_hp,
		"final_departed":departed, "first_natural_attack_tick":first_attack}


func _team(hps: Array = [1000, 1000, 1000], departed: Array = [false, false, false],
		maxes: Array = [1000, 1000, 1000], bases: Array = []) -> Array:
	var team: Array = []
	for i in range(3):
		var data: Dictionary = {"base_h":100 - i * 10, "base_a":[10,14,8][i], "base_t":[20,10,40][i], "base_r":[1,3,0][i]}
		if bases.size() == 3: data = bases[i]
		team.append(_unit(i + 1, hps[i], maxes[i], departed[i], data["base_h"], data["base_a"], data["base_t"], data["base_r"]))
	return team


func _teams(a: Array = [], b: Array = []) -> Dictionary:
	return {"A": a if not a.is_empty() else _team(), "B": b if not b.is_empty() else _team()}


func _swap(teams: Dictionary) -> Dictionary:
	return {"A": teams["B"].duplicate(true), "B": teams["A"].duplicate(true)}


func _memory(rule: String, teams: Dictionary = {}) -> Dictionary:
	var start: Dictionary = teams if not teams.is_empty() else _teams()
	return Rules.evaluate(rule, 0, start, {}).get("memory", {})


func _eval(rule: String, tick: int, teams: Dictionary, memory: Dictionary = {}, departures: Array = []) -> Dictionary:
	var mem := memory if not memory.is_empty() else _memory(rule)
	var result: Dictionary = {}
	for current_tick in range(int(mem.get("last_tick", -1)) + 1, tick + 1):
		result = Rules.evaluate(rule, current_tick, teams, mem, departures)
		if result.has("error") or result["terminal"]: return result
		mem = result["memory"]
	return result if not result.is_empty() else {"error":"test helper expected a later tick"}


func _expect(label: String, actual, expected) -> void:
	checks += 1
	if actual != expected: failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _expect_winner(label: String, rule: String, tick: int, teams: Dictionary, expected: String, mem: Dictionary = {}) -> Dictionary:
	var result := _eval(rule, tick, teams, mem)
	checks += 1
	if result.has("error"):
		failures.append("%s: unexpected input error: %s" % [label, result["error"]])
	elif result["winner"] != expected:
		failures.append("%s: expected winner %s, got %s (%s)" % [label, expected, str(result["winner"]), str(result["reason"])])
	return result


func _test_vc01() -> void:
	var both := _teams(_team([0,0,0], [true,true,true]), _team([0,0,0], [true,true,true]))
	_expect_winner("VC01 same-tick double elimination claims", "VC01", 4, both, "draw")
	_expect_winner("VC01 single full-elimination claim", "VC01", 4, _teams(_team(), _team([0,0,0], [true,true,true])), "A")
	_expect_winner("VC02 rule claim simultaneous with enemy full-elimination claim", "VC02", 1,
		_teams(_team([0,0,0], [true,true,true]), _team([0,0,1000], [true,true,false])), "draw")
	_expect_winner("VC01 left-right mirror", "VC01", 1, _swap(_teams(_team(), _team([0,0,0], [true,true,true]))), "B")


func _test_vc02() -> void:
	_expect_winner("VC02 first final departure", "VC02", 1, _teams(_team(), _team([1000,1000,0], [false,false,true])), "A")
	_expect("VC02 no departure stays live", _eval("VC02", 1, _teams())["winner"], null)


func _test_vc03() -> void:
	var teams := _teams(_team([0,0,1000], [true,true,false]), _team([0,0,1000], [true,true,false]))
	_expect_winner("VC03 simultaneous two-person claims", "VC03", 20, teams, "draw")
	_expect("VC03 revived unit is not a final departure", _eval("VC03", 1,
		_teams(_team(), _team([0,1000,1000], [true,false,false]))) ["winner"], null)


func _test_vc04() -> void:
	_expect_winner("VC04 surround", "VC04", 1, _teams(_team([1000,1000,0], [false,false,true]), _team([1000,0,0], [false,true,true])), "A")
	_expect("VC04 both teams two survivors does not claim", _eval("VC04", 1, _teams())["winner"], null)


func _test_vc05() -> void:
	_expect_winner("VC05 exact half-health boundary", "VC05", 1, _teams(_team(), _team([500,500,500])), "A")
	_expect("VC05 one tenth above boundary fails", _eval("VC05", 1, _teams(_team(), _team([501,500,500]))) ["winner"], null)


func _test_vc06() -> void:
	_expect_winner("VC06 exact quarter-health pair", "VC06", 1, _teams(_team(), _team([250,250,1000])), "A")
	_expect("VC06 one unit above both thresholds fails", _eval("VC06", 1, _teams(_team(), _team([251,251,1000]))) ["winner"], null)


func _test_vc07() -> void:
	_expect_winner("VC07 locked high-H flag", "VC07", 1, _teams(_team(), _team([0,1000,1000], [true,false,false])), "A")
	_expect("VC07 non-flag death not sufficient", _eval("VC07", 1, _teams(_team(), _team([1000,0,1000], [false,true,false]))) ["winner"], null)
	var tied_bases := [{"base_h":100,"base_a":10,"base_t":20,"base_r":1}, {"base_h":100,"base_a":8,"base_t":25,"base_r":0}, {"base_h":80,"base_a":7,"base_t":30,"base_r":0}]
	_expect("VC07 equal base-H chooses lower slot", _eval("VC07", 1,
		_teams(_team(), _team([1000,0,1000], [false,true,false], [1000,1000,1000], tied_bases)))["winner"], null)
	var locked := _memory("VC07")
	var equipped := _team()
	equipped[1]["base_H"] = 999
	equipped[1]["final_departed"] = true
	equipped[1]["hp_tenths"] = 0
	_expect("VC07 post-start base change does not relock", _eval("VC07", 1, _teams(_team(), equipped), locked)["winner"], null)


func _test_vc08() -> void:
	_expect_winner("VC08 highest A/T core", "VC08", 1, _teams(_team(), _team([1000,0,1000], [false,true,false])), "A")
	_expect("VC08 non-core death not sufficient", _eval("VC08", 1, _teams(_team(), _team([0,1000,1000], [true,false,false]))) ["winner"], null)
	var huge_bases := [
		{"base_h":100,"base_a":9_223_372_036_854_775_805,"base_t":9_223_372_036_854_775_806,"base_r":0},
		{"base_h":90,"base_a":9_223_372_036_854_775_806,"base_t":9_223_372_036_854_775_807,"base_r":0},
		{"base_h":80,"base_a":1,"base_t":2,"base_r":0}]
	var huge_target := _teams(_team(), _team([1000,0,1000], [false,true,false], [1000,1000,1000], huge_bases))
	var huge_mem := _memory("VC08", _teams(_team(), _team([1000,1000,1000], [false,false,false], [1000,1000,1000], huge_bases)))
	_expect_winner("VC08 exact int64 A/T ordering selects higher-slot infinitesimal winner", "VC08", 1, huge_target, "A", huge_mem)


func _test_vc09() -> void:
	_expect_winner("VC09 highest base A cannon", "VC09", 1, _teams(_team(), _team([1000,0,1000], [false,true,false])), "A")
	_expect("VC09 non-cannon death not sufficient", _eval("VC09", 1, _teams(_team(), _team([0,1000,1000], [true,false,false]))) ["winner"], null)


func _test_vc10() -> void:
	_expect_winner("VC10 lowest-H weak point", "VC10", 1, _teams(_team(), _team([1000,1000,0], [false,false,true])), "A")
	_expect("VC10 non-weak death not sufficient", _eval("VC10", 1, _teams(_team(), _team([0,1000,1000], [true,false,false]))) ["winner"], null)


func _test_vc11() -> void:
	_expect_winner("VC11 highest-R bastion", "VC11", 1, _teams(_team(), _team([1000,0,1000], [false,true,false])), "A")
	_expect("VC11 other target not sufficient", _eval("VC11", 1, _teams(_team(), _team([0,1000,1000], [true,false,false]))) ["winner"], null)


func _test_vc12() -> void:
	var bases := [{"base_h":120,"base_a":20,"base_t":10,"base_r":0}, {"base_h":90,"base_a":15,"base_t":10,"base_r":0}, {"base_h":80,"base_a":5,"base_t":10,"base_r":0}]
	var start := _teams(_team([1000,1000,1000], [false,false,false], [1000,1000,1000], bases), _team([1000,1000,1000], [false,false,false], [1000,1000,1000], bases))
	var mem := _memory("VC12", start)
	_expect_winner("VC12 overlapping flag/core chooses distinct second core", "VC12", 1,
		_teams(start["A"], _team([0,0,1000], [true,true,false], [1000,1000,1000], bases)), "A", mem)
	_expect("VC12 only one locked core departed is no claim", _eval("VC12", 1,
		_teams(start["A"], _team([0,1000,1000], [true,false,false], [1000,1000,1000], bases)), mem)["winner"], null)
	_expect_winner("VC12 timeout pairs core counts A against B", "VC12", 240,
		_teams(_team([800,700,1000], [false,false,false], [1000,1000,1000], bases),
			_team([0,900,1000], [true,false,false], [1000,1000,1000], bases)), "A", mem)
	_expect_winner("VC12 equal core count compares exact core sums", "VC12", 240,
		_teams(_team([800,0,1000], [false,true,false], [1000,1000,1000], bases),
			_team([0,900,1000], [true,false,false], [1000,1000,1000], bases)), "B", mem)
	_expect_winner("VC12 timeout mirror swaps core-count winner", "VC12", 240,
		_swap(_teams(_team([800,700,1000], [false,false,false], [1000,1000,1000], bases),
			_team([0,900,1000], [true,false,false], [1000,1000,1000], bases))), "B")


func _test_vc13() -> void:
	_expect_winner("VC13 flag plus another departure", "VC13", 1, _teams(_team(), _team([0,0,1000], [true,true,false])), "A")
	_expect("VC13 flag alone does not suffice", _eval("VC13", 1, _teams(_team(), _team([0,1000,1000], [true,false,false]))) ["winner"], null)


func _test_vc14() -> void:
	var initial := _teams()
	var mem := _memory("VC14", initial)
	var acted := _teams()
	acted["B"][0]["first_natural_attack_tick"] = 8
	acted["B"][1]["first_natural_attack_tick"] = 7
	acted["B"][2]["first_natural_attack_tick"] = 7
	acted["B"][1]["final_departed"] = true
	acted["B"][1]["hp_tenths"] = 0
	_expect_winner("VC14 same-tick natural attack chooses smaller slot", "VC14", 7, acted, "A", mem)
	var blocked := _teams()
	blocked["A"][0]["first_natural_attack_tick"] = 2
	blocked["B"][0]["first_natural_attack_tick"] = 2
	_expect("VC14 attack completion ties do not award a claim", _eval("VC14", 2, blocked, mem)["winner"], null)
	var one_attack := _teams(_team([100,100,100]), _team())
	one_attack["A"][0]["first_natural_attack_tick"] = 1
	_expect_winner("VC14 only one team completed a natural attack", "VC14", 240, one_attack, "A", mem)
	var none := _teams(_team([100,100,0], [false,false,true]), _team())
	_expect_winner("VC14 neither attacked falls back to standard L then S", "VC14", 240, none, "B", mem)
	var equal_flags := _teams(_team([500,1000,1000]), _team([500,0,0], [false,true,true]))
	for unit in equal_flags["A"]: unit["first_natural_attack_tick"] = 1
	for unit in equal_flags["B"]: unit["first_natural_attack_tick"] = 2
	_expect_winner("VC14 both flags equal ignores team-sum secondary", "VC14", 240, equal_flags, "draw", mem)


func _test_vc15() -> void:
	var teams := _teams(_team(), _team([750,750,750]))
	var mem := _memory("VC15")
	_expect("VC15 does not start before 4 seconds", _eval("VC15", 39, teams, mem)["winner"], null)
	var at_4 := _eval("VC15", 40, teams, mem); mem = at_4["memory"]
	_expect("VC15 one tick short of 3 seconds", _eval("VC15", 69, teams, mem)["winner"], null)
	_expect_winner("VC15 exact 3-second duration", "VC15", 70, teams, "A", mem)
	var near := _teams(_team(), _team([750,750,751]))
	var near_mem := _memory("VC15")
	near_mem = _eval("VC15", 40, near, near_mem)["memory"]
	_expect("VC15 exact rational difference 0.749 is below threshold", _eval("VC15", 70, near, near_mem)["winner"], null)
	var reset := _teams(_team(), _team([800,800,800]))
	var mem2 := _memory("VC15")
	mem2 = _eval("VC15", 40, teams, mem2)["memory"]
	mem2 = _eval("VC15", 55, reset, mem2)["memory"]
	mem2 = _eval("VC15", 56, teams, mem2)["memory"]
	_expect("VC15 reset does not preserve old progress", _eval("VC15", 85, teams, mem2)["winner"], null)


func _test_vc16() -> void:
	var teams := _teams(_team([1000,1000,0], [false,false,true]), _team([1000,0,0], [false,true,true]))
	var mem := _memory("VC16", teams)
	_expect("VC16 one tick short", _eval("VC16", 39, teams, mem)["winner"], null)
	_expect_winner("VC16 exact 4-second lead", "VC16", 40, teams, "A", mem)
	var reset := _teams(_team([1000,0,0], [false,true,true]), _team([1000,0,0], [false,true,true]))
	var reset_mem := _memory("VC16", teams)
	reset_mem = _eval("VC16", 10, teams, reset_mem)["memory"]
	reset_mem = _eval("VC16", 11, reset, reset_mem)["memory"]
	reset_mem = _eval("VC16", 12, teams, reset_mem)["memory"]
	_expect("VC16 reset clears clock", _eval("VC16", 51, teams, reset_mem)["winner"], null)


func _test_vc17() -> void:
	var teams := _teams(_team([301,1000,1000]), _team([300,1000,1000]))
	var mem := _memory("VC17", teams)
	_expect("VC17 one tick short", _eval("VC17", 29, teams, mem)["winner"], null)
	_expect_winner("VC17 exact boundary and duration", "VC17", 30, teams, "A", mem)
	var equal_flags := _teams(_team([500,1000,1000]), _team([500,0,0], [false,true,true]))
	_expect_winner("VC17 timeout equal flag health ignores team-sum secondary", "VC17", 240, equal_flags, "draw")
	var reset := _teams(_team([300,1000,1000]), _team([300,1000,1000]))
	var reset_mem := _memory("VC17", teams)
	reset_mem = _eval("VC17", 10, teams, reset_mem)["memory"]
	reset_mem = _eval("VC17", 11, reset, reset_mem)["memory"]
	reset_mem = _eval("VC17", 12, teams, reset_mem)["memory"]
	_expect("VC17 equality at 30 percent breaks condition", _eval("VC17", 41, teams, reset_mem)["winner"], null)


func _test_vc18() -> void:
	var teams := _teams(_team(), _team([750,750,1000]))
	var mem := _memory("VC18", teams)
	_expect("VC18 exact quarter and one tick short", _eval("VC18", 29, teams, mem)["winner"], null)
	_expect_winner("VC18 exact quarter for 3 seconds", "VC18", 30, teams, "A", mem)
	var reset := _teams(_team(), _team([750,751,1000]))
	var reset_mem := _memory("VC18", teams)
	reset_mem = _eval("VC18", 10, teams, reset_mem)["memory"]
	reset_mem = _eval("VC18", 11, reset, reset_mem)["memory"]
	reset_mem = _eval("VC18", 12, teams, reset_mem)["memory"]
	_expect("VC18 below two lanes resets", _eval("VC18", 41, teams, reset_mem)["winner"], null)
	_expect("VC18 deadline uses strict h-own greater", _expect_winner("VC18 strict tie lanes", "VC18", 240,
		_teams(_team([800,700,500]), _team([800,700,500])), "draw")["winner"], "draw")
	_expect_winner("VC18 timeout strict h> counts small leads below 0.25", "VC18", 240,
		_teams(_team([800,800,100]), _team([750,750,1000])), "A")


func _test_vc19() -> void:
	var teams := _teams(_team(), _team([0,1000,1000], [true,false,false]))
	var mem := _memory("VC19", teams)
	_expect("VC19 one tick short", _eval("VC19", 19, teams, mem)["winner"], null)
	_expect_winner("VC19 exact 2-second duration", "VC19", 20, teams, "A", mem)
	_expect("VC19 own health equal to half breaks condition", _eval("VC19", 20,
		_teams(_team([500,1000,1000]), _team([0,1000,1000], [true,false,false])), mem)["winner"], null)


func _test_vc20() -> void:
	var teams := _teams(_team([1000,0,0], [false,true,true]), _team([1000,1000,0], [false,false,true]))
	var mem := _memory("VC20", teams)
	var unchanged := teams.duplicate(true)
	for t in range(1, 50): mem = _eval("VC20", t, unchanged, mem)["memory"]
	var wrong_credit := [{"event_id":"dot-other-source", "tick":50, "target_side":"B", "target_slot":2,
		"credited_units":[{"side":"A","slot":2}]}]
	var endpoint := _eval("VC20", 50, unchanged, mem, wrong_credit)
	_expect("VC20 unrelated source does not cancel endpoint timeout", endpoint["winner"], "B")
	var credited := [{"event_id":"lone-kill", "tick":50, "target_side":"B", "target_slot":2,
		"credited_units":[{"side":"A","slot":1}]}]
	var future_event := _eval("VC20", 10, unchanged, _memory("VC20", teams), credited)
	_expect("VC20 does not consume a future-tick departure early", future_event["countdowns"]["vc20_window_ticks_remaining"], 40)
	var killed_state := _teams(_team([1000,0,0], [false,true,true]), _team([1000,0,0], [false,true,true]))
	var kill_result := _eval("VC20", 50, killed_state, mem, credited)
	_expect("VC20 lone credited final departure closes without claim", kill_result["winner"], null)
	var reopened := _eval("VC20", 51, unchanged, kill_result["memory"], [])
	_expect("VC20 population change back into 1v2 opens a fresh window", reopened["countdowns"]["vc20_window_ticks_remaining"], 50)
	var one_v_one := _teams(_team([1000,0,0], [false,true,true]), _team([1000,0,0], [false,true,true]))
	var cancelled_mem := _memory("VC20", teams)
	for t in range(1, 25): cancelled_mem = _eval("VC20", t, unchanged, cancelled_mem)["memory"]
	cancelled_mem = _eval("VC20", 25, one_v_one, cancelled_mem)["memory"]
	var no_phantom_win := _eval("VC20", 50, one_v_one, cancelled_mem)
	_expect("VC20 other-source 1v1 cancels window without phantom majority win", no_phantom_win["winner"], null)
	var reentered := _eval("VC20", 51, unchanged, no_phantom_win["memory"])
	_expect("VC20 only reopens after a later population change", reentered["countdowns"]["vc20_window_ticks_remaining"], 50)
	var mirror_teams := _swap(teams)
	_expect_winner("VC20 mirror assigns timeout claim to other majority", "VC20", 50,
		mirror_teams, "A", _memory("VC20", mirror_teams))


func _test_vc21() -> void:
	var result := _expect_winner("VC21 twelve-second endpoint", "VC21", 120, _teams(_team(), _team([900,900,900])), "A")
	_expect("VC21 uses 120 ticks", result["countdowns"]["battle_ticks_remaining"], 0)


func _test_vc22() -> void:
	_expect_winner("VC22 enemy second departure claims", "VC22", 10,
		_teams(_team(), _team([0,0,1000], [true,true,false])), "A")
	_expect_winner("VC22 own second departure immediately loses", "VC22", 10,
		_teams(_team([0,0,1000], [true,true,false]), _team()), "B")
	_expect_winner("VC22 36-second fallback", "VC22", 360, _teams(_team(), _team([900,900,900])), "A")


func _test_vc23() -> void:
	var teams := _teams(_team([1000,500,0], [false,false,true]), _team([1000,600,0], [false,false,true]))
	_expect_winner("VC23 equal headcount then lowest living health", "VC23", 240, teams, "B")


func _test_vc24() -> void:
	var teams := _teams(_team([900,800,0], [false,false,true]), _team([1000,500,0], [false,false,true]))
	_expect_winner("VC24 both have pair, compare best two", "VC24", 240, teams, "A")
	_expect_winner("VC24 only one reaches two survivors", "VC24", 240,
		_teams(_team([1000,0,0], [false,true,true]), _team()), "B")


func _test_vc25() -> void:
	_expect_winner("VC25 maximum health primary", "VC25", 240, _teams(_team([900,500,500]), _team([800,1000,1000])), "B")


func _test_vc26() -> void:
	_expect_winner("VC26 minimum health primary", "VC26", 240, _teams(_team([600,900,900]), _team([500,1000,1000])), "A")


func _test_vc27() -> void:
	_expect_winner("VC27 smallest enemy bottom-two sum wins", "VC27", 240,
		_teams(_team([900,900,900]), _team([200,300,1000])), "A")


func _test_vc28() -> void:
	_expect_winner("VC28 strict below 75 percent", "VC28", 240, _teams(_team(), _team([749,749,749])), "A")
	var boundary := _eval("VC28", 240, _teams(_team([1000,1000,1000]), _team([750,750,750])))
	_expect("VC28 exact 75 percent is not a sub-75 claim", boundary["claims"]["A"], false)
	_expect("VC28 exact boundary falls through to team health", boundary["winner"], "A")


func _test_vc29() -> void:
	var teams := _teams(_team([900,1000,500]), _team([500,1000,1000]))
	_expect_winner("VC29 flag plus strongest ally", "VC29", 240, teams, "A")
	var fallen := _teams(_team([0,1000,500], [true,false,false]), _team([0,800,700], [true,false,false]))
	_expect_winner("VC29 fallen flags do not early-lose; deadline falls to standard", "VC29", 240, fallen, "draw")


func _test_vc30() -> void:
	_expect_winner("VC30 fewer enemies above half", "VC30", 240,
		_teams(_team(), _team([500,500,1000])), "A")


func _test_arithmetic_and_contract() -> void:
	var mem := _memory("VC15")
	var extreme_a := _team([99_990,99_988,99_970], [false,false,false], [99_991,99_989,99_971])
	var extreme_b := _team([99_989,99_987,99_969], [false,false,false], [99_991,99_989,99_971])
	var exact := _eval("VC15", 40, _teams(extreme_a, extreme_b), mem)
	_expect("overflow-guarded large coprime denominators remain valid", exact.has("error"), false)
	var invalid := Rules.evaluate("VC01", 0, _teams(), {})
	_expect("valid first-tick contract accepted", invalid.has("error"), false)
	_expect("snapshot mutation cannot change stored target locks", Rules.evaluate("VC07", 0, _teams(), {})["memory"]["locks"]["B"]["flag"], 1)
	var too_large := _teams(_team([1,1,1], [false,false,false], [100_001,1000,1000]), _team())
	_expect("extreme denominator beyond domain is rejected", Rules.evaluate("VC01", 0, too_large, {}).has("error"), true)
	var max_domain := _teams(_team([100_000,99_990,99_988], [false,false,false], [100_000,99_991,99_989]),
		_team([99_999,99_989,99_987], [false,false,false], [100_000,99_991,99_989]))
	_expect("maximum documented denominator is accepted without overflow", Rules.evaluate("VC15", 0, max_domain, {}).has("error"), false)
	var wrong_tick := Rules.evaluate("VC01", 1, _teams(), {})
	_expect("first call after tick zero cannot silently relock", wrong_tick.has("error"), true)
	_expect("malformed VC1 identifier is rejected", Rules.evaluate("VC1", 0, _teams(), {}).has("error"), true)
	_expect("trailing rule-id text is rejected", Rules.evaluate("VC01foo", 0, _teams(), {}).has("error"), true)
	var skipped := Rules.evaluate("VC15", 2, _teams(), _memory("VC15"))
	_expect("continuous-rule tick skipping is rejected", skipped.has("error"), true)
	var bad_event := {"event_id":"dup", "tick":0, "target_side":"B", "target_slot":1, "credited_units":[]}
	_expect("duplicate final-departure event IDs are rejected", Rules.evaluate("VC20", 0, _teams(), {}, [bad_event,bad_event]).has("error"), true)
	var reason_result := _expect_winner("winner output has concrete explanation", "VC07", 1,
		_teams(_team(), _team([0,1000,1000], [true,false,false])), "A")
	_expect("winner reason contains fixed slot and remaining health", reason_result["reason"].contains("B1=0/1000"), true)
	_expect("winner output exposes locked target slot", reason_result["locked_targets"]["B"]["flag"], 1)
