extends Node3D
class_name StageCardView

const CARD_FACE_REGION := Rect2(363.0, 109.0, 335.0, 605.0)
const CARD_BACK_REGION := Rect2(718.0, 761.0, 335.0, 597.0)
const CARD_RATIO := 0.5524
const FACE_VIEWPORT := Vector2i(512, 936)
enum PlacementMode { HELD, TABLE }

var card_id := ""
var title := ""
var body := ""
var atlas_texture: Texture2D
var font: Font
var camera: Camera3D
var collision_layer := 8
var face_up := true
var screen_height_fraction := 0.30
var screen_center_x := 0.5
var screen_bottom_y := 0.8
var tabletop_y := 0.02
var textured_face := true
var card_width_world := 0.5
var card_height_world := 0.9
var card_thickness := 0.018
var placement_mode := PlacementMode.TABLE
var base_origin := Vector3.ZERO
var hovered := false
var selected := false
var local_base_position := Vector3.ZERO
var face_quad: MeshInstance3D
var back_quad: MeshInstance3D
var physical_body: MeshInstance3D
var face_pivot: Node3D
var hit_area: Area3D
var front_viewport: SubViewport
var viewport_textures: Array[SubViewport] = []


func _ready() -> void:
	_build_card_mesh()
	if textured_face:
		_build_text_viewport()
	_set_face_materials()
	_build_hit_area()


func _build_card_mesh() -> void:
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("b9ab88")
	paper.roughness = 1.0
	physical_body = MeshInstance3D.new()
	physical_body.name = "SolidCardCore"
	var box := BoxMesh.new()
	box.size = Vector3(card_width_world, card_height_world, card_thickness)
	box.material = paper
	physical_body.mesh = box
	physical_body.position.y = card_height_world * 0.5
	add_child(physical_body)

	face_pivot = Node3D.new()
	face_pivot.name = "FlipAxisLocalToPlacement"
	face_pivot.position.y = card_height_world * 0.5
	add_child(face_pivot)
	face_quad = _make_quad("FrontFace", Vector3(0.0, 0.0, card_thickness * 0.5 + 0.001))
	back_quad = _make_quad("BackFace", Vector3(0.0, 0.0, -card_thickness * 0.5 - 0.001))
	back_quad.rotation.y = PI
	face_pivot.add_child(face_quad)
	face_pivot.add_child(back_quad)


func _make_quad(node_name: String, local_position: Vector3) -> MeshInstance3D:
	var quad_instance := MeshInstance3D.new()
	quad_instance.name = node_name
	var quad := QuadMesh.new()
	quad.size = Vector2(card_width_world, card_height_world)
	quad_instance.mesh = quad
	quad_instance.position = local_position
	return quad_instance


func _build_text_viewport() -> void:
	front_viewport = SubViewport.new()
	front_viewport.name = "TypesetFaceSubViewport"
	front_viewport.size = FACE_VIEWPORT
	front_viewport.transparent_bg = true
	front_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(front_viewport)
	viewport_textures.append(front_viewport)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = Theme.new()
	root.theme.default_font = font
	front_viewport.add_child(root)

	var art_frame := TextureRect.new()
	art_frame.name = "OriginalEquipmentFrameAtlas"
	var atlas_region := AtlasTexture.new()
	atlas_region.atlas = atlas_texture
	atlas_region.region = CARD_FACE_REGION
	art_frame.texture = atlas_region
	art_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_frame.stretch_mode = TextureRect.STRETCH_SCALE
	art_frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(art_frame)

	var heading := Label.new()
	heading.name = "CardTitle"
	heading.text = title
	heading.position = Vector2(46, 156)
	heading.size = Vector2(420, 126)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_override("font", font)
	heading.add_theme_font_size_override("font_size", 96)
	heading.add_theme_color_override("font_color", Color("30261c"))
	root.add_child(heading)

	var copy := Label.new()
	copy.name = "CardBody"
	copy.text = body
	copy.position = Vector2(46, 448)
	copy.size = Vector2(420, 420)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_theme_font_override("font", font)
	copy.add_theme_font_size_override("font_size", 96)
	copy.add_theme_color_override("font_color", Color("30261c"))
	root.add_child(copy)

	var marker := Label.new()
	marker.name = "PrototypeDataMark"
	marker.text = "固定演示"
	marker.position = Vector2(142, 886)
	marker.size = Vector2(228, 34)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_theme_font_override("font", font)
	marker.add_theme_font_size_override("font_size", 26)
	marker.add_theme_color_override("font_color", Color("725a3c"))
	root.add_child(marker)


func _set_face_materials() -> void:
	var front := StandardMaterial3D.new()
	front.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	front.cull_mode = BaseMaterial3D.CULL_DISABLED
	front.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	front.albedo_texture = front_viewport.get_texture() if textured_face else null
	front.albedo_color = Color.WHITE if textured_face else Color("e3d7bc")
	front.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face_quad.material_override = front

	var back := StandardMaterial3D.new()
	back.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back.cull_mode = BaseMaterial3D.CULL_DISABLED
	back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# 3D StandardMaterial does not consistently honor AtlasTexture UV remaps
	# on Compatibility renderers. Keep the source image and crop its mesh UVs.
	var atlas_size := atlas_texture.get_size()
	back.albedo_texture = atlas_texture
	back.uv1_scale = Vector3(CARD_BACK_REGION.size.x / atlas_size.x, CARD_BACK_REGION.size.y / atlas_size.y, 1.0)
	back.uv1_offset = Vector3(CARD_BACK_REGION.position.x / atlas_size.x, CARD_BACK_REGION.position.y / atlas_size.y, 0.0)
	back.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back_quad.material_override = back


func _build_hit_area() -> void:
	hit_area = Area3D.new()
	hit_area.name = "CardPickArea"
	hit_area.collision_layer = collision_layer
	hit_area.collision_mask = 0
	hit_area.input_ray_pickable = false
	hit_area.set_meta("card_id", card_id)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(card_width_world, card_height_world * 0.62, card_thickness + 0.04)
	collision.shape = box
	collision.position.y = card_height_world * 0.31
	hit_area.add_child(collision)
	add_child(hit_area)


func place_from_screen(composition: Node3D, target_camera: Camera3D, center_x: float, bottom_y: float, height_fraction: float) -> void:
	placement_mode = PlacementMode.TABLE
	camera = target_camera
	screen_center_x = center_x
	screen_bottom_y = bottom_y
	screen_height_fraction = height_fraction
	var viewport_size := get_viewport().get_visible_rect().size
	var bottom_point: Vector3 = composition._world_at_screen_point(Vector2(center_x, bottom_y), tabletop_y)
	var top_point: Vector3 = composition._world_at_screen_point(Vector2(center_x, bottom_y - height_fraction), tabletop_y)
	var normalized_half_width := height_fraction * CARD_RATIO * viewport_size.y / viewport_size.x * 0.5
	var center_screen_y := bottom_y - height_fraction * 0.5
	var left_point: Vector3 = composition._world_at_screen_point(Vector2(center_x - normalized_half_width, center_screen_y), tabletop_y)
	var right_point: Vector3 = composition._world_at_screen_point(Vector2(center_x + normalized_half_width, center_screen_y), tabletop_y)
	card_height_world = bottom_point.distance_to(top_point)
	card_width_world = left_point.distance_to(right_point)
	card_thickness = maxf(card_height_world * 0.018, 0.012)
	base_origin = bottom_point
	# A right-handed surface frame: card-up runs toward the far side of the table.
	var table_basis := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	global_transform = Transform3D(table_basis, bottom_point)
	local_base_position = Vector3.ZERO
	_rebuild_geometry_dimensions()
	_set_hover_lift()
	set_face_up(face_up)


func place_held_from_screen(target_camera: Camera3D, center_x: float, bottom_y: float, height_fraction: float, view_depth: float = 12.0) -> void:
	placement_mode = PlacementMode.HELD
	camera = target_camera
	screen_center_x = center_x
	screen_bottom_y = bottom_y
	screen_height_fraction = height_fraction
	var viewport_size := get_viewport().get_visible_rect().size
	var bottom_screen := Vector2(center_x * viewport_size.x, bottom_y * viewport_size.y)
	var bottom_point := target_camera.project_position(bottom_screen, view_depth)
	card_height_world = 2.0 * view_depth * tan(deg_to_rad(target_camera.fov * 0.5)) * height_fraction
	card_width_world = card_height_world * CARD_RATIO
	card_thickness = maxf(card_height_world * 0.018, 0.012)
	base_origin = bottom_point
	global_transform = Transform3D(target_camera.global_basis, bottom_point)
	local_base_position = Vector3.ZERO
	_rebuild_geometry_dimensions()
	_set_hover_lift()
	set_face_up(face_up)


func _rebuild_geometry_dimensions() -> void:
	if physical_body == null:
		return
	var box := physical_body.mesh as BoxMesh
	box.size = Vector3(card_width_world, card_height_world, card_thickness)
	physical_body.position.y = card_height_world * 0.5
	face_pivot.position.y = card_height_world * 0.5
	(face_quad.mesh as QuadMesh).size = Vector2(card_width_world, card_height_world)
	(back_quad.mesh as QuadMesh).size = Vector2(card_width_world, card_height_world)
	face_quad.position = Vector3(0.0, 0.0, card_thickness * 0.5 + 0.001)
	back_quad.position = Vector3(0.0, 0.0, -card_thickness * 0.5 - 0.001)
	if hit_area != null:
		var hit_shape := hit_area.get_child(0) as CollisionShape3D
		var hit_box := hit_shape.shape as BoxShape3D
		hit_box.size = Vector3(card_width_world, card_height_world * 0.62, card_thickness + 0.04)
		hit_shape.position.y = card_height_world * 0.31


func set_face_up(value: bool) -> void:
	face_up = value
	if face_pivot != null:
		face_pivot.rotation = Vector3.ZERO
		face_pivot.rotation.x = 0.0 if face_up else PI


func set_hover_state(is_hovered: bool, is_selected: bool = false) -> void:
	hovered = is_hovered
	selected = is_selected
	_set_hover_lift()


func _set_hover_lift() -> void:
	if camera == null:
		return
	var lift := 0.24 if selected else (0.14 if hovered else 0.0)
	global_position = base_origin + (camera.global_basis.y if placement_mode == PlacementMode.HELD else Vector3.UP) * lift


func get_lift_vector() -> Vector3:
	return camera.global_basis.y if placement_mode == PlacementMode.HELD else Vector3.UP
