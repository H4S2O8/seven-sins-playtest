extends RefCounted
class_name ENHandlers

## Exact numeric imitation only. Unsupported interval/barrier-refresh cards are excluded.
const IMPLEMENTED_IDS: Array[String] = ["EN01","EN03","EN04","EN05","EN06","EN07","EN08","EN09","EN10","EN11","EN12","EN13","EN14"]
const INTEGRATED_IDS: Array[String] = []

func supports_content_id(content_id: String) -> bool:
	return IMPLEMENTED_IDS.has(content_id)

func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	match str(binding.get("content_id", "")):
		"EN01": return _en01(engine,binding,event)
		"EN03": return _en03(engine,binding,event)
		"EN04": return _en04(engine,binding,event)
		"EN05": return _en05(engine,binding,event)
		"EN06": return _en06(engine,binding,event)
		"EN07": return _en07(engine,binding,event)
		"EN08": return _en08(engine,binding,event)
		"EN09": return _en09(engine,binding,event)
		"EN10": return _en10(engine,binding,event)
		"EN11": return _en11(engine,binding,event)
		"EN12": return _en12(engine,binding,event)
		"EN13": return _en13(engine,binding,event)
		"EN14": return _en14(engine,binding,event)
	return []

func _en01(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "periodic" or int(event.get("tick",0)) <= 0 or int(event.tick) % 40 != 0: return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	var target := _current_enemy(engine,owner)
	var actions: Array = [{"kind":"modifier_remove","target_key":str(owner.key),"modifier_id":"EN01:borrowed_A"}]
	if target.is_empty(): return actions
	var bonus := mini(6,maxi(0,int(floor(float(int(target.base_A)-int(owner.base_A))/2.0))))
	if bonus > 0: actions.append({"kind":"modifier_add","target_key":str(owner.key),"stat":"A_flat","amount":bonus,"modifier_id":"EN01:borrowed_A","expires_tick":int(event.tick)+40})
	return actions

func _en03(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hit" or str(event.get("target_key","")) != str(binding.get("owner_key","")) or not _natural(event): return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	var attacker := engine.unit(str(event.get("source_key","")))
	var source := str(binding.get("source_key",""))
	if owner.is_empty() or attacker.is_empty() or owner.side == attacker.side: return []
	var seen := "recorded:%s" % str(attacker.key)
	if engine.get_counter(source,seen) > 0 or engine.get_counter(source,"recorded_count") >= 3: return []
	var best := maxi(engine.get_counter(source,"best_R"),mini(5,int(attacker.get("base_R",attacker.R))))
	var actions: Array = [_counter(seen,1),_counter("recorded_count",engine.get_counter(source,"recorded_count")+1),_counter("best_R",best),
		{"kind":"modifier_remove","target_key":str(owner.key),"modifier_id":"EN03:recorded_R"}]
	var difference := best-int(owner.R)
	if difference > 0: actions.append({"kind":"modifier_add","target_key":str(owner.key),"stat":"R_flat","amount":difference,"modifier_id":"EN03:recorded_R","expires_tick":-1})
	return actions

func _en04(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "hit" and str(event.get("target_key","")) == owner_key and _natural(event):
		var attacker := engine.unit(str(event.get("source_key","")))
		var owner := engine.unit(owner_key)
		var kind := str(event.get("damage_type",""))
		if attacker.is_empty() or owner.is_empty() or attacker.side == owner.side or kind not in ["physical","fire","ice","lightning","poison"] or not engine.ready(source,"mimic"): return []
		return [_counter("mimic_type",_type_code(kind)),_counter("mimic_expiry",int(event.get("tick",0))+40),_cooldown(20,"mimic")]
	if str(event.get("kind","")) == "prepare_attack" and _owner_natural(event,binding):
		var kind_code := engine.get_counter(source,"mimic_type")
		if kind_code <= 0 or int(event.get("tick",0)) >= engine.get_counter(source,"mimic_expiry"): return []
		return [_counter("mimic_type",0),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"damage_type":_type_name(kind_code),"amount_flat":30}}]
	return []

func _en05(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "before_hit" or not _owner_natural(event,binding) or not engine.ready(str(binding.get("source_key","")),"peak"): return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	var target := engine.unit(str(event.get("target_key","")))
	if owner.is_empty() or target.is_empty(): return []
	var own_max := int(owner.initial_max_hp_tenths)
	var target_max := int(target.initial_max_hp_tenths)
	if own_max <= 0 or target_max <= 0: return []
	if 100*int(target.hp_tenths)*own_max < 100*int(owner.hp_tenths)*target_max + 20*own_max*target_max: return []
	var amount := mini(60,int(floor(float(int(target.hp_tenths))*0.05)))
	if amount <= 0: return []
	return [_cooldown(20,"peak"),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":amount,"damage_type":"fixed"}]}}]

func _en06(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "periodic" or int(event.get("tick",0)) <= 0 or int(event.tick)%30 != 0: return []
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	var enemies := engine.units("B" if owner.side == "A" else "A",true)
	var count := 0
	for enemy in enemies:
		if engine.shield_amount(str(enemy.key)) > 0: count += 1
	if count < 2: return []
	var target := _lowest(engine.units(str(owner.side),true))
	if target.is_empty(): return []
	return [{"kind":"shield_grant","target_key":str(target.key),"amount":80,"expires_tick":int(event.tick)+30}]

func _en07(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "healed":
		var target := engine.unit(str(event.get("target_key","")))
		var owner := engine.unit(owner_key)
		var healed := int(event.get("actual_healing",event.get("payload",{}).get("actual_healing",0)))
		if target.is_empty() or owner.is_empty() or target.side == owner.side or str(target.key) != str(_current_enemy(engine,owner).get("key","")) or healed < 50: return []
		return [_counter("wound_slot",int(target.slot)),_counter("wound_side",1 if target.side == "A" else 2),
			_counter("wound_amount",mini(70,int(floor(float(healed)*0.60)))),_counter("wound_expiry",int(event.get("tick",0))+20)]
	if str(event.get("kind","")) == "before_hit" and _owner_natural(event,binding) and engine.ready(source,"wound"):
		var key := str(event.get("target_key",""))
		var side := "A" if engine.get_counter(source,"wound_side") == 1 else "B"
		if key.substr(0,1) != side or int(key.substr(1,1)) != engine.get_counter(source,"wound_slot") or int(event.get("tick",0)) >= engine.get_counter(source,"wound_expiry"): return []
		var amount := engine.get_counter(source,"wound_amount")
		if amount <= 0: return []
		return [_counter("wound_amount",0),_cooldown(30,"wound"),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":amount,"damage_type":"poison"}]}}]
	return []

func _en08(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner := engine.unit(str(binding.get("owner_key","")))
	if owner.is_empty(): return []
	if str(event.get("kind","")) == "hp_lost":
		var attacker := engine.unit(str(event.get("source_key","")))
		var recipient := engine.unit(str(event.get("target_key","")))
		if attacker.is_empty() or recipient.is_empty() or attacker.side == owner.side or recipient.side != owner.side or int(event.get("actual_hp_loss",0)) <= 0: return []
		var key := "enemy_damage:%s" % str(attacker.key)
		return [_counter(key,engine.get_counter(source,key)+int(event.actual_hp_loss))]
	if str(event.get("kind","")) == "periodic" and int(event.get("tick",0)) == 40 and engine.get_counter(source,"locked") == 0:
		var enemies := engine.units("B" if owner.side == "A" else "A",true)
		var selected: Dictionary = {}
		var best := -1
		for enemy in enemies:
			var damage := engine.get_counter(source,"enemy_damage:%s" % str(enemy.key))
			if damage > best or (damage == best and (selected.is_empty() or int(enemy.slot)<int(selected.slot))):
				selected = enemy
				best = damage
		if not selected.is_empty(): return [_counter("locked",1),_counter("locked_slot",int(selected.slot)),_counter("locked_side",1 if selected.side == "A" else 2)]
	if str(event.get("kind","")) == "before_hit" and _owner_natural(event,binding) and engine.ready(source,"pursuit"):
		var target := engine.unit(str(event.get("target_key","")))
		if target.is_empty() or target.side == owner.side or engine.get_counter(source,"locked_slot") != int(target.slot) or engine.get_counter(source,"locked_side") != (1 if target.side == "A" else 2): return []
		return [_cooldown(20,"pursuit"),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"amount_flat":40}}]
	return []

func _en09(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner := engine.unit(str(binding.get("owner_key","")))
	var source := str(binding.get("source_key",""))
	if owner.is_empty(): return []
	if str(event.get("kind","")) == "hit" and _natural(event):
		var ally := engine.unit(str(event.get("source_key","")))
		var target := _current_enemy(engine,owner)
		if ally.is_empty() or ally.side != owner.side or ally.key == owner.key or target.is_empty() or str(event.get("target_key","")) != str(target.key) or not engine.ready(source,"echo"): return []
		var raw := int(event.get("raw_amount",event.get("payload",{}).get("raw_amount",0)))
		var copied := mini(50,int(floor(float(raw)*0.30)))
		if copied <= 0: return []
		return [_counter("echo_amount",copied),_counter("echo_expiry",int(event.get("tick",0))+20),_cooldown(20,"echo")]
	if str(event.get("kind","")) == "prepare_attack" and _owner_natural(event,binding):
		var amount := engine.get_counter(source,"echo_amount")
		if amount <= 0 or int(event.get("tick",0)) >= engine.get_counter(source,"echo_expiry"): return []
		return [_counter("echo_amount",0),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"amount_flat":amount}}]
	return []

func _en10(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "battle_start":
		var owner := engine.unit(owner_key)
		if owner.is_empty(): return []
		var separated := true
		for ally in engine.units(str(owner.side),true):
			if str(ally.key) != owner_key and int(ally.target_slot) == int(owner.target_slot): separated = false
		if not separated: return []
		return [_counter("flight_active",1),_counter("flight_expiry",int(event.get("tick",0))+60),_counter("flight_charges",3),
			{"kind":"modifier_add","target_key":owner_key,"stat":"flying","value":true,"modifier_id":"EN10:flight","expires_tick":int(event.get("tick",0))+60}]
	if str(event.get("kind","")) == "before_hit" and _owner_natural(event,binding) and engine.get_counter(source,"flight_charges") > 0 and int(event.get("tick",0)) < engine.get_counter(source,"flight_expiry"):
		return [_counter("flight_charges",engine.get_counter(source,"flight_charges")-1),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":30,"damage_type":"ice"}]}}]
	return []

func _en11(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "status_applied" or str(event.get("target_key","")) != str(binding.get("owner_key","")): return []
	var attacker := engine.unit(str(event.get("source_key","")))
	var owner := engine.unit(str(binding.get("owner_key","")))
	var status_id := str(event.get("status_id",event.get("payload",{}).get("status_id","")))
	if attacker.is_empty() or owner.is_empty() or attacker.side == owner.side or status_id not in ["burn","bleed","poison"]: return []
	var source := str(binding.get("source_key",""))
	var tick := int(event.get("tick",0))
	var key := "gift:%s" % str(attacker.key)
	if tick < engine.get_counter(source,key): return []
	return [_counter(key,tick+40),{"kind":"status_add","target_key":str(attacker.key),"status_id":status_id,"layers":1,"expires_tick":tick+30}]

func _en12(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind","")) != "hit" or not _owner_natural(event,binding): return []
	var source := str(binding.get("source_key",""))
	var count := engine.get_counter(source,"hit_count")+1
	if count < 2: return [_counter("hit_count",count)]
	var owner := engine.unit(str(binding.get("owner_key","")))
	var target := engine.unit(str(event.get("target_key","")))
	if owner.is_empty() or target.is_empty(): return [_counter("hit_count",0)]
	var others: Array = []
	for enemy in engine.units("B" if owner.side == "A" else "A",true):
		if str(enemy.key) != str(target.key): others.append(enemy)
	var lowest := _lowest(others)
	var actions: Array = [_counter("hit_count",0)]
	if not lowest.is_empty() and _hp_ratio(target)-_hp_ratio(lowest) >= 0.20:
		actions.append({"kind":"damage","target_key":str(target.key),"amount":60,"damage_type":"fixed"})
	return actions

func _en13(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "battle_start":
		var owner := engine.unit(owner_key)
		if owner.is_empty(): return []
		var enemies := engine.units("B" if owner.side=="A" else "A",true)
		var selected: Dictionary = {}
		for enemy in enemies:
			if selected.is_empty() or int(enemy.base_H)>int(selected.base_H) or (int(enemy.base_H)==int(selected.base_H) and int(enemy.slot)<int(selected.slot)):
				selected=enemy
		if selected.is_empty(): return []
		return [_counter("watch_slot",int(selected.slot)),_counter("watch_side",1 if selected.side=="A" else 2)]
	if str(event.get("kind","")) != "periodic" or int(event.get("tick",0))<=0 or int(event.tick)%40!=0: return []
	var owner := engine.unit(owner_key)
	if owner.is_empty(): return []
	var side := "A" if engine.get_counter(source,"watch_side")==1 else "B"
	var target := engine.unit("%s%d" % [side,engine.get_counter(source,"watch_slot")])
	if target.is_empty() or bool(target.dead) or int(owner.target_slot)!=int(target.slot): return []
	return [{"kind":"barrier_grant","target_key":owner_key,"expires_tick":int(event.get("tick",0))+20}]

func _en14(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source := str(binding.get("source_key",""))
	var owner_key := str(binding.get("owner_key",""))
	if str(event.get("kind","")) == "hp_lost":
		var attacker := engine.unit(str(event.get("source_key","")))
		var target := engine.unit(str(event.get("target_key","")))
		var owner := engine.unit(owner_key)
		if attacker.is_empty() or target.is_empty() or owner.is_empty() or attacker.side != owner.side or target.side == owner.side: return []
		var key := "damage_done:%s" % str(attacker.key)
		return [_counter(key,engine.get_counter(source,key)+int(event.get("actual_hp_loss",0)))]
	if str(event.get("kind","")) == "periodic" and int(event.get("tick",0)) in [80,160]:
		var owner := engine.unit(owner_key)
		if owner.is_empty(): return []
		var peers := _others(engine,str(owner.side),owner_key)
		if peers.size() < 2: return []
		var dealt := engine.get_counter(source,"damage_done:" + owner_key)
		for peer in peers:
			if dealt >= engine.get_counter(source,"damage_done:" + str(peer.key)): return []
		var window := int(int(event.tick)/80)
		return [_counter("window:%d" % window,1),_counter("expiry:%d" % window,int(event.tick)+50),_counter("charges:%d" % window,2)]
	if str(event.get("kind","")) == "before_hit" and _owner_natural(event,binding):
		var tick := int(event.get("tick",0))
		for window in [1,2]:
			if engine.get_counter(source,"window:%d" % window) > 0 and tick < engine.get_counter(source,"expiry:%d" % window) and engine.get_counter(source,"charges:%d" % window) > 0:
				return [_counter("charges:%d" % window,engine.get_counter(source,"charges:%d" % window)-1),{"kind":"attack_patch","attack_id":_attack_id(event),"patch":{"append_segments":[{"amount":50,"damage_type":"lightning"}]}}]
	return []

func _owner_natural(event: Dictionary, binding: Dictionary) -> bool:
	return _natural(event) and str(event.get("source_key","")) == str(binding.get("owner_key",""))

func _natural(event: Dictionary) -> bool:
	return bool(event.get("is_natural_attack",false)) and not bool(event.get("is_extra_attack",false)) and not bool(event.get("is_attached_damage",false)) and not bool(event.get("is_redirected",false))

func _attack_id(event: Dictionary) -> String:
	return str(event.get("attack_id",event.get("payload",{}).get("attack_id","")))

func _type_code(kind: String) -> int:
	return ["physical","fire","ice","lightning","poison"].find(kind)+1

func _type_name(code: int) -> String:
	return ["physical","fire","ice","lightning","poison"][code-1] if code in range(1,6) else "physical"

func _counter(key: String, value: int) -> Dictionary:
	return {"kind":"counter","counter_key":key,"value":value}

func _cooldown(ticks: int, key: String) -> Dictionary:
	return {"kind":"cooldown","ticks":ticks,"cooldown_key":key}

func _current_enemy(engine: BattleEngine, owner: Dictionary) -> Dictionary:
	for enemy in engine.units("B" if owner.side == "A" else "A",true):
		if int(enemy.slot) == int(owner.target_slot): return enemy
	return {}

func _hp_ratio(unit_state: Dictionary) -> float:
	var maximum := int(unit_state.get("initial_max_hp_tenths",0))
	return float(unit_state.get("hp_tenths",0))/float(maximum) if maximum > 0 else 1.0

func _lowest(candidates: Array) -> Dictionary:
	var selected: Dictionary = {}
	var best := INF
	for candidate in candidates:
		var ratio := _hp_ratio(candidate)
		if ratio < best or (is_equal_approx(ratio,best) and (selected.is_empty() or int(candidate.slot)<int(selected.slot))):
			selected = candidate
			best = ratio
	return selected

func _others(engine: BattleEngine, side: String, owner_key: String) -> Array:
	var result: Array = []
	for ally in engine.units(side,true):
		if str(ally.key) != owner_key: result.append(ally)
	return result
