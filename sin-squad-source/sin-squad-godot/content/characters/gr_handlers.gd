extends RefCounted
class_name GRHandlers

## Explicit GR01..GR14 implementations. Unsupported combat semantics remain explicit actions.
## IMPLEMENTED_IDS records behavior presence; INTEGRATED_IDS is backed by true step tests.
const IMPLEMENTED_IDS: Array[String] = ["GR01","GR02","GR03","GR04","GR05","GR06","GR07","GR08","GR09","GR10","GR11","GR12","GR13","GR14"]
const INTEGRATED_IDS: Array[String] = ["GR04","GR09"]
const GR01_COIN_CAP := 4
const GR08_REVIVE_COST := 6


func supports_content_id(content_id: String) -> bool:
	return IMPLEMENTED_IDS.has(content_id)


func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	match str(binding.get("content_id", "")):
		"GR01": return _gr01(engine, binding, event)
		"GR02": return _gr02(engine, binding, event)
		"GR03": return _gr03(engine, binding, event)
		"GR04": return _gr04(engine, binding, event)
		"GR05": return _gr05(engine, binding, event)
		"GR06": return _gr06(engine, binding, event)
		"GR07": return _gr07(engine, binding, event)
		"GR08": return _gr08(engine, binding, event)
		"GR09": return _gr09(engine, binding, event)
		"GR10": return _gr10(engine, binding, event)
		"GR11": return _gr11(engine, binding, event)
		"GR12": return _gr12(engine, binding, event)
		"GR13": return _gr13(engine, binding, event)
		"GR14": return _gr14(engine, binding, event)
	return []


func _gr01(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if event.kind == "hit" and bool(event.get("is_attack", false)) and str(event.get("source_key", "")) == owner_key:
		var coins := mini(GR01_COIN_CAP, engine.get_counter(binding.source_key, "coins") + 1)
		if coins == engine.get_counter(binding.source_key, "coins"): return []
		return [_counter("coins", coins)]
	if event.kind != "hp_lost" or str(event.get("target_key", "")) != owner_key: return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or int(owner.hp_tenths) * 2 >= _max_hp(owner) or not engine.ready(binding.source_key, "draw_coin"): return []
	var coins := engine.get_counter(binding.source_key, "coins")
	if coins <= 0: return []
	var current_shield := engine.shield_amount(owner_key, binding.source_key)
	var grant := mini(160 - current_shield, coins * 40)
	if grant <= 0: return []
	return [_counter("coins", 0), _cooldown(40, "draw_coin"),
		{"kind":"shield_grant", "target_key":owner_key, "amount":grant, "expires_tick":int(event.tick) + 40}]


func _gr02(_engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if event.kind == "prepare_attack" and bool(event.get("is_natural_attack", false)) and str(event.get("source_key", "")) == owner_key:
		var prepared := _engine.get_counter(binding.source_key, "premium_prepared")
		if prepared < 2:
			return [_counter("premium_prepared", prepared + 1),
				{"kind":"attack_patch", "attack_id":_attack_id(event), "patch":{"amount_flat":100}}]
		var debt := _engine.get_counter(binding.source_key, "repayment_prepares")
		if debt > 0:
			return [_counter("repayment_prepares", debt - 1),
				{"kind":"attack_patch", "attack_id":_attack_id(event), "patch":{"preparation_delay_ticks":10}}]
	if event.kind == "hit" and bool(event.get("is_natural_attack", false)) and str(event.get("source_key", "")) == owner_key:
		if _engine.get_counter(binding.source_key, "premium_prepared") == 2 and _engine.get_counter(binding.source_key, "repayment_started") == 0:
			return [_counter("repayment_started", 1), _counter("repayment_prepares", 2)]
	return []


func _gr03(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if event.kind == "prepare_attack" and bool(event.get("is_natural_attack", false)) and str(event.get("source_key", "")) == owner_key:
		if engine.get_counter(binding.source_key, "crate_loaded") == 0 and engine.get_counter(binding.source_key, "crate_spent") == 0:
			return [_counter("crate_loaded", 1), {"kind":"attack_suppress", "attack_id":_attack_id(event), "reason":"first_shot_loads_crate"}]
	if event.kind == "before_hit" and bool(event.get("is_natural_attack", false)) and str(event.get("source_key", "")) == owner_key:
		if engine.get_counter(binding.source_key, "crate_loaded") > 0:
			return [_counter("crate_loaded", 0), _counter("crate_spent", 1),
				{"kind":"attack_patch", "attack_id":_attack_id(event), "patch":{"attached_damage":[{"amount":180,"damage_type":"physical","armor_piercing":4}]}}]
	return []


func _gr04(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind == "periodic" and int(event.tick) in [20, 80, 140]:
		var owner := engine.unit(str(binding.get("owner_key", "")))
		if owner.is_empty(): return []
		var candidates := _other_living(engine, str(owner.side), str(owner.key))
		if candidates.is_empty(): return []
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var left := float(a.hp_tenths) / float(_max_hp(a)); var right := float(b.hp_tenths) / float(_max_hp(b))
			return left < right if left != right else int(a.slot) < int(b.slot))
		var target: Dictionary = candidates[0]
		var raw_key := "loan_absorbed:%s" % target.key
		var due_key := "loan_due:%s" % target.key
		var due_tick := int(event.tick)+40
		return [{"kind":"shield_grant","target_key":target.key,"amount":120,"expires_tick":due_tick},
			_counter(raw_key,0),_counter(due_key,due_tick),
			{"kind":"schedule","tick":due_tick,"phase":"damage","independent":true,"source_key":str(owner.key),
				"action":{"kind":"counter_settlement","target_key":str(owner.key),"counter_key":raw_key,
					"amount_bp":5000,"max_amount":60,"damage_type":"self_loss"}}]
	if event.kind == "shield_absorbed" and str(event.get("source_binding_key", "")) == str(binding.source_key):
		var target_key := str(event.get("target_key", "")); var amount := int(event.get("amount",event.get("payload",{}).get("amount",0)))
		if target_key.is_empty() or amount <= 0: return []
		var raw_key := "loan_absorbed:%s" % target_key
		var due_key := "loan_due:%s" % target_key
		if engine.get_counter(binding.source_key,due_key) <= int(event.tick): return []
		return [_counter(raw_key,mini(120,engine.get_counter(binding.source_key,raw_key)+amount))]
	return []


func _gr05(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "shield_gained": return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	var target := engine.unit(str(event.get("target_key", "")))
	if owner.is_empty() or target.is_empty() or target.side == owner.side or int(owner.target_slot) != int(target.slot): return []
	if not engine.ready(binding.source_key, "tax"): return []
	var growth := int(event.get("amount", event.get("payload", {}).get("amount", 0)))
	if growth <= 0 or str(event.get("source_binding_key", "")) == str(binding.source_key): return []
	var tax := mini(40, int(floor(float(growth * 3000) / 10000.0)))
	if tax <= 0: return []
	return [_cooldown(20,"tax"), {"kind":"shield_consume","target_key":target.key,"amount":tax,
		"source_binding_key":str(event.get("source_binding_key", ""))},
		{"kind":"shield_grant","target_key":owner.key,"amount":tax,"expires_tick":int(event.tick)+30}]


func _gr06(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "healed" or str(event.get("target_key", "")) != str(binding.get("owner_key", "")): return []
	var overheal := int(event.get("overheal", event.get("payload", {}).get("overheal", 0)))
	if overheal <= 0: return []
	var reserve := mini(120, engine.get_counter(binding.source_key,"overheal_reserve") + overheal)
	var actions: Array = [_counter("overheal_reserve", reserve)]
	if reserve >= 60 and engine.ready(binding.source_key,"exchange"):
		var owner := engine.unit(str(binding.owner_key)); var candidates := _other_living(engine,str(owner.side),str(owner.key))
		if not candidates.is_empty():
			candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
				var left := float(a.hp_tenths)/float(_max_hp(a)); var right := float(b.hp_tenths)/float(_max_hp(b))
				return left < right if left != right else int(a.slot)<int(b.slot))
			var target: Dictionary = candidates[0]
			actions.append(_counter("overheal_reserve",reserve-60))
			actions.append({"kind":"shield_grant","target_key":target.key,"amount":50,"expires_tick":int(event.tick)+30})
			actions.append(_cooldown(10,"exchange"))
	return actions


func _gr07(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "shield_broken" or str(event.get("reason", event.get("payload", {}).get("reason", ""))) != "damage": return []
	var owner := engine.unit(str(binding.owner_key))
	if owner.is_empty() or str(event.get("target_side", "")) != str(owner.side): return []
	var target := engine.unit(str(event.get("target_key", "")))
	if target.is_empty() or target.key == str(binding.owner_key) or target.get("dead", false): return []
	if str(event.get("source_binding_key", "")) == str(binding.source_key) or not engine.ready(binding.source_key,"repair"): return []
	return [_cooldown(40,"repair"), {"kind":"shield_grant","target_key":target.key,"amount":60,"expires_tick":int(event.tick)+20}]


func _gr08(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if event.kind == "hit" and bool(event.get("is_natural_attack", false)) and not bool(event.get("is_extra_attack", false)) and str(event.get("source_key", "")) == owner_key:
		var marks := mini(6,engine.get_counter(binding.source_key,"redemption_marks")+1)
		if marks == engine.get_counter(binding.source_key,"redemption_marks"): return []
		return [_counter("redemption_marks",marks)]
	if event.kind == "hp_lost" and str(event.get("target_key", "")) == owner_key and int(event.get("actual_hp_loss", 0)) > 0 and engine.get_counter(binding.source_key,"revive_used") == 0:
		var owner := engine.unit(owner_key)
		if owner.is_empty() or not bool(owner.get("pending_final",false)): return []
		if engine.get_counter(binding.source_key,"redemption_marks") < GR08_REVIVE_COST: return []
		return [_counter("revive_used",1),_counter("redemption_marks",0),
			{"kind":"revive","target_key":owner_key,"amount":180},
			{"kind":"modifier_add","target_key":owner_key,"stat":"T_ticks_flat","amount":4,"modifier_id":"GR08:revived-slow","expires_tick":-1}]
	return []


func _gr09(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind == "periodic" and int(event.tick) > 0 and int(event.tick) % 30 == 0:
		var owner := engine.unit(str(binding.get("owner_key", "")))
		if owner.is_empty(): return []
		var next_slot := engine.get_counter(binding.source_key,"pay_slot")
		if next_slot < 1 or next_slot > 3: next_slot = 1
		var recipient_key := "%s%d" % [owner.side,next_slot]
		var recipient := engine.unit(recipient_key)
		var pending_key := "wage_pending:%s" % recipient_key
		var expiry_key := "wage_expiry:%s" % recipient_key
		var actions: Array = [_counter("pay_slot",1 if next_slot == 3 else next_slot+1),_counter(pending_key,0),_counter(expiry_key,0)]
		if not recipient.is_empty() and not recipient.get("dead",false):
			actions.append(_counter(pending_key,1)); actions.append(_counter(expiry_key,int(event.tick)+40))
		return actions
	if event.kind == "prepare_attack" and bool(event.get("is_natural_attack",false)):
		var owner := engine.unit(str(binding.get("owner_key", "")))
		var recipient_key := str(event.get("source_key", ""))
		if owner.is_empty() or recipient_key not in ["%s1" % owner.side,"%s2" % owner.side,"%s3" % owner.side]: return []
		var pending_key := "wage_pending:%s" % recipient_key
		var expiry_key := "wage_expiry:%s" % recipient_key
		if engine.get_counter(binding.source_key,pending_key) <= 0: return []
		if int(event.tick) >= engine.get_counter(binding.source_key,expiry_key): return [_counter(pending_key,0),_counter(expiry_key,0)]
		return [_counter(pending_key,0),_counter(expiry_key,0),{"kind":"attack_patch","attack_id":_attack_id(event),
			"patch":{"amount_flat":50}}]
	return []


func _gr10(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "before_hit" or not bool(event.get("is_natural_attack",false)) or str(event.get("source_key", "")) != str(binding.get("owner_key", "")):
		return []
	var owner := engine.unit(str(binding.owner_key)); var target := engine.unit(str(event.get("target_key", "")))
	if owner.is_empty() or target.is_empty() or not engine.ready(binding.source_key,"audit"): return []
	var self_shield := engine.shield_amount(owner.key); var target_shield := engine.shield_amount(target.key)
	var converted := mini(60,target_shield-self_shield)
	if converted <= 0: return []
	return [_cooldown(20,"audit"),{"kind":"attack_patch","attack_id":_attack_id(event),
		"patch":{"convert_physical_to_fixed_bypass_shield":converted}}]


func _gr11(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	if event.kind == "hit" and bool(event.get("is_natural_attack",false)) and not bool(event.get("is_extra_attack",false)) and str(event.get("source_key", "")) == owner_key:
		var target_key := str(event.get("target_key", ""))
		return [_counter("contract_target_slot",int(target_key.substr(1))),_counter("contract_target_side",1 if target_key.begins_with("A") else 2),_counter("contract_until",int(event.tick)+20)]
	if event.kind == "before_hit" and bool(event.get("is_natural_attack",false)) and not bool(event.get("is_extra_attack",false)):
		var source := engine.unit(str(event.get("source_key", ""))); var target := engine.unit(str(event.get("target_key", "")))
		var owner := engine.unit(owner_key)
		if source.is_empty() or target.is_empty() or owner.is_empty() or source.side != owner.side or source.key == owner_key: return []
		var target_side := "A" if engine.get_counter(binding.source_key,"contract_target_side")==1 else "B"
		if target.side != target_side or int(target.slot) != engine.get_counter(binding.source_key,"contract_target_slot") or int(event.tick) >= engine.get_counter(binding.source_key,"contract_until"): return []
		return [_counter("contract_target_slot",0),_counter("contract_target_side",0),_counter("contract_until",0),
			{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"amount_flat":70}}]
	return []


func _gr12(_engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "before_damage" or str(event.get("target_key", "")) != str(binding.get("owner_key", "")): return []
	var eligible := int(event.get("amount_before_shield",event.get("payload",{}).get("amount_before_shield",0))); var deferred := mini(80,eligible)
	if deferred <= 0 or not _engine.ready(binding.source_key,"debt"): return []
	return [_cooldown(30,"debt"),{"kind":"defer_damage","target_key":str(binding.owner_key),
		"source_key":str(event.get("source_key", "")),"source_binding_key":str(event.get("source_binding_key", "")),
		"amount":deferred,"due_tick":int(event.tick)+20,"skip_armor_and_reduction":true,"enter_shield_step":true}]


func _gr13(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "hp_lost" or str(event.get("source_key", "")) != str(binding.get("owner_key", "")): return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	var target := engine.unit(str(event.get("target_key", "")))
	if owner.is_empty() or target.is_empty() or target.side == owner.side: return []
	var damage_type := str(event.get("damage_type",event.get("payload",{}).get("damage_type","")))
	if damage_type not in ["physical","fire","ice","lightning","poison"] or int(event.get("actual_hp_loss",0)) <= 0: return []
	var key := "damage_type:%s" % damage_type
	if engine.get_counter(binding.source_key,key) > 0 or not engine.ready(binding.source_key,"exchange"): return []
	var count := engine.get_counter(binding.source_key,"type_count")+1
	var actions: Array = [_counter(key,1),_counter("type_count",count)]
	if count >= 3:
		for side in ["A","B"]:
			for ally in engine.units(side,true): actions.append({"kind":"heal","target_key":ally.key,"amount":40})
		for seen_type in ["physical","fire","ice","lightning","poison"]: actions.append(_counter("damage_type:%s" % seen_type,0))
		actions.append(_counter("type_count",0)); actions.append(_cooldown(30,"exchange"))
	return actions


func _gr14(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if event.kind != "periodic" or int(event.tick) <= 0 or int(event.tick)%60 != 0: return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty(): return []
	var spent := mini(100,engine.shield_amount(owner.key))
	if spent <= 0: return []
	var actions: Array = [{"kind":"shield_consume","target_key":owner.key,"amount":spent}]
	for ally in engine.units(str(owner.side),true):
		if str(ally.key) == str(owner.key): continue
		var healing := int(floor(float(spent*6000)/10000.0))
		if healing > 0: actions.append({"kind":"heal","target_key":ally.key,"amount":healing})
	return actions


func _counter(key: String, value: int) -> Dictionary:
	return {"kind":"counter","counter_key":key,"value":value}


func _cooldown(ticks: int, key: String) -> Dictionary:
	return {"kind":"cooldown","ticks":ticks,"cooldown_key":key}


func _attack_id(event: Dictionary) -> String:
	var attack_id := str(event.get("attack_id",event.get("payload",{}).get("attack_id","")))
	assert(not attack_id.is_empty(),"integration_blocked: event must expose stable attack_id")
	return attack_id


func _other_living(engine: BattleEngine, side: String, owner_key: String) -> Array:
	var result: Array = []
	for ally in engine.units(side,true):
		if str(ally.key) != owner_key: result.append(ally)
	return result


func _max_hp(unit_state: Dictionary) -> int:
	if unit_state.has("max_hp_tenths"): return int(unit_state.max_hp_tenths)
	if unit_state.has("initial_max_hp_tenths"): return int(unit_state.initial_max_hp_tenths)
	return int(unit_state.get("H",0))*10
