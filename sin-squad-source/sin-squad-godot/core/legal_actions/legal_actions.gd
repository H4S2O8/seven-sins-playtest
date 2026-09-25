class_name SinLegalActions
extends RefCounted

static func list_actions(observation: Dictionary) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var side := str(observation.get("side", ""))
	var phase := str(observation.get("phase", ""))
	var public_view: Dictionary = observation.get("public", {})
	var stacks: Dictionary = public_view.get("balances", {})
	var stack_account := "player_table" if side == "player" else "opponent_table"
	var stack := int(stacks.get(stack_account, 0))
	var paid: Dictionary = public_view.get("round_paid", {})
	var own_paid := int(paid.get(side, 0))
	var target := int(public_view.get("target_bid", 0))
	var acting := str(observation.get("acting_side", "")) == side
	var own_commit: Dictionary = observation.get("your_private", {}).get("operation_commit", {})
	var may_fold := false
	if phase == "BETTING" and acting:
		may_fold = true
		if target == 0 and own_paid == 0:
			actions.append({"type": "check", "amount_min": 0, "amount_max": 0})
			actions.append({"type": "bet", "amount_min": mini(5, stack), "amount_max": stack, "reason_if_below_five": "all_in_only"})
		else:
			var owed := maxi(0, target - own_paid)
			actions.append({"type": "call", "amount_min": mini(owed, stack), "amount_max": mini(owed, stack), "short_stack_all_in": stack < owed})
			if stack > owed and str(observation.get("public", {}).get("all_in_side", "")).is_empty():
				actions.append({"type": "raise", "amount_min": target + 5, "amount_max": own_paid + stack, "all_in_raise_allowed_below_minimum": true})
		if stack > 0:
			actions.append({"type": "all_in", "amount_min": stack, "amount_max": stack})
	if phase == "OPERATION_COMMIT" and not public_view.get("operation_commits", {}).get(side, {}).get("submitted", false):
		may_fold = true
		actions.append({"type": "commit_operation", "operation": "pass", "fee": 0})
		if stack >= target and target > 0:
			for operation: String in ["draw_card", "move_card", "set_arrows"]:
				actions.append({"type": "commit_operation", "operation": operation, "fee": target})
	if phase == "PUBLIC_COMMIT" and not public_view.get("public_commits", {}).get(side, {}).get("submitted", false):
		may_fold = true
		actions.append({"type": "public_decision", "activate": true, "effect_id": public_view.get("current_public_effect", "")})
		actions.append({"type": "public_decision", "activate": false, "effect_id": public_view.get("current_public_effect", "")})
	if phase == "PUBLIC_BID" and acting:
		may_fold = true
		actions.append({"type": "pass_public_bid", "fee": 0, "meaning": "放弃本次竞价，不等于弃掉本手"})
		var bid_minimum: int = maxi(5, int(public_view.get("public_bid", 0)) + 1)
		if stack >= bid_minimum:
			actions.append({"type": "public_bid", "amount_min": bid_minimum, "amount_max": stack})
	if phase == "DRAFT_SELECTION" and observation.get("your_private", {}).get("private_offer", []).size() > 0 and not bool(observation.your_private.get("draft_selection_submitted", false)):
		may_fold = true
		actions.append({"type": "choose_draft_card", "offer_id": observation.your_private.offer_id,
			"offer": observation.your_private.private_offer.duplicate(true), "external_slots": [1, 2, 3]})
	if phase == "TEAM_SELECTION":
		var candidates: Dictionary = observation.get("your_private", {}).get("team_candidates", {})
		var selected: Dictionary = observation.get("your_private", {}).get("team_selection", {})
		var rerolls: Dictionary = observation.get("your_private", {}).get("team_rerolls", {})
		for slot in [1, 2, 3]:
			var key := str(slot)
			if not selected.has(key):
				actions.append({"type": "choose_character", "slot": slot, "candidates": candidates.get(key, []).duplicate(true)})
				if not bool(rerolls.get(key, false)):
					actions.append({"type": "reroll_character", "slot": slot, "meaning": "该位置最多重抽一次；旧候选永久弃用"})
	if phase == "SETTLED":
		if side == "player":
			actions.append({"type": "leave_table", "amount": stack})
			if not bool(public_view.get("room_over", false)):
				actions.append({"type": "next_hand"})
	if may_fold:
		actions.append({"type": "fold", "meaning": "弃掉本手并输掉已投入筹码"})
	return actions
