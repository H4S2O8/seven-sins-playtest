extends SceneTree

const Bindings = preload("res://content/environment/environment_bindings.gd")
const Handlers = preload("res://content/environment/environment_handlers.gd")
const DATA_PATH := "res://content/environment/environment.json"
const REQUIREMENTS_PATH := "res://content/environment/handler-requirements.json"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var definitions := _read_object(DATA_PATH)
	var requirements := _read_object(REQUIREMENTS_PATH)
	_expect(definitions.get("schema_version") == 1, "definition schema version")
	var definition_counts: Dictionary = definitions.get("counts", {})
	_expect(int(definition_counts.get("AR", -1)) == 20 and int(definition_counts.get("PE", -1)) == 50, "definition counts")
	_expect(requirements.get("schema_version") == 1, "requirements schema version")
	_expect(requirements.get("formal_pool_blocked") == true, "unverified handlers are excluded from formal pool")
	_expect(str(Bindings.build(null).get("error", "")) == "environment_handler_missing", "binding factory rejects missing handler")
	_expect(str(Bindings.build(RefCounted.new()).get("error", "")) == "environment_handler_contract_missing", "binding factory rejects unknown handler contract")
	var handler_instance = Handlers.new()
	_expect(handler_instance.supports_content_id("AR01") and handler_instance.supports_content_id("AR02") and handler_instance.supports_content_id("AR03") and handler_instance.supports_content_id("AR04") and handler_instance.supports_content_id("AR05") and handler_instance.supports_content_id("AR06") and handler_instance.supports_content_id("AR07") and handler_instance.supports_content_id("AR08") and handler_instance.supports_content_id("AR09") and handler_instance.supports_content_id("AR10") and handler_instance.supports_content_id("AR11") and handler_instance.supports_content_id("AR13") and handler_instance.supports_content_id("AR14") and handler_instance.supports_content_id("AR15") and handler_instance.supports_content_id("AR16") and handler_instance.supports_content_id("AR17") and handler_instance.supports_content_id("AR19") and handler_instance.supports_content_id("AR20") and handler_instance.supports_content_id("PE05") and handler_instance.supports_content_id("PE09") and handler_instance.supports_content_id("PE10") and handler_instance.supports_content_id("PE12") and handler_instance.supports_content_id("PE17") and handler_instance.supports_content_id("PE18") and handler_instance.supports_content_id("PE21") and handler_instance.supports_content_id("PE22") and handler_instance.supports_content_id("PE23") and handler_instance.supports_content_id("PE26") and handler_instance.supports_content_id("PE30") and handler_instance.supports_content_id("PE31") and handler_instance.supports_content_id("PE32") and handler_instance.supports_content_id("PE35") and handler_instance.supports_content_id("PE36") and handler_instance.supports_content_id("PE38") and handler_instance.supports_content_id("PE39") and handler_instance.supports_content_id("PE46") and handler_instance.supports_content_id("PE47") and handler_instance.supports_content_id("PE48") and handler_instance.supports_content_id("PE50"), "implemented environment handler IDs")
	_expect(not handler_instance.supports_content_id("AR12") and not handler_instance.supports_content_id("PE01"), "unknown environment handlers rejected")
	_expect(str(Bindings.build(handler_instance).get("error", "")) == "environment_formal_pool_blocked", "partial environment handlers cannot enter formal pool")
	var entries: Array = definitions.get("entries", [])
	var bindings: Array = requirements.get("bindings", [])
	_expect(entries.size() == 70, "exactly 70 source definitions")
	_expect(bindings.size() == 70, "exactly 70 explicit handler requirement rows")
	var expected_ids: Array[String] = []
	for index in range(1, 21): expected_ids.append("AR%02d" % index)
	for index in range(1, 51): expected_ids.append("PE%02d" % index)
	var seen: Dictionary = {}
	for index in range(mini(entries.size(), expected_ids.size())):
		var entry: Dictionary = entries[index]
		var expected_id := expected_ids[index]
		checks += 1
		if str(entry.get("id", "")) != expected_id: _fail("definition order/id at index %d" % index)
		_expect(not seen.has(expected_id), "%s unique" % expected_id)
		seen[expected_id] = true
		_expect(str(entry.get("category", "")) == expected_id.left(2), "%s category" % expected_id)
		_expect(str(entry.get("source", "")) == "04-场地与公共效果.md", "%s source attribution" % expected_id)
		_expect(str(entry.get("source_text", "")).begins_with("### %s｜" % expected_id), "%s preserves complete original text" % expected_id)
		var source_fields: Dictionary = entry.get("source_fields", {})
		_expect(str(source_fields.get("rule_text", "")) != "", "%s original mechanism/effect field" % expected_id)
		_expect(str(source_fields.get("compatibility_text", "")) != "", "%s original compatibility field" % expected_id)
		_expect(str(source_fields.get("presentation_text", "")) != "", "%s original presentation field" % expected_id)
		_expect(str(source_fields.get("rule_label", "")) == ("机制" if expected_id.begins_with("AR") else "效果"), "%s original field label" % expected_id)
	for index in range(mini(bindings.size(), expected_ids.size())):
		var binding: Dictionary = bindings[index]
		var expected_id := expected_ids[index]
		_expect(str(binding.get("content_id", "")) == expected_id, "%s requirement binding" % expected_id)
		_expect(str(binding.get("logic_handler", "")) == "environment_%s" % expected_id, "%s explicit handler identity" % expected_id)
		_expect(str(binding.get("required_source_key", "")) == "global:%s" % expected_id, "%s isolated binding source" % expected_id)
		_expect(str(binding.get("required_owner_key", "not-empty")) == "", "%s global binding owner" % expected_id)
		_expect(not (binding.get("subscribes", []) as Array).is_empty(), "%s event subscription" % expected_id)
		_expect(not (binding.get("required_engine_capabilities", []) as Array).is_empty(), "%s primitive requirements" % expected_id)
		var implemented := expected_id in ["AR01", "AR02", "AR03", "AR04", "AR05", "AR06", "AR07", "AR08", "AR09", "AR10", "AR11", "AR13", "AR14", "AR15", "AR16", "AR17", "AR19", "AR20", "PE05", "PE09", "PE10", "PE12", "PE17", "PE18", "PE21", "PE22", "PE23", "PE26", "PE30", "PE31", "PE32", "PE35", "PE36", "PE38", "PE39", "PE46", "PE47", "PE48", "PE50"]
		_expect(str(binding.get("implementation_status", "")) == ("implemented" if implemented else "not_implemented"), "%s implementation status matches checked handlers" % expected_id)
	if failures.is_empty():
		print("PASS: %d environment data assertions; exact AR01-AR20/PE01-PE50 source fields and explicit handler requirements" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		printerr("FAIL: %d environment data assertion(s) failed across %d checks" % [failures.size(), checks])
		quit(1)


func _read_object(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		_fail("missing %s" % file_path)
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if not value is Dictionary:
		_fail("invalid JSON object %s" % file_path)
		return {}
	return value


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition: _fail(label)


func _fail(message: String) -> void:
	if failures.size() < 30: failures.append(message)
