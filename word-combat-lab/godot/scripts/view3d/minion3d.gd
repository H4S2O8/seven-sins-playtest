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
var hud: Node3D
# 2D 铭牌：有 plate_layer 时用它代替 3D 头顶字（任何距离都清晰）
var plate: PanelContainer
var plate_name: Label
var plate_hp: Label
var plate_fill: ColorRect
var plate_status: Label
var plate_bar: Control
var plate_bg: ColorRect
var bar_w := 96.0
var _compact := false
var table: Node3D
var anim: AnimationPlayer = null    # 模型自带动画（可选）：idle / attack / hit / die / revive
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
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	anim = aps[0] if not aps.is_empty() else null
	play_clip("idle")
	# 敌方面朝我方（+Z），我方面朝对面（-Z）
	pivot.rotation.y = PI if side == 1 else 0.0
	# 头顶信息（远处的对手一排放大，保证看得清）
	hud = Node3D.new()
	# 对手一排：信息放在头顶并放大；我方一排：信息放在脚前的桌面上，不挡住对面
	hud.position = Vector3(0, 0.30, 0) if side == 1 else Vector3(0, 0.0, 0.15)
	hud.scale = Vector3.ONE * (1.6 if side == 1 else 1.15)
	add_child(hud)
	name_label = _label(44, Color("ece8da"), 0.075)
	hud.add_child(name_label)
	bar_back = Proc.box(Vector3(0.14, 0.016, 0.004), Proc.mat(Color("0c0e14"), 0.9), Vector3(0, 0.035, 0))
	bar_back.material_override.no_depth_test = true
	bar_back.material_override.render_priority = 4
	hud.add_child(bar_back)
	bar_fill = Proc.box(Vector3(0.136, 0.012, 0.005), Proc.mat(K.GREEN, 0.5, 0.0, 0.4), Vector3(0, 0.035, 0.002))
	hud.add_child(bar_fill)
	hp_label = _label(44, Color.WHITE, 0.0)
	hud.add_child(hp_label)
	status_label = _label(36, Color("e0b85c"), 0.12)
	hud.add_child(status_label)
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
	_make_plate()
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
	if plate != null:
		plate_name.text = str(u.get("name", "?"))
		plate_status.text = "  ".join(parts)
		plate_status.visible = not parts.is_empty()
	var is_down: bool = anim_down if anim_mode else int(u.get("down_round", -1)) != -1
	_set_down(is_down, false)
	ring.visible = highlight.a > 0.0
	if ring.visible:
		ring.material_override = Proc.mat(highlight, 0.3, 0.0, 2.0)

func _set_hp_visual(hp: float, maxhp: int) -> void:
	var r := clampf(hp / maxf(1.0, float(maxhp)), 0.0, 1.0)
	bar_fill.scale.x = maxf(r, 0.001)
	bar_fill.position.x = -0.068 * (1.0 - r)
	var col: Color = K.GREEN if r > 0.5 else (Color("d8b23a") if r > 0.25 else K.RED)
	var bm := Proc.mat(col, 0.5, 0.0, 0.5)
	bm.no_depth_test = true
	bm.render_priority = 5
	bar_fill.material_override = bm
	hp_label.text = "%d / %d" % [int(round(hp)), maxhp]
	if plate != null:
		plate_hp.text = "%d / %d" % [int(round(hp)), maxhp]
		plate_fill.size.x = bar_w * r
		plate_fill.color = col

func _set_down(down: bool, animate: bool) -> void:
	if down == _down_applied:
		return
	_down_applied = down
	play_clip("die" if down else "revive")
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
	if plate != null and table != null and table.cam != null:
		var l2 := K.label(text, size, col, HORIZONTAL_ALIGNMENT_CENTER)
		l2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		l2.add_theme_constant_override("outline_size", 8)
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		table.plate_layer.add_child(l2)
		var p2: Vector2 = table.cam.unproject_position(global_position + Vector3(0, 0.3, 0)) + table.plate_offset()
		l2.size = Vector2(200, size * 1.4)
		l2.position = p2 - Vector2(100, size)
		var t2 := l2.create_tween().set_parallel(true)
		t2.tween_property(l2, "position:y", l2.position.y - 60.0, 0.9).set_ease(Tween.EASE_OUT)
		t2.tween_property(l2, "modulate:a", 0.0, 0.45).set_delay(0.45)
		t2.chain().tween_callback(l2.queue_free)
		return
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
	play_clip("attack")
	var dir := (target - global_position)
	dir.y = 0.0
	var local := to_local(global_position + dir.normalized() * minf(dir.length() * 0.35, 0.22))
	var t := create_tween()
	t.tween_property(pivot, "position", Vector3(local.x, 0.03, local.z), 0.14).set_ease(Tween.EASE_OUT)
	t.tween_property(pivot, "position", Vector3.ZERO, 0.25).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func(): _busy_lunge = false)

# 受击：向后仰一下
func recoil() -> void:
	play_clip("hit")
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
	_update_plate()
	if model != null and not _down_applied and not _busy_lunge:
		# 轻微呼吸/漂浮（魂是飘着的）
		var amp := 0.004
		var glyph := str(unit.get("glyph", ""))
		if glyph == "魂":
			amp = 0.012
		model.position.y = (0.0 if not selectable else 0.0) + sin(_idle_t * 2.0 + float(uid)) * amp + (0.012 if glyph == "魂" else 0.0)

# 俯视时：对手的信息挪到它身后（屏幕上方），不压在模型上
func set_top_view(top: bool, animate: bool = true) -> void:
	if hud == null or side != 1:
		return
	var pos := Vector3(0, 0.06, -0.17) if top else Vector3(0, 0.30, 0)
	var sc := Vector3.ONE * (1.25 if top else 1.6)
	if not animate:
		hud.position = pos
		hud.scale = sc
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(hud, "position", pos, 0.5)
	t.tween_property(hud, "scale", sc, 0.5)

# ------------------------------------------------------------ 2D 铭牌
func _make_plate() -> void:
	if table == null or table.get("plate_layer") == null:
		return
	var layer: Control = table.plate_layer
	hud.visible = false
	plate = K.panel(Color(0.06, 0.07, 0.11, 0.86), (Color("e0605a") if side == 1 else Color("5a8ad8")).darkened(0.2), 7, 1, 4)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := K.vbox(1)
	plate.add_child(v)
	plate_name = K.label("", 15, Color("ece8da"), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(plate_name)
	var bar := Control.new()
	plate_bar = bar
	bar.custom_minimum_size = Vector2(96, 14)
	var bg := ColorRect.new()
	plate_bg = bg
	bg.color = Color("0c0e14")
	bg.size = Vector2(96, 14)
	bar.add_child(bg)
	plate_fill = ColorRect.new()
	plate_fill.size = Vector2(96, 14)
	plate_fill.color = K.GREEN
	bar.add_child(plate_fill)
	plate_hp = K.label("", 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	plate_hp.size = Vector2(96, 14)
	plate_hp.position = Vector2(0, -2)
	plate_hp.add_theme_color_override("font_outline_color", Color.BLACK)
	plate_hp.add_theme_constant_override("outline_size", 4)
	bar.add_child(plate_hp)
	v.add_child(bar)
	plate_status = K.label("", 12, Color("e0b85c"), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(plate_status)
	layer.add_child(plate)

func _exit_tree() -> void:
	if plate != null and is_instance_valid(plate):
		plate.queue_free()

func _update_plate() -> void:
	if plate == null or table == null or table.cam == null:
		return
	var top: bool = str(table.get("view")) == "top"
	# 我方：铭牌在脚前；对手：坐着看时在头顶，俯视时也放到脚前（两排中间），不会顶出画面
	var below: bool = side == 0 or top
	var anchor: Vector3 = global_position + (Vector3(0, 0.0, 0.12) if below else Vector3(0, 0.36, 0))
	if table.cam.is_position_behind(anchor):
		plate.visible = false
		return
	plate.visible = true
	# 坐着看时远处一排很挤：只留血条（名字在俯视时再显示）
	var compact: bool = side == 1 and not top
	if compact != _compact:
		_compact = compact
		bar_w = 62.0 if compact else 96.0
		plate_name.visible = not compact
		plate_bar.custom_minimum_size.x = bar_w
		plate_bg.size.x = bar_w
		plate_hp.size.x = bar_w
		plate.size = Vector2.ZERO
		_set_hp_visual(shown_hp, int(unit.get("max_hp", 1)))
	var p: Vector2 = table.cam.unproject_position(anchor) + table.plate_offset()
	var sz := plate.get_combined_minimum_size()
	plate.size = sz
	plate.position = Vector2(p.x - sz.x * 0.5, p.y if below else p.y - sz.y)
	plate.modulate.a = 0.45 if _down_applied else 1.0

# 播放模型自带的动画片段（没有就什么都不做；代码做的位移动画照常进行）
func play_clip(name: String) -> void:
	if anim != null and anim.has_animation(name):
		anim.play(name)
		if name != "idle" and anim.has_animation("idle"):
			anim.queue("idle")
