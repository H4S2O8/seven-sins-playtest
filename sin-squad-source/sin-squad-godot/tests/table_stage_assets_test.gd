extends SceneTree

const ATLAS_PATHS := {
	"dealers": "res://assets/sources/dealers/dealer-rig-v2.png",
	"hands": "res://assets/sources/hands/player-hand-poses-v2.png",
	"cards": "res://assets/sources/cards/card-frames-v1.png",
	"chips": "res://assets/sources/chips/chip-atlas-v1.png",
	"opponent_walk": "res://assets/sources/opponent/opponent-walk-keyframes-v1.png",
	"opponent_sit": "res://assets/sources/opponent/opponent-sit-keyframes-v1.png",
}


func _initialize() -> void:
	for asset_name: String in ATLAS_PATHS:
		var image := Image.load_from_file(ATLAS_PATHS[asset_name])
		if image.is_empty():
			push_error("Could not read source atlas: " + ATLAS_PATHS[asset_name])
			quit(1)
			return
		print("ATLAS %s %dx%d" % [asset_name, image.get_width(), image.get_height()])
		if asset_name == "opponent_sit":
			_report_vertical_alpha_components(image)
		var columns := 4 if asset_name == "dealers" or asset_name == "chips" else (2 if asset_name == "hands" or asset_name.begins_with("opponent_") else 3)
		var rows := 2 if asset_name == "cards" or asset_name == "chips" or asset_name.begins_with("opponent_") else 3
		var total_nonempty := 0
		for row in range(rows):
			for column in range(columns):
				var cell := Rect2i(
					floori(float(column * image.get_width()) / columns),
					floori(float(row * image.get_height()) / rows),
					floori(float((column + 1) * image.get_width()) / columns) - floori(float(column * image.get_width()) / columns),
					floori(float((row + 1) * image.get_height()) / rows) - floori(float(row * image.get_height()) / rows)
				)
				var bounds := _alpha_bounds(image, cell, 0.02)
				if not bounds.has_area():
					push_error("Empty expected atlas cell: %s[%d,%d]" % [asset_name, column, row])
					quit(1)
					return
				total_nonempty += 1
				print("  cell r%d c%d alpha_rect=(%d,%d,%d,%d)" % [row + 1, column + 1, bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y])
		print("  nonempty_cells=%d" % total_nonempty)
	quit(0)


func _report_vertical_alpha_components(image: Image) -> void:
	# The opponent sit atlas is not laid out in equal-height rows. Scan each
	# half-width independently and report contiguous non-empty alpha bands.
	for column in range(2):
		var x0 := floori(float(column * image.get_width()) / 2.0)
		var x1 := floori(float((column + 1) * image.get_width()) / 2.0)
		var band_start := -1
		var band_end := -1
		var min_x := x1
		var max_x := x0 - 1
		for y in range(image.get_height()):
			var row_min := x1
			var row_max := x0 - 1
			for x in range(x0, x1):
				if image.get_pixel(x, y).a > 0.02:
					row_min = mini(row_min, x)
					row_max = maxi(row_max, x)
			if row_max >= row_min:
				if band_start < 0:
					band_start = y
				min_x = mini(min_x, row_min)
				max_x = maxi(max_x, row_max)
				band_end = y
			elif band_start >= 0:
				print("  alpha_band c%d=(%d,%d,%d,%d)" % [column + 1, min_x, band_start, max_x - min_x + 1, band_end - band_start + 1])
				band_start = -1
				min_x = x1
				max_x = x0 - 1
		if band_start >= 0:
			print("  alpha_band c%d=(%d,%d,%d,%d)" % [column + 1, min_x, band_start, max_x - min_x + 1, band_end - band_start + 1])


func _alpha_bounds(image: Image, region: Rect2i, alpha_min: float) -> Rect2i:
	var min_x := region.position.x + region.size.x
	var min_y := region.position.y + region.size.y
	var max_x := region.position.x - 1
	var max_y := region.position.y - 1
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if image.get_pixel(x, y).a > alpha_min:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
