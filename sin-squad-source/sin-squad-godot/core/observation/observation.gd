class_name SinObservation
extends RefCounted

static func for_side(state: Dictionary, side: String) -> Dictionary:
	if side not in ["player", "opponent"]:
		return {}
	var other := "opponent" if side == "player" else "player"
	var ledger_data: Dictionary = state.get("ledger", {})
	var balances: Dictionary = ledger_data.get("balances", {})
	var private_state: Dictionary = state.get("private", {})
	var teams: Dictionary = private_state.get("teams", {})
	var own_operations: Dictionary = private_state.get("operation_commits", {})
	var public_operation_status: Dictionary = {}
	var public_draft_status: Dictionary = {}
	for actor: String in ["player", "opponent"]:
		public_operation_status[actor] = {"submitted": state.get("operation_commits", {}).has(actor)}
		public_draft_status[actor] = {"submitted": state.get("draft_selection_commits", {}).has(actor)}
	var public_team_status: Dictionary = {}
	for actor: String in ["player", "opponent"]:
		public_team_status[actor] = {"submitted": state.get("team_selection_commits", {}).has(actor)}
	var public_choice_status: Dictionary = {}
	for actor: String in ["player", "opponent"]:
		public_choice_status[actor] = {"submitted": state.get("public_commits", {}).has(actor)}
		if state.get("public_commits", {}).size() == 2:
			public_choice_status[actor]["activate"] = bool(state.public_commits[actor])
	var table_balances := {"player_table": int(balances.get("player_table", 0)),
		"opponent_table": int(balances.get("opponent_table", 0)), "pot": int(balances.get("pot", 0))}
	var revealed: Array = state.get("resolved_public_effects", []).duplicate(true)
	if str(state.get("phase", "")) in ["PUBLIC_COMMIT", "PUBLIC_BID"]:
		revealed.append({"id": str(state.get("current_public_effect", "")), "status": "awaiting_joint_decision"})
	var show_teams := bool(state.get("teams_revealed", false))
	var public_view := {
		"rule_id": str(state.get("rule_id", "")), "arena_id": str(state.get("arena_id", "")),
		"balances": table_balances, "round_paid": state.get("round_paid", {}).duplicate(true),
		"target_bid": int(state.get("target_bid", 0)), "revealed_effects": revealed,
		"public_commits": public_choice_status, "operation_commits": public_operation_status, "draft_selection_commits": public_draft_status,
		"team_selection": public_team_status,
		"public_bid": int(state.get("public_bid", 0)), "public_bidder": str(state.get("public_bidder", "")),
		"all_in_side": str(state.get("all_in_side", "")),
		"room_over": int(balances.get("player_table", 0)) <= 0 or int(balances.get("opponent_table", 0)) <= 0,
		"battle_result": state.get("battle_result", {}).duplicate(true), "teams_revealed": show_teams,
		"hand_id": int(state.get("hand_id", 0)), "current_public_effect": str(state.get("current_public_effect", "")) if str(state.get("phase", "")) in ["PUBLIC_COMMIT", "PUBLIC_BID"] else ""
	}
	return {
		"side": side, "revision": int(state.get("revision", 0)), "phase": str(state.get("phase", "")),
		"round": int(state.get("round", 0)), "acting_side": str(state.get("acting_side", "")),
		"your_private": {"team": teams.get(side, []).duplicate(true), "team_candidates": state.get("draft_character_offers", {}).get(side, {}).duplicate(true),
			"team_selection": private_state.get("team_selection", {}).get(side, {}).duplicate(true), "team_rerolls": state.get("draft_character_rerolls", {}).get(side, {}).duplicate(true), "private_offer": private_state.get("offers", {}).get(side, []).duplicate(true),
			"offer_id": private_state.get("offer_ids", {}).get(side, ""), "operation_commit": own_operations.get(side, {}).duplicate(true),
			"draft_selection_submitted": state.get("draft_selection_commits", {}).has(side),
			"team_arrows": state.get("arrows", {}).get(side, []).duplicate(), "installed_cards": state.get("installed_cards", {}).get(side, []).duplicate(true),
			"wallet": int(balances.get("player_wallet", 0)) if side == "player" else int(balances.get("opponent_funds", 0))},
		"opponent_public": {"team_sealed": not show_teams, "team": teams.get(other, []).duplicate(true) if show_teams else [],
			"arrows": state.get("arrows", {}).get(other, []).duplicate(),
			"installed_cards": state.get("installed_cards", {}).get(other, []).duplicate(true)},
		"public": public_view
	}
