extends Node3D
class_name PlayerHandRig

const HAND_ATLAS := "res://assets/sources/hands/player-hand-poses-v2.png"
const REGIONS := {
	"left_grip": Rect2(34.0, 29.0, 449.0, 483.0),
	"right_rest": Rect2(558.0, 101.0, 447.0, 407.0),
	"left_pinch": Rect2(22.0, 543.0, 465.0, 481.0),
	"right_push": Rect2(563.0, 588.0, 443.0, 440.0),
	"left_release": Rect2(24.0, 1020.0, 477.0, 484.0),
	"right_point": Rect2(563.0, 1020.0, 443.0, 484.0),
}
var atlas: Texture2D
var camera: Camera3D
var hands: Dictionary = {}
var hand_sprites: Dictionary = {}
var font: Font


func configure(target_camera: Camera3D, label_font: Font) -> void:
	camera = target_camera
	font = label_font
	atlas = load(HAND_ATLAS) as Texture2D


func create_hand(side: String, initial_pose: String, composition: Node3D, screen_anchor: Vector2, desired_height_fraction: float, world_per_pixel: float, view_depth: float = 6.25) -> Node3D:
	var hand_root := Node3D.new()
	hand_root.name = "Player%sHand" % side.capitalize()
	var normalized := screen_anchor
	var viewport_size := get_viewport().get_visible_rect().size
	var point := camera.project_position(Vector2(normalized.x * viewport_size.x, normalized.y * viewport_size.y), view_depth)
	hand_root.global_transform = Transform3D(camera.global_basis.orthonormalized(), point)
	add_child(hand_root)
	var region: Rect2 = REGIONS[initial_pose]
	var desired_pixels := get_viewport().get_visible_rect().size.y * desired_height_fraction
	var scale_factor := desired_pixels / region.size.y
	var sprite := _make_sprite("AtlasPose_" + initial_pose, region, world_per_pixel, scale_factor)
	sprite.position.z = -0.045 if side == "left" else -0.06
	hand_root.add_child(sprite)
	hands[side] = hand_root
	hand_sprites[side] = sprite
	return hand_root


func set_pose(side: String, pose: String) -> void:
	if not hand_sprites.has(side) or not REGIONS.has(pose):
		return
	var sprite: MeshInstance3D = hand_sprites[side]
	_set_region(sprite, REGIONS[pose])


func get_pose_count() -> int:
	return REGIONS.size()


func _make_sprite(node_name: String, region: Rect2, pixel_size: float, scale_factor: float) -> MeshInstance3D:
	var sprite := MeshInstance3D.new()
	sprite.name = node_name
	var quad := QuadMesh.new()
	quad.size = region.size
	sprite.mesh = quad
	sprite.scale = Vector3(pixel_size * scale_factor, pixel_size * scale_factor, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.albedo_texture = atlas
	sprite.material_override = material
	_set_region(sprite, region)
	return sprite


func _set_region(sprite: MeshInstance3D, region: Rect2) -> void:
	var material := sprite.material_override as StandardMaterial3D
	var atlas_size := Vector2(atlas.get_size())
	material.uv1_scale = Vector3(region.size.x / atlas_size.x, region.size.y / atlas_size.y, 1.0)
	material.uv1_offset = Vector3(region.position.x / atlas_size.x, region.position.y / atlas_size.y, 0.0)
