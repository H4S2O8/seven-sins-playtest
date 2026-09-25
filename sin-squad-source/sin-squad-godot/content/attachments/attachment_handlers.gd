extends RefCounted
class_name AttachmentHandlers

const TICKS_PER_SECOND := 10
const CatalogScript = preload("res://content/attachments/attachment_catalog.gd")
const NEGATIVE_STATUS_IDS := ["burn", "bleed", "poison", "chill", "rooted", "silence"]
const IMPLEMENTED_IDS := [
	"EQ01", "EQ02", "EQ03", "EQ04", "EQ05", "EQ06", "EQ07", "EQ08", "EQ09", "EQ10", "EQ11", "EQ12", "EQ13",
	"EQ14", "EQ15", "EQ16", "EQ17", "EQ18", "EQ19", "EQ20", "EQ21", "EQ22", "EQ23", "EQ24", "EQ25", "EQ27", "EQ28", "EQ36",
	"EQ26", "EQ29", "EQ30", "EQ33", "EQ34", "EQ35", "EQ37", "EQ38", "EQ40", "EQ41", "EQ42", "EQ43", "EQ44", "EQ45", "EQ46", "EQ49",
	"FX02", "FX03", "FX05", "FX06", "FX07", "FX08", "FX12", "FX18", "FX21", "FX31", "FX33", "FX34",
	"FX01", "FX09", "FX13", "FX17", "FX20", "FX22", "FX24", "FX26", "FX36", "FX41", "FX43", "FX44", "FX47",
]


static func supports_content_id(content_id: String) -> bool:
	return IMPLEMENTED_IDS.has(content_id)


func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	match str(binding.get("content_id", "")):
		"EQ01", "EQ02", "EQ03", "EQ04", "EQ12", "EQ13": return []
		"EQ05": return _eq05(binding, event)
		"EQ06": return _eq06(engine, binding, event)
		"EQ08": return _eq08(engine, binding, event)
		"EQ09": return _eq09(binding, event)
		"EQ07": return _eq07(engine, binding, event)
		"EQ10": return _eq10(engine, binding, event)
		"EQ11": return _eq11(engine, binding, event)
		"EQ14": return _eq14(engine, binding, event)
		"EQ15": return _eq15(engine, binding, event)
		"EQ16": return _eq16(engine, binding, event)
		"EQ20": return _eq20(engine, binding, event)
		"EQ21": return _eq21(engine, binding, event)
		"EQ22": return _eq22(engine, binding, event)
		"EQ23": return _eq23(engine, binding, event)
		"EQ34": return _eq34(engine, binding, event)
		"EQ36": return _eq36(engine, binding, event)
		"EQ42": return _eq42(engine, binding, event)
		"EQ37": return _eq37(engine, binding, event)
		"EQ43": return _eq43(engine, binding, event)
		"EQ44": return _eq44(engine, binding, event)
		"EQ35": return _eq35(engine, binding, event)
		"EQ38": return _eq38(binding, event)
		"EQ33": return _eq33(engine, binding, event)
		"EQ27": return _eq27(engine, binding, event)
		"EQ19": return _eq19(engine, binding, event)
		"EQ24": return _eq24(engine, binding, event)
		"EQ28": return _eq28(engine, binding, event)
		"EQ26": return []
		"EQ29": return _eq29(engine, binding, event)
		"EQ30": return _eq30(engine, binding, event)
		"EQ45": return _eq45(binding, event)
		"EQ46": return _eq46(engine, binding, event)
		"EQ49": return _eq49(engine, binding, event)
		"FX01": return _fx01(engine, binding, event)
		"EQ18": return _eq18(engine, binding, event)
		"EQ17": return _eq17(engine, binding, event)
		"EQ25": return _eq25(engine, binding, event)
		"EQ40": return _eq40(engine, binding, event)
		"EQ41": return _eq41(engine, binding, event)
		"FX02": return _fx02(engine, binding, event)
		"FX03": return _fx03(engine, binding, event)
		"FX05": return _fx05(engine, binding, event)
		"FX06": return _fx06(engine, binding, event)
		"FX07": return _fx07(engine, binding, event)
		"FX08": return _fx08(engine, binding, event)
		"FX09": return _fx09(engine, binding, event)
		"FX12": return _fx12(engine, binding, event)
		"FX13": return _fx13(engine, binding, event)
		"FX17": return _fx17(engine, binding, event)
		"FX18": return _fx18(engine, binding, event)
		"FX20": return _fx20(engine, binding, event)
		"FX31": return _fx31(engine, binding, event)
		"FX34": return _fx34(engine, binding, event)
		"FX33": return _fx33(engine, binding, event)
		"FX36": return _fx36(engine, binding, event)
		"FX43": return _fx43(engine, binding, event)
		"FX44": return _fx44(engine, binding, event)
		"FX21": return _fx21(engine, binding, event)
		"FX22": return _fx22(engine, binding, event)
		"FX24": return _fx24(engine, binding, event)
		"FX26": return _fx26(engine, binding, event)
		"FX47": return _fx47(engine, binding, event)
		"FX41": return _fx41(engine, binding, event)
	return []


func _eq05(binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "battle_start": return []
	var owner := str(binding.get("owner_key", ""))
	if owner.is_empty(): return []
	return [_shield(owner, 240, int(event.get("tick", 0)) + 60)]


func _eq06(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic": return []
	var tick := int(event.get("tick", -1))
	if tick < 20 or (tick - 20) % 40 != 0: return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
	return [{"kind":"self_loss", "amount":30}]


func _eq08(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic": return []
	var tick := int(event.get("tick", -1))
	if tick < 0 or tick % 40 != 0: return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
	return [_status(str(owner.key), "burn", 1, tick + 30)]


func _eq09(binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "prepare_attack" or str(event.get("source_key", "")) != owner_key:
		return []
	if not bool(event.get("is_natural_attack", false)) and not bool(event.get("is_extra_attack", false)):
		return []
	var context: Dictionary = event.get("payload", {}).get("attack_context", {})
	var segments: Array = context.get("segments", []).duplicate(true)
	if segments.is_empty(): return []
	var main_segment: Dictionary = segments[0]
	main_segment["amount"] = int(floor(float(int(main_segment.get("amount", 0)) * 8000) / 10000.0))
	main_segment["damage_type"] = "fire"
	segments[0] = main_segment
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")), "patch":{"segments":segments}}]


func _eq07(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner) or not engine.ready(str(binding.source_key), "eq07"):
		return []
	if engine.shield_amount(owner) > 0: return []
	return [_cooldown("eq07", 30), _shield(owner, 60, int(event.tick) + 30)]


func _eq10(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner) or not engine.ready(str(binding.source_key), "eq10"):
		return []
	return [_cooldown("eq10", 40), _status(str(event.target_key), "chill", 1, int(event.tick) + 20)]


func _eq11(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner) or not engine.ready(str(binding.source_key), "eq11"):
		return []
	return [_cooldown("eq11", 40), _status(str(event.target_key), "poison", 2, int(event.tick) + 30)]


func _eq14(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "battle_start": return []
	var owner_key := str(binding.get("owner_key", ""))
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var enemy_side := "B" if str(owner.side) == "A" else "A"
	var redirect_id := "EQ14:%s" % str(binding.get("source_key", ""))
	var actions: Array = []
	for ally in engine.units(str(owner.side)):
		if str(ally.key) == owner_key: continue
		for slot in [1, 2, 3]:
			var enemy_key := "%s%d" % [enemy_side, slot]
			actions.append({"kind":"redirect_register", "target_key":str(ally.key), "ratio_bp":2500,
				"recipient_keys":[owner_key], "capacity_per_root":60, "redirect_id":redirect_id,
				"filters":{"source_key":enemy_key}})
	return actions


func _eq15(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "healed" or str(event.get("target_key", "")) != owner_key:
		return []
	var overheal := int(event.get("payload", {}).get("overheal", 0))
	if overheal <= 0 or not engine.ready(str(binding.source_key), "eq15"): return []
	var shield := mini(80, int(floor(float(overheal * 6000) / 10000.0)))
	if shield <= 0: return []
	return [_cooldown("eq15", 20), _shield(owner_key, shield, int(event.tick) + 40)]


func _eq16(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner_key): return []
	var source_key := str(binding.source_key)
	var count := engine.get_counter(source_key, "eq16_natural_hits") + 1
	if count < 4: return [_counter("eq16_natural_hits", count)]
	var stats: Dictionary = engine.effective_stats(owner_key)
	var amount := int(floor(float(int(stats.get("A_tenths", 0)) * 6000) / 10000.0))
	if amount <= 0: return [_counter("eq16_natural_hits", 0)]
	return [_counter("eq16_natural_hits", 0), {"kind":"schedule", "tick":int(event.get("tick", 0)) + 1,
		"phase":"post_damage", "action":{"kind":"extra_attack", "target_key":str(event.get("target_key", "")),
			"amount":amount, "damage_type":str(stats.get("damage_type", "physical"))}}]


func _eq20(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "hit" or not bool(event.get("is_attack", false)) \
		or str(event.get("source_key", "")) != owner_key or not engine.ready(str(binding.source_key), "eq20"):
		return []
	var target_key := str(event.get("target_key", ""))
	if not _has_status(engine.unit(target_key), "burn"): return []
	return [_cooldown("eq20", 30), {"kind":"status_remove", "target_key":target_key, "status_id":"burn", "layers":1},
		{"kind":"damage", "target_key":target_key, "amount":60, "damage_type":"fire"}]


func _eq21(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "hit" or not bool(event.get("is_attack", false)) \
		or str(event.get("source_key", "")) != owner_key or not engine.ready(str(binding.source_key), "eq21"):
		return []
	var target_key := str(event.get("target_key", ""))
	if not _has_status(engine.unit(target_key), "poison"): return []
	return [_cooldown("eq21", 30), {"kind":"status_remove", "target_key":target_key, "status_id":"poison", "layers":1},
		{"kind":"heal", "target_key":owner_key, "amount":60}]


func _eq22(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "hp_lost" or str(event.get("source_key", "")) != owner_key \
		or not bool(event.get("is_natural_attack", false)) or int(event.get("actual_hp_loss", 0)) <= 0 \
		or str(event.get("target_side", "")) == str(engine.unit(owner_key).get("side", "")) \
		or not engine.ready(str(binding.source_key), "eq22"):
		return []
	return [_cooldown("eq22", 20), _status(str(event.get("target_key", "")), "bleed", 1, int(event.tick) + 30)]


func _eq23(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var kind := str(event.get("kind", ""))
	if kind == "battle_start":
		pass
	elif kind in ["hp_lost", "healed"]:
		if str(event.get("target_key", "")) != owner_key: return []
		if kind == "hp_lost" and int(event.get("actual_hp_loss", 0)) <= 0: return []
		if kind == "healed" and int(event.get("payload", {}).get("actual_healing", 0)) <= 0: return []
	else:
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	var maximum := int(engine.effective_stats(owner_key).get("H_max_tenths", 0))
	var bonus_tenths := mini(70, int(floor(float(maxi(maximum - int(owner.hp_tenths), 0)) / 8.0)))
	var has_modifier := false
	for modifier in owner.get("modifiers", []):
		if str(modifier.get("modifier_id", "")) == "EQ23:%s" % owner_key and str(modifier.get("source_binding_key", "")) == str(binding.source_key):
			has_modifier = true
			break
	if bonus_tenths <= 0 and not has_modifier: return []
	var actions: Array = [{"kind":"modifier_remove", "target_key":owner_key, "modifier_id":"EQ23:%s" % owner_key}]
	if bonus_tenths > 0:
		actions.append({"kind":"modifier_add", "target_key":owner_key, "stat":"A_tenths_flat", "amount":bonus_tenths,
			"modifier_id":"EQ23:%s" % owner_key})
	return actions


func _eq34(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "hp_lost" or str(event.get("source_key", "")) != owner_key \
		or not bool(event.get("is_natural_attack", false)) or int(event.get("actual_hp_loss", 0)) <= 0 \
		or not engine.ready(str(binding.source_key), "eq34"):
		return []
	var healing := mini(50, int(floor(float(int(event.actual_hp_loss) * 3000) / 10000.0)))
	if healing <= 0: return []
	return [_cooldown("eq34", 10), {"kind":"heal", "target_key":owner_key, "amount":healing}]


func _eq36(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "shield_broken" or str(event.get("target_key", "")) != owner_key \
		or not engine.ready(str(binding.source_key), "eq36"):
		return []
	var tick := int(event.get("tick", 0))
	return [_cooldown("eq36", 40), {"kind":"modifier_add", "target_key":owner_key,
		"stat":"T_ticks_flat", "amount":-35, "modifier_id":"EQ36:%s:haste" % owner_key, "expires_tick":tick + 40}]


func _eq42(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var kind := str(event.get("kind", ""))
	if kind == "hp_lost" and str(event.get("target_key", "")) == owner_key \
		and int(event.get("actual_hp_loss", 0)) > 0:
		return [_counter("eq42_last_loss_tick", int(event.get("tick", 0)))]
	if kind != "periodic": return []
	var tick := int(event.get("tick", -1))
	if tick < 30 or tick % 30 != 0 or tick - engine.get_counter(str(binding.source_key), "eq42_last_loss_tick") < 20:
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
	return [{"kind":"heal", "target_key":owner_key, "amount":50}]


func _eq37(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var kind := str(event.get("kind", ""))
	if kind == "battle_start":
		return _eq37_sync(engine, binding)
	if kind not in ["status_applied", "status_removed", "expiry"] or str(event.get("target_key", "")) != owner_key:
		return []
	return _eq37_sync(engine, binding)


func _eq37_sync(engine: BattleEngine, binding: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	var has_debuff: bool = not owner.get("statuses", []).is_empty()
	var modifier_id := "EQ37:%s" % owner_key
	var has_modifier := false
	for modifier in owner.get("modifiers", []):
		if str(modifier.get("modifier_id", "")) == modifier_id and str(modifier.get("source_binding_key", "")) == str(binding.source_key):
			has_modifier = true
			break
	if has_debuff and has_modifier:
		return [{"kind":"modifier_remove", "target_key":owner_key, "modifier_id":modifier_id}]
	if not has_debuff and not has_modifier:
		return [{"kind":"modifier_add", "target_key":owner_key, "stat":"A_flat", "amount":5, "modifier_id":modifier_id}]
	return []


func _eq43(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner_key): return []
	var source_key := str(binding.source_key)
	var count := engine.get_counter(source_key, "eq43_natural_hit_count") + 1
	var actions: Array = [_counter("eq43_natural_hit_count", count)]
	if count % 2 == 1:
		actions.append(_status(str(event.get("target_key", "")), "burn", 1, int(event.tick) + 30))
	return actions


func _eq44(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "final_departure" or str(event.get("target_key", "")) != owner_key:
		return []
	var source_key := str(binding.source_key)
	if engine.get_counter(source_key, "eq44_used") > 0: return []
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	var enemy_side := "B" if str(owner.side) == "A" else "A"
	var target_key := "%s%d" % [enemy_side, int(owner.get("target_slot", 1))]
	var selected := engine.unit(target_key)
	if selected.is_empty() or selected.get("dead", true) or selected.get("final_departed", false):
		selected = {}
		for slot in [2, 1, 3]:
			var candidate := engine.unit("%s%d" % [enemy_side, slot])
			if not candidate.is_empty() and not candidate.get("dead", true) and not candidate.get("final_departed", false):
				selected = candidate
				break
	var actions: Array = [_counter("eq44_used", 1)]
	if not selected.is_empty():
		actions.append({"kind":"damage", "target_key":str(selected.key), "amount":120, "damage_type":"lightning"})
	return actions


func _fx24(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "final_departure" or str(event.get("target_key", "")) != owner_key:
		return []
	var source_key := str(binding.get("source_key", ""))
	if engine.get_counter(source_key, "fx24_used") > 0: return []
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	var actions: Array = [_counter("fx24_used", 1)]
	for ally in engine.units(str(owner.side)):
		if str(ally.key) == owner_key or ally.get("dead", true) or ally.get("final_departed", false): continue
		actions.append(_shield(str(ally.key), 120, int(event.get("tick", 0)) + 40))
	return actions


func _fx26(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "final_departure" or str(event.get("target_side", "")) != str(owner_key.substr(0, 1)) \
		or str(event.get("target_key", "")) == owner_key:
		return []
	var source_key := str(binding.get("source_key", ""))
	if engine.get_counter(source_key, "fx26_used") > 0: return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
	var living := engine.units(str(owner.side))
	if living.size() != 1 or str(living[0].get("key", "")) != owner_key: return []
	var tick := int(event.get("tick", 0))
	return [_counter("fx26_used", 1), {"kind":"heal", "target_key":owner_key, "amount":100},
		{"kind":"modifier_add", "target_key":owner_key, "stat":"R_flat", "amount":4,
			"modifier_id":"FX26:%s:solo" % owner_key, "expires_tick":tick + 40}]


func _fx22(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var source_key := str(binding.get("source_key", ""))
	var kind := str(event.get("kind", ""))
	if kind == "final_departure":
		var owner := engine.unit(owner_key)
		if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
		var enemy_side := "B" if str(owner.side) == "A" else "A"
		if str(event.get("target_side", "")) != enemy_side or int(event.get("target_slot", 0)) != int(owner.get("target_slot", 0)):
			return []
		var tick := int(event.get("tick", 0))
		if engine.get_counter(source_key, "fx22_window_expires") > tick: return []
		return [_counter("fx22_target_slot", int(event.get("target_slot", 0))), _counter("fx22_window_expires", tick + 40)]
	if not _natural_hit_from(event, owner_key): return []
	var tick := int(event.get("tick", 0))
	var origin_slot := engine.get_counter(source_key, "fx22_target_slot")
	if origin_slot <= 0 or int(engine.get_counter(source_key, "fx22_window_expires")) <= tick \
		or int(event.get("target_slot", 0)) == origin_slot:
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
	var ally := _lowest_other(engine, str(owner.side), owner_key)
	if ally.is_empty(): return []
	return [_counter("fx22_target_slot", 0), _counter("fx22_window_expires", 0),
		{"kind":"barrier_grant", "target_key":str(ally.key), "expires_tick":tick + 30}]


func _fx13(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var payload: Dictionary = event.get("payload", {})
	if str(event.get("kind", "")) != "barrier_absorbed" or str(event.get("source_key", "")) != owner_key \
		or not bool(payload.get("is_natural_attack", false)) or bool(payload.get("is_extra_attack", false)) \
		or int(payload.get("barrier_absorbed", 0)) <= 0 or int(payload.get("actual_hp_loss", 0)) > 0 \
		or int(payload.get("shield_absorbed", 0)) > 0 \
		or not engine.ready(str(binding.get("source_key", "")), "fx13"):
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
	var ally := _lowest_other(engine, str(owner.side), owner_key)
	if ally.is_empty(): return []
	return [_cooldown("fx13", 60), {"kind":"barrier_grant", "target_key":str(ally.key),
		"expires_tick":int(event.get("tick", 0)) + 20}]


func _fx09(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var source_key := str(binding.get("source_key", ""))
	if str(event.get("kind", "")) == "status_removed" and str(event.get("target_key", "")) == owner_key:
		var payload: Dictionary = event.get("payload", {})
		var status_id := str(payload.get("status_id", ""))
		if int(payload.get("removed_layers", 0)) <= 0 or status_id not in NEGATIVE_STATUS_IDS \
			or not engine.ready(source_key, "fx09"):
			return []
		var owner := engine.unit(owner_key)
		if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
		var tick := int(event.get("tick", 0))
		var actions: Array = [_counter("fx09_charge", 1), _counter("fx09_expires", tick + 30), _cooldown("fx09", 40)]
		var selected: Dictionary = {}
		for ally in engine.units(str(owner.side)):
			if str(ally.key) == owner_key or _negative_status_types(ally).is_empty(): continue
			if selected.is_empty() or int(ally.get("hp_tenths", 0)) < int(selected.get("hp_tenths", 0)) \
				or (int(ally.get("hp_tenths", 0)) == int(selected.get("hp_tenths", 0)) and int(ally.slot) < int(selected.slot)):
				selected = ally
		if not selected.is_empty():
			var oldest: Dictionary = {}
			for status in selected.get("statuses", []):
				if str(status.get("id", "")) not in NEGATIVE_STATUS_IDS: continue
				if oldest.is_empty() or int(status.get("status_instance_id", 0)) < int(oldest.get("status_instance_id", 0)):
					oldest = status
			if not oldest.is_empty():
				actions.append({"kind":"status_remove", "target_key":str(selected.key), "status_id":str(oldest.id), "layers":1})
		return actions
	if str(event.get("kind", "")) != "before_hit" or str(event.get("source_key", "")) != owner_key \
		or not bool(event.get("is_natural_attack", false)) or bool(event.get("is_extra_attack", false)):
		return []
	var tick := int(event.get("tick", 0))
	if engine.get_counter(source_key, "fx09_charge") <= 0 or engine.get_counter(source_key, "fx09_expires") <= tick:
		return []
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")),
		"patch":{"amount_flat":50, "consume_on_hit":[{"counter_key":"fx09_charge","amount":1}]}}]


func _fx17(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var target := engine.unit(str(event.get("target_key", "")))
	if not _natural_hit_from(event, owner_key) or target.is_empty() or not _has_status(target, "bleed") \
		or not engine.ready(str(binding.get("source_key", "")), "fx17"):
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var ally := _lowest_other(engine, str(owner.side), owner_key)
	if ally.is_empty(): return []
	var owner_bleeds := _status_layers(owner, "bleed")
	var ally_bleeds := _status_layers(ally, "bleed")
	if owner_bleeds <= 0 and ally_bleeds <= 0: return []
	var actions: Array = [_cooldown("fx17", 30)]
	if owner_bleeds > 0: actions.append({"kind":"status_remove", "target_key":owner_key, "status_id":"bleed", "layers":1})
	if ally_bleeds > 0: actions.append({"kind":"status_remove", "target_key":str(ally.key), "status_id":"bleed", "layers":1})
	return actions


func _status_layers(unit: Dictionary, status_id: String) -> int:
	var layers := 0
	for status in unit.get("statuses", []):
		if str(status.get("id", "")) == status_id: layers += int(status.get("layers", 0))
	return layers


func _fx20(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var owner := engine.unit(owner_key)
	if not _natural_hit_from(event, owner_key) or owner.is_empty() \
		or not engine.ready(str(binding.get("source_key", "")), "fx20"):
		return []
	var target := engine.unit(str(event.get("target_key", "")))
	if target.is_empty() or _negative_status_types(target).size() < 2: return []
	var ally: Dictionary = {}
	for candidate in engine.units(str(owner.side)):
		if str(candidate.key) == owner_key or _negative_status_types(candidate).is_empty(): continue
		if ally.is_empty() or int(candidate.get("T_ticks", 0)) > int(ally.get("T_ticks", 0)) \
			or (int(candidate.get("T_ticks", 0)) == int(ally.get("T_ticks", 0)) and int(candidate.slot) < int(ally.slot)):
			ally = candidate
	if ally.is_empty(): return []
	var actions: Array = [_cooldown("fx20", 60)]
	for status_id in _negative_status_types(ally):
		actions.append({"kind":"status_remove", "target_key":str(ally.key), "status_id":status_id,
			"layers":_status_layers(ally, status_id)})
	return actions


func _negative_status_types(unit: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for status in unit.get("statuses", []):
		var status_id := str(status.get("id", ""))
		if status_id in NEGATIVE_STATUS_IDS and int(status.get("layers", 0)) > 0 and status_id not in found:
			found.append(status_id)
	return found


func _eq35(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "before_damage" or str(event.get("target_key", "")) != owner_key \
		or engine.shield_amount(owner_key) <= 0:
		return []
	return [{"kind":"damage_reduction", "amount_bp":2500}]


func _eq38(binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "before_damage" or str(event.get("target_key", "")) != owner_key \
		or str(event.get("damage_type", "")) not in ["fire", "ice", "lightning"]:
		return []
	return [{"kind":"damage_reduction", "amount_bp":3500}]


func _eq33(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner_key) or not engine.ready(str(binding.source_key), "eq33"):
		return []
	var payload: Dictionary = event.get("payload", {})
	if int(payload.get("barrier_absorbed", 0)) <= 0 or int(event.get("actual_hp_loss", 0)) > 0 \
		or int(payload.get("shield_absorbed", 0)) > 0:
		return []
	return [_cooldown("eq33", 20), _shield(owner_key, 70, int(event.tick) + 30)]


func _eq27(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_prepare(event, owner_key): return []
	var count := engine.get_counter(str(binding.source_key), "eq27_natural_count") + 1
	var actions: Array = [_counter("eq27_natural_count", count)]
	var modifier_id := "EQ27:%s:interval" % owner_key
	if count == 1:
		actions.append({"kind":"modifier_add", "target_key":owner_key, "stat":"T_ticks_flat", "amount":-5,
			"modifier_id":modifier_id})
	elif count == 4:
		actions.append({"kind":"modifier_remove", "target_key":owner_key, "modifier_id":modifier_id})
		actions.append({"kind":"modifier_add", "target_key":owner_key, "stat":"T_ticks_flat", "amount":2,
			"modifier_id":modifier_id})
	return actions if count <= 4 else []


func _eq19(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_prepare(event, owner_key): return []
	var source_key := str(binding.source_key)
	var count := engine.get_counter(source_key, "eq19_natural_count") + 1
	var actions: Array = [_counter("eq19_natural_count", count % 3)]
	if count % 3 != 0: return actions
	var context: Dictionary = event.get("payload", {}).get("attack_context", {})
	if str(context.get("damage_type", "physical")) != "physical": return actions
	var segments: Array = context.get("segments", []).duplicate(true)
	if segments.is_empty(): return actions
	segments[0]["armor_piercing"] = 8
	actions.append({"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")), "patch":{"segments":segments}})
	return actions


func _eq24(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var kind := str(event.get("kind", ""))
	if kind == "battle_start":
		pass
	elif kind in ["hp_lost", "healed"]:
		if str(event.get("target_key", "")) != owner_key: return []
		if kind == "hp_lost" and int(event.get("actual_hp_loss", 0)) <= 0: return []
		if kind == "healed" and int(event.get("payload", {}).get("actual_healing", 0)) <= 0: return []
	else:
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	var max_hp := int(engine.effective_stats(owner_key).get("H_max_tenths", 0))
	var qualifies := int(owner.hp_tenths) * 4 > max_hp * 3
	var modifier_id := "EQ24:%s:armor" % owner_key
	var has_modifier := false
	for modifier in owner.get("modifiers", []):
		if str(modifier.get("modifier_id", "")) == modifier_id and str(modifier.get("source_binding_key", "")) == str(binding.source_key):
			has_modifier = true
			break
	if qualifies and not has_modifier:
		return [{"kind":"modifier_add", "target_key":owner_key, "stat":"R_flat", "amount":6, "modifier_id":modifier_id}]
	if not qualifies and has_modifier:
		return [{"kind":"modifier_remove", "target_key":owner_key, "modifier_id":modifier_id}]
	return []


func _eq28(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic": return []
	var owner_key := str(binding.get("owner_key", ""))
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
	var tick := int(event.get("tick", -1))
	if tick < 80 or (tick - 80) % 40 != 0: return []
	var count := engine.get_counter(str(binding.source_key), "eq28_awards")
	if count >= 4: return []
	count += 1
	return [_counter("eq28_awards", count), {"kind":"modifier_add", "target_key":owner_key, "stat":"A_flat", "amount":2,
		"modifier_id":"EQ28:%s:award:%d" % [owner_key, count]}]


func _eq45(binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_prepare(event, owner_key): return []
	var owner_slot := int(owner_key.substr(1))
	var target_slot := int(event.get("target_slot", 0))
	var context: Dictionary = event.get("payload", {}).get("attack_context", {})
	var segments: Array = context.get("segments", [])
	if segments.is_empty(): return []
	var amount := int(segments[0].get("amount", 0))
	var changed := maxi(10, amount + (50 if owner_slot == target_slot else -10))
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")), "patch":{"amount":changed}}]


func _eq46(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_prepare(event, owner_key): return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or int(event.get("target_slot", 0)) == int(owner.slot): return []
	var context: Dictionary = event.get("payload", {}).get("attack_context", {})
	if context.get("segments", []).is_empty(): return []
	var patch := {"amount_flat":40}
	if str(owner.get("reach", "ranged")) == "melee" and not bool(owner.get("flying", false)) \
		and int(context.get("preparation_delay", 0)) > 0:
		patch["preparation_delay_ticks"] = -2
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")), "patch":patch}]


func _natural_prepare(event: Dictionary, owner_key: String) -> bool:
	return str(event.get("kind", "")) == "prepare_attack" and str(event.get("source_key", "")) == owner_key \
		and bool(event.get("is_natural_attack", false)) and not bool(event.get("is_extra_attack", false))


func _eq18(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner) or not engine.ready(str(binding.source_key), "eq18"):
		return []
	return [_cooldown("eq18", 40), {"kind":"heal", "target_key":owner, "amount":40}]


func _eq17(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic" or int(event.get("tick", -1)) < 0 or int(event.tick) % 40 != 0:
		return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty() or owner.get("dead", true): return []
	var earliest: Dictionary = {}
	for status in owner.get("statuses", []):
		if earliest.is_empty() or int(status.get("status_instance_id", 0)) < int(earliest.get("status_instance_id", 0)):
			earliest = status
	if earliest.is_empty(): return []
	return [
		{"kind":"status_remove", "target_key":owner.key, "status_id":str(earliest.get("id", "")), "layers":1},
		_shield(str(owner.key), 40, int(event.tick) + 20),
	]


func _eq25(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "hp_lost" or str(event.get("target_key", "")) != owner_key:
		return []
	if int(event.get("actual_hp_loss", 0)) <= 0 or engine.get_counter(str(binding.source_key), "eq25_used") > 0:
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var stats: Dictionary = engine.effective_stats(owner_key)
	if int(owner.hp_tenths) * 100 > int(stats.get("H_max_tenths", 0)) * 35: return []
	return [_counter("eq25_used", 1), {"kind":"heal", "target_key":owner_key, "amount":80},
		{"kind":"barrier_grant", "target_key":owner_key, "expires_tick":int(event.tick) + 20}]


func _eq40(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner) or not engine.ready(str(binding.source_key), "eq40"):
		return []
	return [_cooldown("eq40", 50), _status(str(event.target_key), "silence", 1, int(event.tick) + 8)]


func _eq41(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner) or not engine.ready(str(binding.source_key), "eq41"):
		return []
	return [_cooldown("eq41", 50), _status(str(event.target_key), "rooted", 1, int(event.tick) + 10)]


func _fx01(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner_key): return []
	var source_key := str(binding.source_key)
	if engine.get_counter(source_key, "fx01_fired") > 0: return []
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	var owner_definition_id := str(owner.get("definition_id", ""))
	if owner_definition_id.begins_with("FIXTURE_"): owner_definition_id = owner_definition_id.trim_prefix("FIXTURE_")
	var owner_sin := CatalogScript.sin_for_definition_id(owner_definition_id)
	var tick := int(event.get("tick", 0))
	var actions: Array = [_counter("fx01_fired", 1)]
	for ally in engine.units(str(owner.side)):
		if str(ally.key) == owner_key or ally.get("dead", true) or ally.get("final_departed", false): continue
		var ally_definition_id := str(ally.get("definition_id", ""))
		if ally_definition_id.begins_with("FIXTURE_"): ally_definition_id = ally_definition_id.trim_prefix("FIXTURE_")
		var ally_sin := CatalogScript.sin_for_definition_id(ally_definition_id)
		var duration := 40 if not owner_sin.is_empty() and ally_sin == owner_sin else 30
		actions.append({"kind":"modifier_add", "target_key":str(ally.key), "stat":"A_flat", "amount":4,
			"modifier_id":"FX01:%s:%s" % [owner_key, str(ally.key)], "expires_tick":tick + duration})
	return actions


func _eq29(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "before_hit" or str(event.get("source_key", "")) != owner_key \
		or not bool(event.get("is_natural_attack", false)) or bool(event.get("is_extra_attack", false)):
		return []
	var context: Dictionary = event.get("payload", {}).get("attack_context", {})
	var segments: Array = context.get("segments", [])
	if segments.is_empty() or str(segments[0].get("damage_type", "")) != "physical": return []
	var target_key := str(event.get("target_key", ""))
	var streak := 0
	var history: Array = engine.state.get("events", [])
	for index in range(history.size() - 1, -1, -1):
		var prior: Dictionary = history[index]
		if str(prior.get("kind", "")) != "hit" or str(prior.get("source_key", "")) != owner_key \
			or not bool(prior.get("is_natural_attack", false)) or bool(prior.get("is_extra_attack", false)):
			continue
		if str(prior.get("target_key", "")) != target_key: break
		streak += 1
	if streak <= 0: return []
	var bonus_tenths := mini(streak, 3) * 20
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")),
		"patch":{"amount_flat":bonus_tenths}}]


func _eq30(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var source_key := str(binding.get("source_key", ""))
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true) or owner.get("final_departed", false): return []
	var kind := str(event.get("kind", ""))
	var enemy_side := "B" if str(owner.side) == "A" else "A"
	if kind == "final_departure":
		if str(event.get("target_side", "")) != enemy_side or int(event.get("target_slot", 0)) != int(owner.get("target_slot", 0)):
			return []
		var tick := int(event.get("tick", 0))
		if engine.get_counter(source_key, "eq30_charge") > 0 \
			and engine.get_counter(source_key, "eq30_expires") > tick:
			return []
		return [_counter("eq30_charge", 1), _counter("eq30_expires", tick + 40)]
	if kind != "before_hit" or str(event.get("source_key", "")) != owner_key \
		or not bool(event.get("is_natural_attack", false)) or bool(event.get("is_extra_attack", false)):
		return []
	var tick := int(event.get("tick", 0))
	if engine.get_counter(source_key, "eq30_charge") <= 0 or engine.get_counter(source_key, "eq30_expires") <= tick:
		return []
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")),
		"patch":{"attached_damage":[{"amount":80,"damage_type":"fixed"}],
			"consume_on_hit":[{"counter_key":"eq30_charge","amount":1}]}}]


func _eq49(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var source_key := str(binding.get("source_key", ""))
	if str(event.get("kind", "")) == "hp_lost" and str(event.get("target_key", "")) == owner_key \
		and bool(event.get("is_redirected", false)) and int(event.get("actual_hp_loss", 0)) > 0:
		var tick := int(event.get("tick", 0))
		if engine.get_counter(source_key, "eq49_charge") > 0 and engine.get_counter(source_key, "eq49_expires") > tick:
			return []
		if not engine.ready(source_key, "eq49"): return []
		return [_counter("eq49_charge", 1), _counter("eq49_expires", tick + 40), _cooldown("eq49", 30)]
	if str(event.get("kind", "")) != "before_hit" or str(event.get("source_key", "")) != owner_key \
		or not bool(event.get("is_natural_attack", false)) or bool(event.get("is_extra_attack", false)):
		return []
	var tick := int(event.get("tick", 0))
	if engine.get_counter(source_key, "eq49_charge") <= 0 or engine.get_counter(source_key, "eq49_expires") <= tick:
		return []
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")),
		"patch":{"amount_flat":80, "consume_on_hit":[{"counter_key":"eq49_charge","amount":1}]}}]


func _fx02(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "hp_lost" or str(event.get("target_key", "")) != owner:
		return []
	if int(event.get("actual_hp_loss", 0)) <= 0 or engine.get_counter(str(binding.source_key), "fx02_used") > 0:
		return []
	var wearer := engine.unit(owner)
	if wearer.is_empty() or wearer.get("dead", true): return []
	var actions: Array = [_counter("fx02_used", 1)]
	for ally in engine.units(str(wearer.side)):
		if str(ally.key) != owner:
			actions.append(_shield(str(ally.key), 80, int(event.tick) + 40))
	return actions


func _fx03(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "shield_broken" or str(event.get("target_key", "")) != owner:
		return []
	if not engine.ready(str(binding.source_key), "fx03"): return []
	var wearer := engine.unit(owner)
	if wearer.is_empty() or wearer.get("dead", true): return []
	var actions: Array = [_cooldown("fx03", 40), {"kind":"heal", "target_key":owner, "amount":30}]
	var ally := _lowest_other(engine, str(wearer.side), owner)
	if not ally.is_empty(): actions.append({"kind":"heal", "target_key":ally.key, "amount":60})
	return actions


func _fx05(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "healed" or str(event.get("target_key", "")) != owner:
		return []
	var restored := int(event.get("payload", {}).get("actual_healing", 0))
	if restored <= 0 or not engine.ready(str(binding.source_key), "fx05"): return []
	var wearer := engine.unit(owner)
	if wearer.is_empty() or wearer.get("dead", true): return []
	var ally := _lowest_other(engine, str(wearer.side), owner)
	if ally.is_empty(): return []
	var amount := mini(50, int(floor(float(restored) / 2.0)))
	if amount <= 0: return []
	return [_cooldown("fx05", 30), {"kind":"heal", "target_key":ally.key, "amount":amount}]


func _fx06(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "shield_gained" or str(event.get("target_key", "")) != owner_key:
		return []
	if int(event.get("payload", {}).get("amount", 0)) <= 0 or not engine.ready(str(binding.source_key), "fx06"):
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var ally: Dictionary = {}
	var lowest_total := 2147483647
	for candidate in engine.units(str(owner.side)):
		if str(candidate.key) == owner_key: continue
		var total := engine.shield_amount(str(candidate.key))
		if total < lowest_total or (total == lowest_total and (ally.is_empty() or int(candidate.slot) < int(ally.slot))):
			ally = candidate
			lowest_total = total
	if ally.is_empty(): return []
	var expires := int(event.tick) + 20
	var actions: Array = [_cooldown("fx06", 30), _shield(str(ally.key), 40, expires)]
	var owner_sin := CatalogScript.sin_for_definition_id(str(owner.definition_id))
	var ally_sin := CatalogScript.sin_for_definition_id(str(ally.definition_id))
	if not owner_sin.is_empty() and owner_sin == ally_sin:
		actions.append(_shield(owner_key, 20, expires))
	return actions


func _fx07(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "hit" or str(event.get("target_key", "")) != owner_key:
		return []
	var payload: Dictionary = event.get("payload", {})
	if int(payload.get("barrier_absorbed", 0)) <= 0 or not engine.ready(str(binding.source_key), "fx07"):
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var ally := _highest_other(engine, str(owner.side), owner_key, "A")
	if ally.is_empty(): return []
	return [_cooldown("fx07", 40), {"kind":"modifier_add", "target_key":ally.key, "stat":"A_flat", "amount":6,
		"modifier_id":"FX07:%s" % owner_key, "expires_tick":int(event.tick) + 30}]


func _fx08(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "status_applied" or str(event.get("target_key", "")) != owner_key:
		return []
	var payload: Dictionary = event.get("payload", {})
	var added := int(payload.get("added_layers", 0))
	if added <= 0 or not engine.ready(str(binding.source_key), "fx08"): return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var status_id := str(payload.get("status_id", ""))
	var current_layers := 0
	for status in owner.get("statuses", []):
		if str(status.get("id", "")) == status_id: current_layers += int(status.get("layers", 0))
	if current_layers - added > 0: return []
	var actions: Array = [_cooldown("fx08", 40)]
	for ally in engine.units(str(owner.side)):
		if str(ally.key) == owner_key: continue
		actions.append({"kind":"modifier_add", "target_key":ally.key, "stat":"R_flat", "amount":3,
			"modifier_id":"FX08:%s:%s" % [owner_key, ally.key], "expires_tick":int(event.tick) + 30})
	return actions


func _fx12(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "shield_broken" or not engine.ready(str(binding.source_key), "fx12"):
		return []
	var owner := engine.unit(owner_key)
	var target := engine.unit(str(event.get("target_key", "")))
	if owner.is_empty() or target.is_empty() or owner.get("dead", true) or target.get("dead", true): return []
	if str(event.get("source_key", "")) != owner_key or str(target.side) == str(owner.side): return []
	var actions: Array = [_cooldown("fx12", 40)]
	for ally in engine.units(str(owner.side)):
		actions.append({"kind":"heal", "target_key":str(ally.key), "amount":40})
	return actions


func _fx18(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "status_applied" or str(event.get("target_key", "")) != owner_key:
		return []
	var payload: Dictionary = event.get("payload", {})
	var added := int(payload.get("added_layers", 0))
	if str(payload.get("status_id", "")) != "silence" or added <= 0 \
		or not engine.ready(str(binding.source_key), "fx18"):
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var current_layers := 0
	for status in owner.get("statuses", []):
		if str(status.get("id", "")) == "silence": current_layers += int(status.get("layers", 0))
	if current_layers - added > 0: return []
	var actions: Array = [_cooldown("fx18", 40)]
	for ally in engine.units(str(owner.side)):
		if str(ally.key) == owner_key: continue
		actions.append({"kind":"modifier_add", "target_key":str(ally.key), "stat":"T_ticks_flat", "amount":-3,
			"modifier_id":"FX18:%s:%s" % [owner_key, ally.key], "expires_tick":int(event.tick) + 20})
	return actions


func _fx31(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner_key) or not engine.ready(str(binding.source_key), "fx31"):
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or int(owner.hp_tenths) < int(engine.effective_stats(owner_key).get("H_max_tenths", 0)):
		return []
	var ally := _lowest_other(engine, str(owner.side), owner_key)
	if ally.is_empty(): return []
	return [_cooldown("fx31", 30), {"kind":"heal", "target_key":str(ally.key), "amount":40}]


func _fx34(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner_key) or not engine.ready(str(binding.source_key), "fx34") \
		or engine.shield_amount(owner_key) < 120:
		return []
	var wearer := engine.unit(owner_key)
	if wearer.is_empty() or wearer.get("dead", true): return []
	var actions: Array = [_cooldown("fx34", 40), {"kind":"shield_consume", "target_key":owner_key, "amount":60, "reason":"FX34"}]
	for ally in engine.units(str(wearer.side)):
		if str(ally.key) != owner_key and not ally.get("dead", true):
			actions.append({"kind":"heal", "target_key":str(ally.key), "amount":40})
	return actions


func _fx33(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "healed" or str(event.get("target_key", "")) != owner_key \
		or int(event.get("payload", {}).get("overheal", 0)) <= 0 or not engine.ready(str(binding.source_key), "fx33"):
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var ally := _lowest_other(engine, str(owner.side), owner_key)
	if ally.is_empty(): return []
	var amount := mini(60, int(floor(float(int(event.payload.overheal)) / 2.0)))
	if amount <= 0: return []
	return [_cooldown("fx33", 20), {"kind":"heal", "target_key":str(ally.key), "amount":amount}]


func _fx36(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "healed" or str(event.get("target_key", "")) != owner_key \
		or int(event.get("payload", {}).get("actual_healing", 0)) <= 0 or not engine.ready(str(binding.source_key), "fx36"):
		return []
	var healer_key := str(event.get("source_key", ""))
	var owner := engine.unit(owner_key)
	var healer := engine.unit(healer_key)
	if owner.is_empty() or healer.is_empty() or healer_key == owner_key or str(healer.side) != str(owner.side) \
		or healer.get("dead", true) or healer.get("final_departed", false):
		return []
	var amount := mini(60, int(floor(float(int(event.payload.actual_healing) * 6000) / 10000.0)))
	if amount <= 0: return []
	return [_cooldown("fx36", 30), _shield(healer_key, amount, int(event.tick) + 30)]


func _fx43(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "healed" or str(event.get("source_key", "")) != owner_key \
		or int(event.get("payload", {}).get("actual_healing", 0)) <= 0:
		return []
	var target_key := str(event.get("target_key", ""))
	var owner := engine.unit(owner_key)
	var target := engine.unit(target_key)
	if owner.is_empty() or target.is_empty() or target_key == owner_key or target.get("dead", true) \
		or str(target.side) != str(owner.side):
		return []
	var counter_key := "fx43_recipient_%s" % target_key
	if engine.get_counter(str(binding.source_key), counter_key) > 0: return []
	return [_counter(counter_key, 1), {"kind":"barrier_grant", "target_key":target_key, "expires_tick":int(event.tick) + 20}]


func _fx44(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "shield_gained" or str(event.get("source_key", "")) != owner_key \
		or int(event.get("payload", {}).get("amount", 0)) <= 0 or not engine.ready(str(binding.source_key), "fx44"):
		return []
	var target := engine.unit(str(event.get("target_key", "")))
	var owner := engine.unit(owner_key)
	if owner.is_empty() or target.is_empty() or target.get("dead", true) or str(target.side) != str(owner.side) \
		or int(owner.hp_tenths) >= int(target.hp_tenths):
		return []
	var healing := mini(50, int(floor(float(int(event.payload.amount) * 4000) / 10000.0)))
	if healing <= 0: return []
	return [_cooldown("fx44", 30), {"kind":"heal", "target_key":owner_key, "amount":healing}]


func _fx21(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if not _natural_hit_from(event, owner_key): return []
	var source_key := str(binding.source_key)
	if not engine.ready(source_key, "fx21"): return []
	var target := engine.unit(str(event.get("target_key", "")))
	if target.is_empty(): return []
	var prior_slot := engine.get_counter(source_key, "fx21_target_slot")
	var count := engine.get_counter(source_key, "fx21_count")
	if prior_slot != int(target.slot): count = 0
	count += 1
	var actions: Array = [_counter("fx21_target_slot", int(target.slot)), _counter("fx21_count", count)]
	if count < 3: return actions
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	actions = [_counter("fx21_target_slot", int(target.slot)), _counter("fx21_count", 0), _cooldown("fx21", 60)]
	for ally in engine.units(str(owner.side)):
		if str(ally.key) == owner_key or int(ally.target_slot) != int(target.slot): continue
		actions.append({"kind":"modifier_add", "target_key":str(ally.key), "stat":"T_ticks_flat", "amount":-3,
			"modifier_id":"FX21:%s:%s:%d" % [owner_key, ally.key, int(target.slot)], "expires_tick":int(event.tick) + 40})
	return actions


func _fx47(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) != "hit" or str(event.get("source_key", "")) != owner_key \
		or not bool(event.get("is_extra_attack", false)) or not engine.ready(str(binding.source_key), "fx47"):
		return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var ally := _lowest_other(engine, str(owner.side), owner_key)
	if ally.is_empty(): return []
	var oldest: Dictionary = {}
	for status in ally.get("statuses", []):
		if str(status.get("id", "")) not in ["chill", "rooted"]: continue
		if oldest.is_empty() or int(status.get("status_instance_id", 0)) < int(oldest.get("status_instance_id", 0)):
			oldest = status
	var actions: Array = [_cooldown("fx47", 30), {"kind":"heal", "target_key":str(ally.key), "amount":30}]
	if not oldest.is_empty():
		actions.append({"kind":"status_remove", "target_key":str(ally.key), "status_id":str(oldest.id), "layers":1})
	return actions


func _fx41(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic": return []
	var tick := int(event.get("tick", -1))
	if tick < 0 or tick % 20 != 0: return []
	var owner_key := str(binding.get("owner_key", ""))
	var owner := engine.unit(owner_key)
	if owner.is_empty() or owner.get("dead", true): return []
	var others := 0
	for ally in engine.units(str(owner.side)):
		if str(ally.key) == owner_key: continue
		others += 1
		if engine.shield_amount(str(ally.key)) <= 0: return []
	if others != 2: return []
	var modifier_id := "FX41:%s:armor" % owner_key
	var existing_modifier := false
	for modifier in owner.get("modifiers", []):
		if str(modifier.get("modifier_id", "")) != modifier_id or str(modifier.get("source_binding_key", "")) != str(binding.source_key): continue
		if int(modifier.get("expires_tick", -1)) > tick: return []
		existing_modifier = true
		break
	var actions: Array = []
	if existing_modifier:
		actions.append({"kind":"modifier_remove", "target_key":owner_key, "modifier_id":modifier_id})
	actions.append({"kind":"modifier_add", "target_key":owner_key, "stat":"R_flat", "amount":5,
		"modifier_id":modifier_id, "expires_tick":tick + 20})
	return actions


func _natural_hit_from(event: Dictionary, owner_key: String) -> bool:
	return str(event.get("kind", "")) == "hit" \
		and bool(event.get("is_natural_attack", false)) \
		and not bool(event.get("is_extra_attack", false)) \
		and str(event.get("source_key", "")) == owner_key \
		and not str(event.get("target_key", "")).is_empty()


func _lowest_other(engine: BattleEngine, side: String, owner_key: String) -> Dictionary:
	var selected: Dictionary = {}
	for ally in engine.units(side):
		if str(ally.key) == owner_key: continue
		if selected.is_empty() or int(ally.hp_tenths) < int(selected.hp_tenths) \
			or (int(ally.hp_tenths) == int(selected.hp_tenths) and int(ally.slot) < int(selected.slot)):
			selected = ally
	return selected


func _has_status(unit: Dictionary, status_id: String) -> bool:
	for status in unit.get("statuses", []):
		if str(status.get("id", "")) == status_id and int(status.get("layers", 0)) > 0: return true
	return false


func _highest_other(engine: BattleEngine, side: String, owner_key: String, stat: String) -> Dictionary:
	var selected: Dictionary = {}
	var selected_value := -1
	for ally in engine.units(side):
		if str(ally.key) == owner_key: continue
		var value := int(engine.effective_stats(str(ally.key)).get(stat, 0))
		if selected.is_empty() or value > selected_value or (value == selected_value and int(ally.slot) < int(selected.slot)):
			selected = ally
			selected_value = value
	return selected


func _shield(target_key: String, amount: int, expires_tick: int) -> Dictionary:
	return {"kind":"shield_grant", "target_key":target_key, "amount":amount, "expires_tick":expires_tick}


func _status(target_key: String, status_id: String, layers: int, expires_tick: int) -> Dictionary:
	return {"kind":"status_add", "target_key":target_key, "status_id":status_id, "layers":layers, "expires_tick":expires_tick}


func _cooldown(cooldown_key: String, ticks: int) -> Dictionary:
	return {"kind":"cooldown", "cooldown_key":cooldown_key, "ticks":ticks}


func _counter(counter_key: String, value: int) -> Dictionary:
	return {"kind":"counter", "counter_key":counter_key, "value":value}
