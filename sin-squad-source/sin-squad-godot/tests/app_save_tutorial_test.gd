extends SceneTree

const SessionScript = preload("res://core/session/session.gd")
const CommandScript = preload("res://core/types/command.gd")
const ControllerScript = preload("res://core/app/app_controller.gd")
const ProfileControllerScript = preload("res://core/app/profile_controller.gd")
const SaveStoreScript = preload("res://core/save/save_store.gd")
const TutorialScript = preload("res://tutorial/tutorial_runner.gd")
const EnvironmentHandlersScript = preload("res://content/environment/environment_handlers.gd")

class FixedRosterSession extends SessionScript:
	func _sample_team(side: String) -> Array:
		var ids: Array = ["WR01", "WR02", "WR05"] if side == "player" else ["WR01", "WR04", "WR10"]
		var result: Array = []
		for index in range(ids.size()): result.append({"slot":index + 1,"definition_id":ids[index]})
		return result

class MirrorRosterSession extends SessionScript:
	func _sample_team(_side: String) -> Array:
		var ids: Array = ["WR01", "WR02", "WR05"]
		var result: Array = []
		for index in range(ids.size()): result.append({"slot":index + 1,"definition_id":ids[index]})
		return result

var checks := 0
var failures: Array[String] = []
var command_serial := 0
var environment_handlers = EnvironmentHandlersScript.new()

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_save_replay_safety()
	_test_profile_wallet_lifecycle()
	_test_profile_resume_battle()
	_test_default_formal_pool()
	_test_real_draw_settles_as_tie()
	_test_fold_does_not_reveal_or_replay()
	_test_full_session_flow()
	_test_tutorial_machine()
	if failures.is_empty():
		print("PASS: %d app/save/tutorial assertions; real Session→Assembler→BattleEngine→settlement, versioned data save, 35 event-gated tutorial steps" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("FAIL: %d/%d app/save/tutorial assertions failed" % [failures.size(), checks])
		quit(1)


func _test_save_replay_safety() -> void:
	var session = _new_session(104)
	var first_actor := str(session.state.acting_side)
	var other := "opponent" if first_actor == "player" else "player"
	var bet := _apply(session, first_actor, "bet", {"amount":10})
	_expect(bool(bet.accepted), "save fixture places real opening bet")
	var call := _apply(session, other, "call", {"amount":10})
	_expect(bool(call.accepted) and session.state.phase == "OPERATION_COMMIT", "save fixture reaches paid operation window")
	_expect(bool(_apply(session, "player", "commit_operation", {"operation":"draw_card"}).accepted), "player draw intent committed")
	_expect(bool(_apply(session, "opponent", "commit_operation", {"operation":"draw_card"}).accepted), "opponent draw intent commits and draws")
	_expect(session.state.phase == "DRAFT_SELECTION", "real paid draft is pending private choices")
	var saved_offer: Array = session.state.private.offers.player.duplicate(true)
	var saved_offer_id := str(session.state.private.offer_ids.player)
	var saved_rng_counter := int(session.rng_counter)
	var saved_draft: Dictionary = session.draft.snapshot()
	var saved_balances: Dictionary = session.ledger.balances.duplicate(true)
	var store = SaveStoreScript.new()
	var write := store.commit_session(session, "app_save_pending_offer", {"lesson":"T18"})
	if not str(write.get("error", "")).is_empty(): print("SAVE_DEBUG pending: " + str(write.error))
	_expect(str(write.get("error", "")).is_empty(), "versioned save commits pending private offer")
	var loaded: Dictionary = store.load_session("app_save_pending_offer")
	if not str(loaded.get("error", "")).is_empty(): print("SAVE_DEBUG load: " + str(loaded.error))
	_expect(str(loaded.get("error", "")).is_empty(), "save slot selection loads validated Session snapshot")
	if loaded.has("session"):
		var restored = loaded.session
		_expect(restored.state.private.offers.player == saved_offer and restored.state.private.offer_ids.player == saved_offer_id,
			"private draft offer and stable offer ID survive reload; no reroll")
		if restored.rng_counter != saved_rng_counter or restored.draft.snapshot() != saved_draft:
			print("SAVE_DEBUG rng=%d/%d draft=%s/%s" % [restored.rng_counter,saved_rng_counter,var_to_str(restored.draft.snapshot()),var_to_str(saved_draft)])
		_expect(restored.rng_counter == saved_rng_counter and restored.draft.snapshot() == saved_draft,
			"Session RNG and draft RNG counters/state survive reload")
		_expect(restored.ledger.balances == saved_balances and restored.ledger.assert_invariants(), "wallet/table/pot balances restore exactly and conserve")
		var before := var_to_str(restored.snapshot())
		var duplicate: Dictionary = restored.apply(CommandScript.new("pending-player-draw", "player", "commit_operation",
			{"operation":"draw_card"}, int(restored.state.revision)))
		_expect(not bool(duplicate.get("accepted", false)) and before == var_to_str(restored.snapshot()), "replaying a consumed draw intent cannot redraw")
	var exported: Dictionary = store.export_json(session, {"lesson":"T18"})
	if not str(exported.get("error", "")).is_empty(): print("SAVE_DEBUG export: " + str(exported.error))
	var imported: Dictionary = store.import_json(str(exported.get("json", "")))
	if not str(imported.get("error", "")).is_empty(): print("SAVE_DEBUG import: " + str(imported.error))
	_expect(str(imported.get("error", "")).is_empty(), "data-only JSON export imports through schema validation")
	_expect(imported.get("tutorial_state", {}).get("lesson", "") == "T18", "tutorial progress data is preserved with the Session")
	var invalid_json: Dictionary = store.import_json("{")
	_expect(invalid_json.get("error", "") == "save_json_invalid", "malformed save reports explicit error")
	var unsupported: Dictionary = JSON.parse_string(str(exported.json))
	unsupported.schema_version[SaveStoreScript.INTEGER_TAG] = "999"
	_expect(str(store.import_json(JSON.stringify(unsupported)).get("error", "")).begins_with("save_schema_unsupported"), "unknown schema version is rejected explicitly")
	var corrupt: Dictionary = JSON.parse_string(str(exported.json))
	var tagged_pot: Dictionary = corrupt.session_snapshot.ledger.balances.pot
	tagged_pot[SaveStoreScript.INTEGER_TAG] = str(int(tagged_pot[SaveStoreScript.INTEGER_TAG]) + 1)
	_expect(store.import_json(JSON.stringify(corrupt)).get("error", "") == "save_session_snapshot_corrupt", "inconsistent money snapshot rejected")
	_expect(store.commit_session(session, "../outside").get("error", "") == "invalid_save_slot", "save slot path traversal rejected")
	var plain_data: Dictionary = JSON.parse_string(str(exported.json))
	plain_data.tutorial_state["script_text"] = "extends Node; do not execute"
	var imported_plain := store.import_json(JSON.stringify(plain_data))
	_expect(imported_plain.get("tutorial_state", {}).get("script_text", "") == "extends Node; do not execute", "import treats source-looking content as inert data")
	_test_large_integer_round_trip(store)
	_test_atomic_backup_recovery()


func _test_profile_wallet_lifecycle() -> void:
	var store = SaveStoreScript.new()
	var profile_controller = ProfileControllerScript.new(store)
	var profile_slot := "app_profile_flow_%d" % Time.get_ticks_usec()
	_expect(profile_controller.enter_room(100).get("error", "") == "profile_not_initialized",
		"room entry cannot create a fresh wallet implicitly")
	var created: Dictionary = profile_controller.create_new_profile(profile_slot)
	if not str(created.get("error", "")).is_empty(): print("PROFILE_DEBUG create=" + str(created.error))
	_expect(str(created.get("error", "")).is_empty() and profile_controller.profile.wallet == 1000,
		"new Profile initializes exactly one 1000-chip wallet")
	_expect(profile_controller.create_new_profile(profile_slot).get("error", "") == "profile_already_initialized",
		"same controller cannot reset an initialized wallet")
	var tutorial_saved: Dictionary = profile_controller.save_tutorial_progress({"schema_version":1,"step_index":0,"practice_wallet":{"player":100}}, false)
	if not str(tutorial_saved.get("error", "")).is_empty(): print("PROFILE_DEBUG tutorial=" + str(tutorial_saved.error))
	_expect(str(tutorial_saved.get("error", "")).is_empty(), "no-table tutorial progress saves without an active Session")
	var isolated_tutorial: Dictionary = store.load_tutorial_progress(profile_slot)
	_expect(isolated_tutorial.get("progress", {}).get("practice_wallet", {}).get("player", 0) == 100,
		"tutorial save uses its isolated storage namespace")
	_expect(store.load_profile(profile_slot).get("profile", {}).get("wallet", 0) == 1000,
		"tutorial practice balance never replaces or subtracts the formal Profile wallet")
	# This suite exercises the legacy betting/profile lifecycle. Explicitly opt out
	# of the production team-selection gate so those assertions start at BETTING.
	var entered: Dictionary = profile_controller.enter_room(100, {"seed":773,"first_actor":"player","ante":5,"team_draft":false})
	if not str(entered.get("error", "")).is_empty(): print("PROFILE_DEBUG enter=" + str(entered.error))
	_expect(bool(entered.get("accepted", false)) and profile_controller.profile.wallet == 900,
		"100-chip buy-in debits Profile exactly once")
	var active_session: SinSession = profile_controller.app_controller.session
	_expect(active_session.ledger.balances.player_wallet == 0 and active_session.ledger.initial_total >= 200,
		"Session starts with only the transferred table buy-in, never a second 1000-chip wallet")
	_expect(profile_controller.profile.wallet + int(active_session.ledger.balances.player_table) + int(active_session.state.contributions.player) == 1000,
		"Profile remainder plus player table/pot contribution conserves the original wallet after ante")
	var resumed = ProfileControllerScript.new(store)
	var loaded: Dictionary = resumed.load_profile(profile_slot)
	_expect(str(loaded.get("error", "")).is_empty() and resumed.profile.wallet == 900 and resumed.app_controller != null,
		"active Session snapshot and unspent Profile remainder resume together")
	_expect(resumed.app_controller.session.ledger.balances.player_wallet == 0 and
		resumed.profile.tutorial_progress.get("step_index", -1) == 0 and not resumed.profile.tutorial_completed,
		"resume preserves zero duplicate wallet and prior tutorial progress")
	var folded: Dictionary = resumed.submit(_command(resumed.app_controller.session, "player", "fold", {}))
	_expect(bool(folded.get("accepted", false)), "Profile facade routes legal fold into its real Session")
	var left: Dictionary = resumed.submit(_command(resumed.app_controller.session, "player", "leave_table", {}))
	_expect(bool(left.get("accepted", false)) and resumed.profile.wallet == 995 and resumed.app_controller == null,
		"generic player leave_table routes through Profile and returns only remaining chips")
	var final_load: Dictionary = store.load_profile(profile_slot)
	_expect(str(final_load.get("error", "")).is_empty() and final_load.profile.wallet == 995 and
		final_load.profile.active_session_snapshot == null,
		"no-table saved Profile contains the returned wallet and no stale active Session")
	_expect(store.load_tutorial_progress(profile_slot).progress.practice_wallet.player == 100,
		"Profile/room save cannot overwrite the separate tutorial wallet progress file")
	_expect(resumed.enter_room(150).get("error", "") == "buy_in_choice_invalid" and resumed.profile.wallet == 995,
		"unsupported buy-in cannot debit the Profile")
	for choice in [200, 500, "all"]:
		var choice_seed := 900 + int(resumed.profile.wallet % 73)
		var buy_in_result: Dictionary = resumed.enter_room(choice, {"seed":choice_seed,"first_actor":"player","ante":5,"team_draft":false})
		_expect(bool(buy_in_result.get("accepted", false)), "Profile accepts supported buy-in choice %s" % str(choice))
		var active: SinSession = resumed.app_controller.session
		var expected_table: int = 980 if choice is String else int(choice) - 5
		_expect(active.ledger.balances.player_wallet == 0 and active.ledger.balances.player_table == expected_table,
			"choice %s transfers its exact buy-in into Session" % str(choice))
		_expect(bool(resumed.submit(_command(active, "player", "fold", {})).get("accepted", false)), "Profile routes fold for buy-in %s" % str(choice))
		var choice_left := resumed.leave_room("profile-choice-%s" % str(choice))
		_expect(bool(choice_left.get("accepted", false)), "Profile cashes out legal table remainder for %s" % str(choice))


func _test_profile_resume_battle() -> void:
	var store = SaveStoreScript.new()
	var slot := "prb_%d" % Time.get_ticks_usec()
	var profile = ProfileControllerScript.new(store, true)
	var created: Dictionary = profile.create_new_profile(slot)
	if not bool(created.get("accepted", false)): print("PROFILE_RESUME create=" + str(created))
	_expect(bool(created.get("accepted", false)), "resume fixture creates persisted Profile")
	var entered: Dictionary = profile.enter_room(100, {"seed":1907,"first_actor":"player","ante":5,"team_draft":false})
	if not bool(entered.get("accepted", false)): print("PROFILE_RESUME enter=" + str(entered))
	_expect(bool(entered.get("accepted", false)),
		"resume fixture enters room through wallet boundary")
	var session: SinSession = profile.app_controller.session
	var first := profile.submit(_command(session, "player", "all_in", {}))
	_expect(bool(first.get("accepted", false)), "resume fixture first all-in uses App command API")
	var second := profile.submit(_command(session, "opponent", "all_in", {}))
	_expect(bool(second.get("accepted", false)) and session.state.phase == "BATTLE_READY" and profile.app_controller.pending_battle_replay,
		"real Session reaches replay-ready and Profile persists unsettled battle")
	var ledger_before: Dictionary = session.ledger.snapshot()
	var revision_before := int(session.state.revision)
	var restored = ProfileControllerScript.new(store, true)
	var loaded: Dictionary = restored.load_profile(slot)
	_expect(str(loaded.get("error", "")).is_empty() and restored.app_controller.session.state.phase == "BATTLE_READY" and
		not restored.app_controller.pending_battle_replay,
		"loading BATTLE_READY restores Session but not ephemeral replay cache")
	if restored.app_controller == null: return
	var replay: Dictionary = restored.resume_pending_battle()
	_expect(str(replay.get("error", "")).is_empty() and replay.get("phase", "") == "BATTLE_REPLAY" and replay.get("initial_snapshot", {}).has("teams"),
		"resume recomputes a real replay package with pre-combat teams")
	_expect(restored.app_controller.session.ledger.snapshot() == ledger_before and restored.app_controller.session.state.revision == revision_before,
		"resuming changes neither paid ledger/RNG history nor Session revision")
	var replay_again: Dictionary = restored.resume_pending_battle()
	_expect(replay_again == replay, "repeated resume returns cached replay without another battle simulation")
	var settled: Dictionary = restored.finish_battle_replay(int(replay.get("event_count", -1)))
	_expect(bool(settled.get("accepted", false)) and restored.app_controller.session.state.phase == "SETTLED",
		"resumed replay settles exactly once after presentation completion")
	var settled_snapshot: Dictionary = restored.app_controller.session.snapshot()
	_expect(restored.resume_pending_battle().get("error", "") == "battle_not_ready" and
		restored.app_controller.session.snapshot() == settled_snapshot,
		"settled battle cannot be resumed or paid out a second time")


func _test_default_formal_pool() -> void:
	var session = _new_session(205, 10, 10)
	var controller = ControllerScript.new(session)
	_expect(not controller.integration_review, "normal app controller uses formal play mode")
	var first = controller.submit(_command(session, str(session.state.acting_side), "all_in", {}))
	_expect(bool(first.get("accepted", false)), "formal fixture first all-in action accepted")
	var second_side := str(session.state.acting_side)
	var second = controller.submit(_command(session, second_side, "all_in", {}))
	_expect(bool(second.get("accepted", false)) and str(second.get("battle_error", "")).is_empty() and
		bool(second.get("battle_pending_replay", false)),
		"default release path starts a real battle from the supported formal subset")
	_expect(controller.pending_battle_replay and session.state.phase == "BATTLE_READY",
		"formal battle waits for replay consumption before settlement")


func _test_real_draw_settles_as_tie() -> void:
	var session = MirrorRosterSession.new({"seed":919,"player_table":5,"opponent_table":5,
		"player_wallet":100,"opponent_funds":100,"ante":5,"first_actor":"player",
		"public_effect_pool":[]})
	session.state.rule_id = "VC01"
	session.state.arena_id = "AR02"
	var controller = ControllerScript.new(session, null, true)
	var money_before: Dictionary = session.ledger.balances.duplicate(true)
	var replay: Dictionary = controller.resolve_battle()
	_expect(str(replay.get("error", "")).is_empty() and replay.get("phase", "") == "BATTLE_REPLAY" and replay.get("terminal", false),
		"identical legal WR teams produce a real terminal BattleEngine replay")
	_expect(session.state.phase == "BATTLE_READY" and session.ledger.balances == money_before,
		"battle precomputation does not settle or alter any wallet/pot amount")
	var replay_view: Dictionary = controller.observation("player")
	var expected_prebattle_public := {"player_table":money_before.player_table,
		"opponent_table":money_before.opponent_table,"pot":money_before.pot}
	_expect(replay_view.phase == "BATTLE_REPLAY" and replay_view.public.balances == expected_prebattle_public,
		"replay observation holds the exact prebattle balances and marks BATTLE_REPLAY")
	_expect(replay_view.opponent_public.team.size() == 3 and not replay_view.opponent_public.team_sealed,
		"opposing identities are revealed at battle start for the initial battle presentation")
	_expect(replay.get("initial_snapshot", {}).get("teams", {}).get("A", []).size() == 3 and
		replay.get("initial_snapshot", {}).get("teams", {}).get("B", []).size() == 3,
		"replay carries the pre-combat six-unit initial snapshot, not the final dead-unit snapshot")
	_expect(controller.legal_actions("player").is_empty(), "BATTLE_REPLAY exposes no economic/legal actions")
	var early_finish := controller.finish_battle_replay(0)
	_expect(early_finish.get("error", "") == "battle_replay_incomplete" and session.ledger.balances == money_before,
		"replay cannot be completed before all engine events are consumed")
	var bypass_leave := controller.submit(_command(session, "player", "leave_table", {}))
	_expect(bypass_leave.get("error", "") == "battle_replay_in_progress" and session.ledger.balances == money_before,
		"leave cannot bypass the replay gate")
	var replay_ack: Dictionary = controller.finish_battle_replay(int(replay.get("event_count", -1)))
	_expect(bool(replay_ack.get("accepted", false)) and replay_ack.get("battle_result", {}).get("winner", "") == "draw",
		"completed event replay maps the real BattleEngine draw to tie settlement")
	_expect(session.state.phase == "SETTLED" and session.ledger.balances.pot == 0 and session.ledger.assert_invariants(),
		"only replay completion triggers real draw refunds/conservation in Session")
	_expect(controller.observation("player").public.battle_result.get("winner", "") == "tie",
		"post-replay observation now exposes the settled tie and final balances")


func _test_fold_does_not_reveal_or_replay() -> void:
	var session := _new_session(918)
	var controller = ControllerScript.new(session, null, true)
	_expect(bool(controller.submit(_command(session, "player", "bet", {"amount":10})).get("accepted", false)), "fold privacy fixture bets through controller")
	_expect(bool(controller.submit(_command(session, "opponent", "call", {"amount":10})).get("accepted", false)), "fold privacy fixture reaches operation window")
	var folded: Dictionary = controller.submit(_command(session, "player", "fold", {}))
	_expect(bool(folded.get("accepted", false)) and session.state.phase == "SETTLED" and not controller.pending_battle_replay,
		"fold settles directly without starting a battle replay")
	var after_fold := controller.observation("player")
	_expect(after_fold.opponent_public.team_sealed and after_fold.opponent_public.team.is_empty() and not after_fold.public.teams_revealed,
		"fold reveals no enemy identity because battle never started")


func _test_full_session_flow() -> void:
	var chosen_seed := _find_seed_with_verified_next_hand()
	_expect(chosen_seed > 0, "find deterministic next-hand fixture whose arena/effects are real handlers")
	if chosen_seed <= 0: return
	var session = _new_session(chosen_seed)
	session.state.rule_id = "VC21"
	session.state.arena_id = "AR02"
	var store = SaveStoreScript.new()
	_expect(str(store.commit_session(session, "app_full_flow_selection").get("error", "")).is_empty(), "new table state saved for slot selection")
	var selected_slot: Dictionary = store.load_session("app_full_flow_selection", _new_session(chosen_seed))
	_expect(str(selected_slot.get("error", "")).is_empty(), "full flow begins from a selected saved slot")
	if not selected_slot.has("session"): return
	var selected_session: SinSession = selected_slot.session
	selected_session.state.rule_id = "VC21"
	selected_session.state.arena_id = "AR02"
	var controller = ControllerScript.new(selected_session, null, true)
	_expect(controller.integration_review, "local integration review is explicitly enabled for fixed WR test roster")
	_expect(_advance_hand_to_settlement(controller, {"PE05":true}) , "Session public choices reach a completed actual assembled battle")
	_expect(selected_session.state.phase == "BATTLE_READY" and controller.pending_battle_replay, "actual battle awaits presentation replay before settlement")
	var balances_during_replay: Dictionary = selected_session.ledger.balances.duplicate(true)
	var replay_view := controller.observation("player")
	_expect(replay_view.phase == "BATTLE_REPLAY" and replay_view.opponent_public.team.size() == 3,
		"battle-start view reveals opposing team while preserving prebattle balances")
	_expect(controller.legal_actions("player").is_empty(), "replay phase has no leave/next/economic legal actions")
	var replay_leave := controller.submit(_command(selected_session, "player", "leave_table", {}))
	_expect(replay_leave.get("error", "") == "battle_replay_in_progress" and selected_session.ledger.balances == balances_during_replay,
		"attempted leave cannot expose payout or return chips mid-animation")
	var replay_ack := controller.finish_battle_replay(controller.pending_replay_events.size())
	_expect(bool(replay_ack.get("accepted", false)) and replay_ack.get("battle_result", {}).get("settlement", {}).has("accepted"), "only completed replay triggers settlement and releases final result")
	_expect(selected_session.state.phase == "SETTLED" and controller.observation("player").public.battle_result.has("winner"), "settled balances/outcome become observable only after replay")
	_expect(str(controller.last_battle.get("error", "")).is_empty() and bool(controller.last_battle.get("terminal", false)), "BattleEngine result is terminal, not mocked")
	var battle_snapshot: Dictionary = controller.last_battle.get("snapshot", {})
	var fixture_count := 0
	for side in ["A", "B"]:
		for unit in battle_snapshot.get("teams", {}).get(side, []):
			if bool(unit.get("fixture", false)): fixture_count += 1
	_expect(fixture_count == 0, "review integration uses real WR definitions, no fixture characters")
	_expect(controller.last_battle.get("content_coverage", null) == null or fixture_count == 0, "result path remains real character battle; formal release is still gated")
	var next_result := controller.submit(_command(selected_session, "player", "next_hand", {}))
	_expect(bool(next_result.get("accepted", false)) and selected_session.state.hand_id == 2, "real next_hand command advances Session/RNG")
	_expect(selected_session.state.phase == "BETTING", "next hand starts through Session, not controller shortcut")
	_expect(_advance_hand_to_settlement(controller, {}) , "next hand proceeds through legal public choices and real battle")
	_expect(selected_session.state.phase == "BATTLE_READY" and controller.pending_battle_replay, "second actual battle remains unsettled during replay")
	_expect(bool(controller.finish_battle_replay(controller.pending_replay_events.size()).get("accepted", false)) and selected_session.state.phase == "SETTLED",
		"second replay completion settles before leaving")
	var leave := controller.submit(_command(selected_session, "player", "leave_table", {}))
	_expect(bool(leave.get("accepted", false)) and bool(selected_session.state.left_table), "legal leave command returns chips after settlement")
	_expect(selected_session.ledger.balances.player_table == 0 and selected_session.ledger.balances.opponent_table == 0,
		"leave transfers remaining table stacks exactly once")
	_expect(selected_session.ledger.assert_invariants(), "full flow conserves every wallet, table stack, and pot chip")
	var duplicate_leave := controller.submit(_command(selected_session, "player", "leave_table", {}))
	_expect(not bool(duplicate_leave.get("accepted", false)), "repeat leave is rejected without duplicate wallet transfer")


func _advance_hand_to_settlement(controller, active_effects: Dictionary) -> bool:
	var session: SinSession = controller.session
	var safety := 0
	while session.state.phase != "SETTLED" and safety < 80:
		safety += 1
		match str(session.state.phase):
			"BETTING":
				var actor := str(session.state.acting_side)
				var result: Dictionary = controller.submit(_command(session, actor, "check", {}))
				if not bool(result.get("accepted", false)): return false
			"PUBLIC_COMMIT":
				var activate := active_effects.has(str(session.state.current_public_effect))
				for side in ["player", "opponent"]:
					var result: Dictionary = controller.submit(_command(session, side, "public_decision", {"activate":activate}))
					if not bool(result.get("accepted", false)): return false
			"BATTLE_READY":
				if not controller.pending_battle_replay:
					var battle: Dictionary = controller.resolve_battle()
					if not str(battle.get("error", "")).is_empty(): return false
				return true
			"SETTLED": return true
			_:
				return false
	return session.state.phase == "SETTLED"


func _find_seed_with_verified_next_hand() -> int:
	for seed_value in range(1, 3000):
		var probe = _new_session(seed_value)
		probe.state.phase = "BATTLE_READY"
		var settle_result: Dictionary = probe.settle_battle("tie")
		if not bool(settle_result.get("accepted", false)): continue
		var next := probe.apply(CommandScript.new("seed-probe-next", "player", "next_hand", {}, int(probe.state.revision)))
		if not bool(next.get("accepted", false)): continue
		if not environment_handlers.supports_content_id(str(probe.state.arena_id)): continue
		var all_known := true
		for effect_id in probe.public_effect_pool:
			if not environment_handlers.supports_content_id(str(effect_id)):
				all_known = false
				break
		if all_known: return seed_value
	return -1


func _test_tutorial_machine() -> void:
	var live_session = _new_session(311)
	var live_before := var_to_str(live_session.snapshot())
	var runner = TutorialScript.new()
	var start: Dictionary = runner.begin()
	_expect(str(start.get("error", "")).is_empty() and runner.current_step().id == "T01", "tutorial loads data-defined first step")
	var early := runner.observe({"kind":"opponent_seated"})
	_expect(not str(early.get("error", "")).is_empty() and runner.step_index == 0, "tutorial requires glossary explanations before any gated action")
	_expect(runner.next_step().get("error", "") == "tutorial_progress_requires_real_events", "tutorial has no click-count/next escape hatch")
	var t17_session := _new_session(312)
	var t17_bet: Dictionary = _apply(t17_session, "player", "bet", {"amount":10})
	var t17_call: Dictionary = _apply(t17_session, "opponent", "call", {"amount":10})
	_expect(bool(t17_bet.get("accepted", false)) and bool(t17_call.get("accepted", false)) and t17_session.ledger.balances.pot == 30,
		"T17 real Session fixture computes matched-bet pot as 30")
	_expect(bool(_apply(t17_session, "player", "commit_operation", {"operation":"draw_card"}).get("accepted", false)),
		"T17 real Session saves player's private paid operation intent")
	var t17_batch: Dictionary = _apply(t17_session, "opponent", "commit_operation", {"operation":"pass"})
	var actual_fee_event: Dictionary = {}
	for event in t17_batch.get("events", []):
		if str(event.get("kind", "")) == "operation_fee_paid" and str(event.get("source", "")) == "player":
			actual_fee_event = event.duplicate(true)
	_expect(t17_session.state.phase == "DRAFT_SELECTION" and t17_session.state.private.offers.player.size() == 3,
		"T17 real Session creates a three-card private offer only after the paid batch")
	_expect(t17_session.ledger.balances.pot == 40 and t17_session.ledger.balances.player_table == 75 and
		t17_session.ledger.balances.opponent_table == 85 and not actual_fee_event.is_empty() and
		int(actual_fee_event.payload.pot) == 40,
		"T17 actual ledger proves player pays 10 (total 20), opponent 10 (total 10), pot becomes 40")
	var reset_expected := 0
	for index in range(35):
		var step := runner.current_step()
		_expect(str(step.get("id", "")) == "T%02d" % (index + 1), "tutorial step order is data-defined")
		if bool(step.get("reset_fixture_wallet_before", false)): reset_expected += 1
		for term_id in step.get("terms_before_action", []):
			var explanation: Dictionary = runner.explain(str(term_id))
			_expect(str(explanation.get("error", "")).is_empty() and explanation.get("term", {}).has("definition"),
				"term %s is explained from glossary before action at %s" % [term_id, step.id])
		var before_index: int = runner.step_index
		var irrelevant := runner.observe({"kind":"next"})
		_expect(bool(irrelevant.get("accepted", false)) and runner.step_index == before_index, "non-domain next signal cannot advance %s" % step.id)
		for gate in step.required_events:
			var event: Dictionary
			if index == 16 and str(gate.get("kind", "")) == "operation_fee_paid":
				var wrong_fee: Dictionary = actual_fee_event.duplicate(true)
				wrong_fee.payload.pot = 50
				var runner_before_bad_fee: int = runner.step_index
				var rejected_fee := runner.observe(wrong_fee)
				_expect(not bool(rejected_fee.get("advanced", false)) and runner.step_index == runner_before_bad_fee,
					"T17 rejects a false 50-pot fee event; real Session says 40")
				event = actual_fee_event.duplicate(true)
			elif index == 16 and str(gate.get("kind", "")) == "draft_offer_created":
				event = {"kind":"draft_offer_created","candidate_count":t17_session.state.private.offers.player.size(),
					"private":true,"locked_after_payment":t17_session.state.phase == "DRAFT_SELECTION"}
			else:
				event = gate.get("equals", {}).duplicate(true)
				event["kind"] = str(gate.kind)
			var observed: Dictionary = runner.observe(event)
			_expect(str(observed.get("error", "")).is_empty(), "real-operation event gate accepted for %s/%s" % [step.id, gate.id])
		_expect(runner.step_index == index + 1, "only all required event gates complete %s" % step.id)
		if index == 17:
			var partial := runner.snapshot()
			var resumed = TutorialScript.new()
			_expect(resumed.restore_snapshot(partial) and resumed.step_index == runner.step_index,
				"versioned tutorial progress restores at the exact event-gated step")
	_expect(runner.completed and runner.step_index == 35, "all 35 data-defined steps complete through their event gates")
	_expect(runner.fixture_wallet_resets == reset_expected and reset_expected == 5, "independent economic fixtures reset only the isolated tutorial wallet")
	_expect(var_to_str(live_session.snapshot()) == live_before, "tutorial wallets/fixture resets never mutate the formal Session")
	_expect(runner.explain("unknown_term").get("error", "") == "tutorial_not_active", "completed tutorial cannot mutate state via glossary calls")
	var tutorial_save := SaveStoreScript.new().export_json(live_session, {"runner":runner.snapshot()})
	var tutorial_import := SaveStoreScript.new().import_json(str(tutorial_save.get("json", "")))
	var restored_tutorial = TutorialScript.new()
	var tutorial_state: Dictionary = tutorial_import.get("tutorial_state", {}).get("runner", {})
	_expect(str(tutorial_import.get("error", "")).is_empty() and restored_tutorial.restore_snapshot(tutorial_state),
		"tutorial snapshot survives tagged-integer JSON export/import/restore")
	_expect(restored_tutorial.snapshot() == runner.snapshot(), "tutorial wallet, counters, completion and gates restore exactly")
	var invalid_restore: Dictionary = tutorial_state.duplicate(true)
	invalid_restore.completed = false
	var before_invalid_restore := var_to_str(restored_tutorial.snapshot())
	_expect(not restored_tutorial.restore_snapshot(invalid_restore) and before_invalid_restore == var_to_str(restored_tutorial.snapshot()),
		"invalid tutorial snapshot is rejected without partially mutating runner state")


func _test_large_integer_round_trip(store: SinSaveStore) -> void:
	var large_seed := 9_007_199_254_741_337
	var session := _new_session(large_seed)
	var snapshot_before: Dictionary = session.snapshot()
	var exported := store.export_json(session, {"large_tutorial_counter":9_007_199_254_741_339})
	_expect(str(exported.get("error", "")).is_empty() and str(exported.get("json", "")).contains("$sin_integer"),
		"large int64 values use explicit tagged decimal-string encoding")
	var imported := store.import_json(str(exported.get("json", "")))
	_expect(str(imported.get("error", "")).is_empty() and imported.session.snapshot() == snapshot_before,
		"seed/RNG state/counters above 2^53 round-trip exactly")
	_expect(imported.get("tutorial_state", {}).get("large_tutorial_counter", 0) == 9_007_199_254_741_339,
		"tutorial integer above 2^53 round-trips without JSON float loss")
	var restored: SinSession = imported.session
	var actor := str(session.state.acting_side)
	var other := "opponent" if actor == "player" else "player"
	_expect(bool(_apply(session, actor, "bet", {"amount":10}).get("accepted", false)), "large-seed draft fixture opens betting legally")
	_expect(bool(_apply(restored, actor, "bet", {"amount":10}).get("accepted", false)), "restored large-seed betting opens identically")
	_expect(bool(_apply(session, other, "call", {"amount":10}).get("accepted", false)), "large-seed draft fixture calls legally")
	_expect(bool(_apply(restored, other, "call", {"amount":10}).get("accepted", false)), "restored large-seed betting calls identically")
	_expect(bool(_apply(session, "player", "commit_operation", {"operation":"draw_card"}).get("accepted", false)), "large-seed first draft intent commits")
	_expect(bool(_apply(restored, "player", "commit_operation", {"operation":"draw_card"}).get("accepted", false)), "restored large-seed first draft intent commits")
	var pending_export := store.export_json(session)
	var pending_import := store.import_json(str(pending_export.get("json", "")))
	_expect(str(pending_import.get("error", "")).is_empty(), "mid-draft large RNG state exports/imports before second commitment")
	if pending_import.has("session"): restored = pending_import.session
	_expect(bool(_apply(session, "opponent", "commit_operation", {"operation":"draw_card"}).get("accepted", false)), "large-seed second draft intent commits")
	_expect(bool(_apply(restored, "opponent", "commit_operation", {"operation":"draw_card"}).get("accepted", false)), "reloaded large-seed second draft intent commits")
	_expect(session.state.private.offers == restored.state.private.offers and session.state.private.offer_ids == restored.state.private.offer_ids,
		"the next actual draft offer and identity match after exact large-state reload")
	var invalid_integer := str(exported.json).replace('"%s":"%s"' % [SaveStoreScript.INTEGER_TAG,str(large_seed)], '"%s":"9223372036854775808"' % SaveStoreScript.INTEGER_TAG)
	_expect(store.import_json(invalid_integer).get("error", "") == "save_json_invalid", "int64 overflow is rejected instead of rounded or wrapped")
	var untagged := str(exported.json).replace('"schema_version":{"%s":"2"}' % SaveStoreScript.INTEGER_TAG, '"schema_version":2')
	_expect(store.import_json(untagged).get("error", "") == "save_json_invalid", "untagged JSON integer is not implicitly coerced into session data")


func _test_atomic_backup_recovery() -> void:
	var store = SaveStoreScript.new()
	var first = _new_session(440)
	var second = _new_session(441)
	_expect(str(store.commit_session(first, "app_atomic_recovery").get("error", "")).is_empty(), "first complete snapshot is committed")
	_expect(str(store.commit_session(second, "app_atomic_recovery").get("error", "")).is_empty(), "replacement snapshot commits after same-directory staging")
	var damaged := FileAccess.open("user://saves/app_atomic_recovery.json", FileAccess.WRITE)
	if damaged != null:
		damaged.store_string("partial write")
		damaged.close()
	var recovered: Dictionary = store.load_session("app_atomic_recovery")
	_expect(bool(recovered.get("recovered_from_backup", false)) and recovered.get("session", null).seed_value == first.seed_value,
		"corrupt primary recovers the latest previously complete commit")


func _new_session(seed_value: int, player_stack: int = 100, opponent_stack: int = 100) -> SinSession:
	return FixedRosterSession.new({"seed":seed_value,"player_table":player_stack,"opponent_table":opponent_stack,
		"player_wallet":1000,"opponent_funds":1000,"ante":5,"first_actor":"player",
		"public_effect_pool":["PE05","PE09","PE10"]})


func _command(session: SinSession, actor: String, kind: String, payload: Dictionary) -> SinCommand:
	command_serial += 1
	return CommandScript.new("app-test-%d" % command_serial, actor, kind, payload, int(session.state.revision))


func _apply(session: SinSession, actor: String, kind: String, payload: Dictionary) -> Dictionary:
	return session.apply(_command(session, actor, kind, payload))


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
