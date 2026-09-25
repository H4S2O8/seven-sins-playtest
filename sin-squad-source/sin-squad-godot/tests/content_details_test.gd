extends SceneTree

const DETAILS := preload("res://presentation/table/content_details.gd")

func _init() -> void:
	var catalog := DETAILS.new()
	var ok := catalog.load_catalog()
	for content_id in ["WR01", "EQ01", "FX01", "VC01", "AR01", "PE01"]:
		var text := catalog.detail_text(content_id)
		ok = ok and catalog.has(content_id) and text.contains(content_id) and text.length() > content_id.length()
	print("CONTENT_DETAILS_TEST entries=%d result=%s" % [catalog.entries.size(), "PASS" if ok else "FAIL"])
	quit(0 if ok else 1)
