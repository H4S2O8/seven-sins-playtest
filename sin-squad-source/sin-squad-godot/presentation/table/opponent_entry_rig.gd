extends Node3D
class_name OpponentEntryRig

const WALK_ATLAS_PATH := "res://assets/sources/opponent/opponent-walk-keyframes-v1.png"
const SIT_ATLAS_PATH := "res://assets/sources/opponent/opponent-sit-keyframes-v1.png"
const CAMERA_DEPTH := 17.0
const FOOT_BASELINE := 0.87
const WALK_BOUNDS := [Rect2i(147, 0, 408, 614), Rect2i(709, 0, 336, 616), Rect2i(150, 629, 412, 601), Rect2i(730, 629, 348, 603)]
const SIT_BOUNDS := [Rect2i(212, 1, 258, 626), Rect2i(727, 99, 319, 528), Rect2i(212, 627, 330, 599), Rect2i(758, 627, 328, 599)]
const WALK_HEAD_CENTERS := [Vector2(350, 76), Vector2(890, 76), Vector2(360, 705), Vector2(900, 705)]
const SIT_HEAD_CENTERS := [Vector2(340, 74), Vector2(890, 165), Vector2(365, 712), Vector2(900, 712)]
const WALK_HEAD_HEIGHTS := [112.0, 112.0, 116.0, 116.0]
const SIT_HEAD_HEIGHTS := [120.0, 120.0, 120.0, 120.0]

var camera: Camera3D
var composition: Node3D
var walk_frames: Array[Sprite3D] = []
var sit_frames: Array[Sprite3D] = []
var walk_time := 0.0
var sit_progress := 0.0
var figure_height_fraction := 0.76
var normalized_x := 0.36
var current_mode := "walk"


func configure(target_camera: Camera3D, target_composition: Node3D) -> void:
	camera = target_camera
	composition = target_composition
	_build_atlas_frames(WALK_ATLAS_PATH, WALK_BOUNDS, walk_frames, "WalkKeyPose")
	_build_atlas_frames(SIT_ATLAS_PATH, SIT_BOUNDS, sit_frames, "SitKeyPose")
	set_walk_time(0.0)


func set_walk_time(seconds: float) -> void:
	current_mode = "walk"
	walk_time = clampf(seconds, 0.0, 0.70)
	var phase := mini(3, floori(walk_time / 0.175))
	_show_frame(walk_frames, sit_frames, phase, false)
	# Hold contact poses, move only while a passing pose is visible.
	if phase == 0:
		normalized_x = 0.36
	elif phase == 1:
		normalized_x = lerpf(0.36, 0.43, _smooth((walk_time - 0.175) / 0.175))
	elif phase == 2:
		normalized_x = 0.43
	else:
		normalized_x = lerpf(0.43, 0.50, _smooth((walk_time - 0.525) / 0.175))
	figure_height_fraction = 0.76
	_update_transform()


func set_sit_progress(progress: float) -> void:
	current_mode = "sit"
	sit_progress = clampf(progress, 0.0, 1.0)
	var phase := mini(3, floori(sit_progress * 4.0))
	_show_frame(walk_frames, sit_frames, phase, true)
	# Keep the face on OPP_HEAD. Pose-specific pixels hold head scale constant while
	# the source artwork supplies the bent knees/hip position.
	figure_height_fraction = 0.0
	normalized_x = lerpf(0.50, 0.515, _smooth(sit_progress))
	_update_transform()


func _build_atlas_frames(path: String, regions: Array, frames: Array[Sprite3D], prefix: String) -> void:
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("Missing opponent keypose atlas: " + path)
		return
	for index in range(regions.size()):
		var crop: Rect2i = regions[index]
		# The seated keypose atlas includes legs and shoes below the tabletop.
		# Keep the head, torso, forearms and hands only; real table depth occludes
		# the lower body instead of letting those pixels appear above the actor.
		if path == SIT_ATLAS_PATH and index >= 2:
			crop.size.y = mini(crop.size.y, 410)
		var pose := Sprite3D.new()
		pose.name = "%s%d_CroppedCharacter" % [prefix, index + 1]
		var cropped_atlas := AtlasTexture.new()
		cropped_atlas.atlas = texture
		cropped_atlas.region = Rect2(crop)
		pose.texture = cropped_atlas
		pose.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		pose.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		pose.shaded = false
		pose.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pose.visible = false
		add_child(pose)
		frames.append(pose)


func _show_frame(walking: Array[Sprite3D], sitting: Array[Sprite3D], index: int, seated: bool) -> void:
	for frame_index in range(walking.size()):
		walking[frame_index].visible = not seated and frame_index == index
	for frame_index in range(sitting.size()):
		sitting[frame_index].visible = seated and frame_index == index
	var frame: Sprite3D = sitting[index] if seated else walking[index]
	var region: Rect2i = SIT_BOUNDS[index] if seated else WALK_BOUNDS[index]
	var head_center: Vector2 = SIT_HEAD_CENTERS[index] if seated else WALK_HEAD_CENTERS[index]
	var head_height: float = SIT_HEAD_HEIGHTS[index] if seated else WALK_HEAD_HEIGHTS[index]
	var anchor: Vector3 = composition._world_at_screen_point(Vector2(normalized_x, 0.095), 1.0)
	var camera_local_anchor: Vector3 = camera.global_transform.affine_inverse() * anchor
	var depth := absf(camera_local_anchor.z)
	var viewport_height := float(get_viewport().size.y)
	var world_per_screen_pixel := 2.0 * depth * tan(deg_to_rad(camera.fov * 0.5)) / viewport_height
	var target_head_height_px := viewport_height * 0.10
	frame.pixel_size = world_per_screen_pixel * target_head_height_px / head_height
	var crop_center := Vector2(region.position) + Vector2(region.size) * 0.5
	frame.position = Vector3((crop_center.x - head_center.x) * frame.pixel_size, (head_center.y - crop_center.y) * frame.pixel_size, -0.015)
	figure_height_fraction = float(region.size.y) / head_height * 0.10


func _update_transform() -> void:
	if camera == null:
		return
	# Camera3D screen coordinates use the physical viewport size, not the stretched
	# logical canvas rectangle returned by get_visible_rect().
	var anchor: Vector3 = composition._world_at_screen_point(Vector2(normalized_x, 0.095), 1.0)
	global_transform = Transform3D(camera.global_basis.orthonormalized(), anchor)


func _frustum_height() -> float:
	return 2.0 * CAMERA_DEPTH * tan(deg_to_rad(camera.fov * 0.5))


func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
