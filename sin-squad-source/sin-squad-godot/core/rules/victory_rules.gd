extends RefCounted
class_name VictoryRules

## Pure-data victory adjudication. No SceneTree, rendering, or floating-point health.
## API: evaluate(rule_id: String, tick: int, teams: Dictionary,
##               memory: Dictionary, final_departures: Array = []) -> Dictionary
## teams must contain A and B, each an Array of three slot-ordered Dictionaries.
## See evidence/W03-rules.md for the complete input/output contract.

const BATTLE_TICKS := {
	"VC21": 120,
	"VC22": 360,
}
const DEFAULT_BATTLE_TICKS := 240
const MAX_HP_TENTHS := 100_000
const INT64_MAX := 9_223_372_036_854_775_807
const SIDES := ["A", "B"]
const SLOTS := [1, 2, 3]


static func evaluate(rule_id: String, tick: int, teams: Dictionary,
		memory: Dictionary, final_departures: Array = []) -> Dictionary:
	var err := _validate_input(rule_id, tick, teams, memory, final_departures)
	if err != "":
		return _error_result(err, memory)
	if tick > _deadline(rule_id):
		return _error_result("tick 超过本规则期限；调用方必须在期限端点结束战斗", memory)
	if memory.is_empty() and tick != 0:
		return _error_result("首次 evaluate 必须在开战 tick=0 调用以锁定关键目标", memory)

	var next_memory: Dictionary = memory.duplicate(true)
	if not next_memory.has("schema"):
		next_memory = _initial_memory(rule_id, teams)
	elif str(next_memory.get("rule_id", "")) != rule_id:
		return _error_result("memory.rule_id 与输入 rule_id 不一致", memory)
	if not memory.is_empty() and tick != int(memory.get("last_tick", -1)) + 1:
		return _error_result("evaluate 必须按每个 0.1 秒tick顺序调用，不得跳过或重复", memory)

	# Key targets are immutable for the whole battle. The caller must first call at t=0.
	if not next_memory.has("locks"):
		if tick != 0:
			return _error_result("首次 evaluate 必须在开战 tick=0 调用以锁定关键目标", memory)
		next_memory["locks"] = _lock_targets(rule_id, teams)
	_update_first_attackers(next_memory, teams, tick)

	var duration_error := _check_health_domain(teams)
	if duration_error != "":
		return _error_result(duration_error, memory)

	var countdowns := {"battle_ticks_remaining": maxi(_deadline(rule_id) - tick, 0)}
	var rule_claims := {"A": false, "B": false}
	var claim_reasons := {"A": "", "B": ""}

	if rule_id == "VC15":
		_update_continuous(next_memory, "advantage", tick, teams,
			func(side: String) -> bool: return tick >= 40 and _sum_delta_at_least(teams, side, 3, 4), 30)
		for side in SIDES:
			var since: int = int(next_memory["continuous"]["advantage"][side])
			if since >= 0:
				countdowns["%s_advantage_ticks_remaining" % side] = maxi(since + 30 - tick, 0)
				if tick >= 40 and tick - since >= 30:
					rule_claims[side] = true
					claim_reasons[side] = "整队健康优势至少0.75，已连续维持3.0秒"
	elif rule_id == "VC16":
		_update_continuous(next_memory, "headcount", tick, teams,
			func(side: String) -> bool: return _alive_count(teams[side]) - _alive_count(teams[_other(side)]) >= 1, 40)
		for side in SIDES:
			var since: int = int(next_memory["continuous"]["headcount"][side])
			if since >= 0:
				countdowns["%s_headcount_ticks_remaining" % side] = maxi(since + 40 - tick, 0)
				if tick - since >= 40:
					rule_claims[side] = true
					claim_reasons[side] = "存活人数领先至少1人，已连续维持4.0秒"
	elif rule_id == "VC17":
		_update_continuous(next_memory, "flag_trap", tick, teams,
			func(side: String) -> bool:
				var own_flag: int = int(next_memory["locks"][side].get("flag", 0))
				var enemy_flag: int = int(next_memory["locks"][_other(side)].get("flag", 0))
				return own_flag > 0 and enemy_flag > 0 \
					and _health_at_most(teams[_other(side)][enemy_flag - 1], 3, 10) \
					and _health_greater(teams[side][own_flag - 1], 3, 10), 30)
		for side in SIDES:
			var since: int = int(next_memory["continuous"]["flag_trap"][side])
			if since >= 0:
				countdowns["%s_flag_trap_ticks_remaining" % side] = maxi(since + 30 - tick, 0)
				if tick - since >= 30:
					rule_claims[side] = true
					claim_reasons[side] = "敌旗健康≤30%、己旗健康>30%，已连续维持3.0秒"
	elif rule_id == "VC18":
		_update_continuous(next_memory, "two_lanes", tick, teams,
			func(side: String) -> bool: return _winning_lanes(teams, side, false) >= 2, 30)
		for side in SIDES:
			var since: int = int(next_memory["continuous"]["two_lanes"][side])
			if since >= 0:
				countdowns["%s_two_lanes_ticks_remaining" % side] = maxi(since + 30 - tick, 0)
				if tick - since >= 30:
					rule_claims[side] = true
					claim_reasons[side] = "至少两组对位健康领先0.25，已连续维持3.0秒"
	elif rule_id == "VC19":
		_update_continuous(next_memory, "clean_line", tick, teams,
			func(side: String) -> bool:
				return _departed_count(teams[_other(side)]) >= 1 \
					and _all_health_greater(teams[side], 1, 2), 20)
		for side in SIDES:
			var since: int = int(next_memory["continuous"]["clean_line"][side])
			if since >= 0:
				countdowns["%s_clean_line_ticks_remaining" % side] = maxi(since + 20 - tick, 0)
				if tick - since >= 20:
					rule_claims[side] = true
					claim_reasons[side] = "敌方已有最终退场且己方三人健康均>50%，已维持2.0秒"
	elif rule_id == "VC20":
		_update_vc20(next_memory, tick, teams, final_departures, rule_claims, claim_reasons, countdowns)

	# Other non-window early rules are evaluated from the settled snapshot.
	if rule_id not in ["VC15", "VC16", "VC17", "VC18", "VC19", "VC20"]:
		for side in SIDES:
			var enemy: Array = teams[_other(side)]
			var locks: Dictionary = next_memory["locks"]
			var own_locks: Dictionary = locks[side]
			var enemy_locks: Dictionary = locks[_other(side)]
			match rule_id:
				"VC01":
					if _all_final_departed(enemy): _set_claim(rule_claims, claim_reasons, side, "敌方全队最终退场")
				"VC02":
					if _departed_count(enemy) >= 1: _set_claim(rule_claims, claim_reasons, side, "敌方首名人物最终退场")
				"VC03":
					if _departed_count(enemy) >= 2: _set_claim(rule_claims, claim_reasons, side, "敌方两人最终退场")
				"VC04":
					if _alive_count(teams[side]) >= 2 and _alive_count(enemy) == 1: _set_claim(rule_claims, claim_reasons, side, "己方至少两人存活且敌方仅余一人")
				"VC05":
					if _all_health_at_most(enemy, 1, 2): _set_claim(rule_claims, claim_reasons, side, "敌方三人健康均≤50%")
				"VC06":
					if _count_health_at_most(enemy, 1, 4) >= 2: _set_claim(rule_claims, claim_reasons, side, "敌方至少两人健康≤25%")
				"VC07":
					if _is_departed(enemy, int(enemy_locks.get("flag", 0))): _set_claim(rule_claims, claim_reasons, side, "敌方锁定旗手最终退场")
				"VC08":
					if _is_departed(enemy, int(enemy_locks.get("fire", 0))): _set_claim(rule_claims, claim_reasons, side, "敌方锁定火力核心最终退场")
				"VC09":
					if _is_departed(enemy, int(enemy_locks.get("cannon", 0))): _set_claim(rule_claims, claim_reasons, side, "敌方锁定重炮最终退场")
				"VC10":
					if _is_departed(enemy, int(enemy_locks.get("weak", 0))): _set_claim(rule_claims, claim_reasons, side, "敌方锁定薄弱点最终退场")
				"VC11":
					if _is_departed(enemy, int(enemy_locks.get("bastion", 0))): _set_claim(rule_claims, claim_reasons, side, "敌方锁定堡垒最终退场")
				"VC12":
					var cores: Array = enemy_locks.get("cores", [])
					if cores.size() == 2 and _is_departed(enemy, int(cores[0])) and _is_departed(enemy, int(cores[1])):
						_set_claim(rule_claims, claim_reasons, side, "敌方旗手与火力核心均最终退场")
				"VC13":
					if _is_departed(enemy, int(enemy_locks.get("flag", 0))) and _departed_count(enemy) >= 2:
						_set_claim(rule_claims, claim_reasons, side, "敌旗手与另一名敌人均最终退场")
				"VC14":
					var enemy_flag: int = int(enemy_locks.get("first_attacker", 0))
					if _is_departed(enemy, enemy_flag): _set_claim(rule_claims, claim_reasons, side, "敌方先手旗手最终退场")
				"VC22":
					if _departed_count(enemy) >= 2: _set_claim(rule_claims, claim_reasons, side, "敌方第二人最终退场")

	# Full elimination is a claim, never an override. VC22 also makes a side's
	# second final departure an opponent claim, as specified by the parent card.
	for side in SIDES:
		var enemy_side := _other(side)
		if _all_final_departed(teams[enemy_side]):
			_set_claim(rule_claims, claim_reasons, side, "通用全灭：敌方全队最终退场")
		if rule_id == "VC22" and _departed_count(teams[side]) >= 2:
			_set_claim(rule_claims, claim_reasons, enemy_side, "VC22：己方第二人最终退场，立即判负")

	next_memory["last_tick"] = tick
	var result := _base_result(rule_id, tick, next_memory, rule_claims, claim_reasons, countdowns, teams)
	if result["winner"] == null and tick >= _deadline(rule_id):
		var comparison := _deadline_comparison(rule_id, teams, next_memory)
		result = _resolve_comparison(rule_id, tick, next_memory, rule_claims, claim_reasons, countdowns, comparison, teams)
	return result


static func _validate_input(rule_id: String, tick: int, teams: Dictionary, memory: Dictionary, departures: Array) -> String:
	if not _known_rule(rule_id): return "未知胜利规则 ID: %s" % rule_id
	if tick < 0: return "tick 必须是非负 0.1 秒整数"
	for side in SIDES:
		if not teams.has(side) or not teams[side] is Array or teams[side].size() != 3:
			return "teams.%s 必须是 slot 1-3 的三个单位快照" % side
		for i in range(3):
			var unit = teams[side][i]
			if not unit is Dictionary: return "%s slot %d 必须是 Dictionary" % [side, i + 1]
			if int(unit.get("slot", -1)) != i + 1: return "%s 单位必须按 slot 1-3 固定排序" % side
			for field in ["base_H", "base_A", "base_T_ticks", "base_R", "hp_tenths", "initial_max_hp_tenths"]:
				if not unit.has(field) or not (unit[field] is int): return "%s slot %d 缺少整数 %s" % [side, i + 1, field]
			if int(unit["base_H"]) <= 0 or int(unit["base_A"]) < 0 or int(unit["base_T_ticks"]) <= 0 or int(unit["base_R"]) < 0:
				return "%s slot %d base_H/base_T_ticks 必须为正，base_A/base_R 不得为负" % [side, i + 1]
			if not unit.has("final_departed") or not unit["final_departed"] is bool: return "%s slot %d 缺少布尔 final_departed" % [side, i + 1]
			if not unit.has("first_natural_attack_tick") or (unit["first_natural_attack_tick"] != null and not unit["first_natural_attack_tick"] is int):
				return "%s slot %d first_natural_attack_tick 必须为整数或 null" % [side, i + 1]
	if not memory.is_empty() and (not memory.has("schema") or int(memory.get("schema", -1)) != 1): return "未知 rules memory schema"
	var event_ids: Dictionary = {}
	for event in departures:
		if not event is Dictionary: return "final_departures 元素必须是 Dictionary"
		for field in ["event_id", "tick", "target_side", "target_slot", "credited_units"]:
			if not event.has(field): return "final_departures 缺少字段 %s" % field
		if not event["event_id"] is String or str(event["event_id"]).is_empty(): return "final_departures.event_id 必须为非空字符串"
		if event_ids.has(event["event_id"]): return "final_departures.event_id 必须唯一"
		event_ids[event["event_id"]] = true
		if not event["tick"] is int or int(event["tick"]) < 0: return "final_departures.tick 必须是非负整数"
		if not event["target_side"] is String or not event["target_slot"] is int: return "final_departures target_side/target_slot 类型无效"
		if int(event["tick"]) > _deadline(rule_id): return "final_departures.tick 不得晚于规则期限"
		if str(event["target_side"]) not in SIDES or int(event["target_slot"]) not in SLOTS: return "final_departures target 必须指向 A/B 的 slot 1-3"
		if not event["credited_units"] is Array: return "final_departures.credited_units 必须为 Array"
		for credited in event["credited_units"]:
			if not credited is Dictionary or not credited.get("side", "") is String or not credited.get("slot", 0) is int or str(credited["side"]) not in SIDES or int(credited["slot"]) not in SLOTS:
				return "credited_units 每项必须含 side(A/B) 与 slot(1-3)"
	return ""


static func _check_health_domain(teams: Dictionary) -> String:
	for side in SIDES:
		for unit in teams[side]:
			var maximum: int = unit["initial_max_hp_tenths"]
			if maximum <= 0 or maximum > MAX_HP_TENTHS: return "initial_max_hp_tenths 超出允许区间 1..%d" % MAX_HP_TENTHS
			if int(unit["hp_tenths"]) < 0: return "hp_tenths 不得为负数"
		# With three denominators <= 100,000, their LCM is <= 10^15. The
		# largest intermediate for S + 3/4 is <= 15*10^15, safely below int64.
		var sum: Dictionary = _sum_health(teams[side])
		if sum.is_empty(): return "%s 整队健康有理数求和超出安全64位范围" % side
		if _add_rational(sum, {"n":3,"d":4}).is_empty(): return "%s 健康差阈值运算超出安全64位范围" % side
	return ""


static func _initial_memory(rule_id: String, teams: Dictionary) -> Dictionary:
	return {"schema": 1, "rule_id": rule_id, "last_tick": 0, "locks": _lock_targets(rule_id, teams),
		"continuous": {}, "vc20": {"active": false, "lone_side": "", "lone_slot": 0,
			"start_tick": -1, "awaiting_change": false, "last_counts": {}, "processed_event_ids": []}}


static func _lock_targets(rule_id: String, teams: Dictionary) -> Dictionary:
	var locks := {"A": {}, "B": {}}
	for side in SIDES:
		var side_locks: Dictionary = {}
		var units: Array = teams[side]
		var flag := _best_slot(units, "base_H", true)
		var cannon := _best_slot(units, "base_A", true)
		var weak := _best_slot(units, "base_H", false)
		var bastion := _best_slot(units, "base_R", true)
		var fire := _best_fire_slot(units)
		side_locks["flag"] = flag
		side_locks["cannon"] = cannon
		side_locks["weak"] = weak
		side_locks["bastion"] = bastion
		side_locks["fire"] = fire
		var core: int = fire
		if core == flag:
			core = 0
			for slot in SLOTS:
				if slot == flag: continue
				if core == 0 or _compare_int_ratio(int(units[slot - 1]["base_A"]), int(units[slot - 1]["base_T_ticks"]),
					int(units[core - 1]["base_A"]), int(units[core - 1]["base_T_ticks"])) > 0:
					core = slot
		side_locks["cores"] = [flag, core]
		side_locks["first_attacker"] = 0
		side_locks["first_attack_tick"] = -1
		locks[side] = side_locks
	return locks


static func _update_first_attackers(mem: Dictionary, teams: Dictionary, tick: int) -> void:
	for side in SIDES:
		var side_locks: Dictionary = mem["locks"][side]
		if int(side_locks.get("first_attack_tick", -1)) >= 0: continue
		var earliest_tick := -1
		var first_slot := 0
		for unit in teams[side]:
			if unit["first_natural_attack_tick"] == null: continue
			var attack_tick: int = int(unit["first_natural_attack_tick"])
			if attack_tick > tick: continue
			if earliest_tick < 0 or attack_tick < earliest_tick or (attack_tick == earliest_tick and int(unit["slot"]) < first_slot):
				earliest_tick = attack_tick
				first_slot = int(unit["slot"])
		if earliest_tick >= 0:
			side_locks["first_attacker"] = first_slot
			side_locks["first_attack_tick"] = earliest_tick


static func _best_slot(units: Array, field: String, highest: bool) -> int:
	var best := 1
	for slot in [2, 3]:
		var a: int = int(units[slot - 1][field])
		var b: int = int(units[best - 1][field])
		if (a > b if highest else a < b): best = slot
	return best


static func _best_fire_slot(units: Array) -> int:
	var best := 1
	for slot in [2, 3]:
		var candidate_t: int = int(units[slot - 1]["base_T_ticks"])
		var best_t: int = int(units[best - 1]["base_T_ticks"])
		if candidate_t <= 0 or best_t <= 0: continue
		if _compare_int_ratio(int(units[slot - 1]["base_A"]), candidate_t,
			int(units[best - 1]["base_A"]), best_t) > 0: best = slot
	return best


static func _compare_int_ratio(an: int, ad: int, bn: int, bd: int) -> int:
	if ad <= 0 or bd <= 0: return 0
	return _ratio_compare({"n":an,"d":ad}, {"n":bn,"d":bd})


static func _health(unit: Dictionary) -> Dictionary:
	if bool(unit["final_departed"]): return {"n": 0, "d": 1}
	var den: int = int(unit["initial_max_hp_tenths"])
	var num: int = mini(int(unit["hp_tenths"]), den)
	if num <= 0: return {"n": 0, "d": 1}
	var g: int = _gcd(num, den)
	return {"n": int(num / g), "d": int(den / g)}


static func _sum_health(units: Array) -> Dictionary:
	var total := {"n": 0, "d": 1}
	for unit in units:
		var next := _add_rational(total, _health(unit))
		if next.is_empty(): return {}
		total = next
	return total


static func _add_rational(a: Dictionary, b: Dictionary) -> Dictionary:
	var g: int = _gcd(int(a["d"]), int(b["d"]))
	var af: int = int(int(b["d"]) / g)
	var bf: int = int(int(a["d"]) / g)
	if (af != 0 and int(a["n"]) > INT64_MAX / af) or (bf != 0 and int(b["n"]) > INT64_MAX / bf): return {}
	var an: int = int(a["n"]) * af
	var bn: int = int(b["n"]) * bf
	if an > INT64_MAX - bn or int(a["d"]) > INT64_MAX / af: return {}
	var den: int = int(a["d"]) * af
	var num: int = an + bn
	var reduce: int = _gcd(num, den)
	return {"n": int(num / reduce), "d": int(den / reduce)}


## Exact non-negative rational comparison by continued fractions; no cross-products.
static func _ratio_compare(a: Dictionary, b: Dictionary) -> int:
	var an: int = int(a["n"])
	var ad: int = int(a["d"])
	var bn: int = int(b["n"])
	var bd: int = int(b["d"])
	var reverse := false
	while true:
		var aq: int = int(an / ad)
		var bq: int = int(bn / bd)
		if aq != bq:
			var greater := aq > bq
			return (1 if greater else -1) * (-1 if reverse else 1)
		var ar: int = an % ad
		var br: int = bn % bd
		if ar == 0 or br == 0:
			if ar == 0 and br == 0: return 0
			if ar == 0: return 1 if reverse else -1
			return -1 if reverse else 1
		an = ad
		ad = ar
		bn = bd
		bd = br
		reverse = not reverse
	return 0


static func _gcd(a: int, b: int) -> int:
	var x := absi(a)
	var y := absi(b)
	while y != 0:
		var r: int = x % y
		x = y
		y = r
	return maxi(x, 1)


static func _sum_delta_at_least(teams: Dictionary, side: String, numerator: int, denominator: int) -> bool:
	var own: Dictionary = _sum_health(teams[side])
	var enemy: Dictionary = _sum_health(teams[_other(side)])
	if own.is_empty() or enemy.is_empty(): return false
	# A >= B + p/q. Build B+p/q with gcd reduction and guarded integer arithmetic.
	var threshold := _add_rational(enemy, {"n": numerator, "d": denominator})
	if threshold.is_empty(): return false
	return _ratio_compare(own, threshold) >= 0


static func _health_at_most(unit: Dictionary, numerator: int, denominator: int) -> bool:
	return _ratio_compare(_health(unit), {"n": numerator, "d": denominator}) <= 0


static func _health_greater(unit: Dictionary, numerator: int, denominator: int) -> bool:
	return _ratio_compare(_health(unit), {"n": numerator, "d": denominator}) > 0


static func _all_health_at_most(units: Array, numerator: int, denominator: int) -> bool:
	for unit in units:
		if not _health_at_most(unit, numerator, denominator): return false
	return true


static func _all_health_greater(units: Array, numerator: int, denominator: int) -> bool:
	for unit in units:
		if not _health_greater(unit, numerator, denominator): return false
	return true


static func _count_health_at_most(units: Array, numerator: int, denominator: int) -> int:
	var count := 0
	for unit in units:
		if _health_at_most(unit, numerator, denominator): count += 1
	return count


static func _alive(unit: Dictionary) -> bool:
	return not bool(unit["final_departed"]) and int(unit["hp_tenths"]) > 0


static func _alive_count(units: Array) -> int:
	var count := 0
	for unit in units:
		if _alive(unit): count += 1
	return count


static func _departed_count(units: Array) -> int:
	var count := 0
	for unit in units:
		if bool(unit["final_departed"]): count += 1
	return count


static func _all_final_departed(units: Array) -> bool:
	return _departed_count(units) == 3


static func _is_departed(units: Array, slot: int) -> bool:
	return slot >= 1 and slot <= 3 and bool(units[slot - 1]["final_departed"])


static func _winning_lanes(teams: Dictionary, side: String, strict: bool) -> int:
	var count := 0
	for i in range(3):
		var own: Dictionary = _health(teams[side][i])
		var enemy: Dictionary = _health(teams[_other(side)][i])
		if strict:
			if _ratio_compare(own, enemy) > 0: count += 1
		else:
			var required := _add_rational(enemy, {"n": 1, "d": 4})
			if not required.is_empty() and _ratio_compare(own, required) >= 0: count += 1
	return count


static func _update_continuous(mem: Dictionary, key: String, tick: int, teams: Dictionary,
		condition: Callable, duration: int) -> void:
	if not mem.has("continuous"): mem["continuous"] = {}
	if not mem["continuous"].has(key): mem["continuous"][key] = {"A": -1, "B": -1}
	for side in SIDES:
		if condition.call(side):
			if int(mem["continuous"][key][side]) < 0: mem["continuous"][key][side] = tick
		else:
			mem["continuous"][key][side] = -1


static func _update_vc20(mem: Dictionary, tick: int, teams: Dictionary, departures: Array,
		claims: Dictionary, reasons: Dictionary, countdowns: Dictionary) -> void:
	var state: Dictionary = mem["vc20"]
	var counts := {"A": _alive_count(teams["A"]), "B": _alive_count(teams["B"])}
	var active_side: String = str(state.get("lone_side", ""))
	var start_tick: int = int(state.get("start_tick", -1))
	var processed: Array = state.get("processed_event_ids", [])

	# Resolve qualifying final-departure credits before checking the window endpoint.
	if bool(state.get("active", false)):
		var close_by_kill := false
		for event in departures:
			var event_id: String = event["event_id"]
			if processed.has(event_id): continue
			if int(event["tick"]) < start_tick or int(event["tick"]) > tick or int(event["tick"]) > start_tick + 50: continue
			if str(event["target_side"]) == active_side: continue
			for credit in event["credited_units"]:
				if str(credit["side"]) == active_side and int(credit["slot"]) == int(state["lone_slot"]):
					close_by_kill = true
					break
			if close_by_kill: break
		if close_by_kill:
			state["active"] = false
			state["awaiting_change"] = true
			state["last_counts"] = counts.duplicate()
			state["start_tick"] = -1
			state["lone_side"] = ""
			state["lone_slot"] = 0
		elif counts[active_side] != 1 or counts[_other(active_side)] < 2:
			# Population changed without a qualifying credited kill. The window
			# expires as ineligible, but that change is not a VC20 victory claim.
			state["active"] = false
			state["awaiting_change"] = true
			state["last_counts"] = counts.duplicate()
			state["start_tick"] = -1
			state["lone_side"] = ""
			state["lone_slot"] = 0

	if bool(state.get("active", false)):
		var elapsed: int = tick - start_tick
		countdowns["vc20_window_ticks_remaining"] = maxi(50 - elapsed, 0)
		if elapsed >= 50:
			claims[_other(active_side)] = true
			reasons[_other(active_side)] = "VC20：孤身者5.0秒窗口内未由本人击倒敌人"
			state["active"] = false
			state["awaiting_change"] = true
			state["last_counts"] = counts.duplicate()
			state["start_tick"] = -1
			state["lone_side"] = ""
			state["lone_slot"] = 0
	else:
		var eligible_side := ""
		if counts["A"] == 1 and counts["B"] >= 2: eligible_side = "A"
		elif counts["B"] == 1 and counts["A"] >= 2: eligible_side = "B"
		var changed: bool = counts != state.get("last_counts", counts)
		if eligible_side != "" and (not bool(state.get("awaiting_change", false)) or changed):
			var lone_slot := _only_alive_slot(teams[eligible_side])
			state["active"] = true
			state["lone_side"] = eligible_side
			state["lone_slot"] = lone_slot
			state["start_tick"] = tick
			state["awaiting_change"] = false
			countdowns["vc20_window_ticks_remaining"] = 50
		state["last_counts"] = counts.duplicate()

	for event in departures:
		if int(event["tick"]) <= tick and not processed.has(event["event_id"]): processed.append(event["event_id"])
	state["processed_event_ids"] = processed
	mem["vc20"] = state


static func _only_alive_slot(units: Array) -> int:
	for unit in units:
		if _alive(unit): return int(unit["slot"])
	return 0


static func _deadline(rule_id: String) -> int:
	return int(BATTLE_TICKS.get(rule_id, DEFAULT_BATTLE_TICKS))


static func _deadline_comparison(rule_id: String, teams: Dictionary, mem: Dictionary) -> Array:
	var result: Array = []
	var locks: Dictionary = mem["locks"]
	match rule_id:
		"VC01", "VC03", "VC04", "VC16", "VC19", "VC20", "VC22":
			return _standard_score(teams)
		"VC02":
			for side in SIDES: result.append(_ratio_score("%s 最低健康" % side, _minimum_health(teams[side]), true))
			result.append_array(_standard_health_score(teams))
		"VC05":
			for side in SIDES: result.append(_ratio_score("%s 最高健康" % side, _maximum_health(teams[side]), true))
			result.append_array(_standard_health_score(teams))
		"VC06":
			for side in SIDES: result.append(_ratio_score("%s 第二低健康" % side, _kth_health(teams[side], 1), true))
			result.append_array(_standard_health_score(teams))
		"VC07", "VC08", "VC09", "VC10", "VC11":
			var key: String = {"VC07":"flag", "VC08":"fire", "VC09":"cannon", "VC10":"weak", "VC11":"bastion"}[rule_id]
			for side in SIDES:
				var slot: int = int(locks[side].get(key, 0))
				result.append(_ratio_score("%s 关键目标健康" % side, _health_by_slot(teams[side], slot), true))
			result.append_array(_standard_health_score(teams))
		"VC12":
			var core_counts: Dictionary = {}
			var core_sums: Dictionary = {}
			for side in SIDES:
				var cores: Array = locks[side].get("cores", [])
				var count := 0
				var sum := {"n":0,"d":1}
				for slot in cores:
					if _alive(teams[side][int(slot) - 1]): count += 1
					sum = _safe_add_or_empty(sum, _health(teams[side][int(slot) - 1]))
				core_counts[side] = count
				core_sums[side] = sum
			result.append(_int_score("A 双核存活数", core_counts["A"], true))
			result.append(_int_score("B 双核存活数", core_counts["B"], true))
			result.append(_ratio_score("A 双核健康和", core_sums["A"], true))
			result.append(_ratio_score("B 双核健康和", core_sums["B"], true))
		"VC13":
			for side in SIDES: result.append(_int_score("%s 旗手存活" % side, 1 if _alive_by_slot(teams[side], int(locks[side].get("flag", 0))) else 0, true))
			result.append_array(_standard_score(teams))
		"VC14":
			var a_attacked: bool = int(locks["A"].get("first_attacker", 0)) > 0
			var b_attacked: bool = int(locks["B"].get("first_attacker", 0)) > 0
			if not a_attacked and not b_attacked: return _standard_score(teams)
			if a_attacked != b_attacked:
				result.append(_int_score("A 完成过自然普攻", 1 if a_attacked else 0, true))
				result.append(_int_score("B 完成过自然普攻", 1 if b_attacked else 0, true))
			else:
				result.append(_ratio_score("A 先手旗手健康", _health_by_slot(teams["A"], int(locks["A"]["first_attacker"])), true))
				result.append(_ratio_score("B 先手旗手健康", _health_by_slot(teams["B"], int(locks["B"]["first_attacker"])), true))
		"VC17":
			for side in SIDES:
				var slot: int = int(locks[side].get("flag", 0))
				result.append(_ratio_score("%s 旗手健康" % side, _health_by_slot(teams[side], slot), true))
		"VC15":
			result.append_array(_standard_health_score(teams))
		"VC18":
			for side in SIDES: result.append(_int_score("%s 严格健康领先对位数" % side, _winning_lanes(teams, side, true), true))
			result.append_array(_standard_health_score(teams))
		"VC21":
			result.append_array(_standard_health_score(teams))
			for side in SIDES: result.append(_int_score("%s 存活人数" % side, _alive_count(teams[side]), true))
		"VC23":
			for side in SIDES: result.append(_int_score("%s 存活人数" % side, _alive_count(teams[side]), true))
			for side in SIDES: result.append(_ratio_score("%s 存活者最低健康" % side, _minimum_alive_health(teams[side]), true))
			result.append_array(_standard_health_score(teams))
		"VC24":
			var a_pair: bool = _alive_count(teams["A"]) >= 2
			var b_pair: bool = _alive_count(teams["B"]) >= 2
			result.append(_int_score("A 至少两人存活", 1 if a_pair else 0, true))
			result.append(_int_score("B 至少两人存活", 1 if b_pair else 0, true))
			if a_pair and b_pair:
				result.append(_ratio_score("A 最高两人健康和", _top_two_sum(teams["A"]), true))
				result.append(_ratio_score("B 最高两人健康和", _top_two_sum(teams["B"]), true))
			else:
				result.append(_int_score("A 标准存活人数", _alive_count(teams["A"]), true))
				result.append(_int_score("B 标准存活人数", _alive_count(teams["B"]), true))
				result.append_array(_standard_health_score(teams))
		"VC25":
			for side in SIDES: result.append(_ratio_score("%s 最高健康" % side, _maximum_health(teams[side]), true))
			result.append_array(_standard_score(teams))
		"VC26":
			for side in SIDES: result.append(_ratio_score("%s 最低健康" % side, _minimum_health(teams[side]), true))
			result.append_array(_standard_health_score(teams))
		"VC27":
			for side in SIDES: result.append(_ratio_score("%s 敌方最低两人健康和（低者胜）" % side, _lowest_two_sum(teams[_other(side)]), false))
			result.append_array(_standard_score(teams))
		"VC28":
			for side in SIDES: result.append(_int_score("%s 敌方全员健康<75%%" % side, 1 if _all_health_less_than(teams[_other(side)], 3, 4) else 0, true))
			result.append_array(_standard_health_score(teams))
		"VC29":
			var a_flag: int = int(locks["A"].get("flag", 0))
			var b_flag: int = int(locks["B"].get("flag", 0))
			var a_flag_alive: bool = _alive_by_slot(teams["A"], a_flag)
			var b_flag_alive: bool = _alive_by_slot(teams["B"], b_flag)
			result.append(_int_score("A 旗手存活", 1 if a_flag_alive else 0, true))
			result.append(_int_score("B 旗手存活", 1 if b_flag_alive else 0, true))
			if a_flag_alive and b_flag_alive:
				result.append(_ratio_score("A 旗手+另一最高队友健康", _flag_plus_best_ally(teams["A"], a_flag), true))
				result.append(_ratio_score("B 旗手+另一最高队友健康", _flag_plus_best_ally(teams["B"], b_flag), true))
			else:
				result.append(_int_score("A 标准存活人数", _alive_count(teams["A"]), true))
				result.append(_int_score("B 标准存活人数", _alive_count(teams["B"]), true))
				result.append_array(_standard_health_score(teams))
		"VC30":
			for side in SIDES: result.append(_int_score("%s 敌方健康>50%%人数（少者胜）" % side, _count_health_greater(teams[_other(side)], 1, 2), false))
			result.append_array(_standard_score(teams))
	return result


static func _standard_score(teams: Dictionary) -> Array:
	var result: Array = []
	for side in SIDES: result.append(_int_score("%s 存活人数" % side, _alive_count(teams[side]), true))
	result.append_array(_standard_health_score(teams))
	return result


static func _standard_health_score(teams: Dictionary) -> Array:
	return [_ratio_score("A 整队健康和", _sum_health(teams["A"]), true), _ratio_score("B 整队健康和", _sum_health(teams["B"]), true)]


static func _minimum_health(units: Array) -> Dictionary:
	var best := _health(units[0])
	for i in [1, 2]:
		var candidate := _health(units[i])
		if _ratio_compare(candidate, best) < 0: best = candidate
	return best


static func _minimum_alive_health(units: Array) -> Dictionary:
	var found := false
	var best := {"n":0,"d":1}
	for unit in units:
		if not _alive(unit): continue
		var candidate := _health(unit)
		if not found or _ratio_compare(candidate, best) < 0: best = candidate
		found = true
	return best


static func _maximum_health(units: Array) -> Dictionary:
	var best := _health(units[0])
	for i in [1, 2]:
		var candidate := _health(units[i])
		if _ratio_compare(candidate, best) > 0: best = candidate
	return best


static func _kth_health(units: Array, zero_index: int) -> Dictionary:
	var healths: Array = []
	for unit in units: healths.append(_health(unit))
	healths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _ratio_compare(a, b) < 0)
	return healths[zero_index]


static func _top_two_sum(units: Array) -> Dictionary:
	var healths: Array = []
	for unit in units: healths.append(_health(unit))
	healths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _ratio_compare(a, b) > 0)
	return _safe_add_or_empty(healths[0], healths[1])


static func _lowest_two_sum(units: Array) -> Dictionary:
	var healths: Array = []
	for unit in units: healths.append(_health(unit))
	healths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _ratio_compare(a, b) < 0)
	return _safe_add_or_empty(healths[0], healths[1])


static func _flag_plus_best_ally(units: Array, flag: int) -> Dictionary:
	var sum := _health(units[flag - 1])
	var best_slot := 0
	for unit in units:
		if int(unit["slot"]) == flag: continue
		if best_slot == 0 or _ratio_compare(_health(unit), _health(units[best_slot - 1])) > 0: best_slot = int(unit["slot"])
	return _safe_add_or_empty(sum, _health(units[best_slot - 1]))


static func _health_by_slot(units: Array, slot: int) -> Dictionary:
	return _health(units[slot - 1]) if slot >= 1 and slot <= 3 else {"n":0,"d":1}


static func _alive_by_slot(units: Array, slot: int) -> bool:
	return slot >= 1 and slot <= 3 and _alive(units[slot - 1])


static func _all_health_less_than(units: Array, numerator: int, denominator: int) -> bool:
	for unit in units:
		if _ratio_compare(_health(unit), {"n":numerator,"d":denominator}) >= 0: return false
	return true


static func _count_health_greater(units: Array, numerator: int, denominator: int) -> int:
	var count := 0
	for unit in units:
		if _health_greater(unit, numerator, denominator): count += 1
	return count


static func _safe_add_or_empty(a: Dictionary, b: Dictionary) -> Dictionary:
	return _add_rational(a, b)


static func _int_score(label: String, value: int, higher: bool) -> Dictionary:
	return {"kind":"int", "value":value, "higher":higher, "label":label}


static func _ratio_score(label: String, value: Dictionary, higher: bool) -> Dictionary:
	return {"kind":"ratio", "value":value, "higher":higher, "label":label}


static func _base_result(rule_id: String, tick: int, mem: Dictionary, claims: Dictionary,
		reasons: Dictionary, countdowns: Dictionary, teams: Dictionary) -> Dictionary:
	var winner = null
	var reason := ""
	if claims["A"] and claims["B"]:
		winner = "draw"
		reason = "同一结算tick双方均有胜利claim，判平局；A：%s；B：%s" % [reasons["A"], reasons["B"]]
	elif claims["A"] or claims["B"]:
		winner = "A" if claims["A"] else "B"
		reason = "%s胜：%s" % [winner, reasons[winner]]
	var health_snapshot := _health_snapshot(teams)
	if winner != null: reason += "；" + _health_snapshot_text(health_snapshot) + "；" + _locked_target_text(rule_id, mem["locks"])
	return {"rule_id":rule_id, "tick":tick, "claims":claims.duplicate(),
		"claim_reasons":reasons.duplicate(), "winner":winner, "reason":reason,
		"countdowns":countdowns.duplicate(true), "health_snapshot":health_snapshot,
		"locked_targets":mem["locks"].duplicate(true),
		"memory":mem.duplicate(true), "terminal":winner != null}


static func _resolve_comparison(rule_id: String, tick: int, mem: Dictionary, claims: Dictionary,
		reasons: Dictionary, countdowns: Dictionary, scores: Array, teams: Dictionary) -> Dictionary:
	var base := _base_result(rule_id, tick, mem, claims, reasons, countdowns, teams)
	if base["winner"] != null: return base
	var comparison := _compare_score_sides(scores)
	if comparison == 0:
		base["winner"] = "draw"
		base["reason"] = "到期比较完全相同，平局；" + _score_summary(scores)
	else:
		base["winner"] = "A" if comparison > 0 else "B"
		base["reason"] = "到期比较：%s胜；%s" % [base["winner"], _score_summary(scores)]
	base["reason"] += "；" + _health_snapshot_text(base["health_snapshot"]) + "；" + _locked_target_text(rule_id, mem["locks"])
	base["terminal"] = true
	base["timeout"] = true
	return base


static func _compare_score_sides(scores: Array) -> int:
	# Each metric appears as adjacent A/B entries. The first differing metric decides.
	var i := 0
	while i + 1 < scores.size():
		var a: Dictionary = scores[i]
		var b: Dictionary = scores[i + 1]
		var cmp := 0
		if a["kind"] == "int":
			var av: int = a["value"]
			var bv: int = b["value"]
			if av > bv: cmp = 1
			elif av < bv: cmp = -1
		else: cmp = _ratio_compare(a["value"], b["value"])
		if not bool(a["higher"]): cmp = -cmp
		if cmp != 0: return cmp
		i += 2
	return 0


static func _score_summary(scores: Array) -> String:
	var parts: PackedStringArray = []
	var i := 0
	while i + 1 < scores.size():
		parts.append("%s=%s, %s=%s" % [scores[i]["label"], _score_value(scores[i]), scores[i + 1]["label"], _score_value(scores[i + 1])])
		i += 2
	return "; ".join(parts)


static func _score_value(score: Dictionary) -> String:
	if score["kind"] == "int": return str(score["value"])
	var value: Dictionary = score["value"]
	return "%d/%d" % [value.get("n", 0), value.get("d", 1)]


static func _health_snapshot(teams: Dictionary) -> Dictionary:
	var result := {"A": [], "B": []}
	for side in SIDES:
		for unit in teams[side]:
			var current: int = 0 if bool(unit["final_departed"]) else mini(int(unit["hp_tenths"]), int(unit["initial_max_hp_tenths"]))
			result[side].append({"slot":int(unit["slot"]), "hp_tenths":current,
				"initial_max_hp_tenths":int(unit["initial_max_hp_tenths"]), "health":_health(unit),
				"final_departed":bool(unit["final_departed"]), "alive":_alive(unit)})
	return result


static func _health_snapshot_text(snapshot: Dictionary) -> String:
	var parts: PackedStringArray = []
	for side in SIDES:
		for unit in snapshot[side]:
			parts.append("%s%d=%d/%d(h=%d/%d%s)" % [side, unit["slot"], unit["hp_tenths"],
				unit["initial_max_hp_tenths"], unit["health"]["n"], unit["health"]["d"],
				" final_departed" if unit["final_departed"] else ""])
	return "剩余生命：" + ", ".join(parts)


static func _locked_target_text(rule_id: String, locks: Dictionary) -> String:
	var targets: Array[String] = []
	var fields: Array = []
	match rule_id:
		"VC07", "VC13", "VC17", "VC29": fields = ["flag"]
		"VC08": fields = ["fire"]
		"VC09": fields = ["cannon"]
		"VC10": fields = ["weak"]
		"VC11": fields = ["bastion"]
		"VC12": fields = ["cores"]
		"VC14": fields = ["first_attacker"]
	for side in SIDES:
		for field in fields:
			var value = locks[side].get(field, 0)
			if field == "cores": targets.append("%s双核=slot%s" % [side, str(value)])
			elif int(value) > 0: targets.append("%s%s=slot%d" % [side, field, int(value)])
			else: targets.append("%s%s=尚未产生" % [side, field])
	return "锁定目标：" + (", ".join(targets) if not targets.is_empty() else "本规则无关键目标")


static func _set_claim(claims: Dictionary, reasons: Dictionary, side: String, reason: String) -> void:
	claims[side] = true
	if reasons[side] == "": reasons[side] = reason
	elif not str(reasons[side]).contains(reason): reasons[side] = str(reasons[side]) + "；" + reason


static func _other(side: String) -> String:
	return "B" if side == "A" else "A"


static func _known_rule(rule_id: String) -> bool:
	if not rule_id.begins_with("VC"): return false
	var number: int = int(rule_id.substr(2))
	return number >= 1 and number <= 30 and rule_id == ("VC%02d" % number)


static func _error_result(message: String, memory: Dictionary) -> Dictionary:
	return {"error":message, "claims":{"A":false,"B":false}, "winner":null,
		"reason":"", "countdowns":{}, "memory":memory.duplicate(true), "terminal":false}
