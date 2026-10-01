extends RefCounted
# 代码拼出来的占位模型（基本几何体）。以后 assets/ 里放了 glTF 就自动优先用 glTF。
# 约定：长度单位=米；随从全高约 0.22；原点在脚下中心，面朝 -Z；每个配件以挂点原点为中心。

static func mat(color: Color, rough: float = 0.55, metal: float = 0.1, emit: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

static func _mi(mesh: Mesh, m: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = m
	n.position = pos
	n.rotation_degrees = rot
	n.scale = scl
	return n

static func box(size: Vector3, m: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, m, pos, rot)

static func sphere(r: float, m: Material, pos: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return _mi(s, m, pos, Vector3.ZERO, scl)

static func cyl(r_top: float, r_bot: float, h: float, m: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 16
	return _mi(c, m, pos, rot)

static func capsule(r: float, h: float, m: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return _mi(c, m, pos)

static func torus(inner: float, outer: float, m: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 20
	t.ring_segments = 8
	return _mi(t, m, pos, rot)

# ------------------------------------------------------------ 身体（含挂点）
static func _sockets(root: Node3D, h: float, w: float) -> void:
	var defs := {
		"head": Vector3(0, h, 0), "back": Vector3(0, h * 0.62, w * 0.55), "shoulder_l": Vector3(-w * 0.9, h * 0.78, 0),
		"shoulder_r": Vector3(w * 0.9, h * 0.78, 0), "hand_l": Vector3(-w * 1.25, h * 0.5, -w * 0.3),
		"hand_r": Vector3(w * 1.25, h * 0.5, -w * 0.3), "chest": Vector3(0, h * 0.58, -w * 0.62),
		"waist": Vector3(0, h * 0.36, 0), "aura": Vector3(0, 0.012, 0), "ghost": Vector3(0, 0, 0),
	}
	for k in defs:
		var s := Node3D.new()
		s.name = "Socket_" + k
		s.position = defs[k]
		root.add_child(s)

static func body(kind: String, col: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Body"
	var base_m := mat(col.darkened(0.35), 0.7, 0.2)
	var skin := mat(Color("e8d2b8"), 0.8)
	var cloth := mat(col, 0.65)
	root.add_child(cyl(0.062, 0.07, 0.014, base_m, Vector3(0, 0.007, 0)))
	match kind:
		"body_sword":
			root.add_child(cyl(0.012, 0.016, 0.07, cloth, Vector3(-0.018, 0.05, 0)))
			root.add_child(cyl(0.012, 0.016, 0.07, cloth, Vector3(0.018, 0.05, 0)))
			root.add_child(capsule(0.04, 0.1, cloth, Vector3(0, 0.12, 0)))
			root.add_child(sphere(0.032, skin, Vector3(0, 0.19, 0)))
			root.add_child(box(Vector3(0.072, 0.012, 0.012), mat(col.lightened(0.2)), Vector3(0, 0.195, -0.03)))
			_sockets(root, 0.215, 0.045)
		"body_shield":
			root.add_child(box(Vector3(0.1, 0.1, 0.07), cloth, Vector3(0, 0.07, 0)))
			root.add_child(box(Vector3(0.12, 0.05, 0.08), mat(col.darkened(0.15)), Vector3(0, 0.14, 0)))
			root.add_child(sphere(0.034, skin, Vector3(0, 0.19, 0)))
			root.add_child(sphere(0.04, mat(col.lightened(0.1), 0.4, 0.5), Vector3(0, 0.2, 0.0), Vector3(1, 0.75, 1)))
			_sockets(root, 0.225, 0.06)
		"body_mage":
			root.add_child(cyl(0.02, 0.06, 0.14, cloth, Vector3(0, 0.08, 0)))
			root.add_child(sphere(0.03, skin, Vector3(0, 0.19, 0)))
			root.add_child(cyl(0.0, 0.04, 0.06, mat(col.darkened(0.2)), Vector3(0, 0.24, 0)))
			root.add_child(cyl(0.05, 0.05, 0.006, mat(col.darkened(0.2)), Vector3(0, 0.215, 0)))
			_sockets(root, 0.26, 0.04)
		"body_bow":
			root.add_child(cyl(0.008, 0.012, 0.07, cloth, Vector3(-0.014, 0.05, 0)))
			root.add_child(cyl(0.008, 0.012, 0.07, cloth, Vector3(0.014, 0.05, 0)))
			root.add_child(capsule(0.03, 0.09, cloth, Vector3(0, 0.12, 0)))
			root.add_child(sphere(0.028, skin, Vector3(0, 0.185, 0)))
			root.add_child(cyl(0.0, 0.04, 0.05, mat(col.darkened(0.25)), Vector3(0, 0.205, 0.01)))
			_sockets(root, 0.22, 0.04)
		"body_wisp":
			var gm := mat(col.lightened(0.15), 0.3, 0.0, 0.8, 0.82)
			root.add_child(sphere(0.045, gm, Vector3(0, 0.14, 0)))
			root.add_child(cyl(0.035, 0.0, 0.1, gm, Vector3(0, 0.07, 0)))
			root.add_child(sphere(0.008, mat(Color("1a1a24")), Vector3(-0.015, 0.15, -0.04)))
			root.add_child(sphere(0.008, mat(Color("1a1a24")), Vector3(0.015, 0.15, -0.04)))
			_sockets(root, 0.2, 0.04)
		_:
			root.add_child(capsule(0.04, 0.12, cloth, Vector3(0, 0.1, 0)))
			_sockets(root, 0.2, 0.04)
	return root

# ------------------------------------------------------------ 配件
static func part(kind: String, col: Color) -> Node3D:
	var n := Node3D.new()
	n.name = "Part_" + kind
	var m := mat(col, 0.35, 0.5)
	var glow := mat(col, 0.3, 0.0, 1.4)
	match kind:
		"sword":
			n.add_child(box(Vector3(0.012, 0.1, 0.005), mat(col, 0.25, 0.8), Vector3(0, 0.06, 0)))
			n.add_child(box(Vector3(0.04, 0.008, 0.01), mat(Color("c8a050"), 0.4, 0.6), Vector3(0, 0.008, 0)))
			n.add_child(cyl(0.006, 0.006, 0.03, mat(Color("5a3a20")), Vector3(0, -0.012, 0)))
		"shield":
			n.add_child(cyl(0.045, 0.045, 0.01, m, Vector3(0, 0, -0.01), Vector3(90, 0, 0)))
			n.add_child(sphere(0.014, mat(Color("d8b050"), 0.3, 0.8), Vector3(0, 0, -0.02)))
		"buckler":
			n.add_child(cyl(0.03, 0.03, 0.008, m, Vector3(0, 0, -0.008), Vector3(90, 0, 0)))
		"cape":
			n.add_child(box(Vector3(0.09, 0.14, 0.006), mat(col, 0.8), Vector3(0, -0.02, 0.02), Vector3(8, 0, 0)))
		"thorns":
			for i in 3:
				n.add_child(cyl(0.0, 0.01, 0.045, mat(col, 0.5, 0.2), Vector3(0.012 * i, 0.012 + 0.006 * i, 0), Vector3(0, 0, -30 + 25 * i)))
		"vines":
			n.add_child(torus(0.006, 0.03, mat(Color("3a8a48")), Vector3(0, 0.0, 0), Vector3(70, 0, 0)))
			n.add_child(sphere(0.012, mat(Color("f0a0c0"), 0.5, 0.0, 0.3), Vector3(0.02, 0.012, 0.02)))
			n.add_child(sphere(0.01, mat(Color("f8e080"), 0.5, 0.0, 0.3), Vector3(-0.02, 0.01, -0.015)))
		"twin_ring":
			n.add_child(torus(0.003, 0.02, glow, Vector3(-0.012, 0, -0.01), Vector3(90, 0, 0)))
			n.add_child(torus(0.003, 0.02, glow, Vector3(0.012, 0, -0.01), Vector3(90, 0, 0)))
		"amulet":
			n.add_child(sphere(0.014, glow, Vector3(0, 0, -0.01)))
			n.add_child(torus(0.002, 0.016, mat(Color("c8a050"), 0.4, 0.8), Vector3(0, 0, -0.01), Vector3(90, 0, 0)))
		"ring_double":
			n.add_child(torus(0.004, 0.07, glow, Vector3(0, 0.004, 0)))
			n.add_child(torus(0.004, 0.092, mat(col, 0.3, 0.0, 0.9, 0.7), Vector3(0, 0.012, 0)))
		"afterimage":
			n.add_child(capsule(0.04, 0.12, mat(col, 0.3, 0.0, 0.9, 0.35), Vector3(0.05, 0.11, 0.03)))
		"hourglass":
			n.add_child(cyl(0.0, 0.016, 0.03, m, Vector3(0, 0.015, 0)))
			n.add_child(cyl(0.016, 0.0, 0.03, m, Vector3(0, -0.015, 0)))
			n.add_child(cyl(0.02, 0.02, 0.004, mat(Color("8a6a40")), Vector3(0, 0.032, 0)))
			n.add_child(cyl(0.02, 0.02, 0.004, mat(Color("8a6a40")), Vector3(0, -0.032, 0)))
		"mirror":
			n.add_child(cyl(0.03, 0.03, 0.006, mat(col, 0.1, 0.9), Vector3(0, 0.02, -0.01), Vector3(90, 0, 0)))
			n.add_child(torus(0.003, 0.032, mat(Color("c8a050"), 0.4, 0.8), Vector3(0, 0.02, -0.01), Vector3(90, 0, 0)))
			n.add_child(cyl(0.004, 0.004, 0.04, mat(Color("5a3a20")), Vector3(0, -0.015, -0.01)))
		"wand":
			n.add_child(cyl(0.004, 0.004, 0.11, mat(Color("5a3a20")), Vector3(0, 0.03, 0)))
			n.add_child(sphere(0.014, glow, Vector3(0, 0.095, 0)))
		"halo":
			n.add_child(torus(0.004, 0.034, mat(col, 0.3, 0.0, 1.6), Vector3(0, 0.05, 0)))
		"chains":
			for i in 6:
				var a := TAU * float(i) / 6.0
				n.add_child(torus(0.003, 0.009, m, Vector3(cos(a) * 0.045, 0, sin(a) * 0.045), Vector3(90, rad_to_deg(-a), 0)))
		"mask":
			n.add_child(sphere(0.026, mat(col, 0.6), Vector3(0, -0.005, -0.03), Vector3(1, 1.1, 0.4)))
			n.add_child(box(Vector3(0.008, 0.003, 0.004), mat(Color("1a1a24")), Vector3(-0.01, 0.0, -0.045)))
			n.add_child(box(Vector3(0.008, 0.003, 0.004), mat(Color("1a1a24")), Vector3(0.01, 0.0, -0.045)))
		"book":
			n.add_child(box(Vector3(0.04, 0.05, 0.012), mat(col, 0.7), Vector3(0, 0, 0.02)))
			n.add_child(box(Vector3(0.036, 0.046, 0.002), mat(Color("f0e8d0")), Vector3(0, 0, 0.027)))
		_:
			n.add_child(sphere(0.012, glow))
	return n

# 状态特效（占位）：绕着随从的一圈光环/粒子感
static func status_fx(kind: String, col: Color) -> Node3D:
	var n := Node3D.new()
	n.name = "Fx_" + kind
	var glow := mat(col, 0.3, 0.0, 1.5, 0.75)
	match kind:
		"aura_shield":
			n.add_child(sphere(0.1, mat(col, 0.2, 0.0, 0.6, 0.28), Vector3(0, 0.11, 0)))
		"aura_lock":
			n.add_child(torus(0.004, 0.06, glow, Vector3(0, 0.13, 0), Vector3(90, 0, 0)))
			n.add_child(box(Vector3(0.03, 0.03, 0.01), mat(col), Vector3(0, 0.13, -0.065)))
		"aura_link":
			n.add_child(torus(0.003, 0.08, glow, Vector3(0, 0.1, 0), Vector3(60, 0, 0)))
		_:
			n.add_child(torus(0.005, 0.075, glow, Vector3(0, 0.016, 0)))
			for i in 4:
				var a := TAU * float(i) / 4.0
				n.add_child(sphere(0.008, glow, Vector3(cos(a) * 0.075, 0.07, sin(a) * 0.075)))
	return n
