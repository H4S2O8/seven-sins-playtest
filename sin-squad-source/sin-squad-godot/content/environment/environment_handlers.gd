extends RefCounted
class_name EnvironmentHandlers

const IMPLEMENTED_IDS: Array[String] = ["AR01", "AR02", "AR03", "AR04", "AR05", "AR06", "AR07", "AR08", "AR09", "AR10", "AR11", "AR13", "AR14", "AR15", "AR16", "AR17", "AR19", "AR20", "PE05", "PE09", "PE10", "PE12", "PE17", "PE18", "PE21", "PE22", "PE23", "PE26", "PE30", "PE31", "PE32", "PE35", "PE36", "PE38", "PE39", "PE46", "PE47", "PE48", "PE50"]
const PERMANENT_BARRIER_EXPIRY := 1_000_000


func supports_content_id(content_id: String) -> bool:
	return IMPLEMENTED_IDS.has(content_id)


func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	match str(binding.get("content_id", "")):
		"AR01": return _ar01_broken_bridge(engine, event)
		"AR02": return _ar02_arena(engine, event)
		"AR03": return _ar03_shooting_gallery(engine, event)
		"AR04": return _ar04_pillar_courtyard(engine, event)
		"AR05": return _ar05_snow(engine, event)
		"AR06": return _ar06_ice_ferry(engine, event)
		"AR07": return _ar07_flooded_machine_room(engine, event)
		"AR08": return _ar08_embers(engine, event)
		"AR09": return _ar09_thorn_corridor(engine, event)
		"AR10": return _ar10_gravity(engine, event)
		"AR11": return _ar11_pressure_well(engine, event)
		"AR13": return _ar13_rust(engine, event)
		"AR14": return _ar14_slowest_barrier(engine) if str(event.get("kind", "")) == "battle_start" else []
		"AR15": return _ar15_bloody_altar(engine, event)
		"AR16": return _ar16_starting_silence(engine, event) if str(event.get("kind", "")) == "pre_battle" else []
		"AR17": return _ar17_stairs(engine, event)
		"AR19": return _ar19_last_light(engine, event)
		"AR20": return _ar20_aimed_unit(engine, event)
		"PE05": return _pe05_frost_rain(engine, event)
		"PE09": return _pe09_headwind(engine, event)
		"PE10": return _pe10_blizzard(engine, event)
		"PE12": return _pe12_iron_curtain(engine, event)
		"PE17": return _pe17_sanctuary_tide(engine, event)
		"PE18": return _pe18_shield_echo(engine, event)
		"PE21": return _pe21_haste(engine, event)
		"PE22": return _pe22_late_bell(engine, event)
		"PE23": return _pe23_combo_rhythm(engine, event)
		"PE26": return _pe26_focus_echo(engine, event)
		"PE30": return _pe30_final_sprint(engine, event)
		"PE31": return _pe31_drought(engine, event)
		"PE32": return _pe32_overflow(engine, binding, event)
		"PE35": return _pe35_harvest(engine, event)
		"PE36": return _pe36_backwater(engine, event)
		"PE38": return _pe38_solo_rations(engine, event)
		"PE39": return _pe39_encumbrance(engine, event)
		"PE47": return _pe47_opening_judgment(engine, event)
		"PE48": return _pe48_late_shelter(engine, event)
		"PE50": return _pe50_public_duel(engine, event)
		"PE46": return _pe46_wing_lantern(engine, event)
		_: return []


func _ar01_broken_bridge(engine: BattleEngine, event: Dictionary) -> Array:
	if not _is_melee_cross(engine, event): return []
	return _preparation_patch(event, 5)


func _ar02_arena(engine: BattleEngine, event: Dictionary) -> Array:
	if not _is_melee_cross(engine, event): return []
	return _preparation_patch(event, -4)


func _ar03_shooting_gallery(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "before_hit": return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	if str(attacker.get("reach", "")) != "ranged": return []
	var context: Dictionary = event.get("payload", {}).get("attack_context", {})
	var base_amount := int(context.get("amount", 0))
	var same_slot := int(attacker.get("slot", 0)) == int(event.get("target_slot", 0))
	var scaled_amount := (base_amount * (125 if same_slot else 75)) / 100
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")), "patch":{"amount":scaled_amount}}]


func _ar04_pillar_courtyard(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "before_hit": return []
	if not bool(event.get("is_natural_attack", false)) and not bool(event.get("is_extra_attack", false)): return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	if str(attacker.get("reach", "")) != "ranged": return []
	var target_key := str(event.get("target_key", ""))
	if target_key.is_empty() or engine.get_counter(target_key, "AR04_ranged_cover_used") > 0: return []
	return [
		{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")), "patch":{"suppress":true}},
		{"kind":"counter", "source_binding_key":target_key, "counter_key":"AR04_ranged_cover_used", "value":1}
	]


func _ar05_snow(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "prepare_attack": return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	var count := int(attacker.get("ability_counters", {}).get("natural_attack_count", 0))
	var armor_kind := str(attacker.get("armor_kind", ""))
	if armor_kind == "light" and count <= 2: return _preparation_patch(event, 5)
	if armor_kind == "medium" and count == 1: return _preparation_patch(event, 3)
	return []


func _ar06_ice_ferry(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "hit" or not bool(event.get("is_attack", false)): return []
	if not _is_cross_melee_hit(engine, event): return []
	var attacker_key := str(event.get("source_key", ""))
	return [{"kind":"status_add", "target_key":attacker_key, "status_id":"chill", "layers":1, "expires_tick":int(event.get("tick", -1)) + 20}]


func _ar09_thorn_corridor(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "hit" or not bool(event.get("is_attack", false)): return []
	if not _is_cross_melee_hit(engine, event): return []
	var attacker_key := str(event.get("source_key", ""))
	var completed := engine.get_counter(attacker_key, "AR09_melee_attack_count") + 1
	var actions: Array = [{"kind":"counter", "source_binding_key":attacker_key, "counter_key":"AR09_melee_attack_count", "value":completed}]
	if completed % 3 == 0:
		actions.append({"kind":"self_loss", "target_key":attacker_key, "amount":20})
	return actions


func _ar07_flooded_machine_room(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "hp_lost" or str(event.get("damage_type", "")) != "lightning": return []
	var transferred_amount := int(int(event.get("actual_hp_loss", 0)) * 25 / 100)
	if transferred_amount <= 0: return []
	var actions: Array = []
	var source_key := str(event.get("source_key", ""))
	var original_target := str(event.get("target_key", ""))
	var target_side := str(event.get("target_side", ""))
	for teammate in engine.units(target_side, true):
		if str(teammate.get("key", "")) == original_target: continue
		actions.append({
			"kind":"damage",
			"target_key":str(teammate.get("key", "")),
			"source_key":source_key,
			"amount":transferred_amount,
			"damage_type":"lightning"
		})
	return actions


func _ar10_gravity(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "prepare_attack" or int(event.get("tick", -1)) >= 80: return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	if not bool(attacker.get("flying", false)) and str(attacker.get("armor_kind", "")) != "light": return []
	return _preparation_patch(event, 0, 8000)


func _ar11_pressure_well(engine: BattleEngine, event: Dictionary) -> Array:
	var kind := str(event.get("kind", ""))
	if kind == "battle_start":
		var actions: Array = []
		for side in ["A", "B"]:
			for unit in engine.units(side, true):
				actions.append({"kind":"modifier_add", "target_key":str(unit.get("key", "")), "stat":"damage_reduction_bp", "amount":2500, "modifier_id":"AR11_first_attack_cover"})
		return actions
	if kind != "hit" or not bool(event.get("is_attack", false)): return []
	var attacker_key := str(event.get("source_key", ""))
	if attacker_key.is_empty() or engine.get_counter(attacker_key, "AR11_first_attack_cover_removed") > 0: return []
	return [
		{"kind":"modifier_remove", "target_key":attacker_key, "modifier_id":"AR11_first_attack_cover"},
		{"kind":"counter", "source_binding_key":attacker_key, "counter_key":"AR11_first_attack_cover_removed", "value":1}
	]


func _ar17_stairs(engine: BattleEngine, event: Dictionary) -> Array:
	if not _is_melee_cross(engine, event): return []
	var source_key := str(event.get("source_key", ""))
	var slot := source_key.substr(1).to_int() if source_key.length() > 1 else -1
	if slot == 1: return _preparation_patch(event, 4)
	if slot == 3: return _preparation_patch(event, -4)
	return []


func _ar19_last_light(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "final_departure": return []
	var side := str(event.get("target_side", ""))
	if side not in ["A", "B"]: return []
	var team_marker := "%s1" % side
	if engine.get_counter(team_marker, "AR19_team_triggered") > 0: return []
	var actions: Array = []
	for unit in engine.units(side, true):
		actions.append({
			"kind":"shield_grant",
			"target_key":str(unit.get("key", "")),
			"amount":40,
			"expires_tick":int(event.get("tick", 0)) + 30
		})
	if actions.is_empty(): return []
	actions.append({"kind":"counter", "source_binding_key":team_marker, "counter_key":"AR19_team_triggered", "value":1})
	return actions


func _ar20_aimed_unit(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "prepare_attack": return []
	var target_key := str(event.get("target_key", ""))
	if target_key.is_empty() or engine.get_counter(target_key, "AR20_aim_shield_used") > 0: return []
	return [
		{"kind":"shield_grant","target_key":target_key,"amount":20,"expires_tick":PERMANENT_BARRIER_EXPIRY},
		{"kind":"counter","source_binding_key":target_key,"counter_key":"AR20_aim_shield_used","value":1}
	]


func _pe09_headwind(engine: BattleEngine, event: Dictionary) -> Array:
	if not _is_ranged_cross(engine, event): return []
	return _preparation_patch(event, 6)


func _pe10_blizzard(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "prepare_attack": return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	var delta := 2 if str(attacker.get("armor_kind", "")) == "light" else 0
	if _is_melee_cross(engine, event): delta += 5
	if delta == 0: return []
	return _preparation_patch(event, delta)


func _pe12_iron_curtain(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "pre_battle" or str(event.get("payload", {}).get("phase", "")) != "environment_initial": return []
	var actions: Array = []
	for side in ["A", "B"]:
		for unit in engine.units(side, true):
			actions.append({
				"kind":"modifier_add",
				"target_key":str(unit.get("key", "")),
				"stat":"R_flat",
				"amount":2,
				"modifier_id":"PE12_base_armor_bonus"
			})
	return actions


func _pe17_sanctuary_tide(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic" or int(event.get("tick", -1)) not in [60, 120, 180]: return []
	var actions: Array = []
	for side in ["A", "B"]:
		var lowest: Dictionary = {}
		for unit in engine.units(side, true):
			if lowest.is_empty() or _health_ratio_less(unit, lowest): lowest = unit
		if not lowest.is_empty():
			actions.append({
				"kind":"shield_grant",
				"target_key":str(lowest.get("key", "")),
				"amount":50,
				"expires_tick":1_000_000
			})
	return actions


func _pe18_shield_echo(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "shield_gained" or int(event.get("payload", {}).get("amount", 0)) <= 0: return []
	var actions: Array = []
	for side in ["A", "B"]:
		var newly_shielded: Array[String] = []
		for unit in engine.units(side, true):
			var key := str(unit.get("key", ""))
			if engine.get_counter(key, "PE18_first_numeric_shield_used") > 0 or engine.shield_amount(key) <= 0: continue
			newly_shielded.append(key)
		for key in newly_shielded:
			actions.append({"kind":"counter", "source_binding_key":key, "counter_key":"PE18_first_numeric_shield_used", "value":1})
		for key in newly_shielded:
			for teammate in engine.units(side, true):
				var teammate_key := str(teammate.get("key", ""))
				if teammate_key == key: continue
				actions.append({"kind":"shield_grant", "source_key":key, "target_key":teammate_key, "amount":20, "expires_tick":PERMANENT_BARRIER_EXPIRY})
				if teammate_key not in newly_shielded and engine.get_counter(teammate_key, "PE18_first_numeric_shield_used") == 0:
					actions.append({"kind":"counter", "source_binding_key":teammate_key, "counter_key":"PE18_first_numeric_shield_used", "value":1})
	return actions


func _pe50_public_duel(engine: BattleEngine, event: Dictionary) -> Array:
	var kind := str(event.get("kind", ""))
	if kind == "battle_start":
		var marks: Array = []
		for side in ["A", "B"]:
			for unit in engine.units(side, true):
				marks.append({"kind":"counter", "source_binding_key":str(unit.get("key", "")), "counter_key":"PE50_duel_mark", "value":1})
		return marks
	if kind != "hit" or not bool(event.get("is_attack", false)): return []
	var attacker_key := str(event.get("source_key", ""))
	if attacker_key.is_empty() or engine.get_counter(attacker_key, "PE50_duel_mark") <= 0: return []
	var attacker := engine.unit(attacker_key)
	var target_key := str(event.get("target_key", ""))
	if target_key.is_empty() or int(attacker.get("target_slot", 0)) != int(event.get("target_slot", 0)): return []
	var target := engine.unit(target_key)
	var actions: Array = [{"kind":"counter", "source_binding_key":attacker_key, "counter_key":"PE50_duel_mark", "value":0}]
	if int(target.get("target_slot", 0)) == int(attacker.get("slot", 0)):
		actions.append({"kind":"heal", "target_key":attacker_key, "amount":30})
	else:
		actions.append({"kind":"damage", "target_key":target_key, "amount":20, "damage_type":"fixed"})
	return actions


func _health_ratio_less(a: Dictionary, b: Dictionary) -> bool:
	var comparison := _compare_nonnegative_fractions(
		int(a.get("hp_tenths", 0)), int(a.get("initial_max_hp_tenths", 1)),
		int(b.get("hp_tenths", 0)), int(b.get("initial_max_hp_tenths", 1)))
	if comparison != 0: return comparison < 0
	return int(a.get("slot", 0)) < int(b.get("slot", 0))


func _compare_nonnegative_fractions(numerator_a: int, denominator_a: int, numerator_b: int, denominator_b: int) -> int:
	var a_n := maxi(numerator_a, 0)
	var a_d := maxi(denominator_a, 1)
	var b_n := maxi(numerator_b, 0)
	var b_d := maxi(denominator_b, 1)
	var reversed := false
	while true:
		var quotient_a: int = a_n / a_d
		var quotient_b: int = b_n / b_d
		if quotient_a != quotient_b:
			var result := -1 if quotient_a < quotient_b else 1
			return -result if reversed else result
		var remainder_a := a_n % a_d
		var remainder_b := b_n % b_d
		if remainder_a == 0 or remainder_b == 0:
			if remainder_a == 0 and remainder_b == 0: return 0
			var result := -1 if remainder_a == 0 else 1
			return -result if reversed else result
		a_n = a_d
		a_d = remainder_a
		b_n = b_d
		b_d = remainder_b
		reversed = not reversed
	return 0


func _pe21_haste(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "prepare_attack": return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	var count := int(attacker.get("ability_counters", {}).get("natural_attack_count", 0))
	if count != 1: return []
	return _preparation_patch(event, 0, 5000)


func _pe22_late_bell(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "prepare_attack" or not bool(event.get("is_natural_attack", false)): return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	if int(attacker.get("ability_counters", {}).get("natural_attack_count", 0)) != 1: return []
	return _preparation_patch(event, 10)


func _pe23_combo_rhythm(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "prepare_attack" or not bool(event.get("is_natural_attack", false)): return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	# natural_attack_count advances at the beginning of each natural preparation;
	# therefore count 4 is the preparation immediately following the third completed attack.
	if int(attacker.get("ability_counters", {}).get("natural_attack_count", 0)) != 4: return []
	return _preparation_patch(event, 0, 5000)


func _pe46_wing_lantern(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "shield_broken": return []
	var side := str(event.get("target_side", ""))
	var slot := int(event.get("target_slot", 0))
	if side not in ["A", "B"] or slot not in [1, 3]: return []
	var marker := "%s1" % side
	if engine.get_counter(marker, "PE46_first_flank_break") > 0: return []
	var left := engine.unit("%s1" % side)
	var right := engine.unit("%s3" % side)
	if left.is_empty() or right.is_empty() or bool(left.get("dead", false)) or bool(right.get("dead", false)) or \
		int(left.get("hp_tenths", 0)) <= 0 or int(right.get("hp_tenths", 0)) <= 0:
		return []
	var other_slot := 3 if slot == 1 else 1
	return [
		{"kind":"counter", "source_binding_key":marker, "counter_key":"PE46_first_flank_break", "value":1},
		{"kind":"shield_grant", "target_key":"%s%d" % [side, other_slot], "amount":40, "expires_tick":PERMANENT_BARRIER_EXPIRY}
	]


func _pe26_focus_echo(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "hit" or engine.unit(str(event.get("target_key", ""))).is_empty(): return []
	var target_key := str(event.get("target_key", ""))
	if engine.get_counter(target_key, "PE26_shield_used") > 0: return []
	var source_key := str(event.get("source_key", ""))
	var source_slot := source_key.substr(1).to_int() if source_key.length() > 1 else 0
	if source_slot < 1 or source_slot > 3: return []
	var bit := 1 << (source_slot - 1)
	var tick := int(event.get("tick", -1))
	var stored_start := engine.get_counter(target_key, "PE26_window_start_plus_one")
	var start_tick := stored_start - 1
	var source_mask := engine.get_counter(target_key, "PE26_enemy_slot_mask")
	var actions: Array = []
	if stored_start == 0 or tick > start_tick + 10:
		start_tick = tick
		source_mask = bit
	else:
		source_mask |= bit
	actions.append({"kind":"counter", "source_binding_key":target_key, "counter_key":"PE26_window_start_plus_one", "value":start_tick + 1})
	actions.append({"kind":"counter", "source_binding_key":target_key, "counter_key":"PE26_enemy_slot_mask", "value":source_mask})
	if source_mask != bit and source_mask & (source_mask - 1) != 0:
		actions.append({"kind":"shield_grant", "target_key":target_key, "amount":30, "expires_tick":PERMANENT_BARRIER_EXPIRY})
		actions.append({"kind":"counter", "source_binding_key":target_key, "counter_key":"PE26_shield_used", "value":1})
	return actions


func _pe30_final_sprint(engine: BattleEngine, event: Dictionary) -> Array:
	var kind := str(event.get("kind", ""))
	var tick := int(event.get("tick", -1))
	if kind == "periodic" and tick == 180:
		var actions: Array = []
		for side in ["A", "B"]:
			for unit in engine.units(side, true):
				actions.append({"kind":"modifier_add", "target_key":str(unit.get("key", "")), "stat":"healing_reduction_bp", "amount":2500, "modifier_id":"PE30_late_healing_cut"})
		return actions
	if kind == "prepare_attack" and tick >= 180:
		return _preparation_patch(event, 0, 7500)
	return []


func _pe31_drought(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "pre_battle" or str(event.get("payload", {}).get("phase", "")) != "environment_initial": return []
	var actions: Array = []
	for side in ["A", "B"]:
		for unit in engine.units(side, true):
			actions.append({"kind":"modifier_add", "target_key":str(unit.get("key", "")), "stat":"healing_reduction_bp", "amount":4000, "modifier_id":"PE31_healing_cut"})
	return actions


func _pe32_overflow(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "healed": return []
	var overflow := int(event.get("payload", {}).get("overheal", 0))
	if overflow <= 0: return []
	var target_key := str(event.get("target_key", ""))
	var source_key := str(binding.get("source_key", ""))
	var existing := engine.shield_amount(target_key, source_key)
	var granted_total := mini(existing + int(overflow / 2), 50)
	if granted_total <= existing: return []
	return [{"kind":"shield_grant", "target_key":target_key, "amount":granted_total, "expires_tick":PERMANENT_BARRIER_EXPIRY}]


func _pe36_backwater(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "before_hit": return []
	var attacker := engine.unit(str(event.get("source_key", "")))
	var current_hp := int(attacker.get("hp_tenths", 0))
	var maximum_hp := int(attacker.get("initial_max_hp_tenths", 0))
	if maximum_hp <= 0 or _compare_nonnegative_fractions(current_hp, maximum_hp, 3, 10) >= 0: return []
	var context: Dictionary = event.get("payload", {}).get("attack_context", {})
	var scaled_amount := int(int(context.get("amount", 0)) * 125 / 100)
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")), "patch":{"amount":scaled_amount}}]


func _pe35_harvest(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "final_departure": return []
	var target_side := str(event.get("target_side", ""))
	var actions: Array = []
	for credit in event.get("payload", {}).get("credited_units", []):
		var side := str(credit.get("side", ""))
		if side not in ["A", "B"] or side == target_side: continue
		var team_marker := "%s1" % side
		if engine.get_counter(team_marker, "PE35_harvest_used") > 0: continue
		for unit in engine.units(side, true):
			actions.append({"kind":"heal", "target_key":str(unit.get("key", "")), "amount":30, "phase":"post_damage"})
		if not engine.units(side, true).is_empty():
			actions.append({"kind":"counter", "source_binding_key":team_marker, "counter_key":"PE35_harvest_used", "value":1})
	return actions


func _pe47_opening_judgment(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic" or int(event.get("tick", -1)) != 20: return []
	var actions: Array = []
	for side in ["A", "B"]:
		var highest: Dictionary = {}
		var highest_armor := -1
		for unit in engine.units(side, true):
			var armor := int(engine.effective_stats(str(unit.get("key", ""))).get("R", 0))
			if armor > highest_armor or (armor == highest_armor and int(unit.get("slot", 4)) < int(highest.get("slot", 4))):
				highest = unit
				highest_armor = armor
		if not highest.is_empty():
			actions.append({"kind":"damage", "target_key":str(highest.get("key", "")), "amount":40, "damage_type":"lightning"})
	return actions


func _pe48_late_shelter(engine: BattleEngine, event: Dictionary) -> Array:
	var kind := str(event.get("kind", ""))
	if kind == "hp_lost":
		var target_key := str(event.get("target_key", ""))
		if not target_key.is_empty() and engine.get_counter(target_key, "PE48_ever_lost_hp") == 0:
			return [{"kind":"counter", "source_binding_key":target_key, "counter_key":"PE48_ever_lost_hp", "value":1}]
		return []
	if kind != "periodic" or int(event.get("tick", -1)) != 80: return []
	var actions: Array = []
	for side in ["A", "B"]:
		for unit in engine.units(side, true):
			var key := str(unit.get("key", ""))
			if engine.get_counter(key, "PE48_ever_lost_hp") == 0:
				actions.append({"kind":"barrier_grant", "target_key":key, "expires_tick":PERMANENT_BARRIER_EXPIRY})
	return actions


func _pe38_solo_rations(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "final_departure": return []
	var side := str(event.get("target_side", ""))
	if side not in ["A", "B"] or engine.units(side, true).size() != 1: return []
	var team_marker := "%s1" % side
	if engine.get_counter(team_marker, "PE38_solo_window_used") > 0: return []
	var lone_unit: Dictionary = engine.units(side, true)[0]
	var target_key := str(lone_unit.get("key", ""))
	var tick := int(event.get("tick", -1))
	var actions: Array = [
		{"kind":"shield_grant","target_key":target_key,"amount":60,"expires_tick":PERMANENT_BARRIER_EXPIRY},
		{"kind":"counter","source_binding_key":team_marker,"counter_key":"PE38_solo_window_used","value":1}
	]
	for second in range(1, 5):
		actions.append({
			"kind":"schedule",
			"tick":tick + second * 10,
			"phase":"post_damage",
			"action":{"kind":"heal","target_key":target_key,"amount":10}
		})
	return actions


func _pe39_encumbrance(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic" or int(event.get("tick", -1)) != 120: return []
	var actions: Array = []
	for side in ["A", "B"]:
		for unit in engine.units(side, true):
			var key := str(unit.get("key", ""))
			var shield_total := engine.shield_amount(key)
			var removed := int(shield_total / 2)
			var healing := int(removed / 2)
			if removed > 0: actions.append({"kind":"shield_consume", "target_key":key, "amount":removed})
			if healing > 0: actions.append({"kind":"heal", "target_key":key, "amount":healing})
	return actions


func _is_melee_cross(engine: BattleEngine, event: Dictionary) -> bool:
	if str(event.get("kind", "")) != "prepare_attack": return false
	var source_key := str(event.get("source_key", ""))
	var target_key := str(event.get("target_key", ""))
	var attacker_slot := source_key.substr(1).to_int() if source_key.length() > 1 else -1
	var target_slot := target_key.substr(1).to_int() if target_key.length() > 1 else -1
	var attacker := engine.unit(source_key)
	return str(attacker.get("reach", "")) == "melee" and not bool(attacker.get("flying", false)) and attacker_slot != target_slot


func _is_cross_melee_hit(engine: BattleEngine, event: Dictionary) -> bool:
	if str(event.get("kind", "")) != "hit" or not bool(event.get("is_attack", false)): return false
	var source_key := str(event.get("source_key", ""))
	var target_key := str(event.get("target_key", ""))
	var attacker := engine.unit(source_key)
	if attacker.is_empty() or target_key.is_empty(): return false
	var attacker_slot := int(attacker.get("slot", 0))
	var target_slot := int(event.get("target_slot", 0))
	return str(attacker.get("reach", "")) == "melee" and not bool(attacker.get("flying", false)) and attacker_slot != target_slot


func _is_ranged_cross(engine: BattleEngine, event: Dictionary) -> bool:
	if str(event.get("kind", "")) != "prepare_attack": return false
	var source_key := str(event.get("source_key", ""))
	var target_key := str(event.get("target_key", ""))
	var attacker_slot := source_key.substr(1).to_int() if source_key.length() > 1 else -1
	var target_slot := target_key.substr(1).to_int() if target_key.length() > 1 else -1
	return str(engine.unit(source_key).get("reach", "")) == "ranged" and attacker_slot != target_slot


func _preparation_patch(event: Dictionary, delta_ticks: int, interval_multiplier_bp: int = 10000) -> Array:
	var patch := {}
	if delta_ticks != 0: patch["preparation_delay_ticks"] = delta_ticks
	if interval_multiplier_bp != 10000: patch["interval_multiplier_bp"] = interval_multiplier_bp
	return [{"kind":"attack_patch", "attack_id":str(event.get("payload", {}).get("attack_id", "")), "patch":patch}]


func _ar08_embers(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic": return []
	var tick := int(event.get("tick", -1))
	if tick not in [50, 100, 150, 200]: return []
	var actions: Array = []
	for side in ["A", "B"]:
		for unit in engine.units(side, true):
			actions.append({
				"kind":"damage",
				"target_key":str(unit.get("key", "")),
				"amount":20,
				"damage_type":"fire"
			})
	return actions


func _ar13_rust(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic": return []
	var tick := int(event.get("tick", -1))
	if tick not in [80, 160]: return []
	var armor_loss_needed := 1 if tick == 80 else 2
	var actions: Array = []
	for side in ["A", "B"]:
		for unit in engine.units(side, true):
			if int(unit.get("base_R", 0)) < armor_loss_needed: continue
			actions.append({
				"kind":"modifier_add",
				"target_key":str(unit.get("key", "")),
				"stat":"R_flat",
				"amount":-1,
				"modifier_id":"AR13_base_armor_loss_%d" % tick
			})
	return actions


func _ar14_slowest_barrier(engine: BattleEngine) -> Array:
	var actions: Array = []
	for side in ["A", "B"]:
		var slowest_slot := 1
		var longest_ticks := -1
		for unit in engine.units(side, true):
			var ticks := int(unit.get("base_T_ticks", unit.get("T_ticks", 0)))
			var slot := int(unit.get("slot", 4))
			if ticks > longest_ticks or (ticks == longest_ticks and slot < slowest_slot):
				longest_ticks = ticks
				slowest_slot = slot
		actions.append({
			"kind":"barrier_grant",
			"target_key":"%s%d" % [side, slowest_slot],
			"expires_tick":PERMANENT_BARRIER_EXPIRY
		})
	return actions


func _ar15_bloody_altar(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "hp_lost" or int(event.get("tick", -1)) < 60: return []
	var target_key := str(event.get("target_key", ""))
	var maximum_hp := int(engine.unit(target_key).get("initial_max_hp_tenths", 0))
	if maximum_hp <= 0: return []
	var before_hp := int(event.get("payload", {}).get("batch_hp_before_tenths", -1))
	var after_hp := int(event.get("payload", {}).get("batch_hp_after_tenths", -1))
	var half_health_floor := maximum_hp >> 1
	if before_hp <= half_health_floor or after_hp > half_health_floor: return []
	if engine.get_counter(target_key, "AR15_threshold_shield_used") > 0: return []
	return [
		{"kind":"shield_grant","target_key":target_key,"amount":40,"expires_tick":1_000_000},
		{"kind":"counter","source_binding_key":target_key,"counter_key":"AR15_threshold_shield_used","value":1}
	]


	
func _ar16_starting_silence(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("payload", {}).get("phase", "")) != "environment_initial": return []
	var actions: Array = []
	for side in ["A", "B"]:
		for unit in engine.units(side, true):
			actions.append({
				"kind":"status_add",
				"target_key":str(unit.get("key", "")),
				"status_id":"silence",
				"layers":1,
				"expires_tick":20
			})
	return actions


func _pe05_frost_rain(engine: BattleEngine, event: Dictionary) -> Array:
	if str(event.get("kind", "")) != "periodic": return []
	var tick := int(event.get("tick", -1))
	if tick <= 0 or tick % 40 != 0: return []
	var actions: Array = []
	for side in ["A", "B"]:
		for unit in engine.units(side, true):
			if not (unit.get("shield_pools", []) as Array).is_empty(): continue
			actions.append({
				"kind":"status_add",
				"target_key":str(unit.get("key", "")),
				"status_id":"chill",
				"layers":1,
				"expires_tick":tick + 20
			})
	return actions
