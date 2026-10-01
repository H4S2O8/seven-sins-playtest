extends Control
# 新手引导覆盖层：压暗全屏、只留一个“洞”给玩家操作，附一个对话框。
# 步骤数据在 data/tutorial.json；界面里用 Tut.tag(控件, "名字") 登记可高亮的控件，
# 用 Tut.fire("事件") 告诉引导“玩家做了某事”。没有引导运行时，这些调用什么都不做。

const K = preload("res://scripts/ui/kit.gd")

signal finished(completed: bool)

static var active: Control = null
static var vars: Dictionary = {}
static var providers: Dictionary = {}     # 名字 → Callable() -> Rect2（全局坐标；Rect2() 表示没有）

var steps: Array = []
var idx := -1
var dim: Array = []
var full_dim: ColorRect
var frame: Panel
var dlg: PanelContainer
var title_l: Label
var text_l: Label
var next_b: Button
var skip_b: Button
var exit_b: Button
var prog_l: Label
var hole := Rect2()
var _t := 0.0

# ------------------------------------------------------------ 静态入口
static func tag(c: Control, name: String) -> Control:
	c.add_to_group("tut:" + name)
	return c

static func fire(ev: String) -> void:
	if active != null and is_instance_valid(active):
		active.on_event(ev)

static func is_on() -> bool:
	return active != null and is_instance_valid(active)

# ------------------------------------------------------------ 构建
func start(from_id: String = "") -> void:
	var f := FileAccess.open("res://data/tutorial.json", FileAccess.READ)
	steps = JSON.parse_string(f.get_as_text()).steps
	active = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	for i in 4:
		var r := ColorRect.new()
		r.color = Color(0, 0, 0, 0.62)
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(r)
		dim.append(r)
	full_dim = ColorRect.new()
	full_dim.color = Color(0, 0, 0, 0.55)
	full_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	full_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(full_dim)
	frame = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = K.GOLD
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", sb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	dlg = K.panel(Color("141a2a"), K.GOLD, 16, 3, 16)
	dlg.custom_minimum_size = Vector2(760, 0)
	var v := K.vbox(8)
	dlg.add_child(v)
	var head := K.hbox(10)
	title_l = K.label("", 24, K.GOLD)
	head.add_child(title_l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	prog_l = K.label("", 14, K.MUTED)
	head.add_child(prog_l)
	v.add_child(head)
	text_l = K.wrap_label("", 21, K.TEXT)
	v.add_child(text_l)
	var row := K.hbox(10)
	exit_b = K.button("退出引导", "ghost", 15)
	exit_b.pressed.connect(func(): _finish(false))
	row.add_child(exit_b)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp2)
	skip_b = K.button("跳过这步", "ghost", 15)
	skip_b.pressed.connect(advance)
	row.add_child(skip_b)
	next_b = K.button("下一步  ▶", "primary", 20)
	next_b.custom_minimum_size = Vector2(170, 44)
	next_b.pressed.connect(advance)
	row.add_child(next_b)
	v.add_child(row)
	add_child(dlg)
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	var start_idx := 0
	if from_id != "":
		for i in steps.size():
			if steps[i].id == from_id:
				start_idx = i
	idx = start_idx - 1
	advance()

func _exit_tree() -> void:
	if active == self:
		active = null
		providers.clear()
		vars.clear()

func cur() -> Dictionary:
	return steps[idx] if idx >= 0 and idx < steps.size() else {}

func advance() -> void:
	idx += 1
	if idx >= steps.size():
		_finish(true)
		return
	_enter()

func _finish(ok: bool) -> void:
	finished.emit(ok)
	active = null
	queue_free()

func _enter() -> void:
	var s := cur()
	title_l.text = str(s.get("title", ""))
	text_l.text = _fmt(str(s.get("text", "")))
	var w = s.get("wait", "next")
	var is_next: bool = w is String and w == "next"
	next_b.visible = is_next
	next_b.text = str(s.get("button", "下一步  ▶"))
	skip_b.visible = not is_next and not bool(s.get("hide", false))
	prog_l.text = "%d / %d" % [idx + 1, steps.size()]
	var hidden: bool = bool(s.get("hide", false))
	dlg.visible = not hidden
	full_dim.visible = false
	for r in dim:
		r.visible = false
	frame.visible = false
	exit_b.visible = not hidden
	_layout()

func _fmt(t: String) -> String:
	for k in vars:
		t = t.replace("{%s}" % k, str(vars[k]))
	return t

func on_event(ev: String) -> void:
	var s := cur()
	if s.is_empty():
		return
	var w = s.get("wait", "next")
	var ok := false
	if w is String:
		ok = w == ev
	elif w is Array:
		ok = ev in w
	if ok:
		advance()

# ------------------------------------------------------------ 目标矩形
func target_rect(name: String) -> Rect2:
	if name == "":
		return Rect2()
	if providers.has(name):
		var cb: Callable = providers[name]
		if not cb.is_valid():
			return Rect2()
		var r: Rect2 = cb.call()
		return r
	for n in get_tree().get_nodes_in_group("tut:" + name):
		if n is Control and n.is_visible_in_tree():
			var par := n.get_parent()
			while par != null:
				if par is ScrollContainer:
					(par as ScrollContainer).ensure_control_visible(n)
				par = par.get_parent()
			return n.get_global_rect()
	return Rect2()

func current_hole() -> Rect2:
	return target_rect(str(cur().get("target", "")))

func _process(delta: float) -> void:
	_t += delta
	_layout()

func _layout() -> void:
	var s := cur()
	if s.is_empty():
		return
	var vp := get_viewport_rect().size
	var hidden: bool = bool(s.get("hide", false))
	hole = current_hole()
	var has_hole := hole.size.x > 2.0 and not hidden
	if has_hole:
		hole = hole.grow(8).intersection(Rect2(Vector2.ZERO, vp))
	full_dim.visible = not has_hole and not hidden
	for r in dim:
		r.visible = has_hole
	frame.visible = has_hole
	if has_hole:
		dim[0].position = Vector2(0, 0)
		dim[0].size = Vector2(vp.x, hole.position.y)
		dim[1].position = Vector2(0, hole.end.y)
		dim[1].size = Vector2(vp.x, vp.y - hole.end.y)
		dim[2].position = Vector2(0, hole.position.y)
		dim[2].size = Vector2(hole.position.x, hole.size.y)
		dim[3].position = Vector2(hole.end.x, hole.position.y)
		dim[3].size = Vector2(vp.x - hole.end.x, hole.size.y)
		frame.position = hole.position
		frame.size = hole.size
		frame.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 5.0))
	if dlg.visible:
		var ds := dlg.get_combined_minimum_size()
		dlg.size = ds
		var x := (vp.x - ds.x) * 0.5
		var y := vp.y - ds.y - 28.0
		if has_hole:
			var cy := hole.get_center().y
			if cy > vp.y * 0.5:
				y = 28.0
		var pos_hint: String = str(s.get("pos", ""))
		if pos_hint == "top":
			y = 28.0
		elif pos_hint == "bottom":
			y = vp.y - ds.y - 28.0
		elif pos_hint == "center":
			y = (vp.y - ds.y) * 0.5
		dlg.position = Vector2(x, y)
