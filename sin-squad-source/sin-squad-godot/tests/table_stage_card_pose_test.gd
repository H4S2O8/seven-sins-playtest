extends SceneTree

const STAGE_SCENE := preload("res://presentation/table/table_stage.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var stage: Node = STAGE_SCENE.instantiate()
	root.add_child(stage)
	await create_timer(0.25).timeout
	print("STAGE elapsed=%s viewport=%s camera=%s contact=%s target=%s" % [stage.entry_elapsed, stage.get_viewport().get_visible_rect().size, stage.camera.global_position, stage.player_contact, stage.entry_target_positions.get("P0")])
	for card in stage.player_cards + stage.opponent_cards:
		var center: Vector3 = card.global_position + card.global_basis.y * card.card_height_world * 0.5
		print("CARD %s visible=%s mode=%d world=%s base=%s base_screen=%s screen=%s size=%s xaxis=%s yaxis=%s" % [card.card_id, card.visible, card.placement_mode, card.global_position, card.base_origin, stage.camera.unproject_position(card.base_origin), stage.camera.unproject_position(center), Vector2(card.card_width_world, card.card_height_world), card.global_basis.x, card.global_basis.y])
		var pixel: Vector2 = stage.camera.unproject_position(center)
		print(" HIT %s" % stage.raycast_screen(pixel))
		var screen_corners: Array[Vector2] = []
		for corner in [Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(-0.5, 1.0), Vector2(0.5, 1.0)]:
			var world_corner: Vector3 = card.global_position + card.global_basis.x * corner.x * card.card_width_world + card.global_basis.y * corner.y * card.card_height_world
			screen_corners.append(stage.camera.unproject_position(world_corner))
		var screen_width := maxf(screen_corners[0].distance_to(screen_corners[1]), screen_corners[2].distance_to(screen_corners[3]))
		var screen_height := maxf(screen_corners[0].distance_to(screen_corners[2]), screen_corners[1].distance_to(screen_corners[3]))
		print(" PROJECTED_RATIO %s %s height=%s ratio=%s" % [card.card_id, screen_corners, screen_height, screen_width / screen_height])
	for depth in [2.0, 3.0, 4.0, 5.0, 6.0, 8.5]:
		var point: Vector3 = stage.camera.project_position(Vector2(0.21 * 1920.0, 0.955 * 1080.0), depth)
		print("DEPTH %.1f point=%s projected=%s" % [depth, point, stage.camera.unproject_position(point)])
	quit(0)
