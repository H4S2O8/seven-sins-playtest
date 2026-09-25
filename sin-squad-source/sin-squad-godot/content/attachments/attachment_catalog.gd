class_name AttachmentCatalog
extends RefCounted

const DATA_PATH := "res://content/attachments/attachments.json"
const CHARACTER_DATA_PATH := "res://content/characters/characters.json"

var by_id: Dictionary = {}
var load_error := ""

func load_data(path: String = DATA_PATH) -> bool:
	by_id.clear()
	load_error = ""
	if not FileAccess.file_exists(path):
		load_error = "attachment_data_missing:" + path
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("attachments", null) is Array:
		load_error = "attachment_data_schema_invalid"
		return false
	for raw: Variant in parsed.attachments:
		if not raw is Dictionary:
			load_error = "attachment_not_object"
			return false
		var item_id := str(raw.get("id", ""))
		if item_id.is_empty() or by_id.has(item_id):
			load_error = "attachment_id_missing_or_duplicate:" + item_id
			return false
		if str(raw.get("category", "")) not in ["EQ", "FX"]:
			load_error = "attachment_category_invalid:" + item_id
			return false
		by_id[item_id] = raw.duplicate(true)
	if by_id.size() != 100:
		load_error = "attachment_count_mismatch:%d" % by_id.size()
		return false
	return true

func get_card(card_id: String) -> Dictionary:
	return by_id.get(card_id, {}).duplicate(true)

static func sin_for_definition_id(definition_id: String, path: String = CHARACTER_DATA_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return ""
	for character: Dictionary in parsed.get("characters", []):
		if str(character.get("id", "")) == definition_id:
			return str(character.get("sin", ""))
	return ""

static func apply_setup_modifiers(unit_definition: Dictionary, card_id: String, data_path: String = DATA_PATH) -> Dictionary:
	var result := unit_definition.duplicate(true)
	var card_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if not card_data is Dictionary:
		return {"accepted": false, "reason": "attachment_data_invalid", "unit": unit_definition.duplicate(true)}
	var selected: Dictionary = {}
	for card: Dictionary in card_data.get("attachments", []):
		if str(card.get("id", "")) == card_id:
			selected = card
			break
	if selected.is_empty():
		return {"accepted": false, "reason": "unknown_attachment:" + card_id, "unit": unit_definition.duplicate(true)}
	var extra_modifiers: Array = result.get("setup_modifiers", []).duplicate(true)
	for modifier: Dictionary in selected.get("initial_modifiers", []):
		match str(modifier.get("stat", "")):
			"A_flat", "H_max_flat", "T_ticks_flat", "R_flat":
				var setup_stat := "H_flat" if str(modifier.stat) == "H_max_flat" else str(modifier.stat)
				var setup_modifier := {"stat": setup_stat, "amount": int(modifier.amount), "phase": "pre_battle_setup"}
				for metadata_key: String in ["minimum", "current_hp_minimum", "also_current_hp"]:
					if modifier.has(metadata_key): setup_modifier[metadata_key] = modifier[metadata_key]
				extra_modifiers.append(setup_modifier)
			"reach", "flying":
				extra_modifiers.append({"stat": str(modifier.stat), "value": modifier.value, "phase": "pre_battle_setup"})
			"attack_damage_bp":
				extra_modifiers.append({"stat": "natural_damage_bp", "amount": int(modifier.amount), "phase": "pre_battle_setup"})
			_:
				return {"accepted": false, "reason": "unsupported_setup_modifier:%s:%s" % [card_id, modifier.get("stat", "")], "unit": unit_definition.duplicate(true)}
	result["setup_modifiers"] = extra_modifiers
	result["setup_attachment_id"] = card_id
	return {"accepted": true, "reason": "setup_modifiers_deferred_to_engine_pre_battle_phase", "unit": result}
