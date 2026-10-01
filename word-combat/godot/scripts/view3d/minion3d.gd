extends Node3D
# 桌上的一个随从：模型 + 头顶的名字/生命/状态 + 点选碰撞体 + 全套代码动画。
# 对外接口与 2D 的 minion_card.gd 一致（battle_screen 可以无差别使用）。

const MB = preload("res://scripts/view3d/minion_builder.gd")
const Proc = preload("res://scripts/view3d/proc_parts.gd")
const K = preload("res://scripts/ui/kit.gd")

signal clicked(card)

var uid := -1
var side := 0
var unit: Dictionary = {}
var skills: Array = []
var mode := "battle"
var selectable := false
var highlight := Color(0, 0, 0, 0)
var anim_mode := false
var anim_hp := 0
var anim_down := false
var shown_hp := 0.0

var model: Node3D
var pivot: Node3D                 # 所有动画作用在它上面，不动根的位置
var name_label: Label3D
var hp_label: Label3D
var status_label: Label3D
var bar_back: MeshInstance3D
var bar_fill: MeshInstance3D
var ring: MeshInstance3D
var flash_light: OmniLight3D
var body: StaticBody3D
var _down_applied := false
var _idle_t := 0.0
var _busy_lunge := false

static func get_font() -> Font:
	return load("res://assets/fonts/NotoSansSC-subset.ttf")

func _label(size_px: int, col: Color, y: float) -> Label3D:
	var l := Label3D.new()
	l.font = get_font()
	l.font_size = size_px
	l.pixel_size = 0.0007
	l.modulate = col
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, y, 0)
	l.render_priority = 5
	return l

func setup(u: Dictionary, sk: Array, which_side: int, m: String = "battle") -> void:
	unit = u
	skills = sk
	side = which_side
	mode = m
	uid = int(u.get("uid", -1))
	for c in get_children():
		c.queue_free()
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	model = MB.build(u, sk)
	pivot.add_child(model)
	# 敌方面朝我方（+Z），我方面朝对面（-Z）
	pivot.rotation.y = PI if side == 1 else 0.0
	# 头顶信息
	name_label = _label(44, Color("ece8da"), 0.37)
	add_child(name_label)
	bar_back = Proc.box(Vector3(0.16, 0.016, 0.004), Proc.mat(Color("0c0e14"), 0.9), Vector3(0, 0.325, 0))
	add_child(bar_back)
	bar_fill = Proc.box(Vector3(0.156, 0.012, 0.005), Proc.mat(K.GREEN, 0.5, 0.0, 0.4), Vector3(0, 0.325, 0.002))
	add_child(bar_fill)
	hp_label = _label(40, Color.WHITE, 0.30)
	add_child(hp_label)
	status_label = _label(36, Color("e0b85c"), 0.435)
	add_child(status_label)
	# 选中圈
	ring = Proc.torus(0.004, 0.085, Proc.mat(K.GOLD, 0.3, 0.0, 2.0), Vector3(0, 0.012, 0))
	ring.visible = false
	add_child(ring)
	flash_light = OmniLight3D.new()
	flash_light.position = Vector3(0, 0.2, 0.12 if side == 0 else -0.12)
	flash_light.omni_range = 0.6
	flash_light.light_energy = 0.0
	add_child(flash_light)
	# 点选碰撞体
	body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 0.09
	cs.height = 0.3
	shape.shape = cs
	shape.position = Vector3(0, 0.15, 0)
	body.add_child(shape)
	body.set_meta("uid", uid)
	add_child(body)
	refresh(u, sk)

func refresh(u: Dictionary, sk: Array) -> void:
	unit = u
	skills = sk
	MB.apply_attachments(model, u, sk)
	MB.apply_status_fx(model, u.get("statuses", []))
	name_label.text = "%s" % u.get("name", "?")
	var maxhp := int(u.get("max_hp", 1))
	var hp := int(u.get("hp", maxhp))
	if anim_mode:
		hp = anim_hp
	else:
		shown_hp = hp
	_set_hp_visual(float(hp), maxhp)
	var parts: Array = []
	for s in u.get("statuses", []):
		parts.append(str(s.name) + (" %d" % int(s.value) if s.name == "护盾" else ""))
	if str(u.get("kw", "")) != "":
		parts.append("◆" + str(u.kw) + ("(已用)" if u.get("kw_spent", false) else ""))
	status_label.text = "  ".join(parts)
	var is_down: bool = anim_down if anim_mode else int(u.get("down_round", -1)) != -1
	_set_down(is_down, false)
	ring.visible = highlight.a > 0.0
	if ring.visible:
		ring.material_override = Proc.mat(highlight, 0.3, 0.0, 2.0)

func _set_hp_visual(hp: float, maxhp: int) -> void:
	var r := clampf(hp / maxf(1.0, float(maxhp)), 0.0, 1.0)
	bar_fill.scale.x = maxf(r, 0.001)
	bar_fill.position.x = -0.078 * (1.0 - r)
	var col: Color = K.GREEN if r > 0.5 else (Color("d8b23a") if r > 0.25 else K.RED)
	bar_fill.material_override = Proc.mat(col, 0.5, 0.0, 0.5)
	hp_label.text = "%d / %d" % [int(round(hp)), maxhp]

func _set_down(down: bool, animate: bool) -> void:
	if down == _down_applied:
		return
	_down_applied = down
	var tw := create_tween()
	tw.set_parallel(true)
	var base_y := PI if side == 1 else 0.0
	if down:
		tw.tween_property(pivot, "rotation_degrees:x", -78.0 if side == 0 else 78.0, 0.35 if animate else 0.01)
		tw.tween_property(pivot, "position:y", 0.03, 0.35 if animate else 0.01)
	else:
		tw.tween_property(pivot, "rotation_degrees:x", 0.0, 0.3 if animate else 0.01)
		tw.tween_property(pivot, "position:y", 0.0, 0.3 if animate else 0.01)

# ------------------------------------------------------------ 与 2D 卡片一致的动画接口
func begin_anim(hp: int, down: bool) -> void:
	anim_mode = true
	anim_hp = hp
	anim_down = down
	shown_hp = hp
	refresh(unit, skills)

func end_anim() -> void:
	anim_mode = false
	refresh(unit, skills)

func animate_hp(to_hp: int, dur: float = 0.35) -> void:
	anim_hp = to_hp
	var maxhp := int(unit.get("max_hp", 1))
	var t := create_tween()
	t.tween_method(func(v: float):
		shown_hp = v
		_set_hp_visual(v, maxhp), shown_hp, float(to_hp), dur)

func set_highlight(col: Color) -> void:
	highlight = col
	if ring != null:
		ring.visible = col.a > 0.0
		if ring.visible:
			ring.material_override = Proc.mat(col, 0.3, 0.0, 2.0)

func float_text(text: String, col: Color, size: int = 30) -> void:
	var l := _label(int(size * 2.2), col, 0.46)
	l.text = text
	l.outline_size = 14
	l.pixel_size = 0.0008
	add_child(l)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y + 0.2, 0.9).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.45)
	t.chain().tween_callback(l.queue_free)

func shake() -> void:
	var t := create_tween()
	for i in 6:
		t.tween_property(pivot, "position:x", (0.012 if i % 2 == 0 else -0.012), 0.04)
	t.tween_property(pivot, "position:x", 0.0, 0.04)

func flash(col: Color) -> void:
	flash_light.light_color = col
	var t := create_tween()
	t.tween_property(flash_light, "light_energy", 3.0, 0.07)
	t.tween_property(flash_light, "light_energy", 0.0, 0.3)

# 出招：向对面前冲一下再回来
func lunge(target: Vector3) -> void:
	if _busy_lunge or _down_applied:
		return
	_busy_lunge = true
	var dir := (target - global_position)
	dir.y = 0.0
	var local := to_local(global_position + dir.normalized() * minf(dir.length() * 0.35, 0.22))
	var t := create_tween()
	t.tween_property(pivot, "position", Vector3(local.x, 0.03, local.z), 0.14).set_ease(Tween.EASE_OUT)
	t.tween_property(pivot, "position", Vector3.ZERO, 0.25).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func(): _busy_lunge = false)

# 受击：向后仰一下
func recoil() -> void:
	var t := create_tween()
	var back := 12.0 if side == 0 else -12.0
	t.tween_property(pivot, "rotation_degrees:x", back, 0.07)
	t.tween_property(pivot, "rotation_degrees:x", 0.0 if not _down_applied else pivot.rotation_degrees.x, 0.22)

func hover(on: bool) -> void:
	if _down_applied:
		return
	var t := create_tween()
	t.tween_property(model, "position:y", 0.02 if on else 0.0, 0.1)

func _process(delta: float) -> void:
	_idle_t += delta
	if model != null and not _down_applied and not _busy_lunge:
		# 轻微呼吸/漂浮（魂是飘着的）
		var amp := 0.004
		var glyph := str(unit.get("glyph", ""))
		if glyph == "魂":
			amp = 0.012
		model.position.y = (0.0 if not selectable else 0.0) + sin(_idle_t * 2.0 + float(uid)) * amp + (0.012 if glyph == "魂" else 0.0)
