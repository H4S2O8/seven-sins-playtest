extends RefCounted
class_name EnvironmentHandlerBindings

const DEFINITIONS_PATH := "res://content/environment/environment.json"
const REQUIREMENTS_PATH := "res://content/environment/handler-requirements.json"
const EXPECTED_COUNT := 70


static func build(handler_instance: Variant) -> Dictionary:
	if handler_instance == null or not handler_instance is Object:
		return {"error":"environment_handler_missing","handlers":[]}
	if not handler_instance.has_method("on_event") or not handler_instance.has_method("supports_content_id"):
		return {"error":"environment_handler_contract_missing","handlers":[]}
	var definitions := _read_object(DEFINITIONS_PATH)
	var manifest := _read_object(REQUIREMENTS_PATH)
	if definitions.is_empty() or manifest.is_empty():
		return {"error":"environment_data_invalid_or_missing","handlers":[]}
	if bool(manifest.get("formal_pool_blocked", true)):
		return {"error":"environment_formal_pool_blocked","handlers":[]}
	var entries: Array = definitions.get("entries", [])
	var rows: Array = manifest.get("bindings", [])
	if entries.size() != EXPECTED_COUNT or rows.size() != EXPECTED_COUNT:
		return {"error":"environment_content_count_mismatch","handlers":[]}
	var result: Array = []
	var seen: Dictionary = {}
	for index in range(EXPECTED_COUNT):
		if not entries[index] is Dictionary or not rows[index] is Dictionary:
			return {"error":"environment_entry_schema_invalid:%d" % index,"handlers":[]}
		var definition: Dictionary = entries[index]
		var row: Dictionary = rows[index]
		var content_id := str(definition.get("id", ""))
		if content_id != str(row.get("content_id", "")) or seen.has(content_id):
			return {"error":"environment_id_mismatch_or_duplicate:%s" % content_id,"handlers":[]}
		seen[content_id] = true
		if str(row.get("implementation_status", "")) != "implemented":
			return {"error":"environment_handler_not_implemented:%s" % content_id,"handlers":[]}
		if not bool(handler_instance.supports_content_id(content_id)):
			return {"error":"environment_handler_unknown:%s" % content_id,"handlers":[]}
		var logic_handler := str(row.get("logic_handler", ""))
		var source_key := str(row.get("required_source_key", ""))
		if logic_handler.is_empty() or source_key != "global:%s" % content_id:
			return {"error":"environment_binding_identity_invalid:%s" % content_id,"handlers":[]}
		var binding := {
			"content_id":content_id,
			"logic_handler":logic_handler,
			"source_key":source_key,
			"owner_key":"",
			"kind":str(row.get("required_binding_kind", "")),
			"subscribes":row.get("subscribes", []).duplicate()
		}
		result.append({"logic_handler":logic_handler,"handler":handler_instance,"bindings":[binding]})
	return {"error":"","handlers":result,"content_ids":seen.keys()}


static func _read_object(resource_path: String) -> Dictionary:
	if not FileAccess.file_exists(resource_path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(resource_path))
	return parsed if parsed is Dictionary else {}
