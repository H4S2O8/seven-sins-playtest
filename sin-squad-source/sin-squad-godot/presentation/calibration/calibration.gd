extends Node3D

const LAYOUT = preload("res://presentation/calibration/table_layout.tres")
const ROOM_IMAGE := "res://assets/sources/environment/table-room-clean-v2.png"
const UV_TABLE_IMAGE := "res://assets/sources/environment/tabletop-uv-v1.png"
const OPPONENT_ATLAS := "res://assets/sources/opponent/opponent-pose-reference-v1.png"
const FONT_PATH := "res://assets/fonts/NotoSansSC-Full.ttf"
const TABLE_CORNER_NAMES := ["TABLE_FAR_L", "TABLE_FAR_R", "TABLE_NEAR_R", "TABLE_NEAR_L"]
const TARGET_LABELS := {
	"TABLE_FAR_L": "桌面远左角", "TABLE_FAR_R": "桌面远右角",
	"TABLE_NEAR_L": "桌面近左角", "TABLE_NEAR_R": "桌面近右角",
	"OPP_HEAD": "对手头部", "OPP_TORSO": "对手躯干", "O_RECEIVE": "对手左手接牌",
	"DEALER_P": "左荷官", "DEALER_O": "右荷官",
	"P_RECEIVE": "玩家左手接牌", "P_HAND": "玩家三张手牌",
	"P_CHIPS": "玩家筹码", "O_CHIPS": "对手筹码", "POT": "奖池",
	"RULE_CARD": "胜利规则卡", "ARENA_CARD": "基础场地卡",
	"PUBLIC_1": "公共效果 1", "PUBLIC_2": "公共效果 2", "PUBLIC_3": "公共效果 3",
	"ACTION_TRAY": "操作托盘", "NOTICE": "提示行", "O_SPEECH": "对手短句",
}

var camera: Camera3D
var target_points: Dictionary
var table_mesh: MeshInstance3D
var anchor_nodes: Dictionary = {}
var overlay: AnchorOverlay
var ui_layer: CanvasLayer
var error_rows: VBoxContainer
var status_label: Label
var parallax_button: Button
var material_button: Button
var proxy_label: Label
var parallax_enabled := true
var use_uv_table := false
var base_camera_transform: Transform3D
var capture_mode := false
var debug_mode := true
var room_texture: Texture2D
var uv_table_texture: Texture2D
var tabletop_material: ShaderMaterial
var room_backdrop: Sprite3D
var debug_panel: Control
var debug_controls: Control
var watermark_label: Label
var table_body: StaticBody3D


class AnchorOverlay extends Control:
	var scene_owner: Node3D
	var target_camera: Camera3D
	var marker_font: Font
	var marker_color := Color("e6c986")

	func _draw() -> void:
		if scene_owner == null or target_camera == null:
			return
		for key: String in scene_owner.anchor_nodes:
			var node: Node3D = scene_owner.anchor_nodes[key]
			var point := target_camera.unproject_position(node.global_position)
			if point.x < -20.0 or point.y < -20.0 or point.x > size.x + 20.0 or point.y > size.y + 20.0:
				continue
			draw_line(point + Vector2(-5, 0), point + Vector2(5, 0), marker_color, 1.25, true)
			draw_line(point + Vector2(0, -5), point + Vector2(0, 5), marker_color, 1.25, true)
			if (key.begins_with("P") or key.begins_with("O")) and key.length() == 2:
				draw_string(marker_font, point + Vector2(6, -5), key, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, marker_color)


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("100e0d"))
	target_points = LAYOUT.anchor_targets
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_mode = true
			parallax_enabled = false
		elif arg == "--capture-mode=clean":
			debug_mode = false
	_setup_camera()
	_setup_room_and_table()
	_setup_world_anchors()
	_setup_opponent_proxy()
	_setup_interface()
	base_camera_transform = camera.global_transform
	get_viewport().size_changed.connect(_on_viewport_resized)
	refresh_layout_for_current_viewport()
	_apply_debug_mode()
	if capture_mode:
		_capture_requested_frame(OS.get_cmdline_user_args())


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "CalibrationCamera"
	add_child(camera)
	camera.position = LAYOUT.camera_position
	camera.look_at(LAYOUT.camera_target, Vector3.UP)
	camera.fov = LAYOUT.camera_fov
	camera.current = true


func _setup_room_and_table() -> void:
	room_texture = load(ROOM_IMAGE) as Texture2D
	uv_table_texture = load(UV_TABLE_IMAGE) as Texture2D
	var source_size := room_texture.get_size()
	var room_atlas := AtlasTexture.new()
	room_atlas.atlas = room_texture
	room_atlas.region = Rect2(Vector2.ZERO, source_size)
	room_backdrop = Sprite3D.new()
	room_backdrop.name = "RoomFarBackground"
	room_backdrop.texture = room_atlas
	room_backdrop.pixel_size = 1.0
	room_backdrop.shaded = false
	room_backdrop.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	camera.add_child(room_backdrop)
	_update_room_backdrop()

	var corners: Array[Vector3] = []
	for key: String in TABLE_CORNER_NAMES:
		var target: Vector3 = target_points[key]
		corners.append(_world_at_screen_point(Vector2(target.x, target.y), LAYOUT.table_height))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(corners)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = _cleanplate_table_uvs()
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	table_mesh = MeshInstance3D.new()
	table_mesh.name = "Tabletop3D"
	table_mesh.mesh = array_mesh
	var projection_shader := Shader.new()
	projection_shader.code = """
	shader_type spatial;
	render_mode unshaded, cull_disabled, depth_draw_opaque;
	uniform sampler2D cleanplate_texture : source_color, filter_linear;
	uniform sampler2D uv_table_texture : source_color, filter_linear;
	uniform bool use_uv_table = false;
	void fragment() {
		vec2 sample_uv = use_uv_table ? UV : SCREEN_UV;
		vec3 image_color = use_uv_table ? texture(uv_table_texture, sample_uv).rgb : texture(cleanplate_texture, sample_uv).rgb;
		ALBEDO = image_color;
	}
	"""
	tabletop_material = ShaderMaterial.new()
	tabletop_material.shader = projection_shader
	tabletop_material.set_shader_parameter("cleanplate_texture", room_texture)
	tabletop_material.set_shader_parameter("uv_table_texture", uv_table_texture)
	table_mesh.material_override = tabletop_material
	add_child(table_mesh)
	table_body = StaticBody3D.new()
	table_body.name = "TabletopCollision"
	table_body.collision_layer = 4
	table_body.collision_mask = 0
	var table_shape := CollisionShape3D.new()
	table_shape.shape = _make_table_collision_shape(corners)
	table_body.add_child(table_shape)
	add_child(table_body)


func _cleanplate_table_uvs() -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])


func _make_table_collision_shape(corners: Array[Vector3]) -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for corner: Vector3 in corners:
		points.append(corner + Vector3.UP * 0.035)
		points.append(corner - Vector3.UP * 0.035)
	shape.points = points
	return shape


func _update_room_backdrop() -> void:
	if room_backdrop == null:
		return
	var source_size := room_texture.get_size()
	var distance := 80.0
	var frustum_height := distance * 2.0 * tan(deg_to_rad(LAYOUT.camera_fov * 0.5))
	room_backdrop.pixel_size = frustum_height / source_size.y
	room_backdrop.position = Vector3(0.0, 0.0, -distance)


func _setup_world_anchors() -> void:
	for key: String in target_points:
		var target: Vector3 = target_points[key]
		var anchor := Node3D.new()
		anchor.name = "Anchor_" + key
		anchor.position = _world_at_screen_point(Vector2(target.x, target.y), target.z)
		anchor.set_meta("screen_target", Vector2(target.x, target.y))
		anchor.set_meta("height", target.z)
		anchor.add_to_group("composition_anchors")
		add_child(anchor)
		anchor_nodes[key] = anchor
		var area := Area3D.new()
		area.name = "PickableAnchor"
		area.collision_layer = 2
		area.collision_mask = 0
		area.input_ray_pickable = false
		area.set_meta("anchor_name", key)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		shape.shape = sphere
		area.add_child(shape)
		anchor.add_child(area)
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 10
	add_child(overlay_layer)
	ui_layer = overlay_layer
	overlay = AnchorOverlay.new()
	overlay.name = "ProjectedWorldMarkers"
	overlay.scene_owner = self
	overlay.target_camera = camera
	overlay.marker_font = load(FONT_PATH)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(overlay)


func _setup_opponent_proxy() -> void:
	var atlas_image := load(OPPONENT_ATLAS) as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = atlas_image
	var crop := Rect2(Vector2(70.0, 630.0), Vector2(550.0, 440.0))
	atlas.region = crop
	var source_head_center := Vector2(330.0, 727.5)
	var head_center_in_crop := source_head_center - crop.position
	var uniform_pixel_size := 0.0162
	var head_offset_in_sprite := Vector2(
		(head_center_in_crop.x - crop.size.x * 0.5) * uniform_pixel_size,
		(crop.size.y * 0.5 - head_center_in_crop.y) * uniform_pixel_size
	)
	var proxy_anchor := Node3D.new()
	proxy_anchor.name = "OpponentPoseProxyAnchor"
	proxy_anchor.position = anchor_nodes["OPP_HEAD"].position
	add_child(proxy_anchor)
	var sprite := Sprite3D.new()
	sprite.name = "UnapprovedOpponentPoseProxy"
	sprite.texture = atlas
	sprite.pixel_size = uniform_pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.position = -camera.global_basis.x * head_offset_in_sprite.x - camera.global_basis.y * head_offset_in_sprite.y
	proxy_anchor.add_child(sprite)


func _setup_interface() -> void:
	var theme := Theme.new()
	theme.default_font = load(FONT_PATH)
	theme.default_font_size = 15
	var root := Control.new()
	root.name = "CalibrationUI"
	root.theme = theme
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_layer.add_child(root)

	watermark_label = Label.new()
	watermark_label.name = "CalibrationWatermark"
	watermark_label.add_theme_font_size_override("font_size", 32)
	watermark_label.add_theme_color_override("font_color", Color(0.78, 0.19, 0.14, 0.94))
	watermark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	watermark_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	watermark_label.offset_top = 14
	watermark_label.offset_bottom = 56
	watermark_label.offset_left = 14
	watermark_label.offset_right = -14
	watermark_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(watermark_label)

	proxy_label = Label.new()
	proxy_label.text = "对手站位代理：未验收静态 Atlas 姿势（非动画）"
	proxy_label.add_theme_font_size_override("font_size", 14)
	proxy_label.add_theme_color_override("font_color", Color("e2c894"))
	proxy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(proxy_label)

	var panel := PanelContainer.new()
	panel.name = "ProjectionErrorPanel"
	panel.position = Vector2(10, 76)
	panel.custom_minimum_size = Vector2(292, 0)
	panel.size = Vector2(292, 530)
	panel.modulate = Color(1, 1, 1, 0.94)
	root.add_child(panel)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.045, 0.035, 0.92)
	panel_style.border_color = Color("91794d")
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(9)
	panel.add_theme_stylebox_override("panel", panel_style)
	debug_panel = panel
	var panel_column := VBoxContainer.new()
	panel.add_child(panel_column)
	var heading := Label.new()
	heading.text = "屏幕锚点投影误差 · px"
	heading.add_theme_color_override("font_color", Color("e6d4b0"))
	panel_column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_column.add_child(scroll)
	error_rows = VBoxContainer.new()
	error_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	error_rows.add_theme_constant_override("separation", 1)
	scroll.add_child(error_rows)

	var controls := HBoxContainer.new()
	controls.position = Vector2(12, 12)
	controls.add_theme_constant_override("separation", 8)
	root.add_child(controls)
	debug_controls = controls
	parallax_button = Button.new()
	parallax_button.text = "鼠标微视差：开"
	parallax_button.pressed.connect(_toggle_parallax)
	controls.add_child(parallax_button)
	var debug_button := Button.new()
	debug_button.text = "调试叠层：开"
	debug_button.pressed.connect(_toggle_debug_mode)
	controls.add_child(debug_button)
	material_button = Button.new()
	material_button.text = "桌纹：clean plate"
	material_button.pressed.connect(_toggle_table_material)
	controls.add_child(material_button)
	var capture_hint := Label.new()
	capture_hint.text = "F12 截图 · 点击标记执行 3D 射线选点"
	capture_hint.add_theme_color_override("font_color", Color("e6d4b0"))
	controls.add_child(capture_hint)

	status_label = Label.new()
	status_label.name = "Status"
	status_label.add_theme_color_override("font_color", Color("e6d4b0"))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_label)
	_layout_responsive_labels()


func _world_at_screen_point(normalized_point: Vector2, world_height: float) -> Vector3:
	var view_size := get_viewport().get_visible_rect().size
	var screen_point := Vector2(normalized_point.x * view_size.x, normalized_point.y * view_size.y)
	var ray_origin := camera.project_ray_origin(screen_point)
	var ray_direction := camera.project_ray_normal(screen_point)
	if absf(ray_direction.y) < 0.00001:
		return Vector3(0, world_height, 0)
	var distance := (world_height - ray_origin.y) / ray_direction.y
	return ray_origin + ray_direction * distance


func refresh_layout_for_current_viewport() -> void:
	for key: String in target_points:
		var target: Vector3 = target_points[key]
		anchor_nodes[key].position = _world_at_screen_point(Vector2(target.x, target.y), target.z)
	var corners: Array[Vector3] = []
	for key: String in TABLE_CORNER_NAMES:
		var target: Vector3 = target_points[key]
		corners.append(_world_at_screen_point(Vector2(target.x, target.y), LAYOUT.table_height))
	var arrays := table_mesh.mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(corners)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	table_mesh.mesh = mesh
	var collision_shape: CollisionShape3D = table_body.get_child(0)
	collision_shape.shape = _make_table_collision_shape(corners)
	get_node("OpponentPoseProxyAnchor").position = anchor_nodes["OPP_HEAD"].position
	_update_error_rows()
	_layout_responsive_labels()
	if overlay != null:
		overlay.queue_redraw()


func measure_projection_errors() -> Dictionary:
	var view_size := get_viewport().get_visible_rect().size
	var errors: Dictionary = {}
	for key: String in target_points:
		var target: Vector3 = target_points[key]
		var desired := Vector2(target.x * view_size.x, target.y * view_size.y)
		var actual := camera.unproject_position(anchor_nodes[key].global_position)
		errors[key] = actual.distance_to(desired)
	return errors


func _update_error_rows() -> void:
	if error_rows == null:
		return
	for child in error_rows.get_children():
		child.queue_free()
	var view_size := get_viewport().get_visible_rect().size
	var errors := measure_projection_errors()
	for key: String in target_points:
		var label := Label.new()
		var xy := Vector2(target_points[key].x * view_size.x, target_points[key].y * view_size.y)
		var label_name: String = TARGET_LABELS.get(key, "牌槽 " + key)
		label.text = "%s  %s  (%.0f, %.0f)  Δ%.3f" % [key, label_name, xy.x, xy.y, errors[key]]
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color("e5d6b8"))
		error_rows.add_child(label)


func _layout_responsive_labels() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var root := get_node_or_null("CanvasLayer/CalibrationUI")
	if root != null:
		proxy_label.position = Vector2(0.32 * viewport_size.x, 0.255 * viewport_size.y)
		status_label.position = Vector2(12, viewport_size.y - 36)


func _process(delta: float) -> void:
	if parallax_enabled and not capture_mode:
		var view_size := get_viewport().get_visible_rect().size
		var mouse := get_viewport().get_mouse_position()
		var centered := Vector2((mouse.x / view_size.x - 0.5) * 2.0, (mouse.y / view_size.y - 0.5) * 2.0)
		var target_transform := base_camera_transform
		target_transform.origin += base_camera_transform.basis.x * centered.x * 0.05
		target_transform.origin += base_camera_transform.basis.y * -centered.y * 0.025
		camera.global_transform = camera.global_transform.interpolate_with(target_transform, 1.0 - exp(-delta / 0.25))
	if overlay != null:
		overlay.queue_redraw()


func _on_viewport_resized() -> void:
	_update_room_backdrop()
	refresh_layout_for_current_viewport()


func _toggle_parallax() -> void:
	parallax_enabled = not parallax_enabled
	parallax_button.text = "鼠标微视差：开" if parallax_enabled else "鼠标微视差：关"
	if not parallax_enabled:
		camera.global_transform = base_camera_transform


func _toggle_table_material() -> void:
	use_uv_table = not use_uv_table
	tabletop_material.set_shader_parameter("use_uv_table", use_uv_table)
	material_button.text = "桌纹：顶视 UV" if use_uv_table else "桌纹：clean plate"


func _toggle_debug_mode() -> void:
	_apply_debug_mode(not debug_mode)


func _apply_debug_mode(enabled: bool = debug_mode) -> void:
	debug_mode = enabled
	if watermark_label == null:
		return
	overlay.visible = debug_mode
	debug_panel.visible = debug_mode
	debug_controls.visible = debug_mode
	proxy_label.visible = debug_mode
	watermark_label.text = "构图校准 / 非正式美术" if debug_mode else "构图校准 / 非正式美术 · 对手为未验收静态代理"
	watermark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if debug_mode else HORIZONTAL_ALIGNMENT_LEFT
	watermark_label.add_theme_font_size_override("font_size", 32 if debug_mode else 13)
	watermark_label.remove_theme_stylebox_override("normal")
	if debug_mode:
		watermark_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		watermark_label.offset_top = 14
		watermark_label.offset_bottom = 56
	else:
		watermark_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		watermark_label.position = Vector2(12, 8)
		watermark_label.size = Vector2(420, 24)
		watermark_label.add_theme_color_override("font_color", Color(0.9, 0.76, 0.52, 0.88))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		_save_screenshot("user://composition-calibration.png")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_toggle_debug_mode()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var origin := camera.project_ray_origin(event.position)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(event.position) * 100.0)
		query.collision_mask = 2
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var picked: Area3D = hit.collider
			var key: String = picked.get_meta("anchor_name", "?")
			status_label.text = "3D 射线命中：%s · %s" % [key, TARGET_LABELS.get(key, "牌槽 " + key)]


func _capture_requested_frame(args: PackedStringArray) -> void:
	for _frame in range(6):
		await get_tree().process_frame
	for arg: String in args:
		if arg.begins_with("--capture="):
			_save_screenshot(arg.trim_prefix("--capture="))
			break
	get_tree().quit()


func _save_screenshot(path: String) -> Error:
	var image := get_viewport().get_texture().get_image()
	if image.is_empty():
		return ERR_CANT_CREATE
	var absolute_path := ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var result := image.save_png(absolute_path)
	if status_label != null:
		status_label.text = "截图已保存：%s" % absolute_path if result == OK else "截图保存失败：%s" % error_string(result)
	return result
