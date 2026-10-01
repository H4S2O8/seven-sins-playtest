extends Control
# 新手引导覆盖层：压暗全屏、只留一个“洞”给玩家操作；说话由桌宠“小词”的气泡负责。
# 步骤数据在 data/tutorial.json；界面里用 Tut.tag(控件, "名字") 登记可高亮的控件，
# 用 Tut.fire("事件") 告诉引导“玩家做了某事”。没有引导运行时，这些调用什么都不做。

const K = preload("res://scripts/ui/kit.gd")
const Pet = preload("res://scripts/ui/pet.gd")

signal finished(completed: bool)

static var active: Control = null
static var vars: Dictionary = {}
static var providers: Dictionary = {}     # 名字 → Callable() -> Rect2（全局坐标；Rect2() 表示没有）

var steps: Array = []
var idx := -1
var dim: Array = []
var full_dim: ColorRect
var frame: Panel
var next_b: Button
var skip_b: Button
var exit_b: Button
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
	if Pet.inst != null and is_instance_valid(Pet.inst):
		Pet.inst.tutorial_end()

func cur() -> Dictionary:
	return steps[idx] if idx >= 0 and idx < steps.size() else {}

func advance() -> void:
	idx += 1
	if idx >= steps.size():
		_finish(true)
		return
	_enter()

func _finish(ok: bool) -> void:
	if Pet.inst != null and is_instance_valid(Pet.inst):
		Pet.inst.tutorial_end()
	finished.emit(ok)
	active = null
	queue_free()

func _enter() -> void:
	var s := cur()
	var w = s.get("wait", "next")
	var is_next: bool = w is String and w == "next"
	var hidden: bool = bool(s.get("hide", false))
	full_dim.visible = false
	for r in dim:
		r.visible = false
	frame.visible = false
	next_b = null
	skip_b = null
	exit_b = null
	if Pet.inst == null or not is_instance_valid(Pet.inst):
		return
	if hidden:
		Pet.inst.tutorial_show("", "（看着就好……）", [], Rect2(), "bottom")
		return
	var btns: Array = [{"id": "exit", "label": "退出引导", "style": "ghost", "size": 14, "cb": func(): _finish(false)}]
	if not is_next:
		btns.append({"id": "skip", "label": "跳过这步", "style": "ghost", "size": 14, "cb": advance})
	else:
		btns.append({"id": "next", "label": str(s.get("button", "下一步  ▶")), "style": "primary", "size": 18, "expand": true, "cb": advance})
	var made: Dictionary = Pet.inst.tutorial_show("%s   %d/%d" % [str(s.get("title", "")), idx + 1, steps.size()], _fmt(str(s.get("text", ""))), btns, current_hole(), str(s.get("pos", "")))
	next_b = made.get("next")
	skip_b = made.get("skip")
	exit_b = made.get("exit")
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
	if Pet.inst != null and is_instance_valid(Pet.inst):
		Pet.inst.tutorial_anchor(hole if has_hole else Rect2())
