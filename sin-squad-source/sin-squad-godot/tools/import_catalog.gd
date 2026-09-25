extends SceneTree

const SOURCE_FILES := ["00-战斗约定.md", "01-人物.md", "02-装备与槽位.md", "03-胜利规则.md", "04-场地与公共效果.md", "catalog.json"]
const LOCKED_HASHES := {
	"00-战斗约定.md": "B544791BE4018BA8EFACB83AFD2FD6B1BF2F2CE5D05E49A47E93F7FEB0665697",
	"01-人物.md": "1CE508E93AE694D80DD55CC0F113AA8A6B82E2DBBD3AF81A2622236843704BA5",
	"02-装备与槽位.md": "5E7A8EC39406C64013C15F867DBE61DA4639BE7CBA3611E0C92AC144703E2DBD",
	"03-胜利规则.md": "D3AC501AD84E6B2ED1F102F481DDAF87AF55036815313FA281E96DBD25FC41D1",
	"04-场地与公共效果.md": "CCA7D70FDE065E63707D590F6D8272B8CCF81CB55007822FADF49CC8E7B7FFD9"
}
const EXPECTED_COUNTS := {"WR": 14, "GR": 14, "GL": 14, "EN": 14, "SL": 14, "LU": 14, "PR": 14,
	"EQ": 50, "FX": 50, "VC": 30, "AR": 20, "PE": 50}
const SIN_NAMES := {"WR": "愤怒", "GR": "贪婪", "GL": "暴食", "EN": "嫉妒", "SL": "怠惰", "LU": "色欲", "PR": "傲慢"}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_root := ProjectSettings.globalize_path("res://../sin-squad-design")
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--source-root" and i + 1 < args.size():
			source_root = args[i + 1]
		elif args[i].begins_with("--source-root="):
			source_root = args[i].trim_prefix("--source-root=")
	if not source_root.is_absolute_path():
		source_root = ProjectSettings.globalize_path("res://" + source_root)
	var raw_entries: Array = []
	var hash_manifest := {}
	for file_name: String in SOURCE_FILES:
		var source_path := source_root.path_join(file_name)
		if not FileAccess.file_exists(source_path):
			_fail("missing_source:" + source_path)
			return
		var source_text := FileAccess.get_file_as_string(source_path)
		var digest := _sha256(source_text)
		if LOCKED_HASHES.has(file_name) and digest != LOCKED_HASHES[file_name]:
			_fail("source_hash_mismatch:%s:%s" % [file_name, digest])
			return
		hash_manifest[file_name] = digest
		if file_name == "catalog.json":
			var parsed: Variant = JSON.parse_string(source_text)
			if not parsed is Dictionary or not parsed.get("entries", null) is Array:
				_fail("catalog_schema_invalid")
				return
			raw_entries = parsed.entries
	if raw_entries.size() != 298:
		_fail("catalog_total_mismatch:%d" % raw_entries.size())
		return
	var seen := {}
	var actual_counts := {}
	var normalized: Array[Dictionary] = []
	for entry_value: Variant in raw_entries:
		if not entry_value is Dictionary:
			_fail("catalog_entry_not_object")
			return
		var entry: Dictionary = entry_value
		var id := str(entry.get("id", ""))
		var category := str(entry.get("category", ""))
		if id.is_empty() or seen.has(id):
			_fail("empty_or_duplicate_id:" + id)
			return
		if not EXPECTED_COUNTS.has(category) or str(entry.get("name", "")).is_empty() or str(entry.get("text", "")).is_empty():
			_fail("entry_missing_required_index_fields:" + id)
			return
		seen[id] = true
		actual_counts[category] = int(actual_counts.get(category, 0)) + 1
		normalized.append(_normalize(entry))
	for category: String in EXPECTED_COUNTS:
		if int(actual_counts.get(category, 0)) != EXPECTED_COUNTS[category]:
			_fail("category_count_mismatch:%s:%d" % [category, actual_counts.get(category, 0)])
			return
	var copy_dir := ProjectSettings.globalize_path("res://content/source-catalog")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(copy_dir)
	if mkdir_error != OK:
		_fail("cannot_create_source_catalog:%d" % mkdir_error)
		return
	for file_name: String in SOURCE_FILES:
		var src := FileAccess.get_file_as_string(source_root.path_join(file_name))
		var destination := copy_dir.path_join(file_name)
		var output := FileAccess.open(destination, FileAccess.WRITE)
		if output == null:
			_fail("cannot_write_source:" + destination)
			return
		output.store_string(src)
		output.close()
	var registry := {"schema_version": 1, "source_status": "design-not-implemented", "total": normalized.size(),
		"expected_counts": EXPECTED_COUNTS, "actual_counts": actual_counts, "entries": normalized}
	var registry_dir := ProjectSettings.globalize_path("res://content/registry")
	mkdir_error = DirAccess.make_dir_recursive_absolute(registry_dir)
	if mkdir_error != OK:
		_fail("cannot_create_registry_dir:%d" % mkdir_error)
		return
	var registry_file := FileAccess.open(registry_dir.path_join("catalog_registry.json"), FileAccess.WRITE)
	if registry_file == null:
		_fail("cannot_write_registry")
		return
	registry_file.store_string(JSON.stringify(registry, "\t"))
	registry_file.close()
	var manifest_file := FileAccess.open(copy_dir.path_join("source-manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		_fail("cannot_write_source_manifest")
		return
	manifest_file.store_string(JSON.stringify({"source_root_name": "sin-squad-design", "sha256": hash_manifest}, "\t"))
	manifest_file.close()
	print("IMPORT_OK total=%d unique_ids=%d counts=%s handlers=not_implemented" % [normalized.size(), seen.size(), JSON.stringify(actual_counts)])
	quit(0)

func _normalize(entry: Dictionary) -> Dictionary:
	var category := str(entry.category)
	var text := str(entry.text)
	var fields := {"content_kind": _content_kind(category)}
	if SIN_NAMES.has(category):
		fields.sin = SIN_NAMES[category]
		fields.squad_size = 3
		var panel := RegEx.new()
		panel.compile("面板：H([0-9]+) / A([0-9]+) / T([0-9.]+)秒 / R([0-9]+) / (近|远) / (轻甲|中甲|重甲)")
		var match_result := panel.search(text)
		if match_result == null:
			fields.panel_parse_status = "not_found_in_source_text"
		else:
			fields.max_hp = int(match_result.get_string(1))
			fields.attack = int(match_result.get_string(2))
			fields.attack_interval_seconds = float(match_result.get_string(3))
			fields.armor = int(match_result.get_string(4))
			fields.reach = "melee" if match_result.get_string(5) == "近" else "ranged"
			fields.armor_kind = match_result.get_string(6)
			fields.panel_parse_status = "parsed_from_catalog_source_text"
	if category == "EQ":
		fields.legal_slot_types = ["equipment"]
	if category == "FX":
		fields.legal_slot_types = ["effect"]
	if category == "VC":
		fields.deadline_seconds = _rule_deadline(text)
		fields.rule_handler_status = "not_implemented"
	var entry_id := str(entry.id)
	return {"id": entry_id, "name": str(entry.name), "category": category, "source": str(entry.source), "source_text": text,
		"logic_handler": "", "handler_status": "not_implemented", "presentation_id": "", "schema_version": 1,
		"fields": fields}

func _content_kind(category: String) -> String:
	if SIN_NAMES.has(category):
		return "character"
	match category:
		"EQ": return "equipment"
		"FX": return "slot_effect"
		"VC": return "victory_rule"
		"AR": return "arena"
		"PE": return "public_effect"
	return "unknown"

func _rule_deadline(text: String) -> Variant:
	var regex := RegEx.new()
	regex.compile("(12|24|36)秒")
	var found := regex.search(text)
	return int(found.get_string(1)) if found != null else null

func _sha256(value: String) -> String:
	var context := HashingContext.new()
	var error := context.start(HashingContext.HASH_SHA256)
	if error != OK:
		return ""
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode().to_upper()

func _fail(reason: String) -> void:
	printerr("IMPORT_FAILED " + reason)
	quit(1)

