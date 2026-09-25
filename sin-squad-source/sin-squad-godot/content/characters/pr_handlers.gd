extends RefCounted
class_name PRHandlers

## Explicit PR handlers. PR07 needs a fixed-but-shieldable, reduction-bypassing segment.
## PR11 needs attack-caused shield-break and external-bonus attribution in the event payload.
const IMPLEMENTED_IDS: Array[String] = ["PR01","PR02","PR03","PR04","PR05","PR06","PR08","PR09","PR10","PR12","PR13","PR14"]
const INTEGRATED_IDS: Array[String] = []

func supports_content_id(content_id: String) -> bool:
	return IMPLEMENTED_IDS.has(content_id)

func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	match str(binding.get("content_id","")):
		"PR01": return _pr01(engine,binding,event)
		"PR02": return _pr02(engine,binding,event)
		"PR03": return _pr03(engine,binding,event)
		"PR04": return _pr04(engine,binding,event)
		"PR05": return _pr05(engine,binding,event)
		"PR06": return _pr06(engine,binding,event)
		"PR08": return _pr08(engine,binding,event)
		"PR09": return _pr09(engine,binding,event)
		"PR10": return _pr10(engine,binding,event)
		"PR12": return _pr12(engine,binding,event)
		"PR13": return _pr13(engine,binding,event)
		"PR14": return _pr14(engine,binding,event)
	return []

func _pr01(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "prepare_attack" or not _owner_natural(event,binding): return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	for ally in _others(engine,str(owner.side),str(owner.key)):
		if int(ally.target_slot)==int(owner.target_slot): return []
	return [{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"amount_flat":50}}]

func _pr02(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "battle_start":
		var owner := engine.unit(owner_key)
		if owner.is_empty(): return []
		for enemy in engine.units("B" if owner.side=="A" else "A",true):
			if int(owner.target_slot)==int(enemy.slot) and int(enemy.target_slot)==int(owner.slot):
				return [_counter("duel_target_slot",int(enemy.slot)),_counter("duel_target_side",1 if enemy.side=="A" else 2)]
		return []
	if str(event.get("kind","")) != "hp_lost" or not _owner_natural(event,binding) or str(event.get("source_key","")) != owner_key or int(event.get("actual_hp_loss",0))<=0: return []
	var target := engine.unit(str(event.get("target_key","")))
	var owner := engine.unit(owner_key)
	var tick := int(event.get("tick",0))
	var side := "A" if engine.get_counter(source,"duel_target_side")==1 else "B"
	if owner.is_empty() or target.is_empty() or str(target.side)!=side or int(target.slot)!=engine.get_counter(source,"duel_target_slot") or bool(target.dead) or not engine.ready(source,"duel_heal"): return []
	var healing := mini(40,int(floor(float(int(event.get("actual_hp_loss",0))*20)/100.0)))
	if healing<=0: return []
	return [_cooldown(10,"duel_heal"),{"kind":"heal","target_key":owner_key,"amount":healing}]

func _pr03(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	if str(event.get("kind","")) == "battle_start":
		var initial: Array = []
		for enemy in engine.units("B" if owner.side=="A" else "A",true):
			initial.append(_counter("last_other_damage:%s" % str(enemy.key),-1000))
		return initial
	if str(event.get("kind","")) == "hp_lost":
		var attacker := engine.unit(str(event.get("source_key","")))
		var target := engine.unit(str(event.get("target_key","")))
		if attacker.is_empty() or target.is_empty() or attacker.side!=owner.side or attacker.key==owner.key or target.side==owner.side or int(event.get("actual_hp_loss",0))<=0: return []
		return [_counter("last_other_damage:%s" % str(target.key),int(event.get("tick",0)))]
	if str(event.get("kind","")) != "before_hit" or not _owner_natural(event,binding): return []
	var target := engine.unit(str(event.get("target_key","")))
	if target.is_empty() or int(event.get("tick",0))-engine.get_counter(source,"last_other_damage:%s" % str(target.key)) < 20: return []
	var armor := int(engine.effective_stats(str(target.key)).get("R",target.R))
	var ignored := mini(5,int(floor(float(armor)/2.0)))
	if ignored<=0: return []
	return [{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"armor_piercing":ignored}}]

func _pr04(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "battle_start":
		var owner := engine.unit(owner_key)
		if owner.is_empty(): return []
		var incoming := 0
		for enemy in engine.units("B" if owner.side=="A" else "A",true):
			if int(enemy.target_slot)==int(owner.slot): incoming+=1
		return [_counter("flag_active",1 if incoming>=2 else 0),_counter("flag_expiry",int(event.get("tick",0))+60),_counter("flag_heals",0)]
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding) or engine.get_counter(source,"flag_active")==0 or int(event.get("tick",0))>=engine.get_counter(source,"flag_expiry") or engine.get_counter(source,"flag_heals")>=3 or not engine.ready(source,"flag_cooldown"): return []
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	var actions: Array=[_counter("flag_heals",engine.get_counter(source,"flag_heals")+1),_cooldown(20,"flag_cooldown")]
	for ally in _others(engine,str(owner.side),owner_key):
		actions.append({"kind":"heal","target_key":str(ally.key),"amount":30})
	return actions

func _pr05(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "battle_start": return [_counter("pristine",1)]
	if str(event.get("kind","")) == "hp_lost" and str(event.get("target_key","")) == owner_key and int(event.get("actual_hp_loss",0))>0:
		var attacker := engine.unit(str(event.get("source_key","")))
		if not attacker.is_empty() and attacker.side!=engine.unit(owner_key).side:
			return [_counter("pristine",0)]
	if str(event.get("kind","")) == "prepare_attack" and _owner_natural(event,binding) and engine.get_counter(source,"pristine")>0:
		return [{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":40,"damage_type":"fixed"}]}}]
	return []

func _pr06(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "before_hit" or not _owner_natural(event,binding) or not engine.ready(str(binding.get("source_key","")),"clean_cut"): return []
	var target := engine.unit(str(event.get("target_key","")))
	if target.is_empty() or engine.shield_amount(str(target.key))>0 or bool(target.get("barrier",{}).get("active",false)): return []
	for status in target.get("statuses",[]):
		if str(status.get("id","")) in ["burn","bleed","poison","chill","rooted","silence"] and int(status.get("expires_tick",-1))>int(event.get("tick",0)): return []
	return [_cooldown(20,"clean_cut"),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":70,"damage_type":"physical"}]}}]

func _pr08(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "periodic" or int(event.get("tick",0))<=0 or int(event.tick)%40!=0: return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	for status in owner.get("statuses",[]):
		if str(status.get("id","")) in ["burn","bleed","poison","chill","rooted","silence"] and int(status.get("expires_tick",-1))>int(event.tick): return []
	if engine.shield_amount(str(owner.key),str(binding.get("source_key","")))>0: return []
	return [{"kind":"shield_grant","target_key":str(owner.key),"amount":100,"expires_tick":int(event.tick)+30}]

func _pr09(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding): return []
	var target := engine.unit(str(event.get("target_key","")))
	if target.is_empty(): return []
	var source := str(binding.get("source_key",""))
	var key := "attempted:%s" % str(target.key)
	if engine.get_counter(source,key)>0 or engine.get_counter(source,"attempts")>=3: return []
	var attempts := engine.get_counter(source,"attempts")+1
	var actions: Array=[_counter(key,1),_counter("attempts",attempts)]
	if int(event.get("actual_hp_loss",0))>=100:
		actions.append({"kind":"status_add","target_key":str(target.key),"status_id":"rooted","layers":1,"expires_tick":int(event.get("tick",0))+15})
	return actions

func _pr10(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	if str(event.get("kind","")) == "battle_start":
		for ally in engine.units(str(owner.side),true):
			if int(ally.target_slot)!=int(ally.slot): return []
		return [_counter("correction_active",1),_counter("correction_expiry",int(event.get("tick",0))+40)]
	if str(event.get("kind","")) != "before_hit" or not bool(event.get("is_natural_attack",false)) or bool(event.get("is_extra_attack",false)) or int(event.get("tick",0))>=engine.get_counter(source,"correction_expiry") or engine.get_counter(source,"correction_active")==0: return []
	var attacker := engine.unit(str(event.get("source_key","")))
	if attacker.is_empty() or attacker.side!=owner.side: return []
	var key := "used_slot:%d" % int(attacker.slot)
	if engine.get_counter(source,key)>0: return []
	return [_counter(key,1),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":50,"damage_type":"physical"}]}}]

func _pr12(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key",""))
	var source := str(binding.get("source_key",""))
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	if str(event.get("kind","")) == "final_departure" and str(event.get("target_side",""))==str(owner.side) and engine.get_counter(source,"king_awakened")==0:
		if engine.units(str(owner.side),true).size()!=1 or bool(owner.dead): return []
		return [_counter("king_awakened",1),_counter("king_expiry",int(event.get("tick",0))+50),_counter("king_charges",2),
			{"kind":"shield_grant","target_key":owner_key,"amount":140,"expires_tick":int(event.get("tick",0))+40}]
	if str(event.get("kind","")) == "before_hit" and _owner_natural(event,binding) and engine.get_counter(source,"king_charges")>0 and int(event.get("tick",0))<engine.get_counter(source,"king_expiry"):
		return [_counter("king_charges",engine.get_counter(source,"king_charges")-1),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":60,"damage_type":"lightning"}]}}]
	return []

func _pr13(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	if str(event.get("kind","")) == "battle_start":
		var enemies := engine.units("B" if owner.side=="A" else "A",true)
		enemies.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if int(a.base_H)!=int(b.base_H): return int(a.base_H)>int(b.base_H)
			return int(a.slot)<int(b.slot))
		var actions: Array=[_counter("exam_count",enemies.size())]
		for index in range(enemies.size()):
			actions.append(_counter("exam_slot:%d" % index,int(enemies[index].slot)))
			actions.append(_counter("exam_side:%d" % index,1 if enemies[index].side=="A" else 2))
		return actions
	if str(event.get("kind","")) != "final_departure" or str(event.get("target_side",""))==str(owner.side): return []
	var stage := engine.get_counter(source,"exam_stage")
	if stage>=2 or stage>=engine.get_counter(source,"exam_count"): return []
	var enemy_side := "A" if engine.get_counter(source,"exam_side:%d" % stage)==1 else "B"
	var target_key := "%s%d" % [enemy_side,engine.get_counter(source,"exam_slot:%d" % stage)]
	var departed_key := "%s%d" % [str(event.get("target_side","")),int(event.get("target_slot",0))]
	if target_key!=departed_key: return []
	var credited := false
	for credit in event.get("credited_units",event.get("payload",{}).get("credited_units",[])):
		if str(credit.get("side",""))==str(owner.side) and int(credit.get("slot",0))==int(owner.slot): credited=true
	if not credited or int(owner.target_slot)!=int(event.get("target_slot",0)): return []
	return [_counter("exam_stage",stage+1),{"kind":"barrier_grant","target_key":str(owner.key),"expires_tick":int(event.get("tick",0))+30}]

func _pr14(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "hp_lost" and str(event.get("target_key",""))==owner_key and int(event.get("actual_hp_loss",0))>0:
		var attacker := engine.unit(str(event.get("source_key","")))
		if not attacker.is_empty() and attacker.side!=engine.unit(owner_key).side:
			return [_counter("combo_target_slot",0),_counter("combo_target_side",0),_counter("combo_hits",0)]
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding): return []
	var target := engine.unit(str(event.get("target_key","")))
	var owner := engine.unit(owner_key)
	if target.is_empty() or owner.is_empty(): return []
	var slot := int(target.slot)
	var side := 1 if target.side=="A" else 2
	var count := engine.get_counter(source,"combo_hits")
	if count>=2 and slot==engine.get_counter(source,"combo_target_slot") and side==engine.get_counter(source,"combo_target_side") and engine.ready(source,"combo_barrier"):
		return [_counter("combo_hits",0),_counter("combo_target_slot",0),_counter("combo_target_side",0),_cooldown(40,"combo_barrier"),
			{"kind":"barrier_grant","target_key":owner_key,"expires_tick":int(event.get("tick",0))+20}]
	if slot==engine.get_counter(source,"combo_target_slot") and side==engine.get_counter(source,"combo_target_side"):
		return [_counter("combo_hits",mini(2,count+1))]
	return [_counter("combo_target_slot",slot),_counter("combo_target_side",side),_counter("combo_hits",1)]

func _owner_natural(event: Dictionary,binding: Dictionary) -> bool:
	return _natural(event) and str(event.get("source_key",""))==str(binding.get("owner_key",""))

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
