extends RefCounted
class_name GLHandlers

## Explicit GL-family implementations. GL03 is intentionally unsupported until
## BattleEngine exposes a non-damage barrier-clear action with an actual-clear result.
const IMPLEMENTED_IDS: Array[String] = ["GL01","GL02","GL04","GL06","GL07","GL09","GL10","GL11","GL12","GL13","GL14"]
const INTEGRATED_IDS: Array[String] = []


func supports_content_id(content_id: String) -> bool:
	return IMPLEMENTED_IDS.has(content_id)


func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	match str(binding.get("content_id", "")):
		"GL01": return _gl01(engine, binding, event)
		"GL02": return _gl02(engine, binding, event)
		"GL04": return _gl04(engine, binding, event)
		"GL06": return _gl06(engine, binding, event)
		"GL07": return _gl07(engine, binding, event)
		"GL09": return _gl09(engine, binding, event)
		"GL10": return _gl10(engine, binding, event)
		"GL11": return _gl11(engine, binding, event)
		"GL12": return _gl12(engine, binding, event)
		"GL13": return _gl13(engine, binding, event)
		"GL14": return _gl14(engine, binding, event)
	return []


func _gl01(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic" or int(event.get("tick", 0)) <= 0 or int(event.tick) % 30 != 0: return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty(): return []
	var candidates := _other_living(engine, str(owner.side), str(owner.key))
	var selected: Dictionary = {}
	var selected_layers := 0
	for ally in candidates:
		var layers := _status_layers(ally, "poison")
		if layers > selected_layers or (layers > 0 and layers == selected_layers and (selected.is_empty() or int(ally.slot) < int(selected.slot))):
			selected = ally
			selected_layers = layers
	if selected_layers <= 0: return []
	var cleared := mini(2, selected_layers)
	return [{"kind":"status_remove", "target_key":str(selected.key), "status_id":"poison", "layers":cleared},
		{"kind":"heal", "target_key":str(owner.key), "amount":cleared * 30}]


func _gl02(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "before_hit" or not _is_owner_natural(event, binding): return []
	var attack_id := _attack_id(event)
	if attack_id.is_empty(): return []
	var owner_key := str(binding.get("owner_key", ""))
	var consumed := mini(60, engine.shield_amount(owner_key))
	if consumed <= 0: return []
	return [{"kind":"shield_consume", "target_key":owner_key, "amount":consumed},
		{"kind":"attack_patch", "attack_id":attack_id, "patch":{"amount_flat":int(floor(float(consumed * 3) / 2.0))}}]


func _gl04(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var source_key := str(binding.get("source_key", ""))
	if str(event.get("kind", "")) == "hp_lost" and str(event.get("source_key", "")) == owner_key and bool(event.get("is_natural_attack", false)) and not bool(event.get("is_attached_damage", false)):
		var actual_loss := int(event.get("actual_hp_loss", 0))
		if actual_loss <= 0: return []
		var saved := int(floor(float(actual_loss) * 0.25))
		return [_counter("stomach", mini(120, engine.get_counter(source_key, "stomach") + saved))]
	if str(event.get("kind", "")) == "periodic" and int(event.get("tick", 0)) > 0 and int(event.tick) % 40 == 0:
		var stored := engine.get_counter(source_key, "stomach")
		if stored <= 0: return []
		return [_counter("stomach", 0), {"kind":"heal", "target_key":owner_key, "amount":stored}]
	return []


func _gl06(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source_key := str(binding.get("source_key", ""))
	var owner_key := str(binding.get("owner_key", ""))
	if str(event.get("kind", "")) == "battle_start":
		return [_counter("fed", 0), _counter("unlocked", 0), _counter("threshold75", 0),
			_counter("threshold50", 0), _counter("threshold25", 0),
			{"kind":"counter", "counter_key":"meal_limit", "value":3}]
	if str(event.get("kind", "")) != "hp_lost" or str(event.get("target_key", "")) != owner_key or int(event.get("actual_hp_loss", 0)) <= 0: return []
	var owner := engine.unit(owner_key)
	if owner.is_empty() or int(owner.get("hp_tenths", 0)) <= 0: return []
	var max_hp := int(owner.get("initial_max_hp_tenths", owner.get("max_hp_tenths", 0)))
	if max_hp <= 0: return []
	var unlocked := engine.get_counter(source_key, "unlocked")
	var actions: Array = []
	for threshold in [75, 50, 25]:
		var counter_key := "threshold%d" % threshold
		if int(owner.hp_tenths) * 100 <= max_hp * threshold and engine.get_counter(source_key, counter_key) == 0:
			actions.append(_counter(counter_key, 1))
			unlocked += 1
	if unlocked != engine.get_counter(source_key, "unlocked"): actions.append(_counter("unlocked", unlocked))
	var fed := engine.get_counter(source_key, "fed")
	if fed < unlocked and fed < 3:
		actions.append(_counter("fed", fed + 1))
		actions.append({"kind":"heal", "target_key":owner_key, "amount":80})
	return actions


func _gl07(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "healed" or str(event.get("target_key", "")) != str(binding.get("owner_key", "")): return []
	var amount := int(event.get("actual_healing", event.get("amount", event.get("payload", {}).get("actual_healing", 0))))
	if amount < 40 or not engine.ready(str(binding.get("source_key", "")), "share"): return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty(): return []
	var candidates := _other_living(engine, str(owner.side), str(owner.key))
	var target := _lowest_hp_ratio(candidates)
	if target.is_empty(): return []
	var split := mini(50, int(floor(float(amount * 40) / 100.0)))
	if split <= 0: return []
	return [_cooldown(20, "share"), {"kind":"heal", "target_key":str(target.key), "amount":split}]


func _gl09(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var source_key := str(binding.get("source_key", ""))
	var tick := int(event.get("tick", 0))
	if str(event.get("kind", "")) == "hp_lost" and str(event.get("target_key", "")) == str(binding.get("owner_key", "")) and not bool(event.get("is_self_loss", false)):
		var source := engine.unit(str(event.get("source_key", "")))
		var owner := engine.unit(str(binding.get("owner_key", "")))
		if source.is_empty() or owner.is_empty() or source.side == owner.side: return []
		var bucket := "loss:%d" % tick
		return [_counter(bucket, engine.get_counter(source_key, bucket) + int(event.get("actual_hp_loss", 0)))]
	if str(event.get("kind", "")) != "periodic" or tick <= 0 or tick % 50 != 0: return []
	var total := 0
	var actions: Array = []
	for sample_tick in range(maxi(0, tick - 50), tick):
		var bucket := "loss:%d" % sample_tick
		total += engine.get_counter(source_key, bucket)
		if engine.get_counter(source_key, bucket) > 0: actions.append(_counter(bucket, 0))
	var heal_amount := mini(100, int(floor(float(total) * 0.20)))
	if heal_amount > 0: actions.append({"kind":"heal", "target_key":str(binding.get("owner_key", "")), "amount":heal_amount})
	return actions


func _gl10(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "prepare_attack" or not _is_owner_natural(event, binding): return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty() or int(owner.get("hp_tenths", 0)) != int(owner.get("initial_max_hp_tenths", 0)) or not engine.ready(str(binding.get("source_key", "")), "split"): return []
	var attack_id := _attack_id(event)
	var context: Dictionary = event.get("attack_context", event.get("payload", {}).get("attack_context", {}))
	var segments: Array = context.get("segments", [])
	if segments.size() != 1: return []
	var base_amount := int(segments[0].get("amount", 0))
	var segment_amount := int(floor(float(base_amount * 45) / 100.0))
	if segment_amount <= 0: return []
	var damage_type := str(segments[0].get("damage_type", "physical"))
	var armor_piercing: Variant = segments[0].get("armor_piercing", 0)
	var split_segments: Array = []
	for _index in range(3): split_segments.append({"amount":segment_amount, "damage_type":damage_type, "armor_piercing":armor_piercing})
	return [_cooldown(30, "split"), {"kind":"attack_patch", "attack_id":attack_id, "patch":{"segments":split_segments}}]


func _gl11(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var owner_key := str(binding.get("owner_key", ""))
	var source_key := str(binding.get("source_key", ""))
	if str(event.get("kind", "")) == "hp_lost" and str(event.get("target_key", "")) == owner_key and int(event.get("actual_hp_loss", 0)) > 0:
		var owner := engine.unit(owner_key)
		if owner.is_empty(): return []
		var actions: Array = []
		if engine.get_counter(source_key, "first_hurt") == 0:
			actions.append(_counter("first_hurt", 1))
		if int(owner.hp_tenths) * 100 < int(owner.initial_max_hp_tenths) * 40:
			var stored := engine.get_counter(source_key, "frozen")
			if stored > 0:
				actions.append(_counter("frozen", 0))
				actions.append({"kind":"heal", "target_key":owner_key, "amount":stored})
		return actions
	if str(event.get("kind", "")) != "periodic" or int(event.get("tick", 0)) <= 0 or int(event.tick) % 40 != 0 or engine.get_counter(source_key, "first_hurt") == 0: return []
	var owner_shield := engine.shield_amount(owner_key)
	var amount := mini(60, mini(owner_shield, 120 - engine.get_counter(source_key, "frozen")))
	if amount <= 0: return []
	return [{"kind":"shield_consume", "target_key":owner_key, "amount":amount},
		_counter("frozen", engine.get_counter(source_key, "frozen") + amount)]


func _gl12(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "hit" or str(event.get("target_key", "")) != str(binding.get("owner_key", "")) or not bool(event.get("is_natural_attack", false)) or bool(event.get("is_extra_attack", false)): return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	var attacker := engine.unit(str(event.get("source_key", "")))
	if owner.is_empty() or attacker.is_empty() or owner.side == attacker.side or str(attacker.reach) != "melee" or not engine.ready(str(binding.get("source_key", "")), "acid"): return []
	return [_cooldown(15, "acid"), {"kind":"status_add", "target_key":str(attacker.key), "status_id":"poison", "layers":1, "expires_tick":int(event.get("tick", 0)) + 30}]


func _gl13(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	var tick := int(event.get("tick", 0))
	if str(event.get("kind", "")) != "periodic" or tick <= 0 or tick % 60 != 0: return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty() or int(owner.hp_tenths) * 100 < int(owner.initial_max_hp_tenths) * 60: return []
	var target := _current_enemy(engine, owner)
	if target.is_empty(): return []
	var amount := mini(90, int(floor(float(int(owner.hp_tenths) * 6) / 100.0)))
	if amount <= 0: return []
	return [{"kind":"damage", "target_key":str(target.key), "amount":amount, "damage_type":"fixed"},
		{"kind":"modifier_add", "target_key":str(owner.key), "stat":"T_ticks_percent", "amount":2000,
			"modifier_id":"GL13:stomach_strain:%d" % tick, "expires_tick":tick + 20}]


func _gl14(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "hit" or not _is_owner_natural(event, binding) or not engine.ready(str(binding.get("source_key", "")), "spread"): return []
	var target_key := str(event.get("target_key", ""))
	var target := engine.unit(target_key)
	if target.is_empty() or _status_layers(target, "burn") <= 0: return []
	var owner := engine.unit(str(binding.get("owner_key", "")))
	if owner.is_empty(): return []
	var actions: Array = [_cooldown(30, "spread"), {"kind":"status_remove", "target_key":target_key, "status_id":"burn", "layers":1}]
	for enemy in engine.units("A" if owner.side == "B" else "B", true):
		if str(enemy.key) == target_key: continue
		actions.append({"kind":"status_add", "target_key":str(enemy.key), "status_id":"burn", "layers":1, "expires_tick":int(event.get("tick", 0)) + 30})
	return actions


func _is_owner_natural(event: Dictionary, binding: Dictionary) -> bool:
	return bool(event.get("is_natural_attack", false)) and not bool(event.get("is_extra_attack", false)) and str(event.get("source_key", "")) == str(binding.get("owner_key", ""))


func _attack_id(event: Dictionary) -> String:
	return str(event.get("attack_id", event.get("payload", {}).get("attack_id", "")))


func _counter(key: String, value: int) -> Dictionary:
	return {"kind":"counter", "counter_key":key, "value":value}


func _cooldown(ticks: int, key: String) -> Dictionary:
	return {"kind":"cooldown", "ticks":ticks, "cooldown_key":key}


func _status_layers(unit_state: Dictionary, status_id: String) -> int:
	var layers := 0
	for status in unit_state.get("statuses", []):
		if str(status.get("id", "")) == status_id: layers += int(status.get("layers", 0))
	return layers


func _other_living(engine: BattleEngine, side: String, owner_key: String) -> Array:
	var result: Array = []
	for ally in engine.units(side, true):
		if str(ally.key) != owner_key: result.append(ally)
	return result


func _lowest_hp_ratio(units_to_check: Array) -> Dictionary:
	var selected: Dictionary = {}
	var selected_ratio := INF
	for candidate in units_to_check:
		var maximum := int(candidate.get("initial_max_hp_tenths", candidate.get("max_hp_tenths", 0)))
		if maximum <= 0: continue
		var ratio := float(candidate.get("hp_tenths", 0)) / float(maximum)
		if ratio < selected_ratio or (is_equal_approx(ratio, selected_ratio) and (selected.is_empty() or int(candidate.slot) < int(selected.slot))):
			selected = candidate
			selected_ratio = ratio
	return selected


func _current_enemy(_engine: BattleEngine, owner: Dictionary) -> Dictionary:
	var enemy_side := "B" if str(owner.side) == "A" else "A"
	var target_slot := int(owner.get("target_slot", 1))
	var enemies := _engine.units(enemy_side, true)
	for candidate in enemies:
		if int(candidate.slot) == target_slot: return candidate
	return {}
