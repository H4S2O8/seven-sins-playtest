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
	await physics_frame
	await physics_frame

	_check(stage.player_cards.size() == 3, "three own 3D candidate cards exist")
	_check(stage.opponent_cards.size() == 3, "three opponent 3D card backs exist")
	_check(stage.get_slot_count() == 12, "twelve physical slot areas exist")
	_check(stage.player_chip_stacks.size() == 4 and stage.opponent_chip_stacks.size() == 4, "four denomination stacks per side")
	var sample_chip: Node3D = stage.player_chip_stacks[0].chip_nodes[0]
	_check(sample_chip.get_node_or_null("AtlasEngravedTopFace") != null, "chip top face uses atlas crop on real 3D disc")
	_check(sample_chip.get_node_or_null("AtlasWoodgrainSideBand") != null, "chip side uses atlas wrap UV on real cylinder")
	var player_dealer: Node3D = stage.dealers.dealer_nodes["player"]
	_check(player_dealer.get_node_or_null("LeftShoulderPivot/LeftElbowPivot/LeftWristPivot/LeftHand") != null, "dealer v2 arm parts follow shoulder-elbow-wrist hierarchy")
	_check(stage.opponent_entry.walk_frames.size() == 4 and stage.opponent_entry.sit_frames.size() == 4, "AC01/03 use individually cropped atlas keyposes, not whole-sheet motion")
	_check(stage.entry_chair.get_node_or_null("Seat") != null and stage.entry_chair.get_node_or_null("BackTopRail") != null, "AC02 chair is a separate 3D prop")
	_check(stage.font != null, "local Noto Sans SC font loaded")
	_check(stage.get_action_count() == 21, "AC12–32 debug actions are registered")
	_check(stage.game_session.state.phase == "TEAM_SELECTION" and stage.team_panel.visible,
		"formal table opens the real TEAM_SELECTION panel before betting")
	var initial_player_offer: Array = stage.game_controller.observation("player").your_private.team_candidates["1"].duplicate()
	stage._on_team_reroll_pressed(1)
	var replacement_offer: Array = stage.game_controller.observation("player").your_private.team_candidates["1"]
	_check(replacement_offer.size() == 3 and replacement_offer != initial_player_offer and stage.team_reroll_buttons[1].disabled,
		"team panel permits exactly one position reroll and refreshes all three candidates")
	for discarded in initial_player_offer:
		_check(not replacement_offer.has(discarded), "discarded team candidate %s cannot return" % discarded)
	for team_slot in [1, 2, 3]:
		stage._on_team_candidate_pressed(team_slot, 0)
	_check(stage.game_session.state.phase == "BETTING" and not stage.team_panel.visible,
		"three player choices plus sealed opponent choices enter the unchanged betting flow")
	_check(stage.get_slot_count() == 12 and stage.slot_select.item_count == 6,
		"team selection leaves the existing equipment/effect slot UI unchanged")
	stage._apply_entry_time(0.35)
	_check(stage.opponent_entry.walk_time == 0.35 and not stage.entry_ready, "AC01 midpoint selects a passing keypose and keeps input gated")
	stage._apply_entry_time(1.725)
	_check(stage.opponent_entry.sit_progress > 0.49 and stage.opponent_entry.sit_progress < 0.51, "AC03 midpoint uses a separate bent-knee atlas pose")
	stage._apply_entry_time(2.45)
	_check(stage.player_chip_stacks[0].visible and stage.opponent_chip_stacks[0].visible, "AC01–11 midpoint shows both transferred chip groups")
	stage._apply_entry_time(4.8)
	_check(stage.entry_ready and stage.demo_amounts == {"player": 250, "opponent": 250, "pot": 50}, "4.8-second entry opens input without changing demo wallet amounts")

	for card in stage.player_cards:
		var center: Vector3 = card.global_position + card.global_basis.y * card.card_height_world * 0.5
		var pixel: Vector2 = stage.camera.unproject_position(center)
		var hit: Dictionary = stage.raycast_screen(pixel)
		_check(not hit.is_empty() and hit.collider.has_meta("card_id") and hit.collider.get_meta("card_id") == card.card_id, "screen ray hits physical candidate %s" % card.card_id)

	var chip_stack: Node3D = stage.player_chip_stacks[0]
	var chip_pixel: Vector2 = stage.camera.unproject_position(chip_stack.global_position + Vector3.UP * 0.08)
	var chip_hit: Dictionary = stage.raycast_screen(chip_pixel)
	_check(not chip_hit.is_empty() and chip_hit.collider.has_meta("chip_stack"), "screen ray hits physical chip stack")
	for slot_id: String in stage.slot_meshes:
		var slot: Node3D = stage.slot_meshes[slot_id]
		var slot_pixel: Vector2 = stage.camera.unproject_position(slot.global_position + Vector3.UP * 0.035)
		var slot_hit: Dictionary = stage.raycast_screen(slot_pixel)
		_check_slot_hit(slot_hit, slot_id)

	var arbitrary_points := [Vector2(0.50, 0.47), Vector2(0.42, 0.58), Vector2(0.58, 0.58), Vector2(0.50, 0.68)]
	for point in arbitrary_points:
		var hit: Dictionary = stage.raycast_normalized(point)
		_check(not hit.is_empty(), "arbitrary 3D ray resolves at normalized point %s" % point)

	for action_id in range(12, 33):
		_check(stage.preview_action(action_id, 1000.0), "AC%02d starts" % action_id)
		await create_timer(0.30).timeout
		await process_frame
		_check(not stage.action_busy, "AC%02d completes its timed 3D object preview" % action_id)
	_check(stage.action_log.size() == 21, "all AC12–32 actions ran through stage action entry")
	_check(stage.demo_amounts == {"player": 250, "opponent": 250, "pot": 50}, "fixed demo actions never alter economy amounts")

	if failures == 0:
		print("PASS table stage: 3D cards/chips, twelve slots, arbitrary rays, AC12–32; no economy writes")
	else:
		push_error("Table stage test failures: %d" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)


func _check_slot_hit(hit: Dictionary, slot_id: String) -> void:
	if hit.is_empty() or not hit.collider.has_meta("slot_id") or hit.collider.get_meta("slot_id") != slot_id:
		print("Slot ray diagnostic %s: %s" % [slot_id, hit])
	_check(not hit.is_empty() and hit.collider.has_meta("slot_id") and hit.collider.get_meta("slot_id") == slot_id, "screen ray hits 3D slot %s" % slot_id)
