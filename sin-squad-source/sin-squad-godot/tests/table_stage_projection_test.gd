extends SceneTree

const STAGE_SCENE := preload("res://presentation/table/table_stage.tscn")
const TEST_SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = TEST_SIZES[0]
	await process_frame
	var stage: Node = STAGE_SCENE.instantiate()
	root.add_child(stage)
	await process_frame
	for size: Vector2i in TEST_SIZES:
		root.size = size
		await process_frame
		stage.composition.refresh_layout_for_current_viewport()
		stage._on_viewport_resized()
		await process_frame
		var viewport_size: Vector2 = stage.get_viewport().get_visible_rect().size
		var errors: Dictionary = stage.composition.measure_projection_errors()
		var maximum_error := 0.0
		for key: String in errors:
			maximum_error = maxf(maximum_error, float(errors[key]))
		print("Physical window %dx%d (Godot design viewport %s): max anchor error %.4f logical px" % [size.x, size.y, viewport_size, maximum_error])
		_check(root.size == size, "physical test window set to %dx%d" % [size.x, size.y])
		_check(maximum_error <= 0.10, "all design anchors reproject within 0.10 logical px in %dx%d window test" % [size.x, size.y])
	if failures == 0:
		print("PASS table stage projection at 1280x720 and 1920x1080")
	else:
		push_error("Projection test failures: %d" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
