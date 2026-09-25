extends SceneTree

# Independent integration review. Do not change expected values to fit engine output.
const Battle = preload("res://core/battle/battle_engine.gd")
var passed := 0
var failures: Array[String] = []
var completed_tests := 0

class Effects extends RefCounted:
	var mode := ""
	func on_event(engine, _binding: Dictionary, event: Dictionary) -> Array:
		if mode == "pierce" and event.kind == "prepare_attack" and event.source_key == "A1":
			return [{"kind":"attack_patch", "attack_id":event.payload.attack_id,
				"patch":{"armor_piercing":4}}]
		if mode == "shield" and event.kind == "battle_start":
			return [{"kind":"shield_grant", "target_key":"B1", "amount":30,"expires_tick":100}]
		if mode == "heal_before" and event.kind == "periodic" and event.tick == 6:
			return [{"kind":"heal", "target_key":"A1", "amount":50}]
		if mode == "heal_after" and event.kind == "hp_lost" and event.target_key == "A1":
			return [{"kind":"heal", "target_key":"A1", "amount":50}]
		if mode == "redirect" and event.kind == "battle_start":
			return [{"kind":"redirect_register", "target_key":"A1", "ratio_bp":3000,
				"recipient_keys":["A2"], "capacity_per_second":1000}]
		if mode == "slow" and event.kind == "battle_start":
			return [{"kind":"status_add","target_key":"A1","status_id":"chill","expires_tick":100},
				{"kind":"modifier_add","target_key":"A1","stat":"T_ticks_percent","amount":3500,"expires_tick":100}]
		if mode in ["mixed_speed", "mixed_speed_reverse"] and event.kind == "battle_start":
			var actions: Array = []
			var rates := [2500, 3500, -2000]
			if mode == "mixed_speed_reverse": rates.reverse()
			for i in range(rates.size()):
				actions.append({"kind":"modifier_add","target_key":"A1","stat":"T_ticks_percent",
					"amount":rates[i],"modifier_id":"review_speed_%d" % i,"expires_tick":100})
			return actions
		return []

func _init() -> void:
	var battle_resource: Script = load("res://core/battle/battle_engine.gd")
	if battle_resource == null or not battle_resource.can_instantiate():
		print("ASTRA_BATTLE_REVIEW compile/dependency failure")
		quit(1)
		return
	_test_real_attacks()
	_test_partial_armor_ignore()
	_test_single_shield_break()
	_test_heal_order()
	_test_transfer_not_hit()
	_test_deadline_no_attack()
	_test_armor_floor_and_slow_rounding()
	_test_speed_order_independent()
	_check(completed_tests == 8, "all eight test bodies completed, count=%d" % completed_tests)
	for failure in failures: print("FAIL: ", failure)
	print("ASTRA_BATTLE_REVIEW passed=%d failed=%d" % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _config() -> Dictionary:
	var config := {"test_fixture":true,"seed":937,"rule_id":"VC21","teams":{"A":[],"B":[]}}
	for side in ["A","B"]:
		for slot in [1,2,3]:
			config.teams[side].append({"definition_id":"FIXTURE_%s%d" % [side,slot],
				"fixture":true,"slot":slot,"H":100,"A":10,"T_ticks":6,"R":0,
				"reach":"ranged","armor_kind":"medium","target_slot":slot})
	return config

func _handlers(mode: String) -> Array:
	var handler := Effects.new()
	handler.mode = mode
	return [{"logic_handler":"review", "handler":handler,
		"bindings":[{"content_id":"FIXTURE_REVIEW", "owner_key":"A1",
			"source_key":"A1:review", "kind":"equipment"}]}]

func _advance(engine, count: int) -> Array:
	var events: Array = []
	for i in range(count):
		var result: Dictionary = engine.step()
		_check(str(result.get("error", "")).is_empty(), "step %d error=%s" % [i,result.get("error", "")])
		if not str(result.get("error", "")).is_empty(): break
		events.append_array(result.events)
	return events

func _test_real_attacks() -> void:
	var engine = Battle.new()
	engine.setup(_config())
	var events := _advance(engine,7)
	_check(_count(events,"prepare_attack",0) == 6, "all six units actually start preparation at tick zero")
	_check(_count(events,"hit",6) == 6, "six scheduled attacks really hit at tick six")
	for key in ["A1","A2","A3","B1","B2","B3"]:
		_check(engine.unit(key).hp_tenths == 900, "real attack damages %s once, hp=%s" % [key,engine.unit(key).hp_tenths])
	var later := _advance(engine,6)
	_check(_count(later,"hit",12) == 6, "second attacks at tick twelve, not canceled/restarted each tick")
	completed_tests += 1

func _test_partial_armor_ignore() -> void:
	var config := _config()
	config.teams.B[0].R = 6
	var engine = Battle.new()
	engine.setup(config,_handlers("pierce"))
	_advance(engine,7)
	_check(engine.unit("B1").hp_tenths == 920, "10 physical ignores 4 of R6: exactly 8 HP, hp=%s" % engine.unit("B1").hp_tenths)
	completed_tests += 1

func _test_single_shield_break() -> void:
	var config := _config()
	for unit in config.teams.A:
		unit.A = 1
		unit.target_slot = 1
	for unit in config.teams.B: unit.A = 0
	var engine = Battle.new()
	engine.setup(config,_handlers("shield"))
	var events := _advance(engine,7)
	_check(_count(events,"shield_broken",6) == 1, "three packets empty one shield once, not three break triggers")
	_check(engine.unit("B1").hp_tenths == 1000, "3-point shield blocks three 1-point attacks")
	completed_tests += 1

func _test_heal_order() -> void:
	for mode in ["heal_before","heal_after"]:
		var config := _config()
		for unit in config.teams.A: unit.A = 0
		for unit in config.teams.B: unit.A = 0
		config.teams.A[0].H = 20
		config.teams.A[0].hp_tenths = 100
		config.teams.B[0].A = 12
		var engine = Battle.new()
		engine.setup(config,_handlers(mode))
		_advance(engine,7)
		var expected := 30 if mode == "heal_before" else 0
		_check(engine.unit("A1").hp_tenths == expected, "%s: expected %d tenths, got %d" % [mode,expected,engine.unit("A1").hp_tenths])
	completed_tests += 1

func _test_transfer_not_hit() -> void:
	var config := _config()
	for unit in config.teams.A: unit.A = 0
	for unit in config.teams.B: unit.A = 0
	config.teams.B[0].A = 10
	var engine = Battle.new()
	engine.setup(config,_handlers("redirect"))
	var events := _advance(engine,7)
	_check(engine.unit("A1").hp_tenths == 930 and engine.unit("A2").hp_tenths == 970, "one-pass 30% transfer uses real engine")
	var hits_on_receiver := 0
	for event in events:
		if event.kind == "hit" and event.source_key == "B1" and event.target_key == "A2": hits_on_receiver += 1
	_check(hits_on_receiver == 0, "transfer receiver loses HP but is not directly attacked")
	completed_tests += 1

func _test_deadline_no_attack() -> void:
	var config := _config()
	for side in ["A","B"]:
		for unit in config.teams[side]: unit.T_ticks = 120
	var result: Dictionary = Battle.new().simulate(config)
	_check(str(result.get("error", "")).is_empty() and result.terminal, "deadline simulation actually terminates")
	_check(_count(result.events,"hit",120) == 0, "VC21 endpoint tick 120 adjudicates without landing scheduled attacks")
	_check(result.snapshot.teams.A[0].hp_tenths == 1000, "no phantom endpoint damage")
	completed_tests += 1

func _count(events: Array, kind: String, tick: int) -> int:
	var count := 0
	for event in events:
		if event.kind == kind and event.tick == tick: count += 1
	return count

func _test_armor_floor_and_slow_rounding() -> void:
	var config := _config()
	config.teams.B[0].R = 100
	var engine = Battle.new()
	engine.setup(config)
	_advance(engine,7)
	_check(engine.unit("B1").hp_tenths == 990, "physical armor leaves 1 HP damage, not 0.1 HP")
	config = _config()
	config.teams.A[0].T_ticks = 7
	var slowed = Battle.new()
	slowed.setup(config,_handlers("slow"))
	slowed.step()
	_check(slowed.unit("A1").next_attack_tick == 10, "7 ticks × strongest slow 1.35 rounds upward to 10, not stacked/floored")
	completed_tests += 1

func _check(condition: bool, message: String) -> void:
	if condition: passed += 1
	else: failures.append(message)

func _test_speed_order_independent() -> void:
	for mode in ["mixed_speed", "mixed_speed_reverse"]:
		var config := _config()
		config.teams.A[0].T_ticks = 20
		var engine = Battle.new()
		var initialized: Dictionary = engine.setup(config, _handlers(mode))
		_check(str(initialized.get("error", "")).is_empty(), "mixed-speed setup succeeds")
		var first: Dictionary = engine.step()
		_check(str(first.get("error", "")).is_empty(), "mixed-speed step succeeds")
		_check(engine.unit("A1").next_attack_tick == 23,
			"%s: T20 + strongest slow35%% − haste20%% =23 ticks, got %s" % [mode, engine.unit("A1").next_attack_tick])
	completed_tests += 1
