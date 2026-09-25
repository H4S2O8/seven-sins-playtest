class_name SinTutorialRunner
extends RefCounted

const STEPS_PATH := "res://tutorial/tutorial_steps.json"
const STATE_SCHEMA := 1

var definition: Dictionary = {}
var step_index := -1
var started := false
var completed := false
var explained_terms: Dictionary = {}
var observed_gates: Dictionary = {}
var tutorial_wallet := {"player":100,"opponent":100,"pot":0}
var fixture_wallet_resets := 0
var load_error := ""


func begin() -> Dictionary:
	var loaded := _load_definition()
	if not str(loaded.get("error", "")).is_empty():
		load_error = str(loaded.error)
		return loaded
	definition = loaded.definition
	var validation := _validate_definition()
	if not str(validation.get("error", "")).is_empty():
		load_error = str(validation.error)
		return validation
	step_index = 0
	started = true
	completed = false
	explained_terms.clear()
	observed_gates.clear()
	tutorial_wallet = {"player":100,"opponent":100,"pot":0}
	fixture_wallet_resets = 0
	_enter_step()
	return {"error":"","accepted":true,"current_step":current_step()}


func current_step() -> Dictionary:
	if not started or completed or step_index < 0 or step_index >= definition.get("steps", []).size(): return {}
	return definition.steps[step_index].duplicate(true)


func explain(term_id: String) -> Dictionary:
	if not started or completed: return _error("tutorial_not_active")
	var current := current_step()
	if term_id not in current.get("terms_before_action", []): return _error("term_not_required_on_current_step")
	if not definition.get("glossary", {}).has(term_id): return _error("tutorial_glossary_term_missing")
	explained_terms[term_id] = true
	return {"error":"","accepted":true,"term":definition.glossary[term_id].duplicate(true)}


## Only domain/interaction events can satisfy gates. Calling next_step never advances progress.
func observe(event: Dictionary) -> Dictionary:
	if not started or completed: return _error("tutorial_not_active")
	var missing := _missing_terms()
	if not missing.is_empty(): return _error("explain_terms_before_action:" + ",".join(missing))
	var current := current_step()
	var matched := false
	for gate in current.get("required_events", []):
		var gate_id := str(gate.get("id", ""))
		if observed_gates.has(gate_id): continue
		if _event_matches(event, gate):
			observed_gates[gate_id] = true
			matched = true
			break
	if not matched: return {"error":"","accepted":true,"advanced":false,"current_step_id":str(current.id)}
	if _all_gates_observed(current):
		var completed_id := str(current.id)
		step_index += 1
		explained_terms.clear()
		observed_gates.clear()
		if step_index >= definition.steps.size():
			completed = true
			return {"error":"","accepted":true,"advanced":true,"completed_step":completed_id,"finished":true}
		_enter_step()
		return {"error":"","accepted":true,"advanced":true,"completed_step":completed_id,"finished":false,"current_step":current_step()}
	return {"error":"","accepted":true,"advanced":false,"current_step_id":str(current.id)}


func next_step() -> Dictionary:
	return _error("tutorial_progress_requires_real_events")


func snapshot() -> Dictionary:
	return {"schema_version":STATE_SCHEMA,"step_index":step_index,"started":started,"completed":completed,
		"explained_terms":explained_terms.keys(),"observed_gates":observed_gates.duplicate(true),
		"tutorial_wallet":tutorial_wallet.duplicate(true),"fixture_wallet_resets":fixture_wallet_resets}


func restore_snapshot(data: Dictionary) -> bool:
	var candidate_definition := definition
	if candidate_definition.is_empty():
		var loaded := _load_definition()
		if not str(loaded.get("error", "")).is_empty(): return false
		candidate_definition = loaded.definition
		if not _definition_validation_error(candidate_definition).is_empty(): return false
	if not data.get("schema_version", null) is int or int(data.schema_version) != STATE_SCHEMA: return false
	var index: Variant = data.get("step_index", null)
	if not index is int or index < -1 or index > candidate_definition.steps.size(): return false
	var saved_started: Variant = data.get("started", null)
	var saved_completed: Variant = data.get("completed", null)
	if not saved_started is bool or not saved_completed is bool: return false
	var saved_wallet: Variant = data.get("tutorial_wallet", null)
	if not saved_wallet is Dictionary or saved_wallet.keys().size() != 3: return false
	for account in ["player", "opponent", "pot"]:
		if not saved_wallet.get(account, null) is int or saved_wallet[account] < 0: return false
	var known_terms: Dictionary = candidate_definition.glossary
	var saved_terms: Variant = data.get("explained_terms", null)
	var saved_gates: Variant = data.get("observed_gates", null)
	if not saved_terms is Array or not saved_gates is Dictionary: return false
	var saved_resets: Variant = data.get("fixture_wallet_resets", null)
	if not saved_resets is int or saved_resets < 0 or saved_resets > 5: return false
	if saved_completed != (saved_started and index == candidate_definition.steps.size()): return false
	if not saved_started and (index != -1 or saved_completed): return false
	var current_terms: Array = []
	var valid_gate_ids: Dictionary = {}
	if saved_started and not saved_completed:
		current_terms = candidate_definition.steps[index].get("terms_before_action", [])
		for gate in candidate_definition.steps[index].get("required_events", []): valid_gate_ids[str(gate.id)] = true
	var validated_terms: Dictionary = {}
	for term in saved_terms:
		if not term is String or not known_terms.has(term) or term not in current_terms or validated_terms.has(term): return false
		validated_terms[term] = true
	for gate_id in saved_gates:
		if not gate_id is String or not valid_gate_ids.has(gate_id) or not saved_gates[gate_id] is bool or not saved_gates[gate_id]: return false
	if (not saved_started or saved_completed) and (not saved_terms.is_empty() or not saved_gates.is_empty()): return false
	# Commit only after the entire snapshot has passed validation.
	definition = candidate_definition
	step_index = int(index)
	started = saved_started
	completed = saved_completed
	explained_terms = validated_terms
	observed_gates = saved_gates.duplicate(true)
	tutorial_wallet = saved_wallet.duplicate(true)
	fixture_wallet_resets = int(saved_resets)
	return true


func _load_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STEPS_PATH))
	if not parsed is Dictionary: return _error("tutorial_data_invalid")
	var validation_error := _definition_validation_error(parsed)
	if not validation_error.is_empty(): return _error(validation_error)
	return {"error":"","definition":parsed}


func _validate_definition() -> Dictionary:
	var validation_error := _definition_validation_error(definition)
	return _error(validation_error) if not validation_error.is_empty() else {"error":""}


func _definition_validation_error(candidate: Dictionary) -> String:
	if int(candidate.get("schema_version", -1)) != 1: return "tutorial_schema_unsupported"
	if int(candidate.get("step_count", -1)) != 35 or not candidate.get("steps", null) is Array or candidate.steps.size() != 35:
		return "tutorial_must_define_35_steps"
	if not candidate.get("glossary", null) is Dictionary: return "tutorial_glossary_missing"
	var seen: Dictionary = {}
	for index in range(candidate.steps.size()):
		var step: Variant = candidate.steps[index]
		if not step is Dictionary or str(step.get("id", "")) != "T%02d" % (index + 1) or seen.has(step.get("id", "")):
			return "tutorial_step_ids_invalid_at:%d" % (index + 1)
		seen[str(step.id)] = true
		if not step.get("terms_before_action", null) is Array or not step.get("required_events", null) is Array or step.required_events.is_empty():
			return "tutorial_step_missing_terms_or_event_gate:" + str(step.id)
		for term in step.terms_before_action:
			if not candidate.glossary.has(str(term)): return "tutorial_term_undefined:" + str(term)
		for gate in step.required_events:
			if not gate is Dictionary or str(gate.get("id", "")).is_empty() or str(gate.get("kind", "")).is_empty():
				return "tutorial_event_gate_invalid:" + str(step.id)
	return ""


func _enter_step() -> void:
	var current := current_step()
	if bool(current.get("reset_fixture_wallet_before", false)):
		tutorial_wallet = {"player":100,"opponent":100,"pot":0}
		fixture_wallet_resets += 1


func _missing_terms() -> Array[String]:
	var missing: Array[String] = []
	for term in current_step().get("terms_before_action", []):
		if not explained_terms.has(str(term)): missing.append(str(term))
	return missing


func _all_gates_observed(current: Dictionary) -> bool:
	for gate in current.get("required_events", []):
		if not observed_gates.has(str(gate.get("id", ""))): return false
	return true


func _event_matches(event: Dictionary, gate: Dictionary) -> bool:
	if str(event.get("kind", "")) != str(gate.get("kind", "")): return false
	var expected: Dictionary = gate.get("equals", {})
	for path in expected:
		var actual: Variant = _path_value(event, str(path))
		if actual != expected[path]: return false
	return true


func _path_value(data: Dictionary, path: String) -> Variant:
	var cursor: Variant = data
	for part in path.split("."):
		if not cursor is Dictionary or not cursor.has(part): return null
		cursor = cursor[part]
	return cursor


func _error(message: String) -> Dictionary:
	return {"error":message,"accepted":false}
