extends RefCounted

const EngineScript = preload("res://core/battle/battle_engine.gd")
const VictoryScript = preload("res://core/rules/victory_rules.gd")

var passed := 0
var failed := 0
var lines: Array[String] = []
var active_test := ""

class CountingHandler extends RefCounted:
	var calls := 0
	var response: Array = []
	func on_event(_engine, _binding: Dictionary, _event: Dictionary) -> Array:
		calls += 1
		return response.duplicate(true)

class OpeningSilenceHandler extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "pre_battle" and event.payload.phase == "environment_initial":
			return [{"kind":"status_add","target_key":"A1","status_id":"silence","expires_tick":20}]
		if event.kind == "battle_start": return [{"kind":"counter","counter_key":"opened","value":1}]
		if event.kind == "expiry" and event.payload.get("status_id", "") == "silence":
			return [{"kind":"counter","counter_key":"silence_expired","value":1}]
		return []

class AttackGateHandler extends RefCounted:
	var source_key := ""
	var on_event_kind := ""
	var calls := 0
	var action: Dictionary = {}
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if str(event.kind) != on_event_kind or str(event.source_key) != source_key: return []
		calls += 1
		return [action.duplicate(true)]

class ExtraAttackHandler extends RefCounted:
	var calls := 0
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "hit" and str(event.source_key) == "A1" and bool(event.is_natural_attack) and not bool(event.is_extra_attack):
			calls += 1
			return [{"kind":"extra_attack","target_key":"B1","amount":10,"damage_type":"fire"}]
		return []

class ExtraPatchHandler extends RefCounted:
	var calls := 0
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "before_hit" and str(event.source_key) == "A1" and bool(event.is_extra_attack):
			calls += 1
			return [{"kind":"attack_patch","patch":{"target_key":"B2","amount_flat":10,"damage_type":"fire"}}]
		return []

class EventRecorder extends RefCounted:
	var seen: Array = []
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if str(event.kind) in ["prepare_attack", "before_hit", "hit", "hp_lost", "shield_cleared", "shield_broken", "barrier_absorbed", "healed"]:
			seen.append(event.duplicate(true))
		return []

class ReducerInstallHandler extends RefCounted:
	func on_event(_engine, binding: Dictionary, event: Dictionary) -> Array:
		if event.kind != "battle_start": return []
		return [{"kind":"modifier_add","target_key":"B1","stat":"healing_reduction_bp","amount":4000,"expires_tick":100}]

class ModifierOnStartHandler extends RefCounted:
	var target_key := ""
	var stat := ""
	var amount := 0
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind != "battle_start": return []
		return [{"kind":"modifier_add","target_key":target_key,"stat":stat,"amount":amount,"expires_tick":100}]

class BeforeDamageReductionHandler extends RefCounted:
	var target_key := ""
	var amount_bp := 0
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind != "before_damage" or str(event.target_key) != target_key: return []
		return [{"kind":"damage_reduction","amount_bp":amount_bp}]

class ScopedHealCycleHandler extends RefCounted:
	var observed_targets: Array[String] = []
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "battle_start":
			return [
				{"kind":"heal","target_key":"A2","amount":10},
				{"kind":"heal","target_key":"A3","amount":10}
			]
		if event.kind != "healed": return []
		var target := str(event.get("target_key", ""))
		observed_targets.append(target)
		if target == "A2": return [{"kind":"heal","target_key":"A3","amount":10}]
		if target == "A3": return [{"kind":"heal","target_key":"A2","amount":10}]
		return []

class HealthCapHandler extends RefCounted:
	var hp_modifier := 0
	var damage_at_start := 0
	var revive_amount := 0
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "battle_start":
			var actions: Array = []
			if hp_modifier != 0: actions.append({"kind":"modifier_add","target_key":"B1","stat":"H_max_flat","amount":hp_modifier,"modifier_id":"fixture_health_cap"})
			if damage_at_start > 0: actions.append({"kind":"damage","target_key":"B1","amount":damage_at_start,"damage_type":"fixed"})
			return actions
		if event.kind == "hp_lost" and str(event.get("target_key", "")) == "B1" and revive_amount > 0:
			return [{"kind":"revive","target_key":"B1","amount":revive_amount}]
		return []

class AttackSegmentHandlers extends RefCounted:
	var patch_type := false
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind != "before_hit" or not bool(event.get("is_natural_attack", false)): return []
		if patch_type: return [{"kind":"attack_patch","attack_id":event.attack_id,"patch":{"damage_type":"fire"}}]
		return [{"kind":"attack_patch","attack_id":event.attack_id,"patch":{"append_segments":[{"amount":10,"damage_type":"ice"}]}}]

class StatusEnvironmentHandlers extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "battle_start": return [{"kind":"status_tick_modifier","status_id":"burn","amount_bp":10000}]
		return []

class StatusApplyHandlers extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "battle_start": return [
			{"kind":"status_add","target_key":"B1","status_id":"burn","layers":1,"expires_tick":10},
			{"kind":"status_add","target_key":"B2","status_id":"poison","layers":1,"expires_tick":10}]
		return []

class PoisonExpirySuppressHandler extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind != "status_applied" or str(event.get("payload", {}).get("status_id", "")) != "poison": return []
		return [{"kind":"status_expiry_suppress","target_key":event.target_key,"status_id":"poison",
			"status_cycle_id":int(event.payload.status_cycle_id)}]

class InitialShieldGrantHandler extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "battle_start":
			return [{"kind":"shield_grant","target_key":"A1","source_key":"A1","source_binding_key":"A1:pool_owner","amount":100,"expires_tick":100}]
		return []

class SplitShieldDelayHandler extends RefCounted:
	var split_once := false
	func on_event(engine, _binding: Dictionary, event: Dictionary) -> Array:
		if split_once or event.kind != "shield_gained" or str(event.get("target_key", "")) != "A1": return []
		var payload: Dictionary = event.get("payload", {})
		if str(payload.get("pool_mode", "")) == "add": return []
		if str(payload.get("source_binding_key", "")) != "A1:pool_owner": return []
		split_once = true
		return [
			{"kind":"shield_grant","target_key":"A1","source_key":"A1","source_binding_key":"A1:pool_owner",
				"amount":50,"expires_tick":int(payload.expires_tick),"pool_mode":"refresh"},
			{"kind":"schedule","tick":int(engine.state.tick)+20,"phase":"post_damage","action":{
				"kind":"shield_grant","target_key":"A1","source_key":"A1","source_binding_key":"A1:pool_owner",
				"amount":50,"expires_tick":int(payload.expires_tick),"pool_mode":"add","pool_id":str(payload.pool_id),
				"expected_revision":int(payload.pool_revision)+1}}
		]

class AttackCorrelationHandler extends RefCounted:
	var suppress := false
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind != "before_hit" or str(event.get("source_key", "")) != "A1" or not bool(event.get("is_natural_attack", false)): return []
		var actions: Array = [{"kind":"attack_patch","attack_id":str(event.attack_id),"patch":{
			"append_segments":[{"amount":20,"damage_type":"fixed","target_key":"B2"}],
			"attached_damage":[{"amount":30,"damage_type":"fixed","target_key":"B3"}],
			"consume_on_hit":[{"counter_key":"armed","amount":1}]}}]
		if suppress: actions.append({"kind":"attack_suppress","attack_id":str(event.attack_id)})
		return actions

class AttackResolvedRecorder extends RefCounted:
	var seen: Array = []
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "attack_resolved" and str(event.get("source_key", "")) == "A1": seen.append(event.duplicate(true))
		return []

class ShieldSegmentObservationHandler extends RefCounted:
	var seen: Array[int] = []
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "battle_start":
			return [{"kind":"shield_grant","target_key":"B1","source_key":"B2","source_binding_key":"B2:shield","amount":250,"expires_tick":100}]
		if event.kind == "before_hit" and bool(event.get("is_natural_attack", false)):
			return [{"kind":"attack_patch","attack_id":str(event.attack_id),"patch":{"segments":[
				{"amount":100,"damage_type":"fixed","is_attack":true,"is_natural_attack":true},
				{"amount":150,"damage_type":"fixed","is_attack":true,"is_natural_attack":true}]}}]
		if event.kind == "hit" and str(event.get("source_key", "")) == "A1":
			seen.append(int(event.get("payload", {}).get("shield_after_tenths", -1)))
		return []

class AttachedSourceOverrideHandler extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind == "before_hit" and bool(event.get("is_natural_attack", false)):
			return [{"kind":"attack_patch","attack_id":str(event.attack_id),"patch":{"attached_damage":[
				{"amount":50,"damage_type":"fixed","source_unit_key":"A2"}]}}]
		return []

class RedirectCapStepHandler extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind != "battle_start": return []
		return [
			{"kind":"redirect_register","target_key":"A1","redirect_id":"shared_step_cap","ratio_bp":5000,"capacity_per_root":60,"recipient_keys":["A3"]},
			{"kind":"redirect_register","target_key":"A2","redirect_id":"shared_step_cap","ratio_bp":5000,"capacity_per_root":60,"recipient_keys":["A3"]},
			{"kind":"damage","target_key":"A1","amount":100,"damage_type":"fixed"},
			{"kind":"damage","target_key":"A2","amount":100,"damage_type":"fixed"},
			{"kind":"shield_grant","target_key":"B1","amount":30,"expires_tick":100},
			{"kind":"damage","target_key":"B1","amount":80,"damage_type":"fixed","shield_only":true}
		]

class ShieldPoolTransferStepHandler extends RefCounted:
	func on_event(_engine, _binding: Dictionary, event: Dictionary) -> Array:
		if event.kind != "battle_start": return []
		return [
			{"kind":"shield_grant","target_key":"A1","source_key":"A1","source_binding_key":"A1:pool","amount":20,"expires_tick":30,"pool_mode":"new"},
			{"kind":"shield_grant","target_key":"A1","source_key":"A1","source_binding_key":"A1:pool","amount":10,"expires_tick":50,"pool_mode":"new"},
			{"kind":"shield_transfer","from_target_key":"A1","recipient_keys":["A2","A3"],"amount":13,"pool_source_binding_key":"A1:pool"}
		]

class ScheduleDebtHandler extends RefCounted:
	func on_event(_engine, binding: Dictionary, event: Dictionary) -> Array:
		if event.kind != "battle_start": return []
		return [{"kind":"schedule","tick":1,"phase":"post_damage","action":{
			"kind":"counter_settlement","target_key":"B1","counter_key":"loan_absorbed","amount_bp":5000,
			"max_amount":60,"damage_type":"physical"}}]


func run_all() -> Dictionary:
	_test_b01_damage_pipeline()
	_test_b02_barrier_shield_and_self_loss()
	_test_b03_transfer_cap_and_non_recursion()
	_test_b04_shield_break_semantics()
	_test_b05_shield_refresh_and_expiry_order()
	_test_b06_status_layers_and_source_order()
	_test_b07_silence_scopes_talent_only()
	_test_b08_batch_lethal_and_revive_window()
	_test_b09_root_once_and_extra_generation()
	_test_b10_multihit_barrier_per_segment()
	_test_b11_target_fallback_and_lane_timing()
	_test_b12_final_departure_credit_is_actual_loss()
	_test_b13_rule_deadlines_and_final_departure_input()
	_test_b14_replay_hash_determinism()
	_test_b15_reject_unknown_handlers_and_nonfixture_blanks()
	_test_b16_armor_minimum_and_slow_rounding()
	_test_b17_pre_battle_order_and_half_open_expiry()
	_test_b18_attack_patch_and_suppression_pipeline()
	_test_b19_extra_attack_inherits_root_and_generation()
	_test_b20_redirect_shared_cap_and_heal_attribution()
	_test_b21_batch_event_phase_ordering()
	_test_b22_fractional_attack_stat()
	_test_b23_before_damage_reduction_composition()
	_test_b24_scheduled_counter_settlement_survives_silence()
	_test_b25_same_root_shield_absorption_aggregation()
	_test_b26_event_target_guard_preserves_fanout_and_blocks_cycle()
	_test_b27_one_life_health_floor_and_dynamic_revive_cap()
	_test_b28_status_removed_cycle_identity()
	_test_b29_attack_segment_identity_and_barrier_absorption()
	_test_b30_dot_modifier_and_selective_expiry_suppression()
	_test_b31_result_content_coverage_copy()
	_test_b32_root_transfer_cap_and_shield_only_damage()
	_test_b33_shield_pool_selection_equal_transfer_and_provenance()
	_test_b34_delayed_shield_refill_cancels_on_refresh()
	_test_b35_correlated_attack_multitarget_and_consume_on_hit()
	_test_b36_fast_sim_preserves_outcome_and_events()
	_test_b37_public_ai_capture_and_read_apis()
	_test_b38_segment_hit_shield_snapshot()
	_test_b39_attached_source_unit_override()
	return {"passed":passed,"failed":failed,"lines":lines.duplicate()}


func _test_b01_damage_pipeline() -> void:
	active_test = "B01"
	var engine := _new_engine()
	var setup := engine.setup(_config())
	_check(setup.error == "", "fixture setup")
	var result := engine.fixture_apply([
		{"kind":"damage","target":"B1","source":"A1","amount":90,"damage_type":"physical"}
	])
	_check(result.error == "", "physical damage accepted error=%s" % result.error)
	_check(engine.unit("B1").hp_tenths == 970, "9 physical vs R6 loses exactly 3")
	var fire := _new_engine(); fire.setup(_config())
	fire.fixture_apply([{"kind":"damage","target":"B1","source":"A1","amount":90,"damage_type":"fire"}])
	_check(fire.unit("B1").hp_tenths == 910, "9 fire bypasses armor (hp=%d)" % fire.unit("B1").hp_tenths)
	var zero := _new_engine(); zero.setup(_config())
	zero.fixture_apply([{"kind":"damage","target":"B1","source":"A1","amount":0,"damage_type":"physical"}])
	_check(zero.unit("B1").hp_tenths == 1000, "zero damage does not become minimum 1")
	_done()


func _test_b02_barrier_shield_and_self_loss() -> void:
	active_test = "B02"
	var engine := _new_engine(); engine.setup(_config())
	engine.fixture_apply([{"kind":"shield_grant","target":"B1","source":"A1","amount":20}])
	engine.fixture_apply([{"kind":"barrier_grant","target":"B1"}])
	engine.fixture_apply([{"kind":"damage","target":"B1","source":"A1","amount":90,"damage_type":"physical"}])
	_check(engine.unit("B1").hp_tenths == 1000 and engine.unit("B1").shield_pools[0].amount == 20, "barrier absorbs whole packet before armor/shield err=%s" % engine.state.error)
	var second := _new_engine(); second.setup(_config())
	second.fixture_apply([{"kind":"shield_grant","target":"B1","source":"A1","amount":20}])
	second.fixture_apply([{"kind":"damage","target":"B1","source":"A1","amount":90,"damage_type":"physical"}])
	_check(second.unit("B1").hp_tenths == 990 and second.unit("B1").shield_pools.is_empty(), "armor precedes shield; shield absorbs remainder")
	var self_engine := _new_engine(); self_engine.setup(_config())
	self_engine.fixture_apply([{"kind":"shield_grant","target":"A1","source":"A2","amount":100}])
	self_engine.fixture_apply([{"kind":"barrier_grant","target":"A1"}])
	self_engine.fixture_apply([{"kind":"damage","target":"A1","source":"A1","amount":100,"damage_type":"self_loss","is_self_loss":true}])
	_check(self_engine.unit("A1").hp_tenths == 900 and self_engine.unit("A1").shield_pools.size() == 1 and self_engine.unit("A1").barrier.active, "self loss bypasses all defensive layers")
	_done()


func _test_b03_transfer_cap_and_non_recursion() -> void:
	active_test = "B03"
	var engine := _new_engine(); engine.setup(_config({"R":0}))
	engine.fixture_apply([
		{"kind":"redirect_register","target":"A1","source":"A1:one","ratio_bp":5000,"recipient_keys":["A2"],"capacity_per_second":10000},
		{"kind":"redirect_register","target":"A1","source":"A1:two","ratio_bp":5000,"recipient_keys":["A3"],"capacity_per_second":10000},
		{"kind":"damage_batch","entries":[{"target_key":"A1","source_key":"B1","amount":1000,"damage_type":"fire","root_id":"same-root"}]}
	])
	var a1 := engine.unit("A1"); var a2 := engine.unit("A2"); var a3 := engine.unit("A3")
	_check(a1.hp_tenths == 750 and a2.hp_tenths == 625 and a3.hp_tenths == 625, "redirect result A=%d B=%d C=%d" % [a1.hp_tenths,a2.hp_tenths,a3.hp_tenths])
	_check(a2.redirects.is_empty() and a3.redirects.is_empty(), "receivers do not recursively transfer")
	_done()


func _test_b04_shield_break_semantics() -> void:
	active_test = "B04"
	var engine := _new_engine(); engine.setup(_config())
	var used := engine.fixture_apply([{"kind":"shield_grant","target":"B1","source":"A1","amount":10},{"kind":"shield_consume","target":"B1","amount":10}])
	_check(_count_kind(used.events, "shield_broken") == 0, "active consumption is not a break events=%s" % str(used.events))
	var clear := engine.fixture_apply([{"kind":"shield_grant","target":"B1","source":"A1","amount":10},{"kind":"shield_clear","target":"B1"}])
	_check(_count_kind(clear.events, "shield_broken") == 1, "legal clear to zero emits break")
	engine.fixture_apply([{"kind":"shield_grant","target":"B1","source":"A1","amount":20}])
	var damaged := engine.fixture_apply([{"kind":"damage","target":"B1","source":"A1","amount":30,"damage_type":"fire"}])
	_check(_count_kind(damaged.events, "shield_broken") == 1, "damage depletion emits exactly one break")
	_done()


func _test_b05_shield_refresh_and_expiry_order() -> void:
	active_test = "B05"
	var engine := _new_engine(); engine.setup(_config())
	engine.fixture_apply([
		{"kind":"shield_grant","target":"B1","source":"A1","amount":100,"expires_tick":30},
		{"kind":"shield_grant","target":"B1","source":"A2","amount":100,"expires_tick":20},
		{"kind":"shield_grant","target":"B1","source":"A1","amount":60,"expires_tick":40}
	])
	var pools: Array = engine.unit("B1").shield_pools
	_check(pools.size() == 2 and int(pools[0].amount) == 100 and int(pools[1].amount) == 60, "same source refresh replaces, does not add")
	_check(pools[0].source_key == "A2" and pools[1].source_key == "A1", "earliest expiry pool sorts first")
	engine.fixture_apply([{"kind":"damage","target":"B1","source":"A1","amount":100,"damage_type":"fire"}])
	pools = engine.unit("B1").shield_pools
	_check(pools.size() == 1 and pools[0].source_key == "A1" and int(pools[0].amount) == 60, "earliest-expiry pool absorbs first")
	_done()


func _test_b06_status_layers_and_source_order() -> void:
	active_test = "B06"
	var engine := _new_engine(); engine.setup(_config())
	engine.fixture_apply([
		{"kind":"status_add","target":"B1","status_id":"burn","source_key":"A2","layers":3,"expires_tick":20},
		{"kind":"status_add","target":"B1","status_id":"burn","source_key":"A1","layers":2,"expires_tick":10},
		{"kind":"status_add","target":"B1","status_id":"burn","source_key":"A3","layers":1,"expires_tick":40}
	])
	var statuses: Array = engine.unit("B1").statuses
	_check(_status_layers(statuses, "burn") == 5, "same status capped at five layers")
	_check(_count_source(statuses, "burn", "A2") == 3 and _count_source(statuses, "burn", "A1") == 2, "full-stack refresh preserves existing sources")
	engine.fixture_apply([{"kind":"status_remove","target":"B1","status_id":"burn","layers":2}])
	statuses = engine.unit("B1").statuses
	_check(_count_source(statuses, "burn", "A1") == 0 and _count_source(statuses, "burn", "A2") == 3, "removal consumes earliest-expiring layers first")
	_done()


func _test_b07_silence_scopes_talent_only() -> void:
	active_test = "B07"
	var talent := CountingHandler.new(); talent.response = [{"kind":"counter","counter_key":"triggered","value":1}]
	var equipment := CountingHandler.new(); equipment.response = [{"kind":"counter","counter_key":"triggered","value":1}]
	var handlers := [
		{"logic_handler":"tal","handler":talent,"bindings":[{"content_id":"FIXTURE_T","source_key":"A1:tal","owner_key":"A1","kind":"talent","subscribes":["battle_start"]}]},
		{"logic_handler":"eq","handler":equipment,"bindings":[{"content_id":"FIXTURE_E","source_key":"A1:eq","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]}]}
	]
	var engine := _new_engine(); engine.setup(_config({"silence_owner":"A1"}), handlers)
	engine.fixture_apply([{"kind":"silence","target":"A1","expires_tick":10}])
	var result := engine.step()
	_check(result.error == "" and talent.calls == 0 and equipment.calls == 1, "silence pauses talent only; equipment calls=%d talent=%d err=%s" % [equipment.calls,talent.calls,result.error])
	_done()


func _test_b08_batch_lethal_and_revive_window() -> void:
	active_test = "B08"
	var engine := _new_engine(); engine.setup(_config({"hp_tenths":10}))
	var revived := engine.fixture_apply([
		{"kind":"damage_batch","entries":[
			{"target_key":"A1","source_key":"B1","amount":100,"damage_type":"fire","root_id":"ra"},
			{"target_key":"B1","source_key":"A1","amount":100,"damage_type":"fire","root_id":"rb"}]},
		{"kind":"revive","target":"A1","amount":30},{"kind":"revive","target":"B1","amount":30}
	])
	_check(not engine.unit("A1").final_departed and not engine.unit("B1").final_departed, "both simultaneous deaths can revive before final departure")
	_check(engine.unit("A1").revive_used and engine.unit("B1").revive_used, "revive is tracked per unit")
	var doomed := _new_engine(); doomed.setup(_config({"hp_tenths":10}))
	doomed.fixture_apply([{"kind":"damage_batch","entries":[{"target_key":"A1","source_key":"B1","amount":100,"damage_type":"fire","root_id":"lethal"}]},{"kind":"heal","target":"A1","amount":100}])
	_check(doomed.unit("A1").final_departed and doomed.unit("A1").hp_tenths == 0, "post-lethal ordinary healing cannot reverse final departure")
	_done()


func _test_b09_root_once_and_extra_generation() -> void:
	active_test = "B09"
	var loop := CountingHandler.new(); loop.response = [{"kind":"extra_attack","target_key":"B1","amount":10,"damage_type":"fire"}]
	var handler := {"logic_handler":"loop","handler":loop,"bindings":[{"content_id":"FIXTURE_LOOP","source_key":"A1:loop","owner_key":"A1","kind":"talent","subscribes":["hit"]}]}
	var engine := _new_engine(); engine.setup(_config(), [handler])
	var result := engine.fixture_apply([{"kind":"damage_batch","entries":[
		{"target_key":"B1","source_key":"A1","amount":10,"damage_type":"fire","root_id":"loop-root","is_attack":true},
		{"target_key":"B1","source_key":"A1","amount":10,"damage_type":"fire","root_id":"loop-root","is_attack":true,"segment_index":1}]}])
	_check(result.error == "" and loop.calls == 1, "binding meaningful action once calls=%d err=%s" % [loop.calls,result.error])
	_check(engine.unit("B1").hp_tenths == 970, "extra generation bounded hp=%d queue=%s" % [engine.unit("B1").hp_tenths,str(engine.state.queue)])
	_done()


func _test_b10_multihit_barrier_per_segment() -> void:
	active_test = "B10"
	var engine := _new_engine(_config({"R":0})); engine.setup(_config({"R":0}))
	engine.fixture_apply([{"kind":"barrier_grant","target":"B1"}])
	engine.fixture_apply([{"kind":"damage_batch","entries":[
		{"target_key":"B1","source_key":"A1","amount":100,"damage_type":"fire","root_id":"seg1","is_attack":true,"segment_index":1},
		{"target_key":"B1","source_key":"A1","amount":100,"damage_type":"fire","root_id":"seg2","is_attack":true,"segment_index":2}]}])
	_check(engine.unit("B1").hp_tenths == 900, "barrier blocks one segment; second segment lands separately")
	_done()


func _test_b11_target_fallback_and_lane_timing() -> void:
	active_test = "B11"
	var cfg := _config({"target_slot":3,"R":0})
	cfg.teams.B[2].hp_tenths = 0
	var engine := _new_engine(); engine.setup(cfg)
	var fallback_target := engine._choose_target(engine.unit("A1"))
	_check(str(fallback_target.get("key", "")) == "B2", "dead target fallback order 2,1,3; chosen=%s hp=%s dead=%s" % [str(fallback_target.get("key", "")),str(engine.unit("B3").get("hp_tenths", -1)),str(engine.unit("B3").get("dead", false))])
	engine.step()
	_check(int(engine.unit("A1").next_attack_tick) == 10, "melee off-position attack adds 0.4 seconds")
	var ranged_cfg := _config({"target_slot":3,"reach":"ranged","R":0})
	var ranged := _new_engine(); ranged.setup(ranged_cfg); ranged.step()
	_check(int(ranged.unit("A1").next_attack_tick) == 6, "ranged attacks pay no cross-slot delay")
	var flying_cfg := _config({"target_slot":3,"flying":true,"R":0})
	var flying := _new_engine(); flying.setup(flying_cfg); flying.step()
	_check(int(flying.unit("A1").next_attack_tick) == 6, "flying melee pays no cross-slot delay")
	_done()


func _test_b12_final_departure_credit_is_actual_loss() -> void:
	active_test = "B12"
	var engine := _new_engine(); engine.setup(_config({"hp_tenths":10}))
	engine.fixture_apply([{"kind":"damage_batch","entries":[{"target_key":"B1","source_key":"A1","amount":20,"damage_type":"fire","root_id":"credit","is_attack":true}]}])
	var departures: Array = engine.state.final_departures
	_check(departures.size() == 1 and departures[0].credited_units == [{"side":"A","slot":1}], "departure credit lists positive actual-loss source only")
	var assists := _new_engine(); assists.setup(_config({"hp_tenths":10}))
	assists.fixture_apply([{"kind":"damage_batch","entries":[
		{"target_key":"B1","source_key":"A1","amount":6,"damage_type":"fire","root_id":"c1","is_attack":true},
		{"target_key":"B1","source_key":"A2","amount":6,"damage_type":"fire","root_id":"c2","is_attack":true}]}])
	var credits: Array = assists.state.final_departures[0].credited_units
	_check(assists.unit("B1").hp_tenths == 0 and credits.size() == 2, "same-team simultaneous lethal packets proportionally credit both positive contributors")
	_check(_sum_actual_loss(assists.state.events, "B1") <= 10, "actual hp losses never exceed batch-start remaining HP")
	_done()


func _test_b13_rule_deadlines_and_final_departure_input() -> void:
	active_test = "B13"
	var short := _new_engine(); var c := _config({"H":10000,"A":0,"R":0,"T_ticks":6,"rule_id":"VC21"})
	var s := short.simulate(c)
	_check(s.error == "" and s.terminal and s.snapshot.tick == 120, "VC21 endpoint err=%s terminal=%s tick=%s winner=%s reason=%s" % [s.error,str(s.terminal),str(s.snapshot.get("tick",-1)),str(s.winner),s.reason])
	var long := _new_engine(); c.rule_id = "VC22"
	var l := long.simulate(c)
	_check(l.error == "" and l.terminal and l.snapshot.tick == 360, "VC22 settles exact 36-second endpoint err=%s tick=%s" % [l.error,str(l.snapshot.get("tick",-1))])
	_check(short.state.tick_hashes.size() == 121 and long.state.tick_hashes.size() == 361, "one VictoryRules evaluation per sequential tick including tick zero")
	_done()


func _test_b14_replay_hash_determinism() -> void:
	active_test = "B14"
	var cfg := _config({"H":10000,"A":1,"R":1,"seed":7331})
	var one := _new_engine().simulate(cfg)
	var two := _new_engine().simulate(cfg)
	_check(one.error == "" and two.error == "" and one.terminal and two.terminal and one.snapshot.tick > 0 and one.tick_hashes == two.tick_hashes, "same seed reproduces a real terminal simulation tick by tick")
	_check(one.state_hash == two.state_hash and one.events == two.events, "replay events and final state hash match")
	_done()


func _test_b15_reject_unknown_handlers_and_nonfixture_blanks() -> void:
	active_test = "B15"
	var invalid := _config(); invalid.test_fixture = false
	var engine := _new_engine()
	var result := engine.setup(invalid)
	_check(not result.error.is_empty() and result.winner == null, "fixture cannot enter production config and errors are not draws")
	var broken := _config(); broken.teams.A[0].talent_id = "WR01"
	result = _new_engine().setup(broken)
	_check(not result.error.is_empty() and result.winner == null, "unknown handler content never falls back to blank fixture")
	_done()


func _test_b16_armor_minimum_and_slow_rounding() -> void:
	active_test = "B16"
	var armored := _config({"A":0,"R":100})
	armored.teams.A[0].A = 10
	var natural := _new_engine(); natural.setup(armored)
	for _i in range(7): natural.step()
	_check(natural.unit("B1").hp_tenths == 990, "R100 cannot reduce a 10-tenths packet below 10 tenths")
	var fractional := _new_engine(); fractional.setup(_config({"R":100}))
	fractional.fixture_apply([{"kind":"damage","target":"B1","source":"A1","amount":5,"damage_type":"physical"}])
	_check(fractional.unit("B1").hp_tenths == 995, "sub-1-HP raw packet is not rounded upward")
	var seven := _new_engine(); seven.setup(_config({"T_ticks":7,"R":0}))
	seven.fixture_apply([{"kind":"status_add","target":"A1","status_id":"chill","source_key":"B1","expires_tick":50}])
	seven.step()
	_check(int(seven.unit("A1").next_attack_tick) == 9, "7 ticks times 1.25 rounds upward to 9")
	var slow_handler := CountingHandler.new()
	slow_handler.response = [{"kind":"modifier_add","target_key":"A1","stat":"T_ticks_percent","amount":3500,"expires_tick":50}]
	var slow_binding := {"logic_handler":"slow","handler":slow_handler,"bindings":[{"content_id":"FIXTURE_SLOW","source_key":"A1:slow","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]}]}
	var combined := _new_engine(); combined.setup(_config({"T_ticks":6,"R":0}), [slow_binding])
	combined.fixture_apply([{"kind":"status_add","target":"A1","status_id":"chill","source_key":"B1","expires_tick":50}])
	combined.step()
	_check(int(combined.unit("A1").next_attack_tick) == 9, "chill 25% and slow 35% use the strongest slow only")
	_done()


func _test_b17_pre_battle_order_and_half_open_expiry() -> void:
	active_test = "B17"
	var handler := OpeningSilenceHandler.new()
	var binding := {"logic_handler":"opening","handler":handler,"bindings":[{"content_id":"FIXTURE_OPENING","source_key":"A1:opening","owner_key":"A1","kind":"talent","pre_battle_phase":"environment_initial","subscribes":["pre_battle","battle_start","expiry"]}]}
	var engine := _new_engine(); engine.setup(_config({"H":10000,"A":0,"R":0}), [binding])
	var opening := engine.step()
	_check(opening.error.is_empty() and engine.get_counter("A1:opening", "opened") == 0, "environment-initial silence applies before battle_start talent trigger")
	for _i in range(20): engine.step()
	_check(engine.state.tick == 21 and engine.get_counter("A1:opening", "opened") == 0, "battle_start talent is not backfilled after silence expiry")
	_check(engine.get_counter("A1:opening", "silence_expired") == 1 and not engine._has_status(engine.unit("A1"), "silence"), "expires_tick=20 is removed before tick-20 actions")
	_done()


func _test_b18_attack_patch_and_suppression_pipeline() -> void:
	active_test = "B18"
	var target_handler := AttackGateHandler.new()
	target_handler.source_key = "A1"; target_handler.on_event_kind = "prepare_attack"
	target_handler.action = {"kind":"attack_patch","patch":{"target_key":"B2"}}
	var suppress_handler := AttackGateHandler.new()
	suppress_handler.source_key = "B1"; suppress_handler.on_event_kind = "before_hit"
	suppress_handler.action = {"kind":"attack_suppress"}
	var handlers := [
		{"logic_handler":"target_patch","handler":target_handler,"bindings":[{"content_id":"FIXTURE_PATCH","source_key":"A3:patch","owner_key":"A3","kind":"talent","subscribes":["prepare_attack"]}]},
		{"logic_handler":"suppress","handler":suppress_handler,"bindings":[{"content_id":"FIXTURE_SUPPRESS","source_key":"A2:suppress","owner_key":"A2","kind":"talent","subscribes":["before_hit"]}]}
	]
	var engine := _new_engine(); var cfg := _config({"A":10,"R":0,"T_ticks":6})
	var initialized := engine.setup(cfg, handlers)
	_check(initialized.error.is_empty(), "attack control setup err=%s" % initialized.error)
	for _tick in range(7): engine.step()
	var natural_hits: Array = []
	for event in engine.state.events:
		if event.kind == "hit" and bool(event.is_natural_attack): natural_hits.append(event)
	var patched_hit := false
	var suppressed_enemy_hit := false
	for event in natural_hits:
		if str(event.source_key) == "A1" and str(event.target_key) == "B2": patched_hit = true
		if str(event.source_key) == "B1": suppressed_enemy_hit = true
	_check(patched_hit and engine.unit("B2").hp_tenths == 900, "prepare_attack target patch redirects actual attack packet to B2")
	_check(not suppressed_enemy_hit and suppress_handler.calls == 1, "before_hit suppression cancels B1 packet once; calls=%d" % suppress_handler.calls)
	_check(engine.state.error.is_empty(), "attack control pipeline error=%s" % engine.state.error)
	_done()


func _test_b19_extra_attack_inherits_root_and_generation() -> void:
	active_test = "B19"
	var extra := ExtraAttackHandler.new()
	var patcher := ExtraPatchHandler.new()
	var recorder := EventRecorder.new()
	var handlers := [
		{"logic_handler":"extra","handler":extra,"bindings":[{"content_id":"FIXTURE_EXTRA","source_key":"A1:extra","owner_key":"A1","kind":"talent","subscribes":["hit"]}]},
		{"logic_handler":"extra_patch","handler":patcher,"bindings":[{"content_id":"FIXTURE_EXTRA_PATCH","source_key":"A2:extra_patch","owner_key":"A2","kind":"talent","subscribes":["before_hit"]}]},
		{"logic_handler":"record","handler":recorder,"bindings":[{"content_id":"FIXTURE_RECORD","source_key":"A3:record","owner_key":"A3","kind":"equipment","subscribes":["prepare_attack","before_hit","hit","hp_lost"]}]}
	]
	var engine := _new_engine(); var cfg := _config({"A":10,"R":0,"T_ticks":6})
	var initialized := engine.setup(cfg, handlers)
	_check(initialized.error.is_empty(), "extra pipeline setup err=%s" % initialized.error)
	for _tick in range(7): engine.step()
	var natural: Dictionary = {}
	var extra_prepare := false; var extra_before := false; var extra_hit: Dictionary = {}
	for event in engine.state.events:
		if event.kind == "hit" and event.source_key == "A1" and event.is_natural_attack and event.target_key == "B1": natural = event
	for event in recorder.seen:
		if event.kind == "prepare_attack" and event.source_key == "A1" and event.is_extra_attack: extra_prepare = true
		if event.kind == "before_hit" and event.source_key == "A1" and event.is_extra_attack: extra_before = true
		if event.kind == "hit" and event.source_key == "A1" and event.is_extra_attack: extra_hit = event
	_check(extra.calls == 1 and patcher.calls == 1, "extra handler triggers once per inherited root; extra=%d patch=%d" % [extra.calls,patcher.calls])
	_check(extra_prepare and extra_before and not extra_hit.is_empty(), "extra attack uses prepare/before_hit/hit pipeline")
	_check(not natural.is_empty() and str(extra_hit.root_id) == str(natural.root_id) and int(extra_hit.extra_generation) == 1, "extra hit inherits root and generation=1")
	_check(engine.unit("B2").hp_tenths == 980 and "A1:extra" in extra_hit.triggered_bindings, "before_hit target/amount patch and triggering binding inheritance")
	_check(engine.state.error.is_empty(), "extra pipeline error=%s" % engine.state.error)
	_done()


func _test_b20_redirect_shared_cap_and_heal_attribution() -> void:
	active_test = "B20"
	var redirects := _new_engine(); redirects.setup(_config({"A":0,"R":0,"hp_tenths":1000}))
	var redirected := redirects.fixture_apply([
		{"kind":"redirect_register","target":"A2","source":"A1","source_binding_key":"A1:WR06","ratio_bp":3000,"recipient_keys":["A1"],"capacity_per_second":100},
		{"kind":"redirect_register","target":"A3","source":"A1","source_binding_key":"A1:WR06","ratio_bp":3000,"recipient_keys":["A1"],"capacity_per_second":100},
		{"kind":"damage_batch","entries":[
			{"target_key":"A2","source_key":"B1","amount":200,"damage_type":"fire","root_id":"shared-1"},
			{"target_key":"A3","source_key":"B1","amount":200,"damage_type":"fire","root_id":"shared-2"}]}
	])
	_check(redirected.error.is_empty() and redirects.unit("A1").hp_tenths == 900, "same-binding redirect capacity shared across protected targets; owner HP=%d err=%s" % [redirects.unit("A1").hp_tenths,redirected.error])
	_check(redirects.unit("A2").hp_tenths == 860 and redirects.unit("A3").hp_tenths == 840, "cap remainder stays on each original target after stable source order")

	var reducer_bindings: Array = []
	var reducer_handlers: Array = []
	for slot in [1, 2, 3]:
		var handler_id := "reducer_%d" % slot
		reducer_handlers.append({"logic_handler":handler_id,"handler":ReducerInstallHandler.new(),"bindings":[
			{"content_id":"FIXTURE_REDUCER_%d" % slot,"source_key":"A%d:WR13" % slot,"owner_key":"A%d" % slot,"kind":"talent","subscribes":["battle_start"]}]})
	var healing := _new_engine(); var heal_setup := healing.setup(_config({"A":0,"R":0,"hp_tenths":1000}), reducer_handlers)
	var opened := healing.step()
	var wounded := healing.fixture_apply([{"kind":"damage_batch","entries":[{"target_key":"B1","source_key":"A1","amount":200,"damage_type":"fire","root_id":"wound"}]}])
	var healed := healing.fixture_apply([{"kind":"heal","target":"B1","source":"A1","amount":1000}])
	var heal_event: Dictionary = {}
	for event in healed.events:
		if event.kind == "healed": heal_event = event
	var reductions: Array = heal_event.get("payload", {}).get("healing_reductions", [])
	var prevented_total := 0
	for reduction in reductions: prevented_total += int(reduction.amount)
	_check(heal_setup.error.is_empty() and opened.error.is_empty() and wounded.error.is_empty() and healed.error.is_empty(), "three-source WR13 setup/action errors")
	_check(prevented_total == 1000 and reductions.size() == 3 and reductions[0].source_binding_key == "A1:WR13" and reductions[0].amount == 334, "healing reduction reports capped actual amount and stable largest-remainder attribution: %s" % str(reductions))
	_check(healing.unit("B1").hp_tenths == 800, "120% summed healing reduction caps at 100%, no phantom prevented healing")
	_done()


func _test_b21_batch_event_phase_ordering() -> void:
	active_test = "B21"
	var engine := _new_engine(); engine.setup(_config({"A":10,"R":0,"T_ticks":6}))
	engine.state.teams.A[1].A = 0; engine.state.teams.A[2].A = 0
	engine.state.teams.B[1].A = 0; engine.state.teams.B[2].A = 0
	engine.step()
	engine.fixture_apply([
		{"kind":"shield_grant","target":"A1","source":"fixture:A","amount":50,"expires_tick":100},
		{"kind":"shield_grant","target":"B1","source":"fixture:B","amount":50,"expires_tick":100}
	])
	for _tick in range(1, 7): engine.step()
	var phases: Array[String] = []
	for event in engine.state.events:
		if int(event.get("tick", -1)) != 6: continue
		if str(event.kind) in ["hit", "hp_lost", "shield_absorbed", "shield_broken"]: phases.append(str(event.kind))
	var seen_hp := false; var seen_shield_absorb := false; var seen_shield_break := false
	var phase_ordered := true
	for kind in phases:
		if kind == "hit" and (seen_hp or seen_shield_absorb or seen_shield_break): phase_ordered = false
		if kind == "hp_lost":
			seen_hp = true
			if seen_shield_absorb or seen_shield_break: phase_ordered = false
		if kind == "shield_absorbed":
			seen_shield_absorb = true
			if seen_shield_break: phase_ordered = false
		if kind == "shield_broken": seen_shield_break = true
	_check(engine.state.error.is_empty(), "same-tick damage phase run error=%s" % engine.state.error)
	_check(phases.has("hit") and phases.has("hp_lost") and phases.has("shield_absorbed") and phases.has("shield_broken") and phase_ordered,
		"one batch emits all hit, then hp_lost, then shield_absorbed, then shield_broken; phases=%s" % str(phases))
	_done()


func _test_b22_fractional_attack_stat() -> void:
	active_test = "B22"
	var installer := ModifierOnStartHandler.new(); installer.target_key = "A1"; installer.stat = "A_tenths_flat"; installer.amount = 1
	var recorder := EventRecorder.new()
	var handlers := [
		{"logic_handler":"attack_tenths","handler":installer,"bindings":[{"content_id":"FIXTURE_A_TENTHS","source_key":"A1:fractional","owner_key":"A1","kind":"talent","subscribes":["battle_start"]}]},
		{"logic_handler":"record","handler":recorder,"bindings":[{"content_id":"FIXTURE_TENTHS_RECORD","source_key":"A2:record","owner_key":"A2","kind":"equipment","subscribes":["hit"]}]}
	]
	var engine := _new_engine(); var cfg := _config({"A":0,"R":0,"T_ticks":6,"hp_tenths":1000})
	var initialized := engine.setup(cfg, handlers)
	engine.state.teams.A[0].A = 1
	engine.step()
	engine.state.teams.A[1].A = 0; engine.state.teams.A[2].A = 0
	engine.state.teams.B[0].A = 0; engine.state.teams.B[1].A = 0; engine.state.teams.B[2].A = 0
	for _tick in range(1, 7): engine.step()
	var a1_hit: Dictionary = {}
	for event in recorder.seen:
		if event.kind == "hit" and event.source_key == "A1": a1_hit = event
	_check(initialized.error.is_empty() and engine.effective_stats("A1").A_tenths == 11, "A_tenths_flat exposes exact 0.1 A precision")
	_check(engine.unit("B1").hp_tenths == 989 and int(a1_hit.raw_amount) == 11, "11 tenths A becomes 11 actual raw damage; HP=%d raw=%d" % [engine.unit("B1").hp_tenths,int(a1_hit.get("raw_amount",-1))])
	_check(engine.state.error.is_empty(), "fractional attack run error=%s" % engine.state.error)
	_done()


func _test_b23_before_damage_reduction_composition() -> void:
	active_test = "B23"
	var base_modifier := ModifierOnStartHandler.new(); base_modifier.target_key = "A1"; base_modifier.stat = "damage_reduction_bp"; base_modifier.amount = 5000
	var hook := BeforeDamageReductionHandler.new(); hook.target_key = "A1"; hook.amount_bp = 2500
	var recorder := EventRecorder.new()
	var handlers := [
		{"logic_handler":"base_reduction","handler":base_modifier,"bindings":[{"content_id":"FIXTURE_BASE_REDUCTION","source_key":"A1:base_reduction","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]}]},
		{"logic_handler":"damage_hook","handler":hook,"bindings":[{"content_id":"FIXTURE_DAMAGE_HOOK","source_key":"A2:damage_hook","owner_key":"A2","kind":"equipment","subscribes":["before_damage"]}]},
		{"logic_handler":"record","handler":recorder,"bindings":[{"content_id":"FIXTURE_DAMAGE_RECORD","source_key":"A3:record","owner_key":"A3","kind":"equipment","subscribes":["hp_lost"]}]}
	]
	var engine := _new_engine(); var cfg := _config({"A":0,"R":0,"T_ticks":6,"hp_tenths":1000})
	var initialized := engine.setup(cfg, handlers)
	engine.state.teams.B[0].A = 10; engine.state.teams.B[0].damage_type = "fire"
	engine.state.teams.B[1].A = 0; engine.state.teams.B[2].A = 0
	for _tick in range(7): engine.step()
	var loss_event: Dictionary = {}
	for event in recorder.seen:
		if event.kind == "hp_lost" and event.source_key == "B1" and event.target_key == "A1": loss_event = event
	_check(initialized.error.is_empty() and int(loss_event.actual_hp_loss) == 25, "base50 plus hook25 reaches the shared reduction cap actual loss=%d" % int(loss_event.get("actual_hp_loss", -1)))
	_check(int(loss_event.payload.reduction) == 75 and engine.state.error.is_empty(), "reduction action participates before transfer/shields with audit amount=%d err=%s" % [int(loss_event.get("payload", {}).get("reduction", -1)),engine.state.error])
	_done()


func _test_b24_scheduled_counter_settlement_survives_silence() -> void:
	active_test = "B24"
	var handlers := [{"logic_handler":"scheduled_debt","handler":ScheduleDebtHandler.new(),"bindings":[
		{"content_id":"FIXTURE_DEBT","source_key":"A1:debt","owner_key":"A1","kind":"talent","subscribes":["battle_start"]}]}]
	var engine := _new_engine(); var initialized := engine.setup(_config({"A":0,"R":0,"T_ticks":1000,"hp_tenths":1000}), handlers)
	engine.set_counter("A1:debt", "loan_absorbed", 120)
	var start := engine.step()
	engine.fixture_apply([{"kind":"silence","target":"A1","expires_tick":10}])
	var due := engine.step()
	var settlement: Dictionary = {}
	for event in engine.state.events:
		if event.kind == "hp_lost" and event.target_key == "B1" and event.source_binding_key == "A1:debt": settlement = event
	_check(initialized.error.is_empty() and start.error.is_empty() and due.error.is_empty(), "counter settlement schedule setup/run error")
	_check(engine.unit("B1").hp_tenths == 940 and int(settlement.actual_hp_loss) == 60, "due counter liability reads dynamic value after owner silence and honors cap")
	_check(engine.get_counter("A1:debt", "loan_absorbed") == 0 and int(settlement.tick) == 1, "settlement is exactly once at due tick and clears counter")
	_done()


func _test_b25_same_root_shield_absorption_aggregation() -> void:
	active_test = "B25"
	var engine := _new_engine(); engine.setup(_config({"A":0,"R":0,"hp_tenths":1000}))
	engine.fixture_apply([{"kind":"shield_grant","target":"B1","source":"A1","source_binding_key":"A1:loan","amount":100,"expires_tick":100}])
	var result := engine.fixture_apply([{"kind":"damage_batch","entries":[
		{"target_key":"B1","source_key":"A1","source_binding_key":"A1:loan","amount":60,"damage_type":"fire","root_id":"one-attack-root","segment_index":1},
		{"target_key":"B1","source_key":"A1","source_binding_key":"A1:loan","amount":60,"damage_type":"fire","root_id":"one-attack-root","segment_index":2}]}])
	var absorbed: Array = []
	var broken: Array = []
	for event in result.events:
		if event.kind == "shield_absorbed": absorbed.append(event)
		if event.kind == "shield_broken": broken.append(event)
	_check(result.error.is_empty() and absorbed.size() == 1 and int(absorbed[0].payload.amount) == 100,
		"same-root same-pool shield absorption aggregates once at actual total; events=%s" % str(absorbed))
	_check(broken.size() == 1 and engine.unit("B1").hp_tenths == 980, "break emits once at depletion; remaining 20 tenths hit HP")
	_done()


func _test_b26_event_target_guard_preserves_fanout_and_blocks_cycle() -> void:
	active_test = "B26"
	var fanout := ScopedHealCycleHandler.new()
	var handlers := [{"logic_handler":"fx43_scope","handler":fanout,"bindings":[
		{"content_id":"FIXTURE_EVENT_TARGET_SCOPE","source_key":"A1:FX43","owner_key":"A1","kind":"equipment",
			"trigger_scope":"event_target","subscribes":["battle_start","healed"]}]}]
	var engine := _new_engine(); var cfg := _config({"A":0,"R":0,"T_ticks":1000,"hp_tenths":980})
	var initialized := engine.setup(cfg, handlers)
	var started := engine.step()
	var observed: Dictionary = {}
	for target_key in fanout.observed_targets: observed[target_key] = int(observed.get(target_key, 0)) + 1
	_check(initialized.error.is_empty() and started.error.is_empty(), "event-target guard setup/start must succeed")
	_check(int(observed.get("A2", 0)) == 1 and int(observed.get("A3", 0)) == 1,
		"one same-root group heal reaches both per-target listeners; targets=%s" % str(fanout.observed_targets))
	_check(engine.unit("A2").hp_tenths == 1000 and engine.unit("A3").hp_tenths == 1000,
		"event-target guard preserves sibling effects but the A2→A3→A2 causal cycle terminates")
	_check(engine.state.error.is_empty(), "event-target guard cycle error=%s" % engine.state.error)
	_done()


func _test_b27_one_life_health_floor_and_dynamic_revive_cap() -> void:
	active_test = "B27"
	var static_cfg := _config({"A":0,"R":0,"hp_tenths":50})
	static_cfg.teams.A[0].H = 5
	static_cfg.teams.A[0].setup_modifiers = [
		{"stat":"H_flat","amount":-12,"minimum":1,"current_hp_minimum":1},
		{"stat":"current_hp_delta_tenths","amount":-120}
	]
	var static_engine := _new_engine(); var static_result := static_engine.setup(static_cfg)
	_check(static_result.error.is_empty() and static_engine.effective_stats("A1").H_max_tenths == 10 and static_engine.unit("A1").hp_tenths == 10,
		"setup max/current HP floors at one full life after EQ12-style synchronized reduction")

	var shrink := HealthCapHandler.new(); shrink.hp_modifier = -200
	var shrink_bindings := [{"logic_handler":"health_cap","handler":shrink,"bindings":[
		{"content_id":"FIXTURE_HEALTH_SHRINK","source_key":"A1:health","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]}]}]
	var runtime_engine := _new_engine(); var runtime_init := runtime_engine.setup(_config({"A":0,"R":0,"T_ticks":1000}), shrink_bindings)
	var runtime_start := runtime_engine.step()
	_check(runtime_init.error.is_empty() and runtime_start.error.is_empty() and runtime_engine.effective_stats("B1").H_max_tenths == 10 and runtime_engine.unit("B1").hp_tenths == 10,
		"runtime max-HP reduction floors at one full life and immediately clamps current HP")

	var revive := HealthCapHandler.new(); revive.hp_modifier = 20; revive.damage_at_start = 2000; revive.revive_amount = 2000
	var revive_bindings := [{"logic_handler":"health_cap","handler":revive,"bindings":[
		{"content_id":"FIXTURE_HEALTH_MOD","source_key":"A1:health","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]},
		{"content_id":"FIXTURE_DYNAMIC_REVIVE","source_key":"A2:revive","owner_key":"A2","kind":"equipment","subscribes":["hp_lost"]}]}]
	var revived_engine := _new_engine(); var revive_init := revived_engine.setup(_config({"A":0,"R":0,"T_ticks":1000}), revive_bindings)
	var revive_start := revived_engine.step()
	_check(revive_init.error.is_empty() and revive_start.error.is_empty() and revived_engine.unit("B1").hp_tenths == 1200 and not revived_engine.unit("B1").dead,
		"revive amount is capped by the current dynamic maximum HP, not the pre-modifier snapshot")
	_done()


func _test_b28_status_removed_cycle_identity() -> void:
	active_test = "B28"
	var engine := _new_engine(); engine.setup(_config())
	var applied := engine.fixture_apply([{"kind":"status_add","target":"B1","status_id":"chill","layers":2,"expires_tick":30,"source":"A1"}])
	var cycle := int(applied.events.back().payload.status_cycle_id)
	var partial := engine.fixture_apply([{"kind":"status_remove","target":"B1","status_id":"chill","layers":1}])
	var partial_removed: Dictionary = {}
	for event in partial.events:
		if event.kind == "status_removed": partial_removed = event.payload
	var full := engine.fixture_apply([{"kind":"status_remove","target":"B1","status_id":"chill","layers":1}])
	var full_removed: Dictionary = {}
	for event in full.events:
		if event.kind == "status_removed": full_removed = event.payload
	_check(partial.error.is_empty() and partial_removed.get("removed_cycle_ids", []).is_empty(), "partial stack removal does not end a status cycle")
	_check(full.error.is_empty() and full_removed.get("removed_cycle_ids", []) == [cycle] and int(full_removed.get("status_cycle_id", 0)) == cycle,
		"complete status removal exposes exact status_cycle_id for peer de-duplication")
	_done()


func _test_b29_attack_segment_identity_and_barrier_absorption() -> void:
	active_test = "B29"
	var type_patcher := AttackSegmentHandlers.new(); type_patcher.patch_type = true
	var segment_appender := AttackSegmentHandlers.new()
	var recorder := EventRecorder.new()
	var handlers := [
		{"logic_handler":"main_type","handler":type_patcher,"bindings":[{"content_id":"FIXTURE_MAIN_TYPE","source_key":"A1:WR05","owner_key":"A1","kind":"talent","subscribes":["before_hit"]}]},
		{"logic_handler":"append_ice","handler":segment_appender,"bindings":[{"content_id":"FIXTURE_APPEND_ICE","source_key":"global:PE08","owner_key":"","kind":"public","subscribes":["before_hit"]}]},
		{"logic_handler":"record","handler":recorder,"bindings":[{"content_id":"FIXTURE_ATTACK_RECORD","source_key":"A3:record","owner_key":"A3","kind":"equipment","subscribes":["hit","barrier_absorbed"]}]}
	]
	var engine := _new_engine(); var initialized := engine.setup(_config({"A":0,"R":0,"T_ticks":6}), handlers)
	engine.state.teams.A[0].A = 10
	engine.state.teams.A[1].A = 0; engine.state.teams.A[2].A = 0
	engine.state.teams.B[0].A = 0; engine.state.teams.B[1].A = 0; engine.state.teams.B[2].A = 0
	engine.fixture_apply([{"kind":"barrier_grant","target":"B1","source":"FIXTURE_BARRIER","expires_tick":100}])
	for _tick in range(7): engine.step()
	var attack_hits: Array = []; var barrier_events: Array = []
	for event in recorder.seen:
		if event.kind == "hit" and event.source_key == "A1": attack_hits.append(event)
		if event.kind == "barrier_absorbed": barrier_events.append(event)
	var hit_types: Array[String] = []
	for event in attack_hits: hit_types.append(str(event.damage_type))
	var attack_id := str(attack_hits[0].get("attack_id", "")) if not attack_hits.is_empty() else ""
	var same_attack_id := not attack_id.is_empty()
	for event in attack_hits:
		if str(event.get("attack_id", "")) != attack_id: same_attack_id = false
	_check(initialized.error.is_empty() and engine.state.error.is_empty(), "segment/barrier pipeline errors=%s" % engine.state.error)
	_check(attack_hits.size() == 2 and hit_types == ["fire", "ice"] and same_attack_id,
		"main type patch changes only the main segment; appended ice segment has stable same-attack ID: %s" % str(attack_hits))
	_check(barrier_events.size() == 1 and int(barrier_events[0].get("barrier_absorbed", 0)) == 100
		and str(barrier_events[0].get("payload", {}).get("barrier_source_key", "")) == "FIXTURE_BARRIER",
		"fully absorbed attack emits a source-attributed barrier_absorbed fact")
	_check(engine.unit("B1").hp_tenths == 990, "barrier consumes only first segment; appended ice segment independently removes one HP")
	_done()


func _test_b30_dot_modifier_and_selective_expiry_suppression() -> void:
	active_test = "B30"
	var dot_modifier := StatusEnvironmentHandlers.new()
	var apply_statuses := StatusApplyHandlers.new()
	var suppress_poison := PoisonExpirySuppressHandler.new()
	var handlers := [
		{"logic_handler":"status_environment","handler":dot_modifier,"bindings":[{"content_id":"FIXTURE_BURN_DOUBLE","source_key":"global:PE02","owner_key":"","kind":"public","subscribes":["battle_start"]}]},
		{"logic_handler":"status_apply","handler":apply_statuses,"bindings":[{"content_id":"FIXTURE_STATUS_APPLY","source_key":"A1:status_apply","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]}]},
		{"logic_handler":"suppress_poison","handler":suppress_poison,"bindings":[{"content_id":"FIXTURE_POISON_NO_EXPIRY","source_key":"global:PE04","owner_key":"","kind":"public","subscribes":["status_applied"]}]}
	]
	var engine := _new_engine(); var initialized := engine.setup(_config({"A":0,"R":0,"T_ticks":1000}), handlers)
	for _tick in range(11): engine.step()
	var burn_active := false; var poison_active := false; var poison_expiry := 0
	for status in engine.unit("B1").statuses:
		if str(status.id) == "burn": burn_active = true
	for status in engine.unit("B2").statuses:
		if str(status.id) == "poison": poison_active = true; poison_expiry = int(status.expires_tick)
	_check(initialized.error.is_empty() and engine.state.error.is_empty(), "dot modifier/expiry suppression errors=%s" % engine.state.error)
	_check(engine.unit("B1").hp_tenths == 980 and not burn_active, "burn tick modifier doubles only periodic burn to two life; dot endpoint then expires")
	_check(engine.unit("B2").hp_tenths == 990 and poison_active and poison_expiry == -1,
		"poison expiry suppression is status-selective, preserves periodic damage, and cleanse remains available")
	_done()


func _test_b31_result_content_coverage_copy() -> void:
	active_test = "B31"
	var engine := _new_engine()
	var initialized := engine.setup(_config())
	var coverage: Dictionary = initialized.get("content_coverage", {})
	var fixture_ids: Array = coverage.get("fixture_ids", [])
	_check(initialized.error.is_empty() and fixture_ids.size() == 6,
		"successful setup result exposes fixture content coverage")
	fixture_ids.clear()
	_check(engine.state.content_coverage.fixture_ids.size() == 6,
		"result content_coverage is a deep copy, not mutable engine state")
	var invalid := _new_engine().setup({"test_fixture":true,"teams":{"A":[],"B":[]}})
	_check(not invalid.error.is_empty() and invalid.get("content_coverage", null) is Dictionary
		and invalid.content_coverage.is_empty(), "error result exposes empty content_coverage")
	_done()


func _test_b32_root_transfer_cap_and_shield_only_damage() -> void:
	active_test = "B32"
	var engine := _new_engine(); engine.setup(_config())
	var registered := engine.fixture_apply([
		{"kind":"redirect_register","target":"A1","source":"A3:EQ14","source_binding_key":"A3:EQ14","redirect_id":"eq14-root","ratio_bp":5000,"capacity_per_root":60,"recipient_keys":["A3"]},
		{"kind":"redirect_register","target":"A2","source":"A3:EQ14","source_binding_key":"A3:EQ14","redirect_id":"eq14-root","ratio_bp":5000,"capacity_per_root":60,"recipient_keys":["A3"]}
	])
	var root_batch := engine.fixture_apply([{"kind":"damage_batch","entries":[
		{"target_key":"A1","source_key":"B1","amount":100,"damage_type":"fixed","root_id":"shared-root"},
		{"target_key":"A2","source_key":"B1","amount":100,"damage_type":"fixed","root_id":"shared-root"}
	]}])
	var redirected := 0
	for event in root_batch.events:
		if event.kind == "hp_lost" and str(event.target_key) == "A3" and bool(event.get("payload", {}).get("is_redirected", false)):
			redirected += int(event.get("payload", {}).get("transferred", 0))
	_check(registered.error.is_empty() and root_batch.error.is_empty() and redirected == 60,
		"capacity_per_root shares one 60-tenths cap across sorted protected targets; moved=%d" % redirected)
	_check(engine.unit("A1").hp_tenths == 950 and engine.unit("A2").hp_tenths == 910 and engine.unit("A3").hp_tenths == 940,
		"redirect portion order is stable by target key and never exceeds shared root cap")
	var shield_target := engine.unit("B1")
	var hp_before := int(shield_target.hp_tenths)
	engine.fixture_apply([{"kind":"shield_grant","target":"B1","source":"fixture_shield","amount":30,"expires_tick":100}])
	var shield_only := engine.fixture_apply([{"kind":"damage_batch","entries":[
		{"target_key":"B1","source_key":"A1","amount":80,"damage_type":"fixed","root_id":"shield-only-root","shield_only":true}
	]}])
	_check(shield_only.error.is_empty() and int(engine.unit("B1").hp_tenths) == hp_before and engine.shield_amount("B1") == 0
		and _sum_actual_loss(shield_only.events, "B1") == 0,
		"shield_only damage consumes available shield then discards overflow without HP loss")
	_check(_count_kind(shield_only.events, "shield_absorbed") == 1 and _count_kind(shield_only.events, "hp_lost") == 0,
		"shield-only packet emits its shield absorption but no hp_lost event")
	var step_handler := RedirectCapStepHandler.new()
	var step_bindings := [{"logic_handler":"redirect_cap_step","handler":step_handler,"bindings":[
		{"content_id":"FIXTURE_STEP_REDIRECT_CAP","source_key":"A3:step_cap","owner_key":"A3","kind":"equipment","subscribes":["battle_start"]}]}]
	var real := _new_engine(); var real_setup := real.setup(_config({"A":0,"R":0,"T_ticks":1000}), step_bindings)
	var real_step := real.step()
	_check(real_setup.error.is_empty() and real_step.error.is_empty() and real.unit("A3").hp_tenths == 940
		and real.unit("A1").hp_tenths == 950 and real.unit("A2").hp_tenths == 910,
		"real battle_start actions share the same 6-life root cap across both protected units")
	_check(real.unit("B1").hp_tenths == 1000 and real.shield_amount("B1") == 0
		and _sum_actual_loss(real_step.events, "B1") == 0,
		"production damage action shield_only consumes shield but never overflows to HP")
	_done()


func _test_b33_shield_pool_selection_equal_transfer_and_provenance() -> void:
	active_test = "B33"
	var engine := _new_engine(); engine.setup(_config())
	var setup := engine.fixture_apply([
		{"kind":"shield_grant","target":"A1","source":"A2:pool","source_binding_key":"A2:pool","amount":70,"expires_tick":30,"pool_mode":"new"},
		{"kind":"shield_grant","target":"A1","source":"A2:pool","source_binding_key":"A2:pool","amount":20,"expires_tick":50,"pool_mode":"new"}
	])
	var pools: Array = engine.unit("A1").shield_pools.duplicate(true)
	var second_pool_id := str(pools[1].get("pool_id", "")) if pools.size() > 1 else ""
	var by_source := engine.fixture_apply([{"kind":"shield_transfer","from_target_key":"A1","recipient_keys":["A2","A3"],
		"amount":60,"pool_source_binding_key":"A2:pool"}])
	var selected_pool := engine.fixture_apply([{"kind":"shield_transfer","from_target_key":"A1","recipient_keys":["A2","A3"],
		"amount":13,"pool_id":second_pool_id}])
	var a2_pools: Array = engine.unit("A2").shield_pools
	var a3_pools: Array = engine.unit("A3").shield_pools
	var source_expiries: Array[int] = []; var source_amounts: Array[int] = []
	for unit_pools in [a2_pools,a3_pools]:
		for pool in unit_pools:
			if str(pool.get("source_binding_key", "")) == "A2:pool":
				source_expiries.append(int(pool.expires_tick)); source_amounts.append(int(pool.amount))
	var recipient_totals := [engine.shield_amount("A2", "A2:pool"),engine.shield_amount("A3", "A2:pool")]
	_check(setup.error.is_empty() and by_source.error.is_empty() and selected_pool.error.is_empty()
		and recipient_totals == [37,36], "selected shield pools distribute exactly and evenly with stable one-tenth remainder: %s" % str(recipient_totals))
	_check(source_expiries.count(30) == 2 and source_expiries.count(50) == 2
		and source_amounts.count(30) == 2 and source_amounts.count(7) == 1 and source_amounts.count(6) == 1,
		"source-bound pools preserve distinct expiry and pool-ID selection across recipients: %s/%s" % [str(source_expiries),str(source_amounts)])
	_check(engine.shield_amount("A1", "A2:pool") == 17,
		"transfer debits only selected source amounts, leaving unmatched same-source expiry pool untouched")

	var provenance := _new_engine(); provenance.setup(_config())
	var healing := provenance.fixture_apply([{"kind":"heal","target":"A1","source":"A2","source_binding_key":"A2:heal","amount":10}])
	provenance.fixture_apply([
		{"kind":"shield_grant","target":"A1","source":"A2","source_binding_key":"A2:shield","amount":10,"expires_tick":1},
		{"kind":"barrier_grant","target":"A2","source":"A2","source_binding_key":"A2:barrier","expires_tick":1}
	])
	provenance.step()
	var expiry_result := provenance.step()
	var expiry_keys: Array[String] = []
	for event in expiry_result.events:
		if event.kind == "expiry": expiry_keys.append(str(event.get("payload", {}).get("source_binding_key", "")))
	_check(healing.error.is_empty() and _count_kind(healing.events, "healed") == 1
		and str(healing.events.back().get("payload", {}).get("source_binding_key", "")) == "A2:heal",
		"healed event identifies the acting source binding")
	_check(expiry_keys.has("A2:shield") and expiry_keys.has("A2:barrier"),
		"shield and barrier expiry events retain their distinct source binding keys: %s" % str(expiry_keys))
	var transfer_handler := ShieldPoolTransferStepHandler.new()
	var transfer_bindings := [{"logic_handler":"pool_transfer_step","handler":transfer_handler,"bindings":[
		{"content_id":"FIXTURE_STEP_POOL_TRANSFER","source_key":"A1:pool_transfer","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]}]}]
	var real_transfer := _new_engine(); var transfer_setup := real_transfer.setup(_config({"A":0,"R":0,"T_ticks":1000}), transfer_bindings)
	var transfer_start := real_transfer.step()
	_check(transfer_setup.error.is_empty() and transfer_start.error.is_empty()
		and real_transfer.shield_amount("A2", "A1:pool") == 7 and real_transfer.shield_amount("A3", "A1:pool") == 6,
		"real shield_transfer accepts recipient_keys and apportions the tenth-point remainder by sorted unit key")
	_check(real_transfer.shield_amount("A1", "A1:pool") == 17
		and int(real_transfer.unit("A2").shield_pools[0].expires_tick) == 30 and int(real_transfer.unit("A3").shield_pools[0].expires_tick) == 30,
		"real multi-recipient transfer preserves source binding and selected source-pool expiry")
	_done()


func _test_b34_delayed_shield_refill_cancels_on_refresh() -> void:
	active_test = "B34"
	var source := InitialShieldGrantHandler.new(); var delayed := SplitShieldDelayHandler.new()
	var handlers := [
		{"logic_handler":"shield_source","handler":source,"bindings":[{"content_id":"FIXTURE_SHIELD_SOURCE","source_key":"A1:source","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]}]},
		{"logic_handler":"split_delay","handler":delayed,"bindings":[{"content_id":"FIXTURE_SHIELD_DELAY","source_key":"A2:delay","owner_key":"A2","kind":"equipment","subscribes":["shield_gained"]}]}
	]
	var engine := _new_engine(); var initialized := engine.setup(_config({"A":0,"R":0,"T_ticks":1000}), handlers)
	for _i in range(60):
		if not engine.state.queue.is_empty(): break
		engine.step()
	var due_tick := int(engine.state.queue[0].tick) if not engine.state.queue.is_empty() else int(engine.state.tick)
	while int(engine.state.tick) <= due_tick and not engine.state.queue.is_empty(): engine.step()
	_check(initialized.error.is_empty() and engine.state.error.is_empty() and engine.shield_amount("A1", "A1:pool_owner") == 100,
		"delayed same-pool amount adds at exact due tick while preserving original pool")

	delayed = SplitShieldDelayHandler.new()
	handlers[1]["handler"] = delayed
	var refreshed := _new_engine(); var refreshed_setup := refreshed.setup(_config({"A":0,"R":0,"T_ticks":1000}), handlers)
	for _i in range(60):
		if not refreshed.state.queue.is_empty(): break
		refreshed.step()
	var refreshed_due_tick := int(refreshed.state.queue[0].tick) if not refreshed.state.queue.is_empty() else int(refreshed.state.tick)
	while int(refreshed.state.tick) < refreshed_due_tick: refreshed.step()
	var refresh_result := refreshed.fixture_apply([{"kind":"shield_grant","target":"A1","source":"A1","source_binding_key":"A1:pool_owner",
		"amount":80,"expires_tick":100,"pool_mode":"refresh"}])
	refreshed.step()
	_check(refreshed_setup.error.is_empty() and refresh_result.error.is_empty() and refreshed.state.error.is_empty()
		and refreshed.shield_amount("A1", "A1:pool_owner") == 80,
		"new pool revision cancels stale scheduled refill instead of duplicating replaced shield")
	delayed = SplitShieldDelayHandler.new(); handlers[1]["handler"] = delayed
	var departed := _new_engine(); var departed_setup := departed.setup(_config({"A":0,"R":0,"T_ticks":1000}), handlers)
	for _i in range(60):
		if not departed.state.queue.is_empty(): break
		departed.step()
	var departed_due := int(departed.state.queue[0].tick) if not departed.state.queue.is_empty() else int(departed.state.tick)
	departed.fixture_apply([{"kind":"damage","target":"A1","source":"B1","amount":2000,"damage_type":"fixed"}])
	while int(departed.state.tick) <= departed_due and not departed.state.queue.is_empty(): departed.step()
	_check(departed_setup.error.is_empty() and departed.state.error.is_empty() and departed.unit("A1").final_departed
		and departed.shield_amount("A1", "A1:pool_owner") == 0 and departed.state.queue.is_empty(),
		"final departure removes the original shield and queued refill without recreating a pool")
	_done()


func _test_b35_correlated_attack_multitarget_and_consume_on_hit() -> void:
	active_test = "B35"
	var patcher := AttackCorrelationHandler.new(); var recorder := AttackResolvedRecorder.new()
	var handlers := [
		{"logic_handler":"attack_patch","handler":patcher,"bindings":[{"content_id":"FIXTURE_CORRELATED_ATTACK","source_key":"A1:correlate","owner_key":"A1","kind":"equipment","subscribes":["before_hit"]}]},
		{"logic_handler":"attack_record","handler":recorder,"bindings":[{"content_id":"FIXTURE_ATTACK_RESULT","source_key":"global:record_attack","owner_key":"","kind":"public","subscribes":["attack_resolved"]}]}
	]
	var engine := _new_engine(); var initialized := engine.setup(_config({"A":10,"R":0,"T_ticks":6}), handlers)
	engine.set_counter("A1:correlate", "armed", 2)
	for _i in range(7): engine.step()
	var result_event: Dictionary = recorder.seen[0] if not recorder.seen.is_empty() else {}
	var result_payload: Dictionary = result_event.get("payload", {})
	_check(initialized.error.is_empty() and engine.state.error.is_empty() and recorder.seen.size() == 1,
		"real natural attack emits exactly one correlated attack_resolved fact")
	_check(int(result_payload.get("segment_count", 0)) == 3 and result_payload.get("target_keys", []) == ["B1","B2","B3"]
		and int(result_payload.get("actual_target_count", 0)) == 3 and int(result_payload.get("total_actual_hp_loss", 0)) == 150,
		"attack aggregate correlates main, added segment, and attached damage across targets: %s" % JSON.stringify(result_payload))
	_check(engine.get_counter("A1:correlate", "armed") == 1,
		"consume_on_hit debits the source counter once after any attack segment actually hits")

	patcher = AttackCorrelationHandler.new(); patcher.suppress = true
	handlers[0]["handler"] = patcher
	var stopped := _new_engine(); var stopped_setup := stopped.setup(_config({"A":10,"R":0,"T_ticks":6}), handlers)
	stopped.set_counter("A1:correlate", "armed", 2)
	for _i in range(7): stopped.step()
	_check(stopped_setup.error.is_empty() and stopped.state.error.is_empty() and stopped.get_counter("A1:correlate", "armed") == 2
		and _sum_actual_loss(stopped.state.events, "B1") == 0,
		"suppressed prepared attack emits no hit and does not consume its armed bonus")
	_done()


func _test_b36_fast_sim_preserves_outcome_and_events() -> void:
	active_test = "B36"
	var config := _config({"A":10,"R":0,"T_ticks":20,"seed":97})
	var detailed := _new_engine().simulate(config)
	var fast := _new_engine().simulate(config, [], {"capture_tick_hashes":false})
	_check(detailed.error.is_empty() and fast.error.is_empty() and bool(detailed.terminal) and bool(fast.terminal)
		and detailed.winner == fast.winner and int(detailed.snapshot.tick) == int(fast.snapshot.tick),
		"fast simulation preserves terminal winner and end tick")
	_check(detailed.state_hash == fast.state_hash and detailed.events.size() == fast.events.size(),
		"fast simulation preserves final deterministic state hash and every event")
	_check(not detailed.tick_hashes.is_empty() and fast.tick_hashes.is_empty(),
		"full verification keeps per-tick hashes by default; AI fast mode omits only that evidence")
	var invalid := _new_engine().simulate(config, [], {"unknown":true})
	_check(not invalid.error.is_empty() and invalid.content_coverage.is_empty(), "unknown simulate option is rejected explicitly")
	_done()


func _test_b37_public_ai_capture_and_read_apis() -> void:
	active_test = "B37"
	var config := _config({"A":10,"R":0,"T_ticks":20,"seed":197})
	var from_setup := _new_engine()
	var initialized := from_setup.setup(config, [], {"capture_tick_hashes":false})
	_check(initialized.error.is_empty() and from_setup.state.tick_hashes.is_empty(),
		"setup option disables only tick hash capture")
	var setter_engine := _new_engine()
	var setter_setup := setter_engine.setup(config)
	var changed := setter_engine.set_capture_tick_hashes(false)
	_check(setter_setup.error.is_empty() and changed.error.is_empty() and setter_engine.state.tick_hashes.is_empty(),
		"public setter disables tick hashes without direct state mutation")
	var tick_result := from_setup.step(false)
	var public_snapshot := from_setup.snapshot()
	var public_result := from_setup.result()
	if not public_snapshot.teams.A.is_empty(): public_snapshot.teams.A[0].hp_tenths = -999
	_check(tick_result.error.is_empty() and not from_setup.state.teams.A.is_empty()
		and int(from_setup.state.teams.A[0].hp_tenths) >= 0,
		"step(false) returns usable current events and public snapshot is defensive")
	var full := _new_engine().simulate(config)
	var fast := _new_engine().simulate(config, [], {"capture_tick_hashes":false})
	_check(public_result.error.is_empty() and full.error.is_empty() and fast.error.is_empty()
		and full.events == fast.events and full.state_hash == fast.state_hash
		and full.winner == fast.winner and int(full.snapshot.tick) == int(fast.snapshot.tick),
		"public setup fast mode preserves complete final events, state hash, winner and end tick")
	var invalid := _new_engine().setup(config, [], {"capture_history":false})
	_check(not invalid.error.is_empty(), "unsupported history option is rejected instead of silently changing handler visibility")
	_done()


func _test_b38_segment_hit_shield_snapshot() -> void:
	active_test = "B38"
	var handler := ShieldSegmentObservationHandler.new()
	var handlers := [{"logic_handler":"segment_shield","handler":handler,"bindings":[
		{"content_id":"FIXTURE_SEGMENT_SHIELD","source_key":"A1:eq32_setup","owner_key":"A1","kind":"equipment","subscribes":["battle_start","before_hit"]},
		{"content_id":"FIXTURE_SEGMENT_SHIELD_OBSERVER","source_key":"A1:eq32_observer","owner_key":"A1","kind":"equipment","subscribes":["hit"]}]}]
	var engine := _new_engine()
	var initialized := engine.setup(_config({"A":10,"R":0,"T_ticks":6}), handlers)
	for _i in range(7): engine.step()
	_check(initialized.error.is_empty() and engine.state.error.is_empty() and handler.seen == [150,0],
		"each correlated hit exposes target shield immediately after its own segment settles, not final batch shield: %s" % str(handler.seen))
	_done()


func _test_b39_attached_source_unit_override() -> void:
	active_test = "B39"
	var handler := AttachedSourceOverrideHandler.new()
	var handlers := [{"logic_handler":"fx11_source","handler":handler,"bindings":[
		{"content_id":"FIXTURE_FX11_SOURCE","source_key":"A1:fx11","owner_key":"A1","kind":"slot","subscribes":["before_hit"]}]}]
	var engine := _new_engine()
	var initialized := engine.setup(_config({"A":10,"R":0,"T_ticks":6}), handlers)
	for _i in range(7): engine.step()
	var found := false
	for event in engine.state.events:
		if event.kind != "hp_lost" or not bool(event.get("payload", {}).get("is_attached_damage", false)): continue
		if str(event.get("source_key", "")) == "A2" and str(event.get("source_binding_key", "")) == "A1:fx11" \
			and not bool(event.get("is_attack", false)) and str(event.get("attack_id", "")).contains("natural"):
			found = true
	_check(initialized.error.is_empty() and engine.state.error.is_empty() and found,
		"attached damage attributes source unit to selected attacker while retaining card binding and attack lineage")
	_done()


func _config(overrides: Dictionary = {}) -> Dictionary:
	var unit_overrides: Dictionary = overrides.duplicate(true)
	unit_overrides.erase("rule_id"); unit_overrides.erase("seed"); unit_overrides.erase("hp_tenths"); unit_overrides.erase("silence_owner")
	var sides := {"A":[],"B":[]}
	for side in ["A","B"]:
		for slot in [1,2,3]:
			var unit := {"definition_id":"FIXTURE_%s%d" % [side,slot],"fixture":true,"slot":slot,"H":100,"A":0,"T_ticks":6,"R":6,"reach":"melee","armor_kind":"medium","target_slot":1}
			unit.merge(unit_overrides, true)
			if overrides.has("hp_tenths"): unit["hp_tenths"] = int(overrides.hp_tenths)
			sides[side].append(unit)
	var config := {"test_fixture":true,"seed":int(overrides.get("seed",1)),"rule_id":str(overrides.get("rule_id","VC01")),"teams":sides,"arena_id":"FIXTURE_ARENA","public_effect_ids":[]}
	return config


func _new_engine(_ignored: Dictionary = {}) -> BattleEngine:
	return EngineScript.new()


func _check(condition: bool, message: String) -> void:
	if condition: passed += 1
	else:
		failed += 1
		lines.append("FAIL %s: %s" % [active_test,message])


func _done() -> void:
	if lines.is_empty() or not lines.back().begins_with("FAIL %s:" % active_test): lines.append("PASS %s" % active_test)


func _count_kind(events: Array, kind: String) -> int:
	var count := 0
	for event in events:
		if str(event.get("kind", "")) == kind: count += 1
	return count


func _status_layers(statuses: Array, id: String) -> int:
	var total := 0
	for status in statuses:
		if str(status.id) == id: total += int(status.layers)
	return total


func _count_source(statuses: Array, id: String, source: String) -> int:
	var total := 0
	for status in statuses:
		if str(status.id) == id and str(status.source_key) == source: total += int(status.layers)
	return total


func _sum_actual_loss(events: Array, target: String) -> int:
	var total := 0
	for event in events:
		if event.kind == "hp_lost" and event.target_key == target: total += int(event.actual_hp_loss)
	return total
