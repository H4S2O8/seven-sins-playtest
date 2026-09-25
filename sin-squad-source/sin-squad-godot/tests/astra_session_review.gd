extends SceneTree

# Independent acceptance probes: only public commands advance the session.
# No fixture mutates the live phase, ledger, offer or cards to pass a test.
var failures: Array[String] = []
var checks := 0
var sequence := 0

func _init() -> void:
	call_deferred("_run")

func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("ASTRA_FAIL: " + description)

func send(session: SinSession, side: String, action: String, payload: Dictionary = {}) -> Dictionary:
	sequence += 1
	var result := session.apply(SinCommand.new("astra-%d" % sequence, side, action, payload, session.state.revision))
	expect(bool(result.accepted), "%s/%s accepted: %s" % [side, action, result.get("reason", "")])
	expect(session.ledger.assert_invariants(), "money conserved after %s" % action)
	return result

func reject_atomic(session: SinSession, side: String, action: String, payload: Dictionary, description: String) -> void:
	sequence += 1
	var before := var_to_str(session.snapshot())
	var result := session.apply(SinCommand.new("astra-%d" % sequence, side, action, payload, session.state.revision))
	expect(not bool(result.accepted), description + " rejected")
	expect(before == var_to_str(session.snapshot()), description + " leaves exact snapshot unchanged")

func new_session(options: Dictionary = {}) -> SinSession:
	var config := {"seed": 207, "player_table": 100, "opponent_table": 100, "first_actor": "player"}
	config.merge(options, true)
	return SinSession.new(config)

func check_pair(session: SinSession) -> void:
	for unused in range(2):
		if session.state.phase != "BETTING":
			expect(false, "check_pair still has a betting turn")
			return
		send(session, session.state.acting_side, "check")

func resolve_public(session: SinSession) -> void:
	expect(session.state.phase == "PUBLIC_COMMIT", "next card genuinely revealed")
	if session.state.phase != "PUBLIC_COMMIT":
		return
	send(session, "player", "public_decision", {"activate": false})
	send(session, "opponent", "public_decision", {"activate": false})

func _run() -> void:
	# A normal, untouched session reaches battle after exactly three public cards.
	var session := new_session()
	for index in range(3):
		check_pair(session)
		expect(session.state.public_effect_index == index + 1, "public index %d" % (index + 1))
		resolve_public(session)
	check_pair(session)
	expect(session.state.phase == "BATTLE_READY", "three public reveals then mutual checks starts battle")
	expect(session.state.resolved_public_effects.size() == 3, "exactly three resolved public effects")
	expect(session.settle_battle("tie").accepted, "battle can settle")
	expect(session.ledger.balances.player_table == 100 and session.ledger.balances.opponent_table == 100, "tie refunds own actual contributions")
	send(session, "player", "next_hand")
	expect(session.state.hand_id == 2 and session.state.public_effect_index == 0, "next hand resets public progress")
	expect(session.state.installed_cards.player.is_empty(), "next hand has no inherited equipment")

	# all_in is also a response, not just an opening bet.
	for stacks: Array in [[100, 100], [100, 40], [40, 100]]:
		session = new_session({"player_table": stacks[0], "opponent_table": stacks[1]})
		send(session, "player", "all_in")
		send(session, "opponent", "all_in")
		expect(session.state.phase == "BATTLE_READY", "all-in response resolves without a zero-stack turn: %s" % str(stacks))
		expect(session.ledger.balances.pot == 2 * mini(stacks[0], stacks[1]), "all-in matches smaller stack: %s" % str(stacks))
		expect(session.state.contributions.player == session.state.contributions.opponent, "unmatched ordinary wager not kept in pot")

	# Float and string amounts may not be silently truncated by a call.
	session = new_session()
	send(session, "player", "bet", {"amount": 5})
	reject_atomic(session, "opponent", "call", {"amount": 5.9}, "fractional call")
	reject_atomic(session, "opponent", "call", {"amount": "5"}, "string call")
	send(session, "opponent", "call")

	# Entire hand fold is distinct from auction pass; hidden team stays hidden.
	session = new_session()
	check_pair(session)
	send(session, "player", "fold")
	var visible := session.observation("player")
	expect(visible.opponent_public.team.is_empty() and visible.opponent_public.team_sealed, "fold does not reveal enemy team")
	expect(session.ledger.balances.opponent_table == 105, "fold awards both antes only")

	# A chosen draft is not revealed until its opponent commits its selection.
	session = new_session()
	send(session, "player", "bet", {"amount": 10})
	send(session, "opponent", "call")
	send(session, "player", "commit_operation", {"operation": "draw_card"})
	send(session, "opponent", "commit_operation", {"operation": "draw_card"})
	var first_offers: Dictionary = session.state.private.offers.duplicate(true)
	var first_offer_id: String = session.state.private.offer_ids.player
	var card: String = first_offers.player[0]
	var kind := "equipment" if card.begins_with("EQ") else "effect"
	reject_atomic(session, "player", "choose_draft_card", {"card_id": card, "slot": 1, "slot_kind": "effect" if kind == "equipment" else "equipment", "offer_id": first_offer_id}, "wrong slot kind does not consume choice")
	send(session, "player", "choose_draft_card", {"card_id": card, "slot": 1, "slot_kind": kind, "offer_id": first_offer_id})
	expect(session.observation("opponent").opponent_public.installed_cards.is_empty(), "one-sided draft remains concealed until shared commit")
	var already_picked_actions: Array = SinLegalActions.list_actions(session.observation("player"))
	var offers_again := false
	for action: Dictionary in already_picked_actions:
		if action.type == "choose_draft_card":
			offers_again = true
	expect(not offers_again, "legal actions do not offer a second draft choice while waiting")
	card = first_offers.opponent[0]
	kind = "equipment" if card.begins_with("EQ") else "effect"
	send(session, "opponent", "choose_draft_card", {"card_id": card, "slot": 3, "slot_kind": kind, "offer_id": session.state.private.offer_ids.opponent})
	expect(session.state.installed_cards.player.size() == 6, "equipment and effect occupy distinct three-slot arrays")
	resolve_public(session)
	var actor: String = session.state.acting_side
	send(session, actor, "bet", {"amount": 5})
	send(session, "opponent" if actor == "player" else "player", "call")
	send(session, "player", "commit_operation", {"operation": "draw_card"})
	send(session, "opponent", "commit_operation", {"operation": "pass"})
	expect(session.state.private.offer_ids.player != first_offer_id, "a second paid draw gets a new offer identity")
	expect(session.state.phase == "DRAFT_SELECTION", "second draw genuinely waits for selection")
	# No exact card comparison: legitimate three-choice repetition is allowed.
	var saved := session.snapshot()
	var resumed := new_session({"seed": 999})
	expect(resumed.restore_snapshot(saved), "normal snapshot restores")
	expect(var_to_str(resumed.observation("player")) == var_to_str(session.observation("player")), "saved pending offer fully survives restore")
	var invalid := saved.duplicate(true)
	invalid.ledger.balances.pot += 1
	var before_invalid := var_to_str(resumed.snapshot())
	expect(not resumed.restore_snapshot(invalid), "money-inconsistent snapshot rejected")
	expect(before_invalid == var_to_str(resumed.snapshot()), "invalid restore is atomic")
	print("ASTRA_SESSION_REVIEW checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures:
		print(" - " + failure)
	quit(0 if failures.is_empty() else 1)
