class_name SinProgramAI
extends RefCounted

const Command = preload("res://core/types/command.gd")
const BattleEvaluator = preload("res://core/ai/battle_evaluator.gd")

const STYLES := ["cautious", "aggressive", "bluff"]

## Pure decision boundary: the AI receives only a side-scoped observation and its legal actions.
## If evaluation_context is supplied for draft choices, it must contain candidate_builder,
## battle_adapter, and a fixed hypothetical_opponents array.
static func choose(observation: Dictionary, legal_actions: Array, ai_seed: int,
	style: String = "cautious", evaluation_context: Dictionary = {}) -> SinCommand:
	var side := str(observation.get("side", ""))
	if side not in ["player", "opponent"] or legal_actions.is_empty() or style not in STYLES:
		return null
	var revision := int(observation.get("revision", -1))
	if revision < 0:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = ai_seed ^ (revision * 0x45D9F3B) ^ str(observation.get("phase", "")).hash()
	var candidates: Array[Dictionary] = []
	for action in legal_actions:
		if action is Dictionary and _action_is_well_formed(action):
			candidates.append(action.duplicate(true))
	if candidates.is_empty():
		return null
	var draft_choices := _draft_choices(candidates)
	if not draft_choices.is_empty():
		var draft_index := _choose_draft_index(observation, draft_choices, evaluation_context, ai_seed, style)
		if draft_index < 0:
			return null
		var selected: Dictionary = draft_choices[draft_index]
		return _command(observation, selected.action, selected.payload)
	var utilities: Array[float] = []
	var best := -INF
	for action in candidates:
		var score := _utility(observation, action, style)
		utilities.append(score)
		best = maxf(best, score)
	var eligible: Array[int] = []
	for index in range(candidates.size()):
		if utilities[index] >= best - 14.0:
			eligible.append(index)
	var selected_index := eligible[rng.randi_range(0, eligible.size() - 1)]
	var action: Dictionary = candidates[selected_index]
	return _command(observation, action, _payload_for(action, rng, style))


static func _action_is_well_formed(action: Dictionary) -> bool:
	var kind := str(action.get("type", ""))
	return kind in ["check", "bet", "call", "raise", "all_in", "fold", "commit_operation",
		"public_decision", "public_bid", "pass_public_bid", "choose_draft_card", "leave_table", "next_hand"]


static func _utility(observation: Dictionary, action: Dictionary, style: String) -> float:
	var kind := str(action.type)
	var phase := str(observation.get("phase", ""))
	var score := 35.0
	match kind:
		"check": score = 62.0
		"call": score = 51.0
		"bet": score = 59.0 if style == "aggressive" else (55.0 if style == "bluff" else 47.0)
		"raise": score = 65.0 if style == "aggressive" else (61.0 if style == "bluff" else 43.0)
		"all_in": score = 48.0 if style == "aggressive" else (53.0 if style == "bluff" else 24.0)
		"fold": score = 20.0
		"commit_operation": score = 49.0 if str(action.get("operation", "")) != "pass" else 44.0
		"public_decision": score = (53.0 if bool(action.get("activate", false)) else 50.0)
		"public_bid": score = 54.0 if style != "cautious" else 42.0
		"pass_public_bid": score = 51.0
		"leave_table": score = 48.0
		"next_hand": score = 55.0
	if phase == "BETTING" and kind in ["call", "raise", "all_in", "fold"]:
		var own_side := str(observation.get("side", ""))
		var own_paid := int(observation.get("public", {}).get("round_paid", {}).get(own_side, 0))
		var target := int(observation.get("public", {}).get("target_bid", 0))
		var pot := int(observation.get("public", {}).get("balances", {}).get("pot", 0))
		var amount := int(action.get("amount_min", 0))
		var risk_cost := maxi(amount - own_paid, 0) if kind != "all_in" else amount
		var pot_odds := float(pot) / float(maxi(pot + risk_cost, 1))
		if kind == "call":
			score = 39.0 + 30.0 * pot_odds
			if style == "aggressive": score += 4.0
			if style == "bluff": score += 2.0
			if style == "cautious" and pot_odds < 0.35: score -= 13.0
		if kind == "fold":
			score = 48.0 if target > own_paid else 5.0
			if style == "cautious" and target > own_paid: score += 5.0
		if risk_cost > pot + own_paid:
			score -= 8.0 if style == "cautious" else 2.0
	if style == "bluff" and kind in ["bet", "raise", "public_bid"]:
		score += 3.0
	return score


static func _payload_for(action: Dictionary, rng: RandomNumberGenerator, style: String) -> Dictionary:
	var kind := str(action.type)
	var payload: Dictionary = {}
	match kind:
		"bet", "raise", "public_bid":
			var low := int(action.get("amount_min", 0))
			var high := int(action.get("amount_max", low))
			if high < low: high = low
			var fraction := 0.32 if style == "cautious" else (0.68 if style == "aggressive" else rng.randf_range(0.2, 0.8))
			payload.amount = clampi(low + int(round(float(high - low) * fraction)), low, high)
		"commit_operation":
			payload = action.duplicate(true)
			payload.erase("type")
		"public_decision":
			payload = action.duplicate(true)
			payload.erase("type")
	return payload


static func _draft_choices(actions: Array[Dictionary]) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for action in actions:
		if str(action.get("type", "")) != "choose_draft_card": continue
		for card in action.get("offer", []):
			var card_id := str(card)
			var kind := "equipment" if card_id.begins_with("EQ") else ("effect" if card_id.begins_with("FX") else "")
			if kind.is_empty(): continue
			for slot in action.get("external_slots", [1, 2, 3]):
				if not slot is int or slot < 1 or slot > 3: continue
				choices.append({"action":action,"payload":{"card_id":card_id,"slot":int(slot),"slot_kind":kind}})
	return choices


static func _choose_draft_index(observation: Dictionary, choices: Array[Dictionary], context: Dictionary,
	seed_value: int, style: String) -> int:
	if choices.is_empty(): return -1
	if context.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value ^ int(observation.get("revision", 0))
		return rng.randi_range(0, choices.size() - 1)
	var builder: Callable = context.get("candidate_builder", Callable())
	var adapter: Callable = context.get("battle_adapter", Callable())
	var opponents: Array = context.get("hypothetical_opponents", [])
	if not builder.is_valid() or not adapter.is_valid() or opponents.is_empty(): return -1
	var candidates: Array = []
	for choice in choices:
		var candidate: Variant = builder.call(observation.duplicate(true), choice.payload.duplicate(true))
		if not candidate is Dictionary: return -1
		candidates.append(candidate)
	var evaluation := BattleEvaluator.evaluate_candidates(candidates, opponents, adapter, seed_value)
	if not str(evaluation.get("error", "")).is_empty(): return -1
	var scores: Array = evaluation.scores
	var best := -INF
	var best_indices: Array[int] = []
	for index in range(scores.size()):
		var score := float(scores[index])
		if score > best:
			best = score
			best_indices = [index]
		elif is_equal_approx(score, best):
			best_indices.append(index)
	var rng := RandomNumberGenerator.new()
	var style_salt := 11 if style == "cautious" else (29 if style == "aggressive" else 47)
	rng.seed = seed_value ^ (int(observation.get("revision", 0)) * style_salt)
	return best_indices[rng.randi_range(0, best_indices.size() - 1)]


static func _command(observation: Dictionary, action: Dictionary, payload: Dictionary) -> SinCommand:
	var kind := str(action.get("type", ""))
	var command_type := kind
	if kind == "pass_public_bid": command_type = "pass_public_bid"
	if kind == "choose_draft_card": command_type = "choose_draft_card"
	return Command.new("ai-%d-%s" % [int(observation.get("revision", 0)), str(hash(JSON.stringify(payload)))],
		str(observation.get("side", "")), command_type, payload, int(observation.get("revision", -1)))
