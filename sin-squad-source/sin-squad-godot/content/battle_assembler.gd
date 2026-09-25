class_name SinBattleAssembler
extends RefCounted

## The only bridge from a committed hand to battle data. This file never derives
## abilities from prose, mutates Session, or silently replaces missing handlers.
## integration_review is for local integration tests only, not release admission.
const AttachmentCatalogScript = preload("res://content/attachments/attachment_catalog.gd")
const AttachmentHandlersScript = preload("res://content/attachments/attachment_handlers.gd")
const EnvironmentHandlersScript = preload("res://content/environment/environment_handlers.gd")
const BattleScript = preload("res://core/battle/battle_engine.gd")
const FAMILIES := ["WR", "GR", "GL", "EN", "SL", "LU", "PR"]

var characters: Dictionary = {}
var attachments: Dictionary = {}
var environments: Dictionary = {}
var requirements: Dictionary = {}
var manifests: Array = []
var load_error := ""

func _init() -> void:
	_load_catalog("res://content/characters/characters.json", "characters", 98, characters)
	_load_catalog("res://content/attachments/attachments.json", "attachments", 100, attachments)
	_load_catalog("res://content/environment/environment.json", "entries", 70, environments)
	for family in ["characters", "attachments", "environment"]:
		var data := _read("res://content/%s/handler-requirements.json" % family)
		manifests.append(data)
		for row in data.get("bindings", []):
			if not row is Dictionary:
				load_error = "binding_row_not_dictionary"
				continue
			var content_id := str(row.get("content_id", ""))
			if content_id.is_empty() or requirements.has(content_id):
				load_error = "duplicate_or_empty_binding_id:" + content_id
				continue
			requirements[content_id] = row.duplicate(true)
	if requirements.size() != 268: load_error = "binding_inventory_incomplete:%d" % requirements.size()

func build_from_session(session_state: Dictionary, integration_review := false) -> Dictionary:
	if str(session_state.get("phase", "")) != "BATTLE_READY":
		return _error("hand_not_ready_for_battle")
	var private_data: Variant = session_state.get("private", {})
	if not private_data is Dictionary or not private_data.get("teams", null) is Dictionary:
		return _error("committed_teams_missing")
	return build({"seed":session_state.get("seed", 0), "rule_id":session_state.get("rule_id", ""),
		"arena_id":session_state.get("arena_id", ""), "public_effect_ids":session_state.get("revealed_effects", []),
		"teams":private_data.teams, "installed_cards":session_state.get("installed_cards", {}),
		"arrows":session_state.get("arrows", {})}, integration_review)

func build(request: Dictionary, integration_review := false) -> Dictionary:
	if not load_error.is_empty(): return _error(load_error)
	# Formal play is admitted per requested content, not by the completion state of
	# the entire 268-item catalogue. _add_binding still refuses every item whose
	# real handler does not explicitly advertise support.
	var rule_id := str(request.get("rule_id", ""))
	var rule_ids: Array = []
	for n in range(1, 31): rule_ids.append("VC%02d" % n)
	if rule_id not in rule_ids: return _error("unknown_victory_rule:" + rule_id)
	if not request.get("seed", null) is int: return _error("seed_must_be_integer")
	var teams: Variant = request.get("teams", null)
	var installs: Variant = request.get("installed_cards", {})
	var arrows: Variant = request.get("arrows", {})
	if not teams is Dictionary or not installs is Dictionary or not arrows is Dictionary:
		return _error("team_configuration_invalid")
	var compiled_teams := {"A":[], "B":[]}
	var handlers: Dictionary = {}
	var used_ids: Dictionary = {}
	for side in ["player", "opponent"]:
		var engine_side := "A" if side == "player" else "B"
		var team: Variant = teams.get(side, null)
		var installed: Variant = installs.get(side, [])
		var target_arrows: Variant = arrows.get(side, [1,2,3])
		if not team is Array or team.size() != 3: return _error("team_requires_three_slots:" + side)
		if not installed is Array or installed.size() not in [0,6]: return _error("attachments_require_six_slots:" + side)
		if not target_arrows is Array or target_arrows.size() != 3: return _error("arrows_require_three_slots:" + side)
		var seen: Dictionary = {}
		for index in range(3):
			if not team[index] is Dictionary or int(team[index].get("slot", -1)) != index + 1:
				return _error("team_slot_order_invalid:" + side)
			var id := str(team[index].get("definition_id", ""))
			if not characters.has(id): return _error("unknown_character:" + id)
			if seen.has(id): return _error("duplicate_character_in_team:" + id)
			seen[id] = true
			if not target_arrows[index] is int or target_arrows[index] < 1 or target_arrows[index] > 3:
				return _error("target_slot_invalid:" + side)
			var unit: Dictionary = characters[id].duplicate(true)
			unit["definition_id"] = id
			unit["talent_id"] = id
			unit["slot"] = index + 1
			unit["target_slot"] = int(target_arrows[index])
			var owner_key := "%s%d" % [engine_side,index+1]
			var added := _add_binding(id, owner_key, "talent", handlers)
			if not added.is_empty(): return _error(added)
			used_ids[id] = true
			for category_index in range(2):
				var card_id := "" if installed.is_empty() else str(installed[index + category_index * 3])
				if card_id.is_empty(): continue
				var prefix := "EQ" if category_index == 0 else "FX"
				if not attachments.has(card_id) or not card_id.begins_with(prefix):
					return _error("attachment_wrong_slot_or_unknown:" + card_id)
				unit["equipment_id" if category_index == 0 else "slot_effect_id"] = card_id
				var prepared: Dictionary = AttachmentCatalogScript.apply_setup_modifiers(unit, card_id)
				if not bool(prepared.get("accepted", false)): return _error(str(prepared.get("reason", "setup_modifier_failed")))
				unit = prepared.unit
				added = _add_binding(card_id, owner_key, "equipment" if category_index == 0 else "slot", handlers)
				if not added.is_empty(): return _error(added)
				used_ids[card_id] = true
			compiled_teams[engine_side].append(unit)
	var arena_id := str(request.get("arena_id", ""))
	if not environments.has(arena_id) or not arena_id.begins_with("AR"): return _error("unknown_arena:" + arena_id)
	var public_effects: Variant = request.get("public_effect_ids", [])
	if not public_effects is Array or public_effects.size() > 3: return _error("invalid_public_effects")
	var seen_public: Dictionary = {}
	var environment_ids: Array = [arena_id]
	for id_variant in public_effects:
		var id := str(id_variant)
		if not id.begins_with("PE") or not environments.has(id) or seen_public.has(id): return _error("invalid_or_duplicate_public_effect:" + id)
		seen_public[id] = true
		environment_ids.append(id)
	for id in environment_ids:
		var added := _add_binding(id, "", "arena" if str(id).begins_with("AR") else "public", handlers)
		if not added.is_empty(): return _error(added)
		used_ids[id] = true
	var handler_keys: Array = handlers.keys()
	handler_keys.sort()
	var handler_rows: Array = []
	for key in handler_keys: handler_rows.append(handlers[key])
	return {"error":"", "config":{"seed":int(request.seed), "rule_id":rule_id, "arena_id":arena_id,
		"public_effect_ids":public_effects.duplicate(), "teams":compiled_teams},
		"handlers":handler_rows, "content_ids":used_ids.keys(), "integration_review_only":integration_review}

func simulate(request: Dictionary, integration_review := false) -> Dictionary:
	var assembled := build(request, integration_review)
	if not str(assembled.get("error", "")).is_empty(): return assembled
	var engine = BattleScript.new()
	var result: Dictionary = engine.simulate(assembled.config, assembled.handlers)
	result["integration_review_only"] = integration_review
	return result

func _add_binding(id: String, owner_key: String, kind: String, result: Dictionary) -> String:
	if not requirements.has(id): return "missing_binding_contract:" + id
	var row: Dictionary = requirements[id]
	var logic_id := str(row.get("logic_handler", ""))
	if logic_id.is_empty(): return "missing_handler_id:" + id
	if not result.has(logic_id):
		var handler: Variant
		if kind == "talent":
			var prefix := id.left(2)
			if prefix not in FAMILIES: return "unknown_character_family:" + id
			var script_path := "res://content/characters/%s_handlers.gd" % prefix.to_lower()
			if not ResourceLoader.exists(script_path): return "unimplemented_character_family:" + prefix
			var script: Script = load(script_path)
			if script == null or not script.can_instantiate(): return "invalid_character_handler:" + prefix
			handler = script.new()
		elif kind in ["equipment", "slot"]: handler = AttachmentHandlersScript.new()
		else: handler = EnvironmentHandlersScript.new()
		if not handler.has_method("supports_content_id") or not bool(handler.supports_content_id(id)):
			return "unimplemented_content_handler:" + id
		result[logic_id] = {"logic_handler":logic_id, "handler":handler, "bindings":[]}
	var binding := {"content_id":id, "logic_handler":logic_id, "owner_key":owner_key,
		"source_key":("global:" if owner_key.is_empty() else owner_key + ":") + id, "kind":kind}
	for field in ["subscribes", "trigger_scope", "phase"]:
		if row.has(field): binding[field] = row[field]
	result[logic_id].bindings.append(binding)
	return ""

func _load_catalog(path: String, array_key: String, expected: int, target: Dictionary) -> void:
	var data := _read(path)
	for row in data.get(array_key, []):
		if not row is Dictionary:
			load_error = "invalid_catalog_row:" + path
			continue
		var id := str(row.get("id", ""))
		if id.is_empty() or target.has(id):
			load_error = "invalid_catalog_id:" + path
			continue
		target[id] = row.duplicate(true)
	if target.size() != expected: load_error = "catalog_count_mismatch:" + path

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		load_error = "missing_content_file:" + path
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		load_error = "invalid_content_json:" + path
		return {}
	return parsed

func _error(reason: String) -> Dictionary:
	return {"error":reason, "config":{}, "handlers":[], "content_ids":[]}
