extends SceneTree

const EngineScript = preload("res://core/battle/battle_engine.gd")
const ENHandler = preload("res://content/characters/en_handlers.gd")
const SLHandler = preload("res://content/characters/sl_handlers.gd")
const LUHandler = preload("res://content/characters/lu_handlers.gd")
const PRHandler = preload("res://content/characters/pr_handlers.gd")

class FixtureEffect extends RefCounted:
	var event_kind := ""
	var event_tick := -1
	var actions: Array = []
	func on_event(_engine: BattleEngine, _binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != event_kind: return []
		if event_tick >= 0 and int(event.get("tick", -1)) != event_tick: return []
		return actions.duplicate(true)

var cards: Dictionary = {}
var failures: Array[String] = []
var checks := 0
var scenarios := 0
var event_logs: Dictionary = {}

func _initialize() -> void:
	var engine_script: Script = load("res://core/battle/battle_engine.gd")
	var family_scripts: Array[Script] = [load("res://content/characters/en_handlers.gd"), load("res://content/characters/sl_handlers.gd"),
		load("res://content/characters/lu_handlers.gd"), load("res://content/characters/pr_handlers.gd")]
	var scripts_ready := engine_script.can_instantiate()
	for family_script in family_scripts: scripts_ready = scripts_ready and family_script.can_instantiate()
	if not scripts_ready:
		push_error("family integration fixture aborted: BattleEngine or family handler failed to compile")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/characters.json"))
	if parsed is Dictionary:
		for card in parsed.get("characters", []): cards[str(card.id)] = card
	else:
		failures.append("character catalog failed to load")
	_check_family(ENHandler, 13, ["EN02"])
	_check_family(SLHandler, 11, ["SL03", "SL09", "SL14"])
	_check_family(LUHandler, 9, ["LU01", "LU02", "LU05", "LU07", "LU14"])
	_check_family(PRHandler, 12, ["PR07", "PR11"])
	_test_en13()
	_test_sl13()
	_test_lu13()
	_test_pr06()
	if failures.is_empty():
		print("CHARACTER_FAMILY_ENGINE_SMOKE_OK checks=%d real_engine_scenarios=%d implemented=45 verified_ids=0 integration_blocked=12" % [checks, scenarios])
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check_family(script: Script, expected_count: int, blocked: Array) -> void:
	var handler = script.new()
	_assert(script.IMPLEMENTED_IDS.size() == expected_count, "%s implemented list exact count" % script.get_global_name())
	for content_id: String in script.IMPLEMENTED_IDS:
		_assert(handler.supports_content_id(content_id), "%s supports %s" % [script.get_global_name(), content_id])
	_assert(script.INTEGRATED_IDS.is_empty(), "%s does not overstate integration acceptance" % script.get_global_name())
	for content_id in blocked:
		_assert(not handler.supports_content_id(str(content_id)), "%s rejects unsupported %s" % [script.get_global_name(), content_id])

func _test_en13() -> void:
	var yes := _fixture("EN13", {"A1":{"target_slot":2}, "B2":{"H":130}}, null)
	_run_to(yes.engine, 40, "EN13 locked highest-H target positive")
	_assert(bool(yes.engine.unit("A1").barrier.active), "EN13 grants barrier when current arrow still points to locked highest-H target")
	_scenario()
	var no := _fixture("EN13", {"A1":{"target_slot":1}, "B2":{"H":130}}, null)
	_run_to(no.engine, 40, "EN13 arrow mismatch negative")
	_assert(not bool(no.engine.unit("A1").barrier.active), "EN13 does not grant barrier when arrow points away from locked target")
	_scenario()

func _test_sl13() -> void:
	var pair := _fixture("SL13", {"A1":{"hp_tenths":900,"T_ticks":1000}}, null)
	_run_to(pair.engine, 120, "SL13 first timed shield")
	_assert(pair.engine.shield_amount("A1") == 60 and pair.engine.shield_amount("A2") == 60 and pair.engine.shield_amount("A3") == 60,
		"SL13 grants six shield to every living ally at tick120")
	_run_to(pair.engine, 179, "SL13 shield remains before expiry")
	_assert(pair.engine.shield_amount("A2") == 60, "SL13 shield is active through tick179")
	_run_to(pair.engine, 180, "SL13 expiry and second timed effect")
	_assert(pair.engine.shield_amount("A2") == 0 and int(pair.engine.unit("A1").hp_tenths) == 950,
		"SL13 shield expires at tick180, then the separate five-health team heal resolves")
	_scenario()

func _test_lu13() -> void:
	var pair := _fixture("LU13", {"A1":{"target_slot":1,"T_ticks":1000}, "B1":{"target_slot":1,"T_ticks":1000}, "A2":{"hp_tenths":500}}, null)
	_run_to(pair.engine, 40, "LU13 mutual-arrow bond and periodic grant")
	_assert(pair.engine.get_counter(pair.binding.source_key, "bonded") == 1 and pair.engine.shield_amount("A2") == 50,
		"LU13 creates the mutual-arrow bond and grants five shield to the lowest-ratio other ally at tick40")
	_scenario()
	var no := _fixture("LU13", {"A1":{"target_slot":1,"T_ticks":1000}, "B1":{"target_slot":2,"T_ticks":1000}}, null)
	_run_to(no.engine, 40, "LU13 no mutual-arrow negative")
	_assert(no.engine.get_counter(no.binding.source_key, "bonded") == 0 and no.engine.shield_amount("A2") == 0,
		"LU13 does not establish a link or periodic grant without mutual arrows at battle start")
	_scenario()

func _test_pr06() -> void:
	var base := _fixture("", {"A1":{"A":int(cards["PR06"].A),"T_ticks":20}, "B1":{"R":0,"armor_kind":"light","T_ticks":1000}}, null)
	var active := _fixture("PR06", {"A1":{"T_ticks":20}, "B1":{"R":0,"armor_kind":"light","T_ticks":1000}}, null)
	_run_to(base.engine, 20, "PR06 unconditioned baseline")
	_run_to(active.engine, 20, "PR06 clean target positive")
	var base_loss := _owner_damage(base.engine, "A1", "B1")
	var active_loss := _owner_damage(active.engine, "A1", "B1")
	_assert(active_loss - base_loss == 70, "PR06 adds exactly seven physical damage to a clean target; baseline=%d active=%d" % [base_loss, active_loss])
	_scenario()
	var effect := FixtureEffect.new()
	effect.event_kind = "battle_start"
	effect.actions = [{"kind":"status_add", "target_key":"B1", "status_id":"poison", "layers":1, "expires_tick":100}]
	var dirty := _fixture("PR06", {"A1":{"T_ticks":20}, "B1":{"R":0,"armor_kind":"light","T_ticks":1000}}, effect)
	var dirty_base := _fixture("", {"A1":{"A":int(cards["PR06"].A),"T_ticks":20}, "B1":{"R":0,"armor_kind":"light","T_ticks":1000}}, effect)
	_run_to(dirty.engine, 20, "PR06 listed-status negative")
	_run_to(dirty_base.engine, 20, "PR06 listed-status baseline")
	_assert(_owner_damage(dirty.engine, "A1", "B1") == _owner_damage(dirty_base.engine, "A1", "B1"),
		"PR06 adds no segment while the target has a listed active status")
	_scenario()

func _fixture(content_id: String, overrides: Dictionary, fixture_effect) -> Dictionary:
	var definitions: Array = []
	var binding := {}
	if not content_id.is_empty():
		var handler = _handler_for(content_id).new()
		binding = {"content_id":content_id, "logic_handler":"character_" + content_id, "owner_key":"A1",
			"source_key":"A1:" + content_id, "kind":"talent"}
		definitions.append({"logic_handler":binding.logic_handler, "handler":handler, "bindings":[binding]})
	if fixture_effect != null:
		definitions.append({"logic_handler":"fixture_effect", "handler":fixture_effect,
			"bindings":[{"content_id":"FIXTURE_EFFECT", "logic_handler":"fixture_effect", "owner_key":"A1", "source_key":"fixture:family", "kind":"talent"}]})
	var teams := {"A":[_unit("A",1,content_id),_unit("A",2),_unit("A",3)], "B":[_unit("B",1),_unit("B",2),_unit("B",3)]}
	for side in ["A", "B"]:
		for index in range(3):
			var state: Dictionary = teams[side][index]
			var key := "%s%d" % [side,int(state.slot)]
			if overrides.has(key): state.merge(overrides[key],true)
	var engine = EngineScript.new()
	var result: Dictionary = engine.setup({"seed":17,"rule_id":"VC01","test_fixture":true,"teams":teams},definitions,{"capture_tick_hashes":false})
	if not str(result.get("error","")).is_empty(): failures.append("fixture %s setup: %s" % [content_id,result.error])
	return {"engine":engine,"binding":binding}

func _handler_for(content_id: String) -> Script:
	if content_id.begins_with("EN"): return ENHandler
	if content_id.begins_with("SL"): return SLHandler
	if content_id.begins_with("LU"): return LUHandler
	return PRHandler

func _unit(side: String, slot: int, character_id := "") -> Dictionary:
	var is_owner := side == "A" and slot == 1 and not character_id.is_empty()
	var card: Dictionary = cards.get(character_id,{}) if is_owner else {}
	return {"definition_id":character_id if is_owner else "FIXTURE_%s%d" % [side,slot],
		"talent_id":character_id if is_owner else "", "fixture":not is_owner, "slot":slot,
		"H":int(card.get("H",100)),"A":int(card.get("A",0)),"T_ticks":int(card.get("T_ticks",1000)),
		"R":int(card.get("R",0)),"reach":str(card.get("reach","ranged")),"armor_kind":str(card.get("armor_kind","light")),
		"target_slot":1,"first_attack_tick":1000 if not is_owner else 0}

func _run_to(engine: BattleEngine, final_tick: int, label: String) -> void:
	if not event_logs.has(engine.get_instance_id()): event_logs[engine.get_instance_id()] = []
	while int(engine.snapshot().get("tick",0)) <= final_tick:
		var result: Dictionary = engine.step(false)
		event_logs[engine.get_instance_id()].append_array(result.get("events", []))
		if not str(result.get("error","")).is_empty():
			failures.append("%s: %s" % [label,result.error])
			return

func _owner_damage(engine: BattleEngine, source_key: String, target_key: String) -> int:
	var total := 0
	for event in event_logs.get(engine.get_instance_id(), []):
		if str(event.get("kind","")) == "hp_lost" and str(event.get("source_key","")) == source_key and str(event.get("target_key","")) == target_key:
			total += int(event.get("actual_hp_loss",0))
	return total

func _scenario() -> void:
	scenarios += 1

func _assert(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
