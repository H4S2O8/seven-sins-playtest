class_name SinTableAI
extends RefCounted

## Production opponent: input is a side-scoped Observation, never a Session.
## All counterfactual teams are drawn from an explicit public catalogue. They are
## stable within a hand, so changing an offered card cannot secretly change the test.
const Assembler = preload("res://content/battle_assembler.gd")
const Battle = preload("res://core/battle/battle_engine.gd")
const Command = preload("res://core/types/command.gd")
var assembler = Assembler.new()
var integration_review := false
var public_hypothesis_pool: Array = []
var hypothesis_count := 2
var cache: Dictionary = {}
var diagnostics: Dictionary = {}
var cancelled := false

func _init(review := false, public_test_pool: Array = []) -> void:
	integration_review = review
	public_hypothesis_pool = public_test_pool.duplicate() if review and not public_test_pool.is_empty() else assembler.characters.keys()
	public_hypothesis_pool.sort()

func cancel() -> void:
	cancelled = true

func choose(observation: Dictionary, actions: Array, seed: int, style := "cautious", tree: SceneTree = null) -> Dictionary:
	cancelled = false
	diagnostics = {"simulations":0,"cache_hits":0,"covered_handler_ids":[],"hidden_enemy_read":false,"error":""}
	if str(observation.get("side", "")) not in ["player","opponent"] or actions.is_empty(): return _fail("no_legal_decision")
	if style not in ["cautious","aggressive","bluff"]: return _fail("unknown_ai_style")
	var clean := _visible_only(observation)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ (int(clean.revision) * 7349)
	var hypotheses := _hypotheses(clean,seed)
	if hypotheses.is_empty(): return _fail("no_public_hypotheses")
	var candidates := _candidates(clean,actions)
	if candidates.is_empty(): return _fail("no_concrete_candidates")
	var phase := str(clean.phase)
	var baseline := 0.5
	if phase not in ["SETTLED","DRAFT_SELECTION"]:
		var estimate := await _estimate(clean,{},hypotheses,seed,tree)
		if not str(estimate.error).is_empty(): return _fail(str(estimate.error))
		baseline = float(estimate.score)
	var best_score := -INF
	var best: Dictionary = {}
	var pe_delta := 0.0
	if phase in ["PUBLIC_COMMIT","PUBLIC_BID"]:
		var enabled := await _estimate(clean,{"activate":true},hypotheses,seed,tree)
		var disabled := await _estimate(clean,{"activate":false},hypotheses,seed,tree)
		if not str(enabled.error).is_empty(): return _fail(str(enabled.error))
		if not str(disabled.error).is_empty(): return _fail(str(disabled.error))
		pe_delta = float(enabled.score) - float(disabled.score)
	for candidate: Dictionary in candidates:
		if cancelled: return _fail("ai_cancelled")
		var score := 0.0
		var kind := str(candidate.type)
		if phase == "DRAFT_SELECTION":
			var result := await _estimate(clean,candidate.payload,hypotheses,seed,tree)
			if not str(result.error).is_empty(): return _fail(str(result.error))
			score = float(result.score)
		elif phase == "OPERATION_COMMIT":
			var operation := str(candidate.payload.get("operation", ""))
			if operation == "pass": score = baseline
			elif operation == "draw_card":
				# Unknown future offers are not sampled from the actual draft RNG.
				# Empty sockets increase option value; costly replacement has less value.
				var empty := 0
				for card in _six(clean.your_private.installed_cards):
					if str(card).is_empty(): empty += 1
				score = baseline + 0.028 + 0.018 * empty - _operation_cost(clean)
			else:
				var result := await _estimate(clean,candidate.payload,hypotheses,seed,tree)
				if not str(result.error).is_empty(): return _fail(str(result.error))
				score = float(result.score) - _operation_cost(clean)
		elif kind == "public_decision": score = pe_delta if bool(candidate.payload.activate) else -pe_delta
		elif kind == "public_bid":
			var own_want := bool(clean.public.get("public_commits", {}).get(clean.side, {}).get("activate", pe_delta > 0))
			var utility := pe_delta if own_want else -pe_delta
			var stack := _stack(clean)
			var cap := floori(stack * clampf(utility * 1.2,0.0,0.32))
			var amount := int(candidate.action.amount_min)
			candidate.payload.amount = amount
			score = utility - float(amount)/maxf(float(stack),1.0) * 0.45 if amount <= cap else -2.0
		elif kind == "pass_public_bid": score = 0.0
		elif phase == "BETTING":
			var valued := _bet_value(clean,candidate,baseline,style,rng)
			score = float(valued.score)
			candidate.payload = valued.payload
		else: score = 1.0 if kind == "next_hand" else 0.0
		# Tiny deterministic preference breaks real ties, never swamps real effects.
		score += rng.randf() * 0.00001
		if score > best_score:
			best_score = score
			best = candidate
	if best.is_empty(): return _fail("decision_empty")
	diagnostics["baseline"] = baseline
	diagnostics["public_effect_delta"] = pe_delta
	diagnostics["chosen_score"] = best_score
	diagnostics["hypotheses"] = hypotheses.duplicate(true)
	var command = Command.new("table-ai-%s-%d-%s" % [clean.side,int(clean.revision),str(hash(JSON.stringify(best.payload)))],
		str(clean.side),str(best.type),best.payload.duplicate(true),int(clean.revision))
	return {"error":"","command":command,"diagnostics":diagnostics.duplicate(true)}

func _visible_only(observed: Dictionary) -> Dictionary:
	# Explicit whitelist: even if a caller mistakenly adds Session/private fields,
	# candidate generation and cache keys do not receive them.
	var own: Dictionary = observed.get("your_private", {})
	var opponent: Dictionary = observed.get("opponent_public", {})
	return {"side":str(observed.get("side","")),"revision":int(observed.get("revision",-1)),
		"phase":str(observed.get("phase","")),"round":int(observed.get("round",0)),
		"your_private":{"team":own.get("team",[]).duplicate(true),"installed_cards":own.get("installed_cards",[]).duplicate(),
			"team_arrows":own.get("team_arrows",[1,2,3]).duplicate()},
		"opponent_public":{"installed_cards":opponent.get("installed_cards",[]).duplicate(),"arrows":opponent.get("arrows",[1,2,3]).duplicate()},
		"public":observed.get("public",{}).duplicate(true)}

func _hypotheses(observed: Dictionary, seed: int) -> Array:
	if public_hypothesis_pool.size() < 3: return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ (int(observed.public.get("hand_id",0))*3571)
	var teams: Array = []
	for n in range(hypothesis_count):
		var pool := public_hypothesis_pool.duplicate()
		var team: Array = []
		for slot in range(1,4):
			var selected := rng.randi_range(0,pool.size()-1)
			team.append({"slot":slot,"definition_id":str(pool[selected])})
			pool.remove_at(selected)
		teams.append(team)
	return teams

func _request(observed: Dictionary, change: Dictionary, hypothetical: Array, seed: int) -> Dictionary:
	var own_cards := _six(observed.your_private.installed_cards)
	var arrows: Array = observed.your_private.team_arrows.duplicate()
	if change.has("card_id"):
		var index := int(change.slot)-1 + (3 if str(change.slot_kind)=="effect" else 0)
		own_cards[index] = str(change.card_id)
	if change.get("operation", "") == "move_card":
		var offset := 3 if str(change.slot_kind)=="effect" else 0
		var a := int(change.from)-1+offset
		var b := int(change.to)-1+offset
		var old: Variant = own_cards[a]
		own_cards[a] = own_cards[b]
		own_cards[b] = old
	if change.has("arrows"): arrows = change.arrows.duplicate()
	var effects: Array = []
	for effect in observed.public.get("revealed_effects",[]):
		if effect is Dictionary and bool(effect.get("active",false)): effects.append(str(effect.id))
	var current := str(observed.public.get("current_public_effect",""))
	if change.has("activate") and not current.is_empty():
		effects.erase(current)
		if bool(change.activate): effects.append(current)
	return {"seed":seed,"rule_id":str(observed.public.get("rule_id","")),"arena_id":str(observed.public.get("arena_id","")),
		"public_effect_ids":effects,"teams":{"player":observed.your_private.team.duplicate(true),"opponent":hypothetical.duplicate(true)},
		"installed_cards":{"player":own_cards,"opponent":_six(observed.opponent_public.installed_cards)},
		"arrows":{"player":arrows,"opponent":observed.opponent_public.arrows.duplicate()}}

func _estimate(observed: Dictionary, change: Dictionary, hypotheses: Array, seed: int, tree: SceneTree) -> Dictionary:
	var total := 0.0
	for hypothetical: Array in hypotheses:
		var request := _request(observed,change,hypothetical,seed)
		var key := JSON.stringify(request,"",true)
		if cache.has(key):
			diagnostics.cache_hits += 1
			total += float(cache[key])
			continue
		var assembled: Dictionary = assembler.build(request,integration_review)
		if not str(assembled.error).is_empty(): return {"error":str(assembled.error)}
		var engine = Battle.new()
		var initialized: Dictionary = engine.setup(assembled.config,assembled.handlers,{"capture_tick_hashes":false})
		if not str(initialized.get("error","")).is_empty(): return {"error":str(initialized.error)}
		var result: Dictionary = {}
		var frame_start := Time.get_ticks_usec()
		var steps := 0
		while steps < 362:
			if cancelled: return {"error":"ai_cancelled"}
			result = engine.step(false)
			steps += 1
			if not str(result.get("error","")).is_empty(): return {"error":str(result.error)}
			if bool(result.terminal): break
			if tree != null and Time.get_ticks_usec()-frame_start >= 5000:
				await tree.process_frame
				frame_start = Time.get_ticks_usec()
		if not bool(result.get("terminal",false)): return {"error":"ai_battle_not_terminal"}
		var score := 0.45
		if str(result.get("winner","")) == "A": score = 0.84
		elif str(result.get("winner","")) == "B": score = 0.06
		var margin := 0.0
		for side in ["A","B"]:
			for unit: Dictionary in engine.units(side,false):
				var health := clampf(float(unit.hp_tenths)/maxf(1.0,float(unit.initial_max_hp_tenths)),0.0,1.0)
				margin += health if side=="A" else -health
		score += 0.05 + margin/3.0*0.05
		cache[key] = score
		if cache.size()>256: cache.erase(cache.keys()[0])
		total += score
		diagnostics.simulations += 1
		for id in assembled.get("content_ids",[]):
			if not diagnostics.covered_handler_ids.has(id): diagnostics.covered_handler_ids.append(id)
		if tree != null: await tree.process_frame
	return {"error":"","score":total/maxf(1.0,hypotheses.size())}

func _candidates(observed: Dictionary, actions: Array) -> Array:
	var rows: Array = []
	for action: Dictionary in actions:
		var kind := str(action.get("type",""))
		if action.has("amount_min") and int(action.get("amount_max",0)) < int(action.amount_min): continue
		if kind=="fold" and str(observed.phase) in ["DRAFT_SELECTION","OPERATION_COMMIT","PUBLIC_COMMIT","PUBLIC_BID"]: continue
		if kind=="choose_draft_card":
			for card in action.get("offer",[]):
				for slot in action.get("external_slots",[1,2,3]):
					rows.append(_row(action,{"card_id":card,"slot":slot,"slot_kind":"equipment" if str(card).begins_with("EQ") else "effect"}))
		elif kind=="commit_operation":
			var operation := str(action.operation)
			if operation=="set_arrows":
				for arrows in [[1,1,1],[2,2,2],[3,3,3],[1,2,3],[3,2,1]]:
					if arrows != observed.your_private.team_arrows: rows.append(_row(action,{"operation":operation,"arrows":arrows}))
			elif operation=="move_card":
				var cards := _six(observed.your_private.installed_cards)
				for offset in [0,3]:
					for a in range(3):
						if str(cards[a+offset]).is_empty(): continue
						for b in range(3):
							if a==b or cards[a+offset]==cards[b+offset]: continue
							rows.append(_row(action,{"operation":operation,"slot_kind":"equipment" if offset==0 else "effect","from":a+1,"to":b+1}))
			else: rows.append(_row(action,{"operation":operation}))
		elif kind=="public_decision": rows.append(_row(action,{"activate":bool(action.activate)}))
		else: rows.append(_row(action,{}))
	return rows

func _bet_value(observed: Dictionary, candidate: Dictionary, baseline: float, style: String, rng: RandomNumberGenerator) -> Dictionary:
	var stack := _stack(observed)
	var pot := int(observed.public.get("balances",{}).get("pot",0))
	var own_paid := int(observed.public.get("round_paid",{}).get(observed.side,0))
	var target := int(observed.public.get("target_bid",0))
	var owed := mini(stack,maxi(0,target-own_paid))
	# Two hypotheses are not certainty. Keep estimates away from 0/1 and make
	# bluffing infrequent, seeded and affordable rather than an always-all-in style.
	var confidence := clampf(0.5+(baseline-0.5)*0.78,0.12,0.88)
	var bluff := style=="bluff" and rng.randf()<0.13
	var initiative := 0.07 if style=="aggressive" else 0.0
	var kind := str(candidate.type)
	var score := -10.0
	var payload := {}
	match kind:
		"fold": score = 0.0 if owed>0 else -1.0
		"check": score = 0.025
		"call":
			payload = {"amount":owed,"all_in":bool(candidate.action.get("short_stack_all_in",false))}
			score = (confidence*(pot+owed)-owed)/maxf(10.0,pot+owed) + initiative
		"bet", "raise":
			var low := int(candidate.action.amount_min)
			var high := int(candidate.action.amount_max)
			var spend_cap := maxi(5,floori(stack*(0.24 if style=="cautious" else 0.4)))
			var desired := maxi(low,own_paid+maxi(5,roundi((pot+5)*(0.22+confidence*0.45))))
			var amount := mini(high,mini(desired,own_paid+spend_cap))
			payload = {"amount":clampi(amount,low,high)}
			if amount>=low and (confidence>0.53 or bluff):
				score = confidence-0.49+initiative+(0.25 if bluff else 0.0)-float(maxi(0,amount-own_paid))/maxf(1.0,stack)*0.14
		"all_in":
			score = confidence-0.69 if confidence>0.74 or (stack<=5 and confidence>0.35) else -3.0
	return {"score":score,"payload":payload}

func _operation_cost(observed: Dictionary) -> float:
	var price := int(observed.public.get("target_bid",0))
	var pot := int(observed.public.get("balances",{}).get("pot",0))
	return float(price)/maxf(20.0,float(pot+_stack(observed)))*0.45

func _stack(observed: Dictionary) -> int:
	return int(observed.public.get("balances",{}).get(str(observed.side)+"_table",0))

func _six(cards: Array) -> Array:
	var result := cards.duplicate()
	while result.size()<6: result.append("")
	return result

func _row(action: Dictionary,payload: Dictionary) -> Dictionary:
	return {"type":str(action.type),"action":action.duplicate(true),"payload":payload}

func _fail(error: String) -> Dictionary:
	diagnostics.error = error
	return {"error":error,"command":null,"diagnostics":diagnostics.duplicate(true)}
