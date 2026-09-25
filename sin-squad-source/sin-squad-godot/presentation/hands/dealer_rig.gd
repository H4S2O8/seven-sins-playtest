extends Node3D
class_name DealerRigView

const DEALER_ATLAS := "res://assets/sources/dealers/dealer-rig-v2.png"
const FONT_PATH := "res://assets/fonts/NotoSansSC-Full.ttf"
const PARTS := {
	# Alpha component bounds measured from dealer-rig-v2.png (1448x1086).
	# Hood is deliberately cropped at the neck so its collar doesn't double the torso collar.
	"hood": Rect2(80.0, 10.0, 284.0, 286.0),
	"torso": Rect2(416.0, 10.0, 344.0, 438.0),
	"upper_left": Rect2(861.0, 94.0, 209.0, 326.0),
	"upper_right": Rect2(1144.0, 93.0, 203.0, 326.0),
	"fore_left": Rect2(76.0, 459.0, 246.0, 262.0),
	"fore_right": Rect2(422.0, 465.0, 243.0, 259.0),
	"hand_left": Rect2(769.0, 520.0, 278.0, 167.0),
	"hand_right": Rect2(1135.0, 525.0, 237.0, 161.0),
}

var atlas: Texture2D
var camera: Camera3D
var font: Font
var dealer_nodes: Dictionary = {}
var deal_contact_anchors: Dictionary = {}
var arm_pivots: Dictionary = {}


func _ready() -> void:
	atlas = load(DEALER_ATLAS) as Texture2D
	font = load(FONT_PATH) as Font


func build_upper_body(side: String, composition: Node3D, screen_center: Vector2, hand_target: Vector2, height_fraction: float, mirror: bool = false) -> Node3D:
	camera = composition.camera
	var dealer := Node3D.new()
	dealer.name = "Dealer%sStaticCutoutRig" % side.capitalize()
	var viewport_size := get_viewport().get_visible_rect().size
	var center_pixel := Vector2(screen_center.x * viewport_size.x, screen_center.y * viewport_size.y)
	var depth := 16.0
	var camera_basis := camera.global_basis.orthonormalized()
	var center_world := camera.project_position(center_pixel, depth)
	dealer.global_transform = Transform3D(camera_basis, center_world)
	if mirror:
		dealer.scale.x = -1.0
	add_child(dealer)
	# Preserve the existing authored torso height; the composed crop extends
	# above/below it to include the hood and forearms without shrinking the
	# dealer on the table.
	var source_pixels_per_screen_height: float = PARTS["torso"].size.y
	var adjacent_pixel_world := camera.project_position(center_pixel + Vector2(0.0, 1.0), depth)
	var world_per_screen_pixel := center_world.distance_to(adjacent_pixel_world)
	var pixel_size := viewport_size.y * height_fraction * world_per_screen_pixel / source_pixels_per_screen_height
	var body_width := PARTS["torso"].size.x * pixel_size
	var body_height := PARTS["torso"].size.y * pixel_size
	# The source is a parts atlas, not one contiguous character.  Compose only
	# the hood and torso at their authored aspect ratio; cropping the full atlas
	# would also expose the spare legs/boots above the table.
	var torso := _add_part(dealer, "Torso", "torso", Vector3.ZERO, pixel_size, 0.0)
	var hood_y := (PARTS["torso"].size.y * 0.40) * pixel_size
	_add_part(dealer, "HoodHead", "hood", Vector3(0.0, hood_y, 0.008), pixel_size, 0.0)
	# Retain the articulated hierarchy for entry/reach API compatibility, but
	# keep its individual sprites hidden so animation cannot tear the silhouette.
	var torso_center := PARTS["torso"].position + PARTS["torso"].size * 0.5
	var left_shoulder_source := Vector2(436.0, 145.0)
	var right_shoulder_source := Vector2(719.0, 140.0)
	var left_shoulder := _source_delta(torso_center, left_shoulder_source, pixel_size)
	var right_shoulder := _source_delta(torso_center, right_shoulder_source, pixel_size)
	_build_arm(dealer, "Left", "upper_left", "fore_left", "hand_left", Vector2(881.0, 155.0), Vector2(1018.0, 352.0), Vector2(129.0, 474.0), Vector2(288.0, 672.0), Vector2(801.0, 547.0), Vector2(left_shoulder.x * 0.82, left_shoulder.y), pixel_size)
	_build_arm(dealer, "Right", "upper_right", "fore_right", "hand_right", Vector2(1316.0, 155.0), Vector2(1170.0, 352.0), Vector2(596.0, 480.0), Vector2(450.0, 673.0), Vector2(1159.0, 549.0), Vector2(right_shoulder.x * 0.82, right_shoulder.y), pixel_size)
	for pivot_name in ["LeftShoulderPivot", "RightShoulderPivot"]:
		var pivot := dealer.get_node_or_null(pivot_name) as Node3D
		if pivot != null:
			for child in pivot.find_children("*", "MeshInstance3D", true, false):
				(child as MeshInstance3D).visible = false
	arm_pivots[side] = {
		"left_shoulder": dealer.get_node("LeftShoulderPivot"),
		"left_elbow": dealer.get_node("LeftShoulderPivot/LeftElbowPivot"),
		"right_shoulder": dealer.get_node("RightShoulderPivot"),
		"right_elbow": dealer.get_node("RightShoulderPivot/RightElbowPivot"),
	}
	var marker := Label3D.new()
	marker.name = "StaticAssemblyMark"
	marker.text = "荷官完整上半身合成 · 整体动作稳定"
	marker.font = font
	marker.font_size = 40
	marker.pixel_size = pixel_size * 0.8
	marker.modulate = Color("d4c39e")
	marker.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	marker.position = Vector3(0.0, body_height * 0.95, 0.06)
	dealer.add_child(marker)
	var contact := Node3D.new()
	contact.name = "CardTransferContact"
	var contact_world: Vector3 = composition._world_at_screen_point(hand_target, composition.target_points["P_RECEIVE"].z if side == "player" else composition.target_points["O_RECEIVE"].z)
	dealer.add_child(contact)
	contact.global_position = contact_world
	deal_contact_anchors[side] = contact
	dealer_nodes[side] = dealer
	return dealer


func get_contact_anchor(side: String) -> Vector3:
	if not deal_contact_anchors.has(side):
		return Vector3.ZERO
	return (deal_contact_anchors[side] as Node3D).global_position


func set_entry_reach(side: String, reach: float, settle: float = 0.0) -> void:
	if not arm_pivots.has(side):
		return
	var pivots: Dictionary = arm_pivots[side]
	var amount := clampf(reach, 0.0, 1.0)
	var recover := clampf(settle, 0.0, 1.0)
	var direction := -1.0 if side == "player" else 1.0
	(pivots["left_shoulder"] as Node3D).rotation.z = direction * deg_to_rad(-10.0 * amount + 3.0 * recover)
	(pivots["left_elbow"] as Node3D).rotation.z = direction * deg_to_rad(16.0 * amount - 5.0 * recover)
	(pivots["right_shoulder"] as Node3D).rotation.z = direction * deg_to_rad(7.0 * amount - 2.0 * recover)
	(pivots["right_elbow"] as Node3D).rotation.z = direction * deg_to_rad(-12.0 * amount + 4.0 * recover)


func _add_part(parent: Node3D, node_name: String, key: String, local_position: Vector3, pixel_size: float, roll: float) -> MeshInstance3D:
	var sprite := MeshInstance3D.new()
	sprite.name = node_name
	var region: Rect2 = PARTS[key]
	var quad := QuadMesh.new()
	quad.size = region.size
	sprite.mesh = quad
	sprite.scale = Vector3(pixel_size, pixel_size, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.albedo_texture = atlas
	var atlas_size := Vector2(atlas.get_size())
	material.uv1_scale = Vector3(region.size.x / atlas_size.x, region.size.y / atlas_size.y, 1.0)
	material.uv1_offset = Vector3(region.position.x / atlas_size.x, region.position.y / atlas_size.y, 0.0)
	sprite.material_override = material
	sprite.position = local_position
	sprite.rotation.z = roll
	parent.add_child(sprite)
	return sprite


func _add_region_part(parent: Node3D, node_name: String, region: Rect2, local_position: Vector3, pixel_size: float) -> MeshInstance3D:
	var sprite := MeshInstance3D.new()
	sprite.name = node_name
	var quad := QuadMesh.new()
	quad.size = region.size
	sprite.mesh = quad
	sprite.scale = Vector3(pixel_size, pixel_size, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.albedo_texture = atlas
	var atlas_size := Vector2(atlas.get_size())
	material.uv1_scale = Vector3(region.size.x / atlas_size.x, region.size.y / atlas_size.y, 1.0)
	material.uv1_offset = Vector3(region.position.x / atlas_size.x, region.position.y / atlas_size.y, 0.0)
	sprite.material_override = material
	sprite.position = local_position
	parent.add_child(sprite)
	return sprite


func _build_arm(parent: Node3D, prefix: String, upper_key: String, forearm_key: String, hand_key: String, upper_shoulder_source: Vector2, elbow_source: Vector2, forearm_elbow_source: Vector2, wrist_source: Vector2, hand_wrist_source: Vector2, shoulder_target: Vector2, pixel_size: float) -> void:
	var shoulder := Node3D.new()
	shoulder.name = prefix + "ShoulderPivot"
	shoulder.position = Vector3(shoulder_target.x, shoulder_target.y, 0.018)
	shoulder.rotation.z = 0.0
	parent.add_child(shoulder)
	_add_anchored_sprite(shoulder, prefix + "UpperArm", upper_key, upper_shoulder_source, pixel_size, 0.0)

	var elbow := Node3D.new()
	elbow.name = prefix + "ElbowPivot"
	elbow.position = _source_delta(upper_shoulder_source, elbow_source, pixel_size) + Vector3(0.0, 0.0, 0.012)
	shoulder.add_child(elbow)
	_add_anchored_sprite(elbow, prefix + "Forearm", forearm_key, forearm_elbow_source, pixel_size, 0.0)

	var wrist := Node3D.new()
	wrist.name = prefix + "WristPivot"
	wrist.position = _source_delta(forearm_elbow_source, wrist_source, pixel_size) + Vector3(0.0, 0.0, 0.012)
	elbow.add_child(wrist)
	_add_anchored_sprite(wrist, prefix + "Hand", hand_key, hand_wrist_source, pixel_size, 0.0)


func _add_anchored_sprite(parent: Node3D, node_name: String, key: String, source_anchor: Vector2, pixel_size: float, front_offset: float) -> MeshInstance3D:
	var region: Rect2 = PARTS[key]
	var source_center := region.position + region.size * 0.5
	var anchor_offset := Vector3((source_anchor.x - source_center.x) * pixel_size, (source_center.y - source_anchor.y) * pixel_size, 0.0)
	return _add_part(parent, node_name, key, -anchor_offset + Vector3(0.0, 0.0, front_offset), pixel_size, 0.0)


func _source_delta(from_source: Vector2, to_source: Vector2, pixel_size: float) -> Vector3:
	return Vector3((to_source.x - from_source.x) * pixel_size, -(to_source.y - from_source.y) * pixel_size, 0.0)
