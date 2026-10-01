extends RefCounted
# 拼装一个随从的 3D 形象：身体 + 按 appearance.json 解析出的配件。
# 模型来源优先级：res://assets/ 里的 glTF（存在就用）> proc_parts.gd 的代码占位件。
# 动画与移动全部由代码驱动（对节点做变换），所以素材只需要是静态模型。

const Appearance = preload("res://scripts/view3d/appearance.gd")
const Proc = preload("res://scripts/view3d/proc_parts.gd")

static func _load_asset(rel: String) -> Node3D:
	if rel == "":
		return null
	var path := "res://assets/" + rel
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if res is PackedScene:
		var inst = res.instantiate()
		if inst is Node3D:
			return inst
	return null

static func _color(hex: String) -> Color:
	return Color(hex) if hex != "" else Color.WHITE

# 返回 Node3D：根下有 Body（含 Socket_*）、Attach（各配件）、Fx（状态特效）
static func build(unit: Dictionary, skills: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Minion"
	var b := Appearance.body_for(str(unit.get("glyph", "剑")))
	var body: Node3D = _load_asset(str(b.get("asset", "")))
	if body == null:
		body = Proc.body(str(b.get("proc", "body_sword")), _color(str(b.get("color", "#b45a52"))))
	body.name = "Body"
	root.add_child(body)
	var attach := Node3D.new()
	attach.name = "Attach"
	root.add_child(attach)
	var fx := Node3D.new()
	fx.name = "Fx"
	root.add_child(fx)
	root.scale = Vector3.ONE * Appearance.scale_for(int(unit.get("max_hp", 14)))
	apply_attachments(root, unit, skills)
	return root

# 重新按当前牌面挂配件（编辑词条后调用）
static func apply_attachments(root: Node3D, unit: Dictionary, skills: Array) -> void:
	var body: Node3D = root.get_node("Body")
	var attach: Node3D = root.get_node("Attach")
	for c in attach.get_children():
		attach.remove_child(c)
		c.queue_free()
	for r in Appearance.resolve(unit, skills):
		var inst: Node3D = _load_asset(str(r.get("asset", "")))
		if inst == null:
			inst = Proc.part(str(r.get("proc", "")), _color(str(r.get("color", "#ffffff"))))
		inst.name = "A_" + str(r.slot)
		var sock: Node = body.find_child("Socket_" + str(r.slot), true, false)
		if sock != null and sock is Node3D:
			sock.add_child(inst)
		else:
			attach.add_child(inst)
	root.scale = Vector3.ONE * Appearance.scale_for(int(unit.get("max_hp", 14)))

# 状态特效：按当前状态列表重建
static func apply_status_fx(root: Node3D, statuses: Array) -> void:
	var fx: Node3D = root.get_node("Fx")
	for c in fx.get_children():
		fx.remove_child(c)
		c.queue_free()
	for s in statuses:
		var d := Appearance.status_fx(str(s.name))
		if d.is_empty():
			continue
		fx.add_child(Proc.status_fx(str(d.get("proc", "")), _color(str(d.get("color", "#ffffff")))))
