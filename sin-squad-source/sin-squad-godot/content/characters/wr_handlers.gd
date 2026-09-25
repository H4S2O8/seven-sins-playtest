extends RefCounted
class_name WRHandlers

## Exact WR01..WR14 talent behavior. Ability prose is never inspected here.
## IMPLEMENTED_IDS records explicit handler behavior; INTEGRATED_IDS is only the
## subset with positive/negative/boundary coverage against the shared BattleEngine.
const IMPLEMENTED_IDS: Array[String] = ["WR01","WR02","WR03","WR04","WR05","WR06","WR07","WR08","WR09","WR10","WR11","WR12","WR13","WR14"]
const INTEGRATED_IDS: Array[String] = ["WR01","WR02","WR04","WR05","WR07","WR08","WR09","WR10","WR11","WR12","WR13","WR14"]

const TICKS_PER_SECOND := 10
const ROOT_ANGER_CAP := 120 # 12 damage, in tenths
const WR08_BATTLE_LIMIT := 3


func supports_content_id(content_id: String) -> bool:
	return IMPLEMENTED_IDS.has(content_id)


func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	match str(binding.get("content_id", "")):
		"WR01": return _wr01(engine, binding, event)
		"WR02": return _wr02(engine, binding, event)
		"WR03": return _wr03(engine, binding, event)
		"WR04": return _wr04(engine, binding, event)
		"WR05": return _wr05(engine, binding, event)
		"WR06": return _wr06(engine, binding, event)
		"WR07": return _wr07(engine, binding, event)
		"WR08": return _wr08(engine, binding, event)
		"WR09": return _wr09(engine, binding, event)
		"WR10": return _wr10(engine, binding, event)
		"WR11": return _wr11(engine, binding, event)
		"WR12": return _wr12(engine, binding, event)
		"WR13": return _wr13(engine, binding, event)
		"WR14": return _wr14(engine, binding, event)
	return []


func _wr01(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	if event.kind == "hp_lost" and str(event.get("target_key", "")) == owner_key:
		var attacker_key := str(event.get("source_key", ""))
		var attacker := engine.unit(attacker_key)
		if attacker.is_empty() or str(attacker.side) == str(owner.side) or not engine.ready(binding.source_key, "anger_store"):
			return []
		var loss := _loss(event)
		if loss <= 0: return []
		var current := engine.get_counter(binding.source_key, "anger")
		var stored := mini(ROOT_ANGER_CAP, current + int(floor(float(loss * 4000) / 10000.0)))
		if stored == current: return []
		return [_counter("anger", stored)]
	if event.kind == "hit" and bool(event.get("is_attack", false)) and str(event.get("source_key", "")) == owner_key:
		var anger := engine.get_counter(binding.source_key, "anger")
		if anger <= 0: return []
		var target_key := str(event.get("target_key", ""))
		if target_key.is_empty(): return []
		return [_counter("anger", 0), _cooldown(10, "anger_store"), _damage(target_key, anger, "physical")]
	return []


func _wr02(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "hit" or not bool(event.get("is_attack", false)):
		return []
	var owner_key := str(binding.get("owner_key", ""))
	var owner := engine.unit(owner_key)
	var ally := engine.unit(str(event.get("target_key", "")))
	var attacker := engine.unit(str(event.get("source_key", "")))
	if owner.is_empty() or ally.is_empty() or attacker.is_empty() or owner.get("dead", true): return []
	if str(ally.side) != str(owner.side) or ally.key == owner_key or str(attacker.side) == str(owner.side): return []
	if int(owner.target_slot) != int(attacker.slot) or int(attacker.target_slot) != int(ally.slot): return []
	if _has_status(owner, "rooted", int(event.tick)) and owner.reach == "melee" and int(owner.slot) != int(owner.target_slot): return []
	if not engine.ready(binding.source_key, "default"): return []
	return [_cooldown(30), {"kind":"extra_attack", "target_key":attacker.key,
		"amount":int(owner.get("base_A", owner.A)) * 6, "damage_type":"physical"}]


func _wr03(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "prepare_attack" or str(event.get("source_key", "")) != str(binding.get("owner_key", "")):
		return []
	var owner := engine.unit(str(binding.owner_key))
	if owner.is_empty() or not engine.ready(binding.source_key, "default"): return []
	var rooted := _has_status(owner, "rooted", int(event.tick))
	var slowed := _has_status(owner, "chill", int(event.tick))
	for modifier in owner.get("modifiers", []):
		if int(modifier.get("expires_tick", 2147483647)) >= int(event.tick) and str(modifier.get("stat", "")) in ["T_ticks_percent", "T_ticks_flat"] and int(modifier.get("amount", 0)) > 0:
			slowed = true
	if not rooted and not slowed: return []
	var attack_id := str(event.get("attack_id", event.get("payload", {}).get("attack_id", "")))
	assert(not attack_id.is_empty(), "WR03 contract violation: prepare_attack needs stable pending attack_id")
	var actions: Array = []
	if rooted: actions.append({"kind":"status_remove", "target_key":owner.key, "status_id":"rooted", "layers":1})
	actions.append({"kind":"attack_patch", "attack_id":attack_id,
		"patch":{"ignore_slow_for_this_attack":true,"attached_damage":[{"amount":50,"damage_type":"fixed"}]}})
	actions.append(_cooldown(40))
	return actions


func _wr04(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "hit" or not bool(event.get("is_attack", false)) or str(event.get("source_key", "")) != str(binding.get("owner_key", "")):
		return []
	var target_key := str(event.get("target_key", ""))
	if target_key.is_empty(): return []
	var target := engine.unit(target_key)
	if target.is_empty(): return []
	var active_ids: Array[String] = []
	var active_layers := 0
	for modifier in target.get("modifiers", []):
		var modifier_id := str(modifier.get("modifier_id", ""))
		if str(modifier.get("source_binding_key", "")) != str(binding.source_key): continue
		if not modifier_id.begins_with("WR04:%s:" % target_key): continue
		if str(modifier.get("stat", "")) != "R_flat" or int(modifier.get("amount", 0)) != -1: continue
		active_ids.append(modifier_id)
		active_layers += 1
	var layers := mini(4, active_layers + 1)
	var actions: Array = []
	for modifier_id in active_ids:
		actions.append({"kind":"modifier_remove", "target_key":target_key, "modifier_id":modifier_id,
			"source_binding_key":binding.source_key})
	for index in range(layers):
		actions.append({"kind":"modifier_add", "target_key":target_key, "stat":"R_flat", "amount":-1,
			"modifier_id":"WR04:%s:%d" % [target_key, index], "expires_tick":int(event.tick) + 40})
	return actions


func _wr05(_engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "before_hit" or str(event.get("source_key", "")) != str(binding.get("owner_key", "")):
		return []
	var owner := _engine.unit(str(binding.owner_key))
	if owner.is_empty() or int(owner.hp_tenths) * 100 <= _max_hp_tenths(owner) * 35:
		return []
	var attack_id := str(event.get("attack_id", event.get("payload", {}).get("attack_id", "")))
	assert(not attack_id.is_empty(), "WR05 integration_blocked: before_hit needs stable pending attack_id")
	return [
		{"kind":"attack_patch", "attack_id":attack_id,
			"patch":{"damage_type":"fire","amount_flat":60}},
		{"kind":"self_loss", "amount":60},
	]


func _wr06(_engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "battle_start": return []
	var owner := _engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty() or owner.get("dead", true): return []
	var enemy_side := "B" if str(owner.side) == "A" else "A"
	var attacker := _engine.unit("%s%d" % [enemy_side, int(owner.target_slot)])
	if attacker.is_empty() or attacker.get("dead", true): return []
	var actions: Array = []
	for protected in _engine.units(str(owner.side), true):
		if str(protected.key) == str(owner.key): continue
		actions.append({"kind":"redirect_register", "target_key":protected.key, "ratio_bp":3000,
			"recipient_keys":[owner.key], "capacity_per_second":100,
			"filters":{"source_key":attacker.key,"owner_key":owner.key,"owner_target_slot":int(attacker.slot)},
			"redirect_id":"WR06:%s:%s" % [owner.key, protected.key]})
	return actions


func _wr07(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	if event.kind == "final_departure" and str(event.get("target_side", "")) == str(owner.side) and str(event.get("target_key", "")) != owner_key:
		if owner.get("dead", true) or engine.get_counter(binding.source_key, "relay_used") > 0: return []
		return [_counter("relay_used", 1), _counter("relay_until", int(event.tick) + 50),
			{"kind":"modifier_add", "target_key":owner_key, "stat":"T_ticks_flat", "amount":-5,
				"modifier_id":"WR07:relay", "expires_tick":int(event.tick) + 50}]
	if event.kind == "hit" and bool(event.get("is_attack", false)) and str(event.get("source_key", "")) == owner_key:
		if engine.get_counter(binding.source_key, "relay_used") <= 0 or int(event.tick) >= engine.get_counter(binding.source_key, "relay_until"):
			return []
		return [_status(str(event.get("target_key", "")), "burn", 1, int(event.tick) + 30)]
	return []


func _wr08(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "before_hit" or str(event.get("source_key", "")) != str(binding.get("owner_key", "")):
		return []
	var target := engine.unit(str(event.get("target_key", "")))
	if target.is_empty() or int(target.hp_tenths) * 100 > _max_hp_tenths(target) * 30: return []
	var uses := engine.get_counter(binding.source_key, "tail_uses")
	var target_counter := "tail_target:" + str(target.key)
	if uses >= WR08_BATTLE_LIMIT or engine.get_counter(binding.source_key, target_counter) > 0: return []
	var attack_id := str(event.get("attack_id", event.get("payload", {}).get("attack_id", "")))
	assert(not attack_id.is_empty(), "WR08 integration_blocked: before_hit needs stable pending attack_id")
	return [{"kind":"attack_patch", "attack_id":attack_id,
		"patch":{"attached_damage":[{"amount":90,"damage_type":"fixed"}]}},
		_counter("tail_target:" + str(target.key), 1), _counter("tail_uses", uses + 1)]


func _wr09(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "hit" or not bool(event.get("is_natural_attack", false)) or bool(event.get("is_extra_attack", false)):
		return []
	if str(event.get("source_key", "")) != str(binding.get("owner_key", "")): return []
	var dealt := _loss(event)
	if dealt <= 0: return []
	var owner := engine.unit(str(binding.owner_key))
	if owner.is_empty(): return []
	var enemy_side := "B" if owner.side == "A" else "A"
	var primary_target := str(event.get("target_key", ""))
	var splash_targets: Array[String] = []
	for enemy in engine.units(enemy_side, false):
		if enemy.key == primary_target: continue
		if enemy.get("dead", false) or enemy.get("final_departed", false) or int(enemy.get("hp_tenths", 0)) <= 0: continue
		splash_targets.append(str(enemy.key))
	if splash_targets.size() != 2: return []
	var splash := mini(40, int(floor(float(dealt * 2500) / 10000.0)))
	if splash <= 0: return []
	var actions: Array = []
	for target_key in splash_targets:
		actions.append(_damage(target_key, splash, "physical"))
	return actions


func _wr10(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "before_hit" or str(event.get("source_key", "")) != str(binding.get("owner_key", "")):
		return []
	if not engine.ready(binding.source_key, "default"): return []
	var target := engine.unit(str(event.get("target_key", "")))
	if target.is_empty(): return []
	var shield_total := 0
	for pool in target.get("shield_pools", []): shield_total += int(pool.get("amount", 0))
	var cleared := mini(80, shield_total)
	if cleared <= 0: return []
	var attack_id := str(event.get("attack_id", event.get("payload", {}).get("attack_id", "")))
	assert(not attack_id.is_empty(), "WR10 integration_blocked: before_hit needs stable pending attack_id")
	return [{"kind":"enemy_clear_shield", "target_key":target.key,"amount":80,"attack_id":attack_id,
		"bonus_bp":5000,"bonus_damage_type":"fixed"}, _cooldown(30)]


func _wr11(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "hit" or not bool(event.get("is_natural_attack", false)) or bool(event.get("is_extra_attack", false)):
		return []
	if str(event.get("source_key", "")) != str(binding.get("owner_key", "")): return []
	var owner := engine.unit(str(binding.owner_key))
	if owner.is_empty() or int(event.get("target_slot", 0)) <= 0 or str(event.get("target_side", "")) == str(owner.side): return []
	if not engine.ready(binding.source_key, "lightning"): return []
	var count := engine.get_counter(binding.source_key, "three_beats") + 1
	if count < 3: return [_counter("three_beats", count)]
	return [_counter("three_beats", 0), _cooldown(10, "lightning"),
		_damage(str(event.target_key), 100, "lightning")]


func _wr12(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	if event.kind == "battle_start":
		return [_counter("duel_target_slot", int(owner.get("target_slot", 0)))]
	if event.kind != "hp_lost" or str(event.get("target_key", "")) != owner_key or not bool(event.get("is_attack", false)):
		return []
	if bool(event.get("payload", {}).get("transferred", false)) or int(event.get("actual_hp_loss", 0)) <= 0: return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	if attacker.is_empty() or attacker.side == owner.side or int(attacker.slot) != engine.get_counter(binding.source_key, "duel_target_slot"):
		return []
	if attacker.get("dead", false) or attacker.get("final_departed", false): return []
	if not engine.ready(binding.source_key, "retaliate"): return []
	return [_cooldown(10, "retaliate"), _damage(attacker.key, 30, "fixed")]


func _wr13(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if event.kind == "hit" and bool(event.get("is_attack", false)) and str(event.get("source_key", "")) == owner_key:
		var target_key := str(event.get("target_key", ""))
		if target_key.is_empty(): return []
		return [{"kind":"modifier_add", "target_key":target_key, "stat":"healing_reduction_bp", "amount":4000,
			"modifier_id":"WR13:%s" % owner_key, "expires_tick":int(event.tick) + 20}]
	if event.kind == "healed" and str(event.get("target_key", "")) != "":
		var reduced := 0
		for reduction in event.get("payload", {}).get("healing_reductions", []):
			if str(reduction.get("source_binding_key", "")) == str(binding.source_key):
				reduced += int(reduction.get("amount", 0))
		if reduced <= 0: return []
		var target_key := str(event.target_key)
		var debt_key := "wound_debt:" + target_key
		var debt := mini(60, engine.get_counter(binding.source_key, debt_key) + reduced)
		return [_counter(debt_key, debt)]
	if event.kind == "expiry" and str(event.get("source_binding_key", "")) == str(binding.source_key):
		var target_key := str(event.get("target_key", ""))
		var debt_key := "wound_debt:" + target_key
		var debt := engine.get_counter(binding.source_key, debt_key)
		if debt <= 0: return []
		return [_counter(debt_key, 0), _damage(target_key, debt, "physical")]
	return []


func _wr14(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if event.kind != "final_departure" or str(event.get("target_key", "")) != owner_key:
		return []
	if engine.get_counter(binding.source_key, "departure_used") > 0: return []
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	var enemy_side := "B" if owner.side == "A" else "A"
	var target_key := "%s%d" % [enemy_side, int(owner.get("target_slot", 0))]
	var target := engine.unit(target_key)
	if target.is_empty() or target.get("dead", true) or target.get("final_departed", false):
		return [_counter("departure_used", 1)]
	return [_counter("departure_used", 1), _damage(target_key, 120, "physical"),
		{"kind":"modifier_add", "target_key":target_key, "stat":"T_ticks_percent", "amount":3500,
			"modifier_id":"WR14:%s" % owner_key, "expires_tick":int(event.tick) + 30}]


func _counter(counter_key: String, value: int) -> Dictionary:
	return {"kind":"counter", "counter_key":counter_key, "value":value}


func _cooldown(ticks: int, cooldown_key: String = "default") -> Dictionary:
	return {"kind":"cooldown", "ticks":ticks, "cooldown_key":cooldown_key}


func _damage(target_key: String, amount: int, damage_type: String) -> Dictionary:
	return {"kind":"damage", "target_key":target_key, "amount":amount, "damage_type":damage_type}


func _status(target_key: String, status_id: String, layers: int, expires_tick: int) -> Dictionary:
	return {"kind":"status_add", "target_key":target_key, "status_id":status_id, "layers":layers, "expires_tick":expires_tick}


func _loss(event: Dictionary) -> int:
	return int(event.get("actual_hp_loss", event.get("payload", {}).get("actual_hp_loss", 0)))


func _has_status(unit_state: Dictionary, status_id: String, tick: int) -> bool:
	for status in unit_state.get("statuses", []):
		if str(status.get("id", status.get("status_id", ""))) == status_id and int(status.get("expires_tick", -1)) >= tick:
			return true
	return false


func _max_hp_tenths(unit_state: Dictionary) -> int:
	if unit_state.has("max_hp_tenths"): return int(unit_state.max_hp_tenths)
	if unit_state.has("H"): return int(unit_state.H) * 10
	return int(unit_state.get("initial_max_hp_tenths", 0))
