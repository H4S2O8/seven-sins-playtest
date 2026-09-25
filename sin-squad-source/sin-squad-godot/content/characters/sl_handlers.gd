extends RefCounted
class_name SLHandlers

## Explicit SL handlers. SL03/09/14 require missing preparation/delayed-debt primitives.
const IMPLEMENTED_IDS: Array[String] = ["SL01","SL02","SL04","SL05","SL06","SL07","SL08","SL10","SL11","SL12","SL13"]
const INTEGRATED_IDS: Array[String] = []

func supports_content_id(content_id: String) -> bool:
	return IMPLEMENTED_IDS.has(content_id)

func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	match str(binding.get("content_id","")):
		"SL01": return _sl01(engine,binding,event)
		"SL02": return _sl02(engine,binding,event)
		"SL04": return _sl04(engine,binding,event)
		"SL05": return _sl05(engine,binding,event)
		"SL06": return _sl06(engine,binding,event)
		"SL07": return _sl07(engine,binding,event)
		"SL08": return _sl08(engine,binding,event)
		"SL10": return _sl10(engine,binding,event)
		"SL11": return _sl11(engine,binding,event)
		"SL12": return _sl12(engine,binding,event)
		"SL13": return _sl13(engine,binding,event)
	return []

func _sl01(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "battle_start": return [_counter("last_enemy_loss",-1000)]
	if str(event.get("kind","")) == "hp_lost" and str(event.get("target_key","")) == owner_key:
		var attacker := engine.unit(str(event.get("source_key","")))
		if not attacker.is_empty() and attacker.side != engine.unit(owner_key).side and int(event.get("actual_hp_loss",0)) > 0:
			return [_counter("last_enemy_loss",int(event.get("tick",0)))]
	if str(event.get("kind","")) == "prepare_attack" and _owner_natural(event,binding) and engine.ready(source,"quiet_load"):
		if int(event.get("tick",0))-engine.get_counter(source,"last_enemy_loss") < 20: return []
		return [_cooldown(30,"quiet_load"),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":80,"damage_type":"physical"}]}}]
	return []

func _sl02(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) == "periodic":
		var owner := engine.unit(str(binding.get("owner_key","")))
		if owner.is_empty(): return []
		var actions: Array = []
		for enemy in engine.units("B" if owner.side=="A" else "A",false):
			var due_key := "lamp_due:%s" % str(enemy.key)
			var due := engine.get_counter(str(binding.get("source_key","")),due_key)
			if due > 0 and due <= int(event.get("tick",0)): actions.append(_counter(due_key,0))
		return actions
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding): return []
	var target_key := str(event.get("target_key",""))
	var target := engine.unit(target_key)
	if target.is_empty(): return []
	var source := str(binding.get("source_key",""))
	var due_key := "lamp_due:%s" % target_key
	if engine.get_counter(source,due_key) > 0: return []
	var due := int(event.get("tick",0))+30
	return [_counter(due_key,due),{"kind":"schedule","tick":due,"phase":"damage","independent":true,
		"action":{"kind":"damage","target_key":target_key,"amount":100,"damage_type":"fire"}}]

func _sl04(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	if str(event.get("kind","")) == "hit" and _owner_natural(event,binding):
		var count := engine.get_counter(source,"natural_hits")+1
		if count < 2: return [_counter("natural_hits",count)]
		return [_counter("natural_hits",0),_counter("rest_pending",1)]
	if str(event.get("kind","")) == "prepare_attack" and _owner_natural(event,binding) and engine.get_counter(source,"natural_hits") == 0 and engine.get_counter(source,"rest_pending") > 0:
		return [_counter("rest_pending",0),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"preparation_delay_ticks":10}},
			{"kind":"shield_grant","target_key":str(binding.get("owner_key","")),"amount":100,"expires_tick":int(event.get("tick",0))+20}]
	return []

func _sl05(_engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "prepare_attack" or not _owner_natural(event,binding): return []
	var tick := int(event.get("tick",0))
	return [{"kind":"modifier_add","target_key":str(binding.get("owner_key","")),"stat":"damage_reduction_bp","amount":2500,
		"modifier_id":"SL05:prep_cover:%d" % tick,"expires_tick":tick+12}]

func _sl06(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "periodic" or int(event.get("tick",0)) <= 0 or int(event.tick)%30 != 0: return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty() or int(event.tick)-engine.get_counter(str(binding.get("source_key","")),"last_enemy_loss") < 30: return []
	var target := _lowest(engine.units(str(owner.side),true))
	if target.is_empty(): return []
	return [{"kind":"heal","target_key":str(target.key),"amount":70}]

func _sl07(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	if str(event.get("kind","")) == "battle_start":
		var owner := engine.unit(str(binding.get("owner_key","")))
		if owner.is_empty(): return []
		var allies := engine.units(str(owner.side),true)
		allies.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.slot)<int(b.slot))
		for ally in allies:
			if str(ally.key) != str(owner.key):
				return [_counter("recipient_slot",int(ally.slot)),_counter("recipient_side",1 if ally.side=="A" else 2),
					{"kind":"shield_grant","target_key":str(ally.key),"amount":80,"expires_tick":int(event.get("tick",0))+80}]
	if str(event.get("kind","")) == "expiry" and str(event.get("source_binding_key","")) == source:
		if str(event.get("payload",{}).get("kind","")) != "shield": return []
		var amount := int(event.get("amount",event.get("payload",{}).get("amount",0)))
		var recipient := str(event.get("target_key",""))
		if amount <= 0 or int(recipient.substr(1,1)) != engine.get_counter(source,"recipient_slot"): return []
		if (1 if recipient.begins_with("A") else 2) != engine.get_counter(source,"recipient_side"): return []
		var target := engine.unit(recipient)
		if target.is_empty() or bool(target.dead): return []
		return [{"kind":"heal","target_key":recipient,"amount":amount*2}]
	return []

func _sl08(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding): return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty() or int(owner.target_slot) != int(owner.slot) or not engine.ready(str(binding.get("source_key","")),"parry"): return []
	return [_cooldown(20,"parry"),{"kind":"shield_grant","target_key":str(owner.key),"amount":40,"expires_tick":int(event.get("tick",0))+10}]

func _sl10(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding): return []
	var source := str(binding.get("source_key",""))
	var count := engine.get_counter(source,"natural_hits")+1
	if count < 2: return [_counter("natural_hits",count)]
	return [_counter("natural_hits",0),{"kind":"status_add","target_key":str(event.get("target_key","")),"status_id":"chill","layers":1,"expires_tick":int(event.get("tick",0))+30}]

func _sl11(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding) or not engine.ready(str(binding.get("source_key","")),"late_fee"): return []
	var target := engine.unit(str(event.get("target_key","")))
	var tick := int(event.get("tick",0))
	if target.is_empty() or str(target.get("prepared_attack_id","")).is_empty() or int(target.get("next_attack_tick",tick))-tick < 15: return []
	return [_cooldown(20,"late_fee"),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":60,"damage_type":"fixed"}]}}]

func _sl12(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var tick := int(event.get("tick",0))
	if str(event.get("kind","")) != "periodic" or tick not in [30,90,150]: return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	var target := _current_enemy(engine,owner) if not owner.is_empty() else {}
	if target.is_empty() or str(target.reach) != "melee" or int(target.target_slot) == int(target.slot): return []
	return [{"kind":"status_add","target_key":str(target.key),"status_id":"rooted","layers":1,"expires_tick":tick+15}]

func _sl13(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var tick := int(event.get("tick",0))
	if str(event.get("kind","")) != "periodic" or tick not in [120,180]: return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	var actions: Array = []
	for ally in engine.units(str(owner.side),true):
		if tick == 120: actions.append({"kind":"shield_grant","target_key":str(ally.key),"amount":60,"expires_tick":tick+60})
		else: actions.append({"kind":"heal","target_key":str(ally.key),"amount":50})
	return actions

func _owner_natural(event: Dictionary, binding: Dictionary) -> bool:
	return bool(event.get("is_natural_attack",false)) and not bool(event.get("is_extra_attack",false)) and not bool(event.get("is_attached_damage",false)) and not bool(event.get("is_redirected",false)) and str(event.get("source_key","")) == str(binding.get("owner_key",""))

func _attack_id(event: Dictionary) -> String:
	return str(event.get("attack_id",event.get("payload",{}).get("attack_id","")))

func _counter(key: String, value: int) -> Dictionary:
	return {"kind":"counter","counter_key":key,"value":value}

func _cooldown(ticks: int, key: String) -> Dictionary:
	return {"kind":"cooldown","ticks":ticks,"cooldown_key":key}

func _lowest(candidates: Array) -> Dictionary:
	var selected: Dictionary = {}
	var best := INF
	for candidate in candidates:
		var maximum := int(candidate.get("initial_max_hp_tenths",0))
		var ratio := float(candidate.get("hp_tenths",0))/float(maximum) if maximum>0 else 1.0
		if ratio<best or (is_equal_approx(ratio,best) and (selected.is_empty() or int(candidate.slot)<int(selected.slot))):
			selected=candidate
			best=ratio
	return selected

func _current_enemy(engine: BattleEngine, owner: Dictionary) -> Dictionary:
	for enemy in engine.units("B" if owner.side=="A" else "A",true):
		if int(enemy.slot)==int(owner.target_slot): return enemy
	return {}
