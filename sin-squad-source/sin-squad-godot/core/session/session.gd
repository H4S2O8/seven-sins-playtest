class_name SinSession
extends RefCounted

const SIDES := ["player", "opponent"]
const DEFAULT_PE_CARDS := ["PE01", "PE02", "PE03", "PE04", "PE05", "PE06", "PE07", "PE08", "PE09", "PE10",
	"PE11", "PE12", "PE13", "PE14", "PE15", "PE16", "PE17", "PE18", "PE19", "PE20", "PE21", "PE22", "PE23", "PE24", "PE25",
	"PE26", "PE27", "PE28", "PE29", "PE30", "PE31", "PE32", "PE33", "PE34", "PE35", "PE36", "PE37", "PE38", "PE39", "PE40",
	"PE41", "PE42", "PE43", "PE44", "PE45", "PE46", "PE47", "PE48", "PE49", "PE50"]
const DEFAULT_DRAFT_POOL := [
	"EQ01", "EQ02", "EQ03", "EQ04", "EQ05", "EQ06", "EQ07", "EQ08", "EQ09", "EQ10", "EQ11", "EQ12", "EQ13", "EQ14", "EQ15", "EQ16", "EQ17", "EQ18", "EQ19", "EQ20",
	"EQ21", "EQ22", "EQ23", "EQ24", "EQ25", "EQ26", "EQ27", "EQ28", "EQ29", "EQ30", "EQ31", "EQ32", "EQ33", "EQ34", "EQ35", "EQ36", "EQ37", "EQ38", "EQ39", "EQ40", "EQ41", "EQ42", "EQ43", "EQ44", "EQ45", "EQ46", "EQ47", "EQ48", "EQ49", "EQ50",
	"FX01", "FX02", "FX03", "FX04", "FX05", "FX06", "FX07", "FX08", "FX09", "FX10", "FX11", "FX12", "FX13", "FX14", "FX15", "FX16", "FX17", "FX18", "FX19", "FX20",
	"FX21", "FX22", "FX23", "FX24", "FX25", "FX26", "FX27", "FX28", "FX29", "FX30", "FX31", "FX32", "FX33", "FX34", "FX35", "FX36", "FX37", "FX38", "FX39", "FX40", "FX41", "FX42", "FX43", "FX44", "FX45", "FX46", "FX47", "FX48", "FX49", "FX50"]
const AttachmentHandlersScript = preload("res://content/attachments/attachment_handlers.gd")
const EnvironmentHandlersScript = preload("res://content/environment/environment_handlers.gd")
const CHARACTER_HANDLER_SCRIPTS := {
	"WR": preload("res://content/characters/wr_handlers.gd"),
	"GR": preload("res://content/characters/gr_handlers.gd"),
	"GL": preload("res://content/characters/gl_handlers.gd"),
	"EN": preload("res://content/characters/en_handlers.gd"),
	"SL": preload("res://content/characters/sl_handlers.gd"),
	"LU": preload("res://content/characters/lu_handlers.gd"),
	"PR": preload("res://content/characters/pr_handlers.gd")}

var state: Dictionary = {}
var ledger: EconomyLedger
var seed_value := 1
var rng_counter := 0
var first_actor := "player"
var hand_first_actor := "player"
var rng := RandomNumberGenerator.new()
var applied_commands: Dictionary = {}
var draft := SinDraft.new()
var draft_pool: Array = []
var public_effect_pool: Array = []
var team_draft_enabled := false

func _character_pool() -> Array:
	var result: Array = []
	for prefix: String in ["WR", "GR", "GL", "EN", "SL", "LU", "PR"]:
		var handler = CHARACTER_HANDLER_SCRIPTS[prefix].new()
		for index in range(1, 15):
			var content_id := "%s%02d" % [prefix, index]
			if handler.supports_content_id(content_id): result.append(content_id)
	return result

func _supported_draft_pool() -> Array:
	var result: Array = []
	for content_id in DEFAULT_DRAFT_POOL:
		if AttachmentHandlersScript.supports_content_id(str(content_id)): result.append(content_id)
	return result

func _supported_public_effect_pool() -> Array:
	var handler = EnvironmentHandlersScript.new()
	var result: Array = []
	for content_id in DEFAULT_PE_CARDS:
		if handler.supports_content_id(str(content_id)): result.append(content_id)
	return result

func _supported_arena_pool() -> Array:
	var handler = EnvironmentHandlersScript.new()
	var result: Array = []
	for index in range(1, 21):
		var content_id := "AR%02d" % index
		if handler.supports_content_id(content_id): result.append(content_id)
	return result

func _random_supported_arena() -> String:
	var pool := _supported_arena_pool()
	return str(pool[_next_random(pool.size())])

func _init(options: Dictionary = {}) -> void:
	seed_value = int(options.get("seed", 1))
	team_draft_enabled = bool(options.get("team_draft", false)) and not options.has("teams")
	var player_stack := int(options.get("player_table", 100))
	var opponent_stack := int(options.get("opponent_table", 100))
	var player_wallet := int(options.get("player_wallet", 0))
	var opponent_funds := int(options.get("opponent_funds", 0))
	var ante := int(options.get("ante", 5))
	rng.seed = seed_value
	ledger = EconomyLedger.new(player_wallet, player_stack, opponent_funds, opponent_stack)
	draft = SinDraft.new(seed_value ^ 0x5A17, 0)
	draft_pool = options.get("draft_pool", _supported_draft_pool()).duplicate(true)
	if options.has("public_effect_pool"):
		public_effect_pool = options.public_effect_pool.duplicate()
	else:
		var shuffled_effects: Array = _supported_public_effect_pool()
		for effect_index in range(shuffled_effects.size() - 1, 0, -1):
			var swap_index := _next_random(effect_index + 1)
			var swap_value: Variant = shuffled_effects[effect_index]
			shuffled_effects[effect_index] = shuffled_effects[swap_index]
			shuffled_effects[swap_index] = swap_value
		public_effect_pool = shuffled_effects.slice(0, 3)
	if options.has("first_actor"):
		first_actor = str(options.first_actor)
	else:
		first_actor = "player" if _next_random(2) == 0 else "opponent"
	hand_first_actor = first_actor
	var teams: Dictionary = options.get("teams", {}).duplicate(true)
	if not teams.has("player"):
		if not team_draft_enabled: teams.player = _sample_team("player")
	if not teams.has("opponent"):
		if not team_draft_enabled: teams.opponent = _sample_team("opponent")
	var rule_id := "VC%02d" % (_next_random(30) + 1)
	var arena_id := _random_supported_arena()
	state = {
		"schema_version": 1, "seed": seed_value, "rng_counter": rng_counter, "revision": 0, "hand_id": 1,
		"rule_id": rule_id, "arena_id": arena_id,
		"phase": "BETTING", "round": 0, "acting_side": first_actor, "round_paid": {"player": 0, "opponent": 0},
		"target_bid": 0, "checked": {}, "contributions": {"player": 0, "opponent": 0}, "hand_start_contributions": {"player": 0, "opponent": 0},
		"revealed_effects": [], "resolved_public_effects": [], "public_effect_index": 0, "public_commits": {}, "public_bid": 0, "public_bidder": "", "public_wanted_active": false,
		"operation_commits": {}, "operation_batch_fee": 0, "draft_selection_commits": {}, "installed_cards": {"player": [], "opponent": []},
		"configuration_changed": false,
		"arrows": {"player": [1, 2, 3], "opponent": [1, 2, 3]}, "battle_result": {},
		"teams_revealed": false, "event_counter": 0, "left_table": false, "team_selection_commits": {},
		"private": {"teams": teams, "offers": {}, "offer_ids": {}, "operation_commits": {}, "draft_selection_commits": {}, "pending_configuration": {}, "team_selection": {}}
	}
	if team_draft_enabled:
		var team_offer := draft.begin_character_batch("hand-1-team-selection", _character_pool())
		if not bool(team_offer.get("accepted", false)):
			team_draft_enabled = false
			state.private.teams = {"player": _sample_team("player"), "opponent": _sample_team("opponent")}
		else:
			state.phase = "TEAM_SELECTION"
			state.acting_side = ""
	var common_ante: int = mini(ante, mini(int(ledger.balances.player_table), int(ledger.balances.opponent_table)))
	for side: String in SIDES:
		var stack_account := _table_account(side)
		var paid_ante: int = common_ante
		if paid_ante > 0:
			ledger.transfer("hand-1-ante-" + side, stack_account, "pot", paid_ante)
			state.contributions[side] = paid_ante
	state.hand_start_contributions = state.contributions.duplicate(true)
	state.rng_counter = rng_counter
	if common_ante < ante or int(ledger.balances.player_table) == 0 or int(ledger.balances.opponent_table) == 0:
		state.team_selection_battle_ready = team_draft_enabled
		if team_draft_enabled:
			ledger.initial_total = ledger.total_chips()
			return
		state.phase = "BATTLE_READY"
		state.acting_side = ""
	ledger.initial_total = ledger.total_chips()

func apply(command: SinCommand) -> Dictionary:
	if command == null or command.command_id.is_empty():
		return _reject("empty_command_id")
	var fingerprint := command.fingerprint()
	if applied_commands.has(command.command_id):
		var previous: Dictionary = applied_commands[command.command_id]
		if previous.fingerprint != fingerprint:
			return _reject("command_id_collision")
		var repeated: Dictionary = previous.result.duplicate(true)
		repeated.duplicate = true
		return repeated
	if command.expected_revision >= 0 and command.expected_revision != int(state.revision):
		return _reject("stale_revision")
	if command.actor not in SIDES:
		return _reject("invalid_actor")
	var before_revision := int(state.revision)
	var before: Dictionary = snapshot()
	var events: Array[Dictionary] = []
	var result := _dispatch(command, events)
	if not bool(result.accepted):
		restore_snapshot(before)
		result.revision = before_revision
		return result
	if bool(result.accepted):
		state.revision = before_revision + 1
		state.rng_counter = rng_counter
		result.revision = state.revision
		result.events = events.duplicate(true)
		result.duplicate = false
		ledger.assert_invariants()
		applied_commands[command.command_id] = {"fingerprint": fingerprint, "result": result.duplicate(true)}
	return result

func observation(side: String) -> Dictionary:
	var observed_state := state.duplicate(true)
	observed_state["ledger"] = ledger.snapshot()
	observed_state["draft_character_offers"] = draft.character_offers.duplicate(true)
	observed_state["draft_character_history"] = draft.character_history.duplicate(true)
	observed_state["draft_character_rerolls"] = draft.character_rerolls.duplicate(true)
	return SinObservation.for_side(observed_state, side)

func snapshot() -> Dictionary:
	return {"state": state.duplicate(true), "ledger": ledger.snapshot(), "seed_value": seed_value, "rng_counter": rng_counter, "rng_state": rng.state,
		"first_actor": first_actor, "hand_first_actor": hand_first_actor, "applied_commands": applied_commands.duplicate(true), "draft": draft.snapshot(),
		"draft_pool": draft_pool.duplicate(true), "public_effect_pool": public_effect_pool.duplicate(true), "team_draft_enabled": team_draft_enabled}

func restore_snapshot(data: Dictionary) -> bool:
	if not _snapshot_valid(data):
		return false
	var new_state: Dictionary = data.state.duplicate(true)
	var ledger_data: Dictionary = data.ledger
	var new_ledger := EconomyLedger.new()
	new_ledger.balances = ledger_data.balances.duplicate(true)
	new_ledger.initial_total = int(ledger_data.initial_total)
	new_ledger.transactions = ledger_data.transactions.duplicate(true)
	new_ledger.transaction_log.assign(ledger_data.transaction_log)
	var draft_data: Dictionary = data.draft
	var new_draft := SinDraft.new()
	if not new_draft.restore(draft_data):
		return false
	if not new_ledger.assert_invariants():
		return false
	state = new_state
	ledger = new_ledger
	seed_value = int(data.seed_value)
	rng_counter = int(data.rng_counter)
	rng.seed = int(data.seed_value)
	rng.state = int(data.rng_state)
	first_actor = str(data.first_actor)
	hand_first_actor = str(data.get("hand_first_actor", first_actor))
	applied_commands = data.applied_commands.duplicate(true)
	draft = new_draft
	draft_pool = data.draft_pool.duplicate(true)
	public_effect_pool = data.public_effect_pool.duplicate(true)
	team_draft_enabled = bool(data.get("team_draft_enabled", false))
	return ledger.assert_invariants()

func _dispatch(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	match command.type:
		"fold":
			return _fold_action(command, events)
		"check", "bet", "raise", "call", "all_in":
			return _betting_action(command, events)
		"commit_operation":
			return _commit_operation(command, events)
		"choose_draft_card":
			return _choose_draft(command, events)
		"choose_character":
			return _choose_character(command, events)
		"reroll_character":
			return _reroll_character(command, events)
		"public_decision":
			return _public_decision(command, events)
		"public_bid", "pass_public_bid":
			return _public_bid_action(command, events)
		"leave_table":
			return _leave_table(command, events)
		"next_hand":
			if command.actor != "player":
				return _reject("only_player_can_start_next_hand")
			return _start_next_hand(events)
		_:
			return _reject("unknown_command")

func _fold_action(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	var side: String = command.actor
	var allowed := false
	match str(state.phase):
		"BETTING":
			allowed = state.acting_side == side
		"OPERATION_COMMIT":
			allowed = not state.operation_commits.has(side)
		"DRAFT_SELECTION":
			allowed = side in state.pending_draft_sides and not state.draft_selection_commits.has(side)
		"TEAM_SELECTION":
			allowed = not state.team_selection_commits.has(side)
		"PUBLIC_COMMIT":
			allowed = not state.public_commits.has(side)
		"PUBLIC_BID":
			allowed = state.acting_side == side
	if not allowed:
		return _reject("not_a_legal_fold_window")
	return _settle(side, "fold", _other(side), events)

func _betting_action(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	if state.phase != "BETTING" or state.acting_side != command.actor:
		return _reject("not_betting_turn")
	var side: String = command.actor
	var other := _other(side)
	var paid: int = int(state.round_paid[side])
	var target: int = int(state.target_bid)
	var stack: int = int(ledger.balances[_table_account(side)])
	if command.type == "fold":
		return _settle(side, "fold", other, events)
	if command.type == "check":
		if target != 0 or paid != 0:
			return _reject("cannot_check_with_bet_or_credit")
		state.checked[side] = true
		events.append(_event("check", side, {"round": state.round}))
		if bool(state.checked.get(other, false)):
			state.checked.clear()
			return _after_matched_betting(events, 0)
		state.acting_side = other
		return _accepted("check_submitted")
	if command.type == "bet":
		if target != 0 or paid != 0:
			return _reject("bet_requires_unopened_round")
		var amount: Variant = command.payload.get("amount", -1)
		if not _amount_is_int(amount) or amount <= 0 or amount > stack:
			return _reject("invalid_bet_amount")
		if amount < 5 and amount != stack:
			return _reject("below_minimum_unless_all_in")
		return _pay_bet(side, int(amount), command.command_id, other, events, "bet")
	if command.type == "raise":
		if target <= 0:
			return _reject("raise_requires_open_bet")
		if not str(state.get("all_in_side", "")).is_empty():
			return _reject("cannot_raise_against_all_in")
		var total: Variant = command.payload.get("amount", -1)
		if not _amount_is_int(total) or total <= target or total - paid > stack:
			return _reject("invalid_raise_amount")
		if total - target < 5 and not bool(command.payload.get("all_in", false)):
			return _reject("raise_increment_below_five")
		if total - paid < stack and bool(command.payload.get("all_in", false)):
			return _reject("all_in_must_use_entire_stack")
		return _pay_bet(side, int(total) - paid, command.command_id, other, events, "raise", int(total))
	if command.type == "call":
		var owed := maxi(0, target - paid)
		if owed == 0:
			return _reject("nothing_to_call")
		if stack < owed:
			if stack <= 0 or not bool(command.payload.get("all_in", false)):
				return _reject("short_call_must_be_all_in")
			var short_amount: Variant = command.payload.get("amount", stack)
			if not _amount_is_int(short_amount) or int(short_amount) != stack:
				return _reject("all_in_call_must_use_integer_stack")
			var short_paid := stack
			var result := _pay_bet(side, short_paid, command.command_id, other, events, "all_in_call")
			if result.accepted:
				_refund_unmatched_round(side, other, events)
				return _after_matched_betting(events, mini(int(state.round_paid.player), int(state.round_paid.opponent)), true)
			return result
		var call_amount: Variant = command.payload.get("amount", owed)
		if not _amount_is_int(call_amount) or int(call_amount) != owed:
			return _reject("call_must_match_exact_integer_difference")
		var result := _pay_bet(side, owed, command.command_id, other, events, "call")
		if result.accepted:
			var matched := int(state.round_paid.player) == int(state.round_paid.opponent)
			var forced := int(ledger.balances[_table_account(side)]) == 0 or not str(state.get("all_in_side", "")).is_empty()
			if forced:
				_refund_unmatched_round(side, other, events)
				return _after_matched_betting(events, mini(int(state.round_paid.player), int(state.round_paid.opponent)), true)
			if matched:
				return _after_matched_betting(events, int(state.target_bid))
		return result
	if command.type == "all_in":
		if stack <= 0:
			return _reject("no_chips_to_go_all_in")
		var already_all_in: String = str(state.get("all_in_side", ""))
		var new_paid := paid + stack
		var result := _pay_bet(side, stack, command.command_id, other, events, "all_in", new_paid)
		if not result.accepted:
			return result
		if not already_all_in.is_empty() and already_all_in != side:
			var player_paid: int = int(state.round_paid.player)
			var opponent_paid: int = int(state.round_paid.opponent)
			if player_paid < opponent_paid:
				_refund_unmatched_round("player", "opponent", events)
			elif opponent_paid < player_paid:
				_refund_unmatched_round("opponent", "player", events)
			return _after_matched_betting(events, mini(int(state.round_paid.player), int(state.round_paid.opponent)), true)
		state.all_in_side = side
		state.acting_side = other
		if target > 0 and new_paid <= target:
			_refund_unmatched_round(side, other, events)
			return _after_matched_betting(events, mini(int(state.round_paid.player), int(state.round_paid.opponent)), true)
		return result
	return _reject("unsupported_betting_action")

func _pay_bet(side: String, amount: int, command_id: String, other: String, events: Array[Dictionary], label: String, new_total: int = -1) -> Dictionary:
	var payment := ledger.transfer("command-" + command_id, _table_account(side), "pot", amount)
	if not payment.accepted:
		return _reject(str(payment.reason))
	state.round_paid[side] = int(state.round_paid[side]) + amount
	state.contributions[side] = int(state.contributions[side]) + amount
	if new_total >= 0:
		state.round_paid[side] = new_total
	state.target_bid = maxi(int(state.target_bid), int(state.round_paid[side]))
	if int(ledger.balances[_table_account(side)]) == 0:
		state.all_in_side = side
	events.append(_event(label, side, {"amount": amount, "round_total": state.round_paid[side], "pot": ledger.balances.pot}))
	state.acting_side = other
	return _accepted(label + "_paid")

func _after_matched_betting(events: Array[Dictionary], matched_total: int, forced_all_in: bool = false) -> Dictionary:
	state.target_bid = matched_total
	state.round_paid = {"player": matched_total, "opponent": matched_total}
	state.checked.clear()
	if forced_all_in or int(ledger.balances.player_table) == 0 or int(ledger.balances.opponent_table) == 0:
		state.phase = "BATTLE_READY"
		state.acting_side = ""
		events.append(_event("battle_ready", "system", {"reason": "all_in_or_zero_stack"}))
		return _accepted("battle_ready")
	if matched_total > 0:
		state.phase = "OPERATION_COMMIT"
		state.operation_batch_fee = matched_total
		state.operation_commits.clear()
		state.private.operation_commits.clear()
		return _accepted("operation_commit_open")
	return _complete_betting_round(events)

func _commit_operation(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	if state.phase != "OPERATION_COMMIT" or state.operation_commits.has(command.actor):
		return _reject("operation_commit_closed_or_already_submitted")
	var operation := str(command.payload.get("operation", ""))
	if operation not in ["pass", "draw_card", "move_card", "set_arrows"]:
		return _reject("unknown_operation")
	var fee: int = int(state.operation_batch_fee)
	var stack: int = int(ledger.balances[_table_account(command.actor)])
	if operation != "pass" and (fee <= 0 or stack < fee):
		return _reject("operation_fee_unaffordable")
	if operation == "set_arrows":
		var arrows: Variant = command.payload.get("arrows", [])
		if not arrows is Array or arrows.size() != 3:
			return _reject("arrows_require_three_slots")
		for arrow: Variant in arrows:
			if not arrow is int or arrow < 1 or arrow > 3:
				return _reject("invalid_arrow_target")
	if operation == "move_card" and not _valid_move(command.actor, command.payload):
		return _reject("invalid_card_move")
	var record := {"operation": operation, "payload": command.payload.duplicate(true), "fee": fee if operation != "pass" else 0}
	state.operation_commits[command.actor] = {"submitted": true}
	state.private.operation_commits[command.actor] = record
	events.append(_event("operation_committed_private", command.actor, {"submitted": true}))
	if state.operation_commits.size() < 2:
		return _accepted("operation_private_commit_saved")
	var batch_offer_id := "hand-%d-round-%d-revision-%d" % [state.hand_id, state.round, state.revision + 1]
	draft.begin_batch(batch_offer_id)
	state.operation_batch_offer_id = batch_offer_id
	for side: String in SIDES:
		var intent: Dictionary = state.private.operation_commits[side]
		if intent.operation != "pass":
			var payment := ledger.transfer("operation-%d-%s" % [state.revision + 1, side], _table_account(side), "pot", fee)
			if not payment.accepted:
				return _reject("operation_fee_payment_failed")
			state.contributions[side] = int(state.contributions[side]) + fee
			events.append(_event("operation_fee_paid", side, {"amount": fee, "pot": ledger.balances.pot}))
			if int(ledger.balances[_table_account(side)]) == 0:
				state.operation_batch_all_in = true
	for side: String in SIDES:
		var intent: Dictionary = state.private.operation_commits[side]
		match str(intent.operation):
			"draw_card":
				var offer := draft.draw(side, draft_pool)
				if not offer.accepted:
					return _reject("draft_failed:" + str(offer.reason))
				state.private.offers[side] = offer.cards.duplicate(true)
				state.private.offer_ids[side] = str(offer.offer_id)
			"move_card", "set_arrows":
				state.private.pending_configuration[side] = {"operation": str(intent.operation), "payload": intent.payload.duplicate(true)}
	state.phase = "DRAFT_SELECTION"
	state.draft_selection_commits.clear()
	state.private.draft_selection_commits.clear()
	state.pending_draft_sides = []
	for side: String in SIDES:
		if state.private.offers.has(side):
			state.pending_draft_sides.append(side)
	if state.pending_draft_sides.is_empty():
		return _finish_operation_batch(events)
	return _accepted("operation_batch_revealed")

func _choose_draft(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	if state.phase != "DRAFT_SELECTION" or command.actor not in state.pending_draft_sides or state.draft_selection_commits.has(command.actor):
		return _reject("draft_selection_closed")
	var card_id := str(command.payload.get("card_id", ""))
	var slot: Variant = command.payload.get("slot", -1)
	var slot_kind := str(command.payload.get("slot_kind", ""))
	if not slot is int:
		return _reject("slot_must_be_integer")
	if int(slot) < 1 or int(slot) > 3:
		return _reject("external_slot_must_be_1_to_3")
	var expected_kind := _card_slot_kind(card_id)
	if expected_kind.is_empty() or expected_kind != slot_kind or not _offer_contains(command.actor, card_id):
		return _reject("card_not_in_offer_or_slot_type_mismatch")
	var selection := draft.choose(command.actor, card_id, int(slot), slot_kind)
	if not selection.accepted:
		return _reject(str(selection.reason))
	state.draft_selection_commits[command.actor] = {"submitted": true}
	state.private.draft_selection_commits[command.actor] = selection.selected.duplicate(true)
	if state.draft_selection_commits.size() < state.pending_draft_sides.size():
		return _accepted("draft_choice_private_commit_saved")
	return _finish_operation_batch(events)

func _choose_character(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	if state.phase != "TEAM_SELECTION" or state.team_selection_commits.has(command.actor):
		return _reject("team_selection_closed_or_already_submitted")
	var slot: Variant = command.payload.get("slot", -1)
	var character_id := str(command.payload.get("character_id", ""))
	if not slot is int or int(slot) < 1 or int(slot) > 3 or character_id.is_empty():
		return _reject("invalid_character_selection")
	var selection := draft.choose_character(command.actor, int(slot), character_id)
	if not bool(selection.get("accepted", false)):
		return _reject(str(selection.get("reason", "character_selection_rejected")))
	var picks: Dictionary = state.private.team_selection.get(command.actor, {}).duplicate(true)
	picks[str(slot)] = character_id
	state.private.team_selection[command.actor] = picks.duplicate(true)
	events.append(_event("character_selected_private", command.actor, {"slot": int(slot), "submitted": true}))
	if picks.size() < 3: return _accepted("character_selection_saved")
	state.team_selection_commits[command.actor] = {"submitted": true}
	if state.team_selection_commits.size() < SIDES.size(): return _accepted("character_selection_side_complete")
	for side: String in SIDES:
		var team: Array = []
		var side_picks: Dictionary = state.private.team_selection[side]
		for position in [1, 2, 3]: team.append({"slot": position, "definition_id": str(side_picks[str(position)])})
		state.private.teams[side] = team
	state.phase = "BATTLE_READY" if bool(state.get("team_selection_battle_ready", false)) else "BETTING"
	state.acting_side = "" if state.phase == "BATTLE_READY" else first_actor
	events.append(_event("team_selection_completed", "system", {"hand_id": int(state.hand_id)}))
	return _accepted("team_selection_completed")

func _reroll_character(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	if state.phase != "TEAM_SELECTION" or state.team_selection_commits.has(command.actor):
		return _reject("team_selection_closed_or_already_submitted")
	var slot: Variant = command.payload.get("slot", -1)
	if not slot is int or int(slot) < 1 or int(slot) > 3: return _reject("invalid_character_position")
	var result := draft.reroll_character(command.actor, int(slot), _character_pool())
	if not bool(result.get("accepted", false)): return _reject(str(result.get("reason", "character_reroll_rejected")))
	events.append(_event("character_rerolled_private", command.actor, {"slot": int(slot), "reroll_used": true}))
	return _accepted("character_rerolled")

func _finish_operation_batch(events: Array[Dictionary]) -> Dictionary:
	var changed := false
	for side: String in SIDES:
		var staged: Dictionary = state.private.pending_configuration.get(side, {})
		var has_pick: bool = state.private.draft_selection_commits.has(side)
		if staged.is_empty() and not has_pick:
			continue
		changed = true
		var installed: Array = state.installed_cards[side].duplicate(true)
		while installed.size() < 6:
			installed.append("")
		var arrows: Array = state.arrows[side].duplicate()
		if staged.get("operation", "") == "move_card":
			_apply_move_to(installed, staged.payload)
		elif staged.get("operation", "") == "set_arrows":
			arrows = staged.payload.arrows.duplicate()
		var replaced := ""
		if has_pick:
			var pick: Dictionary = state.private.draft_selection_commits[side]
			var index: int = int(pick.slot) - 1 if pick.slot_kind == "equipment" else 2 + int(pick.slot)
			replaced = str(installed[index])
			installed[index] = str(pick.card_id)
		state.installed_cards[side] = installed
		state.arrows[side] = arrows
		if has_pick:
			var published_pick: Dictionary = state.private.draft_selection_commits[side]
			events.append(_event("draft_card_installed", side, {"offer_id": published_pick.offer_id, "card_id": published_pick.card_id,
				"slot": published_pick.slot, "slot_kind": published_pick.slot_kind, "replaced": replaced}))
		elif staged.get("operation", "") == "move_card":
			events.append(_event("card_moved", side, staged.payload.duplicate(true)))
		elif staged.get("operation", "") == "set_arrows":
			events.append(_event("arrows_changed", side, {"arrows": arrows.duplicate()}))
	state.configuration_changed = changed
	draft.archive_batch()
	state.private.offers.clear()
	state.private.offer_ids.clear()
	state.private.operation_commits.clear()
	state.private.draft_selection_commits.clear()
	state.private.pending_configuration.clear()
	state.operation_commits.clear()
	state.draft_selection_commits.clear()
	if bool(state.get("operation_batch_all_in", false)):
		state.phase = "BATTLE_READY"
		state.acting_side = ""
		state.operation_batch_all_in = false
		events.append(_event("battle_ready", "system", {"reason": "completed_committed_operation_batch"}))
		return _accepted("battle_ready_after_operations")
	return _complete_betting_round(events)

func _complete_betting_round(events: Array[Dictionary]) -> Dictionary:
	first_actor = _other(first_actor)
	state.round += 1
	state.round_paid = {"player": 0, "opponent": 0}
	state.target_bid = 0
	state.checked.clear()
	state.all_in_side = ""
	if int(state.public_effect_index) < public_effect_pool.size():
		var effect_id := str(public_effect_pool[int(state.public_effect_index)])
		state.public_effect_index = int(state.public_effect_index) + 1
		state.current_public_effect = effect_id
		state.public_commits.clear()
		state.phase = "PUBLIC_COMMIT"
		state.acting_side = ""
		events.append(_event("public_effect_revealed", "system", {"effect_id": effect_id, "index": state.public_effect_index}))
		return _accepted("public_effect_commit_open")
	if bool(state.configuration_changed):
		state.configuration_changed = false
		return _begin_betting_round(events)
	state.phase = "BATTLE_READY"
	state.acting_side = ""
	events.append(_event("battle_ready", "system", {"reason": "both_passed_after_public_effects"}))
	return _accepted("battle_ready")

func _begin_betting_round(events: Array[Dictionary]) -> Dictionary:
	state.phase = "BETTING"
	state.acting_side = first_actor
	state.configuration_changed = false
	state.round_paid = {"player": 0, "opponent": 0}
	state.target_bid = 0
	state.checked.clear()
	events.append(_event("next_betting_round", "system", {"round": state.round, "first_actor": first_actor}))
	return _accepted("next_betting_round")

func _public_decision(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	if state.phase != "PUBLIC_COMMIT" or state.public_commits.has(command.actor):
		return _reject("public_commit_closed_or_duplicate")
	if not command.payload.get("activate", null) is bool:
		return _reject("activate_must_be_boolean")
	state.public_commits[command.actor] = bool(command.payload.activate)
	if state.public_commits.size() < 2:
		return _accepted("public_choice_private_commit_saved")
	var player_choice: bool = state.public_commits.player
	var opponent_choice: bool = state.public_commits.opponent
	if player_choice == opponent_choice:
		if player_choice:
			state.revealed_effects.append(str(state.current_public_effect))
		state.resolved_public_effects.append({"id": str(state.current_public_effect), "active": player_choice, "paid": 0, "winner": ""})
		events.append(_event("public_effect_resolved", "system", {"effect_id": state.current_public_effect, "active": player_choice, "paid": 0}))
		return _begin_betting_round(events)
	state.phase = "PUBLIC_BID"
	state.public_bid = 0
	state.public_bidder = ""
	state.public_wanted_active = player_choice
	state.acting_side = "player" if player_choice else "opponent"
	return _accepted("public_bidding_open")

func _public_bid_action(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	if state.phase != "PUBLIC_BID" or state.acting_side != command.actor:
		return _reject("not_public_bid_turn")
	var stack: int = int(ledger.balances[_table_account(command.actor)])
	if command.type == "pass_public_bid":
		if int(state.public_bid) == 0:
			events.append(_event("public_bid_declined", command.actor, {"effect_id": state.current_public_effect, "paid": 0}))
			return _resolve_public_effect(false, 0, "", events)
		var winner := str(state.public_bidder)
		var amount := int(state.public_bid)
		var pay := ledger.transfer("public-auction-%d" % state.revision, _table_account(winner), "pot", amount)
		if not pay.accepted:
			return _reject("public_bid_payment_failed")
		state.contributions[winner] = int(state.contributions[winner]) + amount
		return _resolve_public_effect(bool(state.public_wanted_active), amount, winner, events)
	var amount_variant: Variant = command.payload.get("amount", -1)
	if not _amount_is_int(amount_variant) or amount_variant < maxi(5, int(state.public_bid) + 1) or amount_variant > stack:
		return _reject("invalid_public_bid")
	if amount_variant < 5:
		return _reject("public_bid_minimum_five")
	state.public_bid = int(amount_variant)
	state.public_bidder = command.actor
	state.public_wanted_active = command.actor == ("player" if state.public_commits.player else "opponent")
	state.acting_side = _other(command.actor)
	events.append(_event("public_bid_submitted", command.actor, {"quote": amount_variant, "effect_id": state.current_public_effect}))
	return _accepted("public_bid_submitted")

func _resolve_public_effect(active: bool, paid: int, winner: String, events: Array[Dictionary]) -> Dictionary:
	if active:
		state.revealed_effects.append(str(state.current_public_effect))
	state.resolved_public_effects.append({"id": str(state.current_public_effect), "active": active, "paid": paid, "winner": winner})
	events.append(_event("public_effect_resolved", "system", {"effect_id": state.current_public_effect, "active": active, "paid": paid, "winner": winner}))
	state.public_commits.clear()
	state.public_bid = 0
	state.public_bidder = ""
	if not winner.is_empty() and int(ledger.balances[_table_account(winner)]) == 0:
		state.phase = "BATTLE_READY"
		state.acting_side = ""
		events.append(_event("battle_ready", "system", {"reason": "public_bidder_spent_last_chip"}))
		return _accepted("battle_ready_after_public_bid")
	return _begin_betting_round(events)

func _settle(folding_side: String, reason: String, winner: String, events: Array[Dictionary]) -> Dictionary:
	if state.phase in ["SETTLED", "BATTLE_READY"]:
		return _reject("hand_not_settleable")
	var pot := int(ledger.balances.pot)
	if reason == "fold":
		if pot > 0:
			var award := ledger.transfer("settle-%d-fold" % state.hand_id, "pot", _table_account(winner), pot)
			if not award.accepted:
				return _reject("pot_award_failed")
	else:
		return _reject("unsupported_settlement_reason")
	state.phase = "SETTLED"
	state.acting_side = ""
	state.teams_revealed = false
	var income := {"player": 0, "opponent": 0}
	income[winner] = pot
	state.battle_result = {"reason": reason, "winner": winner, "folding_side": folding_side,
		"invested": state.contributions.duplicate(true), "pot_awarded": pot,
		"net": {"player": int(income.player) - int(state.contributions.player), "opponent": int(income.opponent) - int(state.contributions.opponent)}}
	events.append(_event("hand_settled", "system", state.battle_result.duplicate(true)))
	return _accepted("hand_settled")

func settle_battle(winner: String) -> Dictionary:
	if state.phase != "BATTLE_READY" or winner not in SIDES + ["tie"]:
		return _reject("battle_not_ready_or_invalid_result")
	var events: Array[Dictionary] = []
	var pot := int(ledger.balances.pot)
	if winner == "tie":
		for side: String in SIDES:
			var amount: int = int(state.contributions[side])
			if amount > 0:
				var refund := ledger.transfer("settle-%d-tie-%s" % [state.hand_id, side], "pot", _table_account(side), amount)
				if not refund.accepted:
					return _reject("tie_refund_failed")
	else:
		if pot > 0:
			var award := ledger.transfer("settle-%d-winner" % state.hand_id, "pot", _table_account(winner), pot)
			if not award.accepted:
				return _reject("pot_award_failed")
	state.phase = "SETTLED"
	state.acting_side = ""
	state.teams_revealed = true
	var income := {"player": 0, "opponent": 0}
	if winner == "tie":
		income = state.contributions.duplicate(true)
	else:
		income[winner] = pot
	state.battle_result = {"reason": "tie" if winner == "tie" else "battle", "winner": winner,
		"invested": state.contributions.duplicate(true), "pot_awarded": pot if winner != "tie" else 0, "refund": income,
		"net": {"player": int(income.player) - int(state.contributions.player), "opponent": int(income.opponent) - int(state.contributions.opponent)}}
	events.append(_event("hand_settled", "system", state.battle_result.duplicate(true)))
	state.revision += 1
	ledger.assert_invariants()
	return {"accepted": true, "reason": "hand_settled", "revision": state.revision, "events": events, "duplicate": false}

func _leave_table(command: SinCommand, events: Array[Dictionary]) -> Dictionary:
	if command.actor != "player":
		return _reject("only_player_can_leave_table")
	if state.phase != "SETTLED":
		return _reject("cannot_leave_before_settlement")
	if bool(state.get("left_table", false)):
		return _reject("already_left_table")
	for side: String in SIDES:
		var from := _table_account(side)
		var to := "player_wallet" if side == "player" else "opponent_funds"
		var amount: int = int(ledger.balances[from])
		if amount > 0:
			var returned := ledger.transfer("leave-%d-%s" % [state.hand_id, side], from, to, amount)
			if not returned.accepted:
				return _reject("table_return_failed")
	state.left_table = true
	state.revision += 1
	events.append(_event("table_left", "system", {"player_wallet": ledger.balances.player_wallet, "pot": ledger.balances.pot}))
	return {"accepted": true, "reason": "table_left", "revision": state.revision, "events": events, "duplicate": false}

func _start_next_hand(events: Array[Dictionary]) -> Dictionary:
	if state.phase != "SETTLED" or bool(state.get("left_table", false)):
		return _reject("next_hand_requires_settled_active_table")
	if int(ledger.balances.player_table) <= 0 or int(ledger.balances.opponent_table) <= 0:
		return _reject("room_over_no_chips")
	hand_first_actor = _other(hand_first_actor)
	first_actor = hand_first_actor
	var hand_id := int(state.hand_id) + 1
	var rule_id := "VC%02d" % (_next_random(30) + 1)
	var arena_id := _random_supported_arena()
	var teams := {"player": _sample_team("player"), "opponent": _sample_team("opponent")}
	state = {"schema_version": 1, "seed": seed_value, "rng_counter": rng_counter, "revision": state.revision,
		"hand_id": hand_id, "rule_id": rule_id, "arena_id": arena_id, "phase": "BETTING", "round": 0,
		"acting_side": first_actor, "round_paid": {"player": 0, "opponent": 0}, "target_bid": 0, "checked": {},
		"contributions": {"player": 0, "opponent": 0}, "hand_start_contributions": {"player": 0, "opponent": 0},
		"revealed_effects": [], "resolved_public_effects": [], "public_effect_index": 0, "public_commits": {}, "public_bid": 0,
		"public_bidder": "", "public_wanted_active": false, "operation_commits": {}, "operation_batch_fee": 0,
		"draft_selection_commits": {}, "installed_cards": {"player": [], "opponent": []}, "configuration_changed": false,
		"arrows": {"player": [1, 2, 3], "opponent": [1, 2, 3]}, "battle_result": {}, "teams_revealed": false,
		"event_counter": 0, "left_table": false, "private": {"teams": teams, "offers": {}, "offer_ids": {},
		"operation_commits": {}, "draft_selection_commits": {}, "pending_configuration": {}}}
	var shuffled_effects: Array = _supported_public_effect_pool()
	for effect_index in range(shuffled_effects.size() - 1, 0, -1):
		var swap_index := _next_random(effect_index + 1)
		var swap_value: Variant = shuffled_effects[effect_index]
		shuffled_effects[effect_index] = shuffled_effects[swap_index]
		shuffled_effects[swap_index] = swap_value
	public_effect_pool = shuffled_effects.slice(0, 3)
	var common_ante: int = mini(5, mini(int(ledger.balances.player_table), int(ledger.balances.opponent_table)))
	for side: String in SIDES:
		if common_ante > 0:
			var posted := ledger.transfer("hand-%d-ante-%s" % [hand_id, side], _table_account(side), "pot", common_ante)
			if not posted.accepted:
				return _reject("next_hand_ante_failed")
			state.contributions[side] = common_ante
	state.hand_start_contributions = state.contributions.duplicate(true)
	state.rng_counter = rng_counter
	if common_ante < 5 or int(ledger.balances.player_table) == 0 or int(ledger.balances.opponent_table) == 0:
		state.phase = "BATTLE_READY"
		state.acting_side = ""
	events.append(_event("next_hand_started", "system", {"hand_id": hand_id, "ante_each": common_ante}))
	return _accepted("next_hand_started")

func _refund_unmatched_round(depleted_side: String, other_side: String, events: Array[Dictionary]) -> void:
	var depleted_total: int = int(state.round_paid[depleted_side])
	var other_total: int = int(state.round_paid[other_side])
	if other_total > depleted_total:
		var refund_amount := other_total - depleted_total
		var refund := ledger.transfer("hand-%d-round-refund-%d-%s" % [state.hand_id, state.round, other_side], "pot", _table_account(other_side), refund_amount)
		if refund.accepted:
			state.round_paid[other_side] = depleted_total
			state.contributions[other_side] = int(state.contributions[other_side]) - refund_amount
			events.append(_event("unmatched_round_refund", other_side, {"amount": refund_amount, "round": state.round}))

func _valid_move(side: String, payload: Dictionary) -> bool:
	var from: Variant = payload.get("from", -1)
	var to: Variant = payload.get("to", -1)
	var kind := str(payload.get("slot_kind", ""))
	if not from is int or not to is int or from < 1 or from > 3 or to < 1 or to > 3 or from == to or kind not in ["equipment", "effect"]:
		return false
	var cards: Array = state.installed_cards[side]
	var source_index: int = int(from) - 1 if kind == "equipment" else 2 + int(from)
	var target_index: int = int(to) - 1 if kind == "equipment" else 2 + int(to)
	if cards.size() <= source_index or cards.size() <= target_index or str(cards[source_index]).is_empty():
		return false
	if not str(cards[target_index]).is_empty() and _card_slot_kind(str(cards[source_index])) != _card_slot_kind(str(cards[target_index])):
		return false
	return _card_slot_kind(str(cards[source_index])) == kind

func _apply_move_to(cards: Array, payload: Dictionary) -> void:
	var kind := str(payload.slot_kind)
	var source_index: int = int(payload.from) - 1 if kind == "equipment" else 2 + int(payload.from)
	var target_index: int = int(payload.to) - 1 if kind == "equipment" else 2 + int(payload.to)
	var temp: Variant = cards[source_index]
	cards[source_index] = cards[target_index]
	cards[target_index] = temp

func _offer_contains(side: String, card_id: String) -> bool:
	for card: Variant in state.private.offers.get(side, []):
		if str(card) == card_id:
			return true
	return false

func _card_slot_kind(card_id: String) -> String:
	if card_id.begins_with("EQ"):
		return "equipment"
	if card_id.begins_with("FX"):
		return "effect"
	return ""

func _sample_team(side: String) -> Array:
	var ids: Array = _character_pool()
	for i in range(ids.size() - 1, 0, -1):
		var j := _next_random(i + 1)
		var temp: Variant = ids[i]
		ids[i] = ids[j]
		ids[j] = temp
	var team := ids.slice(0, 3)
	var result: Array = []
	for i in range(3):
		result.append({"slot": i + 1, "definition_id": team[i]})
	return result

func _next_random(limit: int) -> int:
	var state_value := rng.randi_range(0, limit - 1)
	rng_counter += 1
	return state_value

func _table_account(side: String) -> String:
	return "player_table" if side == "player" else "opponent_table"

func _other(side: String) -> String:
	return "opponent" if side == "player" else "player"

func _event(kind: String, source: String, payload: Dictionary) -> Dictionary:
	state.event_counter = int(state.get("event_counter", 0)) + 1
	return {"event_id": "event-%d-%d" % [int(state.get("hand_id", 0)), int(state.event_counter)],
		"root_id": "command-%d" % (int(state.revision) + 1), "tick": 0, "phase": str(state.phase), "source": source,
		"targets": [], "kind": kind, "payload": payload.duplicate(true), "visibility": "public", "cause_id": ""}

func _snapshot_valid(data: Dictionary) -> bool:
	for key: String in ["state", "ledger", "seed_value", "rng_counter", "rng_state", "first_actor", "applied_commands", "draft", "draft_pool", "public_effect_pool"]:
		if not data.has(key):
			return false
	if not data.state is Dictionary or not data.ledger is Dictionary or not data.applied_commands is Dictionary or not data.draft_pool is Array or not data.public_effect_pool is Array:
		return false
	var ledger_data: Dictionary = data.ledger
	if not ledger_data.get("balances", null) is Dictionary or not ledger_data.get("transactions", null) is Dictionary or not ledger_data.get("transaction_log", null) is Array:
		return false
	var balances: Dictionary = ledger_data.balances
	var total := 0
	for account: String in EconomyLedger.ACCOUNT_NAMES:
		var amount: Variant = balances.get(account, null)
		if not amount is int or amount < 0:
			return false
		total += amount
	if not ledger_data.get("initial_total", null) is int or int(ledger_data.initial_total) != total:
		return false
	var saved_state: Dictionary = data.state
	for key: String in ["revision", "hand_id", "phase", "private", "round_paid", "contributions", "teams_revealed", "event_counter"]:
		if not saved_state.has(key):
			return false
	if not saved_state.revision is int or saved_state.revision < 0 or not saved_state.hand_id is int or saved_state.hand_id < 1:
		return false
	if str(saved_state.phase) not in ["TEAM_SELECTION", "BETTING", "OPERATION_COMMIT", "DRAFT_SELECTION", "PUBLIC_COMMIT", "PUBLIC_BID", "BATTLE_READY", "SETTLED"]:
		return false
	if not saved_state.private is Dictionary or not saved_state.round_paid is Dictionary or not saved_state.contributions is Dictionary:
		return false
	for side: String in SIDES:
		if not saved_state.round_paid.has(side) or not saved_state.contributions.has(side):
			return false
		if not saved_state.round_paid[side] is int or saved_state.round_paid[side] < 0 or not saved_state.contributions[side] is int or saved_state.contributions[side] < 0:
			return false
	if not data.draft is Dictionary:
		return false
	var draft_data: Dictionary = data.draft
	if not draft_data.get("seed", null) is int or not draft_data.get("counter", null) is int or not draft_data.get("rng_state", null) is int:
		return false
	if not draft_data.get("offers", null) is Dictionary or not draft_data.get("selected", null) is Dictionary or not draft_data.get("archive", null) is Array:
		return false
	return true

func _amount_is_int(value: Variant) -> bool:
	return value is int

func _accepted(reason: String) -> Dictionary:
	return {"accepted": true, "reason": reason}

func _reject(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason, "revision": int(state.get("revision", 0)), "events": [], "duplicate": false}
