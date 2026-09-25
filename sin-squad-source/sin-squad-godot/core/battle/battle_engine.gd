extends RefCounted
class_name BattleEngine

const VictoryRules = preload("res://core/rules/victory_rules.gd")
const SIDES: Array[String] = ["A", "B"]
const MAX_EVENT_ACTIONS := 4096
const MAX_TRANSFER_RATIO := 7500
const MAX_DAMAGE_TENTHS := 1_000_000_000

var state: Dictionary = {}
var bindings: Array[Dictionary] = []
var handlers: Dictionary = {}
var configured := false
var fixture_mode := false


func setup(config: Dictionary, p_handlers: Array = [], options: Dictionary = {}) -> Dictionary:
	state = {}
	bindings.clear()
	handlers.clear()
	configured = false
	for option_key in options:
		if str(option_key) != "capture_tick_hashes": return _error("未知 setup option: %s" % str(option_key))
	fixture_mode = bool(config.get("test_fixture", false))
	var validation := _validate_config(config, p_handlers)
	if not validation.is_empty():
		return _error(validation)
	for handler in p_handlers:
		if handler is Dictionary:
			var item: Dictionary = handler.duplicate(true)
			var handler_id := str(item.get("logic_handler", item.get("handler_id", "")))
			if handler_id.is_empty() or handlers.has(handler_id):
				return _error("handler ID 缺失或重复: %s" % handler_id)
			handlers[handler_id] = item.get("handler", item.get("implementation", null))
			if item.has("content_id"):
				bindings.append(item)
			else:
				for binding in item.get("bindings", []):
					var installed: Dictionary = binding.duplicate(true)
					if not installed.has("logic_handler"): installed["logic_handler"] = handler_id
					bindings.append(installed)
		else:
			return _error("handlers 每项必须为 Dictionary")
	bindings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("source_key", "")) < str(b.get("source_key", "")))
	for binding in bindings:
		var binding_handler_id := str(binding.get("logic_handler", ""))
		if binding_handler_id.is_empty() or not handlers.has(binding_handler_id):
			return _error("binding %s 引用未知处理器 %s" % [binding.get("content_id", ""), binding_handler_id])
	var units: Dictionary = {"A": [], "B": []}
	for side in SIDES:
		for definition in config["teams"][side]:
			units[side].append(_make_unit(side, definition))
	state = {
		"schema_version": 1,
		"seed": int(config.get("seed", 0)),
		"rule_id": str(config["rule_id"]),
		"arena_id": str(config.get("arena_id", "")),
		"public_effect_ids": config.get("public_effect_ids", []).duplicate(),
		"tick": 0,
		"teams": units,
		"queue": [],
		"pending_damage": [],
		"pending_attacks": {},
		"delivered_event_ids": {},
		"events": [],
		"tick_hashes": [],
		"final_departures": [],
		"victory_memory": {},
		"winner": null,
		"reason": "",
		"terminal": false,
		"error": "",
		"event_serial": 0,
		"root_serial": 0,
		"root_triggered": {},
		"root_action_counts": {},
		"status_serial": 0,
		"battle_started": false,
		"content_coverage": {"fixture_ids": [], "handler_ids": []},
		"first_natural_attack_tick": {"A": null, "B": null},
		"active_damage_entry_id":"","active_damage_deferred":0,"active_damage_available":0,
		"active_damage_reduction_bp":0,"damage_reduction_bp":0,
		"status_tick_modifiers":[],
		"redirect_capacity_used":{},"root_redirect_capacity_used":{},"shield_pool_serial":0,
		"capture_tick_hashes":bool(options.get("capture_tick_hashes", true))
	}
	for binding in bindings:
		state.content_coverage.handler_ids.append(str(binding.get("content_id", "")))
	for side in SIDES:
		for unit in units[side]:
			if bool(unit.get("fixture", false)):
				state.content_coverage.fixture_ids.append(unit.definition_id)
	configured = true
	return _result()


func set_capture_tick_hashes(enabled: bool) -> Dictionary:
	if not configured: return _error("BattleEngine.setup 必须先成功")
	state.capture_tick_hashes = enabled
	return _result()


## Public defensive copy for UI/AI consumers; callers must not mutate engine state.
func snapshot() -> Dictionary:
	if not configured: return {}
	return _snapshot()


## Public result copy, including a defensive snapshot and current deterministic hash.
func result() -> Dictionary:
	if not configured: return _error("BattleEngine.setup 必须先成功")
	return _result()


func step(capture_details: bool = true) -> Dictionary:
	if not configured:
		return _error("BattleEngine.setup 必须先成功")
	if not str(state.error).is_empty():
		return _error(str(state.error))
	if bool(state.terminal):
		return _result() if capture_details else _light_step_result([])
	var deadline := 120 if state.rule_id == "VC21" else (360 if state.rule_id == "VC22" else 240)
	if state.tick > deadline:
		return _fail("引擎 tick 越过胜利规则期限")
	var tick_events: Array = []
	# The deadline tick is adjudication-only: no attacks, status ticks, heals, or expiries run.
	if int(state.tick) < deadline:
		_process_expiries(tick_events)
		_deliver_events(tick_events)
		if not state.battle_started:
			state.battle_started = true
			_emit_root("pre_battle", "", -1, "", {"phase":"static_snapshot","eligible_binding_kinds":["equipment","slot"],"eligible_binding_phases":["static_snapshot"]}, tick_events)
			_deliver_events(tick_events)
			_emit_root("pre_battle", "", -1, "", {"phase":"environment_initial","eligible_binding_kinds":["environment","arena","public"],"eligible_binding_phases":["environment_initial"]}, tick_events)
			_deliver_events(tick_events)
			_emit_root("battle_start", "", -1, "", {"independent": true}, tick_events)
			_deliver_events(tick_events)
		_emit_root("periodic", "", -1, "", {"independent": true}, tick_events)
		_deliver_events(tick_events)
		# Independent effects resolve before the one same-tick damage batch.
		_process_queue_phase("pre_damage", tick_events)
		_process_periodic(tick_events)
		_process_expiries(tick_events, true)
		_deliver_events(tick_events)
		_process_queue_phase("damage", tick_events)
		_process_attack_timeline(tick_events)
		_process_queue_phase("damage", tick_events)
		_process_damage_batches(tick_events)
		_deliver_events(tick_events)
		var settle_rounds := 0
		while _has_due_queue("post_damage") and settle_rounds < 64 and state.error.is_empty():
			_process_queue_phase("post_damage", tick_events)
			_process_damage_batches(tick_events)
			_deliver_events(tick_events)
			settle_rounds += 1
		if settle_rounds >= 64 and _has_due_queue("post_damage"):
			return _fail("同刻派生动作超过安全事件预算")
		_process_queue_phase("cleanup", tick_events)
		_deliver_events(tick_events)
		_finalize_departures(tick_events)
		_deliver_events(tick_events)
		var departure_rounds := 0
		while (_has_due_queue("post_damage") or not state.pending_damage.is_empty()) and departure_rounds < 64 and state.error.is_empty():
			_process_queue_phase("post_damage", tick_events)
			_process_queue_phase("damage", tick_events)
			_process_damage_batches(tick_events)
			_deliver_events(tick_events)
			_finalize_departures(tick_events)
			_deliver_events(tick_events)
			departure_rounds += 1
		if departure_rounds >= 64 and (_has_due_queue("post_damage") or not state.pending_damage.is_empty()):
			return _fail("final_departure派生动作超过安全事件预算")
	if not str(state.error).is_empty(): return _error(str(state.error))
	var snapshot := _snapshot_for_rules()
	var adjudication: Dictionary = VictoryRules.evaluate(str(state.rule_id), int(state.tick), snapshot,
		state.victory_memory, state.final_departures)
	if adjudication.has("error"):
		return _fail("VictoryRules.evaluate: %s" % adjudication.error)
	state.victory_memory = adjudication.memory
	if adjudication.terminal:
		state.terminal = true
		state.winner = adjudication.winner
		state.reason = adjudication.reason
		_emit_root("battle_end", "", -1, "", {"winner": state.winner, "reason": state.reason}, tick_events)
	state.events.append_array(tick_events)
	if bool(state.get("capture_tick_hashes", true)):
		state.tick_hashes.append({"tick": state.tick, "hash": _hash_state()})
	if not state.terminal:
		state.tick += 1
	return _result(tick_events) if capture_details else _light_step_result(tick_events)


func simulate(config: Dictionary, p_handlers: Array = [], options: Dictionary = {}) -> Dictionary:
	for option_key in options:
		if str(option_key) != "capture_tick_hashes": return _error("未知 simulate option: %s" % str(option_key))
	var initialized := setup(config, p_handlers, options)
	if not str(initialized.get("error", "")).is_empty():
		return initialized
	var all_events: Array = []
	var first := step(false)
	if not str(first.get("error", "")).is_empty():
		return first
	all_events.append_array(first.events)
	var max_steps := 361
	while not bool(state.terminal) and max_steps > 0:
		var result := step(false)
		if not str(result.get("error", "")).is_empty():
			return result
		all_events.append_array(result.events)
		max_steps -= 1
	if not bool(state.terminal):
		return _fail("模拟超过安全时限")
	var result := _result()
	result.events = all_events
	result.tick_hashes = state.tick_hashes.duplicate(true)
	return result


func _light_step_result(events: Array) -> Dictionary:
	return {"events":events,"terminal":bool(state.get("terminal", false)),"winner":state.get("winner", null),
		"reason":str(state.get("reason", "")),"error":str(state.get("error", ""))}


## Explicitly scoped test seam for primitive fixtures; unavailable in production configs.
func fixture_apply(actions: Array) -> Dictionary:
	if not configured:
		return _error("BattleEngine.setup 必须先成功")
	if not fixture_mode:
		return _error("fixture_apply 仅允许 test_fixture=true")
	var events: Array = []
	var pending_damage: Array = []
	for action in actions:
		if not action is Dictionary:
			return _error("fixture action 必须为 Dictionary")
		var kind := str(action.get("kind", ""))
		match kind:
			"damage":
				pending_damage.append({"target_key":str(action.get("target", action.get("target_key", ""))),
					"source_key":str(action.get("source", action.get("source_key", ""))),
					"source_binding_key":str(action.get("source_binding_key", "")),"amount":int(action.get("amount", -1)),
					"damage_type":str(action.get("damage_type", "physical")),"armor_piercing":action.get("armor_piercing", 0),
					"is_self_loss":bool(action.get("is_self_loss", false)),"is_attack":bool(action.get("is_attack", false)),
					"is_natural_attack":bool(action.get("is_natural_attack", false)),"is_extra_attack":bool(action.get("is_extra_attack", false)),
					"extra_generation":int(action.get("extra_generation", 0)),"root_id":_action_root(action),
					"shield_only":bool(action.get("shield_only", false)),
					"triggered_bindings":action.get("triggered_bindings", []).duplicate(),"segment_index":int(action.get("segment_index", 0))})
			"heal":
				var target := _unit_by_key(str(action.get("target", "")))
				if target.is_empty(): return _error("heal target 无效")
				_apply_heal(target, int(action.get("amount", -1)), str(action.get("source", "")), events, "fixture", str(action.get("source_binding_key", "")))
			"shield_grant":
				var target := _unit_by_key(str(action.get("target", "")))
				if target.is_empty(): return _error("shield target 无效")
				_grant_shield(target, str(action.get("source", "fixture")), int(action.get("amount", -1)), int(action.get("expires_tick", state.tick + 10)), events,
					str(action.get("source_binding_key", "")),str(action.get("pool_mode", "refresh")),str(action.get("pool_id", "")),
					int(action.get("expected_revision", -1)),str(action.get("origin_pool_id", "")))
			"barrier_grant":
				var target := _unit_by_key(str(action.get("target", "")))
				if target.is_empty(): return _error("barrier target 无效")
				if not bool(target.barrier.active): target.barrier = {"active": true, "source_key": str(action.get("source", "fixture")),
					"source_binding_key":str(action.get("source_binding_key", "")),"expires_tick": int(action.get("expires_tick", state.tick + 10))}
			"redirect_register":
				var redirect_target := _unit_by_key(str(action.get("target", "")))
				if redirect_target.is_empty(): return _error("redirect target无效")
				redirect_target.redirects.append({"source_key":str(action.get("source", "fixture")),"ratio_bp":int(action.get("ratio_bp", 0)),
					"source_binding_key":str(action.get("source_binding_key", action.get("source", "fixture"))),
					"redirect_id":str(action.get("redirect_id", action.get("source_binding_key", action.get("source", "fixture")))),
					"recipient_keys":action.get("recipient_keys", []).duplicate(),"capacity_per_second":int(action.get("capacity_per_second", MAX_DAMAGE_TENTHS)),
					"capacity_per_root":int(action.get("capacity_per_root", MAX_DAMAGE_TENTHS)),"filters":{}})
			"status_add":
				var target := _unit_by_key(str(action.get("target", "")))
				if target.is_empty(): return _error("status target 无效")
				_add_status(target, action, events)
			"status_remove":
				var target := _unit_by_key(str(action.get("target", "")))
				if target.is_empty(): return _error("status target 无效")
				_remove_status(target, str(action.get("status_id", "")), int(action.get("layers", 1)), events)
			"silence":
				var target := _unit_by_key(str(action.get("target", "")))
				if target.is_empty(): return _error("silence target 无效")
				_add_status(target, {"status_id":"silence", "source_key":str(action.get("source", "fixture")), "layers":1, "expires_tick":int(action.get("expires_tick", state.tick + 10))}, events)
			"shield_clear":
				var target := _unit_by_key(str(action.get("target", "")))
				if target.is_empty(): return _error("shield target 无效")
				_clear_shields(target, events, true)
			"shield_consume":
				var target := _unit_by_key(str(action.get("target", "")))
				if target.is_empty(): return _error("shield target 无效")
				_consume_shields(target, int(action.get("amount", -1)), events, false)
			"shield_transfer":
				var source := _unit_by_key(str(action.get("from_target_key", "")))
				var recipients: Array = action.get("recipient_keys", [str(action.get("target", ""))])
				if source.is_empty() or not recipients is Array: return _error("shield_transfer source/recipients无效")
				var selector := {"pool_id":str(action.get("pool_id", "")),"source_key":str(action.get("pool_source_key", "")),
					"source_binding_key":str(action.get("pool_source_binding_key", "")),"expires_tick":int(action.get("pool_expires_tick", -1))}
				if not _transfer_shield(source, recipients, int(action.get("amount", -1)), selector, events, str(action.get("source_binding_key", "fixture"))):
					return _error(str(state.error))
			"revive":
				var target := _unit_by_key(str(action.get("target", "")))
				if target.is_empty(): return _error("revive target 无效")
				_revive(target, int(action.get("amount", -1)), str(action.get("source", "fixture")), events)
			"damage_batch":
				var entries: Array = action.get("entries", [])
				if not _resolve_damage_batch(entries, events): return _error(str(state.error))
			_: return _error("未知 fixture action: %s" % kind)
	if not pending_damage.is_empty() and not _resolve_damage_batch(pending_damage, events):
		return _error(str(state.error))
	_deliver_events(events)
	var drain_rounds := 0
	while not state.queue.is_empty() and drain_rounds < 64 and state.error.is_empty():
		var before_count: int = state.queue.size()
		_process_queue_phase("damage", events)
		_process_queue_phase("post_damage", events)
		_process_damage_batches(events)
		_deliver_events(events)
		drain_rounds += 1
		if state.queue.size() == before_count: break
	_finalize_departures(events)
	_deliver_events(events)
	state.events.append_array(events)
	return {"events": events, "snapshot": _snapshot_for_rules(), "error": ""}


func unit(key: String) -> Dictionary:
	var found := _unit_by_key(key)
	return found.duplicate(true)


func effective_stats(key: String) -> Dictionary:
	var found := _unit_by_key(key)
	if found.is_empty(): return {}
	var stats := {"H_max_tenths":_effective_max_hp_tenths(found),"A":_effective_stat(found, "A"),
		"A_tenths":_effective_stat(found, "A") * 10 + _modifier_amount(found, "A_tenths_flat"),
		"T_ticks":_effective_stat(found, "T_ticks"),"R":_effective_armor(found),"reach":str(found.reach),
		"damage_type":str(found.damage_type),"flying":bool(found.flying),"target_slot":int(found.target_slot)}
	for modifier in found.modifiers:
		var stat := str(modifier.get("stat", ""))
		if stat in ["reach", "damage_type", "flying"] and modifier.has("value"): stats[stat] = modifier.value
	return stats


func shield_amount(unit_key: String, source_binding_key: String = "") -> int:
	var found := _unit_by_key(unit_key)
	if found.is_empty(): return 0
	var total := 0
	for pool in found.shield_pools:
		if source_binding_key.is_empty() or str(pool.get("source_binding_key", "")) == source_binding_key: total += int(pool.amount)
	return total


func _effective_stat(target: Dictionary, stat: String) -> int:
	var value := int(target.get(stat, 0))
	var flat := 0
	var percent_bp := 0
	for modifier in target.modifiers:
		if str(modifier.get("stat", "")) == "%s_flat" % stat: flat += int(modifier.get("amount", 0))
		if str(modifier.get("stat", "")) == "%s_percent_bp" % stat: percent_bp += int(modifier.get("amount", 0))
	return maxi(0, int(floor(float((value + flat) * (10000 + percent_bp)) / 10000.0)))


func _modifier_amount(target: Dictionary, stat: String, source_binding_key: String = "") -> int:
	var total := 0
	for modifier in target.modifiers:
		if str(modifier.get("stat", "")) == stat and (source_binding_key.is_empty() or str(modifier.get("source_binding_key", "")) == source_binding_key):
			total += int(modifier.get("amount", 0))
	for modifier in target.get("setup_modifiers", []):
		if str(modifier.get("stat", "")) == stat and (source_binding_key.is_empty() or str(modifier.get("source_binding_key", "")) == source_binding_key):
			total += int(modifier.get("amount", 0))
	return total


func units(side: String, alive_only: bool = true) -> Array:
	if side not in SIDES: return []
	var result: Array = []
	for item in state.teams[side]:
		if not alive_only or _is_alive(item): result.append(item.duplicate(true))
	return result


func get_counter(source_key: String, counter: String) -> int:
	var owner := _source_owner(source_key)
	return int(owner.ability_counters.get(counter, 0)) if not owner.is_empty() else 0


func set_counter(source_key: String, counter: String, value: int) -> bool:
	var owner := _source_owner(source_key)
	if owner.is_empty() or counter.is_empty(): return false
	owner.ability_counters[counter] = value
	return true


func ready(source_key: String, cooldown_key: String = "default") -> bool:
	var owner := _source_owner(source_key)
	return not owner.is_empty() and int(owner.cooldowns.get(cooldown_key, 0)) <= int(state.tick)


func start_cooldown(source_key: String, ticks: int, cooldown_key: String = "default") -> bool:
	var owner := _source_owner(source_key)
	if owner.is_empty() or ticks < 0: return false
	owner.cooldowns[cooldown_key] = int(state.tick) + ticks
	return true


func _validate_config(config: Dictionary, p_handlers: Array) -> String:
	for key in ["seed", "rule_id", "teams"]:
		if not config.has(key): return "config 缺少字段 %s" % key
	if not config.seed is int or not config.rule_id is String:
		return "seed 必须为整数，rule_id 必须为字符串"
	if not (str(config.rule_id) in _all_rule_ids()): return "未知胜利规则 ID: %s" % str(config.rule_id)
	if not config.teams is Dictionary: return "teams 必须为 Dictionary"
	for side in SIDES:
		if not config.teams.has(side) or not config.teams[side] is Array or config.teams[side].size() != 3:
			return "teams.%s 必须包含三个固定阵位" % side
		for index in range(3):
			var definition = config.teams[side][index]
			if not definition is Dictionary: return "%s[%d] 必须为 Dictionary" % [side, index]
			for field in ["slot", "H", "A", "T_ticks", "R", "reach", "armor_kind"]:
				if not definition.has(field): return "%s[%d] 缺少 %s" % [side, index, field]
			if int(definition.slot) != index + 1: return "%s 阵位必须按1/2/3固定排序" % side
			if int(definition.H) <= 0 or int(definition.A) < 0 or int(definition.T_ticks) < 6 or int(definition.R) < 0:
				return "%s%d 面板数值越界；T_ticks最少6" % [side, index + 1]
			if str(definition.reach) not in ["melee", "ranged"] or str(definition.armor_kind) not in ["light", "medium", "heavy"]:
				return "%s%d reach/armor_kind 无效" % [side, index + 1]
			var id := str(definition.get("definition_id", definition.get("id", "")))
			if id.is_empty(): return "%s%d 缺少 definition_id" % [side, index + 1]
			if bool(definition.get("fixture", false)) and (not bool(config.get("test_fixture", false)) or not id.begins_with("FIXTURE_")):
				return "fixture人物只允许 test_fixture=true 且 ID 使用 FIXTURE_ 前缀"
			for content_field in ["talent_id", "equipment_id", "slot_effect_id"]:
				var content_id := str(definition.get(content_field, ""))
				if not content_id.is_empty() and not _has_content_binding(content_id, p_handlers):
					return "内容 %s 无已接入处理器；拒绝按白板运行" % content_id
			if not bool(definition.get("fixture", false)) and not id.begins_with("FIXTURE_") and str(definition.get("talent_id", "")).is_empty():
				return "%s 缺少已接入的talent_id；正式单位不能隐式白板化" % id
	return ""


func _make_unit(side: String, definition: Dictionary) -> Dictionary:
	var bare := {"H":int(definition.H),"A":int(definition.A),"T_ticks":int(definition.T_ticks),"R":int(definition.R),
		"reach":str(definition.reach),"damage_type":str(definition.get("damage_type", "physical")),"flying":bool(definition.get("flying", false))}
	var effective := bare.duplicate(true)
	var current_hp_delta := 0
	var current_hp_floor := 0
	for modifier in definition.get("setup_modifiers", []):
		if not modifier is Dictionary: continue
		var stat := str(modifier.get("stat", "")); var amount := int(modifier.get("amount", 0))
		match stat:
			"H_flat", "A_flat", "T_ticks_flat", "R_flat":
				var field := stat.trim_suffix("_flat")
				effective[field] = int(effective[field]) + amount
				if stat == "H_flat": current_hp_delta += amount * 10
				if stat == "H_flat" and modifier.has("minimum"): effective.H = maxi(int(effective.H), int(modifier.minimum))
			"A_tenths_flat": pass
			"current_hp_delta_tenths": current_hp_delta += amount
			"reach": effective.reach = str(modifier.get("value", effective.reach))
			"damage_type": effective.damage_type = str(modifier.get("value", effective.damage_type))
			"flying": effective.flying = bool(modifier.get("value", true))
		if modifier.has("current_hp_minimum"): current_hp_floor = maxi(current_hp_floor, int(modifier.current_hp_minimum) * 10)
	var max_hp := maxi(int(effective.H), 1) * 10
	var hp := int(definition.get("hp_tenths", int(bare.H) * 10)) + current_hp_delta
	hp = clampi(hp, current_hp_floor, max_hp)
	var speed_ticks := int(effective.T_ticks)
	return {"key":"%s%d" % [side, int(definition.slot)], "side":side, "slot":int(definition.slot),
		"definition_id":str(definition.get("definition_id", definition.get("id", ""))),
		"fixture":bool(definition.get("fixture", false)),
		"base_H":int(bare.H), "base_A":int(bare.A), "base_T_ticks":int(bare.T_ticks), "base_R":int(bare.R),
		"H":int(effective.H), "A":int(effective.A), "T_ticks":speed_ticks, "R":int(effective.R),
		"reach":str(effective.reach), "armor_kind":str(definition.armor_kind), "flying":bool(effective.flying), "damage_type":str(effective.damage_type),
		"target_slot":int(definition.get("target_slot", 1)), "hp_tenths":hp, "initial_max_hp_tenths":max_hp,
		"shield_pools":[], "barrier":{"active":false,"source_key":"","expires_tick":-1}, "statuses":[],
		"modifiers":[], "next_attack_tick":maxi(0, int(definition.get("first_attack_tick", 0))),
		"ability_counters":{}, "cooldowns":{}, "revive_used":false, "dead":hp <= 0, "final_departed":false,
		"pending_final":false, "source_ids":{"talent":str(definition.get("talent_id", "")),
		"equipment":str(definition.get("equipment_id", "")), "slot":str(definition.get("slot_effect_id", ""))},
		"first_natural_attack_tick":null, "redirects":[], "redirect_capacity_used":{},"prepared_attack_id":"",
		"setup_modifiers":definition.get("setup_modifiers", []).duplicate(true)}


func _all_rule_ids() -> Array:
	var result: Array = []
	for i in range(1, 31): result.append("VC%02d" % i)
	return result


func _has_content_binding(content_id: String, p_handlers: Array) -> bool:
	for handler in p_handlers:
		if handler is Dictionary:
			if str(handler.get("content_id", "")) == content_id: return true
			for binding in handler.get("bindings", []):
				if str(binding.get("content_id", "")) == content_id: return true
	return false


func _emit_root(kind: String, source: String, target_slot: int, target_side: String, payload: Dictionary, events: Array) -> Dictionary:
	state.root_serial += 1
	return _emit(kind, source, target_slot, target_side, payload.merged({"root_id":"root-%08d" % state.root_serial}, true), events)


func _emit(kind: String, source: String, target_slot: int, target_side: String, payload: Dictionary, events: Array) -> Dictionary:
	state.event_serial += 1
	var root_id := str(payload.get("root_id", ""))
	if root_id.is_empty():
		state.root_serial += 1
		root_id = "root-%08d" % state.root_serial
	var event := {"event_id":"event-%08d" % state.event_serial, "root_id":root_id,
		"tick":int(state.tick), "kind":kind, "source_key":source, "source":source,
		"source_binding_key":str(payload.get("source_binding_key", "")),
		"attack_id":str(payload.get("attack_id", "")),
		"target_key":"%s%d" % [target_side, target_slot] if target_slot > 0 else "",
		"target_slot":target_slot, "target_side":target_side, "cause_id":str(payload.get("cause_id", "")),
		"actual_hp_loss":int(payload.get("actual_hp_loss", 0)), "absorbed_shield":int(payload.get("absorbed_shield", 0)),
		"barrier_absorbed":int(payload.get("barrier_absorbed", 0)),
		"raw_amount":int(payload.get("raw_amount", 0)), "damage_type":str(payload.get("damage_type", "")),
		"is_natural_attack":bool(payload.get("is_natural_attack", false)),
		"is_extra_attack":bool(payload.get("is_extra_attack", false)),
		"is_attack":bool(payload.get("is_attack", false)) or bool(payload.get("is_natural_attack", false)) or bool(payload.get("is_extra_attack", false)),
		"is_redirected":bool(payload.get("is_redirected", false)),"is_attached_damage":bool(payload.get("is_attached_damage", false)),
		"is_direct_attack":bool(payload.get("is_direct_attack", false)),
		"extra_generation":int(payload.get("extra_generation", 0)),
		"triggered_bindings":payload.get("triggered_bindings", []).duplicate(), "payload":payload.duplicate(true)}
	events.append(event)
	return event


func _deliver_events(events: Array) -> void:
	var cursor := 0
	var action_count := 0
	while cursor < events.size():
		var event: Dictionary = events[cursor]
		cursor += 1
		var event_id := str(event.get("event_id", ""))
		if event_id.is_empty() or state.delivered_event_ids.has(event_id): continue
		state.delivered_event_ids[event_id] = true
		for binding in bindings:
			var handler_id := str(binding.get("logic_handler", ""))
			if not handlers.has(handler_id):
				state.error = "binding %s 引用未知处理器 %s" % [binding.get("content_id", ""), handler_id]
				return
			var implementation = handlers[handler_id]
			if implementation == null or not implementation.has_method("on_event"):
				state.error = "处理器 %s 未实现 on_event" % handler_id
				return
			if not _subscribed(binding, str(event.kind)): continue
			var eligible_kinds: Array = event.payload.get("eligible_binding_kinds", [])
			var eligible_phases: Array = event.payload.get("eligible_binding_phases", [])
			var binding_phase := str(binding.get("pre_battle_phase", ""))
			if not eligible_kinds.is_empty() and str(binding.get("kind", "")) not in eligible_kinds and binding_phase not in eligible_phases: continue
			if _binding_silenced(binding): continue
			var root_triggers: Array = state.root_triggered.get(str(event.root_id), event.payload.get("triggered_bindings", [])).duplicate()
			var source_key := str(binding.get("source_key", ""))
			var trigger_scope := str(binding.get("trigger_scope", "root"))
			if trigger_scope not in ["root", "event_target"]:
				state.error = "binding %s trigger_scope无效: %s" % [source_key, trigger_scope]
				return
			var trigger_token := source_key if trigger_scope == "root" else "%s@target:%s" % [source_key, str(event.get("target_key", ""))]
			if root_triggers.has(trigger_token): continue
			var emitted = implementation.on_event(self, binding.duplicate(true), event.duplicate(true))
			if not emitted is Array:
				state.error = "处理器 %s 必须返回动作Array" % handler_id
				return
			if emitted.is_empty(): continue
			root_triggers.append(trigger_token)
			state.root_triggered[str(event.root_id)] = root_triggers.duplicate()
			event.payload.triggered_bindings = root_triggers
			for action in emitted:
				action_count += 1
				var root_action_count := int(state.root_action_counts.get(str(event.root_id), 0)) + 1
				state.root_action_counts[str(event.root_id)] = root_action_count
				if root_action_count > MAX_EVENT_ACTIONS:
					state.error = "根事件动作预算超限 root=%s" % event.root_id
					return
				if not _dispatch_action(action, binding, event, events): return
	

func _subscribed(binding: Dictionary, event_kind: String) -> bool:
	var listens: Array = binding.get("subscribes", binding.get("events", []))
	return listens.is_empty() or listens.has(event_kind)


func _binding_silenced(binding: Dictionary) -> bool:
	if str(binding.get("kind", "")) != "talent": return false
	var owner := _unit_by_key(str(binding.get("owner_key", "")))
	if owner.is_empty(): return false
	for status in owner.statuses:
		if status.id == "silence" and int(status.expires_tick) > int(state.tick): return true
	return false


func _dispatch_action(action: Dictionary, binding: Dictionary, parent_event: Dictionary, events: Array) -> bool:
	if not action is Dictionary:
		state.error = "处理器动作必须为 Dictionary"
		return false
	var owner_key := str(binding.get("owner_key", ""))
	var source_key := str(action.get("source_key", owner_key))
	var source_binding_key := str(action.get("source_binding_key", binding.get("source_key", "")))
	var target_key := str(action.get("target_key", parent_event.get("target_key", "")))
	var kind := str(action.get("kind", ""))
	var payload := action.duplicate(true)
	payload["root_id"] = str(parent_event.root_id)
	payload["cause_id"] = str(parent_event.event_id)
	payload["triggered_bindings"] = parent_event.payload.get("triggered_bindings", []).duplicate()
	payload["source_binding_key"] = source_binding_key
	payload["extra_generation"] = int(parent_event.extra_generation)
	var target := _unit_by_key(target_key)
	match kind:
		"damage":
			if target.is_empty(): state.error = "damage动作目标无效"; return false
			_queue_damage({"target_key":target_key, "source_key":source_key, "amount":int(action.get("amount", -1)),
				"damage_type":str(action.get("damage_type", "physical")), "armor_piercing":action.get("armor_piercing", 0),
				"shield_only":bool(action.get("shield_only", false)),
				"root_id":payload.root_id, "cause_id":payload.cause_id,"source_binding_key":source_binding_key,
				"triggered_bindings":payload.triggered_bindings, "extra_generation":payload.extra_generation,
				"trigger_event_kind":str(parent_event.kind)})
		"self_loss":
			var self_target_key := str(action.get("target_key", owner_key))
			var self_unit := _unit_by_key(self_target_key)
			if self_unit.is_empty(): state.error = "self_loss缺少有效target_key/owner"; return false
			_queue_damage({"target_key":self_target_key,"source_key":self_target_key,"source_binding_key":source_binding_key,"amount":int(action.get("amount", -1)),
				"damage_type":"self_loss","is_self_loss":true,"root_id":payload.root_id,"cause_id":payload.cause_id,
				"trigger_event_kind":str(parent_event.kind),"triggered_bindings":payload.triggered_bindings.duplicate(),"extra_generation":payload.extra_generation})
		"heal":
			if target.is_empty(): state.error = "heal动作目标无效"; return false
			if str(action.get("phase", "pre_damage")) == "pre_damage": _apply_heal(target, int(action.get("amount", -1)), source_key, events, payload.root_id, source_binding_key)
			else: _queue_action("post_damage", action.merged({"target_key":target_key,"source_key":source_key,"source_binding_key":source_binding_key,
				"root_id":payload.root_id,"cause_id":payload.cause_id,"triggered_bindings":payload.triggered_bindings.duplicate(),"extra_generation":payload.extra_generation}, true))
		"shield_grant":
			if target.is_empty(): state.error = "shield_grant目标无效"; return false
			if not _grant_shield(target, source_key, int(action.get("amount", -1)), int(action.get("expires_tick", state.tick + 1)), events,
				str(action.get("source_binding_key", source_binding_key)),str(action.get("pool_mode", "refresh")),
				str(action.get("pool_id", "")),int(action.get("expected_revision", -1)),str(action.get("origin_pool_id", ""))): return false
		"shield_clear":
			if target.is_empty(): state.error = "shield_clear目标无效"; return false
			_clear_shields(target, events, true)
		"enemy_clear_shield":
			if target.is_empty() or target.side == str(_unit_by_key(owner_key).get("side", "")): state.error = "enemy_clear_shield目标必须为敌方单位"; return false
			var clear_result := _clear_shield_amount(target, int(action.get("amount", -1)), source_key, source_binding_key, events)
			if clear_result < 0: return false
			var attack_id := str(action.get("attack_id", parent_event.payload.get("attack_id", "")))
			if action.has("bonus_bp"):
				if not state.pending_attacks.has(attack_id): state.error = "enemy_clear_shield bonus找不到攻击"; return false
				var bonus_amount := int(floor(float(clear_result * int(action.get("bonus_bp", 0))) / 10000.0))
				if bonus_amount > 0:
					state.pending_attacks[attack_id].segments.append({"amount":bonus_amount,"damage_type":str(action.get("bonus_damage_type", "fixed")),
						"armor_piercing":action.get("armor_piercing", 0),"is_attack":true,"is_natural_attack":true})
		"shield_consume":
			if target.is_empty(): state.error = "shield_consume目标无效"; return false
			_consume_shields(target, int(action.get("amount", -1)), events, false, str(action.get("source_binding_key", "")))
		"shield_transfer":
			var from_unit := _unit_by_key(str(action.get("from_target_key", "")))
			var recipient_keys: Array = action.get("recipient_keys", [target_key] if not target_key.is_empty() else [])
			if from_unit.is_empty() or not recipient_keys is Array: state.error = "shield_transfer source/recipients无效"; return false
			var pool_filter := {"pool_id":str(action.get("pool_id", "")),"source_key":str(action.get("pool_source_key", "")),
				"source_binding_key":str(action.get("pool_source_binding_key", "")),"expires_tick":int(action.get("pool_expires_tick", -1))}
			if not _transfer_shield(from_unit, recipient_keys, int(action.get("amount", -1)), pool_filter, events, source_binding_key): return false
		"barrier_grant":
			if target.is_empty(): state.error = "barrier目标无效"; return false
			if not bool(target.barrier.active):
				target.barrier = {"active":true,"source_key":source_key,"source_binding_key":source_binding_key,"expires_tick":int(action.get("expires_tick", state.tick + 1))}
				_emit("shield_gained", source_key, target.slot, target.side, {"kind":"barrier","source_binding_key":source_binding_key}, events)
		"status_add":
			if target.is_empty(): state.error = "status_add目标无效"; return false
			_add_status(target, action.merged({"source_key":source_key,"source_binding_key":source_binding_key}, true), events)
		"status_remove":
			if target.is_empty(): state.error = "status_remove目标无效"; return false
			_remove_status(target, str(action.get("status_id", "")), int(action.get("layers", 1)), events, str(action.get("source_binding_key", "")))
		"status_expiry_suppress":
			if target.is_empty() or str(action.get("status_id", "")) not in ["burn", "chill", "bleed", "poison", "silence", "rooted", "anti_heal"]:
				state.error = "status_expiry_suppress目标或状态无效"; return false
			for status in target.statuses:
				if str(status.id) != str(action.status_id): continue
				if action.has("status_cycle_id") and int(status.get("status_cycle_id", 0)) != int(action.status_cycle_id): continue
				if action.has("status_instance_id") and int(status.get("status_instance_id", 0)) != int(action.status_instance_id): continue
				status.expiry_suppressed = true
				status.expires_tick = -1
		"status_tick_modifier":
			var status_id := str(action.get("status_id", ""))
			var amount_bp := int(action.get("amount_bp", -20001))
			if status_id not in ["burn", "bleed", "poison"] or amount_bp < -10000 or amount_bp > 100000:
				state.error = "status_tick_modifier参数无效"; return false
			var modifier_source := str(action.get("source_binding_key", source_binding_key))
			var modifier_index := -1
			for i in range(state.status_tick_modifiers.size()):
				var existing_modifier: Dictionary = state.status_tick_modifiers[i]
				if str(existing_modifier.status_id) == status_id and str(existing_modifier.source_binding_key) == modifier_source: modifier_index = i; break
			var tick_modifier := {"status_id":status_id,"source_binding_key":modifier_source,"amount_bp":amount_bp,"expires_tick":int(action.get("expires_tick", -1))}
			if modifier_index >= 0: state.status_tick_modifiers[modifier_index] = tick_modifier
			else: state.status_tick_modifiers.append(tick_modifier)
		"modifier_add":
			if target.is_empty(): state.error = "modifier_add目标无效"; return false
			target.modifiers.append(action.merged({"source_key":source_key,"source_binding_key":source_binding_key,
				"modifier_id":str(action.get("modifier_id", action.get("modifier_key", source_binding_key))),"expires_tick":int(action.get("expires_tick", -1))}, true))
			_clamp_current_hp_to_max(target)
		"modifier_remove":
			if target.is_empty(): state.error = "modifier_remove目标无效"; return false
			_remove_modifier(target, str(action.get("modifier_id", action.get("modifier_key", ""))), str(action.get("source_binding_key", source_binding_key)))
		"schedule":
			var due := int(action.get("tick", -1))
			if due < int(state.tick): state.error = "schedule tick 不得倒退"; return false
			var scheduled: Dictionary = action.get("action", {}).duplicate(true)
			if str(scheduled.get("kind", "")).is_empty(): state.error = "schedule缺少嵌套action kind"; return false
			scheduled["root_id"] = payload.root_id
			if not scheduled.has("source_key"): scheduled["source_key"] = source_key
			if not scheduled.has("source_binding_key"): scheduled["source_binding_key"] = source_binding_key
			scheduled["cause_id"] = payload.cause_id
			scheduled["triggered_bindings"] = payload.triggered_bindings.duplicate()
			scheduled["extra_generation"] = payload.extra_generation
			scheduled["independent_root"] = bool(action.get("independent", false))
			_queue_action(str(action.get("phase", "damage")), scheduled, due)
		"extra_attack":
			if int(parent_event.extra_generation) >= 1: return true
			var attacker_key := str(action.get("attacker_key", owner_key))
			var attacker := _unit_by_key(attacker_key)
			var owner := _unit_by_key(owner_key)
			if attacker.is_empty() or owner.is_empty() or attacker.side != owner.side:
				state.error = "extra_attack attacker_key必须是owner同队单位"; return false
			var amount_bp := int(action.get("amount_bp_of_attacker", -1))
			if amount_bp > 50000: state.error = "extra_attack amount_bp_of_attacker超限"; return false
			_queue_action("post_damage", {"kind":"extra_attack","source_key":attacker_key,"attacker_key":attacker_key,
				"source_binding_key":source_binding_key,"target_key":target_key,
				"amount":int(action.get("amount", 0)),"amount_bp_of_attacker":amount_bp,
				"inherit_damage_type":bool(action.get("inherit_damage_type", false)),"damage_type":str(action.get("damage_type", "physical")),
				"armor_piercing":action.get("armor_piercing", 0),
				"root_id":payload.root_id,"cause_id":payload.cause_id,"triggered_bindings":payload.triggered_bindings.duplicate(),
				"extra_generation":int(parent_event.extra_generation) + 1})
		"revive":
			if target.is_empty(): state.error = "revive目标无效"; return false
			_revive(target, int(action.get("amount", -1)), source_key, events)
		"attack_patch":
			var attack_id := str(action.get("attack_id", parent_event.payload.get("attack_id", "")))
			if not state.pending_attacks.has(attack_id): state.error = "attack_patch找不到待命中攻击 %s" % attack_id; return false
			var attack: Dictionary = state.pending_attacks[attack_id]
			var patch_data: Dictionary = action.get("patch", {})
			for field in patch_data:
				if field not in ["amount", "amount_flat", "damage_type", "armor_piercing", "segments", "append_segments", "attached_damage", "preparation_delay_ticks", "interval_multiplier_bp", "target_key", "bonus_packets", "bonus_amount", "ignore_slow_for_this_attack", "suppress", "convert_physical_to_fixed_bypass_shield", "consume_on_hit"]:
					state.error = "未知 attack_patch 字段: %s" % str(field); return false
			for field in ["amount", "damage_type", "armor_piercing", "segments", "attached_damage", "preparation_delay_ticks", "interval_multiplier_bp", "target_key"]:
				if not patch_data.has(field): continue
				if field == "attached_damage":
					for attached in patch_data.attached_damage:
						var installed: Dictionary = attached.duplicate(true)
						installed["source_key"] = str(attached.get("source_unit_key", owner_key))
						installed["source_binding_key"] = source_binding_key
						attack.attached_damage.append(installed)
				else:
					attack[field] = patch_data[field].duplicate(true) if patch_data[field] is Array or patch_data[field] is Dictionary else patch_data[field]
			if patch_data.has("segments"):
				for segment in patch_data.segments:
					if not segment is Dictionary or int(segment.get("amount", -1)) < 0 or str(segment.get("damage_type", "")) not in ["physical", "fire", "ice", "lightning", "poison", "fixed"]:
						state.error = "attack_patch segments元素无效"; return false
					for segment_field in segment:
						if segment_field not in ["amount", "damage_type", "armor_piercing", "is_attack", "is_natural_attack", "bypass_shield", "follow_main_damage_type", "target_key"]:
							state.error = "未知 attack_patch segment字段: %s" % str(segment_field); return false
			if patch_data.has("append_segments"):
				if not patch_data.append_segments is Array: state.error = "attack_patch append_segments必须为Array"; return false
				for segment_spec in patch_data.append_segments:
					if not segment_spec is Dictionary or int(segment_spec.get("amount", -1)) < 0 or str(segment_spec.get("damage_type", "")) not in ["physical", "fire", "ice", "lightning", "poison", "fixed"]:
						state.error = "attack_patch append_segments元素无效"; return false
					for segment_field in segment_spec:
						if segment_field not in ["amount", "damage_type", "armor_piercing", "bypass_shield", "target_key"]:
							state.error = "未知 attack_patch append_segment字段: %s" % str(segment_field); return false
					var appended_segment := {"amount":int(segment_spec.amount),"damage_type":str(segment_spec.damage_type),
						"armor_piercing":segment_spec.get("armor_piercing", 0),"bypass_shield":bool(segment_spec.get("bypass_shield", false)),
						"is_attack":true,"is_natural_attack":true,"follow_main_damage_type":false}
					if segment_spec.has("target_key"): appended_segment["target_key"] = str(segment_spec.target_key)
					attack.segments.append(appended_segment)
			if patch_data.has("attached_damage"):
				if not patch_data.attached_damage is Array: state.error = "attack_patch attached_damage必须为Array"; return false
				for attached_spec in patch_data.attached_damage:
					if not attached_spec is Dictionary or int(attached_spec.get("amount", -1)) < 0 or str(attached_spec.get("damage_type", "fixed")) not in ["physical", "fire", "ice", "lightning", "poison", "fixed"]:
						state.error = "attack_patch attached_damage元素无效"; return false
					for attached_field in attached_spec:
						if attached_field not in ["amount", "damage_type", "armor_piercing", "target_key", "bypass_shield", "shield_only", "source_unit_key"]:
							state.error = "未知 attack_patch attached_damage字段: %s" % str(attached_field); return false
					if attached_spec.has("source_unit_key"):
						var attached_source := _unit_by_key(str(attached_spec.source_unit_key))
						var owner := _unit_by_key(owner_key)
						if attached_source.is_empty() or owner.is_empty() or attached_source.side != owner.side:
							state.error = "attached_damage source_unit_key必须为有效同队单位"; return false
			if patch_data.has("consume_on_hit"):
				if not patch_data.consume_on_hit is Array: state.error = "attack_patch consume_on_hit必须为Array"; return false
				if not attack.has("consume_on_hit"): attack.consume_on_hit = []
				for consume_spec in patch_data.consume_on_hit:
					if not consume_spec is Dictionary or str(consume_spec.get("counter_key", "")).is_empty() or int(consume_spec.get("amount", 1)) <= 0:
						state.error = "attack_patch consume_on_hit元素无效"; return false
					for consume_field in consume_spec:
						if consume_field not in ["counter_key", "amount"]: state.error = "未知 consume_on_hit字段: %s" % str(consume_field); return false
					attack.consume_on_hit.append({"source_binding_key":source_binding_key,"counter_key":str(consume_spec.counter_key),"amount":int(consume_spec.get("amount", 1))})
			if patch_data.has("bonus_packets") or patch_data.has("bonus_amount"):
				var bonus_packets := int(patch_data.get("bonus_packets", 0))
				var bonus_amount := int(patch_data.get("bonus_amount", 0))
				if bonus_packets < 0 or bonus_amount < 0: state.error = "bonus_packets/bonus_amount不得为负数"; return false
				for _i in range(bonus_packets): attack.attached_damage.append({"amount":bonus_amount,"damage_type":str(patch_data.get("damage_type", attack.damage_type)),"armor_piercing":patch_data.get("armor_piercing", 0),"source_key":owner_key,"source_binding_key":source_binding_key})
			if patch_data.has("damage_type"):
				for segment in attack.segments:
					if bool(segment.get("follow_main_damage_type", true)): segment.damage_type = str(patch_data.damage_type)
			if patch_data.has("armor_piercing"):
				for segment in attack.segments: segment.armor_piercing = patch_data.armor_piercing
			if patch_data.has("amount") and not patch_data.has("segments") and not attack.segments.is_empty(): attack.segments[0].amount = int(patch_data.amount)
			if patch_data.has("amount_flat") and not attack.segments.is_empty(): attack.segments[0].amount += int(patch_data.amount_flat)
			if patch_data.has("ignore_slow_for_this_attack"):
				if not patch_data.ignore_slow_for_this_attack is bool: state.error = "ignore_slow_for_this_attack必须为bool"; return false
				attack.ignore_slow_for_this_attack = patch_data.ignore_slow_for_this_attack
			if patch_data.has("suppress"):
				if not patch_data.suppress is bool: state.error = "suppress必须为bool"; return false
				attack.suppressed = patch_data.suppress
			if patch_data.has("convert_physical_to_fixed_bypass_shield"):
				var conversion := int(patch_data.convert_physical_to_fixed_bypass_shield)
				if conversion < 0: state.error = "伤害转换不得为负数"; return false
				var converted_segments: Array = []
				var conversion_remaining := conversion
				for segment in attack.segments:
					var converted := mini(conversion_remaining, int(segment.amount)) if str(segment.damage_type) == "physical" else 0
					conversion_remaining -= converted
					var physical_part := int(segment.amount) - converted
					if physical_part > 0:
						var physical_segment: Dictionary = segment.duplicate(true); physical_segment.amount = physical_part; converted_segments.append(physical_segment)
					if converted > 0: converted_segments.append({"amount":converted,"damage_type":"fixed","armor_piercing":0,"bypass_shield":true,"is_attack":true,"is_natural_attack":true})
				attack.segments = converted_segments
			state.pending_attacks[attack_id] = attack
		"redirect_register":
			if owner_key.is_empty(): state.error = "redirect_register缺少owner"; return false
			var owner := _unit_by_key(owner_key)
			if owner.is_empty() or target.is_empty() or target.side != owner.side: state.error = "redirect_register要求有效的友方受保护target_key"; return false
			var redirect_ratio := int(action.get("ratio_bp", -1))
			var root_capacity := int(action.get("capacity_per_root", MAX_DAMAGE_TENTHS))
			var second_capacity := int(action.get("capacity_per_second", MAX_DAMAGE_TENTHS))
			if redirect_ratio < 0 or redirect_ratio > 10000 or root_capacity < 0 or second_capacity < 0 or not action.get("recipient_keys", []) is Array:
				state.error = "redirect_register ratio/capacity/recipient_keys无效"; return false
			var redirect_filters: Dictionary = action.get("filters", {}).duplicate(true)
			redirect_filters["owner_key"] = str(redirect_filters.get("owner_key", owner_key))
			target.redirects.append({"redirect_id":str(action.get("redirect_id", source_binding_key)),"source_key":source_key,
				"source_binding_key":source_binding_key,"owner_key":owner_key,"ratio_bp":redirect_ratio,
				"recipient_keys":action.get("recipient_keys", []).duplicate(),"capacity_per_second":second_capacity,
				"capacity_per_root":root_capacity,
				"filters":redirect_filters})
		"counter":
			if not set_counter(source_binding_key, str(action.get("counter_key", "")), int(action.get("value", 0))): state.error = "counter目标无效"; return false
		"cooldown":
			if not start_cooldown(source_binding_key, int(action.get("ticks", -1)), str(action.get("cooldown_key", "default"))): state.error = "cooldown参数无效"; return false
		"attack_suppress":
			var suppress_id := str(action.get("attack_id", parent_event.payload.get("attack_id", "")))
			if not state.pending_attacks.has(suppress_id): state.error = "attack_suppress找不到待处理攻击"; return false
			state.pending_attacks[suppress_id].suppressed = true
		"defer_damage":
			var current_id := str(parent_event.payload.get("damage_entry_id", ""))
			var deferred_amount := int(action.get("amount", -1))
			var due_tick := int(action.get("due_tick", -1))
			if current_id.is_empty() or current_id != str(state.active_damage_entry_id) or deferred_amount < 0 or deferred_amount > int(state.active_damage_available) or due_tick <= int(state.tick): state.error = "defer_damage参数/上下文无效"; return false
			state.active_damage_deferred = int(state.active_damage_deferred) + deferred_amount
			_queue_action("damage", {"kind":"damage","target_key":target_key,"source_key":source_key,
				"source_binding_key":source_binding_key,"amount":deferred_amount,"damage_type":str(action.get("damage_type", "fixed")),
				"root_id":payload.root_id,"skip_armor_and_reduction":bool(action.get("skip_armor_and_reduction", false)),
				"enter_shield_step":bool(action.get("enter_shield_step", false))}, due_tick)
		"damage_reduction":
			var current_damage_id := str(parent_event.payload.get("damage_entry_id", ""))
			var reduction_bp := int(action.get("amount_bp", -1))
			if str(parent_event.kind) != "before_damage" or current_damage_id.is_empty() or current_damage_id != str(state.active_damage_entry_id) or reduction_bp < 0:
				state.error = "damage_reduction仅可在有效before_damage上下文中使用"; return false
			state.active_damage_reduction_bp = int(state.active_damage_reduction_bp) + reduction_bp
		_: state.error = "未知动作 ID: %s" % kind; return false
	return true


func _queue_action(phase: String, action: Dictionary, due_tick: int = -1) -> void:
	state.queue.append({"phase":phase,"tick":int(state.tick) if due_tick < 0 else due_tick,"action":action.duplicate(true),"serial":state.queue.size()})


func _queue_damage(entry: Dictionary) -> void:
	var phase := "post_damage" if str(entry.get("trigger_event_kind", "")) in ["hit", "hp_lost", "attack_resolved", "final_departure"] else "damage"
	_queue_action(phase, {"kind":"damage_entry","entry":entry.duplicate(true)})


func _has_due_queue(phase: String) -> bool:
	for item in state.queue:
		if str(item.phase) == phase and int(item.tick) <= int(state.tick): return true
	return false


func _process_queue_phase(phase: String, events: Array) -> void:
	var remaining: Array = []
	var selected: Array = []
	for queued in state.queue:
		if str(queued.phase) == phase and int(queued.tick) <= int(state.tick): selected.append(queued)
		else: remaining.append(queued)
	state.queue = remaining
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.serial) < int(b.serial))
	for queued in selected:
		var action: Dictionary = queued.action
		if bool(action.get("independent_root", false)): action["root_id"] = _new_root()
		if action.get("kind", "") in ["damage_entry", "extra_attack"]:
			if action.kind == "damage_entry": state.pending_damage.append(action.entry)
			else: _execute_extra_attack(action, events)
		elif action.get("kind", "") in ["damage", "self_loss"]:
			var damage_type := "self_loss" if action.kind == "self_loss" else str(action.get("damage_type", "physical"))
			state.pending_damage.append({"target_key":str(action.get("target_key", action.get("target", ""))),
				"source_key":str(action.get("source_key", "")),"source_binding_key":str(action.get("source_binding_key", "")),
				"amount":int(action.get("amount", -1)),"damage_type":damage_type,"is_self_loss":action.kind == "self_loss",
				"root_id":_action_root(action),"cause_id":str(action.get("cause_id", "")),
				"extra_generation":int(action.get("extra_generation", 0)),"triggered_bindings":action.get("triggered_bindings", []).duplicate(),
				"skip_armor_and_reduction":bool(action.get("skip_armor_and_reduction", false)),"enter_shield_step":bool(action.get("enter_shield_step", false))})
		elif action.get("kind", "") == "heal":
			var target := _unit_by_key(str(action.get("target_key", "")))
			if not target.is_empty(): _apply_heal(target, int(action.get("amount", -1)), str(action.get("source_key", "")), events, str(action.get("root_id", "")), str(action.get("source_binding_key", "")))
		elif action.get("kind", "") == "shield_grant":
			var target := _unit_by_key(str(action.get("target_key", "")))
			if target.is_empty(): state.error = "scheduled shield target无效"; return
			if not _is_alive(target) or int(action.get("expires_tick", -1)) <= int(state.tick): continue
			if not _grant_shield(target, str(action.get("source_key", "")), int(action.get("amount", -1)), int(action.get("expires_tick", state.tick + 1)), events,
				str(action.get("source_binding_key", "")),str(action.get("pool_mode", "refresh")),str(action.get("pool_id", "")),
				int(action.get("expected_revision", -1)),str(action.get("origin_pool_id", ""))): return
		elif action.get("kind", "") == "barrier_grant":
			var target := _unit_by_key(str(action.get("target_key", "")))
			if target.is_empty(): state.error = "scheduled barrier target无效"; return
			if not bool(target.barrier.active): target.barrier = {"active":true,"source_key":str(action.get("source_key", "")),"source_binding_key":str(action.get("source_binding_key", "")),"expires_tick":int(action.get("expires_tick", state.tick + 1))}
		elif action.get("kind", "") == "status_add":
			var target := _unit_by_key(str(action.get("target_key", "")))
			if target.is_empty(): state.error = "scheduled status target无效"; return
			_add_status(target, action, events)
		elif action.get("kind", "") == "revive":
			var target := _unit_by_key(str(action.get("target_key", "")))
			if target.is_empty(): state.error = "scheduled revive target无效"; return
			_revive(target, int(action.get("amount", -1)), str(action.get("source_key", "")), events)
		elif action.get("kind", "") == "counter_settlement":
			var target := _unit_by_key(str(action.get("target_key", "")))
			var binding_key := str(action.get("source_binding_key", ""))
			var counter_key := str(action.get("counter_key", ""))
			var amount_bp := int(action.get("amount_bp", -1))
			var max_amount := int(action.get("max_amount", -1))
			if target.is_empty() or binding_key.is_empty() or counter_key.is_empty() or amount_bp < 0 or amount_bp > 10000 or max_amount < 0:
				state.error = "counter_settlement参数无效"; return
			var stored := maxi(get_counter(binding_key, counter_key), 0)
			var settled_amount := mini(max_amount, int(floor(float(stored * amount_bp) / 10000.0)))
			if not set_counter(binding_key, counter_key, 0): state.error = "counter_settlement无法清空来源counter"; return
			if settled_amount > 0:
				state.pending_damage.append({"target_key":target.key,"source_key":str(action.get("source_key", "")),
					"source_binding_key":binding_key,"amount":settled_amount,"damage_type":str(action.get("damage_type", "physical")),
					"is_self_loss":str(action.get("damage_type", "physical")) == "self_loss",
					"root_id":_action_root(action),"cause_id":str(action.get("cause_id", "")),
					"extra_generation":int(action.get("extra_generation", 0)),"triggered_bindings":action.get("triggered_bindings", []).duplicate()})
		else:
			state.error = "queue phase=%s 不支持 action kind=%s" % [phase,str(action.get("kind", ""))]


func _process_damage_batches(events: Array) -> void:
	if state.pending_damage.is_empty(): return
	var batch: Array = state.pending_damage.duplicate(true)
	state.pending_damage.clear()
	_resolve_damage_batch(batch, events)


func _run_before_damage_hooks(target: Dictionary, entry: Dictionary, amount: int, events: Array) -> int:
	if amount <= 0: return amount
	var event := _emit("before_damage", str(entry.get("source_key", "")), target.slot, target.side,
		{"root_id":_entry_root(entry),"source_binding_key":str(entry.get("source_binding_key", "")),"raw_amount":amount,
		"amount_before_armor_reduction":amount,"amount_before_shield":amount,"damage_type":str(entry.get("damage_type", "physical")),
		"is_attack":bool(entry.get("is_attack", false)),"is_natural_attack":bool(entry.get("is_natural_attack", false)),
		"is_extra_attack":bool(entry.get("is_extra_attack", false)),"is_attached_damage":bool(entry.get("is_attached_damage", false)),
		"is_redirected":bool(entry.get("_was_redirected", false)),"extra_generation":int(entry.get("extra_generation", 0)),
		"triggered_bindings":entry.get("triggered_bindings", []).duplicate()}, events)
	event.payload.damage_entry_id = event.event_id
	state.active_damage_entry_id = event.event_id
	state.active_damage_available = amount
	state.active_damage_deferred = 0
	state.active_damage_reduction_bp = 0
	_deliver_events(events)
	var deferred := mini(amount, int(state.active_damage_deferred))
	state.damage_reduction_bp = int(state.active_damage_reduction_bp)
	state.active_damage_entry_id = ""
	state.active_damage_available = 0
	state.active_damage_deferred = 0
	state.active_damage_reduction_bp = 0
	return amount - deferred


func _execute_extra_attack(action: Dictionary, events: Array) -> void:
	var attacker := _unit_by_key(str(action.get("attacker_key", action.get("source_key", ""))))
	if attacker.is_empty() or not _is_alive(attacker): return
	var target := _unit_by_key(str(action.get("target_key", "")))
	if target.is_empty() or not _is_alive(target): target = _choose_target(attacker)
	if target.is_empty(): return
	var attack_id := "%s-extra-%08d" % [attacker.key, int(state.event_serial) + 1]
	var root_id := _action_root(action)
	var attack_amount := int(action.get("amount", -1))
	if int(action.get("amount_bp_of_attacker", -1)) >= 0:
		var attacker_amount := maxi(_effective_stat(attacker, "A") * 10 + _modifier_amount(attacker, "A_tenths_flat"), 0)
		attack_amount = int(floor(float(attacker_amount * int(action.amount_bp_of_attacker)) / 10000.0))
	var attack_damage_type := str(effective_stats(attacker.key).get("damage_type", attacker.damage_type)) if bool(action.get("inherit_damage_type", false)) else str(action.get("damage_type", "physical"))
	var context := {"attack_id":attack_id,"root_id":root_id,"source_key":attacker.key,"source_binding_key":str(action.get("source_binding_key", "")),
		"target_key":target.key,"amount":attack_amount,"damage_type":attack_damage_type,
		"segments":[{"amount":int(action.get("amount", -1)),"damage_type":str(action.get("damage_type", "physical")),"armor_piercing":action.get("armor_piercing", 0),"is_attack":true,"is_natural_attack":false}],
		"attached_damage":[],"cause_id":str(action.get("cause_id", "")),
		"extra_generation":int(action.get("extra_generation", 1)),"triggered_bindings":action.get("triggered_bindings", []).duplicate(),
		"consume_on_hit":action.get("consume_on_hit", []).duplicate(true)}
	context.segments = [{"amount":attack_amount,"damage_type":attack_damage_type,"armor_piercing":action.get("armor_piercing", 0),"is_attack":true,"is_natural_attack":false}]
	if attack_amount < 0 or attack_amount > MAX_DAMAGE_TENTHS: state.error = "extra_attack amount无效"; return
	state.pending_attacks[attack_id] = context
	var prepared := _emit("prepare_attack", attacker.key, target.slot, target.side,
		{"root_id":root_id,"cause_id":context.cause_id,"source_binding_key":context.source_binding_key,"triggered_bindings":context.triggered_bindings.duplicate(),
		"attack_id":attack_id,"attack_context":context.duplicate(true),"is_extra_attack":true,"extra_generation":context.extra_generation}, events)
	_deliver_events(events)
	context = state.pending_attacks.get(attack_id, context)
	if bool(context.get("suppressed", false)):
		state.pending_attacks.erase(attack_id)
		return
	target = _unit_by_key(str(context.get("target_key", target.key)))
	if target.is_empty() or not _is_alive(target): state.error = "extra_attack patched target无效"; state.pending_attacks.erase(attack_id); return
	var before := _emit("before_hit", attacker.key, target.slot, target.side,
		{"root_id":root_id,"cause_id":context.cause_id,"source_binding_key":context.source_binding_key,"triggered_bindings":context.triggered_bindings.duplicate(),
		"attack_id":attack_id,"attack_context":context.duplicate(true),"is_extra_attack":true,"extra_generation":context.extra_generation}, events)
	_deliver_events(events)
	context = state.pending_attacks.get(attack_id, context)
	target = _unit_by_key(str(context.get("target_key", target.key)))
	if target.is_empty() or not _is_alive(target): state.error = "extra_attack patched target无效"; state.pending_attacks.erase(attack_id); return
	var segment_index := 0
	for segment in context.get("segments", []):
		segment_index += 1
		var segment_target_key := str(segment.get("target_key", target.key))
		var segment_target := _unit_by_key(segment_target_key)
		if segment_target.is_empty() or not _is_alive(segment_target): state.error = "extra_attack segment target无效"; return
		state.pending_damage.append({"target_key":segment_target.key,"source_key":attacker.key,"source_binding_key":str(context.source_binding_key),
			"amount":int(segment.amount),"damage_type":str(segment.damage_type),"armor_piercing":segment.get("armor_piercing", 0),
			"root_id":root_id if segment_index == 1 else _new_root(),"cause_id":str(context.get("cause_id", "")),
			"triggered_bindings":context.get("triggered_bindings", []).duplicate(),"attack_id":attack_id,"is_attack":true,"is_natural_attack":false,
			"is_extra_attack":true,"extra_generation":int(context.extra_generation),"segment_index":segment_index,"bypass_shield":bool(segment.get("bypass_shield", false)),
			"consume_on_hit":context.get("consume_on_hit", []).duplicate(true)})
	for attached in context.get("attached_damage", []):
		segment_index += 1
		var attached_target := _unit_by_key(str(attached.get("target_key", target.key)))
		if attached_target.is_empty() or not _is_alive(attached_target): state.error = "extra_attack attached target无效"; return
		state.pending_damage.append({"target_key":attached_target.key,"source_key":str(attached.get("source_key", attacker.key)),"source_binding_key":str(attached.get("source_binding_key", context.source_binding_key)),
			"amount":int(attached.get("amount", 0)),"damage_type":str(attached.get("damage_type", "fixed")),"armor_piercing":attached.get("armor_piercing", 0),
			"root_id":root_id,"cause_id":str(context.get("cause_id", "")),"triggered_bindings":context.get("triggered_bindings", []).duplicate(),
			"attack_id":attack_id,"is_attack":false,"is_natural_attack":false,"is_extra_attack":true,
			"extra_generation":int(context.extra_generation),"segment_index":segment_index,"is_attached_damage":true,
			"bypass_shield":bool(attached.get("bypass_shield", false)),"shield_only":bool(attached.get("shield_only", false))})
	state.pending_attacks.erase(attack_id)


func _process_attack_timeline(events: Array) -> void:
	# First complete preparations begun on earlier ticks, then start each next preparation.
	for side in SIDES:
		for attacker in state.teams[side]:
			if not _is_alive(attacker): continue
			var attack_id := str(attacker.get("prepared_attack_id", ""))
			if not attack_id.is_empty() and int(attacker.next_attack_tick) <= int(state.tick):
				var context: Dictionary = state.pending_attacks.get(attack_id, {})
				if bool(context.get("suppressed", false)):
					state.pending_attacks.erase(attack_id)
					attacker.prepared_attack_id = ""
					_begin_attack_prepare(attacker, events)
					continue
				var target := _unit_by_key(str(context.get("target_key", "")))
				if target.is_empty() or not _is_alive(target): target = _choose_target(attacker)
				if target.is_empty(): continue
				if _has_status(attacker, "rooted") and attacker.reach == "melee" and attacker.slot != target.slot: continue
				var before_event := _emit("before_hit", attacker.key, target.slot, target.side,
					{"root_id":context.root_id,"attack_id":attack_id,"attack_context":context.duplicate(true),
					"is_natural_attack":true,"is_attack":false,"extra_generation":0}, events)
				_deliver_events(events)
				context = state.pending_attacks.get(attack_id, context)
				if bool(context.get("suppressed", false)):
					state.pending_attacks.erase(attack_id)
					attacker.prepared_attack_id = ""
					_begin_attack_prepare(attacker, events)
					continue
				var patched_target := _unit_by_key(str(context.get("target_key", target.key)))
				if not patched_target.is_empty() and _is_alive(patched_target): target = patched_target
				var segments: Array = context.get("segments", [])
				var segment_index := 0
				for segment in segments:
					segment_index += 1
					var segment_target := _unit_by_key(str(segment.get("target_key", target.key)))
					if segment_target.is_empty() or not _is_alive(segment_target): state.error = "自然攻击 segment target无效"; return
					state.pending_damage.append({"target_key":segment_target.key,"source_key":attacker.key,"source_binding_key":str(context.get("source_binding_key", "")),
						"amount":int(segment.get("amount", 0)),"damage_type":str(segment.get("damage_type", "physical")),
						"armor_piercing":segment.get("armor_piercing", 0),"root_id":str(context.root_id) if segment_index == 1 else _new_root(),"attack_id":attack_id,
						"is_attack":bool(segment.get("is_attack", true)),"is_natural_attack":bool(segment.get("is_natural_attack", true)),
						"extra_generation":0,"triggered_bindings":context.get("triggered_bindings", []).duplicate(),"cause_id":str(context.get("cause_id", "")),
						"segment_index":segment_index,"is_attached_damage":false,"bypass_shield":bool(segment.get("bypass_shield", false)),
						"consume_on_hit":context.get("consume_on_hit", []).duplicate(true)})
				for attached in context.get("attached_damage", []):
					segment_index += 1
					var attached_target := _unit_by_key(str(attached.get("target_key", target.key)))
					if attached_target.is_empty() or not _is_alive(attached_target): state.error = "自然攻击 attached target无效"; return
					state.pending_damage.append({"target_key":attached_target.key,"source_key":str(attached.get("source_key", attacker.key)),"source_binding_key":str(attached.get("source_binding_key", context.get("source_binding_key", ""))),
						"amount":int(attached.get("amount", 0)),"damage_type":str(attached.get("damage_type", "fixed")),
						"armor_piercing":attached.get("armor_piercing", 0),"root_id":str(context.root_id),"attack_id":attack_id,
					"is_attack":false,"is_natural_attack":false,"extra_generation":0,"triggered_bindings":context.get("triggered_bindings", []).duplicate(),
					"cause_id":str(context.get("cause_id", "")),"segment_index":segment_index,"is_attached_damage":true,
					"bypass_shield":bool(attached.get("bypass_shield", false)),"shield_only":bool(attached.get("shield_only", false))})
				state.pending_attacks.erase(attack_id)
				attacker.prepared_attack_id = ""
				attacker.first_natural_attack_tick = int(state.tick) if attacker.first_natural_attack_tick == null else attacker.first_natural_attack_tick
				state.first_natural_attack_tick[attacker.side] = int(attacker.first_natural_attack_tick)
			if str(attacker.prepared_attack_id).is_empty(): _begin_attack_prepare(attacker, events)


func _begin_attack_prepare(attacker: Dictionary, events: Array) -> void:
	if not _is_alive(attacker): return
	var target := _choose_target(attacker)
	if target.is_empty(): return
	var count := int(attacker.ability_counters.get("natural_attack_count", 0)) + 1
	attacker.ability_counters["natural_attack_count"] = count
	var attack_id := "%s-natural-%06d" % [attacker.key,count]
	var root := _new_root()
	var cross_delay := 4 if attacker.reach == "melee" and not bool(attacker.flying) and attacker.slot != target.slot else 0
	var natural_base_tenths := maxi(_effective_stat(attacker, "A") * 10 + _modifier_amount(attacker, "A_tenths_flat"), 0)
	var natural_amount := int(floor(float(natural_base_tenths * (10000 + _modifier_amount(attacker, "natural_damage_bp"))) / 10000.0))
	var natural_type := str(effective_stats(attacker.key).get("damage_type", attacker.damage_type))
	var context := {"attack_id":attack_id,"root_id":root,"source_key":attacker.key,"source_binding_key":"",
		"target_key":target.key,"amount":natural_amount,"damage_type":natural_type,"armor_piercing":0,
		"segments":[{"amount":natural_amount,"damage_type":natural_type,"armor_piercing":0,"is_attack":true,"is_natural_attack":true}],
		"attached_damage":[],"preparation_delay":cross_delay}
	state.pending_attacks[attack_id] = context
	attacker.prepared_attack_id = attack_id
	var prepare_event := _emit("prepare_attack", attacker.key, target.slot, target.side,
		{"root_id":root,"attack_id":attack_id,"attack_context":context.duplicate(true),
		"is_natural_attack":true,"is_attack":false,"extra_generation":0,"preparation_delay":cross_delay}, events)
	_deliver_events(events)
	context = state.pending_attacks[attack_id]
	cross_delay += int(context.get("preparation_delay_ticks", 0))
	var interval := maxi(6, _modified_attack_interval(attacker, bool(context.get("ignore_slow_for_this_attack", false))))
	interval = maxi(6, int(floor(float(interval * int(context.get("interval_multiplier_bp", 10000))) / 10000.0)))
	attacker.next_attack_tick = int(state.tick) + interval + maxi(0, cross_delay)


func _modified_attack_interval(unit_state: Dictionary, ignore_slow: bool = false) -> int:
	var positive_slow_bp := 0
	for status in unit_state.statuses:
		if status.id == "chill" and not ignore_slow: positive_slow_bp = maxi(positive_slow_bp, 2500)
	var negative_haste_bp := 0
	var all_modifiers: Array = unit_state.modifiers.duplicate(true)
	all_modifiers.append_array(unit_state.get("setup_modifiers", []))
	for modifier in all_modifiers:
		if str(modifier.get("stat", "")) != "T_ticks_percent": continue
		var modifier_bp := int(modifier.get("amount", 0))
		if modifier_bp > 0 and not ignore_slow: positive_slow_bp = maxi(positive_slow_bp, modifier_bp)
		elif modifier_bp < 0: negative_haste_bp += modifier_bp
	var flat_ticks := 0
	for modifier in unit_state.modifiers:
		if str(modifier.get("stat", "")) == "T_ticks_flat": flat_ticks += int(modifier.get("amount", 0))
	var base_ticks := maxi(int(unit_state.T_ticks) + flat_ticks, 0)
	var net_bp := positive_slow_bp + negative_haste_bp
	var scaled := base_ticks * maxi(0, 10000 + net_bp)
	return maxi(6, int(ceil(float(scaled) / 10000.0)))


func _choose_target(attacker: Dictionary) -> Dictionary:
	var enemy_side := "B" if attacker.side == "A" else "A"
	var preferred := int(attacker.target_slot)
	if preferred >= 1 and preferred <= 3 and _is_alive(state.teams[enemy_side][preferred - 1]): return state.teams[enemy_side][preferred - 1]
	for slot in [2, 1, 3]:
		if _is_alive(state.teams[enemy_side][slot - 1]): return state.teams[enemy_side][slot - 1]
	return {}


func _process_periodic(events: Array) -> void:
	for side in SIDES:
		for target in state.teams[side]:
			if not _is_alive(target): continue
			for status in target.statuses:
				if str(status.id) not in ["burn", "bleed", "poison"]: continue
				if int(status.next_tick) != int(state.tick): continue
				var total_modifier_bp := 0
				for modifier in state.status_tick_modifiers:
					if str(modifier.status_id) == str(status.id): total_modifier_bp += int(modifier.amount_bp)
				var amount := int(floor(float(int(status.layers) * 10 * maxi(0, 10000 + total_modifier_bp)) / 10000.0))
				var type := "fire" if status.id == "burn" else "physical" if status.id == "bleed" else "poison"
				if amount > 0:
					state.pending_damage.append({"target_key":target.key,"source_key":status.source_key,"source_binding_key":str(status.get("source_binding_key", "")),"amount":amount,"damage_type":type,
						"root_id":_new_root(),"is_periodic":true,"segment_index":int(status.get("instance_id", 0))})
				status.next_tick += 10


func _process_expiries(events: Array, allow_dot_endpoint_cleanup: bool = false) -> void:
	for side in SIDES:
		for target in state.teams[side]:
			if bool(target.barrier.active) and int(target.barrier.expires_tick) <= int(state.tick):
				_emit("expiry", str(target.barrier.source_key), target.slot, target.side, {"kind":"barrier","source_binding_key":str(target.barrier.get("source_binding_key", ""))}, events)
				target.barrier = {"active":false,"source_key":"","expires_tick":-1}
			for i in range(target.shield_pools.size() - 1, -1, -1):
				if int(target.shield_pools[i].expires_tick) <= int(state.tick):
					var expired_pool: Dictionary = target.shield_pools[i]
					_emit("expiry", str(expired_pool.source_key), target.slot, target.side, {"kind":"shield","source_binding_key":str(expired_pool.get("source_binding_key", "")),"amount":int(expired_pool.amount)}, events)
					target.shield_pools.remove_at(i)
			var expired_cycles: Dictionary = {}
			for i in range(target.statuses.size() - 1, -1, -1):
				var status_id := str(target.statuses[i].id)
				var dot_endpoint := status_id in ["burn", "bleed", "poison"] and int(target.statuses[i].expires_tick) == int(state.tick)
				if int(target.statuses[i].expires_tick) >= 0 and int(target.statuses[i].expires_tick) <= int(state.tick) and (not dot_endpoint or allow_dot_endpoint_cleanup):
					var expired: Dictionary = target.statuses[i]
					target.statuses.remove_at(i)
					var cycle := str(expired.get("status_cycle_id", expired.get("status_instance_id", 0)))
					if not expired_cycles.has(cycle): expired_cycles[cycle] = expired
			for cycle in expired_cycles:
				var expired: Dictionary = expired_cycles[cycle]
				_emit("expiry", expired.source_key, target.slot, target.side, {"status_id":expired.id,"status_instance_id":expired.status_instance_id,
					"status_cycle_id":int(expired.get("status_cycle_id", expired.status_instance_id)),"source_binding_key":str(expired.get("source_binding_key", ""))}, events)
			for i in range(target.modifiers.size() - 1, -1, -1):
				if int(target.modifiers[i].get("expires_tick", -1)) >= 0 and int(target.modifiers[i].expires_tick) <= int(state.tick):
					var expired_modifier: Dictionary = target.modifiers[i]
					target.modifiers.remove_at(i)
					_emit("expiry", str(expired_modifier.get("source_key", "")), target.slot, target.side, {"kind":"modifier","modifier_id":str(expired_modifier.get("modifier_id", "")),"source_binding_key":str(expired_modifier.get("source_binding_key", ""))}, events)
					_clamp_current_hp_to_max(target)
	for i in range(state.status_tick_modifiers.size() - 1, -1, -1):
		var tick_modifier: Dictionary = state.status_tick_modifiers[i]
		if int(tick_modifier.get("expires_tick", -1)) >= 0 and int(tick_modifier.expires_tick) <= int(state.tick):
			_emit("expiry", "", -1, "", {"kind":"status_tick_modifier","status_id":str(tick_modifier.status_id),
				"source_binding_key":str(tick_modifier.source_binding_key)}, events)
			state.status_tick_modifiers.remove_at(i)


func _resolve_damage_batch(entries: Array, events: Array) -> bool:
	if entries.is_empty(): return true
	var stable: Array = []
	for raw_entry in entries:
		if not raw_entry is Dictionary: state.error = "damage entry必须为Dictionary"; return false
		var target := _unit_by_key(str(raw_entry.get("target_key", "")))
		var amount := int(raw_entry.get("amount", -1))
		if target.is_empty() or amount < 0 or amount > MAX_DAMAGE_TENTHS:
			state.error = "damage entry target/amount无效"; return false
		if amount == 0 or not _is_alive(target): continue
		stable.append(raw_entry.duplicate(true))
	stable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a.target_key) != str(b.target_key): return str(a.target_key) < str(b.target_key)
		var a_source := str(a.get("source_key", "")); var b_source := str(b.get("source_key", ""))
		var a_slot := a_source.substr(1).to_int() if a_source.length() > 1 else 99
		var b_slot := b_source.substr(1).to_int() if b_source.length() > 1 else 99
		if a_slot != b_slot: return a_slot < b_slot
		if a_source.substr(0, 1) != b_source.substr(0, 1): return a_source.substr(0, 1) < b_source.substr(0, 1)
		var a_extra := bool(a.get("is_extra_attack", false)); var b_extra := bool(b.get("is_extra_attack", false))
		if a_extra != b_extra: return not a_extra
		return int(a.get("segment_index", 0)) < int(b.get("segment_index", 0)))
	var packets: Array = []
	for entry in stable:
		var target := _unit_by_key(str(entry.target_key))
		var original := int(entry.amount)
		var type := str(entry.get("damage_type", "physical"))
		var amount := original
		var barrier_absorbed := 0
		var barrier_source_key := ""
		var barrier_source_binding_key := ""
		var self_loss := bool(entry.get("is_self_loss", false))
		if not self_loss and not bool(entry.get("enter_shield_step", false)) and bool(target.barrier.active) and amount > 0:
			barrier_source_key = str(target.barrier.get("source_key", ""))
			barrier_source_binding_key = str(target.barrier.get("source_binding_key", ""))
			barrier_absorbed = amount
			target.barrier = {"active":false,"source_key":"","expires_tick":-1}
			amount = 0
		var armor_blocked := 0
		if amount > 0 and type == "physical" and not self_loss and not bool(entry.get("skip_armor_and_reduction", false)) and not bool(entry.get("enter_shield_step", false)):
			var piercing_value = entry.get("armor_piercing", 0)
			var ignored_armor := _effective_armor(target) if piercing_value is bool and piercing_value else int(piercing_value) if piercing_value is int else 0
			ignored_armor = mini(ignored_armor, _effective_armor(target))
			armor_blocked = mini(maxi(amount - 10, 0), maxi(_effective_armor(target) - ignored_armor, 0) * 10)
			amount -= armor_blocked
		var hook_reduction_bp := 0
		if amount > 0 and not self_loss and not bool(entry.get("skip_armor_and_reduction", false)) and not bool(entry.get("enter_shield_step", false)):
			amount = _run_before_damage_hooks(target, entry, amount, events)
			hook_reduction_bp = int(state.damage_reduction_bp)
			state.damage_reduction_bp = 0
		var reduction_bp := mini(_effective_reduction_bp(target) + hook_reduction_bp, 7500)
		var reduction := int(floor(float(amount * reduction_bp) / 10000.0)) if not self_loss and not bool(entry.get("skip_armor_and_reduction", false)) and not bool(entry.get("enter_shield_step", false)) else 0
		amount -= reduction
		var transferred := 0
		if not self_loss and amount > 0 and not bool(entry.get("enter_shield_step", false)) and not bool(entry.get("shield_only", false)):
			var redirect_result := _calculate_transfers(target, amount, entry)
			transferred = int(redirect_result.amount)
			for portion in redirect_result.portions:
				var receiver := _unit_by_key(str(portion.target_key))
				var moved := int(portion.amount)
				var receiver_barrier := 0
				var receiver_barrier_source_key := ""
				var receiver_barrier_binding_key := ""
				if bool(receiver.barrier.active) and moved > 0:
					receiver_barrier_source_key = str(receiver.barrier.get("source_key", ""))
					receiver_barrier_binding_key = str(receiver.barrier.get("source_binding_key", ""))
					receiver_barrier = moved
					receiver.barrier = {"active":false,"source_key":"","expires_tick":-1}
					moved = 0
				var receiver_prior_shields: Array = receiver.shield_pools.duplicate(true)
				var receiver_shield_log: Array = []
				var receiver_shield := _consume_shields(receiver, moved, events, false, "", receiver_shield_log) if moved > 0 and not bool(entry.get("bypass_shield", false)) else 0
				moved -= receiver_shield
				var receiver_broke_shield: bool = receiver_shield > 0 and receiver_prior_shields.size() > 0 and receiver.shield_pools.is_empty()
				var receiver_broken_pool: Dictionary = receiver_prior_shields.back().duplicate(true) if receiver_broke_shield else {}
				packets.append({"entry":entry,"target_key":receiver.key,"source_key":str(entry.get("source_key", "")),
					"source_binding_key":str(entry.get("source_binding_key", "")),"original":int(portion.amount),
					"armor_blocked":0,"reduction":0,"transferred":int(portion.amount),"shield_absorbed":receiver_shield,
					"barrier_absorbed":receiver_barrier,"barrier_source_key":receiver_barrier_source_key,
					"barrier_source_binding_key":receiver_barrier_binding_key,"remaining_damage":moved,"damage_type":type,"is_transfer":true,
					"shield_broke":receiver_broke_shield,"broken_pool":receiver_broken_pool,"shield_log":receiver_shield_log})
			amount -= transferred
		var shield_absorbed := 0
		var shield_broke := false
		var broken_pool: Dictionary = {}
		var shield_log: Array = []
		if amount > 0 and not self_loss and not bool(entry.get("bypass_shield", false)):
			var prior_shields: Array = target.shield_pools.duplicate(true)
			shield_absorbed = _consume_shields(target, amount, events, false, "", shield_log)
			shield_broke = shield_absorbed > 0 and prior_shields.size() > 0 and target.shield_pools.is_empty()
			if shield_broke: broken_pool = prior_shields.back().duplicate(true)
			amount -= shield_absorbed
		if bool(entry.get("shield_only", false)):
			amount = 0
		packets.append({"entry":entry,"target_key":target.key,"source_key":str(entry.get("source_key", "")),
			"source_binding_key":str(entry.get("source_binding_key", "")),"original":original,"armor_blocked":armor_blocked,
			"reduction":reduction,"transferred":transferred,"shield_absorbed":shield_absorbed,
			"barrier_source_key":barrier_source_key,"barrier_source_binding_key":barrier_source_binding_key,
			"barrier_absorbed":barrier_absorbed,"remaining_damage":amount,"damage_type":type,"shield_only":bool(entry.get("shield_only", false)),"is_transfer":false,
			"shield_after_tenths":_shield_total(target),"shield_broke":shield_broke,"broken_pool":broken_pool,"shield_log":shield_log})
	# Allocate each target's remaining HP across every simultaneous packet before emitting any loss.
	var by_target: Dictionary = {}
	for packet in packets:
		if not by_target.has(packet.target_key): by_target[packet.target_key] = []
		by_target[packet.target_key].append(packet)
	for target_key in by_target:
		var target := _unit_by_key(str(target_key))
		var group: Array = by_target[target_key]
		var weights: Array[int] = []
		var sum_damage := 0
		for packet in group:
			var weight := int(packet.remaining_damage)
			weights.append(weight)
			sum_damage += weight
		var budget := mini(maxi(int(target.hp_tenths), 0), sum_damage)
		var batch_hp_before := int(target.hp_tenths)
		var allocations := _allocate_simultaneous(weights, budget)
		var total_loss := 0
		for i in range(group.size()):
			group[i]["actual_hp_loss"] = allocations[i]
			group[i]["overkill"] = maxi(weights[i] - allocations[i], 0)
			total_loss += allocations[i]
		target.hp_tenths -= total_loss
		for packet in group:
			packet["batch_hp_before_tenths"] = batch_hp_before
			packet["batch_hp_after_tenths"] = int(target.hp_tenths)
		if target.hp_tenths <= 0:
			target.hp_tenths = 0
			target.dead = true
			target.pending_final = true
	var notifications: Array = []
	for packet in packets:
		var entry: Dictionary = packet.entry
		var target := _unit_by_key(str(packet.target_key))
		var payload: Dictionary = packet.duplicate(true)
		payload["root_id"] = _entry_root(entry)
		payload["cause_id"] = str(entry.get("cause_id", ""))
		payload["raw_amount"] = int(packet.original)
		payload["attack_id"] = str(entry.get("attack_id", ""))
		payload["batch_hp_before_tenths"] = int(packet.get("batch_hp_before_tenths", target.hp_tenths))
		payload["batch_hp_after_tenths"] = int(packet.get("batch_hp_after_tenths", target.hp_tenths))
		payload["is_natural_attack"] = bool(entry.get("is_natural_attack", false))
		payload["is_extra_attack"] = bool(entry.get("is_extra_attack", false))
		payload["is_attack"] = bool(entry.get("is_attack", false)) or bool(entry.get("is_natural_attack", false)) or bool(entry.get("is_extra_attack", false))
		payload["is_redirected"] = bool(packet.get("is_transfer", false))
		payload["is_attached_damage"] = bool(entry.get("is_attached_damage", false))
		payload["is_direct_attack"] = bool(payload.is_attack) and not bool(payload.is_redirected) and not bool(payload.is_attached_damage)
		if bool(packet.get("is_transfer", false)):
			payload["is_attack"] = false
			payload["is_natural_attack"] = false
			payload["is_extra_attack"] = false
			payload["is_direct_attack"] = false
		payload["extra_generation"] = int(entry.get("extra_generation", 0))
		payload["triggered_bindings"] = entry.get("triggered_bindings", []).duplicate()
		if bool(entry.get("is_natural_attack", false)) and not bool(entry.get("is_extra_attack", false)):
			var attacker := _unit_by_key(str(entry.get("source_key", "")))
			if not attacker.is_empty() and attacker.first_natural_attack_tick == null:
				attacker.first_natural_attack_tick = int(state.tick)
				state.first_natural_attack_tick[attacker.side] = int(state.tick)
		notifications.append({"packet":packet,"entry":entry,"target":target,"payload":payload})
	# Damage state is fully committed above. Fan out by event phase, not packet, so
	# all attack reactions observe the same post-batch HP/shield snapshot first.
	for notification in notifications:
		var packet: Dictionary = notification.packet
		var target: Dictionary = notification.target
		var payload: Dictionary = notification.payload
		if bool(payload.is_attack) and not bool(packet.get("is_transfer", false)):
			_emit("hit", str(packet.source_key), target.slot, target.side, payload, events)
	var consumed_attack_ids: Dictionary = {}
	for notification in notifications:
		var packet: Dictionary = notification.packet
		var entry: Dictionary = notification.entry
		if not bool(notification.payload.get("is_attack", false)) or bool(packet.get("is_transfer", false)): continue
		var attack_id := str(entry.get("attack_id", ""))
		if attack_id.is_empty() or consumed_attack_ids.has(attack_id): continue
		consumed_attack_ids[attack_id] = true
		for consume_spec in entry.get("consume_on_hit", []):
			var binding_key := str(consume_spec.get("source_binding_key", ""))
			var counter_key := str(consume_spec.get("counter_key", ""))
			var current := get_counter(binding_key, counter_key)
			if not set_counter(binding_key, counter_key, maxi(current - int(consume_spec.get("amount", 1)), 0)):
				state.error = "attack consume_on_hit counter无效"; return false
	for notification in notifications:
		var packet: Dictionary = notification.packet
		var target: Dictionary = notification.target
		var payload: Dictionary = notification.payload
		if int(packet.actual_hp_loss) > 0: _emit("hp_lost", str(packet.source_key), target.slot, target.side, payload, events)
	for notification in notifications:
		var packet: Dictionary = notification.packet
		if int(packet.get("barrier_absorbed", 0)) <= 0: continue
		var target: Dictionary = notification.target
		var payload: Dictionary = notification.payload.duplicate(true)
		payload["barrier_source_key"] = str(packet.get("barrier_source_key", ""))
		payload["barrier_source_binding_key"] = str(packet.get("barrier_source_binding_key", ""))
		_emit("barrier_absorbed", str(packet.source_key), target.slot, target.side, payload, events)
	var shield_absorptions: Array = []
	var shield_absorption_indexes: Dictionary = {}
	for notification in notifications:
		var packet: Dictionary = notification.packet
		var entry: Dictionary = notification.entry
		var target: Dictionary = notification.target
		var damage_source_key := str(entry.get("source_key", ""))
		var root_id := _entry_root(entry)
		var damage_source := _unit_by_key(damage_source_key)
		for shield_part in packet.get("shield_log", []):
			var shield_source_key := str(shield_part.get("source_key", ""))
			var shield_binding_key := str(shield_part.get("source_binding_key", ""))
			var aggregate_key := "%s|%s|%s|%s|%s" % [root_id,target.key,shield_source_key,shield_binding_key,damage_source_key]
			if shield_absorption_indexes.has(aggregate_key):
				var current_index := int(shield_absorption_indexes[aggregate_key])
				shield_absorptions[current_index].amount += int(shield_part.amount)
			else:
				shield_absorption_indexes[aggregate_key] = shield_absorptions.size()
				shield_absorptions.append({"target_key":target.key,"source_key":shield_source_key,"source_binding_key":shield_binding_key,
					"damage_source_unit":damage_source_key,"is_enemy_damage":not damage_source.is_empty() and damage_source.side != target.side,
					"root_id":root_id,"amount":int(shield_part.amount)})
	for absorption in shield_absorptions:
		var target := _unit_by_key(str(absorption.target_key))
		var amount := int(absorption.amount)
		_emit("shield_absorbed", str(absorption.source_key), target.slot, target.side,
			{"root_id":str(absorption.root_id),"source_binding_key":str(absorption.source_binding_key),
			"damage_source_unit":str(absorption.damage_source_unit),"is_enemy_damage":bool(absorption.is_enemy_damage),
			"amount":amount,"absorbed_shield":amount,"raw_amount":amount,"reason":"damage"}, events)
	for notification in notifications:
		var packet: Dictionary = notification.packet
		var entry: Dictionary = notification.entry
		var target: Dictionary = notification.target
		if bool(packet.get("shield_broke", false)):
			var broken: Dictionary = packet.get("broken_pool", {})
			var damage_source := _unit_by_key(str(entry.get("source_key", "")))
			_emit("shield_broken", str(broken.get("source_key", "")), target.slot, target.side,
				{"reason":"damage","source_binding_key":str(broken.get("source_binding_key", "")),"absorbed_shield":int(packet.shield_absorbed),
				"damage_source_unit":str(entry.get("source_key", "")),"is_enemy_damage":not damage_source.is_empty() and damage_source.side != target.side}, events)
	var attack_results: Dictionary = {}
	for notification in notifications:
		var packet: Dictionary = notification.packet
		var entry: Dictionary = notification.entry
		var attack_id := str(entry.get("attack_id", ""))
		if attack_id.is_empty() or not (bool(entry.get("is_natural_attack", false)) or bool(entry.get("is_extra_attack", false)) or bool(entry.get("is_attached_damage", false))): continue
		if not attack_results.has(attack_id):
			attack_results[attack_id] = {"attack_id":attack_id,"root_id":_entry_root(entry),"source_key":str(entry.get("source_key", "")),
				"source_binding_key":str(entry.get("source_binding_key", "")),"cause_id":str(entry.get("cause_id", "")),
				"is_natural_attack":bool(entry.get("is_natural_attack", false)),"is_extra_attack":bool(entry.get("is_extra_attack", false)),
				"extra_generation":int(entry.get("extra_generation", 0)),"triggered_bindings":entry.get("triggered_bindings", []).duplicate(),
				"segment_keys":{},"targets":{},"total_actual_hp_loss":0,"total_shield_absorbed":0,"total_barrier_absorbed":0,"total_transferred":0}
		var result: Dictionary = attack_results[attack_id]
		var segment_key := str(entry.get("segment_index", 0))
		result.segment_keys[segment_key] = true
		var target_key := str(packet.target_key)
		if not result.targets.has(target_key):
			result.targets[target_key] = {"target_key":target_key,"actual_hp_loss":0,"shield_absorbed":0,"barrier_absorbed":0,"transferred":0,"redirected":false}
		var target_result: Dictionary = result.targets[target_key]
		target_result.actual_hp_loss += int(packet.get("actual_hp_loss", 0))
		target_result.shield_absorbed += int(packet.get("shield_absorbed", 0))
		target_result.barrier_absorbed += int(packet.get("barrier_absorbed", 0))
		target_result.transferred += int(packet.get("transferred", 0))
		target_result.redirected = bool(target_result.redirected) or bool(packet.get("is_transfer", false))
		result.total_actual_hp_loss += int(packet.get("actual_hp_loss", 0))
		result.total_shield_absorbed += int(packet.get("shield_absorbed", 0))
		result.total_barrier_absorbed += int(packet.get("barrier_absorbed", 0))
		result.total_transferred += int(packet.get("transferred", 0)) if not bool(packet.get("is_transfer", false)) else 0
	var attack_ids: Array = attack_results.keys()
	attack_ids.sort()
	for attack_id in attack_ids:
		var result: Dictionary = attack_results[attack_id]
		var target_keys: Array = result.targets.keys(); target_keys.sort()
		var target_results: Array = []
		var actual_target_count := 0
		for target_key in target_keys:
			var target_result: Dictionary = result.targets[target_key]
			if int(target_result.actual_hp_loss) > 0: actual_target_count += 1
			target_results.append(target_result)
		_emit("attack_resolved", str(result.source_key), -1, "", {"attack_id":str(result.attack_id),"root_id":str(result.root_id),
			"cause_id":str(result.cause_id),"source_binding_key":str(result.source_binding_key),
			"is_natural_attack":bool(result.is_natural_attack),"is_extra_attack":bool(result.is_extra_attack),
			"extra_generation":int(result.extra_generation),"triggered_bindings":result.triggered_bindings.duplicate(),
			"segment_count":result.segment_keys.size(),"target_keys":target_keys,"targets":target_results,"actual_target_count":actual_target_count,
			"total_actual_hp_loss":int(result.total_actual_hp_loss),"total_shield_absorbed":int(result.total_shield_absorbed),
			"total_barrier_absorbed":int(result.total_barrier_absorbed),"total_transferred":int(result.total_transferred)}, events)
	return true


func _allocate_simultaneous(weights: Array[int], budget: int) -> Array[int]:
	var allocations: Array[int] = []
	var total := 0
	for weight in weights: total += weight
	if budget <= 0 or total <= 0:
		for _weight in weights: allocations.append(0)
		return allocations
	if budget >= total: return weights.duplicate()
	var remainders: Array[int] = []
	for weight in weights:
		var numerator := weight * budget
		allocations.append(int(floor(float(numerator) / total)))
		remainders.append(numerator % total)
	var assigned := 0
	for value in allocations: assigned += value
	var left := budget - assigned
	var order: Array[int] = []
	for i in range(weights.size()): order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if remainders[a] != remainders[b]: return remainders[a] > remainders[b]
		return a < b)
	for i in range(mini(left, order.size())): allocations[order[i]] += 1
	return allocations


func _binding_owner_order(source_binding_key: String) -> int:
	if source_binding_key.length() < 2: return 999
	var owner := _unit_by_key(source_binding_key.substr(0, 2))
	if owner.is_empty(): return 999
	return (0 if str(owner.side) == "A" else 10) + int(owner.slot)


func _calculate_transfers(target: Dictionary, amount: int, entry: Dictionary) -> Dictionary:
	var requests: Array = []
	var total_bp := 0
	for redirect in target.redirects:
		var filters: Dictionary = redirect.get("filters", {})
		if not str(filters.get("source_key", "")).is_empty() and str(filters.source_key) != str(entry.get("source_key", "")): continue
		if redirect.filters.get("damage_type", "") != "" and str(redirect.filters.damage_type) != str(entry.get("damage_type", "")): continue
		var filter_owner := _unit_by_key(str(filters.get("owner_key", "")))
		if not filter_owner.is_empty():
			if not _is_alive(filter_owner): continue
			if filters.has("owner_target_slot") and int(filter_owner.target_slot) != int(filters.owner_target_slot): continue
		var filtered_source := _unit_by_key(str(filters.get("source_key", "")))
		if not filtered_source.is_empty() and not _is_alive(filtered_source): continue
		var requested := int(floor(float(amount * int(redirect.ratio_bp)) / 10000.0))
		if requested <= 0: continue
		total_bp += int(redirect.ratio_bp)
		requests.append({"redirect":redirect,"requested":requested})
	var scale_bp := 10000 if total_bp <= MAX_TRANSFER_RATIO else int(floor(float(MAX_TRANSFER_RATIO * 10000) / total_bp))
	var desired: Array = []
	var sum_amount := 0
	for request in requests:
		var adjusted := int(floor(float(request.requested * scale_bp) / 10000.0))
		var recipient_keys: Array = request.redirect.recipient_keys.duplicate()
		recipient_keys.sort()
		var eligible: Array = []
		for candidate_key in recipient_keys:
			var candidate := _unit_by_key(str(candidate_key))
			if not candidate.is_empty() and _is_alive(candidate) and candidate.key != target.key: eligible.append(str(candidate_key))
		if eligible.is_empty(): continue
		var each := int(floor(float(adjusted) / eligible.size()))
		var remainder := adjusted - each * eligible.size()
		var root_cap_key := "%s@%s" % [str(request.redirect.get("redirect_id", request.redirect.get("source_binding_key", request.redirect.source_key))),_entry_root(entry)]
		var root_capacity := int(request.redirect.get("capacity_per_root", MAX_DAMAGE_TENTHS))
		var root_used := int(state.root_redirect_capacity_used.get(root_cap_key, 0))
		for recipient_index in range(eligible.size()):
			var recipient_key: String = eligible[recipient_index]
			var recipient := _unit_by_key(str(recipient_key))
			var cap_owner := str(request.redirect.get("source_binding_key", request.redirect.source_key))
			var key := "%s@%s@%d" % [cap_owner,recipient.key,int(state.tick) / 10]
			var capacity := int(request.redirect.capacity_per_second)
			var used := int(state.redirect_capacity_used.get(key, 0))
			var remaining := maxi(capacity - used, 0)
			var portion := mini(each + (1 if recipient_index < remainder else 0), remaining)
			portion = mini(portion, maxi(root_capacity - root_used, 0))
			if portion > 0:
				desired.append({"target_key":recipient.key,"amount":portion,"redirect_key":request.redirect.source_key,"capacity_key":key})
				sum_amount += portion
				state.redirect_capacity_used[key] = used + portion
				root_used += portion
				state.root_redirect_capacity_used[root_cap_key] = root_used
	return {"amount":sum_amount,"portions":desired}


func _effective_armor(target: Dictionary) -> int:
	var armor := int(target.R)
	for modifier in target.modifiers:
		if str(modifier.get("stat", "")) == "R_flat": armor += int(modifier.get("amount", 0))
	return maxi(armor, 0)


func _effective_reduction_bp(target: Dictionary) -> int:
	var reduction := 0
	for modifier in target.modifiers:
		if str(modifier.get("stat", "")) == "damage_reduction_bp": reduction += int(modifier.get("amount", 0))
	return clampi(reduction, 0, 7500)


func _apply_heal(target: Dictionary, amount: int, source_key: String, events: Array, root_id: String, source_binding_key: String = "") -> void:
	if amount < 0:
		state.error = "治疗量不得为负数"; return
	if not _is_alive(target) or _has_status(target, "anti_heal"):
		_emit("healed", source_key, target.slot, target.side, {"root_id":root_id,"source_binding_key":source_binding_key,"requested_healing":amount,"actual_healing":0,"overheal":0,"blocked":true,"healing_reductions":[]}, events)
		return
	var healing_reductions: Array = []
	var total_reduction_bp := 0
	var active_reducers: Array = []
	for modifier in target.modifiers:
		if str(modifier.get("stat", "")) != "healing_reduction_bp": continue
		var reduction_bp := maxi(int(modifier.get("amount", 0)), 0)
		if reduction_bp <= 0: continue
		total_reduction_bp += reduction_bp
		active_reducers.append(modifier.duplicate(true))
	active_reducers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key := str(a.get("source_binding_key", "")); var b_key := str(b.get("source_binding_key", ""))
		var a_order := _binding_owner_order(a_key); var b_order := _binding_owner_order(b_key)
		return a_order < b_order if a_order != b_order else a_key < b_key)
	var prevented := mini(amount, int(floor(float(amount * mini(total_reduction_bp, 10000)) / 10000.0)))
	var reduction_weights: Array[int] = []
	for modifier in active_reducers: reduction_weights.append(maxi(int(modifier.amount), 0))
	var reduction_shares := _allocate_simultaneous(reduction_weights, prevented)
	for i in range(active_reducers.size()):
		healing_reductions.append({"source_key":str(active_reducers[i].get("source_key", "")),
			"source_binding_key":str(active_reducers[i].get("source_binding_key", "")),"amount":reduction_shares[i]})
	var effective_amount := amount - prevented
	var before := int(target.hp_tenths)
	var gained := mini(effective_amount, _effective_max_hp_tenths(target) - before)
	var overflow := maxi(effective_amount - maxi(gained, 0), 0)
	if gained <= 0:
		_emit("healed", source_key, target.slot, target.side, {"root_id":root_id,"source_binding_key":source_binding_key,"requested_healing":amount,"actual_healing":0,"overheal":overflow,"healing_reductions":healing_reductions}, events)
		return
	target.hp_tenths += gained
	_emit("healed", source_key, target.slot, target.side, {"root_id":root_id,"source_binding_key":source_binding_key,"requested_healing":amount,"actual_healing":gained,"overheal":overflow,"healing_reductions":healing_reductions}, events)


func _grant_shield(target: Dictionary, source_key: String, amount: int, expires_tick: int, events: Array, source_binding_key: String = "",
		pool_mode: String = "refresh", pool_id: String = "", expected_revision: int = -1, origin_pool_id: String = "") -> bool:
	if amount < 0 or expires_tick < int(state.tick) or pool_mode not in ["refresh", "new", "add"]:
		state.error = "护盾数量/期限/池模式无效"; return false
	var found := -1
	if pool_mode == "add":
		for i in range(target.shield_pools.size()):
			var candidate: Dictionary = target.shield_pools[i]
			if str(candidate.get("pool_id", "")) == pool_id and int(candidate.get("revision", 0)) == expected_revision:
				found = i; break
		if found < 0: return true # A stale delayed refill is cancelled, not an error.
		var existing: Dictionary = target.shield_pools[found]
		if int(existing.expires_tick) <= int(state.tick): return true
		existing.amount = int(existing.amount) + amount
		existing.revision = int(existing.get("revision", 0)) + 1
		existing.origin_pool_id = str(existing.get("origin_pool_id", pool_id))
		pool_id = str(existing.pool_id)
		expires_tick = int(existing.expires_tick)
	elif pool_mode == "refresh":
		for i in range(target.shield_pools.size()):
			if str(target.shield_pools[i].source_key) == source_key and str(target.shield_pools[i].get("source_binding_key", "")) == source_binding_key:
				found = i; break
	var positive_delta := amount
	if pool_mode == "refresh" and found >= 0:
		var previous: Dictionary = target.shield_pools[found]
		positive_delta = maxi(amount - int(previous.amount), 0)
		pool_id = str(previous.get("pool_id", ""))
		if pool_id.is_empty(): pool_id = _new_shield_pool_id()
		target.shield_pools[found] = {"pool_id":pool_id,"origin_pool_id":str(previous.get("origin_pool_id", pool_id)),
			"revision":int(previous.get("revision", 0)) + 1,"source_key":source_key,"source_binding_key":source_binding_key,
			"amount":amount,"expires_tick":expires_tick}
	elif pool_mode != "add":
		if pool_id.is_empty(): pool_id = _new_shield_pool_id()
		target.shield_pools.append({"pool_id":pool_id,"origin_pool_id":origin_pool_id if not origin_pool_id.is_empty() else pool_id,
			"revision":1,"source_key":source_key,"source_binding_key":source_binding_key,"amount":amount,"expires_tick":expires_tick})
	target.shield_pools.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.expires_tick) != int(b.expires_tick): return int(a.expires_tick) < int(b.expires_tick)
		var a_slot := str(a.source_key).substr(1).to_int() if str(a.source_key).length() > 1 else 99
		var b_slot := str(b.source_key).substr(1).to_int() if str(b.source_key).length() > 1 else 99
		if a_slot != b_slot: return a_slot < b_slot
		if str(a.get("source_binding_key", "")) != str(b.get("source_binding_key", "")):
			return str(a.get("source_binding_key", "")) < str(b.get("source_binding_key", ""))
		return str(a.get("pool_id", "")) < str(b.get("pool_id", "")))
	if positive_delta > 0:
		var result_pool: Dictionary = {}
		for pool in target.shield_pools:
			if str(pool.get("pool_id", "")) == pool_id: result_pool = pool; break
		_emit("shield_gained", source_key, target.slot, target.side,
			{"amount":positive_delta,"source_binding_key":source_binding_key,"pool_amount":int(result_pool.get("amount", amount)),
			"pool_id":pool_id,"pool_revision":int(result_pool.get("revision", 1)),"expires_tick":int(result_pool.get("expires_tick", expires_tick)),
			"origin_pool_id":str(result_pool.get("origin_pool_id", pool_id)),"pool_mode":pool_mode}, events)
	return true


func _new_shield_pool_id() -> String:
	state.shield_pool_serial = int(state.get("shield_pool_serial", 0)) + 1
	return "shield-pool-%08d" % int(state.shield_pool_serial)


func _consume_shields(target: Dictionary, amount: int, events: Array, emit_break: bool = true, source_binding_filter: String = "", consumption_log: Array = []) -> int:
	if amount < 0: state.error = "护盾消耗量不得为负数"; return 0
	var initial := amount
	var i := 0
	while amount > 0 and i < target.shield_pools.size():
		var pool: Dictionary = target.shield_pools[i]
		if not source_binding_filter.is_empty() and str(pool.get("source_binding_key", "")) != source_binding_filter:
			i += 1
			continue
		var used := mini(amount, int(pool.amount))
		if used > 0: consumption_log.append({"source_key":str(pool.source_key),"source_binding_key":str(pool.get("source_binding_key", "")),"amount":used})
		pool.amount -= used
		amount -= used
		if int(pool.amount) <= 0: target.shield_pools.remove_at(i)
		else: i += 1
	var absorbed := initial - amount
	if emit_break and absorbed > 0 and target.shield_pools.is_empty():
		_emit("shield_broken", "", target.slot, target.side, {"absorbed_shield":absorbed,"reason":"consume"}, events)
	return absorbed


func _shield_total(target: Dictionary) -> int:
	var total := 0
	for pool in target.get("shield_pools", []): total += int(pool.get("amount", 0))
	return total


func _transfer_shield(source: Dictionary, recipient_keys: Array, amount: int, selector: Dictionary, events: Array, transfer_binding_key: String) -> bool:
	if amount < 0: state.error = "shield_transfer数量不得为负数"; return false
	var recipients: Array[Dictionary] = []
	var sorted_keys: Array = recipient_keys.duplicate()
	sorted_keys.sort()
	for key_value in sorted_keys:
		var candidate := _unit_by_key(str(key_value))
		if candidate.is_empty() or candidate.key == source.key or not _is_alive(candidate): continue
		if not recipients.is_empty() and recipients.back().key == candidate.key: continue
		recipients.append(candidate)
	if recipients.is_empty():
		state.error = "shield_transfer没有有效存活接收者"; return false
	var selected: Array[Dictionary] = []
	var available := 0
	for pool in source.shield_pools:
		if not str(selector.get("pool_id", "")).is_empty() and str(pool.get("pool_id", "")) != str(selector.pool_id): continue
		if not str(selector.get("source_key", "")).is_empty() and str(pool.get("source_key", "")) != str(selector.source_key): continue
		if not str(selector.get("source_binding_key", "")).is_empty() and str(pool.get("source_binding_key", "")) != str(selector.source_binding_key): continue
		if int(selector.get("expires_tick", -1)) >= 0 and int(pool.get("expires_tick", -1)) != int(selector.expires_tick): continue
		selected.append(pool)
		available += int(pool.amount)
	var moved_total := mini(amount, available)
	var left := moved_total
	var pool_parts: Array[Dictionary] = []
	for pool in selected:
		var part := mini(left, int(pool.amount))
		if part > 0:
			pool_parts.append({"pool_id":str(pool.get("pool_id", "")),"origin_pool_id":str(pool.get("origin_pool_id", pool.get("pool_id", ""))),
				"source_key":str(pool.source_key),"source_binding_key":str(pool.get("source_binding_key", "")),
				"expires_tick":int(pool.expires_tick),"amount":part})
			left -= part
		if left == 0: break
	var shares: Array[int] = []
	for _recipient in recipients: shares.append(int(floor(float(moved_total) / recipients.size())))
	for i in range(moved_total % recipients.size()): shares[i] += 1
	var recipient_left: Array[int] = shares.duplicate()
	for part in pool_parts:
		var part_left := int(part.amount)
		for i in range(recipients.size()):
			var portion := mini(part_left, recipient_left[i])
			if portion <= 0: continue
			var receiver: Dictionary = recipients[i]
			if not _grant_shield(receiver, str(part.source_key), portion, int(part.expires_tick), events,
				str(part.source_binding_key),"new","",-1,str(part.origin_pool_id)): return false
			recipient_left[i] -= portion
			part_left -= portion
		if part_left > 0:
			state.error = "shield_transfer内部均分分配不守恒"; return false
	for part in pool_parts:
		for pool_index in range(source.shield_pools.size()):
			var pool: Dictionary = source.shield_pools[pool_index]
			if str(pool.get("pool_id", "")) != str(part.pool_id): continue
			pool.amount = int(pool.amount) - int(part.amount)
			pool.revision = int(pool.get("revision", 0)) + 1
			if int(pool.amount) <= 0: source.shield_pools.remove_at(pool_index)
			break
	var actual_moved := moved_total
	if actual_moved < amount:
		_emit("shield_transfer_shortfall", transfer_binding_key, recipients[0].slot, recipients[0].side,
			{"requested":amount,"transferred":actual_moved,"recipient_keys":sorted_keys,"pool_selector":selector.duplicate(true)}, events)
	return true


func _clear_shields(target: Dictionary, events: Array, legal_clear: bool) -> void:
	if target.shield_pools.is_empty(): return
	target.shield_pools.clear()
	if legal_clear: _emit("shield_broken", "", target.slot, target.side, {"cleared":true,"reason":"clear"}, events)


func _clear_shield_amount(target: Dictionary, amount: int, source_key: String, source_binding_key: String, events: Array) -> int:
	if amount < 0: state.error = "enemy_clear_shield数量不得为负数"; return -1
	var left := amount
	var removed := 0
	var last_pool: Dictionary = {}
	var index := 0
	while left > 0 and index < target.shield_pools.size():
		var pool: Dictionary = target.shield_pools[index]
		var part := mini(left, int(pool.amount))
		if part <= 0: index += 1; continue
		last_pool = pool.duplicate(true)
		pool.amount -= part
		left -= part
		removed += part
		if int(pool.amount) <= 0: target.shield_pools.remove_at(index)
		else: index += 1
	if removed > 0:
		_emit("shield_cleared", source_key, target.slot, target.side,
			{"amount":removed,"source_binding_key":source_binding_key,"pool_source_binding_key":str(last_pool.get("source_binding_key", ""))}, events)
		if target.shield_pools.is_empty():
			_emit("shield_broken", source_key, target.slot, target.side,
				{"reason":"clear","amount":removed,"source_binding_key":source_binding_key,"pool_source_binding_key":str(last_pool.get("source_binding_key", ""))}, events)
	return removed


func _add_status(target: Dictionary, action: Dictionary, events: Array) -> void:
	var id := str(action.get("status_id", ""))
	var layers := int(action.get("layers", 1))
	var expires := int(action.get("expires_tick", state.tick + 10))
	if id.is_empty() or layers <= 0 or expires < int(state.tick): state.error = "状态参数无效"; return
	if id not in ["burn", "chill", "bleed", "poison", "silence", "rooted", "anti_heal"]:
		state.error = "未知状态 ID: %s" % id; return
	var existing := 0
	var cycle_id := 0
	for status in target.statuses:
		if status.id == id:
			existing += int(status.layers)
			if cycle_id == 0: cycle_id = int(status.get("status_cycle_id", status.get("status_instance_id", 0)))
	var accepted := mini(layers, maxi(5 - existing, 0))
	for status in target.statuses:
		if status.id == id and not bool(status.get("expiry_suppressed", false)): status.expires_tick = maxi(int(status.expires_tick), expires)
	if accepted > 0:
		state.status_serial += 1
		if cycle_id == 0: cycle_id = state.status_serial
		target.statuses.append({"id":id,"source_key":str(action.get("source_key", "")),"source_binding_key":str(action.get("source_binding_key", "")),
			"status_instance_id":state.status_serial,"status_cycle_id":cycle_id,"layers":accepted,"expires_tick":expires,"expiry_suppressed":false,"next_tick":int(state.tick) + 10})
	_emit("status_applied", str(action.get("source_key", "")), target.slot, target.side,
		{"status_id":id,"status_instance_id":state.status_serial,"status_cycle_id":cycle_id,"source_binding_key":str(action.get("source_binding_key", "")),"added_layers":accepted,"refreshed":existing > 0}, events)


func _remove_status(target: Dictionary, id: String, layers: int, events: Array, source_binding_filter: String = "") -> void:
	if layers <= 0: state.error = "移除状态层数必须大于0"; return
	var original_cycles: Dictionary = {}
	var removed_instances: Array = []
	for existing_status in target.statuses:
		if str(existing_status.id) != id: continue
		var existing_cycle := int(existing_status.get("status_cycle_id", existing_status.get("status_instance_id", 0)))
		original_cycles[existing_cycle] = true
	target.statuses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.expires_tick) != int(b.expires_tick): return int(a.expires_tick) < int(b.expires_tick)
		return str(a.source_key) < str(b.source_key))
	var left := layers
	var i := 0
	while i < target.statuses.size() and left > 0:
		var status: Dictionary = target.statuses[i]
		if str(status.id) != id or (not source_binding_filter.is_empty() and str(status.get("source_binding_key", "")) != source_binding_filter):
			i += 1
			continue
		var remove := mini(left, int(status.layers))
		status.layers -= remove
		left -= remove
		if int(status.layers) <= 0:
			removed_instances.append(int(status.get("status_instance_id", 0)))
			target.statuses.remove_at(i)
		else: i += 1
	var remaining_cycles: Dictionary = {}
	for remaining_status in target.statuses:
		if str(remaining_status.id) == id:
			remaining_cycles[int(remaining_status.get("status_cycle_id", remaining_status.get("status_instance_id", 0)))] = true
	var removed_cycles: Array = []
	for original_cycle in original_cycles:
		if not remaining_cycles.has(original_cycle): removed_cycles.append(int(original_cycle))
	removed_cycles.sort()
	removed_instances.sort()
	var removed_payload := {"status_id":id,"source_binding_key":source_binding_filter,"requested_layers":layers,"removed_layers":layers-left,
		"removed_cycle_ids":removed_cycles,"removed_status_instance_ids":removed_instances}
	if removed_cycles.size() == 1: removed_payload["status_cycle_id"] = int(removed_cycles[0])
	if removed_instances.size() == 1: removed_payload["status_instance_id"] = int(removed_instances[0])
	_emit("status_removed", "", target.slot, target.side, removed_payload, events)


func _remove_modifier(target: Dictionary, modifier_id: String, source_binding_filter: String) -> void:
	for i in range(target.modifiers.size() - 1, -1, -1):
		var modifier: Dictionary = target.modifiers[i]
		if not modifier_id.is_empty() and str(modifier.get("modifier_id", "")) != modifier_id: continue
		if not source_binding_filter.is_empty() and str(modifier.get("source_binding_key", "")) != source_binding_filter: continue
		target.modifiers.remove_at(i)
	_clamp_current_hp_to_max(target)


func _effective_max_hp_tenths(target: Dictionary) -> int:
	var health := int(target.initial_max_hp_tenths)
	for modifier in target.modifiers:
		if str(modifier.get("stat", "")) in ["H_flat", "H_max_flat"]: health += int(modifier.get("amount", 0)) * 10
	return maxi(10, health)


func _clamp_current_hp_to_max(target: Dictionary) -> void:
	target.hp_tenths = mini(int(target.hp_tenths), _effective_max_hp_tenths(target))


func _revive(target: Dictionary, amount: int, source_key: String, events: Array) -> void:
	if amount <= 0 or bool(target.revive_used) or bool(target.final_departed) or not bool(target.pending_final): return
	target.revive_used = true
	target.pending_final = false
	target.dead = false
	target.hp_tenths = mini(amount, _effective_max_hp_tenths(target))
	_emit("revived", source_key, target.slot, target.side, {"amount":target.hp_tenths}, events)


func _finalize_departures(events: Array) -> void:
	# Death is observed from the fully resolved batch; registered revives have already run.
	for side in SIDES:
		for target in state.teams[side]:
			if not bool(target.pending_final) or bool(target.final_departed): continue
			var credits: Array = []
			var event_id := "departure-%08d" % (state.final_departures.size() + 1)
			for event in events:
				if event.kind != "hp_lost" or int(event.target_slot) != int(target.slot) or str(event.target_side) != side: continue
				var source := _unit_by_key(str(event.source_key))
				if source.is_empty() or source.side == side: continue
				var entry: Dictionary = event.payload.get("entry", {})
				var credit_key := {"side":source.side,"slot":source.slot}
				var has := false
				for old in credits:
					if old == credit_key: has = true
				if not has: credits.append(credit_key)
			var departure := {"event_id":event_id,"tick":int(state.tick),"target_side":side,"target_slot":int(target.slot),"credited_units":credits}
			state.final_departures.append(departure)
			target.final_departed = true
			target.dead = true
			target.pending_final = false
			_emit("final_departure", "", target.slot, side, departure, events)


func _is_alive(unit_state: Dictionary) -> bool:
	return not bool(unit_state.get("dead", false)) and not bool(unit_state.get("final_departed", false)) and int(unit_state.get("hp_tenths", 0)) > 0


func _has_status(unit_state: Dictionary, id: String) -> bool:
	for status in unit_state.statuses:
		if str(status.id) == id and int(status.expires_tick) > int(state.tick): return true
	return false


func _new_root() -> String:
	state.root_serial += 1
	return "root-%08d" % state.root_serial


func _action_root(action: Dictionary) -> String:
	var root_id := str(action.get("root_id", ""))
	return _new_root() if root_id.is_empty() else root_id


func _entry_root(entry: Dictionary) -> String:
	var root_id := str(entry.get("root_id", ""))
	return _new_root() if root_id.is_empty() else root_id


func _unit_by_key(key: String) -> Dictionary:
	if key.length() < 2: return {}
	var side := key.substr(0, 1)
	if side not in SIDES: return {}
	var slot := key.substr(1).to_int()
	if slot < 1 or slot > 3: return {}
	return state.teams[side][slot - 1]


func _source_owner(source_key: String) -> Dictionary:
	var owner := _unit_by_key(source_key)
	if not owner.is_empty(): return owner
	for binding in bindings:
		if str(binding.get("source_key", "")) == source_key: return _unit_by_key(str(binding.get("owner_key", "")))
	return {}


func _snapshot_for_rules() -> Dictionary:
	var result := {"A":[],"B":[]}
	for side in SIDES:
		for item in state.teams[side]:
			result[side].append({"slot":int(item.slot),"base_H":int(item.base_H),"base_A":int(item.base_A),
				"base_T_ticks":int(item.base_T_ticks),"base_R":int(item.base_R),"hp_tenths":int(item.hp_tenths),
				"initial_max_hp_tenths":int(item.initial_max_hp_tenths),"final_departed":bool(item.final_departed),
				"first_natural_attack_tick":item.first_natural_attack_tick})
	return result


func _snapshot() -> Dictionary:
	return {"tick":int(state.tick),"teams":state.teams.duplicate(true),"winner":state.winner,
		"terminal":bool(state.terminal),"rule_id":str(state.rule_id)}


func _hash_state() -> String:
	var canonical := {"tick":state.tick,"teams":state.teams,"queue":state.queue,
		"pending_damage":state.pending_damage,"pending_attacks":state.pending_attacks,
		"redirect_capacity_used":state.redirect_capacity_used,"root_redirect_capacity_used":state.root_redirect_capacity_used,
		"final_departures":state.final_departures,"victory_memory":state.victory_memory,
		"root_triggered":state.root_triggered,"root_action_counts":state.root_action_counts,
		"winner":state.winner,"terminal":state.terminal,"seed":state.seed}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(canonical, "", false).to_utf8_buffer())
	return context.finish().hex_encode()


func _result(new_events: Array = []) -> Dictionary:
	var error_message := str(state.get("error", ""))
	var coverage: Dictionary = {} if not error_message.is_empty() else state.get("content_coverage", {}).duplicate(true)
	return {"events":new_events.duplicate(true),"snapshot":_snapshot(),"terminal":bool(state.get("terminal", false)),
		"winner":state.get("winner", null),"reason":str(state.get("reason", "")),
		"state_hash":_hash_state() if configured else "","tick_hashes":state.get("tick_hashes", []).duplicate(true),
		"content_coverage":coverage,"error":error_message}


func _error(message: String) -> Dictionary:
	return {"events":[],"snapshot":{},"terminal":false,"winner":null,"reason":"","state_hash":"","tick_hashes":[],"content_coverage":{},"error":message}


func _fail(message: String) -> Dictionary:
	state.error = message
	return _error(message)
