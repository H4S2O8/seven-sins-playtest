class_name SinContentDetails
extends RefCounted

const CATALOG_PATH := "res://content/registry/catalog_registry.json"

var entries: Dictionary = {}

func load_catalog(path: String = CATALOG_PATH) -> bool:
	entries.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	for raw_entry: Variant in parsed.get("entries", []):
		if not raw_entry is Dictionary:
			continue
		var content_id := str(raw_entry.get("id", ""))
		if not content_id.is_empty():
			entries[content_id] = raw_entry.duplicate(true)
	return not entries.is_empty()

func has(content_id: String) -> bool:
	return entries.has(content_id)

func detail_text(content_id: String) -> String:
	var entry: Dictionary = entries.get(content_id, {})
	if entry.is_empty():
		return content_id
	var name := str(entry.get("name", ""))
	var source_text := str(entry.get("source_text", "")).strip_edges()
	var lines := source_text.split("\n")
	if not lines.is_empty() and str(lines[0]).begins_with("###"):
		lines.remove_at(0)
	var body := "\n".join(lines).strip_edges()
	var title := "%s｜%s" % [content_id, name] if not name.is_empty() else content_id
	return title if body.is_empty() else "%s\n%s" % [title, body]

func combined_text(content_ids: Array, heading: String = "") -> String:
	var unique: Dictionary = {}
	var blocks: Array[String] = []
	for value: Variant in content_ids:
		var content_id := str(value)
		if content_id.is_empty() or unique.has(content_id):
			continue
		unique[content_id] = true
		blocks.append(detail_text(content_id))
	var body := "\n\n".join(blocks)
	if heading.is_empty():
		return body
	return heading if body.is_empty() else "%s\n\n%s" % [heading, body]
