extends Control
# 20秒时间轴：刻度、双方宣告的落点、结算时的播放头与事件小点。

const K = preload("res://scripts/ui/kit.gd")

var marks: Array = []        # {t:int, label:String, side:int, windup:int}
var dots: Array = []         # {t:float, color:Color, side:int}
var playhead := -1.0
var windup_hint := -1        # 选中技能时显示最早起手刻度
var start_hint := -1         # 选中技能时显示拟定起手

func _init() -> void:
	custom_minimum_size = Vector2(0, 98)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func clear_all() -> void:
	marks = []
	dots = []
	playhead = -1.0
	windup_hint = -1
	start_hint = -1
	queue_redraw()

func set_playhead(t: float) -> void:
	playhead = t
	queue_redraw()

func add_dot(t: float, color: Color, side: int) -> void:
	dots.append({"t": t, "color": color, "side": side})
	queue_redraw()

func _x(t: float) -> float:
	var left := 46.0
	var right := size.x - 46.0
	return left + (right - left) * clampf(t / 20.0, 0.0, 1.0)

func _draw() -> void:
	var font := get_theme_default_font()
	var w := size.x
	var mid := size.y * 0.5
	# 底条
	draw_rect(Rect2(40, mid - 7, w - 80, 14), Color("232a3e"), true)
	draw_rect(Rect2(40, mid - 7, w - 80, 14), K.EDGE, false, 1.0)
	# 早期可起手区间
	if windup_hint >= 0:
		draw_rect(Rect2(_x(0), mid - 7, _x(windup_hint) - _x(0), 14), Color(0.6, 0.15, 0.15, 0.55), true)
	for t in range(0, 21):
		var x := _x(float(t))
		var h := 12.0 if t % 5 == 0 else 6.0
		draw_line(Vector2(x, mid + 7), Vector2(x, mid + 7 + h), K.MUTED, 1.0)
		if t % 5 == 0:
			draw_string(font, Vector2(x - 10, mid + 38), "%d秒" % t if t > 0 else "0", HORIZONTAL_ALIGNMENT_CENTER, 24, 14, K.MUTED)
	if start_hint >= 0:
		var xs := _x(float(start_hint))
		draw_line(Vector2(xs, mid - 24), Vector2(xs, mid + 8), K.GOLD, 2.0)
		draw_string(font, Vector2(xs + 6, mid - 14), "拟 %d秒" % start_hint, HORIZONTAL_ALIGNMENT_LEFT, 80, 14, K.GOLD)
	# 宣告标记
	var used_slots := {}
	for mk in marks:
		var x2 := _x(float(mk.t))
		var col: Color = K.BLUE if mk.side == 0 else K.RED
		var up: bool = mk.side == 1
		var y0 := mid - 8 if up else mid + 8
		var y1 := mid - 40 if up else mid + 48
		draw_line(Vector2(x2, y0), Vector2(x2, y1), col, 3.0)
		draw_circle(Vector2(x2, mid), 8.0, col)
		var txt: String = "%s %d秒" % [mk.label, mk.t]
		var tw := 150.0
		var tx := clampf(x2 - tw / 2.0, 4.0, w - tw - 4.0)
		var ty := (y1 - 4.0) if up else (y1 + 16.0)
		draw_rect(Rect2(tx - 2, ty - 16, tw + 4, 22), Color(col.r, col.g, col.b, 0.28), true)
		draw_string(font, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_CENTER, tw, 15, K.TEXT)
	# 事件小点
	for d in dots:
		var x3 := _x(float(d.t))
		var y3: float = mid - 16.0 if d.side == 1 else mid + 18.0
		draw_circle(Vector2(x3, y3), 4.0, d.color)
	if playhead >= 0.0:
		var xp := _x(playhead)
		draw_line(Vector2(xp, mid - 30), Vector2(xp, mid + 30), K.GOLD, 3.0)
		draw_circle(Vector2(xp, mid), 6.0, K.GOLD)
