class_name SinSaveStore
extends RefCounted

const SessionScript = preload("res://core/session/session.gd")
const FORMAT_ID := "sin-squad-session-save"
const SCHEMA_VERSION := 2
const SAVE_DIRECTORY := "user://saves"
const PROFILE_DIRECTORY := "user://profiles"
const TUTORIAL_DIRECTORY := "user://tutorial-saves"
const INTEGER_TAG := "$sin_integer"
const PROFILE_FORMAT := "sin-squad-profile-save"
const PROFILE_SCHEMA := 1
const TUTORIAL_FORMAT := "sin-squad-tutorial-save"
const TUTORIAL_SCHEMA := 1


func commit_session(session: SinSession, slot: String = "default", tutorial_state: Dictionary = {}) -> Dictionary:
	if session == null: return _error("session_missing")
	if not _valid_slot(slot): return _error("invalid_save_slot")
	if not session.ledger.assert_invariants(): return _error("session_ledger_invalid")
	var normalized := _normalize_json_data({"format":FORMAT_ID,"schema_version":SCHEMA_VERSION,
		"session_snapshot":session.snapshot(),"tutorial_state":tutorial_state})
	if not str(normalized.get("error", "")).is_empty(): return _error("save_contains_non_data_value:" + str(normalized.error))
	var document: Dictionary = normalized.data
	var validation := _validate_document(document)
	if not str(validation.get("error", "")).is_empty(): return validation
	return _atomic_commit(_slot_path(slot), document, Callable(self, "_validate_document"), slot, SCHEMA_VERSION)


func load_session(slot: String = "default", restore_into: SinSession = null) -> Dictionary:
	if not _valid_slot(slot): return _error("invalid_save_slot")
	var primary := _read_and_validate_path(_slot_path(slot), restore_into)
	if str(primary.get("error", "")).is_empty(): return primary
	# A prior complete commit remains recoverable if a crash interrupted replacement.
	var backup := _read_and_validate_path(_slot_path(slot) + ".bak", restore_into)
	if str(backup.get("error", "")).is_empty():
		backup["recovered_from_backup"] = true
		return backup
	return primary


## Imports JSON data only. It never loads scripts/resources or executes document fields.
func import_json(contents: String) -> Dictionary:
	if contents.length() > 8_000_000: return _error("save_too_large")
	var parsed := _parse_json(contents)
	if not bool(parsed.get("ok", false)): return _error("save_json_invalid")
	if not parsed.data is Dictionary: return _error("save_json_invalid")
	return _validate_document(parsed.data)


func export_json(session: SinSession, tutorial_state: Dictionary = {}) -> Dictionary:
	if session == null: return _error("session_missing")
	var normalized := _normalize_json_data({"format":FORMAT_ID,"schema_version":SCHEMA_VERSION,
		"session_snapshot":session.snapshot(),"tutorial_state":tutorial_state})
	if not str(normalized.get("error", "")).is_empty(): return _error("save_contains_non_data_value:" + str(normalized.error))
	var document: Dictionary = normalized.data
	var validation := _validate_document(document)
	if not str(validation.get("error", "")).is_empty(): return validation
	return {"error":"","json":JSON.stringify(_encode_json_data(document), "", false),"schema_version":SCHEMA_VERSION}


func commit_profile(profile: Dictionary, slot: String = "default") -> Dictionary:
	if not _valid_slot(slot): return _error("invalid_profile_slot")
	var normalized := _normalize_json_data({"format":PROFILE_FORMAT,"schema_version":PROFILE_SCHEMA,"profile":profile})
	if not str(normalized.get("error", "")).is_empty(): return _error("profile_contains_non_data_value:" + str(normalized.error))
	var document: Dictionary = normalized.data
	var validation := _validate_profile_document(document)
	if not str(validation.get("error", "")).is_empty(): return validation
	return _atomic_commit(_profile_path(slot), document, Callable(self, "_validate_profile_document"), slot, PROFILE_SCHEMA)


func load_profile(slot: String = "default") -> Dictionary:
	if not _valid_slot(slot): return _error("invalid_profile_slot")
	var primary := _read_validate_profile_path(_profile_path(slot))
	if str(primary.get("error", "")).is_empty(): return primary
	var backup := _read_validate_profile_path(_profile_path(slot) + ".bak")
	if str(backup.get("error", "")).is_empty():
		backup["recovered_from_backup"] = true
		return backup
	return primary


func export_profile_json(profile: Dictionary) -> Dictionary:
	var normalized := _normalize_json_data({"format":PROFILE_FORMAT,"schema_version":PROFILE_SCHEMA,"profile":profile})
	if not str(normalized.get("error", "")).is_empty(): return _error("profile_contains_non_data_value:" + str(normalized.error))
	var document: Dictionary = normalized.data
	var validation := _validate_profile_document(document)
	if not str(validation.get("error", "")).is_empty(): return validation
	return {"error":"","json":JSON.stringify(_encode_json_data(document), "", false),"schema_version":PROFILE_SCHEMA}


func import_profile_json(contents: String) -> Dictionary:
	if contents.length() > 8_000_000: return _error("profile_too_large")
	var parsed := _parse_json(contents)
	if not bool(parsed.get("ok", false)) or not parsed.data is Dictionary: return _error("profile_json_invalid")
	return _validate_profile_document(parsed.data)


## A dedicated namespace prevents tutorial-only wallet/progress saves from replacing a Profile.
func commit_tutorial_progress(progress: Dictionary, slot: String = "default") -> Dictionary:
	if not _valid_slot(slot): return _error("invalid_tutorial_slot")
	var normalized := _normalize_json_data({"format":TUTORIAL_FORMAT,"schema_version":TUTORIAL_SCHEMA,"progress":progress})
	if not str(normalized.get("error", "")).is_empty(): return _error("tutorial_save_contains_non_data_value:" + str(normalized.error))
	var document: Dictionary = normalized.data
	if not str(document.get("format", "")) == TUTORIAL_FORMAT or not document.get("progress", null) is Dictionary:
		return _error("tutorial_save_invalid")
	return _atomic_commit(_tutorial_path(slot), document, Callable(self, "_validate_tutorial_document"), slot, TUTORIAL_SCHEMA)


func load_tutorial_progress(slot: String = "default") -> Dictionary:
	if not _valid_slot(slot): return _error("invalid_tutorial_slot")
	var primary := _read_validate_tutorial_path(_tutorial_path(slot))
	if str(primary.get("error", "")).is_empty(): return primary
	var backup := _read_validate_tutorial_path(_tutorial_path(slot) + ".bak")
	if str(backup.get("error", "")).is_empty():
		backup["recovered_from_backup"] = true
		return backup
	return primary


func _validate_document(document: Dictionary, restore_into: SinSession = null) -> Dictionary:
	var non_data_path := _non_data_path(document, "root")
	if not non_data_path.is_empty(): return _error("save_contains_non_data_value:" + non_data_path)
	if str(document.get("format", "")) != FORMAT_ID: return _error("save_format_unsupported")
	if not _is_exact_integer(document.get("schema_version", null)) or int(document.schema_version) != SCHEMA_VERSION:
		return _error("save_schema_unsupported:%s" % str(document.get("schema_version", "missing")))
	if not document.get("session_snapshot", null) is Dictionary: return _error("save_session_snapshot_missing")
	if not document.get("tutorial_state", {}) is Dictionary: return _error("save_tutorial_state_invalid")
	var restored: SinSession = restore_into if restore_into != null else SessionScript.new()
	if not restored.restore_snapshot(document.session_snapshot): return _error("save_session_snapshot_corrupt")
	if not restored.ledger.assert_invariants(): return _error("save_ledger_invalid")
	return {"error":"","session":restored,"tutorial_state":document.get("tutorial_state", {}).duplicate(true),
		"schema_version":SCHEMA_VERSION}


func _validate_profile_document(document: Dictionary) -> Dictionary:
	var invalid_path := _non_data_path(document, "root")
	if not invalid_path.is_empty(): return _error("profile_non_data_value:" + invalid_path)
	if not document.get("format", "") == PROFILE_FORMAT: return _error("profile_format_unsupported")
	if not document.get("schema_version", null) is int or document.schema_version != PROFILE_SCHEMA:
		return _error("profile_schema_unsupported")
	var profile: Variant = document.get("profile", null)
	if not profile is Dictionary: return _error("profile_data_missing")
	for required_key in ["wallet", "tutorial_completed", "settings", "tutorial_progress", "active_session_snapshot"]:
		if not profile.has(required_key): return _error("profile_field_missing:" + str(required_key))
	var wallet: Variant = profile.get("wallet", null)
	if not wallet is int or wallet < 0: return _error("profile_wallet_invalid")
	if not profile.get("tutorial_completed", null) is bool: return _error("profile_tutorial_flag_invalid")
	if not profile.get("settings", null) is Dictionary or not profile.get("tutorial_progress", null) is Dictionary:
		return _error("profile_preferences_or_tutorial_invalid")
	var active: Variant = profile.get("active_session_snapshot", null)
	var active_session: SinSession = null
	if active != null:
		if not active is Dictionary: return _error("profile_active_session_invalid")
		active_session = SessionScript.new()
		if not active_session.restore_snapshot(active) or not active_session.ledger.assert_invariants():
			return _error("profile_active_session_corrupt")
	return {"error":"","profile":profile.duplicate(true),"active_session":active_session,"schema_version":PROFILE_SCHEMA}


func _validate_tutorial_document(document: Dictionary) -> Dictionary:
	var invalid_path := _non_data_path(document, "root")
	if not invalid_path.is_empty(): return _error("tutorial_non_data_value:" + invalid_path)
	if document.get("format", "") != TUTORIAL_FORMAT: return _error("tutorial_format_unsupported")
	if not document.get("schema_version", null) is int or document.schema_version != TUTORIAL_SCHEMA:
		return _error("tutorial_schema_unsupported")
	if not document.get("progress", null) is Dictionary: return _error("tutorial_progress_invalid")
	return {"error":"","progress":document.progress.duplicate(true),"schema_version":TUTORIAL_SCHEMA}


func _atomic_commit(path: String, document: Dictionary, validator: Callable, slot: String, schema: int) -> Dictionary:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if directory_error != OK: return _error("save_directory_unavailable:%d" % directory_error)
	var temporary_path := path + ".tmp"
	var backup_path := path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null: return _error("save_open_failed:%d" % FileAccess.get_open_error())
	file.store_string(JSON.stringify(_encode_json_data(document), "", false))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return _error("save_write_failed:%d" % write_error)
	var staged := _read_decoded_path(temporary_path)
	if not str(staged.get("error", "")).is_empty(): return _error("save_staged_validation_failed:" + str(staged.error))
	var stage_validation: Dictionary = validator.call(staged.document)
	if not str(stage_validation.get("error", "")).is_empty(): return _error("save_staged_validation_failed:" + str(stage_validation.error))
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temporary_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	var had_previous := FileAccess.file_exists(path)
	if had_previous:
		if FileAccess.file_exists(backup_path):
			var remove_backup := DirAccess.remove_absolute(absolute_backup)
			if remove_backup != OK: return _error("save_backup_rotation_failed:%d" % remove_backup)
		var backup_result := DirAccess.rename_absolute(absolute_path, absolute_backup)
		if backup_result != OK: return _error("save_backup_create_failed:%d" % backup_result)
	var replace_result := DirAccess.rename_absolute(absolute_temp, absolute_path)
	if replace_result != OK:
		if had_previous:
			var rollback_result := DirAccess.rename_absolute(absolute_backup, absolute_path)
			if rollback_result != OK: return _error("save_replace_failed:%d;rollback_failed:%d" % [replace_result,rollback_result])
		return _error("save_replace_failed:%d" % replace_result)
	return {"error":"","saved":true,"slot":slot,"schema_version":schema}


func _read_validate_profile_path(path: String) -> Dictionary:
	var parsed := _read_decoded_path(path)
	if not str(parsed.get("error", "")).is_empty(): return parsed
	return _validate_profile_document(parsed.document)


func _read_validate_tutorial_path(path: String) -> Dictionary:
	var parsed := _read_decoded_path(path)
	if not str(parsed.get("error", "")).is_empty(): return parsed
	return _validate_tutorial_document(parsed.document)


func _read_decoded_path(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _error("save_not_found_or_unreadable:%d" % FileAccess.get_open_error())
	var contents := file.get_as_text()
	file.close()
	if contents.length() > 8_000_000: return _error("save_too_large")
	var parsed := _parse_json(contents)
	if not bool(parsed.get("ok", false)) or not parsed.data is Dictionary: return _error("save_json_invalid")
	return {"error":"","document":parsed.data}


func _non_data_path(value: Variant, path: String) -> String:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return ""
		TYPE_FLOAT:
			return "" if is_finite(float(value)) else path
		TYPE_ARRAY:
			for index in range(value.size()):
				var invalid := _non_data_path(value[index], "%s[%d]" % [path,index])
				if not invalid.is_empty(): return invalid
			return ""
		TYPE_DICTIONARY:
			for key in value:
				if not key is String: return "%s.<non_string_key>" % path
				var invalid := _non_data_path(value[key], "%s.%s" % [path,key])
				if not invalid.is_empty(): return invalid
			return ""
		_:
			return path


func _parse_json(contents: String) -> Dictionary:
	var parser := JSON.new()
	var error_code := parser.parse(contents)
	if error_code != OK: return {"ok":false}
	var decoded := _decode_json_data(parser.data)
	if not str(decoded.get("error", "")).is_empty(): return {"ok":false}
	return {"ok":true,"data":decoded.data}


func _read_and_validate_path(path: String, restore_into: SinSession = null) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _error("save_not_found_or_unreadable:%d" % FileAccess.get_open_error())
	var contents := file.get_as_text()
	file.close()
	if contents.length() > 8_000_000: return _error("save_too_large")
	var parsed := _parse_json(contents)
	if not bool(parsed.get("ok", false)) or not parsed.data is Dictionary: return _error("save_json_invalid")
	return _validate_document(parsed.data, restore_into)


func _encode_json_data(value: Variant) -> Variant:
	match typeof(value):
		TYPE_INT:
			return {INTEGER_TAG:str(value)}
		TYPE_ARRAY:
			var result: Array = []
			for item in value: result.append(_encode_json_data(item))
			return result
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key in value: result[str(key)] = _encode_json_data(value[key])
			return result
		_:
			return value


func _decode_json_data(value: Variant, path: String = "root") -> Dictionary:
	if value is Array:
		var result: Array = []
		for index in range(value.size()):
			var item := _decode_json_data(value[index], "%s[%d]" % [path,index])
			if not str(item.get("error", "")).is_empty(): return item
			result.append(item.data)
		return {"error":"","data":result}
	if value is Dictionary:
		if value.has(INTEGER_TAG):
			if value.size() != 1 or not value[INTEGER_TAG] is String: return {"error":path + ".integer_tag_invalid"}
			var parsed_integer := _parse_tagged_integer(value[INTEGER_TAG])
			if not bool(parsed_integer.get("ok", false)): return {"error":path + ".integer_tag_invalid"}
			return {"error":"","data":parsed_integer.value}
		var result: Dictionary = {}
		for key in value:
			if not key is String: return {"error":path + ".non_string_key"}
			var item := _decode_json_data(value[key], "%s.%s" % [path,key])
			if not str(item.get("error", "")).is_empty(): return item
			result[key] = item.data
		return {"error":"","data":result}
	if value is int or (value is float and is_finite(float(value)) and float(value) == roundf(float(value))):
		return {"error":path + ".untagged_integer"}
	return {"error":"","data":value}


func _parse_tagged_integer(text_value: String) -> Dictionary:
	if text_value.is_empty() or text_value == "-0": return {"ok":false}
	var digits := text_value.trim_prefix("-")
	if digits.is_empty(): return {"ok":false}
	for character in digits:
		if character < "0" or character > "9": return {"ok":false}
	if digits.length() > 1 and digits.begins_with("0"): return {"ok":false}
	if text_value.begins_with("-"):
		if digits.length() > 19 or (digits.length() == 19 and digits > "9223372036854775808"): return {"ok":false}
	else:
		if digits.length() > 19 or (digits.length() == 19 and digits > "9223372036854775807"): return {"ok":false}
	return {"ok":true,"value":int(text_value)}


func _normalize_json_data(value: Variant, path: String = "root") -> Dictionary:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return {"error":"","data":value}
		TYPE_STRING_NAME:
			return {"error":"","data":str(value)}
		TYPE_FLOAT:
			if not is_finite(float(value)): return {"error":path}
			if _is_exact_integer(value): return {"error":path + ".integer_must_be_typed_int"}
			return {"error":"","data":value}
		TYPE_ARRAY:
			var converted: Array = []
			for index in range(value.size()):
				var item := _normalize_json_data(value[index], "%s[%d]" % [path,index])
				if not str(item.get("error", "")).is_empty(): return item
				converted.append(item.data)
			return {"error":"","data":converted}
		TYPE_DICTIONARY:
			var converted: Dictionary = {}
			for key in value:
				if not key is String and not key is StringName: return {"error":"%s.<non_text_key>" % path}
				var normalized_key := str(key)
				if converted.has(normalized_key): return {"error":"%s.<duplicate_normalized_key>" % path}
				var item := _normalize_json_data(value[key], "%s.%s" % [path,normalized_key])
				if not str(item.get("error", "")).is_empty(): return item
				converted[normalized_key] = item.data
			return {"error":"","data":converted}
		_:
			return {"error":path}


func _is_exact_integer(value: Variant) -> bool:
	if value is int: return true
	if not value is float or not is_finite(float(value)): return false
	return absf(float(value) - roundf(float(value))) < 0.0000001


func _valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 32: return false
	var regex := RegEx.new()
	if regex.compile("^[A-Za-z0-9_-]+$") != OK: return false
	return regex.search(slot) != null


func _slot_path(slot: String) -> String:
	return SAVE_DIRECTORY + "/" + slot + ".json"


func _profile_path(slot: String) -> String:
	return PROFILE_DIRECTORY + "/" + slot + ".json"


func _tutorial_path(slot: String) -> String:
	return TUTORIAL_DIRECTORY + "/" + slot + ".json"


func _error(message: String) -> Dictionary:
	return {"error":message}
