class_name SinBattleEvaluator
extends RefCounted

## Candidate and opponent dictionaries are passed to a caller-owned adapter which must
## construct and run the real BattleEngine. No Session or hidden-opponent state is read here.
static func evaluate_candidates(candidates: Array, hypothetical_opponents: Array, battle_adapter: Callable, ai_seed: int) -> Dictionary:
	if candidates.is_empty() or hypothetical_opponents.is_empty():
		return {"error":"候选与固定假想队伍都必须非空"}
	if not battle_adapter.is_valid():
		return {"error":"需要BattleEngine适配器回调"}
	var scores: Array[float] = []
	var coverage_ids: Dictionary = {}
	var simulations := 0
	for candidate_index in range(candidates.size()):
		var wins := 0
		var draws := 0
		for opponent_index in range(hypothetical_opponents.size()):
			if not candidates[candidate_index] is Dictionary or not _legal_fixed_team(hypothetical_opponents[opponent_index]):
				return {"error":"候选配置必须为Dictionary，假想队伍必须是合法的三阵位固定队伍"}
			# Paired common seeds remove avoidable battle-RNG noise between candidates.
			var case_seed := _case_seed(ai_seed, opponent_index)
			var result: Variant = battle_adapter.call(candidates[candidate_index].duplicate(true),
				hypothetical_opponents[opponent_index].duplicate(true), case_seed)
			if not result is Dictionary or not str(result.get("error", "")).is_empty():
				return {"error":"BattleEngine适配器失败: %s" % str(result.get("error", "无结果"))}
			if not result.has("winner") or not bool(result.get("terminal", false)) or not result.has("content_coverage"):
				return {"error":"适配器必须返回真实模拟winner和content_coverage"}
			var own_side := str(candidates[candidate_index].get("ai_side", "A"))
			if str(result.get("winner", "")) == own_side: wins += 1
			elif result.get("winner", null) == null or str(result.get("winner", "")) == "draw": draws += 1
			var coverage: Variant = result.content_coverage
			if not coverage is Dictionary or not coverage.get("handler_ids", []) is Array:
				return {"error":"BattleEngine content_coverage格式无效"}
			for content_id in coverage.handler_ids:
				coverage_ids[str(content_id)] = true
			simulations += 1
		scores.append((float(wins) + float(draws) * 0.5) / float(hypothetical_opponents.size()))
	var covered_ids: Array = coverage_ids.keys()
	covered_ids.sort()
	return {"scores":scores,"simulation_count":simulations,"hypothetical_team_count":hypothetical_opponents.size(),
		"covered_handler_ids":covered_ids,"coverage_is_complete_298":false}


static func _case_seed(seed_value: int, opponent_index: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ (opponent_index * 0x119DE1F3)
	return int(rng.randi())


static func _legal_fixed_team(team: Variant) -> bool:
	if not team is Array or team.size() != 3: return false
	for index in range(3):
		var unit: Variant = team[index]
		if not unit is Dictionary: return false
		for field in ["slot", "definition_id", "H", "A", "T_ticks", "R", "reach", "armor_kind"]:
			if not unit.has(field): return false
		if int(unit.slot) != index + 1 or int(unit.H) <= 0 or int(unit.A) < 0 or int(unit.T_ticks) < 6 or int(unit.R) < 0:
			return false
		if str(unit.reach) not in ["melee", "ranged"] or str(unit.armor_kind) not in ["light", "medium", "heavy"]:
			return false
	return true
