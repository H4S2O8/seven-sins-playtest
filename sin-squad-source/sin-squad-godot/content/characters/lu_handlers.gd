extends RefCounted
class_name LUHandlers

## Explicit LU-family handlers. Missing interval, capped-reduction, and status-time primitives remain unsupported.
const IMPLEMENTED_IDS: Array[String] = ["LU03","LU04","LU06","LU08","LU09","LU10","LU11","LU12","LU13"]
const INTEGRATED_IDS: Array[String] = []

func supports_content_id(content_id: String) -> bool:
	return IMPLEMENTED_IDS.has(content_id)

func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	match str(binding.get("content_id","")):
		"LU03": return _lu03(engine,binding,event)
		"LU04": return _lu04(engine,binding,event)
		"LU06": return _lu06(engine,binding,event)
		"LU08": return _lu08(engine,binding,event)
		"LU09": return _lu09(engine,binding,event)
		"LU10": return _lu10(engine,binding,event)
		"LU11": return _lu11(engine,binding,event)
		"LU12": return _lu12(engine,binding,event)
		"LU13": return _lu13(engine,binding,event)
	return []

func _lu03(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding) or not engine.ready(str(binding.get("source_key","")),"crossline"): return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	var candidates: Array = []
	for ally in _others(engine,str(owner.side),str(owner.key)):
		if int(ally.target_slot) != int(owner.target_slot): candidates.append(ally)
	var target := _lowest(candidates)
	if target.is_empty(): return []
	return [_cooldown(20,"crossline"),{"kind":"heal","target_key":str(target.key),"amount":40}]

func _lu04(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hit" or not _natural(event): return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	var attacker := engine.unit(str(event.get("source_key","")))
	var target := engine.unit(str(event.get("target_key","")))
	if owner.is_empty() or attacker.is_empty() or target.is_empty() or attacker.side != owner.side: return []
	var source := str(binding.get("source_key",""))
	var tick := int(event.get("tick",0))
	var attacker_key := str(attacker.key)
	var latest_key := "hit_tick:%s" % attacker_key
	var paired_key := "paired_tick:%s" % attacker_key
	var old_tick := engine.get_counter(source,latest_key)
	var old_target_slot := engine.get_counter(source,"hit_target_slot:%s" % attacker_key)
	var old_target_side := engine.get_counter(source,"hit_target_side:%s" % attacker_key)
	var actions: Array = [_counter(latest_key,tick),_counter("hit_target_slot:%s" % attacker_key,int(target.slot)),
		_counter("hit_target_side:%s" % attacker_key,1 if target.side=="A" else 2)]
	var match_key := ""
	var match_gap := 100000
	if attacker.key == owner.key:
		for ally in _others(engine,str(owner.side),str(owner.key)):
			var ally_tick := engine.get_counter(source,"hit_tick:%s" % str(ally.key))
			var gap := tick-ally_tick
			if ally_tick <= 0 or gap < 0 or gap > 10 or engine.get_counter(source,"paired_tick:%s" % str(ally.key)) == ally_tick: continue
			if engine.get_counter(source,"hit_target_slot:%s" % str(ally.key)) != int(target.slot) or engine.get_counter(source,"hit_target_side:%s" % str(ally.key)) != (1 if target.side=="A" else 2): continue
			if gap < match_gap or (gap == match_gap and (match_key.is_empty() or int(ally.slot)<int(match_key.substr(1,1)))):
				match_key = str(ally.key); match_gap = gap
	else:
		var gap := tick-engine.get_counter(source,"hit_tick:%s" % str(owner.key))
		if (gap >= 0 and gap <= 10
		and engine.get_counter(source,"paired_tick:%s" % str(owner.key)) != engine.get_counter(source,"hit_tick:%s" % str(owner.key))
		and engine.get_counter(source,"hit_target_slot:%s" % str(owner.key)) == int(target.slot)
		and engine.get_counter(source,"hit_target_side:%s" % str(owner.key)) == (1 if target.side=="A" else 2)):
			match_key = str(owner.key); match_gap = gap
	if not match_key.is_empty() and engine.ready(source,"reunion"):
		var partner := engine.unit(match_key)
		actions.append(_counter("paired_tick:%s" % attacker_key,tick))
		actions.append(_counter("paired_tick:%s" % match_key,engine.get_counter(source,"hit_tick:%s" % match_key) if match_key != attacker_key else tick))
		actions.append(_cooldown(30,"reunion"))
		actions.append({"kind":"shield_grant","target_key":str(owner.key),"amount":40,"expires_tick":tick+20})
		actions.append({"kind":"shield_grant","target_key":str(partner.key),"amount":40,"expires_tick":tick+20})
	return actions

func _lu06(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding): return []
	var source := str(binding.get("source_key",""))
	var count := engine.get_counter(source,"natural_hits")+1
	if count not in [2,5]: return [_counter("natural_hits",count)]
	return [_counter("natural_hits",count),{"kind":"status_add","target_key":str(event.get("target_key","")),"status_id":"silence","layers":1,"expires_tick":int(event.get("tick",0))+12}]

func _lu08(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var kind := str(event.get("kind",""))
	var target_key := str(event.get("target_key",""))
	if kind == "status_applied" and target_key != str(binding.get("owner_key","")):
		var status_id := str(event.get("status_id",event.get("payload",{}).get("status_id","")))
		var owner := engine.unit(str(binding.get("owner_key","")))
		var target := engine.unit(target_key)
		if status_id != "silence" or owner.is_empty() or target.is_empty() or owner.side != target.side or target.key == owner.key or not engine.ready(source,"comfort:%s" % target_key): return []
		var cycle := int(event.get("status_cycle_id",event.get("payload",{}).get("status_cycle_id",event.get("status_instance_id",0))))
		return [_cooldown(50,"comfort:%s" % target_key),_counter("silence_cycle:%s" % target_key,cycle),
			{"kind":"shield_grant","target_key":target_key,"amount":70,"expires_tick":int(event.get("tick",0))+20}]
	if kind in ["status_removed","expiry"] and str(event.get("status_id",event.get("payload",{}).get("status_id",""))) == "silence":
		var cycle := int(event.get("status_cycle_id",event.get("payload",{}).get("status_cycle_id",event.get("status_instance_id",0))))
		var recipient := engine.unit(target_key)
		if recipient.is_empty() or bool(recipient.dead) or cycle != engine.get_counter(source,"silence_cycle:%s" % target_key): return []
		return [_counter("silence_cycle:%s" % target_key,0),{"kind":"heal","target_key":target_key,"amount":40}]
	return []

func _lu09(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	if str(event.get("kind","")) == "hit" and _natural(event):
		var attacker := engine.unit(str(event.get("source_key","")))
		var owner := engine.unit(str(binding.get("owner_key","")))
		if attacker.is_empty() or owner.is_empty() or attacker.side != owner.side: return []
		var key := str(attacker.key)
		return [_counter("last_hit:%s" % key,int(event.get("tick",0))),_counter("hit_seen:%s" % key,1)]
	if str(event.get("kind","")) != "periodic" or int(event.get("tick",0)) <= 0 or int(event.tick)%50 != 0: return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	var allies := engine.units(str(owner.side),true)
	if allies.size() != 3: return []
	for ally in allies:
		if engine.get_counter(source,"hit_seen:%s" % str(ally.key)) <= 0 or int(event.tick)-engine.get_counter(source,"last_hit:%s" % str(ally.key)) > 50: return []
	var actions: Array = []
	for ally in allies: actions.append({"kind":"heal","target_key":str(ally.key),"amount":50})
	return actions

func _lu10(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hp_lost" or int(event.get("actual_hp_loss",0)) <= 0: return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	var target := engine.unit(str(event.get("target_key","")))
	if owner.is_empty() or target.is_empty() or owner.side != target.side or owner.key == target.key: return []
	var before := int(event.get("batch_hp_before_tenths",event.get("payload",{}).get("batch_hp_before_tenths",0)))
	var after := int(event.get("batch_hp_after_tenths",event.get("payload",{}).get("batch_hp_after_tenths",target.hp_tenths)))
	if before*100 > int(target.initial_max_hp_tenths)*30 or after*100 > int(target.initial_max_hp_tenths)*30 or after <= 0 or int(owner.hp_tenths) <= 80: return []
	var source := str(binding.get("source_key",""))
	var key := "saved:%s" % str(target.key)
	if engine.get_counter(source,key) > 0: return []
	return [_counter(key,1),{"kind":"self_loss","target_key":str(owner.key),"amount":80},
		{"kind":"shield_grant","target_key":str(target.key),"amount":140,"expires_tick":int(event.get("tick",0))+30}]

func _lu11(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	if str(event.get("kind","")) == "before_hit" and _owner_natural(event,binding):
		var target := engine.unit(str(event.get("target_key","")))
		var side := "A" if engine.get_counter(source,"memory_target_side")==1 else "B"
		if (target.is_empty() or str(target.side)!=side or int(target.slot)!=engine.get_counter(source,"memory_target_slot")
		or int(event.get("tick",0))>=engine.get_counter(source,"memory_expiry") or engine.get_counter(source,"memory_charges")<=0): return []
		return [_counter("memory_charges",engine.get_counter(source,"memory_charges")-1),
			{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":60,"damage_type":"ice"}]}}]
	if str(event.get("kind","")) != "final_departure": return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	var departed := engine.unit(str(event.get("target_key","")))
	if owner.is_empty() or departed.is_empty() or owner.side != departed.side or departed.key == owner.key: return []
	if engine.get_counter(source,"memory_created") > 0: return []
	var enemy_side := "B" if owner.side=="A" else "A"
	var slot := int(departed.target_slot)
	var living := engine.units(enemy_side,true)
	for enemy in living:
		if int(enemy.slot)==slot:
			return [_counter("memory_created",1),_counter("memory_target_slot",slot),_counter("memory_target_side",1 if enemy.side=="A" else 2),
				_counter("memory_expiry",int(event.get("tick",0))+40),_counter("memory_charges",2)]
	return []

func _lu12(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "battle_start":
		var owner := engine.unit(owner_key)
		if owner.is_empty(): return []
		var others := _others(engine,str(owner.side),owner_key)
		others.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if int(a.base_H)!=int(b.base_H): return int(a.base_H)<int(b.base_H)
			return int(a.slot)<int(b.slot))
		if others.is_empty(): return []
		return [_counter("locked_target_slot",int(others[0].slot)),_counter("locked_target_side",1 if others[0].side=="A" else 2)]
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding): return []
	var count := engine.get_counter(source,"natural_hits")+1
	if count<3: return [_counter("natural_hits",count)]
	var side := "A" if engine.get_counter(source,"locked_target_side")==1 else "B"
	var target_key := "%s%d" % [side,engine.get_counter(source,"locked_target_slot")]
	var target := engine.unit(target_key)
	var actions: Array = [_counter("natural_hits",0)]
	if not target.is_empty() and not bool(target.dead):
		actions.append({"kind":"heal","target_key":target_key,"amount":70})
		var bleed := _layers(target,"bleed")
		if bleed>0: actions.append({"kind":"status_remove","target_key":target_key,"status_id":"bleed","layers":1})
	return actions

func _lu13(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	var source := str(binding.get("source_key",""))
	if str(event.get("kind","")) == "battle_start":
		var paired: Dictionary = {}
		var enemy_side := "B" if owner.side=="A" else "A"
		for enemy in engine.units(enemy_side,true):
			if int(owner.target_slot)==int(enemy.slot) and int(enemy.target_slot)==int(owner.slot): paired=enemy; break
		if paired.is_empty(): return []
		return [_counter("bonded",1),_counter("bonded_enemy_slot",int(paired.slot)),_counter("bonded_enemy_side",1 if paired.side=="A" else 2),
			{"kind":"shield_grant","target_key":str(owner.key),"amount":80,"expires_tick":int(event.get("tick",0))+40}]
	if str(event.get("kind","")) == "final_departure":
		var departed := str(event.get("target_key",""))
		var bonded_side := "A" if engine.get_counter(source,"bonded_enemy_side")==1 else "B"
		var bonded_key := "%s%d" % [bonded_side,engine.get_counter(source,"bonded_enemy_slot")]
		if departed == str(owner.key) or (engine.get_counter(source,"bonded")>0 and departed == bonded_key):
			return [_counter("bonded",0)]
		return []
	if str(event.get("kind","")) != "periodic" or int(event.get("tick",0))<=0 or int(event.tick)%40!=0 or engine.get_counter(source,"bonded")<=0: return []
	var side := "A" if engine.get_counter(source,"bonded_enemy_side")==1 else "B"
	var enemy := engine.unit("%s%d" % [side,engine.get_counter(source,"bonded_enemy_slot")])
	if enemy.is_empty() or bool(enemy.dead): return []
	var target := _lowest(_others(engine,str(owner.side),str(owner.key)))
	if target.is_empty(): return []
	return [{"kind":"shield_grant","target_key":str(target.key),"amount":50,"expires_tick":int(event.tick)+20}]

func _owner_natural(event: Dictionary, binding: Dictionary) -> bool:
	return _natural(event) and str(event.get("source_key","")) == str(binding.get("owner_key",""))

func _natural(event: Dictionary) -> bool:
	return bool(event.get("is_natural_attack",false)) and not bool(event.get("is_extra_attack",false)) and not bool(event.get("is_attached_damage",false)) and not bool(event.get("is_redirected",false))

func _attack_id(event: Dictionary) -> String:
	return str(event.get("attack_id",event.get("payload",{}).get("attack_id","")))

func _counter(key: String,value: int) -> Dictionary:
	return {"kind":"counter","counter_key":key,"value":value}

func _cooldown(ticks: int,key: String) -> Dictionary:
	return {"kind":"cooldown","ticks":ticks,"cooldown_key":key}

func _others(engine: BattleEngine,side: String,owner_key: String) -> Array:
	var result: Array=[]
	for ally in engine.units(side,true):
		if str(ally.key)!=owner_key: result.append(ally)
	return result

func _lowest(candidates: Array) -> Dictionary:
	var selected: Dictionary={}
	var best:=INF
	for candidate in candidates:
		var maximum:=int(candidate.get("initial_max_hp_tenths",0))
		var ratio:=float(candidate.get("hp_tenths",0))/float(maximum) if maximum>0 else 1.0
		if ratio<best or (is_equal_approx(ratio,best) and (selected.is_empty() or int(candidate.slot)<int(selected.slot))):
			selected=candidate
			best=ratio
	return selected

func _layers(unit_state: Dictionary,status_id: String) -> int:
	var count:=0
	for status in unit_state.get("statuses",[]):
		if str(status.get("id",""))==status_id: count+=int(status.get("layers",0))
	return count
