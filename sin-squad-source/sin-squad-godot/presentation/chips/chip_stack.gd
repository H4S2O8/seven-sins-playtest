extends Node3D
class_name StageChipStack

const CHIP_THICKNESS := 0.080
const CHIP_RADIUS := 0.36
const MAX_VISIBLE_CHIPS := 7
const CHIP_ATLAS_PATH := "res://assets/sources/chips/chip-atlas-v1.png"
const TOP_REGIONS := [
	Rect2(18.0, 165.0, 422.0, 278.0), Rect2(456.0, 165.0, 422.0, 278.0),
	Rect2(895.0, 165.0, 423.0, 278.0), Rect2(1334.0, 165.0, 422.0, 278.0),
]
const SIDE_REGIONS := [
	Rect2(19.0, 443.0, 417.0, 299.0), Rect2(457.0, 443.0, 418.0, 299.0),
	Rect2(897.0, 443.0, 420.0, 299.0), Rect2(1338.0, 443.0, 417.0, 299.0),
]

var denomination := 1
var amount := 1
var font: Font
var tint := Color("6f3028")
var chip_nodes: Array[Node3D] = []
var is_public_pot := false
var chip_atlas: Texture2D


func _ready() -> void:
	chip_atlas = load(CHIP_ATLAS_PATH) as Texture2D
	_build_stack()


func configure(value: int, count: int, ink: Color, label_font: Font, public_pot: bool = false) -> void:
	denomination = value
	amount = count
	tint = ink
	font = label_font
	is_public_pot = public_pot


func _build_stack() -> void:
	for child in get_children():
		child.queue_free()
	chip_nodes.clear()
	if is_public_pot:
		_build_pot_tray()
		_add_pick_area(0.46, 0.12)
		return
	var visible_count := clampi(amount, 1, MAX_VISIBLE_CHIPS)
	for index in range(visible_count):
		var chip := Node3D.new()
		chip.name = "Chip_%02d_%d" % [denomination, index + 1]
		chip.position.y = index * CHIP_THICKNESS
		add_child(chip)
		chip_nodes.append(chip)
		_build_chip_disc(chip, index == visible_count - 1)
	_add_pick_area(CHIP_RADIUS * 1.1, maxf(float(visible_count) * CHIP_THICKNESS, CHIP_THICKNESS))


func _add_pick_area(radius: float, height: float) -> void:
	var area := Area3D.new()
	area.name = "ChipStackRayPickArea"
	area.collision_layer = 32
	area.collision_mask = 0
	area.input_ray_pickable = false
	area.set_meta("chip_stack", true)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height + 0.04
	collision.shape = shape
	collision.position.y = height * 0.5
	area.add_child(collision)
	add_child(area)


func _build_chip_disc(chip: Node3D, top_chip: bool) -> void:
	var core := MeshInstance3D.new()
	core.name = "CarvedWoodChip"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = CHIP_RADIUS
	cylinder.bottom_radius = CHIP_RADIUS
	cylinder.height = CHIP_THICKNESS
	cylinder.radial_segments = 32
	cylinder.rings = 3
	core.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.96
	core.material_override = material
	chip.add_child(core)

	_add_textured_side(chip)
	_add_top_face(chip)

	if top_chip:
		var engraving := Label3D.new()
		engraving.name = "DenominationEngraving"
		engraving.text = str(denomination)
		engraving.font = font
		engraving.font_size = 54
		engraving.pixel_size = 0.0012
		engraving.modulate = Color("eadbb9")
		engraving.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		engraving.position = Vector3(0.0, CHIP_THICKNESS * 0.53, 0.0)
		engraving.rotation.x = -PI * 0.5
		chip.add_child(engraving)


func _add_textured_side(chip: Node3D) -> void:
	var region := _atlas_side_region()
	var atlas_size := Vector2(chip_atlas.get_size())
	var material := _atlas_material(region, atlas_size)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 48
	for index in range(SEGMENTS + 1):
		var angle := TAU * float(index) / SEGMENTS
		var radial := Vector3(sin(angle), 0.0, cos(angle))
		vertices.append(radial * (CHIP_RADIUS + 0.001) + Vector3.UP * (CHIP_THICKNESS * 0.5))
		vertices.append(radial * (CHIP_RADIUS + 0.001) - Vector3.UP * (CHIP_THICKNESS * 0.5))
		normals.append(radial)
		normals.append(radial)
		uvs.append(Vector2(float(index) / SEGMENTS, 1.0))
		uvs.append(Vector2(float(index) / SEGMENTS, 0.0))
		if index < SEGMENTS:
			var base := index * 2
			indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var side := MeshInstance3D.new()
	side.name = "AtlasWoodgrainSideBand"
	side.mesh = mesh
	side.material_override = material
	chip.add_child(side)


func _add_top_face(chip: Node3D) -> void:
	var region := _atlas_top_region()
	var atlas_size := Vector2(chip_atlas.get_size())
	var face := MeshInstance3D.new()
	face.name = "AtlasEngravedTopFace"
	var quad := QuadMesh.new()
	quad.size = Vector2(CHIP_RADIUS * 2.0, CHIP_RADIUS * 2.0)
	face.mesh = quad
	face.rotation.x = -PI * 0.5
	face.position.y = CHIP_THICKNESS * 0.5 + 0.002
	face.material_override = _atlas_material(region, atlas_size)
	chip.add_child(face)


func _atlas_top_region() -> Rect2:
	var chip_index := [1, 5, 25, 100].find(denomination)
	return TOP_REGIONS[maxi(chip_index, 0)]


func _atlas_side_region() -> Rect2:
	var chip_index := [1, 5, 25, 100].find(denomination)
	return SIDE_REGIONS[maxi(chip_index, 0)]


func _atlas_material(region: Rect2, atlas_size: Vector2) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.albedo_texture = chip_atlas
	material.uv1_scale = Vector3(region.size.x / atlas_size.x, region.size.y / atlas_size.y, 1.0)
	material.uv1_offset = Vector3(region.position.x / atlas_size.x, region.position.y / atlas_size.y, 0.0)
	return material


func _build_pot_tray() -> void:
	var dish := MeshInstance3D.new()
	dish.name = "PublicCopperBowl"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.44
	cylinder.bottom_radius = 0.37
	cylinder.height = 0.10
	cylinder.radial_segments = 48
	dish.mesh = cylinder
	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color("694a31")
	copper.roughness = 0.86
	dish.material_override = copper
	add_child(dish)
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.36
	rim_mesh.outer_radius = 0.43
	rim_mesh.rings = 40
	rim_mesh.ring_segments = 8
	rim.mesh = rim_mesh
	rim.position.y = 0.055
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("a98b51")
	gold.roughness = 1.0
	rim.material_override = gold
	add_child(rim)


func set_demo_count(new_amount: int) -> void:
	amount = maxi(0, new_amount)
	_build_stack()


func get_visual_chip_count() -> int:
	return chip_nodes.size()
