extends RefCounted

var passed := 0
var failed := 0
var lines: Array[String] = []
var serial := 0
var current_test := ""
var test_failures: Dictionary = {}

func run_all() -> Dictionary:
	_test_e01_accounting_example()
	_test_e02_round_match_delta()
	_test_e03_unequal_contribution_tie_refund()
	_test_e04_public_auction_total_price()
	_test_e05_public_consensus_and_decline()
	_test_e06_unmatched_all_in_refund()
	_test_e07_atomic_operation_batch_when_empty()
	_test_e08_zero_stack_can_still_win()
	_test_e09_idempotency_and_invalid_amounts()
	_test_e10_no_free_draw_and_response_after_third_effect()
	_test_e11_snapshot_replay_and_private_offer()
	_test_e12_invariants_over_seeded_sequences()
	_test_review_round_queue_and_seed_privacy()
	_test_review_common_ante_and_auction_all_in()
	_test_review_atomicity_fold_privacy_and_legal_actions()
	_test_review_double_draw_batch_and_archive()
	_test_review_next_hand_loop()
	return {"passed": passed, "failed": failed, "lines": lines.duplicate()}

func _test_e01_accounting_example() -> void:
	current_test = "E01"
	var game := _new_game({"first_actor": "player"})
	_check(game.ledger.balances.pot == 10, "E01 antes are included in pot")
	_send(game, "player", "bet", {"amount": 10})
	_send(game, "opponent", "call", {"amount": 10})
	_send(game, "player", "commit_operation", {"operation": "set_arrows", "arrows": [2, 2, 2]})
	var result := _send(game, "opponent", "commit_operation", {"operation": "pass"})
	_check(result.accepted, "E01 operations commit")
	_check(game.ledger.balances.player_table == 75 and game.ledger.balances.opponent_table == 85 and game.ledger.balances.pot == 40, "E01 expected 75/85/40")
	_check(game.ledger.total_chips() == 200, "E01 conservation")
	_done("E01")

func _test_e02_round_match_delta() -> void:
	current_test = "E02"
	var game := _new_game({"first_actor": "player", "ante": 0})
	_send(game, "player", "bet", {"amount": 10})
	_send(game, "opponent", "raise", {"amount": 30})
	_send(game, "player", "call", {"amount": 20})
	_check(game.state.round_paid.player == 30 and game.state.round_paid.opponent == 30, "E02 matched total is 30")
	_check(game.ledger.balances.pot == 60, "E02 only 20 extra is collected")
	_done("E02")

func _test_e03_unequal_contribution_tie_refund() -> void:
	current_test = "E03"
	var game := _new_game({"first_actor": "player", "ante": 0, "public_effect_pool": []})
	_send(game, "player", "bet", {"amount": 10})
	_send(game, "opponent", "call", {"amount": 10})
	_send(game, "player", "commit_operation", {"operation": "set_arrows", "arrows": [1, 1, 1]})
	_send(game, "opponent", "commit_operation", {"operation": "pass"})
	_send(game, game.state.acting_side, "check", {})
	_send(game, game.state.acting_side, "check", {})
	_check(game.state.phase == "BATTLE_READY", "E03 reaches ready after mutual checks")
	var settled := game.settle_battle("tie")
	_check(settled.accepted, "E03 tie settles")
	_check(game.ledger.balances.player_table == 100 and game.ledger.balances.opponent_table == 100, "E03 both actual contributions returned")
	_check(game.ledger.balances.pot == 0 and game.state.battle_result.net.player == 0 and game.state.battle_result.net.opponent == 0, "E03 tie has no hidden transfer")
	_done("E03")

func _test_e04_public_auction_total_price() -> void:
	current_test = "E04"
	var game := _open_first_public({"first_actor": "player", "ante": 0})
	_send(game, "player", "public_decision", {"activate": true})
	_send(game, "opponent", "public_decision", {"activate": false})
	_send(game, "player", "public_bid", {"amount": 5})
	_send(game, "opponent", "public_bid", {"amount": 10})
	_send(game, "player", "public_bid", {"amount": 15})
	_send(game, "opponent", "pass_public_bid", {})
	_check(game.ledger.balances.player_table == 85 and game.ledger.balances.opponent_table == 100, "E04 only winning total quote is charged")
	_check(game.ledger.balances.pot == 15 and game.state.revealed_effects == ["PE01"], "E04 losing bid is uncharged and winning bidder's choice resolves")
	_done("E04")

func _test_e05_public_consensus_and_decline() -> void:
	current_test = "E05"
	var game := _open_first_public({"first_actor": "player", "ante": 0})
	_send(game, "player", "public_decision", {"activate": true})
	_send(game, "opponent", "public_decision", {"activate": true})
	_check(game.ledger.balances.pot == 0 and game.state.revealed_effects.size() == 1, "E05 mutual activation is free")
	_check(game.state.phase == "BETTING" and game.state.round == 1, "E05 consensus resumes the prepared round")
	var declined := _open_first_public({"first_actor": "player", "ante": 0})
	_send(declined, "player", "public_decision", {"activate": true})
	_send(declined, "opponent", "public_decision", {"activate": false})
	_send(declined, declined.state.acting_side, "pass_public_bid", {})
	_check(declined.ledger.balances.pot == 0 and declined.state.revealed_effects.is_empty(), "E05 first bidder may decline with no payment")
	_done("E05")

func _test_e06_unmatched_all_in_refund() -> void:
	current_test = "E06"
	var game := _new_game({"first_actor": "opponent", "ante": 0, "player_table": 20, "opponent_table": 50})
	_send(game, "opponent", "all_in", {})
	_check(game.state.phase == "BETTING" and game.state.acting_side == "player", "E06 overbet all-in waits for the other decision")
	_send(game, "player", "all_in", {})
	_check(game.state.phase == "BATTLE_READY", "E06 short all-in response closes unmatched round")
	_check(game.ledger.balances.opponent_table == 30 and game.ledger.balances.player_table == 0 and game.ledger.balances.pot == 40, "E06 refunds only 30 current-round unmatched chips")
	_check(game.state.contributions.opponent == 20 and game.state.contributions.player == 20, "E06 refunded overage is excluded from current contribution")
	var ante_all_in := _new_game({"first_actor": "player", "ante": 5, "player_table": 40, "opponent_table": 100})
	_send(ante_all_in, "player", "all_in", {})
	var all_in_response := _send(ante_all_in, "opponent", "all_in", {})
	_check(all_in_response.accepted and ante_all_in.state.phase == "BATTLE_READY", "E06 all-in response to a short-stack all-in closes the hand")
	_check(ante_all_in.state.round_paid.player == 35 and ante_all_in.state.round_paid.opponent == 35, "E06 all-in response refunds excess to exact owed amount")
	_check(ante_all_in.ledger.balances.opponent_table == 60 and ante_all_in.ledger.balances.pot == 80, "E06 ante plus matched wagers remain conserved after all-in response")
	_check(all_in_response.events.any(func(domain_event: Dictionary) -> bool: return domain_event.kind == "unmatched_round_refund" and domain_event.payload.amount == 60), "E06 all-in excess has a real refund event")
	var followed := _new_game({"first_actor": "player", "ante": 0, "player_table": 45, "opponent_table": 100, "public_effect_pool": ["PE01", "PE02", "PE03"]})
	_send(followed, "player", "bet", {"amount": 10})
	_send(followed, "opponent", "raise", {"amount": 30})
	_send(followed, "player", "call", {"amount": 20})
	_send(followed, "player", "commit_operation", {"operation": "pass"})
	_send(followed, "opponent", "commit_operation", {"operation": "pass"})
	_send(followed, "player", "public_decision", {"activate": false})
	_send(followed, "opponent", "public_decision", {"activate": false})
	_check(followed.state.round_paid.player == 0 and followed.state.round_paid.opponent == 0, "E06 a new round resets ordinary contributions")
	_send(followed, "opponent", "bet", {"amount": 20})
	var small_all_in := _send(followed, "player", "all_in", {})
	_check(followed.state.phase == "BATTLE_READY" and followed.state.round_paid.player == followed.state.round_paid.opponent, "E06 all-in response settles at matched current-round amount")
	_check(small_all_in.accepted and followed.ledger.balances.opponent_table == 55 and followed.ledger.balances.pot == 90, "E06 small all-in returns only this round's excess")
	_done("E06")

func _test_e07_atomic_operation_batch_when_empty() -> void:
	current_test = "E07"
	var game := _new_game({"first_actor": "player", "ante": 0, "player_table": 20, "opponent_table": 40, "public_effect_pool": []})
	_send(game, "player", "bet", {"amount": 10})
	_send(game, "opponent", "call", {"amount": 10})
	_send(game, "player", "commit_operation", {"operation": "set_arrows", "arrows": [3, 3, 3]})
	var result := _send(game, "opponent", "commit_operation", {"operation": "set_arrows", "arrows": [2, 2, 2]})
	_check(result.accepted and game.state.phase == "BATTLE_READY", "E07 both submitted operations resolve despite first payer reaching zero")
	_check(game.state.arrows.player == [3, 3, 3] and game.state.arrows.opponent == [2, 2, 2], "E07 both same-batch choices applied")
	_check(game.ledger.balances.player_table == 0 and game.ledger.balances.pot == 40, "E07 operation fees are in pot exactly once")
	_done("E07")

func _test_e08_zero_stack_can_still_win() -> void:
	current_test = "E08"
	var game := _new_game({"first_actor": "player", "ante": 0, "player_table": 20, "opponent_table": 20})
	_send(game, "player", "all_in", {})
	_send(game, "opponent", "call", {"amount": 20})
	_check(game.state.phase == "BATTLE_READY" and game.ledger.balances.player_table == 0, "E08 zero stack is not a loss before settlement")
	var result := game.settle_battle("player")
	_check(result.accepted and game.ledger.balances.player_table == 40 and game.ledger.balances.pot == 0, "E08 winner receives unresolved pot")
	_done("E08")

func _test_e09_idempotency_and_invalid_amounts() -> void:
	current_test = "E09"
	var game := _new_game({"first_actor": "player", "ante": 0})
	var duplicate_command := SinCommand.new("same-bet", "player", "bet", {"amount": 5}, game.state.revision)
	var first := game.apply(duplicate_command)
	var second := game.apply(duplicate_command)
	_check(first.accepted and second.accepted and second.duplicate, "E09 repeated command is idempotent")
	_check(game.ledger.balances.player_table == 95 and game.ledger.balances.pot == 5, "E09 repeated bet moves chips once")
	var tx_first := game.ledger.transfer("unique-transfer", "player_table", "pot", 2)
	var tx_second := game.ledger.transfer("unique-transfer", "player_table", "pot", 2)
	_check(tx_first.accepted and tx_second.duplicate and game.ledger.balances.pot == 7, "E09 repeated transaction is idempotent")
	var before := game.ledger.snapshot()
	var negative := game.ledger.transfer("negative", "player_table", "pot", -1)
	var not_int := game.ledger.transfer("not-int", "player_table", "pot", NAN)
	var overdraw := game.ledger.transfer("overdraw", "player_table", "pot", 10000)
	_check(not negative.accepted and not not_int.accepted and not overdraw.accepted, "E09 negative NaN and overbalance rejected")
	_check(game.ledger.balances == before.balances, "E09 invalid amounts leave ledger untouched")
	var collision := game.ledger.transfer("unique-transfer", "player_table", "pot", 3)
	_check(not collision.accepted and collision.reason == "transaction_id_collision", "E09 reused transaction key cannot change meaning")
	_done("E09")

func _test_e10_no_free_draw_and_response_after_third_effect() -> void:
	current_test = "E10"
	var game := _new_game({"first_actor": "player", "ante": 0, "public_effect_pool": ["PE01", "PE02", "PE03"]})
	_check(game.state.phase == "BETTING" and game.ledger.balances.pot == 0, "E10 starts with no free offer")
	_send(game, "player", "check", {})
	_send(game, "opponent", "check", {})
	for index in range(3):
		_check(game.state.phase == "PUBLIC_COMMIT", "E10 public %d opens in order" % (index + 1))
		_send(game, "player", "public_decision", {"activate": false})
		_send(game, "opponent", "public_decision", {"activate": false})
		if index < 2:
			_send(game, game.state.acting_side, "check", {})
			_send(game, game.state.acting_side, "check", {})
	_check(game.state.phase == "BETTING" and game.state.round >= 3, "E10 third effect leaves a normal response round")
	var first_bettor: String = game.state.acting_side
	var second_bettor := "opponent" if first_bettor == "player" else "player"
	_send(game, first_bettor, "bet", {"amount": 5})
	_send(game, second_bettor, "call", {"amount": 5})
	_send(game, "player", "commit_operation", {"operation": "set_arrows", "arrows": [1, 3, 2]})
	_send(game, "opponent", "commit_operation", {"operation": "pass"})
	_check(game.state.phase == "BETTING" and game.state.arrows.player == [1, 3, 2], "E10 operation change is followed by a response round")
	_done("E10")

func _test_e11_snapshot_replay_and_private_offer() -> void:
	current_test = "E11"
	var game := _new_game({"first_actor": "player", "ante": 0, "seed": 412})
	_send(game, "player", "bet", {"amount": 10})
	_send(game, "opponent", "call", {"amount": 10})
	_send(game, "player", "commit_operation", {"operation": "draw_card"})
	_send(game, "opponent", "commit_operation", {"operation": "pass"})
	var p_observation := game.observation("player")
	var o_observation := game.observation("opponent")
	_check(p_observation.your_private.private_offer.size() == 3, "E11 chooser receives three locked candidates")
	_check(o_observation.your_private.private_offer.is_empty(), "E11 opponent cannot see chooser candidates")
	_check(p_observation.opponent_public.team.is_empty() and p_observation.opponent_public.team_sealed, "E11 opponent team is sealed")
	var saved := game.snapshot()
	var restored := _new_game({"first_actor": "player", "ante": 0, "seed": 412})
	_check(restored.restore_snapshot(saved), "E11 committed state restores")
	_check(restored.observation("player").your_private.private_offer == p_observation.your_private.private_offer, "E11 restored candidates are identical")
	_check(restored.state.rng_counter == game.state.rng_counter and restored.ledger.balances.pot == game.ledger.balances.pot, "E11 RNG counter and pot are identical")
	var candidate_id := str(p_observation.your_private.private_offer[0])
	var kind := "equipment" if candidate_id.begins_with("EQ") else "effect"
	var pick_command := SinCommand.new("pick-once", "player", "choose_draft_card", {"card_id": candidate_id, "slot": 1, "slot_kind": kind}, restored.state.revision)
	var first_pick := restored.apply(pick_command)
	var replay_pick := restored.apply(pick_command)
	_check(first_pick.accepted and replay_pick.duplicate, "E11 repeated draft command cannot pick twice")
	_check(restored.state.installed_cards.player.size() == 6, "E11 installed slot state is explicit")
	_done("E11")

func _test_e12_invariants_over_seeded_sequences() -> void:
	current_test = "E12"
	for seed in range(1, 33):
		var game := _new_game({"first_actor": "player" if seed % 2 else "opponent", "ante": 0, "seed": seed, "public_effect_pool": []})
		var pre_total := game.ledger.total_chips()
		if seed % 3 == 0:
			_send(game, game.state.acting_side, "fold", {})
		else:
			if game.state.acting_side == "player":
				_send(game, "player", "bet", {"amount": 5})
				_send(game, "opponent", "call", {"amount": 5})
			else:
				_send(game, "opponent", "bet", {"amount": 5})
				_send(game, "player", "call", {"amount": 5})
			_send(game, "player", "commit_operation", {"operation": "pass"})
			_send(game, "opponent", "commit_operation", {"operation": "pass"})
			if game.state.phase == "BETTING":
				_send(game, game.state.acting_side, "check", {})
				_send(game, game.state.acting_side, "check", {})
			if game.state.phase == "BATTLE_READY":
				game.settle_battle("tie" if seed % 2 else "player")
		game.ledger.assert_invariants()
		_check(game.ledger.total_chips() == pre_total and game.ledger.balances.pot >= 0, "E12 conservation seed %d" % seed)
		if game.state.phase == "SETTLED":
			var leave := SinCommand.new("leave-%d" % seed, "player", "leave_table", {}, game.state.revision)
			var first_leave := game.apply(leave)
			var second_leave := game.apply(leave)
			_check(first_leave.accepted and second_leave.duplicate, "E12 repeated leave is idempotent seed %d" % seed)
			_check(game.ledger.balances.pot == 0, "E12 settled pot empty seed %d" % seed)
	_done("E12")

func _test_review_round_queue_and_seed_privacy() -> void:
	current_test = "REVIEW-QUEUE"
	var game := SinSession.new({"first_actor": "player", "ante": 5, "seed": 9001})
	var unique := {}
	for effect_id: Variant in game.public_effect_pool:
		unique[str(effect_id)] = true
	var player_view := game.observation("player")
	var opponent_view := game.observation("opponent")
	_check(game.public_effect_pool.size() == 3 and unique.size() == 3, "REVIEW exactly three unique effects queued")
	_check(str(player_view.public.rule_id).begins_with("VC") and str(player_view.public.arena_id).begins_with("AR"), "REVIEW rule and base arena are public")
	_check(not player_view.has("seed") and not player_view.has("rng_state") and not player_view.public.has("public_effect_queue"), "REVIEW seed and unrevealed queue stay hidden")
	_check(opponent_view.public.rule_id == player_view.public.rule_id and opponent_view.public.arena_id == player_view.public.arena_id, "REVIEW both sides share public setup")
	_done("REVIEW-QUEUE")

func _test_review_common_ante_and_auction_all_in() -> void:
	current_test = "REVIEW-ANTE-AUCTION"
	var short := _new_game({"ante": 5, "player_table": 4, "opponent_table": 100})
	_check(short.ledger.balances.player_table == 0 and short.ledger.balances.opponent_table == 96 and short.ledger.balances.pot == 8, "REVIEW common min ante is four each")
	_check(short.state.phase == "BATTLE_READY", "REVIEW short ante starts battle early")
	var auction := _open_first_public({"first_actor": "player", "ante": 0, "player_table": 10, "opponent_table": 100})
	_send(auction, "player", "public_decision", {"activate": true})
	_send(auction, "opponent", "public_decision", {"activate": false})
	_send(auction, "player", "public_bid", {"amount": 5})
	_send(auction, "opponent", "public_bid", {"amount": 6})
	_send(auction, "player", "pass_public_bid", {})
	_check(auction.ledger.balances.opponent_table == 94 and auction.ledger.balances.pot == 6, "REVIEW public bid may increase by one")
	var all_in_auction := _open_first_public({"first_actor": "player", "ante": 0, "player_table": 10, "opponent_table": 100})
	_send(all_in_auction, "player", "public_decision", {"activate": true})
	_send(all_in_auction, "opponent", "public_decision", {"activate": false})
	_send(all_in_auction, "player", "public_bid", {"amount": 10})
	_send(all_in_auction, "opponent", "pass_public_bid", {})
	_check(all_in_auction.state.phase == "BATTLE_READY" and all_in_auction.ledger.balances.player_table == 0, "REVIEW auction last-chip payment early-opens battle")
	_check(all_in_auction.state.public_effect_index == 1, "REVIEW later public cards remain unflipped")
	_done("REVIEW-ANTE-AUCTION")

func _test_review_atomicity_fold_privacy_and_legal_actions() -> void:
	current_test = "REVIEW-ATOMIC-PRIVACY"
	var game := _new_game({"first_actor": "player", "ante": 0, "public_effect_pool": ["PE01"]})
	_send(game, "player", "bet", {"amount": 10})
	var before := game.snapshot()
	var decimal_call := game.apply(SinCommand.new("decimal-call", "opponent", "call", {"amount": 5.6}, game.state.revision))
	var string_call := game.apply(SinCommand.new("string-call", "opponent", "call", {"amount": "10"}, game.state.revision))
	_check(not decimal_call.accepted and not string_call.accepted and game.snapshot().ledger == before.ledger, "REVIEW decimal and string calls rejected atomically")
	var min_raise := game.apply(SinCommand.new("small-raise", "opponent", "raise", {"amount": 12}, game.state.revision))
	_check(not min_raise.accepted and game.state.target_bid == 10, "REVIEW ordinary raise still needs five-chip increment")
	_send(game, "opponent", "call", {"amount": 10})
	_send(game, "player", "commit_operation", {"operation": "pass"})
	_send(game, "opponent", "commit_operation", {"operation": "pass"})
	_send(game, "player", "public_decision", {"activate": true})
	var actions := SinLegalActions.list_actions(game.observation("opponent"))
	_check(actions.any(func(action: Dictionary) -> bool: return action.type == "public_decision") and actions.any(func(action: Dictionary) -> bool: return action.type == "fold"), "REVIEW public decision window offers fold separately")
	_send(game, "opponent", "fold", {})
	var player_view := game.observation("player")
	var opponent_view := game.observation("opponent")
	_check(game.state.phase == "SETTLED" and not player_view.public.teams_revealed and player_view.opponent_public.team.is_empty(), "REVIEW fold settlement keeps enemy team hidden")
	_check(player_view.public.balances.pot == 0 and player_view.public.balances.player_table == 110, "REVIEW observation exposes current balances")
	_check(SinLegalActions.list_actions(opponent_view).is_empty(), "REVIEW opponent cannot leave or start next hand")
	var invalid_snapshot := game.snapshot()
	invalid_snapshot.ledger.balances.player_table = -5
	var old_state := game.state.duplicate(true)
	_check(not game.restore_snapshot(invalid_snapshot) and game.state == old_state, "REVIEW invalid restore leaves session untouched")
	_done("REVIEW-ATOMIC-PRIVACY")

func _test_review_double_draw_batch_and_archive() -> void:
	current_test = "REVIEW-DOUBLE-DRAW"
	var pool := ["EQ01", "EQ02", "EQ03"]
	var game := _new_game({"first_actor": "player", "ante": 0, "seed": 71, "draft_pool": pool, "public_effect_pool": ["PE01", "PE02", "PE03"]})
	_send(game, "player", "bet", {"amount": 10})
	_send(game, "opponent", "call", {"amount": 10})
	_send(game, "player", "commit_operation", {"operation": "draw_card"})
	var batch_result := _send(game, "opponent", "commit_operation", {"operation": "draw_card"})
	var player_view := game.observation("player")
	var opponent_view := game.observation("opponent")
	_check(player_view.your_private.private_offer.size() == 3 and opponent_view.your_private.private_offer.size() == 3, "REVIEW both sides receive private candidates")
	_check(player_view.your_private.offer_id == opponent_view.your_private.offer_id, "REVIEW batch shares a stable offer id")
	var p_id := str(player_view.your_private.private_offer[0])
	var o_id := str(opponent_view.your_private.private_offer[0])
	_send(game, "player", "choose_draft_card", {"card_id": p_id, "slot": 1, "slot_kind": "equipment"})
	var pending_actions := SinLegalActions.list_actions(game.observation("player"))
	_check(not pending_actions.any(func(action: Dictionary) -> bool: return action.type == "choose_draft_card") and not pending_actions.any(func(action: Dictionary) -> bool: return action.type == "fold"), "REVIEW submitted chooser has no repeated choice/fold action")
	_check(game.observation("opponent").opponent_public.installed_cards.is_empty(), "REVIEW first pick is not exposed early")
	_send(game, "opponent", "choose_draft_card", {"card_id": o_id, "slot": 3, "slot_kind": "equipment"})
	_check(game.state.installed_cards.player.size() == 6 and game.state.installed_cards.opponent.size() == 6, "REVIEW both installs reveal together")
	_check(game.draft.archive.size() == 1 and game.draft.offers.is_empty() and game.draft.selected.is_empty(), "REVIEW completed offer archived and active draft cleared")
	var event_ids := {}
	for domain_event: Dictionary in batch_result.events:
		event_ids[domain_event.event_id] = true
	_check(event_ids.size() == batch_result.events.size(), "REVIEW event IDs are unique in a batch")
	_send(game, "player", "public_decision", {"activate": false})
	_send(game, "opponent", "public_decision", {"activate": false})
	var first_actor: String = game.state.acting_side
	var second_actor := "opponent" if first_actor == "player" else "player"
	_send(game, first_actor, "bet", {"amount": 5})
	_send(game, second_actor, "call", {"amount": 5})
	_send(game, "player", "commit_operation", {"operation": "draw_card"})
	_send(game, "opponent", "commit_operation", {"operation": "pass"})
	var second_offer: Array = game.observation("player").your_private.private_offer
	_check(second_offer.size() == 3 and second_offer.has("EQ01") and game.observation("player").your_private.offer_id != player_view.your_private.offer_id, "REVIEW later offer may contain a prior ID under a new batch ID")
	var saved := game.snapshot()
	var restored := _new_game({"first_actor": "player", "ante": 0, "seed": 71, "draft_pool": pool, "public_effect_pool": ["PE01", "PE02", "PE03"]})
	_check(restored.restore_snapshot(saved) and restored.observation("player").your_private.private_offer == second_offer, "REVIEW second candidates persist across reload")
	var bad_kind := restored.apply(SinCommand.new("bad-kind", "player", "choose_draft_card", {"card_id": str(second_offer[0]), "slot": 1, "slot_kind": "effect"}, restored.state.revision))
	_check(not bad_kind.accepted and restored.observation("player").your_private.private_offer == second_offer, "REVIEW wrong slot kind cannot consume offer")
	var chosen := restored.apply(SinCommand.new("second-pick", "player", "choose_draft_card", {"card_id": "EQ01", "slot": 3, "slot_kind": "equipment"}, restored.state.revision))
	var repeated := restored.apply(SinCommand.new("second-pick", "player", "choose_draft_card", {"card_id": "EQ01", "slot": 3, "slot_kind": "equipment"}, saved.state.revision))
	_check(chosen.accepted and repeated.duplicate and restored.draft.archive.size() == 2, "REVIEW repeated second pick command does not apply twice")
	_done("REVIEW-DOUBLE-DRAW")

func _test_review_next_hand_loop() -> void:
	current_test = "REVIEW-NEXT-HAND"
	var game := _new_game({"first_actor": "player", "ante": 5, "seed": 830, "public_effect_pool": []})
	var total := game.ledger.total_chips()
	var old_first := game.hand_first_actor
	_send(game, "player", "fold", {})
	var player_table: int = game.ledger.balances.player_table
	var opponent_table: int = game.ledger.balances.opponent_table
	var hand_id: int = game.state.hand_id
	var result := _send(game, "player", "next_hand", {})
	_check(result.accepted and game.state.hand_id == hand_id + 1 and game.state.phase == "BETTING", "REVIEW next hand starts through command")
	_check(game.hand_first_actor != old_first and game.state.round == 0 and game.state.target_bid == 0, "REVIEW first actor reverses and hand state resets")
	_check(game.ledger.balances.player_table == player_table - 5 and game.ledger.balances.opponent_table == opponent_table - 5 and game.ledger.balances.pot == 10, "REVIEW table chips persist and both pay next ante")
	_check(game.ledger.total_chips() == total and game.state.installed_cards.player.is_empty() and game.state.installed_cards.opponent.is_empty(), "REVIEW chip conservation and build reset")
	_check(game.public_effect_pool.size() == 3 and game.state.private.offers.is_empty(), "REVIEW next hand gets a new private three-card queue")
	_done("REVIEW-NEXT-HAND")

func _open_first_public(options: Dictionary) -> SinSession:
	var configuration := options.duplicate(true)
	if not configuration.has("public_effect_pool"):
		configuration.public_effect_pool = ["PE01"]
	var game := _new_game(configuration)
	_send(game, "player", "check", {})
	_send(game, "opponent", "check", {})
	return game

func _new_game(options: Dictionary) -> SinSession:
	serial += 1
	var configuration := {"player_table": 100, "opponent_table": 100, "player_wallet": 0, "opponent_funds": 0, "ante": 5, "first_actor": "player", "seed": serial, "public_effect_pool": []}
	for key: Variant in options:
		configuration[key] = options[key]
	return SinSession.new(configuration)

func _send(game: SinSession, actor: String, action: String, payload: Dictionary) -> Dictionary:
	serial += 1
	var command := SinCommand.new("test-command-%d" % serial, actor, action, payload, int(game.state.revision))
	var result: Dictionary = game.apply(command)
	_check(bool(result.accepted), "command %s/%s accepted (%s)" % [actor, action, result.get("reason", "")])
	return result

func _check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		test_failures[current_test] = int(test_failures.get(current_test, 0)) + 1
		lines.append("FAIL %s %s" % [current_test, description])

func _done(test_id: String) -> void:
	lines.append("%s %s" % ["PASS" if int(test_failures.get(test_id, 0)) == 0 else "FAIL", test_id])
