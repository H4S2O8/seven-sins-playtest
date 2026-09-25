extends SceneTree

const ATLAS_PATH := "res://assets/sources/dealers/dealer-rig-v2.png"


func _initialize() -> void:
	var image := Image.load_from_file(ATLAS_PATH)
	var visited := PackedByteArray()
	visited.resize(image.get_width() * image.get_height())
	var queue := PackedInt32Array()
	var components: Array[Dictionary] = []
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var start := y * image.get_width() + x
			if visited[start] != 0 or image.get_pixel(x, y).a < 0.08:
				continue
			visited[start] = 1
			queue.clear()
			queue.append(start)
			var min_x := x
			var max_x := x
			var min_y := y
			var max_y := y
			var cursor := 0
			while cursor < queue.size():
				var point := queue[cursor]
				cursor += 1
				var px := point % image.get_width()
				var py := point / image.get_width()
				min_x = mini(min_x, px)
				max_x = maxi(max_x, px)
				min_y = mini(min_y, py)
				max_y = maxi(max_y, py)
				for neighbor in [point - 1, point + 1, point - image.get_width(), point + image.get_width()]:
					if neighbor < 0 or neighbor >= visited.size() or visited[neighbor] != 0:
						continue
					var nx: int = neighbor % image.get_width()
					var ny: int = neighbor / image.get_width()
					if absi(nx - px) + absi(ny - py) != 1 or image.get_pixel(nx, ny).a < 0.08:
						continue
					visited[neighbor] = 1
					queue.append(neighbor)
			components.append({"area": queue.size(), "x": min_x, "y": min_y, "w": max_x - min_x + 1, "h": max_y - min_y + 1})
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.area > b.area)
	for component in components:
		if component.area > 500:
			print("COMP %s" % component)
	quit(0)
