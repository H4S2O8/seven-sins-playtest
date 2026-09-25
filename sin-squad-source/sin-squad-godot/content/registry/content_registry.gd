class_name ContentRegistry
extends RefCounted

const EXPECTED_COUNTS := {"WR": 14, "GR": 14, "GL": 14, "EN": 14, "SL": 14, "LU": 14, "PR": 14,
	"EQ": 50, "FX": 50, "VC": 30, "AR": 20, "PE": 50}
const REGISTRY_PATH := "res://content/registry/catalog_registry.json"

var by_id: Dictionary = {}
var by_category: Dictionary = {}
var load_error := ""

func load_registry(path: String = REGISTRY_PATH) -> bool:
	by_id.clear()
	by_category.clear()
	load_error = ""
	if not FileAccess.file_exists(path):
		load_error = "registry_missing:" + path
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("entries", null) is Array:
		load_error = "registry_invalid_json_or_schema"
		return false
	for raw: Variant in parsed.entries:
		if not raw is Dictionary:
			load_error = "entry_not_object"
			return false
		var entry: Dictionary = raw
		var item_id := str(entry.get("id", ""))
		var category := str(entry.get("category", ""))
		if item_id.is_empty() or by_id.has(item_id):
			load_error = "missing_or_duplicate_id:" + item_id
			return false
		if not EXPECTED_COUNTS.has(category):
			load_error = "unknown_category:" + category
			return false
		if str(entry.get("handler_status", "")) != "not_implemented" or not str(entry.get("logic_handler", "")).is_empty():
			load_error = "unexpected_handler_claim:" + item_id
			return false
		by_id[item_id] = ContentDefinition.from_dict(entry)
		if not by_category.has(category):
			by_category[category] = []
		by_category[category].append(item_id)
	if by_id.size() != 298:
		load_error = "entry_count_mismatch:%d" % by_id.size()
		return false
	for category: String in EXPECTED_COUNTS:
		if by_category.get(category, []).size() != EXPECTED_COUNTS[category]:
			load_error = "category_count_mismatch:%s:%d" % [category, by_category.get(category, []).size()]
			return false
	return true

func get_definition(item_id: String) -> ContentDefinition:
	return by_id.get(item_id)

func ids_for_category(category: String) -> Array:
	return by_category.get(category, []).duplicate()

func summary() -> Dictionary:
	var result := {"total": by_id.size(), "categories": {}}
	for category: String in EXPECTED_COUNTS:
		result.categories[category] = by_category.get(category, []).size()
	return result

