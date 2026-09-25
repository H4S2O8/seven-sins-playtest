extends SceneTree

const AI = preload("res://core/ai/program_ai.gd")
const Evaluator = preload("res://core/ai/battle_evaluator.gd")
const LegalActions = preload("res://core/legal_actions/legal_actions.gd")
const Battle = preload("res://core/battle/battle_engine.gd")
const Session = preload("res://core/session/session.gd")

var checks := 0
var failures: Array[String] = []
var adapter_calls := 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_legal_command_boundary()
	_test_determinism_and_hidden_team_independence()
	_test_style_and_amount_diversity()
	_test_risk_and_session_command()
	_test_real_battle_adapter()
	if failures.is_empty():
		print("PASS: %d AI assertions; observation-only decisions, legal commands, deterministic styles, real BattleEngine adapter (%d simulations; %d covered handlers; not full 298)" % [checks, adapter_calls, 0])
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("FAIL: %d/%d AI assertions failed" % [failures.size(), checks])
		quit(1)


func _test_legal_command_boundary() -> void:
	var observation := _observation("BETTING")
	var actions := LegalActions.list_actions(observation)
	for style in ["cautious", "aggressive", "bluff"]:
		var command = AI.choose(observation, actions, 419, style)
		_expect(command != null, "%s yields a command" % style)
		_expect(_command_matches_legal_action(command, actions), "%s command is a LegalActions member" % style)
	var draft_observation := _observation("DRAFT_SELECTION")
	draft_observation.your_private.private_offer = ["EQ07", "FX11"]
	draft_observation.your_private.offer_id = "offer-fixed"
	var draft_actions := LegalActions.list_actions(draft_observation)
	var draft_command = AI.choose(draft_observation, draft_actions, 91, "bluff")
	_expect(draft_command != null and draft_command.type == "choose_draft_card", "draft creates a concrete choose command")
	_expect(draft_command != null and ["EQ07", "FX11"].has(str(draft_command.payload.get("card_id", ""))), "draft card is in the private legal offer")
	_expect(draft_command != null and int(draft_command.payload.get("slot", 0)) in [1, 2, 3], "draft slot is legal")
	_expect(draft_command != null and ((str(draft_command.payload.card_id).begins_with("EQ") and draft_command.payload.slot_kind == "equipment") or
		(str(draft_command.payload.card_id).begins_with("FX") and draft_command.payload.slot_kind == "effect")), "draft slot-kind follows the card ID")
	_expect(AI.choose(observation, [], 1) == null, "empty legal set refuses to invent an action")
	_expect(AI.choose({}, actions, 1) == null, "missing side-scoped observation refuses to act")


func _test_determinism_and_hidden_team_independence() -> void:
	var observation := _observation("BETTING")
	var actions := LegalActions.list_actions(observation)
	var first = AI.choose(observation, actions, 991, "bluff")
	var repeated = AI.choose(observation, actions, 991, "bluff")
	_expect(first.fingerprint() == repeated.fingerprint(), "same observation/style/seed reproduces exact Command")
	var altered := observation.duplicate(true)
	altered.opponent_public.team_sealed = false
	altered.opponent_public.team = [{"definition_id":"FIXTURE_SECRET"}]
	altered.opponent_public.arrows = [3, 2, 1]
	altered.opponent_public.installed_cards = ["EQ01"]
	var under_altered_hidden_team = AI.choose(altered, actions, 991, "bluff")
	_expect(first.fingerprint() == under_altered_hidden_team.fingerprint(), "hidden actual opponent changes do not affect AI decision")


func _test_style_and_amount_diversity() -> void:
	var observation := _observation("BETTING")
	var actions: Array[Dictionary] = [
		{"type":"check","amount_min":0,"amount_max":0},
		{"type":"bet","amount_min":5,"amount_max":100},
		{"type":"all_in","amount_min":100,"amount_max":100},
		{"type":"fold"}
	]
	var cautious = AI.choose(observation, actions, 55, "cautious")
	_expect(cautious.type == "check", "cautious strategy prefers low-risk check over unsolicited all-in")
	var distinct: Dictionary = {}
	for seed_value in range(1, 101):
		var command = AI.choose(observation, actions, seed_value, "aggressive")
		distinct[command.type + ":" + str(command.payload.get("amount", 0))] = true
	_expect(distinct.size() >= 2, "aggressive seeded decisions vary across legal actions/amounts")
	_expect(not distinct.has("all_in:100") or distinct.size() > 3, "all-in is not the strategy's fixed output")
	var limited := [{"type":"bet","amount_min":7,"amount_max":19}]
	for seed_value in range(1, 20):
		var command = AI.choose(observation, limited, seed_value, "bluff")
		_expect(int(command.payload.amount) >= 7 and int(command.payload.amount) <= 19, "seeded bluff amount remains inside legal bounds")


func _test_risk_and_session_command() -> void:
	var observation := _observation("BETTING")
	var high_cost := [{"type":"call","amount_min":90,"amount_max":90},{"type":"fold"}]
	observation.public.balances.pot = 5
	observation.public.target_bid = 95
	observation.public.round_paid.player = 5
	var cautious_pass = AI.choose(observation, high_cost, 3, "cautious")
	_expect(cautious_pass.type == "fold", "cautious style folds a poor-pot-odds expensive call")
	var favorable_odds := [{"type":"call","amount_min":5,"amount_max":5},{"type":"fold"}]
	observation.public.balances.pot = 50
	observation.public.target_bid = 10
	observation.public.round_paid.player = 5
	var cautious_call = AI.choose(observation, favorable_odds, 3, "cautious")
	_expect(cautious_call.type == "call", "cautious style calls when pot odds are favorable")
	var session = Session.new({"seed":17,"first_actor":"player","ante":0,"player_table":100,"opponent_table":100})
	var live_observation: Dictionary = session.observation("player")
	var live_actions: Array[Dictionary] = LegalActions.list_actions(live_observation)
	var command = AI.choose(live_observation, live_actions, 17, "cautious")
	var result: Dictionary = session.apply(command)
	_expect(bool(result.get("accepted", false)), "a command from live Session observation/LegalActions is accepted")


func _test_real_battle_adapter() -> void:
	var candidates := [{"candidate_id":"base"},{"candidate_id":"variant"}]
	var hypotheses := [_team("B", 1)]
	var evaluation := Evaluator.evaluate_candidates(candidates, hypotheses, Callable(self, "_battle_adapter"), 2026)
	_expect(str(evaluation.get("error", "")).is_empty(), "adapter evaluation runs without errors")
	_expect(int(evaluation.get("simulation_count", 0)) == candidates.size() * hypotheses.size(), "every candidate/hypothesis is simulated")
	_expect(adapter_calls == candidates.size() * hypotheses.size(), "adapter callback invoked for each fixed sample")
	_expect(evaluation.get("coverage_is_complete_298", true) == false, "partial simulation never claims all 298 handlers")
	_expect(evaluation.get("covered_handler_ids", []).is_empty(), "coverage reports only handlers actually loaded")
	var failure := Evaluator.evaluate_candidates(candidates, hypotheses, Callable(), 1)
	_expect(not str(failure.get("error", "")).is_empty(), "missing engine adapter is an explicit error")
	var observation := _observation("DRAFT_SELECTION")
	observation.your_private.private_offer = ["EQ04"]
	var actions := LegalActions.list_actions(observation)
	var context := {
		"candidate_builder":Callable(self, "_draft_candidate_builder"),
		"battle_adapter":Callable(self, "_battle_adapter"),
		"hypothetical_opponents":hypotheses
	}
	var before := adapter_calls
	var selected = AI.choose(observation, actions, 32, "cautious", context)
	_expect(selected != null and selected.type == "choose_draft_card", "draft evaluation returns one legal selection")
	_expect(adapter_calls - before == 3, "draft candidates are evaluated against fixed hypothetical roster using real engine")


func _battle_adapter(candidate: Dictionary, hypothetical: Array, seed_value: int) -> Dictionary:
	adapter_calls += 1
	var engine = Battle.new()
	var own_team: Array = candidate.get("team", _team("A", 1))
	var result: Dictionary = engine.simulate({
		"seed":seed_value,"rule_id":"VC21","test_fixture":true,
		"teams":{"A":own_team,"B":hypothetical}
	})
	result["content_coverage"] = engine.state.get("content_coverage", {}).duplicate(true)
	return result


func _draft_candidate_builder(_observation: Dictionary, choice: Dictionary) -> Dictionary:
	var team := _team("A", 1)
	# This fixture changes only legal candidate stats to prove the adapter evaluates a candidate config;
	# production builders must install only handlers actually supported by their BattleEngine registry.
	if int(choice.slot) == 1:
		team[0].H += 1
	return {"team":team,"choice":choice.duplicate(true)}


func _observation(phase: String) -> Dictionary:
	return {
		"side":"player","revision":7,"phase":phase,"round":1,"acting_side":"player",
		"your_private":{"team":_team("A", 1),"private_offer":[],"offer_id":"","operation_commit":{},
			"draft_selection_submitted":false,"team_arrows":[1,2,3],"installed_cards":["","","","","", ""],"wallet":0},
		"opponent_public":{"team_sealed":true,"team":[],"arrows":[1,2,3],"installed_cards":[]},
		"public":{"balances":{"player_table":100,"opponent_table":100,"pot":10},"round_paid":{"player":5,"opponent":5},
			"target_bid":0,"public_bid":0,"room_over":false,"operation_commits":{},"public_commits":{}}
	}


func _team(side: String, health_bonus: int) -> Array:
	var result: Array = []
	for slot in range(1, 4):
		result.append({"slot":slot,"definition_id":"FIXTURE_%s%d" % [side, slot],"fixture":true,
			"H":10 + health_bonus,"A":1,"T_ticks":10,"R":0,"reach":"melee","armor_kind":"light"})
	return result


func _command_matches_legal_action(command, actions: Array) -> bool:
	if command == null: return false
	for action in actions:
		var expected := str(action.type)
		if expected == command.type:
			if expected in ["bet", "raise", "public_bid"]:
				var amount := int(command.payload.get("amount", -1))
				if amount < int(action.get("amount_min", 0)) or amount > int(action.get("amount_max", -1)): continue
			return true
		if expected == "commit_operation" and command.type == expected and str(command.payload.get("operation", "")) == str(action.get("operation", "")):
			return true
		if expected == "public_decision" and command.type == expected and bool(command.payload.get("activate", false)) == bool(action.get("activate", false)):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
