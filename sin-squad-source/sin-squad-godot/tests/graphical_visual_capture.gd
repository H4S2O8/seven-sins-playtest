extends SceneTree

const STAGE_SCENE := preload("res://presentation/table/table_stage.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var stage: Node = STAGE_SCENE.instantiate()
	root.add_child(stage)
	for _frame in range(12):
		await process_frame
	stage._apply_entry_time(4.8)
	for _frame in range(4):
		await process_frame
	var opening := root.get_texture().get_image()
	var opening_error := opening.save_png("res://evidence/playable-opening.png")
	if opening_error != OK:
		push_error("opening capture failed: %s" % opening_error)
		quit(1)
		return
	var safety := 0
	while stage.game_session.state.phase != "SETTLED" and safety < 160:
		safety += 1
		stage.advance_playable_smoke_once()
		await process_frame
	for _frame in range(8):
		await process_frame
	var settled := root.get_texture().get_image()
	var settled_error := settled.save_png("res://evidence/playable-settled.png")
	if settled_error != OK:
		push_error("settled capture failed: %s" % settled_error)
		quit(1)
		return
	if stage.game_session.state.phase != "SETTLED":
		push_error("graphical playthrough did not settle")
		quit(1)
		return
	print("GRAPHICAL_PLAYTHROUGH_OK steps=%d" % safety)
	quit(0)
