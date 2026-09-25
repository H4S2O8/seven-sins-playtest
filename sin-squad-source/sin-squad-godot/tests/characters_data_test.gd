extends SceneTree

const SINS := {
	"WR": "愤怒", "GR": "贪婪", "GL": "暴食", "EN": "嫉妒",
	"SL": "怠惰", "LU": "色欲", "PR": "傲慢",
}
const EXPECTED_HASH := "1CE508E93AE694D80DD55CC0F113AA8A6B82E2DBBD3AF81A2622236843704BA5"


func _initialize() -> void:
	var data := _read_json("res://content/characters/characters.json")
	var requirements := _read_json("res://content/characters/handler-requirements.json")
	var source_catalog := _read_json("res://content/source-catalog/catalog.json")
	_check(data.get("count") == 98, "characters.json count must be 98")
	_check(data.get("source", {}).get("sha256") == EXPECTED_HASH, "source hash mismatch")
	_check(data.get("handlers_ready_for_formal_pool") == false, "import must not mark handlers complete")
	_check(data.get("characters", []).size() == 98, "character array length must be 98")
	_check(requirements.get("formal_pool_blocked") == true, "formal pool must remain blocked")
	_check(requirements.get("bindings", []).size() == 98, "binding requirements must cover 98 IDs")

	var seen := {}
	var handler_keys := {}
	var source_entries := {}
	for source_entry in source_catalog.get("entries", []):
		source_entries[str(source_entry.get("id", ""))] = source_entry
	var counts := {}
	for character in data.characters:
		var id := str(character.get("id", ""))
		_check(not id.is_empty() and not seen.has(id), "empty or duplicate ID: " + id)
		seen[id] = true
		var prefix := id.substr(0, 2)
		_check(SINS.has(prefix) and character.get("sin") == SINS.get(prefix), "sin mismatch: " + id)
		counts[prefix] = int(counts.get(prefix, 0)) + 1
		_check(int(character.get("H", 0)) > 0, "invalid H: " + id)
		_check(int(character.get("A", 0)) > 0, "invalid A: " + id)
		_check(int(character.get("T_ticks", 0)) >= 6, "invalid T_ticks: " + id)
		_check(int(character.get("R", -1)) >= 0, "invalid R: " + id)
		_check(character.get("reach") in ["melee", "ranged"], "invalid reach: " + id)
		_check(character.get("armor_kind") in ["light", "medium", "heavy"], "invalid armor_kind: " + id)
		_check(not str(character.get("ability_text", "")).is_empty(), "empty ability text: " + id)
		_check(character.get("source_hash") == EXPECTED_HASH, "card source hash mismatch: " + id)
		_check(str(character.get("source_text", "")).begins_with("### " + id + "｜"), "source text mismatch: " + id)
		_check(source_entries.has(id), "missing source-catalog entry: " + id)
		var source_entry: Dictionary = source_entries[id]
		_check(source_entry.get("name") == character.get("name"), "source-catalog name mismatch: " + id)
		_check(source_entry.get("text") == character.get("source_text"), "source-catalog text mismatch: " + id)
		_check(source_entry.get("text").split("\n")[2].trim_prefix("能力：") == character.get("ability_text"),
			"ability text mismatch: " + id)
		var handler := str(character.get("logic_handler", ""))
		_check(handler == "character_" + id, "non-exact handler key: " + id)
		_check(not handler_keys.has(handler), "handler key shared by cards: " + id)
		_check(character.get("implementation_status") == "not_implemented", "unverified handler marked implemented: " + id)
		_check(character.get("positive_test") == false and character.get("negative_test") == false and character.get("expiry_test") == false,
			"unverified BattleEngine tests marked complete: " + id)
		handler_keys[handler] = true

	for prefix in SINS:
		_check(int(counts.get(prefix, 0)) == 14, "wrong character count for " + prefix)
	var binding_ids := {}
	for binding in requirements.bindings:
		var id := str(binding.get("content_id", ""))
		_check(seen.has(id) and not binding_ids.has(id), "missing/duplicate binding requirement: " + id)
		_check(binding.get("logic_handler") == "character_" + id, "binding key mismatch: " + id)
		_check(binding.get("required_binding_kind") == "talent", "wrong binding kind: " + id)
		_check(binding.get("positive_case") == "required_not_implemented", "positive test misreported: " + id)
		_check(binding.get("negative_case") == "required_not_implemented", "negative test misreported: " + id)
		_check(binding.get("expiry_or_departure_case") == "required_not_implemented", "expiry test misreported: " + id)
		binding_ids[id] = true
	_check(binding_ids.size() == 98, "binding requirement ID set incomplete")
	print("CHARACTER_DATA_TEST_OK count=98 unique_bindings=98 source_hash=" + EXPECTED_HASH + " integration=blocked")
	quit(0)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	_check(file != null, "cannot open " + path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(parsed is Dictionary, "invalid JSON document " + path)
	return parsed


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("CHARACTER_DATA_TEST_FAILED: " + message)
		quit(1)
