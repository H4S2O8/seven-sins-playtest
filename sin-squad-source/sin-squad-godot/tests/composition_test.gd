extends SceneTree

const CALIBRATION_SCENE := preload("res://presentation/calibration/calibration.tscn")
const TEST_SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var window := get_root()
	window.size = TEST_SIZES[0]
	var scene := CALIBRATION_SCENE.instantiate()
	window.add_child(scene)
	await process_frame
	await physics_frame
	scene.parallax_enabled = false
	scene.camera.global_transform = scene.base_camera_transform
	for size: Vector2i in TEST_SIZES:
		window.size = size
		await process_frame
		await physics_frame
		await process_frame
		scene.refresh_layout_for_current_viewport()
		await process_frame
		await physics_frame
		await physics_frame
		var errors: Dictionary = scene.measure_projection_errors()
		var max_error := 0.0
		for key: String in errors:
			max_error = maxf(max_error, errors[key])
			_check(errors[key] <= 1.0, "%s at %dx%d: %.4f px" % [key, size.x, size.y, errors[key]])
		print("COMPOSITION %dx%d anchors=%d max_projection_error_px=%.5f" % [size.x, size.y, errors.size(), max_error])
		_check_ray_pick(scene, "P2", size)
		_check_table_ray_pick(scene, size)
	_check(scene.anchor_nodes.size() == scene.target_points.size(), "all layout targets have Node3D anchors")
	scene._toggle_table_material()
	_check(scene.tabletop_material.get_shader_parameter("use_uv_table") == true, "optional top-view UV material toggle activates")
	scene._toggle_table_material()
	if failures > 0:
		push_error("Composition calibration failed: %d assertion(s)" % failures)
		quit(1)
	else:
		print("COMPOSITION TEST PASS")
		quit(0)


func _check_ray_pick(scene: Node3D, key: String, size: Vector2i) -> void:
	var target: Vector3 = scene.target_points[key]
	var screen_point := Vector2(target.x * size.x, target.y * size.y)
	var origin: Vector3 = scene.camera.project_ray_origin(screen_point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + scene.camera.project_ray_normal(screen_point) * 100.0)
	query.collision_mask = 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty(), "2D-to-3D ray hits an anchor at %dx%d" % [size.x, size.y])
	if not hit.is_empty():
		_check(hit.collider.get_meta("anchor_name", "") == key, "ray selects the corresponding world anchor at %dx%d" % [size.x, size.y])


func _check_table_ray_pick(scene: Node3D, size: Vector2i) -> void:
	var screen_point := Vector2(size.x * 0.5, size.y * 0.5)
	var origin: Vector3 = scene.camera.project_ray_origin(screen_point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + scene.camera.project_ray_normal(screen_point) * 120.0)
	query.collision_mask = 4
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_back_faces = true
	var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty(), "projected 2D ray hits the actual 3D tabletop at %dx%d" % [size.x, size.y])
	if not hit.is_empty():
		_check(hit.collider.name == "TabletopCollision", "table ray resolves to the tabletop collision mesh at %dx%d" % [size.x, size.y])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
