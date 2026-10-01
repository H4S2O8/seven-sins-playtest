extends Node3D
# 3D 牌桌：我坐在桌前（第一人称），对面坐着对手；桌上两排随从，右侧是行动点筹码。
# 所有动画与移动由代码驱动；模型可以以后整体替换（见 assets/ 与 appearance.json）。

const Proc = preload("res://scripts/view3d/proc_parts.gd")
const Minion3D = preload("res://scripts/view3d/minion3d.gd")
const K = preload("res://scripts/ui/kit.gd")

signal minion_clicked(uid)
signal minion_hovered(uid)

const SLOT_DX := 0.27
const ROW_Z := 0.30

var cam: Camera3D
var minions: Dictionary = {}       # uid -> Minion3D
var ap_stacks: Array = [null, null]
var ap_labels: Array = [null, null]
var ap_shown: Array = [0, 0]
var opponent: Node3D
var _hover_uid := -1
var _t := 0.0
var enabled_input := true
var sway := Vector2.ZERO
var intent_root: Node3D
# 两种视角：seat = 坐在桌前（第一人称，看结算）；top = 俯视棋盘（宣告时，像炉石一样摆开 5 对 5）
const VIEWS := {
	"seat": {"pos": Vector3(0, 0.66, 1.0), "rot": Vector3(-33, 0, 0), "fov": 56.0, "dx": 0.31, "sway": 1.0},
	"top": {"pos": Vector3(0, 1.1, 0.6), "rot": Vector3(-64, 0, 0), "fov": 50.0, "dx": 0.42, "sway": 0.25},
}
var view := "seat"
var plate_layer: Control = null        # 2D 铭牌层（由战斗界面提供）
var plate_origin: Control = null       # 3D 视口在屏幕上的位置
var cam_pos := Vector3(0, 0.66, 1.0)
var cam_rot := Vector3(-33, 0, 0)
var sway_k := 1.0
var slot_dx := 0.31
var _last_intents: Array = []
var _last_state: Dictionary = {}
var _shake_amp := 0.0
var _shake_t := 0.0

func _ready() -> void:
	_build_world()

# ------------------------------------------------------------ 场景
# 素材替换：res://assets/table/<名字>.tscn|.glb|.gltf 存在就用它
static func asset(name: String) -> Node3D:
	for ext in ["tscn", "glb", "gltf"]:
		var path := "res://assets/table/%s.%s" % [name, ext]
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is PackedScene:
				var n = res.instantiate()
				if n is Node3D:
					return n
	return null

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("0b0c12")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("7a80a0")
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color("0b0c12")
	e.fog_density = 0.35
	env.environment = e
	add_child(env)
	# 吊灯：暖光打在桌面上
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.25, 0.0)
	lamp.omni_range = 3.2
	lamp.light_energy = 2.4
	lamp.light_color = Color("ffe0b0")
	lamp.shadow_enabled = true
	add_child(lamp)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-60, 160, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("a0b0ff")
	add_child(fill)
	# 地面（暗）
	var floor_m := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(12, 12)
	floor_m.mesh = fp
	floor_m.position = Vector3(0, -0.75, 0)
	floor_m.material_override = Proc.mat(Color("101018"), 0.95)
	add_child(floor_m)
	# 桌子：木框 + 绿呢桌面
	var wood := Proc.mat(Color("4a2e1c"), 0.6, 0.05)
	var custom_table := asset("table")
	if custom_table != null:
		add_child(custom_table)
	var code_table := Node3D.new()
	code_table.visible = custom_table == null
	add_child(code_table)
	code_table.add_child(Proc.box(Vector3(2.7, 0.1, 1.8), wood, Vector3(0, -0.05, 0)))
	var felt := MeshInstance3D.new()
	var fpm := PlaneMesh.new()
	fpm.size = Vector2(2.45, 1.55)
	felt.mesh = fpm
	felt.position = Vector3(0, 0.001, 0)
	felt.material_override = Proc.mat(Color("1f5a40"), 0.95)
	code_table.add_child(felt)
	for sx in [-1, 1]:
		code_table.add_child(Proc.box(Vector3(0.08, 0.04, 1.8), wood, Vector3(sx * 1.31, 0.02, 0)))
	for sz in [-1, 1]:
		code_table.add_child(Proc.box(Vector3(2.7, 0.04, 0.08), wood, Vector3(0, 0.02, sz * 0.86)))
	for lx in [-1.2, 1.2]:
		for lz in [-0.75, 0.75]:
			code_table.add_child(Proc.box(Vector3(0.12, 0.7, 0.12), wood, Vector3(lx, -0.45, lz)))
	# 桌面中线（我方/对方分界）
	var line := Proc.box(Vector3(2.2, 0.002, 0.006), Proc.mat(Color("2f7a58"), 0.8), Vector3(0, 0.003, 0))
	code_table.add_child(line)
	# 我的相机：第一人称坐在桌前
	cam = Camera3D.new()
	cam.position = Vector3(0, 0.66, 1.0)
	cam.rotation_degrees = Vector3(-33, 0, 0)
	cam.fov = 56
	cam.current = true
	add_child(cam)
	_build_opponent()
	for s in 2:
		_build_ap_stack(s)
	intent_root = Node3D.new()
	intent_root.name = "Intents"
	add_child(intent_root)

func _build_opponent() -> void:
	var custom := asset("opponent")
	if custom != null:
		opponent = custom
		opponent.position = Vector3(0, 0, -0.85)
		add_child(opponent)
		return
	opponent = Node3D.new()
	opponent.position = Vector3(0, 0, -0.85)
	var robe := Proc.mat(Color("2a2438"), 0.8)
	var skin := Proc.mat(Color("d8c0a8"), 0.8)
	opponent.add_child(Proc.cyl(0.16, 0.26, 0.55, robe, Vector3(0, 0.26, -0.12)))
	opponent.add_child(Proc.sphere(0.11, skin, Vector3(0, 0.66, -0.1)))
	opponent.add_child(Proc.cyl(0.0, 0.17, 0.2, Proc.mat(Color("1c1828"), 0.8), Vector3(0, 0.82, -0.1)))
	opponent.add_child(Proc.sphere(0.014, Proc.mat(Color("e0b85c"), 0.3, 0.0, 2.0), Vector3(-0.04, 0.67, 0.0)))
	opponent.add_child(Proc.sphere(0.014, Proc.mat(Color("e0b85c"), 0.3, 0.0, 2.0), Vector3(0.04, 0.67, 0.0)))
	for sx in [-1, 1]:
		opponent.add_child(Proc.capsule(0.04, 0.34, robe, Vector3(sx * 0.2, 0.26, 0.12)))
		opponent.get_child(opponent.get_child_count() - 1).rotation_degrees = Vector3(80, 0, sx * 10)
	add_child(opponent)

func _build_ap_stack(s: int) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(1.05, 0.0, 0.34 if s == 0 else -0.34)
	var base := Proc.cyl(0.075, 0.08, 0.012, Proc.mat(Color("3a2a1a"), 0.7), Vector3(0, 0.006, 0))
	holder.add_child(base)
	var stack := Node3D.new()
	holder.add_child(stack)
	ap_stacks[s] = stack
	var lab := Label3D.new()
	lab.font = Minion3D.get_font()
	lab.font_size = 56
	lab.pixel_size = 0.0009
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = K.GOLD if s == 0 else Color("e0a09a")
	lab.outline_size = 12
	lab.position = Vector3(0, 0.0, 0)
	holder.add_child(lab)
	ap_labels[s] = lab
	var cap := Label3D.new()
	cap.font = Minion3D.get_font()
	cap.text = "我的行动点" if s == 0 else "对手行动点"
	cap.font_size = 36
	cap.pixel_size = 0.0007
	cap.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cap.modulate = Color("9aa2b8")
	cap.position = Vector3(0, 0.0, 0.11)
	holder.add_child(cap)
	add_child(holder)

# 行动点筹码：每 5 点一枚，满 60 点 12 枚
func set_ap(s: int, value: int, animate: bool = true) -> void:
	var stack: Node3D = ap_stacks[s]
	var chips: int = clampi(int(ceil(float(value) / 5.0)), 0, 12)
	var have := stack.get_child_count()
	while have < chips:
		var col: Color = K.GOLD if s == 0 else Color("d88a82")
		var chip: Node3D = asset("chip_mine" if s == 0 else "chip_foe")
		if chip == null:
			chip = Proc.cyl(0.05, 0.05, 0.014, Proc.mat(col, 0.3, 0.7, 0.2))
		chip.position = Vector3(0, 0.02 + have * 0.016, 0)
		stack.add_child(chip)
		if animate:
			chip.position.y += 0.25
			chip.scale = Vector3(0.5, 0.5, 0.5)
			var t := create_tween()
			t.set_parallel(true)
			t.tween_property(chip, "position:y", 0.02 + have * 0.016, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
			t.tween_property(chip, "scale", Vector3.ONE, 0.2)
		have += 1
	while have > chips:
		var last: Node = stack.get_child(have - 1)
		if animate:
			var t2 := create_tween()
			t2.set_parallel(true)
			t2.tween_property(last, "position:y", last.position.y + 0.25, 0.25)
			t2.tween_property(last, "scale", Vector3.ZERO, 0.25)
			t2.chain().tween_callback(last.queue_free)
			stack.remove_child(last)
			var ghost: Node = last
			add_child(ghost)
			ghost.global_position = stack.global_position + Vector3(0, 0.02 + (have - 1) * 0.016, 0)
		else:
			stack.remove_child(last)
			last.queue_free()
		have -= 1
	ap_shown[s] = value
	(ap_labels[s] as Label3D).text = str(value)
	(ap_labels[s] as Label3D).position.y = 0.05 + chips * 0.016 + 0.05

# ------------------------------------------------------------ 随从
func slot_pos(s: int, idx: int) -> Vector3:
	return Vector3((float(idx) - 2.0) * slot_dx, 0.0, ROW_Z if s == 0 else -ROW_Z)

func clear_minions() -> void:
	for uid in minions:
		minions[uid].queue_free()
	minions.clear()

func setup_state(st: Dictionary, skills_of: Callable) -> void:
	_last_state = st
	clear_minions()
	for s in 2:
		var units: Array = st.sides[s].units
		for i in units.size():
			var u: Dictionary = units[i]
			var m := Minion3D.new()
			m.table = self
			add_child(m)
			m.position = slot_pos(s, i)
			m.setup(u, skills_of.call(u), s, "battle")
			minions[int(u.uid)] = m

# 位置变化（换位）时让随从滑过去
func relayout(st: Dictionary, animate: bool = true) -> void:
	for s in 2:
		var units: Array = st.sides[s].units
		for i in units.size():
			var m: Node3D = minions.get(int(units[i].uid))
			if m == null:
				continue
			var target := slot_pos(s, i)
			if animate and m.position.distance_to(target) > 0.001:
				var t := create_tween()
				t.tween_property(m, "position", target, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			else:
				m.position = target

func screen_pos(uid: int) -> Vector2:
	var m: Node3D = minions.get(uid)
	if m == null or cam == null:
		return Vector2.ZERO
	return cam.unproject_position(m.global_position + Vector3(0, 0.14, 0))

# ------------------------------------------------------------ 输入：射线点选与悬停
func _pick(pos: Vector2) -> int:
	var from := cam.project_ray_origin(pos)
	var to := from + cam.project_ray_normal(pos) * 5.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return -1
	var col: Object = hit.collider
	if col != null and col.has_meta("uid"):
		return int(col.get_meta("uid"))
	return -1

func _unhandled_input(ev: InputEvent) -> void:
	if not enabled_input or cam == null:
		return
	if ev is InputEventMouseMotion:
		var vp := get_viewport().get_visible_rect().size
		sway = Vector2((ev.position.x / vp.x - 0.5), (ev.position.y / vp.y - 0.5))
		var uid := _pick(ev.position)
		if uid != _hover_uid:
			if minions.has(_hover_uid):
				(minions[_hover_uid] as Minion3D).hover(false)
			_hover_uid = uid
			if minions.has(uid):
				(minions[uid] as Minion3D).hover(true)
			minion_hovered.emit(uid)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var uid2 := _pick(ev.position)
		if uid2 >= 0 and minions.has(uid2):
			(minions[uid2] as Minion3D).clicked.emit(minions[uid2])
			minion_clicked.emit(uid2)

func _process(delta: float) -> void:
	_t += delta
	if cam != null:
		# 第一人称的头部：轻微呼吸 + 随鼠标探身
		var sw := sway * sway_k
		cam.position = cam_pos + Vector3(sw.x * 0.12, -sw.y * 0.05 + sin(_t * 0.9) * 0.004 * sway_k, sw.y * 0.06)
		cam.rotation_degrees = cam_rot + Vector3(-sw.y * 3.0, -sw.x * 4.0, 0)
		if _shake_t > 0.0:
			_shake_t -= delta
			var k := _shake_amp * clampf(_shake_t / 0.35, 0.0, 1.0)
			cam.position += Vector3(randf_range(-k, k), randf_range(-k, k), 0)
			cam.rotation_degrees.z = randf_range(-k, k) * 40.0
	if opponent != null:
		opponent.position.y = sin(_t * 1.1) * 0.004
		opponent.rotation_degrees.x = sin(_t * 0.7) * 0.8

# ------------------------------------------------------------ 镜头震动（打击感）
func shake(amp: float, dur: float = 0.35) -> void:
	_shake_amp = maxf(_shake_amp if _shake_t > 0.0 else 0.0, amp)
	_shake_t = maxf(_shake_t, dur)

# ------------------------------------------------------------ 意图箭头：谁在第几秒打谁、打多少
func clear_intents() -> void:
	if intent_root == null:
		return
	for c in intent_root.get_children():
		c.queue_free()

func _unshaded(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _bez(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	return p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)

func _intent_label(text: String, col: Color, pos: Vector3, size_px: int = 54) -> Label3D:
	var l := Label3D.new()
	l.font = Minion3D.get_font()
	l.text = text
	l.font_size = size_px
	l.pixel_size = 0.0011
	l.modulate = col
	l.outline_size = 16
	l.outline_modulate = Color(0, 0, 0, 0.95)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 6
	l.position = pos
	intent_root.add_child(l)
	return l

func _arc(a: Vector3, b: Vector3, col: Color, label: String) -> void:
	var p0 := a + Vector3(0, 0.2, 0)
	var p2 := b + Vector3(0, 0.2, 0)
	var dist := p0.distance_to(p2)
	var p1 := (p0 + p2) * 0.5 + Vector3(0, 0.12 + dist * 0.35, 0)
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = _unshaded(Color(col.r, col.g, col.b, 0.85))
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := 24
	var w := 0.012
	for i in n + 1:
		var t := float(i) / n
		var p := _bez(p0, p1, p2, t)
		var tan := (_bez(p0, p1, p2, minf(1.0, t + 0.02)) - _bez(p0, p1, p2, maxf(0.0, t - 0.02))).normalized()
		var to_cam := (cam.global_position - p).normalized() if cam != null else Vector3.UP
		var side := tan.cross(to_cam).normalized() * w * (1.0 - 0.5 * t)
		im.surface_add_vertex(p - side)
		im.surface_add_vertex(p + side)
	im.surface_end()
	intent_root.add_child(mi)
	# 箭头
	var head := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.028
	cm.height = 0.06
	head.mesh = cm
	head.material_override = _unshaded(col)
	intent_root.add_child(head)
	var tip := p2
	var dir := (p2 - _bez(p0, p1, p2, 0.93)).normalized()
	head.position = tip - dir * 0.03
	head.basis = Basis(Quaternion(Vector3.UP, dir))
	# 沿弧线跑的小光点
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.016
	sm.height = 0.032
	dot.mesh = sm
	dot.material_override = _unshaded(col.lightened(0.5))
	intent_root.add_child(dot)
	var tw := dot.create_tween().set_loops()
	tw.tween_method(func(t: float): dot.position = _bez(p0, p1, p2, t), 0.0, 1.0, 1.1)
	_intent_label(label, col.lightened(0.35), _bez(p0, p1, p2, 0.72) + Vector3(0, 0.05, 0), 64)

# intents：[{host, side, start, name, hits:[{uid, dmg, heal, status}], tags:[..]}]
func set_intents(intents: Array) -> void:
	_last_intents = intents
	clear_intents()
	if cam == null:
		return
	for it in intents:
		var host: Node3D = minions.get(int(it.host))
		if host == null:
			continue
		var foe: bool = int(it.side) == 1
		var base_col: Color = Color("ff6a5a") if foe else Color("6aa8ff")
		var placed_self := false
		for h in it.hits:
			var tgt: Node3D = minions.get(int(h.uid))
			if tgt == null:
				continue
			var parts: Array = []
			if int(h.dmg) > 0:
				parts.append("-%d" % int(h.dmg))
			if int(h.heal) > 0:
				parts.append("+%d" % int(h.heal))
			for st in h.status:
				parts.append(str(st))
			var col := base_col
			if int(h.dmg) == 0:
				col = Color("6ad49a") if int(h.heal) > 0 else Color("e8c060")
			var label := "%d秒 %s" % [int(it.start), " ".join(parts)]
			if int(h.uid) == int(it.host):
				_intent_label(label, col, host.position + Vector3(0, 0.62, 0), 48)
				placed_self = true
			else:
				_arc(host.position, tgt.position, col, label)
		if not it.tags.is_empty():
			var y := 0.70 if placed_self else 0.62
			_intent_label("%d秒 %s" % [int(it.start), "·".join(it.tags)], Color("c8a0ff"), host.position + Vector3(0, y, 0), 48)
		elif it.hits.is_empty():
			_intent_label("%d秒 %s" % [int(it.start), str(it.name)], base_col.lightened(0.3), host.position + Vector3(0, 0.62, 0), 44)

# ------------------------------------------------------------ 视角切换
func set_view(v: String, animate: bool = true) -> void:
	if not VIEWS.has(v) or (v == view and animate):
		return
	view = v
	var cfg: Dictionary = VIEWS[v]
	var dur := 0.55 if animate else 0.0
	clear_intents()
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if dur <= 0.0:
		cam_pos = cfg.pos
		cam_rot = cfg.rot
		cam.fov = cfg.fov
		sway_k = cfg.sway
		slot_dx = cfg.dx
	else:
		t.tween_property(self, "cam_pos", cfg.pos, dur)
		t.tween_property(self, "cam_rot", cfg.rot, dur)
		t.tween_property(cam, "fov", cfg.fov, dur)
		t.tween_property(self, "sway_k", cfg.sway, dur)
		t.tween_property(self, "slot_dx", cfg.dx, dur)
	for uid in minions:
		(minions[uid] as Node3D).call("set_top_view", v == "top", animate)
	# 随从跟着滑到新间距；箭头等镜头停稳后按新角度重画
	if not _last_state.is_empty():
		var t2 := create_tween()
		t2.tween_method(func(_x: float): relayout(_last_state, false), 0.0, 1.0, maxf(dur, 0.01))
		t2.tween_callback(func(): set_intents(_last_intents))

func plate_offset() -> Vector2:
	return plate_origin.get_global_rect().position if plate_origin != null else Vector2.ZERO
