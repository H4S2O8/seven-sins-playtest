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

func _ready() -> void:
	_build_world()

# ------------------------------------------------------------ 场景
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
	add_child(Proc.box(Vector3(2.7, 0.1, 1.8), wood, Vector3(0, -0.05, 0)))
	var felt := MeshInstance3D.new()
	var fpm := PlaneMesh.new()
	fpm.size = Vector2(2.45, 1.55)
	felt.mesh = fpm
	felt.position = Vector3(0, 0.001, 0)
	felt.material_override = Proc.mat(Color("1f5a40"), 0.95)
	add_child(felt)
	for sx in [-1, 1]:
		add_child(Proc.box(Vector3(0.08, 0.04, 1.8), wood, Vector3(sx * 1.31, 0.02, 0)))
	for sz in [-1, 1]:
		add_child(Proc.box(Vector3(2.7, 0.04, 0.08), wood, Vector3(0, 0.02, sz * 0.86)))
	for lx in [-1.2, 1.2]:
		for lz in [-0.75, 0.75]:
			add_child(Proc.box(Vector3(0.12, 0.7, 0.12), wood, Vector3(lx, -0.45, lz)))
	# 桌面中线（我方/对方分界）
	var line := Proc.box(Vector3(2.2, 0.002, 0.006), Proc.mat(Color("2f7a58"), 0.8), Vector3(0, 0.003, 0))
	add_child(line)
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

func _build_opponent() -> void:
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
		var chip := Proc.cyl(0.05, 0.05, 0.014, Proc.mat(col, 0.3, 0.7, 0.2), Vector3(0, 0.02 + have * 0.016, 0))
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
	return Vector3((float(idx) - 2.0) * SLOT_DX, 0.0, ROW_Z if s == 0 else -ROW_Z)

func clear_minions() -> void:
	for uid in minions:
		minions[uid].queue_free()
	minions.clear()

func setup_state(st: Dictionary, skills_of: Callable) -> void:
	clear_minions()
	for s in 2:
		var units: Array = st.sides[s].units
		for i in units.size():
			var u: Dictionary = units[i]
			var m := Minion3D.new()
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
		var base := Vector3(0, 0.66, 1.0)
		cam.position = base + Vector3(sway.x * 0.12, -sway.y * 0.05 + sin(_t * 0.9) * 0.004, sway.y * 0.06)
		cam.rotation_degrees = Vector3(-33 - sway.y * 3.0, -sway.x * 4.0, 0)
	if opponent != null:
		opponent.position.y = sin(_t * 1.1) * 0.004
		opponent.rotation_degrees.x = sin(_t * 0.7) * 0.8
