extends SceneTree

const EngineScript = preload("res://core/battle/battle_engine.gd")
const CatalogScript = preload("res://content/attachments/attachment_catalog.gd")
const AttachmentHandlersScript = preload("res://content/attachments/attachment_handlers.gd")

class Driver extends RefCounted:
	var actions: Array = []
	var event_kind := "battle_start"
	var fired := false
	var extra_actions: Array = []
	var extra_tick := -1
	var extra_fired := false

	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if not fired and str(event.get("kind", "")) == event_kind:
			fired = true
			return actions.duplicate(true)
		if not extra_fired and extra_tick >= 0 and str(event.get("kind", "")) == "periodic" and int(event.get("tick", -1)) == extra_tick:
			extra_fired = true
			return extra_actions.duplicate(true)
		return []


class FX43CycleToOwner extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) == "shield_gained" and str(event.get("source_binding_key", "")) == "A1:FX43" \
			and str(event.get("target_key", "")) == "A2" and str(event.get("payload", {}).get("kind", "")) == "barrier":
			return [{"kind":"heal", "target_key":"A1", "amount":10}]
		return []


class FX43CycleBack extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) == "healed" and str(event.get("source_key", "")) == "A2" \
			and str(event.get("target_key", "")) == "A1":
			return [{"kind":"heal", "target_key":"A2", "amount":10}]
		return []


class EQ09AttachPhysical extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) == "prepare_attack" and str(event.get("source_key", "")) == "A1" \
			and bool(event.get("is_extra_attack", false)):
			return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")),
				"patch":{"attached_damage":[{"amount":20,"damage_type":"physical"}]}}]
		return []


class EQ29SwitchMainPhysical extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) == "prepare_attack" and str(event.get("source_key", "")) == "A1" \
			and int(event.get("tick", -1)) >= 18:
			return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")), "patch":{"damage_type":"physical"}}]
		return []


var checks := 0
var failures: Array[String] = []
var HandlerScript: Script
var trigger_scope_by_card: Dictionary = {}
var exercised_card_ids: Dictionary = {}


func _initialize() -> void:
	HandlerScript = load("res://content/attachments/attachment_handlers.gd") as Script
	if HandlerScript == null or not HandlerScript.can_instantiate():
		push_error("ATTACHMENT_ENGINE_BATCH_ABORTED: attachment_handlers.gd did not compile")
		quit(1)
		return
	var attachment_document: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/attachments/attachments.json"))
	if not attachment_document is Dictionary:
		push_error("ATTACHMENT_ENGINE_BATCH_ABORTED: attachment metadata did not parse")
		quit(1)
		return
	for card: Dictionary in attachment_document.get("attachments", []):
		if card.has("trigger_scope"): trigger_scope_by_card[str(card.get("id", ""))] = str(card.trigger_scope)
	_test_setup_only("EQ01", {"owner_attack":10})
	_test_setup_only("EQ02", {"owner_hp":500})
	_test_setup_only("EQ03", {"owner_speed":8})
	_test_setup_only("EQ04", {"owner_armor":2, "enemy_attack":8, "owner_attack":0})
	_test_setup_only("EQ12")
	_test_eq12_minimum()
	_test_setup_only("EQ13", {"owner_attack":10})
	_test_eq05()
	_test_eq14()
	_test_eq06()
	_test_eq08()
	_test_eq09()
	_test_eq29()
	_test_eq30()
	_test_eq49()
	_test_eq26()
	_test_eq17()
	_test_natural_hit_status("EQ10", "chill", 20, "eq10")
	_test_natural_hit_status("EQ11", "poison", 30, "eq11")
	_test_natural_hit_status("EQ40", "silence", 8, "eq40")
	_test_natural_hit_status("EQ41", "rooted", 10, "eq41")
	_test_eq15()
	_test_eq16()
	_test_consume_debuff("EQ20", "burn", 920, 980, "eq20")
	_test_consume_debuff("EQ21", "poison", 980, 980, "eq21")
	_test_eq07()
	_test_fx02()
	_test_fx01()
	_test_fx03()
	_test_fx05()
	_test_fx06()
	_test_fx07()
	_test_fx08()
	_test_fx09()
	_test_fx12()
	_test_fx13()
	_test_fx17()
	_test_fx20()
	_test_fx22()
	_test_fx18()
	_test_eq25()
	_test_eq18()
	_test_eq22()
	_test_eq23()
	_test_eq34()
	_test_eq36()
	_test_fx31()
	_test_fx34()
	_test_eq42()
	_test_fx33()
	_test_fx36()
	_test_fx43()
	_test_fx44()
	_test_eq37()
	_test_fx21()
	_test_eq43()
	_test_eq44()
	_test_fx24()
	_test_fx26()
	_test_fx47()
	_test_eq35()
	_test_eq38()
	_test_eq33()
	_test_eq27()
	_test_fx41()
	_test_eq19()
	_test_eq24()
	_test_eq28()
	_test_eq45()
	_test_eq46()
	_test_handler_support_manifest(attachment_document)
	if failures.is_empty() and checks > 0:
		print("ATTACHMENT_ENGINE_BATCH_OK checks=%d cards_with_runtime_fixtures=%d trigger_negative_expiry=verified" % [checks, exercised_card_ids.size()])
		quit(0)
	else:
		if checks == 0: failures.append("ATTACHMENT_ENGINE_BATCH_ABORTED: no assertions executed")
		push_error("ATTACHMENT_ENGINE_BATCH_FAILED checks=%d failures=%d" % [checks, failures.size()])
		for failure in failures: push_error(failure)
		quit(1)


func _test_eq05() -> void:
	var positive := _new_case("EQ05")
	_run_until(positive.engine, 0)
	_check(positive.engine.shield_amount("A1", "A1:EQ05") == 240, "EQ05 battle_start grants exactly 24 shield")
	_run_until(positive.engine, 1)
	_check(positive.engine.shield_amount("A1", "A1:EQ05") == 240, "EQ05 does not retrigger on periodic/non-start events")
	_run_until(positive.engine, 60)
	_check(positive.engine.shield_amount("A1", "A1:EQ05") == 0, "EQ05 pool expires at six seconds")


func _test_eq14() -> void:
	var positive := _new_case("EQ14", {"enemy_attack":8, "ally2_hp":1000, "owner_attack":0})
	_run_until(positive.engine, 0)
	# B1's tick-zero attack targets A1 by default; use a fixture driver to hit A2.
	var driver := Driver.new()
	driver.actions = [{"kind":"damage", "target_key":"A2", "amount":80, "source_key":"B1", "damage_type":"physical"}]
	var redirected := _new_case("EQ14", {"enemy_attack":0, "owner_attack":0}, [], {"handlers":[{"logic_handler":"fixture_driver", "handler":driver,
		"bindings":[{"content_id":"FIXTURE_EQ14_DRIVER", "logic_handler":"fixture_driver", "source_key":"B1:DRIVER", "owner_key":"B1", "kind":"slot"}]}]})
	_run_until(redirected.engine, 0)
	_check(int(redirected.engine.unit("A2").hp_tenths) == 940 and int(redirected.engine.unit("A1").hp_tenths) == 980,
		"EQ14 transfers twenty-five percent of a teammate packet to the wearer")
	var capped_driver := Driver.new()
	capped_driver.actions = [{"kind":"damage", "target_key":"A2", "amount":800, "source_key":"B1", "damage_type":"physical"}]
	var capped := _new_case("EQ14", {"enemy_attack":0, "owner_attack":0}, [], {"handlers":[{"logic_handler":"fixture_driver", "handler":capped_driver,
		"bindings":[{"content_id":"FIXTURE_EQ14_CAP", "logic_handler":"fixture_driver", "source_key":"B1:CAP", "owner_key":"B1", "kind":"slot"}]}]})
	_run_until(capped.engine, 0)
	_check(int(capped.engine.unit("A1").hp_tenths) == 940,
		"EQ14 applies its six-point per-root transfer cap")


func _test_eq15() -> void:
	var owner_full := [{"kind":"heal", "target_key":"A1", "amount":100}]
	var positive := _new_case("EQ15", {"enemy_attack":0}, owner_full)
	_run_until(positive.engine, 0)
	_check(positive.engine.shield_amount("A1", "A1:EQ15") == 60, "EQ15 converts 60 percent of overheal into shield")
	var no_overheal := [{"kind":"heal", "target_key":"A1", "amount":100}]
	var negative := _new_case("EQ15", {"enemy_attack":0, "owner_hp":900}, no_overheal)
	_run_until(negative.engine, 0)
	_check(negative.engine.shield_amount("A1", "A1:EQ15") == 0 and negative.engine.ready("A1:EQ15", "eq15"),
		"EQ15 does not trigger when received healing has no overflow")
	var expiry := _new_case("EQ15", {"enemy_attack":0}, owner_full)
	_run_until(expiry.engine, 40)
	_check(expiry.engine.shield_amount("A1", "A1:EQ15") == 0 and _has_expiry(expiry.engine.state.events, "", "A1:EQ15"),
		"EQ15 converted shield expires after four seconds")


func _test_eq16() -> void:
	var positive := _new_case("EQ16", {"enemy_attack":0, "owner_damage_type":"ice"}, [
		{"kind":"barrier_grant", "target_key":"B1", "expires_tick":100}
	])
	_run_until(positive.engine, 18)
	_check(int(positive.engine.unit("B1").hp_tenths) == 960
		and positive.engine.get_counter("A1:EQ16", "eq16_natural_hits") == 3,
		"EQ16 counts even a first natural hit fully cancelled by barrier, but does not proc before four hits")
	_run_until(positive.engine, 24)
	_check(int(positive.engine.unit("B1").hp_tenths) == 940
		and positive.engine.get_counter("A1:EQ16", "eq16_natural_hits") == 0,
		"EQ16 clears its natural-hit count on the fourth completed hit")
	_run_until(positive.engine, 25)
	var ledger := _hp_loss_ledger(positive.engine, "B1")
	_check(int(positive.engine.unit("B1").hp_tenths) == 928 and ledger.size() == 4
		and int(ledger[3].loss) == 12 and str(ledger[3].damage_type) == "ice",
		"EQ16 schedules one 60%%-A ice extra attack one tick after the fourth hit (ledger=%s)" % str(ledger))
	_run_until(positive.engine, 30)
	_check(int(positive.engine.unit("B1").hp_tenths) == 908
		and positive.engine.get_counter("A1:EQ16", "eq16_natural_hits") == 1,
		"EQ16 extra attack does not increment its four-natural-hit counter")
	var no_hits := _new_case("EQ16", {"enemy_attack":0, "owner_slow":true})
	_run_until(no_hits.engine, 30)
	_check(no_hits.engine.get_counter("A1:EQ16", "eq16_natural_hits") == 0
		and int(no_hits.engine.unit("B1").hp_tenths) == 1000,
		"EQ16 does not fire without four natural hit events")


func _test_consume_debuff(card_id: String, status_id: String, expected_positive_hp: int, expected_negative_hp: int, cooldown_key: String) -> void:
	var setup_status := [{"kind":"status_add", "target_key":"B1", "status_id":status_id, "layers":1, "expires_tick":100}]
	var owner_hp := 500 if card_id == "EQ21" else 1000
	var positive := _new_case(card_id, {"enemy_attack":0, "owner_hp":owner_hp}, setup_status)
	_run_until(positive.engine, 6)
	_check(int(positive.engine.unit("B1").hp_tenths) == expected_positive_hp
		and _status_count(positive.engine.unit("B1"), status_id) == 0,
		"%s consumes one %s layer and applies its printed payoff" % [card_id, status_id])
	var expected_owner_hp := owner_hp + 60 if card_id == "EQ21" else owner_hp
	_check(int(positive.engine.unit("A1").hp_tenths) == expected_owner_hp, "%s applies the correct owner-side payoff" % card_id)
	var negative := _new_case(card_id, {"enemy_attack":0, "owner_hp":owner_hp})
	_run_until(negative.engine, 6)
	_check(int(negative.engine.unit("B1").hp_tenths) == expected_negative_hp
		and int(negative.engine.unit("A1").hp_tenths) == owner_hp,
		"%s does not pay out when the target lacks %s" % [card_id, status_id])
	var expiry := _new_case(card_id, {"enemy_attack":0}, setup_status)
	_run_until(expiry.engine, 36)
	_check(expiry.engine.ready("A1:%s" % card_id, cooldown_key), "%s cooldown expires at three seconds" % card_id)


func _test_setup_only(card_id: String, options: Dictionary = {}) -> void:
	var test_case := _new_case(card_id, options)
	var engine: BattleEngine = test_case.engine
	var unit: Dictionary = engine.unit("A1")
	match card_id:
		"EQ01": _check(int(engine.effective_stats("A1").A) == 13 and int(unit.base_A) == 10, "EQ01 setup +3 affects combat A but preserves base A")
		"EQ02": _check(int(unit.H) == 118 and int(unit.initial_max_hp_tenths) == 1180 and int(unit.hp_tenths) == 680 and int(unit.base_H) == 100,
			"EQ02 setup +18 synchronizes current HP/max HP and preserves base H")
		"EQ03": _check(int(engine.effective_stats("A1").T_ticks) == 6 and int(unit.base_T_ticks) == 8, "EQ03 setup reduces attack interval by two ticks")
		"EQ04": _check(int(engine.effective_stats("A1").R) == 5 and int(unit.base_R) == 2, "EQ04 setup adds three armor over naked base")
		"EQ12": _check(int(unit.H) == 88 and int(unit.hp_tenths) == 880 and bool(unit.flying) and int(unit.base_H) == 100,
			"EQ12 setup synchronizes H, current HP and flight without a combat damage event")
		"EQ13": _check(int(engine.effective_stats("A1").A) == 7 and str(unit.reach) == "ranged" and int(unit.base_A) == 10,
			"EQ13 setup changes attack/reach while preserving naked base")
	_run_until(engine, 1)
	var emitted_by_card := false
	for event in engine.state.events:
		if str(event.get("source_binding_key", "")) == "A1:%s" % card_id: emitted_by_card = true
	_check(not emitted_by_card, "%s setup-only modifier does not create combat-trigger actions" % card_id)
	_run_until(engine, 240)
	unit = engine.unit("A1")
	match card_id:
		"EQ01": _check(int(engine.effective_stats("A1").A) == 13, "EQ01 setup modifier persists for the battle lifetime")
		"EQ02": _check(int(unit.H) == 118 and int(unit.base_H) == 100, "EQ02 setup modifier persists without altering naked H")
		"EQ03": _check(int(engine.effective_stats("A1").T_ticks) == 6, "EQ03 setup modifier persists for the battle lifetime")
		"EQ04": _check(int(engine.effective_stats("A1").R) == 5, "EQ04 setup modifier persists for the battle lifetime")
		"EQ12": _check(int(unit.H) == 88 and bool(unit.flying), "EQ12 setup modifier persists for the battle lifetime")
		"EQ13": _check(int(engine.effective_stats("A1").A) == 7 and str(unit.reach) == "ranged", "EQ13 setup modifier persists for the battle lifetime")


func _test_eq06() -> void:
	var positive := _new_case("EQ06", {"enemy_attack":0, "owner_attack":0})
	_run_until(positive.engine, 20)
	_check(int(positive.engine.unit("A1").hp_tenths) == 970, "EQ06 inflicts scheduled unshieldable self-loss beginning at two seconds")
	var negative := _new_case("EQ06", {"enemy_attack":0, "owner_attack":0})
	_run_until(negative.engine, 19)
	_check(int(negative.engine.unit("A1").hp_tenths) == 1000, "EQ06 does not self-damage before its first due tick")
	var departure := _new_case("EQ06", {"enemy_attack":0, "owner_attack":0, "owner_hp":60})
	_run_until(departure.engine, 100)
	_check(bool(departure.engine.unit("A1").final_departed) and int(departure.engine.unit("A1").hp_tenths) == 0,
		"EQ06 stops scheduling after self-inflicted final departure")


func _test_eq12_minimum() -> void:
	var low_panel := _new_case("EQ12", {"enemy_attack":0, "owner_base_H":10})
	_run_until(low_panel.engine, 0)
	_check(int(low_panel.engine.unit("A1").H) == 1 and int(low_panel.engine.unit("A1").hp_tenths) == 10
		and bool(low_panel.engine.unit("A1").flying),
		"EQ12 applies H floor 1 and synchronized current-HP floor 1 at battle setup (H=%d hp=%d)" % [int(low_panel.engine.unit("A1").H), int(low_panel.engine.unit("A1").hp_tenths)])


func _test_eq26() -> void:
	var positive := _new_case("EQ26", {"enemy_attack":0, "enemy_armor":0}, [
		{"kind":"extra_attack", "target_key":"B1", "amount":20, "damage_type":"physical"}
	])
	_run_until(positive.engine, 12)
	var ledger := _hp_loss_ledger(positive.engine, "B1")
	_check(int(positive.engine.effective_stats("A1").T_ticks) == 12 and ledger.size() == 2
		and int(ledger[0].loss) == 20 and int(ledger[1].loss) == 29
		and str(ledger[0].damage_type) == "physical" and str(ledger[1].damage_type) == "physical",
		"EQ26 slows natural T by six ticks and raises only the natural main damage 45%% (ledger=%s)" % str(ledger))
	_run_until(positive.engine, 240)
	_check(int(positive.engine.effective_stats("A1").T_ticks) == 12,
		"EQ26 setup bonus remains battle-long rather than expiring")


func _test_eq08() -> void:
	var positive := _new_case("EQ08", {"enemy_attack":0, "owner_attack":0})
	_run_until(positive.engine, 0)
	_check(_status_count(positive.engine.unit("A1"), "burn") == 1, "EQ08 applies first self-burn at battle start")
	var negative := _new_case("EQ08", {"enemy_attack":0, "owner_attack":0})
	_run_until(negative.engine, 1)
	_check(_status_count(negative.engine.unit("A1"), "burn") == 1, "EQ08 does not add extra burn between four-second intervals")
	var expiry := _new_case("EQ08", {"enemy_attack":0, "owner_attack":0})
	_run_until(expiry.engine, 31)
	_check(_status_count(expiry.engine.unit("A1"), "burn") == 0 and _has_expiry(expiry.engine.state.events, "burn", "A1:EQ08"),
		"EQ08 burn instance expires after three seconds")
	var repeated := _new_case("EQ08", {"enemy_attack":0, "owner_attack":0})
	_run_until(repeated.engine, 40)
	_check(_status_count(repeated.engine.unit("A1"), "burn") == 1 and _first_event_tick(repeated.engine.state.events, "status_applied", "A1") == 0,
		"EQ08 starts another burn interval at four seconds")


func _test_eq09() -> void:
	var natural := _new_case("EQ09", {"enemy_attack":0, "enemy_armor":3})
	_run_until(natural.engine, 6)
	var natural_ledger := _hp_loss_ledger(natural.engine, "B1")
	_check(int(natural.engine.unit("B1").hp_tenths) == 984 and natural_ledger.size() == 1
		and int(natural_ledger[0].loss) == 16 and str(natural_ledger[0].damage_type) == "fire"
		and not _has_status(natural.engine.unit("B1"), "burn"),
		"EQ09 converts only the natural main segment to 80% fire through armor, without applying burn")
	var extra := _new_case("EQ09", {"enemy_attack":0, "enemy_armor":1, "owner_attack":0}, [
		{"kind":"extra_attack", "target_key":"B1", "amount":30, "damage_type":"physical"}
	], {"handlers":[{"logic_handler":"eq09_attached_fixture", "handler":EQ09AttachPhysical.new(), "bindings":[
		{"content_id":"FIXTURE_EQ09_ATTACHED", "logic_handler":"eq09_attached_fixture", "source_key":"A1:EQ09_ATTACHED", "owner_key":"A1", "kind":"slot"}]}]})
	_run_until(extra.engine, 0)
	var extra_ledger := _hp_loss_ledger(extra.engine, "B1")
	_check(extra_ledger.size() == 2 and str(extra_ledger[0].damage_type) == "fire"
		and int(extra_ledger[0].loss) == 24 and str(extra_ledger[1].damage_type) == "physical"
		and int(extra_ledger[1].loss) == 10,
		"EQ09 converts its owner's extra-attack main segment but leaves attached physical damage untouched")
	var other_source := _new_case("EQ09", {"enemy_attack":0, "enemy_armor":3, "owner_attack":0}, [
		{"kind":"extra_attack", "target_key":"B1", "amount":20, "damage_type":"physical"}
	], {"owner_key":"A2"})
	_run_until(other_source.engine, 0)
	var other_ledger := _hp_loss_ledger(other_source.engine, "B1")
	_check(other_ledger.size() == 1 and str(other_ledger[0].damage_type) == "physical" and int(other_ledger[0].loss) == 10,
		"EQ09 never converts an attack sourced by another teammate")


func _test_eq29() -> void:
	var streak := _new_case("EQ29", {"enemy_attack":0})
	_run_until(streak.engine, 24)
	var streak_ledger := _hp_loss_ledger(streak.engine, "B1")
	var amounts: Array[int] = []
	for entry: Dictionary in streak_ledger: amounts.append(int(entry.loss))
	_check(amounts == [20, 40, 60, 80] and int(streak.engine.unit("B1").hp_tenths) == 800,
		"EQ29 adds 2/4/6 physical HP to successive natural main hits and caps the bonus at 6")

	var switched := _new_case("EQ29", {"enemy_attack":0, "enemy_hp":40})
	_run_until(switched.engine, 24)
	var first_target := _hp_loss_ledger(switched.engine, "B1")
	var next_target := _hp_loss_ledger(switched.engine, "B2")
	_check(first_target.size() == 2 and int(first_target[0].loss) == 20 and int(first_target[1].loss) == 20
		and next_target.size() >= 2 and int(next_target[0].loss) == 20 and int(next_target[1].loss) == 40,
		"EQ29 resets its consecutive-hit bonus when natural targeting moves to a different enemy")

	var elemental := _new_case("EQ29", {"enemy_attack":0, "owner_damage_type":"fire"})
	_run_until(elemental.engine, 18)
	var elemental_ledger := _hp_loss_ledger(elemental.engine, "B1")
	_check(elemental_ledger.size() == 3 and int(elemental_ledger[0].loss) == 20
		and int(elemental_ledger[1].loss) == 20 and int(elemental_ledger[2].loss) == 20,
		"EQ29 leaves nonphysical main damage unchanged")
	var converts := _new_case("EQ29", {"enemy_attack":0, "owner_damage_type":"fire"}, [], {"handlers":[
		{"logic_handler":"fixture_eq29_type_switch", "handler":EQ29SwitchMainPhysical.new(), "bindings":[
			{"content_id":"FIXTURE_EQ29_TYPE_SWITCH", "logic_handler":"fixture_eq29_type_switch",
				"source_key":"A1:EQ29_TYPE_SWITCH", "owner_key":"A1", "kind":"slot"}]}
	]})
	_run_until(converts.engine, 24)
	var converted_ledger := _hp_loss_ledger(converts.engine, "B1")
	_check(converted_ledger.size() == 4 and str(converted_ledger[0].damage_type) == "fire"
		and str(converted_ledger[2].damage_type) == "fire" and str(converted_ledger[3].damage_type) == "physical"
		and int(converted_ledger[3].loss) == 80,
		"EQ29 records nonphysical hits and applies the capped bonus once the main segment becomes physical")

	var extra_only := _new_case("EQ29", {"enemy_attack":0, "owner_slow":true}, [
		{"kind":"extra_attack", "target_key":"B1", "amount":30, "damage_type":"physical"}
	])
	_run_until(extra_only.engine, 0)
	var extra_ledger := _hp_loss_ledger(extra_only.engine, "B1")
	_check(extra_ledger.size() == 1 and int(extra_ledger[0].loss) == 30,
		"EQ29 neither counts nor boosts an extra attack")


func _test_eq30() -> void:
	var positive := _new_case("EQ30", {"enemy_attack":0, "owner_attack":2, "owner_target_slot":1}, [
		{"kind":"damage", "target_key":"B1", "amount":1000, "damage_type":"fixed", "source_key":"A2"},
		{"kind":"extra_attack", "target_key":"B2", "amount":20, "damage_type":"physical"}
	])
	_run_until(positive.engine, 0)
	_check(positive.engine.get_counter("A1:EQ30", "eq30_charge") == 1,
		"EQ30 stores one four-second charge when the current target finally departs")
	_run_until(positive.engine, 6)
	var positive_ledger := _hp_loss_ledger(positive.engine, "B2")
	var fixed_total := 0
	for entry: Dictionary in positive_ledger:
		if str(entry.damage_type) == "fixed": fixed_total += int(entry.loss)
	_check(fixed_total == 80 and positive.engine.get_counter("A1:EQ30", "eq30_charge") == 0,
		"EQ30 ignores the intervening extra attack, appends eight fixed damage after the next natural hit, and consumes on hit")

	var no_departure := _new_case("EQ30", {"enemy_attack":0, "owner_attack":2})
	_run_until(no_departure.engine, 6)
	var ordinary_ledger := _hp_loss_ledger(no_departure.engine, "B1")
	_check(ordinary_ledger.size() == 1 and int(ordinary_ledger[0].loss) == 20
		and str(ordinary_ledger[0].damage_type) == "physical"
		and no_departure.engine.get_counter("A1:EQ30", "eq30_charge") == 0,
		"EQ30 does not modify a natural hit when no target-departure charge was earned")

	var expired := _new_case("EQ30", {"enemy_attack":0, "owner_speed":40, "owner_target_slot":1}, [
		{"kind":"damage", "target_key":"B1", "amount":1000, "damage_type":"fixed", "source_key":"A2"}
	])
	_run_until(expired.engine, 40)
	var expired_ledger := _hp_loss_ledger(expired.engine, "B2")
	var expired_fixed := 0
	for entry: Dictionary in expired_ledger:
		if str(entry.damage_type) == "fixed": expired_fixed += int(entry.loss)
	_check(expired_fixed == 0 and expired_ledger.size() == 1,
		"EQ30 does not attach or consume its charge when the first natural hit arrives at the exact four-second expiry")


func _test_eq49() -> void:
	var redirect_action := {"kind":"redirect_register", "target_key":"A2", "ratio_bp":5000,
		"recipient_keys":["A1"], "capacity_per_second":1000}
	var positive := _new_case("EQ49", {"enemy_attack":2, "enemy_target":2, "owner_attack":2}, [redirect_action])
	_run_until(positive.engine, 6)
	_check(int(positive.engine.unit("A1").hp_tenths) == 990
		and positive.engine.get_counter("A1:EQ49", "eq49_charge") == 1,
		"EQ49 arms only after redirected damage causes the wearer actual HP loss")
	_run_until(positive.engine, 12)
	var positive_ledger := _hp_loss_ledger(positive.engine, "B1")
	_check(positive_ledger.size() >= 2 and int(positive_ledger[0].loss) == 20
		and int(positive_ledger[1].loss) == 100
		and positive.engine.get_counter("A1:EQ49", "eq49_charge") == 0,
		"EQ49 adds eight to the next natural main hit using its existing damage type and consumes on hit")

	var direct := _new_case("EQ49", {"enemy_attack":2, "enemy_target":1, "owner_attack":2})
	_run_until(direct.engine, 12)
	var direct_ledger := _hp_loss_ledger(direct.engine, "B1")
	_check(direct_ledger.size() == 2 and int(direct_ledger[0].loss) == 20 and int(direct_ledger[1].loss) == 20
		and direct.engine.get_counter("A1:EQ49", "eq49_charge") == 0,
		"EQ49 does not arm on ordinary direct HP loss")

	var shielded := _new_case("EQ49", {"enemy_attack":2, "enemy_target":2, "owner_attack":2}, [
		redirect_action, {"kind":"shield_grant", "target_key":"A1", "amount":20, "expires_tick":100}
	])
	_run_until(shielded.engine, 12)
	var shielded_ledger := _hp_loss_ledger(shielded.engine, "B1")
	_check(shielded_ledger.size() == 2 and int(shielded_ledger[1].loss) == 20
		and int(shielded.engine.unit("A1").hp_tenths) == 1000
		and shielded.engine.get_counter("A1:EQ49", "eq49_charge") == 0,
		"EQ49 does not arm when the redirected packet is fully absorbed by the wearer's shield")

	var expired := _new_case("EQ49", {"enemy_attack":2, "enemy_target":2, "owner_speed":46, "owner_target_slot":1}, [
		redirect_action
	], {"tick":7, "actions":[{"kind":"damage", "target_key":"B1", "amount":2000, "damage_type":"fixed", "source_key":"A2"}]})
	_run_until(expired.engine, 46)
	var expired_ledger := _hp_loss_ledger(expired.engine, "B2")
	_check(expired_ledger.size() == 1 and int(expired_ledger[0].loss) == 20,
		"EQ49's four-second charge expires before a natural hit at the exact boundary")


func _test_eq17() -> void:
	var with_status := _new_case("EQ17", {"enemy_attack":0, "owner_attack":0}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"poison", "layers":1, "expires_tick":100}
	])
	_run_until(with_status.engine, 0)
	_check(_status_count(with_status.engine.unit("A1"), "poison") == 0 and with_status.engine.shield_amount("A1", "A1:EQ17") == 40,
		"EQ17 clears an existing negative effect and grants four shield on its periodic check")
	var no_status := _new_case("EQ17", {"enemy_attack":0, "owner_attack":0})
	_run_until(no_status.engine, 0)
	_check(no_status.engine.shield_amount("A1", "A1:EQ17") == 0,
		"EQ17 does not grant shield when no negative status exists")
	var expiry := _new_case("EQ17", {"enemy_attack":0, "owner_attack":0}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"poison", "layers":1, "expires_tick":100}
	])
	_run_until(expiry.engine, 20)
	_check(expiry.engine.shield_amount("A1", "A1:EQ17") == 0 and _has_expiry(expiry.engine.state.events, "", "A1:EQ17"),
		"EQ17 granted shield expires at two seconds")


func _test_natural_hit_status(card_id: String, status_id: String, duration: int, cooldown_key: String) -> void:
	var positive := _new_case(card_id)
	_run_until(positive.engine, 8)
	var target: Dictionary = positive.engine.unit("B1")
	var found := _find_status(target, status_id)
	var trigger_tick := _first_event_tick(positive.engine.state.events, "hit", "A1")
	_check(not found.is_empty() and trigger_tick >= 0 and int(found.get("expires_tick", -1)) == trigger_tick + duration,
		"%s natural hit applies %s with exact duration" % [card_id, status_id])
	var negative := _new_case(card_id, {"owner_slow":true, "enemy_attack":0})
	_run_until(negative.engine, 12)
	_check(_find_status(negative.engine.unit("B1"), status_id).is_empty(),
		"%s does not trigger without owner's natural hit" % card_id)
	var expiry := _new_case(card_id)
	_run_until(expiry.engine, trigger_tick + duration)
	_check(_find_status(expiry.engine.unit("B1"), status_id).is_empty()
		and _has_expiry(expiry.engine.state.events, status_id, "A1:%s" % card_id),
		"%s %s expires at authored boundary" % [card_id, status_id])
	_check(cooldown_key in ["eq10", "eq11", "eq40", "eq41"], "%s cooldown key is explicitly registered" % card_id)


func _test_eq07() -> void:
	var positive := _new_case("EQ07", {"enemy_attack":0})
	_run_until(positive.engine, 6)
	_check(positive.engine.shield_amount("A1", "A1:EQ07") == 60, "EQ07 natural hit grants shield only while owner unshielded")
	var negative := _new_case("EQ07", {"owner_slow":true, "enemy_attack":0}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":10, "expires_tick":100}
	])
	_run_until(negative.engine, 12)
	_check(negative.engine.shield_amount("A1", "A1:EQ07") == 0, "EQ07 does not trigger without its natural hit")
	var expiry := _new_case("EQ07", {"enemy_attack":0})
	_run_until(expiry.engine, 36)
	_check(_has_expiry(expiry.engine.state.events, "", "A1:EQ07"), "EQ07 shield pool expires at three seconds")


func _test_fx01() -> void:
	var positive := _new_case("FX01", {"enemy_attack":0, "owner_definition_id":"FIXTURE_WR01",
		"ally2_definition_id":"FIXTURE_WR02", "ally3_definition_id":"FIXTURE_GR01"})
	_run_until(positive.engine, 6)
	_check(int(positive.engine.effective_stats("A2").A) == 4 and int(positive.engine.effective_stats("A3").A) == 4
		and positive.engine.get_counter("A1:FX01", "fx01_fired") == 1,
		"FX01 gives both same-sin and other-sin teammates +4 A on the first natural hit")
	_run_until(positive.engine, 36)
	_check(int(positive.engine.effective_stats("A2").A) == 4 and int(positive.engine.effective_stats("A3").A) == 0,
		"FX01 same-sin ally keeps its four-second buff while the other-sin buff expires at three seconds")
	_run_until(positive.engine, 60)
	_check(int(positive.engine.effective_stats("A2").A) == 0 and int(positive.engine.effective_stats("A3").A) == 0,
		"FX01 buffs expire and do not reapply on later natural hits")
	var no_hit := _new_case("FX01", {"enemy_attack":0, "owner_slow":true,
		"owner_definition_id":"FIXTURE_WR01", "ally2_definition_id":"FIXTURE_WR02", "ally3_definition_id":"FIXTURE_GR01"})
	_run_until(no_hit.engine, 60)
	_check(int(no_hit.engine.effective_stats("A2").A) == 0 and int(no_hit.engine.effective_stats("A3").A) == 0
		and no_hit.engine.get_counter("A1:FX01", "fx01_fired") == 0,
		"FX01 does not grant bonuses before the wearer's first natural hit")


func _test_fx02() -> void:
	var positive := _new_case("FX02", {"enemy_attack":2})
	_run_until(positive.engine, 6)
	_check(positive.engine.shield_amount("A2", "A1:FX02") == 80 and positive.engine.shield_amount("A3", "A1:FX02") == 80,
		"FX02 first actual HP loss grants 8 shield to both other allies")
	var negative := _new_case("FX02", {"enemy_attack":0, "enemy_target":2})
	_run_until(negative.engine, 6)
	_check(positive.engine.get_counter("A1:FX02", "fx02_used") == 1 and negative.engine.get_counter("A1:FX02", "fx02_used") == 0,
		"FX02 does not consume its once-per-battle trigger without owner's HP loss")
	var expiry := _new_case("FX02", {"enemy_attack":2})
	_run_until(expiry.engine, 46)
	_check(expiry.engine.shield_amount("A2", "A1:FX02") == 0 and _has_expiry(expiry.engine.state.events, "", "A1:FX02"),
		"FX02 ally shields expire at four seconds")


func _test_fx03() -> void:
	var driver_actions := [{"kind":"shield_grant", "target_key":"A1", "amount":10, "expires_tick":100}]
	var positive := _new_case("FX03", {"enemy_attack":2, "owner_hp":800, "ally2_hp":500}, driver_actions)
	_run_until(positive.engine, 6)
	_check(int(positive.engine.unit("A1").hp_tenths) == 820 and int(positive.engine.unit("A2").hp_tenths) == 560,
		"FX03 shield break heals wearer 3 and lowest other ally 6")
	_check(not positive.engine.ready("A1:FX03", "fx03"), "FX03 starts four-second cooldown after shield break")
	var negative := _new_case("FX03", {"enemy_attack":2}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":120, "expires_tick":100}
	])
	_run_until(negative.engine, 6)
	_check(negative.engine.ready("A1:FX03", "fx03") and int(negative.engine.unit("A1").hp_tenths) == 1000,
		"FX03 does not fire while a shield pool remains")
	var expiry := _new_case("FX03", {"enemy_attack":2, "owner_hp":800, "ally2_hp":500}, driver_actions)
	_run_until(expiry.engine, 46)
	_check(expiry.engine.ready("A1:FX03", "fx03"), "FX03 cooldown reopens at four seconds")


func _test_fx05() -> void:
	var heal_owner := [{"kind":"heal", "target_key":"A1", "amount":200}]
	var positive := _new_case("FX05", {"enemy_attack":0, "enemy_target":3, "owner_hp":500, "ally2_hp":500}, heal_owner)
	_run_until(positive.engine, 0)
	_check(int(positive.engine.unit("A2").hp_tenths) == 550, "FX05 transfers half of actual owner healing, capped at 5")
	_check(not positive.engine.ready("A1:FX05", "fx05"), "FX05 starts cooldown after actual healing")
	var heal_ally := [{"kind":"heal", "target_key":"A2", "amount":200}]
	var negative := _new_case("FX05", {"enemy_attack":0, "enemy_target":3, "owner_hp":500, "ally2_hp":500}, heal_ally)
	_run_until(negative.engine, 0)
	_check(int(negative.engine.unit("A3").hp_tenths) == 1000 and negative.engine.ready("A1:FX05", "fx05"),
		"FX05 does not trigger for healing another unit")
	var expiry := _new_case("FX05", {"enemy_attack":0, "enemy_target":3, "owner_hp":500}, heal_owner)
	_run_until(expiry.engine, 30)
	_check(expiry.engine.ready("A1:FX05", "fx05"), "FX05 cooldown reopens at three seconds")


func _test_fx06() -> void:
	var positive := _new_case("FX06", {"enemy_attack":0}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":30, "expires_tick":100}
	])
	_run_until(positive.engine, 0)
	_check(positive.engine.shield_amount("A2", "A1:FX06") == 40, "FX06 grants four shield to the other ally with the least shield")
	_check(not positive.engine.ready("A1:FX06", "fx06"), "FX06 begins three-second cooldown")
	var negative := _new_case("FX06", {"enemy_attack":0}, [
		{"kind":"shield_grant", "target_key":"A2", "amount":30, "expires_tick":100}
	])
	_run_until(negative.engine, 0)
	_check(negative.engine.shield_amount("A3", "A1:FX06") == 0 and negative.engine.ready("A1:FX06", "fx06"),
		"FX06 does not trigger when another unit receives the shield")
	var expiry := _new_case("FX06", {"enemy_attack":0}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":30, "expires_tick":100}
	])
	_run_until(expiry.engine, 20)
	_check(expiry.engine.shield_amount("A2", "A1:FX06") == 0 and _has_expiry(expiry.engine.state.events, "", "A1:FX06"),
		"FX06 distributed shield expires at two seconds")


func _test_fx07() -> void:
	var positive := _new_case("FX07", {"owner_hp":900, "enemy_attack":2}, [
		{"kind":"barrier_grant", "target_key":"A1", "expires_tick":100}
	])
	_run_until(positive.engine, 6)
	_check(int(positive.engine.effective_stats("A2").A) == 6, "FX07 barrier absorbs damage and buffs the highest-A other ally")
	var negative := _new_case("FX07", {"owner_hp":900, "enemy_attack":2}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":120, "expires_tick":100}
	])
	_run_until(negative.engine, 6)
	_check(int(negative.engine.effective_stats("A2").A) == 0, "FX07 does not trigger when a shield, not barrier, absorbs damage")
	var expiry := _new_case("FX07", {"owner_hp":900, "enemy_attack":2}, [
		{"kind":"barrier_grant", "target_key":"A1", "expires_tick":100}
	])
	_run_until(expiry.engine, 36)
	_check(int(expiry.engine.effective_stats("A2").A) == 0 and _has_modifier_expiry(expiry.engine.state.events, "FX07:A1", "A1:FX07"),
		"FX07 ally attack modifier expires at three seconds")


func _test_fx08() -> void:
	var positive := _new_case("FX08", {"enemy_attack":0}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"burn", "layers":1, "expires_tick":50}
	])
	_run_until(positive.engine, 0)
	_check(int(positive.engine.effective_stats("A2").R) == 3 and int(positive.engine.effective_stats("A3").R) == 3,
		"FX08 first transition into a negative status buffs teammates' armor")
	var negative := _new_case("FX08", {"enemy_attack":0}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"burn", "layers":1, "expires_tick":50}
	], {"tick":40, "actions":[{"kind":"status_add", "target_key":"A1", "status_id":"burn", "layers":1, "expires_tick":70}]})
	_run_until(negative.engine, 40)
	_check(int(negative.engine.effective_stats("A2").R) == 0 and negative.engine.ready("A1:FX08", "fx08"),
		"FX08 does not retrigger when another layer is added to an existing status")
	var expiry := _new_case("FX08", {"enemy_attack":0}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"burn", "layers":1, "expires_tick":50}
	])
	_run_until(expiry.engine, 30)
	_check(int(expiry.engine.effective_stats("A2").R) == 0 and _has_modifier_expiry(expiry.engine.state.events, "FX08:A1:A2", "A1:FX08"),
		"FX08 teammate armor bonus expires at three seconds")


func _test_fx12() -> void:
	var enemy_shield := [{"kind":"shield_grant", "target_key":"B1", "amount":10, "expires_tick":100}]
	var positive := _new_case("FX12", {"enemy_attack":0, "owner_hp":500, "ally2_hp":500}, enemy_shield)
	_run_until(positive.engine, 6)
	_check(int(positive.engine.unit("A1").hp_tenths) == 540 and int(positive.engine.unit("A2").hp_tenths) == 540,
		"FX12 breaking an enemy shield heals all living allies four")
	_check(not positive.engine.ready("A1:FX12", "fx12"), "FX12 starts four-second cooldown")
	var negative := _new_case("FX12", {"enemy_attack":0, "owner_hp":500, "ally2_hp":500}, [
		{"kind":"shield_grant", "target_key":"B1", "amount":120, "expires_tick":100}
	])
	_run_until(negative.engine, 6)
	_check(int(negative.engine.unit("A1").hp_tenths) == 500 and int(negative.engine.unit("A2").hp_tenths) == 500
		and negative.engine.ready("A1:FX12", "fx12"), "FX12 does not trigger while enemy shield remains positive")
	var expiry := _new_case("FX12", {"enemy_attack":0}, enemy_shield)
	_run_until(expiry.engine, 44)
	_check(not expiry.engine.ready("A1:FX12", "fx12"), "FX12 cooldown remains active before four seconds")
	_run_until(expiry.engine, 45)
	_check(expiry.engine.ready("A1:FX12", "fx12"), "FX12 cooldown reopens at four seconds")


func _test_fx09() -> void:
	var positive := _new_case("FX09", {"enemy_attack":0, "ally2_hp":500, "ally3_hp":400}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A2", "status_id":"silence", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A3", "status_id":"poison", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A3", "status_id":"chill", "layers":1, "expires_tick":100},
		{"kind":"status_remove", "target_key":"A1", "status_id":"bleed", "layers":1}
	])
	_run_until(positive.engine, 0)
	_check(_status_count(positive.engine.unit("A3"), "poison") == 0
		and _status_count(positive.engine.unit("A3"), "chill") == 1
		and _status_count(positive.engine.unit("A2"), "silence") == 1
		and positive.engine.get_counter("A1:FX09", "fx09_charge") == 1,
		"FX09 grants its next-hit charge after active self-cleanse and removes the oldest negative state from the lowest-health debuffed ally")
	_run_until(positive.engine, 6)
	var positive_ledger := _hp_loss_ledger(positive.engine, "B1")
	_check(positive_ledger.size() == 1 and int(positive_ledger[0].loss) == 70
		and positive.engine.get_counter("A1:FX09", "fx09_charge") == 0,
		"FX09 adds five to the next natural main hit and consumes its charge on hit")

	var no_ally := _new_case("FX09", {"enemy_attack":0, "owner_attack":2}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"burn", "layers":1, "expires_tick":100},
		{"kind":"status_remove", "target_key":"A1", "status_id":"burn", "layers":1}
	])
	_run_until(no_ally.engine, 6)
	var no_ally_ledger := _hp_loss_ledger(no_ally.engine, "B1")
	_check(no_ally_ledger.size() == 1 and int(no_ally_ledger[0].loss) == 70,
		"FX09 keeps its self-damage bonus when there is no debuffed teammate to cleanse")

	var unrelated := _new_case("FX09", {"enemy_attack":0, "owner_attack":2}, [
		{"kind":"status_add", "target_key":"A2", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_remove", "target_key":"A1", "status_id":"bleed", "layers":1}
	])
	_run_until(unrelated.engine, 6)
	var unrelated_ledger := _hp_loss_ledger(unrelated.engine, "B1")
	_check(unrelated_ledger.size() == 1 and int(unrelated_ledger[0].loss) == 20
		and _status_count(unrelated.engine.unit("A2"), "bleed") == 1,
		"FX09 ignores a removal request that actually removes no negative-state layer")

	var expired := _new_case("FX09", {"enemy_attack":0, "owner_attack":2, "owner_speed":30}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_remove", "target_key":"A1", "status_id":"bleed", "layers":1}
	])
	_run_until(expired.engine, 30)
	var expired_ledger := _hp_loss_ledger(expired.engine, "B1")
	_check(expired_ledger.size() == 1 and int(expired_ledger[0].loss) == 20,
		"FX09 does not apply the stored damage bonus when the next natural hit lands at the exact three-second expiry")

	var cooldown := _new_case("FX09", {"enemy_attack":0, "owner_attack":2}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_remove", "target_key":"A1", "status_id":"bleed", "layers":1}
	], {"tick":40, "actions":[
		{"kind":"status_add", "target_key":"A1", "status_id":"poison", "layers":1, "expires_tick":100},
		{"kind":"status_remove", "target_key":"A1", "status_id":"poison", "layers":1}
	]})
	_run_until(cooldown.engine, 42)
	var cooldown_ledger := _hp_loss_ledger(cooldown.engine, "B1")
	var tick42_loss := 0
	for entry: Dictionary in cooldown_ledger:
		if int(entry.tick) == 42: tick42_loss += int(entry.loss)
	_check(tick42_loss == 70, "FX09 cooldown expires at four seconds and permits the next queued charge")


func _test_fx13() -> void:
	var positive := _new_case("FX13", {"enemy_attack":0, "enemy_armor":3}, [
		{"kind":"barrier_grant", "target_key":"B1", "expires_tick":100}
	])
	_run_until(positive.engine, 6)
	_check(bool(positive.engine.unit("A2").barrier.active)
		and int(positive.engine.unit("B1").hp_tenths) == 1000,
		"FX13 grants a two-second barrier to the lowest-health teammate when an enemy barrier fully cancels the natural main hit")

	var no_barrier := _new_case("FX13", {"enemy_attack":0})
	_run_until(no_barrier.engine, 6)
	_check(not bool(no_barrier.engine.unit("A2").barrier.active)
		and no_barrier.engine.ready("A1:FX13", "fx13"),
		"FX13 does not trigger or spend cooldown when the natural hit is not barrier-absorbed")

	var expiry := _new_case("FX13", {"enemy_attack":0}, [
		{"kind":"barrier_grant", "target_key":"B1", "expires_tick":100}
	], {"tick":62, "actions":[{"kind":"barrier_grant", "target_key":"B1", "expires_tick":100}]})
	_run_until(expiry.engine, 6)
	_check(bool(expiry.engine.unit("A2").barrier.active)
		and int(expiry.engine.unit("A2").barrier.expires_tick) == 26,
		"FX13 teammate barrier lasts exactly two seconds")
	_run_until(expiry.engine, 26)
	_check(not bool(expiry.engine.unit("A2").barrier.active), "FX13 barrier expires at its exact authored tick")
	_run_until(expiry.engine, 66)
	var grants := 0
	for event in expiry.engine.state.events:
		if str(event.get("kind", "")) == "shield_gained" and str(event.get("source_binding_key", "")) == "A1:FX13": grants += 1
	_check(grants == 2, "FX13 cooldown permits a new barrier at the exact six-second boundary")


func _test_fx17() -> void:
	var positive := _new_case("FX17", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"bleed", "layers":2, "expires_tick":100},
		{"kind":"status_add", "target_key":"A2", "status_id":"bleed", "layers":2, "expires_tick":100},
		{"kind":"status_add", "target_key":"B1", "status_id":"bleed", "layers":1, "expires_tick":100}
	])
	_run_until(positive.engine, 6)
	_check(_status_count(positive.engine.unit("A1"), "bleed") == 1
		and _status_count(positive.engine.unit("A2"), "bleed") == 1
		and _status_count(positive.engine.unit("B1"), "bleed") == 1
		and not positive.engine.ready("A1:FX17", "fx17"),
		"FX17 consumes one bleed layer on the wearer and lowest-health ally after hitting a bleeding enemy")

	var ally_only := _new_case("FX17", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"status_add", "target_key":"A2", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"B1", "status_id":"bleed", "layers":1, "expires_tick":100}
	])
	_run_until(ally_only.engine, 6)
	_check(_status_count(ally_only.engine.unit("A2"), "bleed") == 0,
		"FX17 still cleanses the lowest-health ally when the wearer has no bleed")

	var no_bleed := _new_case("FX17", {"enemy_attack":0}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A2", "status_id":"bleed", "layers":1, "expires_tick":100}
	])
	_run_until(no_bleed.engine, 6)
	_check(_status_count(no_bleed.engine.unit("A1"), "bleed") == 1
		and _status_count(no_bleed.engine.unit("A2"), "bleed") == 1
		and no_bleed.engine.ready("A1:FX17", "fx17"),
		"FX17 does not cleanse or spend cooldown when its natural-hit target is not bleeding")

	var expired := _new_case("FX17", {"enemy_attack":0, "owner_slow":true}, [
		{"kind":"status_add", "target_key":"A2", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"B1", "status_id":"bleed", "layers":1, "expires_tick":5}
	])
	_run_until(expired.engine, 10)
	_check(_status_count(expired.engine.unit("A2"), "bleed") == 1
		and expired.engine.ready("A1:FX17", "fx17"),
		"FX17 does not trigger after the target's bleed expires before the natural hit")

	var cooldown := _new_case("FX17", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A2", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"B1", "status_id":"bleed", "layers":1, "expires_tick":100}
	], {"tick":35, "actions":[
		{"kind":"status_add", "target_key":"A1", "status_id":"bleed", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A2", "status_id":"bleed", "layers":1, "expires_tick":100}
	]})
	_run_until(cooldown.engine, 6)
	_run_until(cooldown.engine, 36)
	_check(_status_count(cooldown.engine.unit("A1"), "bleed") == 0
		and _status_count(cooldown.engine.unit("A2"), "bleed") == 0,
		"FX17 cooldown expires at three seconds and permits the next eligible natural hit")


func _test_fx20() -> void:
	var positive := _new_case("FX20", {"enemy_attack":0, "ally2_hp":500, "ally2_speed":300, "ally3_speed":400}, [
		{"kind":"status_add", "target_key":"B1", "status_id":"bleed", "layers":2, "expires_tick":100},
		{"kind":"status_add", "target_key":"B1", "status_id":"chill", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A2", "status_id":"poison", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A3", "status_id":"poison", "layers":2, "expires_tick":100},
		{"kind":"status_add", "target_key":"A3", "status_id":"silence", "layers":1, "expires_tick":100}
	])
	_run_until(positive.engine, 6)
	_check(_status_count(positive.engine.unit("A3"), "poison") == 0
		and _status_count(positive.engine.unit("A3"), "silence") == 0
		and _status_count(positive.engine.unit("A2"), "poison") == 1
		and not positive.engine.ready("A1:FX20", "fx20"),
		"FX20 clears every negative status from the longest-base-T debuffed ally when hitting an enemy with two distinct negative statuses")

	var one_type := _new_case("FX20", {"enemy_attack":0}, [
		{"kind":"status_add", "target_key":"B1", "status_id":"poison", "layers":2, "expires_tick":100},
		{"kind":"status_add", "target_key":"A2", "status_id":"silence", "layers":1, "expires_tick":100}
	])
	_run_until(one_type.engine, 6)
	_check(_status_count(one_type.engine.unit("A2"), "silence") == 1
		and one_type.engine.ready("A1:FX20", "fx20"),
		"FX20 counts distinct negative status types, not layers, and leaves cooldown ready")

	var expired := _new_case("FX20", {"enemy_attack":0, "owner_slow":true}, [
		{"kind":"status_add", "target_key":"B1", "status_id":"poison", "layers":1, "expires_tick":5},
		{"kind":"status_add", "target_key":"B1", "status_id":"chill", "layers":1, "expires_tick":5},
		{"kind":"status_add", "target_key":"A2", "status_id":"silence", "layers":1, "expires_tick":100}
	])
	_run_until(expired.engine, 10)
	_check(_status_count(expired.engine.unit("A2"), "silence") == 1
		and expired.engine.ready("A1:FX20", "fx20"),
		"FX20 does not trigger after the enemy's qualifying negative states expire")

	var cooldown := _new_case("FX20", {"enemy_attack":0, "ally3_speed":400}, [
		{"kind":"status_add", "target_key":"B1", "status_id":"poison", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"B1", "status_id":"rooted", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A3", "status_id":"silence", "layers":1, "expires_tick":100}
	], {"tick":65, "actions":[
		{"kind":"status_add", "target_key":"A3", "status_id":"poison", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A3", "status_id":"chill", "layers":1, "expires_tick":100}
	]})
	_run_until(cooldown.engine, 6)
	_run_until(cooldown.engine, 66)
	_check(_status_count(cooldown.engine.unit("A3"), "poison") == 0
		and _status_count(cooldown.engine.unit("A3"), "chill") == 0,
		"FX20 cooldown allows a fresh cleanse at its six-second boundary")


func _test_fx22() -> void:
	var positive := _new_case("FX22", {"enemy_attack":0, "owner_target_slot":1}, [
		{"kind":"damage", "target_key":"B1", "amount":1000, "damage_type":"fixed", "source_key":"A2"}
	])
	_run_until(positive.engine, 6)
	_check(int(positive.engine.get_counter("A1:FX22", "fx22_target_slot")) == 0
		and bool(positive.engine.unit("A2").barrier.active)
		and int(positive.engine.unit("A2").barrier.expires_tick) == 36,
		"FX22 opens on the current target's final departure and protects the lowest-health ally after the next natural hit")

	var no_window := _new_case("FX22", {"enemy_attack":0})
	_run_until(no_window.engine, 6)
	_check(not bool(no_window.engine.unit("A2").barrier.active),
		"FX22 does not grant a barrier without a prior current-target final departure")

	var expired := _new_case("FX22", {"enemy_attack":0, "owner_speed":40, "owner_target_slot":1}, [
		{"kind":"damage", "target_key":"B1", "amount":1000, "damage_type":"fixed", "source_key":"A2"}
	])
	_run_until(expired.engine, 40)
	_check(not bool(expired.engine.unit("A2").barrier.active),
		"FX22 rejects a natural hit landing at the exact four-second window expiry")


func _test_fx18() -> void:
	var owner_silenced := [{"kind":"status_add", "target_key":"A1", "status_id":"silence", "layers":1, "expires_tick":100}]
	var positive := _new_case("FX18", {"enemy_attack":0}, owner_silenced)
	_run_until(positive.engine, 0)
	_check(int(positive.engine.effective_stats("A2").T_ticks) == 197 and int(positive.engine.effective_stats("A3").T_ticks) == 197,
		"FX18 first silence transition slows both other allies by three ticks")
	var negative := _new_case("FX18", {"enemy_attack":0}, [
		{"kind":"status_add", "target_key":"A2", "status_id":"silence", "layers":1, "expires_tick":100}
	])
	_run_until(negative.engine, 0)
	_check(int(negative.engine.effective_stats("A2").T_ticks) == 200,
		"FX18 does not trigger when a teammate rather than wearer becomes silenced")
	var expiry := _new_case("FX18", {"enemy_attack":0}, owner_silenced)
	_run_until(expiry.engine, 20)
	_check(int(expiry.engine.effective_stats("A2").T_ticks) == 200 and _has_modifier_expiry(expiry.engine.state.events, "FX18:A1:A2", "A1:FX18"),
		"FX18 teammate timing penalty expires after two seconds")


func _test_eq25() -> void:
	var positive := _new_case("EQ25", {"enemy_attack":0, "owner_hp":300, "owner_attack":0}, [
		{"kind":"self_loss", "amount":10}
	])
	_run_until(positive.engine, 0)
	_check(int(positive.engine.unit("A1").hp_tenths) == 370 and bool(positive.engine.unit("A1").barrier.active),
		"EQ25 post-loss low-health trigger heals eight and grants barrier")
	var negative := _new_case("EQ25", {"enemy_attack":0, "owner_hp":400, "owner_attack":0}, [
		{"kind":"self_loss", "amount":10}
	])
	_run_until(negative.engine, 0)
	_check(int(negative.engine.unit("A1").hp_tenths) == 390 and not bool(negative.engine.unit("A1").barrier.active),
		"EQ25 does not trigger above the 35 percent threshold")
	var expiry := _new_case("EQ25", {"enemy_attack":0, "owner_hp":300, "owner_attack":0}, [
		{"kind":"self_loss", "amount":10}
	])
	_run_until(expiry.engine, 20)
	_check(not bool(expiry.engine.unit("A1").barrier.active),
		"EQ25 barrier expires at two seconds")


func _test_eq18() -> void:
	var positive := _new_case("EQ18", {"enemy_attack":0, "owner_hp":500})
	_run_until(positive.engine, 6)
	_check(int(positive.engine.unit("A1").hp_tenths) == 540, "EQ18 heals owner 4 after own natural hit")
	var negative := _new_case("EQ18", {"owner_slow":true, "enemy_attack":2})
	_run_until(negative.engine, 6)
	_check(int(negative.engine.unit("A1").hp_tenths) == 980, "EQ18 does not heal from an enemy natural hit")
	var expiry := _new_case("EQ18", {"enemy_attack":0, "owner_hp":500})
	_run_until(expiry.engine, 47)
	var before_boundary := int(expiry.engine.unit("A1").hp_tenths)
	_run_until(expiry.engine, 48)
	var late_hit := false
	for event in expiry.engine.state.events:
		if event.kind == "hit" and event.source_key == "A1" and int(event.tick) >= 48: late_hit = true
	_check(before_boundary == 540 and int(expiry.engine.unit("A1").hp_tenths) == 580 and late_hit,
		"EQ18 cooldown expires and permits the next eligible natural hit")


func _test_eq22() -> void:
	var positive := _new_case("EQ22", {"enemy_attack":0})
	_run_until(positive.engine, 6)
	_check(_status_count(positive.engine.unit("B1"), "bleed") == 1,
		"EQ22 applies bleed only after natural main damage causes actual HP loss")
	var blocked := _new_case("EQ22", {"enemy_attack":0}, [
		{"kind":"barrier_grant", "target_key":"B1", "expires_tick":100}
	])
	_run_until(blocked.engine, 6)
	_check(_status_count(blocked.engine.unit("B1"), "bleed") == 0 and blocked.engine.ready("A1:EQ22", "eq22"),
		"EQ22 does not apply bleed or consume cooldown when barrier fully prevents loss")
	var expiry := _new_case("EQ22", {"enemy_attack":0})
	var slow_expiry := _new_case("EQ22", {"owner_speed":36, "enemy_attack":0})
	_run_until(slow_expiry.engine, 66)
	_check(_status_count(slow_expiry.engine.unit("B1"), "bleed") == 0 and _has_expiry(slow_expiry.engine.state.events, "bleed", "A1:EQ22"),
		"EQ22 bleed expires after three seconds")


func _test_eq23() -> void:
	var positive := _new_case("EQ23", {"enemy_attack":0, "owner_hp":1000, "owner_attack":0}, [
		{"kind":"self_loss", "amount":300}
	], {"tick":10, "actions":[{"kind":"heal", "target_key":"A1", "amount":300}]})
	_run_until(positive.engine, 0)
	_check(int(positive.engine.unit("A1").hp_tenths) == 700 and int(positive.engine.effective_stats("A1").get("A_tenths", -1)) == 37,
		"EQ23 derives 0.1 attack increments from missing HP divided by eight")
	_run_until(positive.engine, 10)
	_check(int(positive.engine.unit("A1").hp_tenths) == 1000 and int(positive.engine.effective_stats("A1").get("A_tenths", -1)) == 0,
		"EQ23 removes its dynamic attack modifier immediately after healing (hp=%d A=%s mods=%s)" % [int(positive.engine.unit("A1").hp_tenths), str(positive.engine.effective_stats("A1")), str(positive.engine.unit("A1").modifiers)])
	var negative := _new_case("EQ23", {"enemy_attack":0, "owner_attack":0})
	_run_until(negative.engine, 0)
	_check(int(negative.engine.effective_stats("A1").get("A_tenths", -1)) == 0,
		"EQ23 grants no missing-life attack bonus at full health")


func _test_eq34() -> void:
	var positive := _new_case("EQ34", {"enemy_attack":0, "owner_hp":500})
	_run_until(positive.engine, 6)
	_check(int(positive.engine.unit("A1").hp_tenths) == 506,
		"EQ34 heals thirty percent of actual natural-attack HP loss (hp=%d)" % int(positive.engine.unit("A1").hp_tenths))
	var barrier := _new_case("EQ34", {"enemy_attack":0, "owner_hp":500}, [
		{"kind":"barrier_grant", "target_key":"B1", "expires_tick":100}
	])
	_run_until(barrier.engine, 6)
	_check(int(barrier.engine.unit("A1").hp_tenths) == 500 and barrier.engine.ready("A1:EQ34", "eq34"),
		"EQ34 does not heal or consume cooldown when main damage causes no HP loss")
	var expiry := _new_case("EQ34", {"enemy_attack":0, "owner_hp":500})
	_run_until(expiry.engine, 18)
	_check(int(expiry.engine.unit("A1").hp_tenths) == 512,
		"EQ34 reopens after its one-second cooldown and heals on the next natural hit")


func _test_eq36() -> void:
	var broken_by_damage := _new_case("EQ36", {"enemy_attack":2, "owner_attack":1, "owner_speed":40}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":10, "expires_tick":100}
	])
	_run_until(broken_by_damage.engine, 6)
	_check(int(broken_by_damage.engine.effective_stats("A1").T_ticks) == 5
		and int(broken_by_damage.engine.unit("A1").hp_tenths) == 990,
		"EQ36 reduces T by 35 ticks after damage exhausts the wearer's shield")
	_run_until(broken_by_damage.engine, 46)
	var natural_ledger := _hp_loss_ledger(broken_by_damage.engine, "B1")
	_check(natural_ledger.size() == 2 and int(natural_ledger[0].tick) == 40 and int(natural_ledger[1].tick) == 46,
		"EQ36's haste takes effect at the next attack schedule (natural hits=%s)" % str(natural_ledger))
	_check(int(broken_by_damage.engine.effective_stats("A1").T_ticks) == 40
		and broken_by_damage.engine.ready("A1:EQ36", "eq36")
		and _has_modifier_expiry(broken_by_damage.engine.state.events, "EQ36:A1:haste", "A1:EQ36"),
		"EQ36 haste and cooldown both expire after four seconds")
	var clear := _new_case("EQ36", {"enemy_attack":0, "owner_speed":40}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":20, "expires_tick":100}
	], {"tick":6, "actions":[{"kind":"shield_clear", "target_key":"A1"}]})
	_run_until(clear.engine, 6)
	_check(int(clear.engine.effective_stats("A1").T_ticks) == 5 and clear.engine.shield_amount("A1") == 0,
		"EQ36 also triggers when an explicit clear removes the final shield")
	var no_break := _new_case("EQ36", {"enemy_attack":0, "owner_speed":40})
	_run_until(no_break.engine, 6)
	_check(int(no_break.engine.effective_stats("A1").T_ticks) == 40 and no_break.engine.ready("A1:EQ36", "eq36"),
		"EQ36 does not grant haste when no shield-breaking event occurs")


func _test_fx31() -> void:
	var positive := _new_case("FX31", {"enemy_attack":0, "ally2_hp":500})
	_run_until(positive.engine, 6)
	_check(int(positive.engine.unit("A2").hp_tenths) == 540,
		"FX31 at full wearer health heals the lowest-health other ally")
	var not_full := _new_case("FX31", {"enemy_attack":0, "owner_hp":999, "ally2_hp":500})
	_run_until(not_full.engine, 6)
	_check(int(not_full.engine.unit("A2").hp_tenths) == 500 and not_full.engine.ready("A1:FX31", "fx31"),
		"FX31 does not trigger when wearer is missing even a small amount of health")
	var expiry := _new_case("FX31", {"enemy_attack":0, "ally2_hp":500})
	_run_until(expiry.engine, 35)
	_check(int(expiry.engine.unit("A2").hp_tenths) == 540,
		"FX31 does not retrigger before three-second cooldown expiry")


func _test_fx34() -> void:
	var positive := _new_case("FX34", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":120, "expires_tick":100}
	])
	_run_until(positive.engine, 6)
	_check(positive.engine.shield_amount("A1") == 60 and int(positive.engine.unit("A2").hp_tenths) == 540
		and int(positive.engine.unit("A3").hp_tenths) == 1000,
		"FX34 spends six shield after natural hit to heal every other living ally (shield=%d hp2=%d hp3=%d)" % [positive.engine.shield_amount("A1"), int(positive.engine.unit("A2").hp_tenths), int(positive.engine.unit("A3").hp_tenths)])
	var insufficient := _new_case("FX34", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":119, "expires_tick":100}
	])
	_run_until(insufficient.engine, 6)
	_check(insufficient.engine.shield_amount("A1") == 119 and int(insufficient.engine.unit("A2").hp_tenths) == 500
		and insufficient.engine.ready("A1:FX34", "fx34"),
		"FX34 does not activate below twelve shield")
	var expiry := _new_case("FX34", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":120, "expires_tick":100}
	], {"tick":45, "actions":[{"kind":"shield_grant", "target_key":"A1", "amount":180, "expires_tick":100}]})
	_run_until(expiry.engine, 48)
	_check(int(expiry.engine.unit("A2").hp_tenths) == 580 and not expiry.engine.ready("A1:FX34", "fx34"),
		"FX34 cooldown gates repeated conversions until four seconds")


func _test_eq42() -> void:
	var positive := _new_case("EQ42", {"enemy_attack":0, "owner_hp":900, "owner_attack":0}, [
		{"kind":"self_loss", "amount":100}
	])
	_run_until(positive.engine, 29)
	_check(int(positive.engine.unit("A1").hp_tenths) == 800,
		"EQ42 does not heal before three-second check or within the two-second no-loss window")
	_run_until(positive.engine, 30)
	_check(int(positive.engine.unit("A1").hp_tenths) == 850,
		"EQ42 heals five after two seconds without actual HP loss")
	_run_until(positive.engine, 60)
	_check(int(positive.engine.unit("A1").hp_tenths) == 900,
		"EQ42 continues healing at each three-second check while eligible")
	var interrupted := _new_case("EQ42", {"enemy_attack":0, "owner_hp":900, "owner_attack":0}, [],
		{"tick":20, "actions":[{"kind":"self_loss", "amount":100}]})
	_run_until(interrupted.engine, 30)
	_check(int(interrupted.engine.unit("A1").hp_tenths) == 800,
		"EQ42 is suppressed when actual loss occurred within the preceding two seconds (hp=%d last_loss=%d)" % [int(interrupted.engine.unit("A1").hp_tenths), interrupted.engine.get_counter("A1:EQ42", "eq42_last_loss_tick")])
	_run_until(interrupted.engine, 60)
	_check(int(interrupted.engine.unit("A1").hp_tenths) == 850,
		"EQ42 resumes at its next three-second check after the full two-second no-loss interval (hp=%d last_loss=%d)" % [int(interrupted.engine.unit("A1").hp_tenths), interrupted.engine.get_counter("A1:EQ42", "eq42_last_loss_tick")])


func _test_fx33() -> void:
	var positive := _new_case("FX33", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"heal", "target_key":"A1", "amount":100}
	])
	_run_until(positive.engine, 0)
	_check(int(positive.engine.unit("A2").hp_tenths) == 550,
		"FX33 transfers half actual overflow to the lowest-health other ally")
	var no_overheal := _new_case("FX33", {"enemy_attack":0, "owner_hp":900, "ally2_hp":500}, [
		{"kind":"heal", "target_key":"A1", "amount":100}
	])
	_run_until(no_overheal.engine, 0)
	_check(int(no_overheal.engine.unit("A2").hp_tenths) == 500 and no_overheal.engine.ready("A1:FX33", "fx33"),
		"FX33 does not trigger or consume cooldown on healing without overflow")
	var cooldown := _new_case("FX33", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"heal", "target_key":"A1", "amount":100}
	], {"tick":10, "actions":[{"kind":"heal", "target_key":"A1", "amount":100}]})
	_run_until(cooldown.engine, 10)
	_check(int(cooldown.engine.unit("A2").hp_tenths) == 550 and not cooldown.engine.ready("A1:FX33", "fx33"),
		"FX33 ignores an overflow during the two-second cooldown")


func _test_fx36() -> void:
	var positive := _new_case("FX36", {"enemy_attack":0, "owner_hp":900}, [
		{"kind":"heal", "target_key":"A1", "amount":100}
	], {"owner_key":"A2"})
	_run_until(positive.engine, 0)
	_check(positive.engine.shield_amount("A2", "A1:FX36") == 60,
		"FX36 grants healer sixty percent of actual received healing as shield")
	var self_heal := _new_case("FX36", {"enemy_attack":0, "owner_hp":900}, [
		{"kind":"heal", "target_key":"A1", "amount":100}
	])
	_run_until(self_heal.engine, 0)
	_check(self_heal.engine.shield_amount("A1", "A1:FX36") == 0,
		"FX36 does not reward self-healing")
	var expiry := _new_case("FX36", {"enemy_attack":0, "owner_hp":900}, [
		{"kind":"heal", "target_key":"A1", "amount":100}
	], {"owner_key":"A2"})
	_run_until(expiry.engine, 30)
	_check(expiry.engine.shield_amount("A2", "A1:FX36") == 0,
		"FX36 healer shield expires after three seconds")


func _test_fx43() -> void:
	var positive := _new_case("FX43", {"enemy_attack":0, "ally2_hp":500, "ally3_hp":500}, [
		{"kind":"heal", "target_key":"A2", "amount":100},
		{"kind":"heal", "target_key":"A2", "amount":100},
		{"kind":"heal", "target_key":"A3", "amount":100}
	])
	_run_until(positive.engine, 0)
	_check(bool(positive.engine.unit("A2").barrier.active) and bool(positive.engine.unit("A3").barrier.active),
		"FX43 grants one barrier independently to each other ally after actual healing (A2=%s A3=%s c2=%d c3=%d)" % [str(positive.engine.unit("A2").barrier), str(positive.engine.unit("A3").barrier), positive.engine.get_counter("A1:FX43", "fx43_recipient_A2"), positive.engine.get_counter("A1:FX43", "fx43_recipient_A3")])
	var cycle := _new_case("FX43", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"heal", "target_key":"A2", "amount":100}
	], {"handlers":[
		{"logic_handler":"fx43_cycle_to_owner", "handler":FX43CycleToOwner.new(), "bindings":[
			{"content_id":"FIXTURE_FX43_CYCLE_TO_OWNER", "logic_handler":"fx43_cycle_to_owner", "source_key":"A2:FX43_CYCLE", "owner_key":"A2", "kind":"slot"}]},
		{"logic_handler":"fx43_cycle_back", "handler":FX43CycleBack.new(), "bindings":[
			{"content_id":"FIXTURE_FX43_CYCLE_BACK", "logic_handler":"fx43_cycle_back", "source_key":"A1:FX43_CYCLE_BACK", "owner_key":"A1", "kind":"slot"}]}
	]})
	_run_until(cycle.engine, 0)
	_check(bool(cycle.engine.unit("A2").barrier.active)
		and cycle.engine.get_counter("A1:FX43", "fx43_recipient_A2") == 1
		and _hp_loss_ledger(cycle.engine, "A2").is_empty(),
		"FX43 root lineage permits the sibling recipient but blocks an A1→A2→A1→A2 re-entry")
	var overheal := _new_case("FX43", {"enemy_attack":0}, [
		{"kind":"heal", "target_key":"A2", "amount":100}
	])
	_run_until(overheal.engine, 0)
	_check(not bool(overheal.engine.unit("A2").barrier.active),
		"FX43 does not consume a recipient's once-only grant for overflow-only healing")
	var expiry := _new_case("FX43", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"heal", "target_key":"A2", "amount":100}
	], {"tick":20, "actions":[{"kind":"heal", "target_key":"A2", "amount":100}]})
	_run_until(expiry.engine, 20)
	_check(not bool(expiry.engine.unit("A2").barrier.active)
		and expiry.engine.get_counter("A1:FX43", "fx43_recipient_A2") == 1,
		"FX43 barrier expires at two seconds without re-arming that recipient")


func _test_fx44() -> void:
	var positive := _new_case("FX44", {"enemy_attack":0, "owner_hp":500, "ally2_hp":800}, [
		{"kind":"shield_grant", "target_key":"A2", "amount":100, "expires_tick":100}
	])
	_run_until(positive.engine, 0)
	_check(int(positive.engine.unit("A1").hp_tenths) == 540,
		"FX44 heals wearer forty percent of actual new shield given to a healthier ally")
	var wrong_order := _new_case("FX44", {"enemy_attack":0, "owner_hp":900, "ally2_hp":800}, [
		{"kind":"shield_grant", "target_key":"A2", "amount":100, "expires_tick":100}
	])
	_run_until(wrong_order.engine, 0)
	_check(int(wrong_order.engine.unit("A1").hp_tenths) == 900 and wrong_order.engine.ready("A1:FX44", "fx44"),
		"FX44 does not trigger when wearer is not lower-health than shield recipient")
	var refresh := _new_case("FX44", {"enemy_attack":0, "owner_hp":500, "ally2_hp":800}, [
		{"kind":"shield_grant", "target_key":"A2", "amount":100, "expires_tick":100}
	], {"tick":30, "actions":[{"kind":"shield_grant", "target_key":"A2", "amount":200, "expires_tick":100}]})
	_run_until(refresh.engine, 30)
	_check(int(refresh.engine.unit("A1").hp_tenths) == 580,
		"FX44 cooldown expires and counts only a positive shield-value increase")


func _test_eq37() -> void:
	var positive := _new_case("EQ37", {"enemy_attack":0})
	_run_until(positive.engine, 0)
	_check(int(positive.engine.effective_stats("A1").A) == 7,
		"EQ37 grants five attack while wearer has no negative status")
	var active := _new_case("EQ37", {"enemy_attack":0}, [
		{"kind":"status_add", "target_key":"A1", "status_id":"poison", "layers":1, "expires_tick":20}
	])
	_run_until(active.engine, 0)
	_check(int(active.engine.effective_stats("A1").A) == 2,
		"EQ37 suppresses its attack bonus while any negative status is active")
	_run_until(active.engine, 20)
	_check(int(active.engine.effective_stats("A1").A) == 7,
		"EQ37 restores its attack bonus immediately after the final status expires")


func _test_fx21() -> void:
	var positive := _new_case("FX21", {"enemy_attack":0})
	_run_until(positive.engine, 18)
	_check(int(positive.engine.effective_stats("A2").T_ticks) == 197
		and int(positive.engine.effective_stats("A3").T_ticks) == 197,
		"FX21 grants timing reduction to teammates currently attacking the same target after three natural hits")
	var no_hits := _new_case("FX21", {"owner_slow":true, "enemy_attack":0})
	_run_until(no_hits.engine, 30)
	_check(int(no_hits.engine.effective_stats("A2").T_ticks) == 200 and no_hits.engine.ready("A1:FX21", "fx21"),
		"FX21 does not accumulate without natural hit events")
	var expiry := _new_case("FX21", {"enemy_attack":0})
	_run_until(expiry.engine, 58)
	_check(int(expiry.engine.effective_stats("A2").T_ticks) == 200
		and _has_modifier_expiry(expiry.engine.state.events, "FX21:A1:A2:1", "A1:FX21"),
		"FX21 timing modifier expires at four seconds")


func _test_eq43() -> void:
	var positive := _new_case("EQ43", {"enemy_attack":0})
	_run_until(positive.engine, 12)
	_check(_status_count(positive.engine.unit("B1"), "burn") == 1
		and positive.engine.get_counter("A1:EQ43", "eq43_natural_hit_count") == 2,
		"EQ43 counts each natural hit but applies burn only on odd numbered hits")
	var no_attack := _new_case("EQ43", {"owner_slow":true, "enemy_attack":0})
	_run_until(no_attack.engine, 30)
	_check(_status_count(no_attack.engine.unit("B1"), "burn") == 0
		and no_attack.engine.get_counter("A1:EQ43", "eq43_natural_hit_count") == 0,
		"EQ43 does not count or ignite without natural hit events")
	var expiry := _new_case("EQ43", {"owner_speed":36, "enemy_attack":0})
	_run_until(expiry.engine, 66)
	_check(_status_count(expiry.engine.unit("B1"), "burn") == 0
		and _has_expiry(expiry.engine.state.events, "burn", "A1:EQ43"),
		"EQ43 burn expires three seconds after its eligible odd hit")


func _test_eq44() -> void:
	var selected := _new_case("EQ44", {"owner_hp":10, "owner_attack":0, "owner_target_slot":2, "enemy_attack":0}, [
		{"kind":"self_loss", "target_key":"A1", "amount":10}
	])
	_run_until(selected.engine, 0)
	var selected_ledger := _hp_loss_ledger(selected.engine, "B2")
	_check(int(selected.engine.unit("B2").hp_tenths) == 880 and selected_ledger.size() == 1
		and int(selected_ledger[0].loss) == 120 and str(selected_ledger[0].damage_type) == "lightning"
		and selected.engine.get_counter("A1:EQ44", "eq44_used") == 1,
		"EQ44 final departure deals exactly twelve lightning HP to the recorded living target once")

	var fallback := _new_case("EQ44", {"owner_hp":10, "owner_attack":0, "owner_target_slot":2, "enemy_attack":0}, [
		{"kind":"damage", "target_key":"B2", "amount":1000, "damage_type":"fixed", "source_key":"A2"},
		{"kind":"self_loss", "target_key":"A1", "amount":10}
	])
	_run_until(fallback.engine, 0)
	var fallback_ledger := _hp_loss_ledger(fallback.engine, "B1")
	_check(int(fallback.engine.unit("B2").hp_tenths) == 0 and int(fallback.engine.unit("B1").hp_tenths) == 880
		and fallback_ledger.size() == 1 and str(fallback_ledger[0].damage_type) == "lightning",
		"EQ44 falls back in printed 2-1-3 order when its recorded target has departed")

	var none_alive := _new_case("EQ44", {"owner_hp":10, "owner_attack":0, "enemy_attack":0}, [
		{"kind":"damage", "target_key":"B1", "amount":1000, "damage_type":"fixed", "source_key":"A2"},
		{"kind":"damage", "target_key":"B2", "amount":1000, "damage_type":"fixed", "source_key":"A2"},
		{"kind":"damage", "target_key":"B3", "amount":1000, "damage_type":"fixed", "source_key":"A2"},
		{"kind":"self_loss", "target_key":"A1", "amount":10}
	])
	_run_until(none_alive.engine, 0)
	var lightning_events := 0
	for event in none_alive.engine.state.events:
		if str(event.get("kind", "")) == "hp_lost" and str(event.get("damage_type", event.get("payload", {}).get("damage_type", ""))) == "lightning":
			lightning_events += 1
	_check(lightning_events == 0 and none_alive.engine.get_counter("A1:EQ44", "eq44_used") == 1,
		"EQ44 consumes its once-per-battle trigger without damage when no enemy survives")


func _test_fx24() -> void:
	var positive := _new_case("FX24", {"owner_hp":10, "owner_attack":0, "enemy_attack":0}, [
		{"kind":"self_loss", "target_key":"A1", "amount":10}
	])
	_run_until(positive.engine, 0)
	_check(positive.engine.unit("A1").get("final_departed", false)
		and positive.engine.shield_amount("A2", "A1:FX24") == 120
		and positive.engine.shield_amount("A3", "A1:FX24") == 120,
		"FX24 grants twelve shield to every surviving teammate on the wearer's final departure")

	var no_departure := _new_case("FX24", {"enemy_attack":0, "owner_attack":0})
	_run_until(no_departure.engine, 0)
	_check(no_departure.engine.shield_amount("A2", "A1:FX24") == 0
		and no_departure.engine.shield_amount("A3", "A1:FX24") == 0,
		"FX24 does not grant shield while the wearer remains in battle")

	var expiry := _new_case("FX24", {"owner_hp":10, "owner_attack":0, "enemy_attack":0}, [
		{"kind":"self_loss", "target_key":"A1", "amount":10}
	])
	_run_until(expiry.engine, 40)
	_check(expiry.engine.shield_amount("A2", "A1:FX24") == 0
		and expiry.engine.shield_amount("A3", "A1:FX24") == 0
		and _has_expiry(expiry.engine.state.events, "", "A1:FX24"),
		"FX24 teammate shields expire exactly four seconds after final departure")


func _test_fx26() -> void:
	var positive := _new_case("FX26", {"owner_hp":500, "owner_attack":0, "enemy_attack":0}, [
		{"kind":"damage", "target_key":"A2", "amount":2000, "damage_type":"fixed", "source_key":"B1"},
		{"kind":"damage", "target_key":"A3", "amount":2000, "damage_type":"fixed", "source_key":"B1"}
	])
	_run_until(positive.engine, 0)
	_check(positive.engine.units("A").size() == 1 and int(positive.engine.unit("A1").hp_tenths) == 600
		and int(positive.engine.effective_stats("A1").R) == 4
		and positive.engine.get_counter("A1:FX26", "fx26_used") == 1,
		"FX26 heals ten and grants four armor only after the wearer becomes the team's sole survivor")

	var not_solo := _new_case("FX26", {"owner_hp":500, "owner_attack":0, "enemy_attack":0}, [
		{"kind":"damage", "target_key":"A2", "amount":2000, "damage_type":"fixed", "source_key":"B1"}
	])
	_run_until(not_solo.engine, 0)
	_check(int(not_solo.engine.unit("A1").hp_tenths) == 500
		and int(not_solo.engine.effective_stats("A1").R) == 0
		and not_solo.engine.ready("A1:FX26", "fx26_used"),
		"FX26 does not trigger when another teammate remains after a departure")

	var no_departure := _new_case("FX26", {"owner_hp":500, "enemy_attack":0, "owner_attack":0})
	_run_until(no_departure.engine, 0)
	_check(int(no_departure.engine.unit("A1").hp_tenths) == 500
		and int(no_departure.engine.effective_stats("A1").R) == 0,
		"FX26 does not trigger merely because the wearer is alive")

	var expiry := _new_case("FX26", {"owner_hp":500, "owner_attack":0, "enemy_attack":0}, [
		{"kind":"damage", "target_key":"A2", "amount":2000, "damage_type":"fixed", "source_key":"B1"},
		{"kind":"damage", "target_key":"A3", "amount":2000, "damage_type":"fixed", "source_key":"B1"}
	])
	_run_until(expiry.engine, 40)
	_check(int(expiry.engine.effective_stats("A1").R) == 0
		and _has_modifier_expiry(expiry.engine.state.events, "FX26:A1:solo", "A1:FX26"),
		"FX26's temporary armor expires exactly four seconds after activation")


func _test_fx47() -> void:
	var positive := _new_case("FX47", {"enemy_attack":0, "ally2_hp":500}, [
		{"kind":"status_add", "target_key":"A2", "status_id":"chill", "layers":1, "expires_tick":100},
		{"kind":"status_add", "target_key":"A2", "status_id":"rooted", "layers":1, "expires_tick":100},
		{"kind":"extra_attack", "target_key":"B1", "amount":10, "damage_type":"physical"}
	], {"tick":30, "actions":[{"kind":"extra_attack", "target_key":"B1", "amount":10, "damage_type":"physical"}]})
	_run_until(positive.engine, 0)
	_check(int(positive.engine.unit("A2").hp_tenths) == 530 and not _has_status(positive.engine.unit("A2"), "chill")
		and _has_status(positive.engine.unit("A2"), "rooted"),
		"FX47 extra-attack hit heals the lowest ally and clears its earliest chill/rooted status")
	_run_until(positive.engine, 30)
	_check(int(positive.engine.unit("A2").hp_tenths) == 560,
		"FX47 cooldown expires and can respond to a later extra-attack hit")
	var natural := _new_case("FX47", {"enemy_attack":0, "ally2_hp":500})
	_run_until(natural.engine, 6)
	_check(int(natural.engine.unit("A2").hp_tenths) == 500 and natural.engine.ready("A1:FX47", "fx47"),
		"FX47 does not trigger from the wearer's natural attack")


func _test_eq35() -> void:
	var positive := _new_case("EQ35", {"enemy_attack":0, "owner_hp":1000, "owner_attack":0}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":1, "expires_tick":100},
		{"kind":"damage", "target_key":"A1", "amount":20, "damage_type":"fixed"}
	], {"tick":10, "actions":[{"kind":"damage", "target_key":"A1", "amount":20, "damage_type":"fixed"}]})
	_run_until(positive.engine, 10)
	_check(int(positive.engine.unit("A1").hp_tenths) == 966 and positive.engine.shield_amount("A1") == 0,
		"EQ35 reduces exactly the first damage while shield exists; later hit after shield depletion is unreduced")
	var no_shield := _new_case("EQ35", {"enemy_attack":0, "owner_hp":1000, "owner_attack":0}, [
		{"kind":"damage", "target_key":"A1", "amount":100, "damage_type":"fixed"}
	])
	_run_until(no_shield.engine, 0)
	_check(int(no_shield.engine.unit("A1").hp_tenths) == 900,
		"EQ35 does not reduce damage without a shield at before_damage")
	var remains_active := _new_case("EQ35", {"enemy_attack":0, "owner_hp":1000, "owner_attack":0}, [
		{"kind":"shield_grant", "target_key":"A1", "amount":100, "expires_tick":100}
	])
	_run_until(remains_active.engine, 30)
	_check(remains_active.engine.shield_amount("A1") == 100,
		"EQ35 passive remains installed for the battle while its shield pool persists")


func _test_eq38() -> void:
	var fire := _new_case("EQ38", {"enemy_attack":0, "owner_hp":1000, "owner_attack":0}, [
		{"kind":"damage", "target_key":"A1", "amount":100, "damage_type":"fire"}
	])
	_run_until(fire.engine, 0)
	_check(int(fire.engine.unit("A1").hp_tenths) == 935,
		"EQ38 reduces fire damage by thirty-five percent")
	var ice := _new_case("EQ38", {"enemy_attack":0, "owner_hp":1000, "owner_attack":0}, [
		{"kind":"damage", "target_key":"A1", "amount":100, "damage_type":"ice"}
	])
	_run_until(ice.engine, 0)
	_check(int(ice.engine.unit("A1").hp_tenths) == 935,
		"EQ38 also reduces ice damage by thirty-five percent")
	var wrong_type := _new_case("EQ38", {"enemy_attack":0, "owner_hp":1000, "owner_attack":0}, [
		{"kind":"damage", "target_key":"A1", "amount":100, "damage_type":"physical"},
		{"kind":"damage", "target_key":"A1", "amount":100, "damage_type":"poison"},
		{"kind":"damage", "target_key":"A1", "amount":100, "damage_type":"lightning"}
	])
	_run_until(wrong_type.engine, 0)
	_check(int(wrong_type.engine.unit("A1").hp_tenths) == 735,
		"EQ38 leaves physical and poison unchanged but reduces lightning damage")


func _test_eq33() -> void:
	var positive := _new_case("EQ33", {"enemy_attack":0}, [
		{"kind":"barrier_grant", "target_key":"B1", "expires_tick":100}
	])
	_run_until(positive.engine, 6)
	_check(positive.engine.shield_amount("A1", "A1:EQ33") == 70 and int(positive.engine.unit("B1").hp_tenths) == 1000,
		"EQ33 grants seven shield when its natural main attack is fully absorbed by an enemy barrier")
	var shield_only := _new_case("EQ33", {"enemy_attack":0}, [
		{"kind":"shield_grant", "target_key":"B1", "amount":200, "expires_tick":100}
	])
	_run_until(shield_only.engine, 6)
	_check(shield_only.engine.shield_amount("A1", "A1:EQ33") == 0 and shield_only.engine.ready("A1:EQ33", "eq33"),
		"EQ33 does not trigger when an enemy shield, not a barrier, absorbs the hit")
	var expiry := _new_case("EQ33", {"enemy_attack":0}, [
		{"kind":"barrier_grant", "target_key":"B1", "expires_tick":100}
	])
	_run_until(expiry.engine, 36)
	_check(expiry.engine.shield_amount("A1", "A1:EQ33") == 0 and _has_expiry(expiry.engine.state.events, "", "A1:EQ33"),
		"EQ33 converted shield expires after three seconds")


func _test_eq27() -> void:
	var positive := _new_case("EQ27", {"enemy_attack":0, "owner_speed":20})
	_run_until(positive.engine, 67)
	var natural_ticks: Array[int] = []
	for event in positive.engine.state.events:
		if str(event.get("kind", "")) == "hit" and str(event.get("source_key", "")) == "A1" \
			and bool(event.get("is_natural_attack", false)):
			natural_ticks.append(int(event.get("tick", -1)))
	_check(natural_ticks.size() >= 4 and natural_ticks[1] - natural_ticks[0] == 15
		and natural_ticks[2] - natural_ticks[1] == 15 and natural_ticks[3] - natural_ticks[2] == 22,
		"EQ27 schedules the first three natural attacks at T-0.5 then uses T+0.2 (ticks=%s T=%d count=%d)" % [str(natural_ticks), int(positive.engine.effective_stats("A1").T_ticks), positive.engine.get_counter("A1:EQ27", "eq27_natural_count")])
	_check(int(positive.engine.effective_stats("A1").T_ticks) == 22,
		"EQ27's post-third-attack slow interval remains for the battle")
	var extra_does_not_count := _new_case("EQ27", {"enemy_attack":0, "owner_speed":20}, [
		{"kind":"extra_attack", "target_key":"B1", "amount":10, "damage_type":"physical"}
	])
	_run_until(extra_does_not_count.engine, 0)
	_check(extra_does_not_count.engine.get_counter("A1:EQ27", "eq27_natural_count") == 1,
		"EQ27 does not spend its natural-attack sequence on an extra attack (count=%d)" % extra_does_not_count.engine.get_counter("A1:EQ27", "eq27_natural_count"))


func _test_fx41() -> void:
	var both_shielded := _new_case("FX41", {"enemy_attack":0, "owner_attack":0}, [
		{"kind":"shield_grant", "target_key":"A2", "amount":20, "expires_tick":100},
		{"kind":"shield_grant", "target_key":"A3", "amount":20, "expires_tick":100}
	])
	_run_until(both_shielded.engine, 0)
	_check(int(both_shielded.engine.effective_stats("A1").R) == 5,
		"FX41 grants five armor when both other living teammates have shield")
	_run_until(both_shielded.engine, 20)
	_check(int(both_shielded.engine.effective_stats("A1").R) == 5,
		"FX41 renews at the two-second check without stacking duplicate armor")
	var one_shielded := _new_case("FX41", {"enemy_attack":0, "owner_attack":0}, [
		{"kind":"shield_grant", "target_key":"A2", "amount":20, "expires_tick":100}
	])
	_run_until(one_shielded.engine, 0)
	_check(int(one_shielded.engine.effective_stats("A1").R) == 0,
		"FX41 does not grant armor when either other teammate lacks shield")
	var expiry := _new_case("FX41", {"enemy_attack":0, "owner_attack":0}, [
		{"kind":"shield_grant", "target_key":"A2", "amount":20, "expires_tick":20},
		{"kind":"shield_grant", "target_key":"A3", "amount":20, "expires_tick":20}
	])
	_run_until(expiry.engine, 20)
	_check(int(expiry.engine.effective_stats("A1").R) == 0
		and _has_modifier_expiry(expiry.engine.state.events, "FX41:A1:armor", "A1:FX41"),
		"FX41 protection ends when its checked shield condition expires")


func _test_eq19() -> void:
	var positive := _new_case("EQ19", {"enemy_attack":0, "enemy_armor":3})
	_run_until(positive.engine, 18)
	var physical_ledger := _hp_loss_ledger(positive.engine, "B1")
	var exact_three_hit_losses := physical_ledger.size() == 3
	if exact_three_hit_losses:
		exact_three_hit_losses = int(physical_ledger[0].loss) == 10 and int(physical_ledger[1].loss) == 10 \
			and int(physical_ledger[2].loss) == 20
	_check(int(positive.engine.unit("B1").hp_tenths) == 960 and exact_three_hit_losses
		and positive.engine.get_counter("A1:EQ19", "eq19_natural_count") == 1,
		"EQ19 third natural physical hit ignores three armor after prior 10+10 tenths losses; fourth attack has begun counting (B1 hp=%d losses=%s count=%d)" % [int(positive.engine.unit("B1").hp_tenths), str(physical_ledger), positive.engine.get_counter("A1:EQ19", "eq19_natural_count")])
	_run_until(positive.engine, 24)
	_check(int(positive.engine.unit("B1").hp_tenths) == 950,
		"EQ19 returns to ordinary armor calculation after the third hit")
	var elemental := _new_case("EQ19", {"enemy_attack":0, "enemy_armor":3, "owner_damage_type":"fire"})
	_run_until(elemental.engine, 18)
	_check(int(elemental.engine.unit("B1").hp_tenths) == 940,
		"EQ19's third-attack armor piercing does not alter elemental main damage")


func _test_eq24() -> void:
	var above := _new_case("EQ24", {"enemy_attack":0})
	_run_until(above.engine, 0)
	_check(int(above.engine.effective_stats("A1").R) == 6 and int(above.engine.effective_stats("A1").T_ticks) == 8,
		"EQ24 retains its unconditional two-tick penalty and grants armor above seventy-five percent")
	var threshold := _new_case("EQ24", {"enemy_attack":0, "owner_hp":750})
	_run_until(threshold.engine, 0)
	_check(int(threshold.engine.effective_stats("A1").R) == 0,
		"EQ24 strict threshold does not grant armor at exactly seventy-five percent health")
	var dynamic := _new_case("EQ24", {"enemy_attack":0, "owner_hp":760}, [],
		{"tick":10, "actions":[{"kind":"self_loss", "amount":10}]})
	_run_until(dynamic.engine, 10)
	_check(int(dynamic.engine.unit("A1").hp_tenths) == 750 and int(dynamic.engine.effective_stats("A1").R) == 0,
		"EQ24 removes armor in response to actual loss on a distinct causal root (hp=%d max=%d R=%d)" % [int(dynamic.engine.unit("A1").hp_tenths), int(dynamic.engine.effective_stats("A1").H_max_tenths), int(dynamic.engine.effective_stats("A1").R)])


func _test_eq28() -> void:
	var positive := _new_case("EQ28", {"enemy_attack":0})
	_run_until(positive.engine, 79)
	_check(int(positive.engine.effective_stats("A1").A) == 2,
		"EQ28 does not award attack before eight seconds")
	_run_until(positive.engine, 80)
	_check(int(positive.engine.effective_stats("A1").A) == 4,
		"EQ28 awards two attack at eight seconds")
	_run_until(positive.engine, 200)
	_check(int(positive.engine.effective_stats("A1").A) == 10 and positive.engine.get_counter("A1:EQ28", "eq28_awards") == 4,
		"EQ28 grants four timed awards totaling eight attack by twenty seconds")
	_run_until(positive.engine, 240)
	_check(int(positive.engine.effective_stats("A1").A) == 10,
		"EQ28 stops awarding after the fourth permanent stack")
	var departed := _new_case("EQ28", {"enemy_attack":0, "owner_hp":100, "owner_attack":0}, [],
		{"tick":70, "actions":[{"kind":"self_loss", "amount":100}]})
	_run_until(departed.engine, 80)
	_check(bool(departed.engine.unit("A1").final_departed) and int(departed.engine.effective_stats("A1").A) == 0,
		"EQ28 grants no timed attack after the wearer finally departs")


func _test_eq45() -> void:
	var aligned := _new_case("EQ45", {"enemy_attack":0, "owner_target_slot":1})
	_run_until(aligned.engine, 6)
	_check(int(aligned.engine.unit("B1").hp_tenths) == 930,
		"EQ45 adds five attack to the aligned natural main segment")
	var cross := _new_case("EQ45", {"enemy_attack":0, "owner_target_slot":2})
	_run_until(cross.engine, 6)
	_check(int(cross.engine.unit("B2").hp_tenths) == 990,
		"EQ45 subtracts one attack off-slot with a one-point minimum")


func _test_eq46() -> void:
	var cross := _new_case("EQ46", {"enemy_attack":0, "owner_target_slot":2})
	_run_until(cross.engine, 6)
	_check(int(cross.engine.unit("B2").hp_tenths) == 940,
		"EQ46 adds four attack to an off-slot natural main segment")
	var melee := _new_case("EQ46", {"enemy_attack":0, "owner_target_slot":2, "owner_reach":"melee"})
	_run_until(melee.engine, 7)
	_check(int(melee.engine.unit("B2").hp_tenths) == 1000,
		"EQ46 reduces cross-lane melee preparation by two ticks")
	_run_until(melee.engine, 8)
	_check(int(melee.engine.unit("B2").hp_tenths) == 940,
		"EQ46 resolves shortened cross-lane melee attack at the adjusted tick")


func _test_handler_support_manifest(document: Dictionary) -> void:
	_check(AttachmentHandlersScript.IMPLEMENTED_IDS.size() == 69, "attachment handler manifest explicitly identifies the implemented card paths")
	for content_id: String in AttachmentHandlersScript.IMPLEMENTED_IDS:
		_check(AttachmentHandlersScript.supports_content_id(content_id), "supports_content_id accepts listed card %s" % content_id)
		_check(exercised_card_ids.has(content_id), "listed card %s has a real setup/engine fixture" % content_id)
	for card: Dictionary in document.get("attachments", []):
		var content_id := str(card.get("id", ""))
		_check(AttachmentHandlersScript.supports_content_id(content_id) == AttachmentHandlersScript.IMPLEMENTED_IDS.has(content_id),
			"support manifest stays explicit for %s" % content_id)
	_check(AttachmentHandlersScript.supports_content_id("EQ14") and not AttachmentHandlersScript.supports_content_id("FX04")
		and not AttachmentHandlersScript.supports_content_id("UNKNOWN"), "unsupported cards and unknown IDs stay outside handler support")


func _new_case(card_id: String, options: Dictionary = {}, driver_actions: Array = [], driver_extra: Dictionary = {}) -> Dictionary:
	exercised_card_ids[card_id] = true
	var handler = HandlerScript.new()
	var binding_kind := "equipment" if card_id.begins_with("EQ") else "slot"
	var binding := {"content_id":card_id, "logic_handler":"attachment_handlers", "source_key":"A1:%s" % card_id,
		"owner_key":"A1", "kind":binding_kind}
	if trigger_scope_by_card.has(card_id): binding["trigger_scope"] = trigger_scope_by_card[card_id]
	var bindings := [binding]
	var handlers: Array = [{"logic_handler":"attachment_handlers", "handler":handler, "bindings":bindings}]
	if not driver_actions.is_empty() or not driver_extra.get("actions", []).is_empty():
		var driver := Driver.new()
		driver.actions = driver_actions.duplicate(true)
		driver.extra_tick = int(driver_extra.get("tick", -1))
		driver.extra_actions = driver_extra.get("actions", []).duplicate(true)
		var driver_owner := str(driver_extra.get("owner_key", "A1"))
		handlers.append({"logic_handler":"fixture_driver", "handler":driver,
			"bindings":[{"content_id":"FIXTURE_DRIVER", "logic_handler":"fixture_driver", "source_key":"%s:DRIVER" % driver_owner,
			"owner_key":driver_owner, "kind":"slot"}]})
	for extra_handler: Dictionary in driver_extra.get("handlers", []): handlers.append(extra_handler.duplicate(true))
	var a1_speed := 200 if bool(options.get("owner_slow", false)) else int(options.get("owner_speed", 6))
	var a_team := [
		_unit("A1", 1, int(options.get("owner_hp", 1000)), a1_speed, card_id, int(options.get("owner_attack", 2)),
			int(options.get("owner_target_slot", 1)), str(options.get("owner_reach", "ranged")), str(options.get("owner_damage_type", "physical")),
			int(options.get("owner_armor", 0)), int(options.get("owner_base_H", 100))),
		_unit("A2", 2, int(options.get("ally2_hp", 1000)), int(options.get("ally2_speed", 200)), "", 0),
		_unit("A3", 3, int(options.get("ally3_hp", 1000)), int(options.get("ally3_speed", 200)), "", 0),
	]
	if options.has("owner_definition_id"): a_team[0]["definition_id"] = str(options.owner_definition_id)
	if options.has("ally2_definition_id"): a_team[1]["definition_id"] = str(options.ally2_definition_id)
	if options.has("ally3_definition_id"): a_team[2]["definition_id"] = str(options.ally3_definition_id)
	var b_team := [
		_unit("B1", 1, int(options.get("enemy_hp", 1000)), 6, "", int(options.get("enemy_attack", 2)), int(options.get("enemy_target", 1)), "ranged", "physical", int(options.get("enemy_armor", 0))),
		_unit("B2", 2, 1000, 200, "", 0, 1),
		_unit("B3", 3, 1000, 200, "", 0, 1),
	]
	var engine = EngineScript.new()
	var result: Dictionary = engine.setup({"seed":101, "rule_id":"VC01", "test_fixture":true, "teams":{"A":a_team,"B":b_team}}, handlers)
	_check(str(result.get("error", "")).is_empty(), "%s battle setup is accepted (error=%s)" % [card_id, str(result.get("error", ""))])
	return {"engine":engine, "events":[], "binding":binding}


func _unit(key: String, slot: int, hp_tenths: int, speed: int, card_id: String, attack: int, target_slot: int = 1,
		reach: String = "ranged", damage_type: String = "physical", armor: int = 0, base_h: int = 100) -> Dictionary:
	var result := {"definition_id":"FIXTURE_%s" % key, "fixture":true, "slot":slot,
		"H":base_h, "A":attack, "T_ticks":speed, "R":maxi(armor, 2 if slot == 1 and card_id == "EQ04" else 0), "reach":reach, "damage_type":damage_type, "armor_kind":"medium",
		"hp_tenths":hp_tenths, "target_slot":target_slot}
	if slot == 1 and not card_id.is_empty():
		if card_id.begins_with("EQ"): result["equipment_id"] = card_id
		else: result["slot_effect_id"] = card_id
		var prepared: Dictionary = CatalogScript.apply_setup_modifiers(result, card_id)
		if bool(prepared.get("accepted", false)): result = prepared.unit
	return result


func _run_until(engine: BattleEngine, target_tick: int) -> void:
	while int(engine.state.get("tick", 0)) <= target_tick and not bool(engine.state.get("terminal", false)):
		var result: Dictionary = engine.step()
		if not str(result.get("error", "")).is_empty():
			_fail("real BattleEngine step failed: " + str(result.error))
			return


func _find_status(unit: Dictionary, status_id: String) -> Dictionary:
	for status in unit.get("statuses", []):
		if str(status.get("id", "")) == status_id: return status
	return {}


func _status_count(unit: Dictionary, status_id: String) -> int:
	var count := 0
	for status in unit.get("statuses", []):
		if str(status.get("id", "")) == status_id: count += int(status.get("layers", 0))
	return count


func _has_status(unit: Dictionary, status_id: String) -> bool:
	return _status_count(unit, status_id) > 0


func _has_expiry(events: Array, status_id: String, source_binding_key: String) -> bool:
	for event in events:
		if str(event.get("kind", "")) != "expiry": continue
		var payload: Dictionary = event.get("payload", {})
		if (status_id.is_empty() or str(payload.get("status_id", "")) == status_id) \
			and (source_binding_key.is_empty() or str(payload.get("source_binding_key", "")) == source_binding_key): return true
	return false


func _has_modifier_expiry(events: Array, modifier_id: String, source_binding_key: String) -> bool:
	for event in events:
		if str(event.get("kind", "")) != "expiry": continue
		var payload: Dictionary = event.get("payload", {})
		if str(payload.get("modifier_id", "")) == modifier_id and str(payload.get("source_binding_key", "")) == source_binding_key:
			return true
	return false


func _first_event_tick(events: Array, event_kind: String, source_key: String) -> int:
	for event in events:
		if str(event.get("kind", "")) == event_kind and str(event.get("source_key", "")) == source_key:
			return int(event.get("tick", -1))
	return -1


func _hp_loss_ledger(engine: BattleEngine, target_key: String) -> Array:
	var ledger: Array = []
	for event in engine.state.events:
		if str(event.get("kind", "")) != "hp_lost" or str(event.get("target_key", "")) != target_key:
			continue
		ledger.append({"tick":int(event.get("tick", -1)), "source":str(event.get("source_key", "")),
			"loss":int(event.get("actual_hp_loss", event.get("payload", {}).get("actual_hp_loss", 0))),
			"damage_type":str(event.get("damage_type", event.get("payload", {}).get("damage_type", "")))})
	return ledger


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append("ATTACHMENT_ENGINE_CHECK: " + description)


func _fail(message: String) -> void:
	failures.append(message)
