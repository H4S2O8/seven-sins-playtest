extends Control
# 矢量小图标：用来代替汉字图标，避免被误会成“词”。素材到位后可整体换成图片。

var kind := "star"
var col := Color.WHITE

const MAP := {
	"剑": "sword", "盾": "shield", "咒": "spell", "弓": "bow", "魂": "wisp",
	"斩": "slash", "轰": "burst", "爆": "burst", "愈": "cross", "养": "leaf", "御": "shield", "反": "mirror",
	"换": "swap", "时": "clock", "吸": "drop", "分": "split", "散": "split", "化": "swirl", "转": "swirl",
	"叠": "stack", "追": "arrow", "税": "coin", "遗": "ghost",
}

static func make(glyph: String, px: float, color: Color) -> Control:
	var c := new()
	c.kind = MAP.get(glyph, "star")
	c.col = color
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 1.0:
		s = minf(custom_minimum_size.x, custom_minimum_size.y)
	var o := Vector2((size.x - s) * 0.5, (size.y - s) * 0.5)
	var u := s / 100.0
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * u
	var dark := col.darkened(0.45)
	match kind:
		"sword":
			draw_colored_polygon(PackedVector2Array([P.call(50, 6), P.call(60, 22), P.call(56, 66), P.call(44, 66), P.call(40, 22)]), col)
			draw_rect(Rect2(P.call(26, 66), Vector2(48, 9) * u), dark)
			draw_rect(Rect2(P.call(45, 75), Vector2(10, 18) * u), dark)
		"shield":
			draw_colored_polygon(PackedVector2Array([P.call(16, 14), P.call(84, 14), P.call(84, 50), P.call(50, 92), P.call(16, 50)]), col)
			draw_colored_polygon(PackedVector2Array([P.call(28, 26), P.call(72, 26), P.call(72, 48), P.call(50, 76), P.call(28, 48)]), dark)
		"spell":
			draw_circle(P.call(50, 50), 12 * u, col)
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(P.call(50 + cos(a) * 18, 50 + sin(a) * 18), P.call(50 + cos(a) * 42, 50 + sin(a) * 42), col, 7 * u)
		"bow":
			draw_arc(P.call(30, 50), 42 * u, -1.2, 1.2, 20, col, 7 * u)
			draw_line(P.call(30 + cos(-1.2) * 42, 50 + sin(-1.2) * 42), P.call(30 + cos(1.2) * 42, 50 + sin(1.2) * 42), dark, 3 * u)
			draw_line(P.call(30, 50), P.call(92, 50), col, 5 * u)
			draw_colored_polygon(PackedVector2Array([P.call(96, 50), P.call(82, 42), P.call(82, 58)]), col)
		"wisp":
			draw_circle(P.call(50, 40), 24 * u, col)
			draw_colored_polygon(PackedVector2Array([P.call(26, 44), P.call(74, 44), P.call(66, 88), P.call(50, 76), P.call(34, 88)]), col)
			draw_circle(P.call(42, 40), 5 * u, dark)
			draw_circle(P.call(58, 40), 5 * u, dark)
		"slash":
			draw_line(P.call(18, 84), P.call(84, 16), col, 14 * u)
			draw_line(P.call(30, 90), P.call(90, 30), col.darkened(0.3), 6 * u)
		"burst":
			var pts := PackedVector2Array()
			for i in 16:
				var r := 46.0 if i % 2 == 0 else 22.0
				pts.append(P.call(50 + cos(TAU * i / 16.0) * r, 50 + sin(TAU * i / 16.0) * r))
			draw_colored_polygon(pts, col)
		"cross":
			draw_rect(Rect2(P.call(38, 14), Vector2(24, 72) * u), col)
			draw_rect(Rect2(P.call(14, 38), Vector2(72, 24) * u), col)
		"leaf":
			draw_colored_polygon(PackedVector2Array([P.call(14, 80), P.call(24, 36), P.call(60, 12), P.call(88, 14), P.call(84, 50), P.call(52, 82)]), col)
			draw_line(P.call(16, 86), P.call(66, 36), dark, 5 * u)
		"mirror":
			draw_colored_polygon(PackedVector2Array([P.call(50, 8), P.call(80, 50), P.call(50, 92), P.call(20, 50)]), col)
			draw_line(P.call(50, 8), P.call(50, 92), dark, 5 * u)
		"swap":
			draw_line(P.call(16, 34), P.call(80, 34), col, 9 * u)
			draw_colored_polygon(PackedVector2Array([P.call(92, 34), P.call(74, 20), P.call(74, 48)]), col)
			draw_line(P.call(84, 66), P.call(20, 66), col, 9 * u)
			draw_colored_polygon(PackedVector2Array([P.call(8, 66), P.call(26, 52), P.call(26, 80)]), col)
		"clock":
			draw_arc(P.call(50, 50), 40 * u, 0, TAU, 32, col, 8 * u)
			draw_line(P.call(50, 50), P.call(50, 24), col, 7 * u)
			draw_line(P.call(50, 50), P.call(70, 58), col, 7 * u)
		"drop":
			draw_circle(P.call(50, 62), 26 * u, col)
			draw_colored_polygon(PackedVector2Array([P.call(50, 8), P.call(74, 54), P.call(26, 54)]), col)
		"split":
			draw_line(P.call(50, 90), P.call(50, 52), col, 8 * u)
			draw_line(P.call(50, 52), P.call(18, 14), col, 8 * u)
			draw_line(P.call(50, 52), P.call(82, 14), col, 8 * u)
		"swirl":
			draw_arc(P.call(50, 50), 34 * u, 0.3, 5.2, 24, col, 9 * u)
			draw_colored_polygon(PackedVector2Array([P.call(86, 54), P.call(70, 34), P.call(94, 36)]), col)
		"stack":
			for i in 3:
				draw_rect(Rect2(P.call(18, 62 - i * 22), Vector2(64, 16) * u), col.darkened(0.1 * i))
		"arrow":
			draw_line(P.call(10, 50), P.call(70, 50), col, 12 * u)
			draw_colored_polygon(PackedVector2Array([P.call(94, 50), P.call(66, 24), P.call(66, 76)]), col)
		"coin":
			draw_circle(P.call(50, 50), 40 * u, col)
			draw_circle(P.call(50, 50), 26 * u, dark)
		"ghost":
			draw_circle(P.call(50, 40), 28 * u, col)
			draw_rect(Rect2(P.call(22, 40), Vector2(56, 44) * u), col)
			for i in 3:
				draw_circle(P.call(30 + i * 20, 86), 10 * u, col)
		_:
			var st := PackedVector2Array()
			for i in 10:
				var r := 44.0 if i % 2 == 0 else 20.0
				st.append(P.call(50 + cos(TAU * i / 10.0 - PI / 2) * r, 50 + sin(TAU * i / 10.0 - PI / 2) * r))
			draw_colored_polygon(st, col)
