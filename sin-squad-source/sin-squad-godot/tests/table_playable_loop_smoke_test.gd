extends SceneTree

const STAGE_SCENE := preload("res://presentation/table/table_stage.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var stage: Node = STAGE_SCENE.instantiate()
	root.add_child(stage)
	await process_frame
	_check(stage.team_panel.visible and not stage.game_panel.visible, "team selection owns the opening UI")
	var guard := 0
	while stage.game_session.state.phase != "SETTLED" and guard < 80:
		stage.advance_playable_smoke_once()
		await process_frame
		guard += 1
	_check(stage.game_session.state.phase == "SETTLED", "minimal legal-action loop reaches a settled battle")
	_check(stage.game_panel.visible and stage.game_action_box.get_child_count() > 0, "settled state remains actionable")
	var has_next_hand := false
	var next_hand_action: Dictionary = {}
	for action: Dictionary in stage.game_controller.legal_actions("player"):
		if str(action.get("type", "")) == "next_hand":
			has_next_hand = true
			next_hand_action = action
	_check(has_next_hand or bool(stage.game_controller.observation("player").public.room_over), "settled hand offers next hand unless the room is over")
	if has_next_hand:
		var previous_hand := int(stage.game_session.state.hand_id)
		stage._submit_game_action("player", next_hand_action)
		_check(int(stage.game_session.state.hand_id) == previous_hand + 1 and stage.game_session.state.phase != "SETTLED",
			"next-hand UI command opens the next playable hand")
	if failures == 0:
		print("PASS table playable loop smoke")
	else:
		push_error("Table playable loop smoke failures: %d" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
