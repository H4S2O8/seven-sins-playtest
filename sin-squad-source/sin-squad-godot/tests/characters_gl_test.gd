extends SceneTree

const EngineScript = preload("res://core/battle/battle_engine.gd")
const HandlerScript = preload("res://content/characters/gl_handlers.gd")

class FixtureEffect extends RefCounted:
	var event_kind := ""
	var event_tick := -1
	var actions: Array = []
	func on_event(_engine: BattleEngine, _binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != event_kind: return []
		if event_tick >= 0 and int(event.get("tick", -1)) != event_tick: return []
		return actions.duplicate(true)

var cards: Dictionary = {}
var checks := 0
var failures: Array[String] = []
var scenarios := 0
var event_logs: Dictionary = {}


func _initialize() -> void:
	var engine_script: Script = load("res://core/battle/battle_engine.gd")
	var handler_script: Script = load("res://content/characters/gl_handlers.gd")
	if not engine_script.can_instantiate() or not handler_script.can_instantiate():
		push_error("GL integration fixture aborted: BattleEngine or handler failed to compile")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/characters.json"))
	if parsed is Dictionary:
		for card in parsed.get("characters", []): cards[str(card.id)] = card
	else:
		failures.append("character catalog failed to load")
	var handler = HandlerScript.new()
	_assert(HandlerScript.IMPLEMENTED_IDS.size() == 11, "GL explicitly exposes only eleven currently supported IDs")
	for content_id: String in HandlerScript.IMPLEMENTED_IDS:
		_assert(handler.supports_content_id(content_id), "GL support query accepts " + content_id)
	for blocked_id in ["GL03", "GL05", "GL08", "GL99", "WR01"]:
		_assert(not handler.supports_content_id(str(blocked_id)), "GL support query rejects blocked/foreign " + str(blocked_id))
	_assert(HandlerScript.INTEGRATED_IDS.is_empty(), "No GL ID is admitted before positive/negative/expiry matrix completion")
	_test_gl01()
	_test_gl02()
	_test_gl04()
	_test_gl06()
	_test_gl07()
	_test_gl09()
	_test_gl10()
	_test_gl11()
	_test_gl12()
	_test_gl13()
	_test_gl14()
	if failures.is_empty():
		print("GL_HANDLER_BATCH_OK checks=%d implemented=11 real_engine_scenarios=%d integration_blocked=3 verified=0" % [checks, scenarios])
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)


func _test_gl01() -> void:
	var effect := FixtureEffect.new()
	effect.event_kind = "battle_start"
	effect.actions = [
		{"kind":"status_add", "target_key":"A2", "status_id":"poison", "layers":3, "expires_tick":100},
		{"kind":"status_add", "target_key":"A3", "status_id":"poison", "layers":2, "expires_tick":100}]
	var pair := _fixture("GL01", {"A1":{"hp_tenths":900,"T_ticks":1000}}, effect)
	_run_to(pair.engine, 30, "GL01 poison cleanse/heal")
	_assert(_layers(pair.engine.unit("A2"), "poison") == 1 and _layers(pair.engine.unit("A3"), "poison") == 2,
		"GL01 real periodic tick clears up to two layers from highest-poison ally")
	_assert(int(pair.engine.unit("A1").hp_tenths) == 960, "GL01 real clear count restores 6 health")
	_scenario()


func _test_gl02() -> void:
	var effect := FixtureEffect.new()
	effect.event_kind = "battle_start"
	effect.actions = [{"kind":"shield_grant", "target_key":"A1", "amount":60, "expires_tick":100}]
	var pair := _fixture("GL02", {"A1":{"T_ticks":27}, "B1":{"R":0,"armor_kind":"light","T_ticks":1000}}, effect)
	_run_to(pair.engine, 27, "GL02 shield-to-hit conversion")
	_assert(pair.engine.shield_amount("A1") == 0, "GL02 consumes six points before natural hit")
	_assert(int(pair.engine.unit("B1").hp_tenths) == 790, "GL02 six-point shield spend adds nine physical damage to 12 base")
	_scenario()


func _test_gl04() -> void:
	var pair := _fixture("GL04", {"A1":{"hp_tenths":900,"T_ticks":20}, "B1":{"A":0,"T_ticks":1000}})
	_run_to(pair.engine, 40, "GL04 stomach bank/settlement")
	_assert(pair.engine.get_counter(pair.binding.source_key, "stomach") == 25, "GL04 tick40 first clears old 25-tenths bank, then tick40 natural hit starts a new 25 bank; stored=%d" % pair.engine.get_counter(pair.binding.source_key, "stomach"))
	_assert(int(pair.engine.unit("B1").hp_tenths) == 800 and int(pair.engine.unit("A1").hp_tenths) == 925,
		"GL04 tick40 actually heals the prior bank while both natural attacks cause 100 loss; A1=%d B1=%d" % [int(pair.engine.unit("A1").hp_tenths),int(pair.engine.unit("B1").hp_tenths)])
	_scenario()


func _test_gl06() -> void:
	var effect := FixtureEffect.new()
	effect.event_kind = "periodic"
	effect.event_tick = 1
	effect.actions = [{"kind":"damage", "target_key":"A1", "amount":300, "damage_type":"fixed"}]
	var pair := _fixture("GL06", {"A1":{"hp_tenths":500,"T_ticks":1000}, "B1":{"A":0,"T_ticks":1000}}, effect)
	_run_to(pair.engine, 1, "GL06 one loss crossing all ration thresholds")
	_assert(pair.engine.get_counter(pair.binding.source_key, "unlocked") == 3 and pair.engine.get_counter(pair.binding.source_key, "fed") == 1,
		"GL06 one actual loss crossing 75/50/25 unlocks all three but consumes only one ration; unlocked=%d fed=%d" % [pair.engine.get_counter(pair.binding.source_key, "unlocked"),pair.engine.get_counter(pair.binding.source_key, "fed")])
	_assert(int(pair.engine.unit("A1").hp_tenths) == 280,
		"GL06 nonlethal loss to 200 is followed by exactly 80 healing, hp=%d" % int(pair.engine.unit("A1").hp_tenths))
	_scenario()


func _test_gl07() -> void:
	var effect := FixtureEffect.new()
	effect.event_kind = "periodic"
	effect.event_tick = 1
	effect.actions = [{"kind":"heal", "target_key":"A1", "amount":40}]
	var pair := _fixture("GL07", {"A1":{"hp_tenths":900,"T_ticks":1000}, "A2":{"hp_tenths":700}, "A3":{"hp_tenths":600}}, effect)
	_run_to(pair.engine, 1, "GL07 effective-heal sharing")
	_assert(int(pair.engine.unit("A1").hp_tenths) == 940 and int(pair.engine.unit("A3").hp_tenths) == 616,
		"GL07 shares 40%% of actual 4-point healing to the lowest-ratio other ally")
	_scenario()


func _test_gl09() -> void:
	var pair := _fixture("GL09", {"A1":{"hp_tenths":1200,"T_ticks":1000}, "B1":{"A":10,"damage_type":"lightning","T_ticks":20,"target_slot":1}})
	_run_to(pair.engine, 50, "GL09 non-overlapping five-second loss window")
	var counted := 0
	for event in _events_for(pair.engine):
		if str(event.get("kind", "")) == "hp_lost" and str(event.get("target_key", "")) == "A1" and str(event.get("source_key", "")) == "B1": counted += int(event.get("actual_hp_loss", 0))
	_assert(counted > 0 and int(pair.engine.unit("A1").hp_tenths) > 1200 - counted,
		"GL09 actual enemy-sourced loss from the prior five seconds is partially restored at tick50")
	_scenario()


func _test_gl10() -> void:
	var pair := _fixture("GL10", {"A1":{"T_ticks":25}, "B1":{"R":0,"armor_kind":"light","T_ticks":1000}})
	_run_to(pair.engine, 25, "GL10 segmented 45-percent attack")
	var natural_segments := 0
	var total_loss := 0
	for event in _events_for(pair.engine):
		if str(event.get("kind", "")) == "hp_lost" and str(event.get("source_key", "")) == "A1" and str(event.get("target_key", "")) == "B1" and bool(event.get("is_natural_attack", false)):
			natural_segments += 1
			total_loss += int(event.get("actual_hp_loss", 0))
	_assert(natural_segments == 3 and total_loss == 162 and int(pair.engine.unit("B1").hp_tenths) == 838,
		"GL10 real attack resolves as three separate 45%% segments through damage engine; segments=%d loss=%d" % [natural_segments,total_loss])
	_scenario()


func _test_gl11() -> void:
	var effect := FixtureEffect.new()
	effect.event_kind = "periodic"
	effect.event_tick = 30
	effect.actions = [{"kind":"shield_grant", "target_key":"A1", "amount":120, "expires_tick":100}]
	var pair := _fixture("GL11", {"A1":{"hp_tenths":800,"T_ticks":1000}, "B1":{"A":15,"T_ticks":20,"target_slot":1}}, effect)
	_run_to(pair.engine, 60, "GL11 shield freezing and low-health redemption")
	_assert(pair.engine.get_counter(pair.binding.source_key, "frozen") == 0,
		"GL11 redemption clears the stored shield value on first post-40-percent loss")
	_assert(int(pair.engine.unit("A1").hp_tenths) > 0 and int(pair.engine.unit("A1").hp_tenths) >= 450,
		"GL11 real sub-40-percent loss cashes frozen shield into healing")
	_scenario()


func _test_gl12() -> void:
	var pair := _fixture("GL12", {"A1":{"T_ticks":1000}, "B1":{"A":10,"reach":"melee","T_ticks":20,"target_slot":1}})
	_run_to(pair.engine, 20, "GL12 direct enemy melee-hit retaliation")
	_assert(_layers(pair.engine.unit("B1"), "poison") == 1,
		"GL12 poisoned melee attacker even if target defenses modify damage; poison is source-attributed")
	_scenario()


func _test_gl13() -> void:
	var pair := _fixture("GL13", {"A1":{"T_ticks":1000}, "B1":{"R":0,"armor_kind":"light","T_ticks":1000}})
	_run_to(pair.engine, 80, "GL13 fixed pulse and temporary preparation slow")
	var fixed_loss := 0
	for event in _events_for(pair.engine):
		if str(event.get("kind", "")) == "hp_lost" and str(event.get("source_key", "")) == "A1" and str(event.get("target_key", "")) == "B1" and str(event.get("damage_type", "")) == "fixed": fixed_loss += int(event.get("actual_hp_loss", 0))
	_assert(fixed_loss == 85, "GL13 six-percent current-health fixed pulse is emitted at tick60; observed=%d" % fixed_loss)
	_assert(int(pair.engine.effective_stats("A1").T_ticks) == 1000, "GL13 temporary 20%% preparation slow expires at tick80")
	_scenario()


func _test_gl14() -> void:
	var effect := FixtureEffect.new()
	effect.event_kind = "battle_start"
	effect.actions = [{"kind":"status_add", "target_key":"B1", "status_id":"burn", "layers":1, "expires_tick":100}]
	var pair := _fixture("GL14", {"A1":{"T_ticks":20}, "B1":{"T_ticks":1000}, "B2":{"T_ticks":1000}, "B3":{"T_ticks":1000}}, effect)
	_run_to(pair.engine, 20, "GL14 burn consumption and live-enemy spread")
	_assert(_layers(pair.engine.unit("B1"), "burn") == 0 and _layers(pair.engine.unit("B2"), "burn") == 1 and _layers(pair.engine.unit("B3"), "burn") == 1,
		"GL14 real natural hit consumes one target burn then spreads to every other living enemy")
	_scenario()


func _fixture(content_id: String, overrides: Dictionary = {}, fixture_effect = null) -> Dictionary:
	var handler = HandlerScript.new()
	var owner_key := "A1"
	var binding := {"content_id":content_id, "logic_handler":"character_" + content_id, "owner_key":owner_key,
		"source_key":owner_key + ":" + content_id, "kind":"talent"}
	var definition := {"logic_handler":binding.logic_handler, "handler":handler, "bindings":[binding]}
	var teams := {"A":[_unit("A", 1, content_id), _unit("A", 2), _unit("A", 3)],
		"B":[_unit("B", 1), _unit("B", 2), _unit("B", 3)]}
	for side in ["A", "B"]:
		for index in range(3):
			var unit_state: Dictionary = teams[side][index]
			var key := "%s%d" % [side, int(unit_state.slot)]
			if overrides.has(key): unit_state.merge(overrides[key], true)
	var definitions: Array = [definition]
	if fixture_effect != null:
		definitions.append({"logic_handler":"fixture_effect", "handler":fixture_effect,
			"bindings":[{"content_id":"FIXTURE_EFFECT", "logic_handler":"fixture_effect", "owner_key":"A1", "source_key":"fixture:GL", "kind":"talent"}]})
	var engine = EngineScript.new()
	var result: Dictionary = engine.setup({"seed":7, "rule_id":"VC01", "test_fixture":true, "teams":teams}, definitions, {"capture_tick_hashes":false})
	if not str(result.get("error", "")).is_empty(): failures.append("GL fixture setup %s: %s" % [content_id, result.error])
	return {"engine":engine, "binding":binding}


func _unit(side: String, slot: int, character_id := "") -> Dictionary:
	var owner := side == "A" and slot == 1 and not character_id.is_empty()
	var card: Dictionary = cards.get(character_id, {}) if owner else {}
	return {"definition_id":character_id if owner else "FIXTURE_%s%d" % [side, slot], "talent_id":character_id if owner else "",
		"fixture":not owner, "slot":slot, "H":int(card.get("H", 100)), "A":int(card.get("A", 0)),
		"T_ticks":int(card.get("T_ticks", 1000)), "R":int(card.get("R", 0)), "reach":str(card.get("reach", "ranged")),
		"armor_kind":str(card.get("armor_kind", "light")), "target_slot":1, "first_attack_tick":1000 if not owner else 0}


func _run_to(engine: BattleEngine, final_tick: int, label: String) -> void:
	if not event_logs.has(engine.get_instance_id()): event_logs[engine.get_instance_id()] = []
	for tick in range(final_tick + 1):
		var result: Dictionary = engine.step(false)
		event_logs[engine.get_instance_id()].append_array(result.get("events", []))
		if not str(result.get("error", "")).is_empty():
			failures.append("%s failed at tick %d: %s" % [label, tick, result.error])
			return

func _events_for(engine: BattleEngine) -> Array:
	return event_logs.get(engine.get_instance_id(), [])


func _layers(unit_state: Dictionary, status_id: String) -> int:
	var result := 0
	for status in unit_state.get("statuses", []):
		if str(status.get("id", "")) == status_id: result += int(status.get("layers", 0))
	return result


func _scenario() -> void:
	scenarios += 1


func _assert(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
