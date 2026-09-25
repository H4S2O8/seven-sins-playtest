extends SceneTree

const STAGE_SCENE := preload("res://presentation/table/table_stage.tscn")
const CAPTURE_SIZE := Vector2i(1280, 720)


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = CAPTURE_SIZE
	var stage: Node = STAGE_SCENE.instantiate()
	root.add_child(stage)
	await process_frame
	var checkpoints := [0.0, 0.35, 0.70, 1.35, 1.725, 2.10, 2.45, 2.80, 3.35, 3.70, 4.40, 4.80]
	for checkpoint: float in checkpoints:
		stage._apply_entry_time(checkpoint)
		await process_frame
		await process_frame
		print("Entry %.3f viewport=%s actor_at=%s chair_at=%s walk=%.3f sit=%.3f height=%.3f" % [checkpoint, stage.get_viewport().size, stage.camera.unproject_position(stage.opponent_entry.global_position), stage.camera.unproject_position(stage.entry_chair.global_position), stage.opponent_entry.walk_time, stage.opponent_entry.sit_progress, stage.opponent_entry.figure_height_fraction])
		var frame := root.get_texture().get_image()
		if frame.is_empty():
			push_error("Root viewport returned an empty image at %.3f" % checkpoint)
			quit(1)
			return
		var time_mark := ("%.3f" % checkpoint).replace(".", "-")
		var evidence_path := "res://evidence/W05-entry-%s-1280x720.png" % time_mark
		var frame_error := frame.save_png(evidence_path)
		if frame_error != OK:
			push_error("Could not save timeline frame %s: %s" % [evidence_path, error_string(frame_error)])
			quit(1)
			return
		print("Saved actual Godot viewport checkpoint %.3fs: %s" % [checkpoint, evidence_path])
	stage._play_entry_timeline()
	await create_timer(5.1).timeout
	var screenshot := root.get_texture().get_image()
	var output_path := "res://evidence/W05-stage-1280x720.png"
	var error := screenshot.save_png(output_path)
	if error != OK:
		push_error("Could not save final viewport image: %s" % error_string(error))
		quit(1)
		return
	print("Saved actual real-time 4.8-second entry playback screenshot %s (%s)" % [output_path, screenshot.get_size()])
	quit(0)
