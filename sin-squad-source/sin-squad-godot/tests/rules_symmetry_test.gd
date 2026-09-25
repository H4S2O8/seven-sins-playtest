extends SceneTree

const Rules = preload("res://core/rules/victory_rules.gd")
const SEEDS := [11, 73, 2026]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for seed_value in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var history := _make_history(seed_value, rng)
		for rule_number in range(1, 31):
			var rule_id := "VC%02d" % rule_number
			var deadline := 120 if rule_id == "VC21" else (360 if rule_id == "VC22" else 240)
			var memory: Dictionary = {}
			var mirrored_memory: Dictionary = {}
			var baseline_locks: Dictionary = {}
			var finished := false
			for tick in range(deadline + 1):
				var teams: Dictionary = _snapshot(history, tick)
				var mirrored_teams: Dictionary = _swap_teams(teams)
				var departures: Array = _departures_through(history, tick)
				var mirrored_departures: Array = _swap_departures(departures)
				var result: Dictionary = Rules.evaluate(rule_id, tick, teams, memory, departures)
				var mirrored_result: Dictionary = Rules.evaluate(rule_id, tick, mirrored_teams, mirrored_memory, mirrored_departures)
				if result.has("error") or mirrored_result.has("error"):
					_fail("%s seed=%d tick=%d input error: %s / %s" % [rule_id, seed_value, tick, result.get("error", ""), mirrored_result.get("error", "")])
					break
				_assert_pair(rule_id, seed_value, tick, result, mirrored_result)
				_assert_locked_slots(rule_id, seed_value, tick, result, mirrored_result)
				if tick == 0:
					baseline_locks = result["memory"]["locks"].duplicate(true)
				else:
					_assert_base_locks_unchanged(rule_id, seed_value, tick, baseline_locks, result["memory"]["locks"])
				if bool(result["terminal"]) != bool(mirrored_result["terminal"]):
					_fail("%s seed=%d tick=%d terminal state not symmetric" % [rule_id, seed_value, tick])
					break
				if bool(result["terminal"]):
					finished = true
					break
				memory = result["memory"]
				mirrored_memory = mirrored_result["memory"]
			if not finished and failures.is_empty():
				_fail("%s seed=%d did not resolve at or before its deadline" % [rule_id, seed_value])
	if failures.is_empty():
		print("PASS: %d symmetry assertions; VC01-VC30 x 3 seeds; mirrored claims, final-departure credits, and locked slots" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		printerr("FAIL: %d symmetry assertion(s) failed across %d checks" % [failures.size(), checks])
		quit(1)


func _make_history(seed_value: int, rng: RandomNumberGenerator) -> Dictionary:
	var units := {"A": [], "B": []}
	for side in ["A", "B"]:
		for slot in [1, 2, 3]:
			var base_h: int = rng.randi_range(84, 152)
			var base_a: int = rng.randi_range(6, 20)
			var base_t: int = rng.randi_range(6, 50)
			var base_r: int = rng.randi_range(0, 10)
			units[side].append({
				"slot":slot,
				"base_H":base_h,
				"base_A":base_a,
				"base_T_ticks":base_t,
				"base_R":base_r,
				"max_hp":base_h * 10 + rng.randi_range(0, 100),
				"wear_per_tick":rng.randi_range(0, 3),
				"natural_attack_tick":rng.randi_range(0, 28),
			})
	var first_b_slot := 2 + (seed_value % 2)
	var second_b_slot := 5 - first_b_slot
	var first_departure_tick := 5 + (seed_value % 3)
	var second_departure_tick := first_departure_tick + 5
	var third_departure_tick := second_departure_tick + 9
	var fourth_departure_tick := third_departure_tick + 50
	var fifth_departure_tick := fourth_departure_tick + 25
	var deaths := [
		{"side":"B", "slot":first_b_slot, "tick":first_departure_tick},
		{"side":"A", "slot":3, "tick":second_departure_tick},
		{"side":"A", "slot":2, "tick":third_departure_tick},
		{"side":"B", "slot":second_b_slot, "tick":fourth_departure_tick},
		{"side":"A", "slot":1, "tick":fifth_departure_tick},
	]
	var departures: Array = []
	var creditors := ["A", "B", "B", "A", "B"]
	var credit_slots := [1, 1, 1, 1, 1]
	for index in range(deaths.size()):
		var death: Dictionary = deaths[index]
		departures.append({
			"event_id":"seed-%d-departure-%d" % [seed_value, index + 1],
			"tick":death["tick"],
			"target_side":death["side"],
			"target_slot":death["slot"],
			"credited_units":[{"side":creditors[index], "slot":credit_slots[index]}],
		})
	return {"units":units, "deaths":deaths, "departures":departures}


func _snapshot(history: Dictionary, tick: int) -> Dictionary:
	var result := {"A": [], "B": []}
	for side in ["A", "B"]:
		for source in history["units"][side]:
			var departed := false
			for death in history["deaths"]:
				if death["side"] == side and int(death["slot"]) == int(source["slot"]) and int(death["tick"]) <= tick:
					departed = true
					break
			var max_hp: int = source["max_hp"]
			var current_hp := 0 if departed else maxi(max_hp - tick * int(source["wear_per_tick"]), 1)
			var attack_tick = int(source["natural_attack_tick"]) if int(source["natural_attack_tick"]) <= tick else null
			result[side].append({
				"slot":int(source["slot"]),
				"base_H":int(source["base_H"]),
				"base_A":int(source["base_A"]),
				"base_T_ticks":int(source["base_T_ticks"]),
				"base_R":int(source["base_R"]),
				"hp_tenths":current_hp,
				"initial_max_hp_tenths":max_hp,
				"final_departed":departed,
				"first_natural_attack_tick":attack_tick,
			})
	return result


func _swap_teams(teams: Dictionary) -> Dictionary:
	var result := {"A": [], "B": []}
	result["A"] = teams["B"].duplicate(true)
	result["B"] = teams["A"].duplicate(true)
	return result


func _swap_departures(departures: Array) -> Array:
	var result: Array = []
	for event in departures:
		var swapped: Dictionary = event.duplicate(true)
		swapped["target_side"] = _other(str(event["target_side"]))
		for credited in swapped["credited_units"]:
			credited["side"] = _other(str(credited["side"]))
		result.append(swapped)
	return result


func _departures_through(history: Dictionary, tick: int) -> Array:
	var result: Array = []
	for event in history["departures"]:
		if int(event["tick"]) <= tick:
			result.append(event.duplicate(true))
	return result


func _assert_pair(rule_id: String, seed_value: int, tick: int, result: Dictionary, mirrored: Dictionary) -> void:
	checks += 2
	if result["claims"]["A"] != mirrored["claims"]["B"] or result["claims"]["B"] != mirrored["claims"]["A"]:
		_fail("%s seed=%d tick=%d claims failed A/B mirror" % [rule_id, seed_value, tick])
	var expected = "draw" if result["winner"] == "draw" else (null if result["winner"] == null else _other(str(result["winner"])))
	if mirrored["winner"] != expected:
		_fail("%s seed=%d tick=%d winner %s mirrored as %s, expected %s" % [rule_id, seed_value, tick, str(result["winner"]), str(mirrored["winner"]), str(expected)])


func _assert_locked_slots(rule_id: String, seed_value: int, tick: int, result: Dictionary, mirrored: Dictionary) -> void:
	var original: Dictionary = result["memory"].get("locks", {})
	var swapped: Dictionary = mirrored["memory"].get("locks", {})
	if original.is_empty() or swapped.is_empty():
		_fail("%s seed=%d tick=%d missing target locks" % [rule_id, seed_value, tick])
		return
	for field in ["flag", "fire", "cannon", "weak", "bastion", "cores", "first_attacker", "first_attack_tick"]:
		checks += 2
		if original["A"].get(field) != swapped["B"].get(field):
			_fail("%s seed=%d tick=%d A.%s slot changed under mirror" % [rule_id, seed_value, tick, field])
		if original["B"].get(field) != swapped["A"].get(field):
			_fail("%s seed=%d tick=%d B.%s slot changed under mirror" % [rule_id, seed_value, tick, field])


func _assert_base_locks_unchanged(rule_id: String, seed_value: int, tick: int, baseline: Dictionary, current: Dictionary) -> void:
	for side in ["A", "B"]:
		for field in ["flag", "fire", "cannon", "weak", "bastion", "cores"]:
			checks += 1
			if baseline[side].get(field) != current[side].get(field):
				_fail("%s seed=%d tick=%d %s.%s base target lock changed" % [rule_id, seed_value, tick, side, field])


func _other(side: String) -> String:
	return "B" if side == "A" else "A"


func _fail(message: String) -> void:
	if failures.size() < 20: failures.append(message)
