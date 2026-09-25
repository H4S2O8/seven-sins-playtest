class_name SinAppController
extends RefCounted

const SessionScript = preload("res://core/session/session.gd")
const CommandScript = preload("res://core/types/command.gd")
const LegalActionsScript = preload("res://core/legal_actions/legal_actions.gd")
const AssemblerScript = preload("res://content/battle_assembler.gd")
const BattleScript = preload("res://core/battle/battle_engine.gd")

var session: SinSession
var assembler: SinBattleAssembler
var integration_review := false
var last_battle: Dictionary = {}
var pending_battle_replay := false
var pending_replay_result: Dictionary = {}
var pending_replay_events: Array = []
var pending_initial_snapshot: Dictionary = {}
var battle_ready_observations: Dictionary = {}

func _init(p_session: SinSession = null, p_assembler: SinBattleAssembler = null,
	p_integration_review: bool = false) -> void:
	session = p_session
	assembler = p_assembler if p_assembler != null else AssemblerScript.new()
	integration_review = p_integration_review


func legal_actions(side: String) -> Array[Dictionary]:
	if session == null or pending_battle_replay: return []
	return LegalActionsScript.list_actions(session.observation(side))


## Commands enter through LegalActions, then Session. Battle settlement is deferred
## until finish_battle_replay has consumed the complete event sequence.
func submit(command: SinCommand) -> Dictionary:
	if session == null: return _error("session_missing")
	if command == null: return _error("command_missing")
	if pending_battle_replay: return _error("battle_replay_in_progress")
	if not _is_legal(command): return _error("command_not_in_legal_actions")
	var accepted: Dictionary = session.apply(command)
	if not bool(accepted.get("accepted", false)): return accepted
	var result := accepted.duplicate(true)
	if session.state.phase == "BATTLE_READY":
		var battle_result := resolve_battle()
		if not str(battle_result.get("error", "")).is_empty():
			result["battle_error"] = str(battle_result.error)
		else:
			result["battle_replay"] = battle_result.duplicate(true)
			result["battle_pending_replay"] = true
	return result


func resolve_battle() -> Dictionary:
	if session == null: return _error("session_missing")
	if session.state.phase != "BATTLE_READY": return _error("battle_not_ready")
	if pending_battle_replay: return _error("battle_replay_already_prepared")
	battle_ready_observations = {
		"player":session.observation("player"),
		"opponent":session.observation("opponent")}
	var assembled: Dictionary = assembler.build_from_session(session.state, integration_review)
	if not str(assembled.get("error", "")).is_empty():
		return _error("assembly_rejected:" + str(assembled.error))
	var engine = BattleScript.new()
	var simulated: Dictionary = engine.simulate(assembled.config, assembled.handlers)
	if not str(simulated.get("error", "")).is_empty():
		return _error("battle_simulation_failed:" + str(simulated.error))
	if not bool(simulated.get("terminal", false)):
		return _error("battle_simulation_not_terminal")
	var battle_winner: Variant = simulated.get("winner", null)
	var session_winner := "tie"
	if battle_winner != null and str(battle_winner) != "draw":
		if str(battle_winner) == "A": session_winner = "player"
		elif str(battle_winner) == "B": session_winner = "opponent"
		else: return _error("battle_winner_invalid:" + str(battle_winner))
	pending_battle_replay = true
	var result := simulated.duplicate(true)
	result["error"] = ""
	result["session_winner"] = session_winner
	pending_replay_result = result.duplicate(true)
	pending_replay_events = result.get("events", []).duplicate(true)
	pending_initial_snapshot = assembled.config.duplicate(true)
	return {"error":"","phase":"BATTLE_REPLAY","initial_snapshot":pending_initial_snapshot.duplicate(true),
		"events":pending_replay_events.duplicate(true),"event_count":pending_replay_events.size(),"terminal":true}


## Presentation calls this only after consuming all returned battle events. The actual
## Session ledger transfer/refund occurs here—never during precomputation.
func finish_battle_replay(consumed_event_count: int) -> Dictionary:
	if not pending_battle_replay or session == null or session.state.phase != "BATTLE_READY":
		return _error("no_completed_battle_replay")
	if consumed_event_count != pending_replay_events.size(): return _error("battle_replay_incomplete")
	var session_winner := str(pending_replay_result.get("session_winner", ""))
	var settled: Dictionary = session.settle_battle(session_winner)
	if not bool(settled.get("accepted", false)):
		return _error("settlement_failed:" + str(settled.get("reason", "unknown")))
	pending_battle_replay = false
	var completed_result := pending_replay_result.duplicate(true)
	completed_result["settlement"] = settled.duplicate(true)
	completed_result["events"].append_array(settled.get("events", []))
	last_battle = completed_result.duplicate(true)
	pending_replay_result.clear()
	pending_replay_events.clear()
	pending_initial_snapshot.clear()
	battle_ready_observations.clear()
	return {"accepted":true,"error":"","events":[],"battle_result":completed_result}


func acknowledge_battle_replay(consumed_event_count: int) -> Dictionary:
	return finish_battle_replay(consumed_event_count)


func pending_battle_replay_package() -> Dictionary:
	if not pending_battle_replay: return _error("no_pending_battle_replay")
	return {"error":"","phase":"BATTLE_REPLAY","initial_snapshot":pending_initial_snapshot.duplicate(true),
		"events":pending_replay_events.duplicate(true),"event_count":pending_replay_events.size(),"terminal":true}


## UI-facing state is always observed, never a private Session dictionary. During battle
## playback balances remain at the captured pre-battle values, while both teams are revealed.
func observation(side: String) -> Dictionary:
	if session == null: return {}
	if pending_battle_replay:
		if side not in ["player", "opponent"]: return {}
		var observed: Dictionary = battle_ready_observations[side].duplicate(true)
		observed["phase"] = "BATTLE_REPLAY"
		observed.public["battle_result"] = {}
		observed.public["teams_revealed"] = true
		var other := "opponent" if side == "player" else "player"
		var state_private: Dictionary = session.state.private
		observed.opponent_public["team_sealed"] = false
		observed.opponent_public["team"] = state_private.teams[other].duplicate(true)
		observed.opponent_public["arrows"] = session.state.arrows[other].duplicate(true)
		observed.opponent_public["installed_cards"] = session.state.installed_cards[other].duplicate(true)
		return observed
	return session.observation(side)


func _is_legal(command: SinCommand) -> bool:
	if command.actor not in ["player", "opponent"]: return false
	var actions: Array[Dictionary] = legal_actions(command.actor)
	for action in actions:
		if str(action.get("type", "")) != command.type: continue
		match command.type:
			"bet", "raise", "public_bid":
				var amount: Variant = command.payload.get("amount", null)
				if not amount is int: continue
				if int(amount) < int(action.get("amount_min", 0)) or int(amount) > int(action.get("amount_max", -1)): continue
			"call":
				var call_amount: Variant = command.payload.get("amount", action.get("amount_min", null))
				if not call_amount is int or int(call_amount) < int(action.get("amount_min", 0)) or int(call_amount) > int(action.get("amount_max", -1)): continue
				if bool(action.get("short_stack_all_in", false)) and not bool(command.payload.get("all_in", false)): continue
			"commit_operation":
				if str(command.payload.get("operation", "")) != str(action.get("operation", "")): continue
			"public_decision":
				if not command.payload.get("activate", null) is bool or bool(command.payload.activate) != bool(action.activate): continue
			"choose_draft_card":
				var card_id := str(command.payload.get("card_id", ""))
				var slot := int(command.payload.get("slot", 0))
				var kind := "equipment" if card_id.begins_with("EQ") else ("effect" if card_id.begins_with("FX") else "")
				if not action.get("offer", []).has(card_id) or slot not in [1, 2, 3] or kind.is_empty() or kind != str(command.payload.get("slot_kind", "")): continue
			"choose_character":
				if int(command.payload.get("slot", 0)) != int(action.get("slot", -1)): continue
				if not action.get("candidates", []).has(str(command.payload.get("character_id", ""))): continue
			"reroll_character":
				if int(command.payload.get("slot", 0)) != int(action.get("slot", -1)): continue
			"next_hand", "leave_table", "check", "fold", "all_in", "pass_public_bid":
				pass
			_:
				continue
		return true
	return false


func _error(message: String) -> Dictionary:
	return {"accepted":false,"error":message,"reason":message,"events":[]}
