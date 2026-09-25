extends SceneTree

var failures: Array[String] = []
var checks := 0
var sequence := 0

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("TEAM_SELECTION_FAIL: " + label)

func _send(session: SinSession, side: String, kind: String, payload: Dictionary) -> Dictionary:
	sequence += 1
	return session.apply(SinCommand.new("team-selection-%d" % sequence, side, kind, payload, session.state.revision))

func _run() -> void:
	var session := SinSession.new({"seed": 447, "team_draft": true, "first_actor": "player"})
	_check(session.state.phase == "TEAM_SELECTION", "team draft opens before betting")
	var player_view := session.observation("player")
	var opponent_view := session.observation("opponent")
	_check(player_view.your_private.team_candidates.size() == 3, "player sees three fixed candidate positions")
	_check(opponent_view.your_private.team_candidates.size() == 3, "opponent sees three fixed candidate positions")
	var all_initial: Dictionary = {}
	for side in ["player", "opponent"]:
		for slot in ["1", "2", "3"]:
			var cards: Array = session.draft.character_offers[side][slot]
			_check(cards.size() == 3, "%s slot %s has three candidates" % [side, slot])
			for card in cards:
				_check(not all_initial.has(card), "initial candidate does not repeat across teams")
				all_initial[card] = true
	var old_player_slot: Array = session.draft.character_offers.player["1"].duplicate()
	var reroll := _send(session, "player", "reroll_character", {"slot": 1})
	_check(bool(reroll.accepted), "first reroll is accepted")
	var replacement: Array = session.draft.character_offers.player["1"].duplicate()
	for discarded in old_player_slot:
		_check(not replacement.has(discarded), "discarded character cannot return in replacement")
	var before_second := var_to_str(session.snapshot())
	var second := _send(session, "player", "reroll_character", {"slot": 1})
	_check(not bool(second.accepted), "second reroll for same position is rejected")
	_check(var_to_str(session.snapshot()) == before_second, "rejected second reroll is atomic")
	var saved := session.snapshot()
	var restored := SinSession.new({"seed": 999})
	_check(restored.restore_snapshot(saved), "pending team selection restores")
	_check(restored.draft.character_offers == session.draft.character_offers, "restore preserves exact candidates without redrawing")
	_check(restored.draft.character_history == session.draft.character_history, "restore preserves discarded candidate history")
	for side in ["player", "opponent"]:
		for slot in [1, 2, 3]:
			var cards: Array = restored.draft.character_offers[side][str(slot)]
			var picked := str(cards[0])
			var chosen := _send(restored, side, "choose_character", {"slot": slot, "character_id": picked})
			_check(bool(chosen.accepted), "%s chooses slot %d from private offer" % [side, slot])
	_check(restored.state.phase == "BETTING", "both completed teams enter unchanged betting flow")
	_check(restored.state.private.teams.player.size() == 3 and restored.state.private.teams.opponent.size() == 3, "three chosen characters become fixed teams")
	_check(restored.observation("player").opponent_public.team.is_empty(), "opponent selected team remains sealed")
	print("TEAM_SELECTION_TEST checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
