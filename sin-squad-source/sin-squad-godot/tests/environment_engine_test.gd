extends SceneTree

const Battle = preload("res://core/battle/battle_engine.gd")
const Environments = preload("res://content/environment/environment_handlers.gd")

var checks := 0
var failures: Array[String] = []


class TalentProbe extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		var counter_key := "battle_start_calls" if str(event.get("kind", "")) == "battle_start" else "periodic_calls"
		var calls := engine.get_counter(str(binding.source_key), counter_key) + 1
		return [{"kind":"counter","counter_key":counter_key,"value":calls}]


class ShieldFixture extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		return [{"kind":"shield_grant","target_key":"A1","amount":30,"expires_tick":100}]


class HealFixture extends RefCounted:
	var amount := 0
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		return [{"kind":"heal","target_key":"B1","amount":amount}]


class DoubleKillFixture extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		return [
			{"kind":"damage","target_key":"A1","amount":200,"damage_type":"fixed"},
			{"kind":"damage","target_key":"A2","amount":200,"damage_type":"fixed"}
		]


class FirstEnemyKillFixture extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		return [{"kind":"damage","target_key":"B1","amount":2000,"damage_type":"fixed"}]


class FirstHpLossFixture extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		return [{"kind":"damage","target_key":"A1","amount":1,"damage_type":"fixed"}]


class TimedDamageFixture extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		var actions: Array = []
		for due_tick in [1, 7]:
			actions.append({"kind":"schedule", "tick":due_tick, "phase":"damage", "independent":true,
				"action":{"kind":"damage", "target_key":"A1", "amount":100, "damage_type":"physical"}})
		return actions


class EncumbranceShieldFixture extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		return [
			{"kind":"shield_grant","target_key":"A1","amount":101,"expires_tick":1000},
			{"kind":"shield_grant","target_key":"A2","amount":40,"expires_tick":1000},
			{"kind":"shield_grant","target_key":"B1","amount":80,"expires_tick":1000}
		]


class ShieldEchoFixture extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		return [
			{"kind":"shield_grant","target_key":"A1","amount":30,"expires_tick":1000},
			{"kind":"shield_grant","target_key":"B1","amount":30,"expires_tick":1000},
			{"kind":"schedule","tick":2,"phase":"damage","independent":true,"action":{"kind":"shield_grant","target_key":"A2","amount":10,"expires_tick":1000}}
		]


class HealingWindowFixture extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		return [
			{"kind":"schedule","tick":179,"phase":"pre_damage","independent":true,"action":{"kind":"heal","target_key":"A2","amount":100}},
			{"kind":"schedule","tick":180,"phase":"pre_damage","independent":true,"action":{"kind":"heal","target_key":"A2","amount":100}}
		]


class DroughtFixture extends RefCounted:
	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		return [
			{"kind":"heal","target_key":"B1","amount":100},
			{"kind":"shield_grant","target_key":"A1","amount":30,"expires_tick":1000}
		]


class FlankShieldBreakFixture extends RefCounted:
	var broken_slot := 1
	var dead_flank := 0

	func on_event(engine: BattleEngine, binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind", "")) != "battle_start": return []
		var actions: Array = [{"kind":"shield_grant","target_key":"A%d" % broken_slot,"amount":20,"expires_tick":1000},
			{"kind":"schedule","tick":1,"phase":"damage","independent":true,
			"action":{"kind":"damage","target_key":"A%d" % broken_slot,"amount":50,"damage_type":"fixed"}}]
		if dead_flank in [1, 3]: actions.append({"kind":"damage","target_key":"A%d" % dead_flank,"amount":3000,"damage_type":"fixed"})
		return actions


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var environment_handler = Environments.new()
	var probe := TalentProbe.new()
	var handlers := [
		{
			"logic_handler":"environment_AR14",
			"handler":environment_handler,
			"bindings":[_binding("AR14", "arena", ["battle_start"])]
		},
		{
			"logic_handler":"environment_AR16",
			"handler":environment_handler,
			"bindings":[_binding("AR16", "environment", ["pre_battle"])]
		},
		{
			"logic_handler":"fixture_talent_probe",
			"handler":probe,
			"bindings":[{
				"content_id":"FIXTURE_TALENT_PROBE",
				"logic_handler":"fixture_talent_probe",
				"source_key":"A1:FIXTURE_TALENT_PROBE",
				"owner_key":"A1",
				"kind":"talent",
				"subscribes":["battle_start", "periodic"]
			}]
		}
	]
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":23,
		"rule_id":"VC21",
		"arena_id":"AR14",
		"test_fixture":true,
		"teams":{"A":_team("A"),"B":_team("B")}
	}, handlers)
	_expect(str(initialized.get("error", "")).is_empty(), "real BattleEngine fixture setup")
	if not str(initialized.get("error", "")).is_empty():
		_finish()
		return

	var first: Dictionary = engine.step()
	_expect(str(first.get("error", "")).is_empty(), "tick-zero environment actions settle")
	_expect(bool(engine.unit("A1").barrier.active), "AR14 selects A's longest base-T unit")
	_expect(not bool(engine.unit("A2").barrier.active), "AR14 does not grant another A barrier")
	_expect(bool(engine.unit("B2").barrier.active), "AR14 resolves equal longest base-T by lower slot")
	_expect(not bool(engine.unit("B3").barrier.active), "AR14 lower-slot tie is stable")
	for side in ["A", "B"]:
		for unit in engine.units(side, true):
			var has_silence := false
			for status in unit.statuses:
				if str(status.id) == "silence" and int(status.expires_tick) == 20: has_silence = true
			_expect(has_silence, "AR16 pauses talents for first 20 ticks on %s" % unit.key)
	_expect(engine.get_counter("A1:FIXTURE_TALENT_PROBE", "battle_start_calls") == 0, "AR16 blocks the talent's battle_start counter")
	_expect(engine.get_counter("A1:FIXTURE_TALENT_PROBE", "periodic_calls") == 0, "AR16 suppresses periodic talent actions in tick zero")
	while int(engine.state.tick) < 20:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "real engine sequential tick %d" % int(engine.state.tick))
	_expect(engine.get_counter("A1:FIXTURE_TALENT_PROBE", "periodic_calls") == 0, "AR16 stays active through tick 19")
	_expect(engine.get_counter("A1:FIXTURE_TALENT_PROBE", "battle_start_calls") == 0, "AR16 does not replay the skipped battle_start at expiry")
	var resumed: Dictionary = engine.step()
	_expect(str(resumed.get("error", "")).is_empty(), "real engine resumes at tick 20")
	_expect(int(engine.state.tick) == 21, "engine advanced one tick after tick-20 evaluation")
	_expect(engine.get_counter("A1:FIXTURE_TALENT_PROBE", "periodic_calls") == 1, "AR16 resumes talent at exactly 2 seconds")
	_expect(engine.get_counter("A1:FIXTURE_TALENT_PROBE", "battle_start_calls") == 0, "AR16 has no deferred opening talent at tick 20")
	for unit in engine.units("A", false):
		for status in unit.statuses:
			_expect(str(status.id) != "silence", "AR16 silence expires before tick-20 actions")
	_test_ar08()
	_test_ar07()
	_test_ar03()
	_test_pe36()
	_test_ar13()
	_test_ar15()
	_test_ar19()
	_test_ar20()
	_test_ar04()
	_test_ar06()
	_test_ar09()
	_test_ar11()
	_test_pe05()
	_test_pe12()
	_test_pe17()
	_test_pe18()
	_test_pe26()
	_test_pe30()
	_test_pe31()
	_test_pe32()
	_test_pe35()
	_test_pe38()
	_test_pe39()
	_test_pe47()
	_test_pe48()
	_test_pe50()
	_test_prepare_handlers()
	_test_pe23_natural_rhythm()
	_test_pe46_wing_lantern()
	_test_exact_health_ratio_ordering()
	_finish()


func _binding(content_id: String, binding_kind: String, subscribes: Array) -> Dictionary:
	return {
		"content_id":content_id,
		"logic_handler":"environment_%s" % content_id,
		"source_key":"global:%s" % content_id,
		"owner_key":"",
		"kind":binding_kind,
		"subscribes":subscribes
	}


func _team(side: String) -> Array:
	var rows: Array = []
	var times := [700, 900, 900] if side == "B" else [900, 500, 500]
	for slot in [1, 2, 3]:
		rows.append({
			"definition_id":"FIXTURE_ENV_%s%d" % [side, slot],
			"fixture":true,
			"slot":slot,
			"H":200,
			"A":1,
			"T_ticks":times[slot - 1],
			"R":0,
			"reach":"ranged",
			"armor_kind":"medium",
			"first_attack_tick":1000
		})
	return rows


func _test_ar08() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_AR08",
		"handler":environment_handler,
		"bindings":[_binding("AR08", "arena", ["periodic"])]
	}]
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":81,
		"rule_id":"VC21",
		"arena_id":"AR08",
		"test_fixture":true,
		"teams":{"A":_team("A"),"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR08 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 49:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR08 sequential tick before 5 seconds")
	for side in ["A", "B"]:
		for unit in engine.units(side, false):
			_expect(int(unit.hp_tenths) == 2000, "AR08 does not burn early at %s" % unit.key)
	var five_second_tick: Dictionary = engine.step()
	_expect(str(five_second_tick.get("error", "")).is_empty(), "AR08 5-second engine step")
	for side in ["A", "B"]:
		for unit in engine.units(side, false):
			_expect(int(unit.hp_tenths) == 1980, "AR08 exact fire damage at %s" % unit.key)
			_expect(unit.statuses.is_empty(), "AR08 fire pulse does not apply burn at %s" % unit.key)
	while int(engine.state.tick) <= 99:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR08 sequential tick before 10 seconds")
	for side in ["A", "B"]:
		for unit in engine.units(side, false):
			_expect(int(unit.hp_tenths) == 1980, "AR08 no off-schedule fire at %s" % unit.key)
	var ten_second_tick: Dictionary = engine.step()
	_expect(str(ten_second_tick.get("error", "")).is_empty(), "AR08 10-second engine step")
	for side in ["A", "B"]:
		for unit in engine.units(side, false):
			_expect(int(unit.hp_tenths) == 1960, "AR08 repeated pulse at %s" % unit.key)


func _test_ar13() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_AR13",
		"handler":environment_handler,
		"bindings":[_binding("AR13", "arena", ["periodic"])]
	}]
	var team_a := _team("A")
	team_a[0].R = 0
	team_a[0].setup_modifiers = [{"stat":"R_flat","amount":2}]
	team_a[1].R = 2
	team_a[1].setup_modifiers = [{"stat":"R_flat","amount":2}]
	team_a[2].R = 1
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":83,
		"rule_id":"VC22",
		"arena_id":"AR13",
		"test_fixture":true,
		"teams":{"A":team_a,"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR13 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	_expect(int(engine.effective_stats("A1").R) == 2, "AR13 base-zero armor retains unrelated +2 armor")
	_expect(int(engine.effective_stats("A2").R) == 4, "AR13 begins with base and unrelated armor contribution")
	while int(engine.state.tick) <= 79:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR13 sequential tick before 8 seconds")
	_expect(int(engine.effective_stats("A2").R) == 4, "AR13 no early armor loss before tick 80")
	var at_eight: Dictionary = engine.step()
	_expect(str(at_eight.get("error", "")).is_empty(), "AR13 exact 8-second step")
	_expect(int(engine.effective_stats("A1").R) == 2, "AR13 does not remove temporary armor when base armor is zero")
	_expect(int(engine.effective_stats("A2").R) == 3, "AR13 removes exactly one base armor at tick 80")
	_expect(int(engine.effective_stats("A3").R) == 0, "AR13 floors base armor at zero")
	while int(engine.state.tick) <= 159:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR13 sequential tick before 16 seconds")
	_expect(int(engine.effective_stats("A2").R) == 3, "AR13 no second reduction before tick 160")
	var at_sixteen: Dictionary = engine.step()
	_expect(str(at_sixteen.get("error", "")).is_empty(), "AR13 exact 16-second step")
	_expect(int(engine.effective_stats("A1").R) == 2, "AR13 base-zero temporary armor remains intact at tick 160")
	_expect(int(engine.effective_stats("A2").R) == 2, "AR13 removes one additional base armor at tick 160")
	_expect(int(engine.effective_stats("A3").R) == 0, "AR13 base armor never becomes negative")


func _test_ar03() -> void:
	_run_ar03_case(2, 1875, "same-slot ranged bonus")
	_run_ar03_case(1, 1925, "cross-slot ranged penalty")


func _run_ar03_case(target_slot: int, expected_hp: int, label: String) -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_AR03",
		"handler":environment_handler,
		"bindings":[_binding("AR03", "arena", ["before_hit"])]
	}]
	var team_a := _team("A")
	team_a[1].A = 10
	team_a[1].T_ticks = 50
	team_a[1].reach = "ranged"
	team_a[1].target_slot = target_slot
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":85 + target_slot,
		"rule_id":"VC22",
		"arena_id":"AR03",
		"test_fixture":true,
		"teams":{"A":team_a,"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR03 %s engine setup" % label)
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 54:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR03 %s sequential attack timeline" % label)
	_expect(int(engine.unit("B%d" % target_slot).hp_tenths) == expected_hp, "AR03 %s exact damage multiplier" % label)


func _test_ar07() -> void:
	_run_ar07_case(false)
	_run_ar07_case(true)


func _run_ar07_case(shield_original: bool) -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_AR07",
		"handler":environment_handler,
		"bindings":[_binding("AR07", "arena", ["hp_lost"])]
	}]
	var team_a := _team("A")
	team_a[0].A = 10
	team_a[0].T_ticks = 6
	team_a[0].reach = "ranged"
	team_a[0].damage_type = "lightning"
	team_a[0].target_slot = 1
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":86 if shield_original else 84,
		"rule_id":"VC22",
		"arena_id":"AR07",
		"test_fixture":true,
		"teams":{"A":team_a,"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR07 real BattleEngine setup (shield=%s)" % shield_original)
	if not str(initialized.get("error", "")).is_empty(): return
	if shield_original:
		var shielded: Dictionary = engine.fixture_apply([{"kind":"shield_grant","target":"B1","source":"fixture_shield","amount":200,"expires_tick":100}])
		_expect(str(shielded.get("error", "")).is_empty(), "AR07 fixture numeric shield setup")
	while int(engine.state.tick) <= 6:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR07 real lightning attack settles")
	var expected_primary := 2000 if shield_original else 1900
	var expected_side := 2000 if shield_original else 1975
	_expect(int(engine.unit("B1").hp_tenths) == expected_primary, "AR07 primary lightning damage/resisted hit")
	_expect(int(engine.unit("B2").hp_tenths) == expected_side, "AR07 first side arc uses 25 percent actual loss")
	_expect(int(engine.unit("B3").hp_tenths) == expected_side, "AR07 second side arc is bounded without chaining")


func _test_pe36() -> void:
	_run_pe36_case(599, 1875, "strictly below 30 percent")
	_run_pe36_case(600, 1900, "exactly 30 percent does not qualify")


func _run_pe36_case(current_hp: int, expected_target_hp: int, label: String) -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_PE36",
		"handler":environment_handler,
		"bindings":[_binding("PE36", "public", ["before_hit"])]
	}]
	var team_a := _team("A")
	team_a[1].A = 10
	team_a[1].T_ticks = 50
	team_a[1].reach = "ranged"
	team_a[1].hp_tenths = current_hp
	team_a[1].target_slot = 2
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":88,
		"rule_id":"VC22",
		"public_effect_ids":["PE36"],
		"test_fixture":true,
		"teams":{"A":team_a,"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE36 %s engine setup" % label)
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 50:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "PE36 %s sequential attack timeline" % label)
	_expect(int(engine.unit("B2").hp_tenths) == expected_target_hp, "PE36 %s exact health threshold result" % label)


func _test_ar15() -> void:
	_run_ar15_case(60, true)
	_run_ar15_case(50, false)


func _run_ar15_case(hit_tick: int, expect_shield: bool) -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_AR15",
		"handler":environment_handler,
		"bindings":[_binding("AR15", "arena", ["hp_lost"])]
	}]
	var team_a := _team("A")
	team_a[0].A = 10
	team_a[0].T_ticks = hit_tick
	team_a[0].reach = "ranged"
	team_a[0].target_slot = 1
	var team_b := _team("B")
	team_b[0].hp_tenths = 1100
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":110 + hit_tick,
		"rule_id":"VC22",
		"arena_id":"AR15",
		"test_fixture":true,
		"teams":{"A":team_a,"B":team_b}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR15 real BattleEngine setup at tick %d" % hit_tick)
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= hit_tick:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR15 sequential timeline through candidate threshold event")
	var expected_amount := 40 if expect_shield else 0
	_expect(engine.shield_amount("B1", "global:AR15") == expected_amount, "AR15 shield requires a post-six-second downward crossing")
	if not expect_shield:
		while int(engine.state.tick) <= 100:
			var advanced: Dictionary = engine.step()
			_expect(str(advanced.get("error", "")).is_empty(), "AR15 no late award after an early crossing")
		_expect(engine.shield_amount("B1", "global:AR15") == 0, "AR15 early crossing is not replayed later")


func _test_ar19() -> void:
	var environment_handler = Environments.new()
	var double_kill := DoubleKillFixture.new()
	var handler_rows := [
		{
			"logic_handler":"environment_AR19",
			"handler":environment_handler,
			"bindings":[_binding("AR19", "arena", ["final_departure"])]
		},
		{
			"logic_handler":"fixture_double_kill",
			"handler":double_kill,
			"bindings":[{
				"content_id":"FIXTURE_DOUBLE_KILL",
				"logic_handler":"fixture_double_kill",
				"source_key":"B1:FIXTURE_DOUBLE_KILL",
				"owner_key":"B1",
				"kind":"equipment",
				"subscribes":["battle_start"]
			}]
		}
	]
	var team_a := _team("A")
	team_a[0].H = 10
	team_a[1].H = 10
	team_a[2].H = 10
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":119,
		"rule_id":"VC21",
		"arena_id":"AR19",
		"test_fixture":true,
		"teams":{"A":team_a,"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR19 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var first: Dictionary = engine.step()
	_expect(str(first.get("error", "")).is_empty(), "AR19 same-tick final departures settle")
	var departure_count := 0
	for event in first.get("events", []):
		if str(event.get("kind", "")) == "final_departure" and str(event.get("target_side", "")) == "A": departure_count += 1
	_expect(departure_count == 2, "AR19 fixture creates simultaneous first departures")
	_expect(engine.shield_amount("A3", "global:AR19") == 40, "AR19 awards the surviving teammate one four-point shield")
	_expect(engine.shield_amount("B1", "global:AR19") == 0, "AR19 remains per-team, not global once")
	while not bool(engine.state.terminal) and int(engine.state.tick) <= 29:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR19 sequential shield window")
	_expect(engine.shield_amount("A3", "global:AR19") == 40, "AR19 shield remains before tick-30 expiry")
	var expiry: Dictionary = engine.step()
	_expect(str(expiry.get("error", "")).is_empty(), "AR19 exact three-second expiry tick")
	_expect(engine.shield_amount("A3", "global:AR19") == 0, "AR19 shield expires at tick 30")


func _test_ar20() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_AR20",
		"handler":environment_handler,
		"bindings":[_binding("AR20", "arena", ["prepare_attack"])]
	}]
	var team_a := _team("A")
	for unit in team_a: unit.target_slot = 1
	var team_b := _team("B")
	for unit in team_b: unit.target_slot = 1
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":120,
		"rule_id":"VC21",
		"arena_id":"AR20",
		"test_fixture":true,
		"teams":{"A":team_a,"B":team_b}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR20 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var first: Dictionary = engine.step()
	_expect(str(first.get("error", "")).is_empty(), "AR20 first preparations settle")
	_expect(engine.shield_amount("B1", "global:AR20") == 20, "AR20 first of multiple attackers grants exactly one two-point shield")
	_expect(engine.get_counter("B1", "AR20_aim_shield_used") == 1, "AR20 stores one-shot mark on targeted unit")
	_expect(engine.shield_amount("B2", "global:AR20") == 0 and engine.shield_amount("B3", "global:AR20") == 0, "AR20 does not protect targets with no enemy preparation")
	_expect(engine.shield_amount("A1", "global:AR20") == 20, "AR20 applies symmetrically to a target on the other side")
	_expect(engine.shield_amount("A2", "global:AR20") == 0 and engine.shield_amount("A3", "global:AR20") == 0, "AR20 does not shield un-targeted allied units")


func _test_ar11() -> void:
	var environment_handler = Environments.new()
	var damage_fixture := TimedDamageFixture.new()
	var handler_rows := [
		{"logic_handler":"environment_AR11", "handler":environment_handler, "bindings":[_binding("AR11", "arena", ["battle_start", "hit"])]},
		{"logic_handler":"fixture_timed_damage", "handler":damage_fixture, "bindings":[{
			"content_id":"FIXTURE_TIMED_DAMAGE", "logic_handler":"fixture_timed_damage", "source_key":"B1:FIXTURE_TIMED_DAMAGE",
			"owner_key":"B1", "kind":"equipment", "subscribes":["battle_start"]
		}]}
	]
	var team_a := _team("A")
	team_a[0].T_ticks = 6
	team_a[0].first_attack_tick = 6
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":111, "rule_id":"VC21", "arena_id":"AR11", "test_fixture":true,
		"teams":{"A":team_a, "B":_team("B")}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR11 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 7:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR11 tick-accurate cover / first attack timeline")
	_expect(int(engine.unit("A1").hp_tenths) == 1825, "AR11 reduces the pre-first-attack hit by 25%, then removes cover permanently after A1 attacks")
	_expect(engine.get_counter("A1", "AR11_first_attack_cover_removed") == 1, "AR11 removal is tied to the protected unit's own completed attack")


func _test_ar06() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{"logic_handler":"environment_AR06", "handler":environment_handler, "bindings":[_binding("AR06", "arena", ["hit"])]}]
	var team_a := _team("A")
	team_a[0].reach = "melee"
	team_a[0].target_slot = 2
	team_a[0].T_ticks = 50
	team_a[0].first_attack_tick = 50
	team_a[1].reach = "melee"
	team_a[1].target_slot = 2
	team_a[1].T_ticks = 50
	team_a[1].first_attack_tick = 50
	team_a[2].reach = "ranged"
	team_a[2].target_slot = 1
	team_a[2].T_ticks = 50
	team_a[2].first_attack_tick = 50
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":106, "rule_id":"VC21", "arena_id":"AR06", "test_fixture":true,
		"teams":{"A":team_a, "B":_team("B")}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR06 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 54:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR06 eligible hit and ineligible attacks resolve")
	_expect(_status_expiry(engine.unit("A1"), "chill") == 74, "AR06 cross-melee attacker receives chill for exactly 2 seconds (expiry=%d, state_tick=%d)" % [_status_expiry(engine.unit("A1"), "chill"), int(engine.state.tick)])
	_expect(not _has_status(engine.unit("A2"), "chill"), "AR06 same-slot melee does not trigger")
	_expect(not _has_status(engine.unit("A3"), "chill"), "AR06 ranged attack does not trigger")
	while int(engine.state.tick) < 74:
		var before_expiry: Dictionary = engine.step()
		_expect(str(before_expiry.get("error", "")).is_empty(), "AR06 chill remains through tick 69")
	var expiry: Dictionary = engine.step()
	_expect(str(expiry.get("error", "")).is_empty(), "AR06 exact 2-second expiry")
	_expect(not _has_status(engine.unit("A1"), "chill"), "AR06 chill clears at its half-open expiry")


func _test_ar04() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{"logic_handler":"environment_AR04", "handler":environment_handler, "bindings":[_binding("AR04", "arena", ["before_hit"])]}]
	var team_a := _team("A")
	team_a[0].A = 10
	team_a[0].reach = "ranged"
	team_a[0].target_slot = 1
	team_a[0].T_ticks = 6
	team_a[0].first_attack_tick = 6
	team_a[1].reach = "melee"
	team_a[1].target_slot = 2
	team_a[1].T_ticks = 6
	team_a[1].first_attack_tick = 6
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":104, "rule_id":"VC21", "arena_id":"AR04", "test_fixture":true,
		"teams":{"A":team_a, "B":_team("B")}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR04 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 13:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR04 one ranged shot is suppressed, later attacks settle")
	_expect(engine.get_counter("B1", "AR04_ranged_cover_used") == 1, "AR04 consumes the target's cover on the first ranged basic attack")
	_expect(int(engine.unit("B1").hp_tenths) == 1900, "AR04 fully negates only the first of two ranged attacks")
	_expect(engine.get_counter("B2", "AR04_ranged_cover_used") == 0, "AR04 melee does not consume the cover")
	_expect(int(engine.unit("B2").hp_tenths) == 1980, "AR04 leaves same-position melee damage unchanged")
	_expect(engine.get_counter("B3", "AR04_ranged_cover_used") == 0, "AR04 unaffected units keep their cover")


func _test_ar09() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{"logic_handler":"environment_AR09", "handler":environment_handler, "bindings":[_binding("AR09", "arena", ["hit"])]}]
	var team_a := _team("A")
	team_a[0].reach = "melee"
	team_a[0].target_slot = 2
	team_a[0].T_ticks = 6
	team_a[0].first_attack_tick = 6
	team_a[1].reach = "ranged"
	team_a[1].target_slot = 1
	team_a[1].T_ticks = 6
	team_a[1].first_attack_tick = 6
	team_a[2].reach = "melee"
	team_a[2].target_slot = 3
	team_a[2].T_ticks = 6
	team_a[2].first_attack_tick = 6
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":109, "rule_id":"VC21", "arena_id":"AR09", "test_fixture":true,
		"teams":{"A":team_a, "B":_team("B")}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "AR09 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 30:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "AR09 counts completed attacks through the third hit")
	_expect(engine.get_counter("A1", "AR09_melee_attack_count") == 3, "AR09 counts only cross-position melee attack completions")
	_expect(int(engine.unit("A1").hp_tenths) == 1980, "AR09 applies exactly 2 self-damage after attack three (hp=%d, count=%d)" % [int(engine.unit("A1").hp_tenths), engine.get_counter("A1", "AR09_melee_attack_count")])
	_expect(engine.get_counter("A2", "AR09_melee_attack_count") == 0 and engine.get_counter("A3", "AR09_melee_attack_count") == 0, "AR09 ranged and same-slot attacks do not advance its counter")


func _test_pe05() -> void:
	var environment_handler = Environments.new()
	var shield_fixture := ShieldFixture.new()
	var handler_rows := [
		{
			"logic_handler":"environment_PE05",
			"handler":environment_handler,
			"bindings":[_binding("PE05", "public", ["periodic"])]
		},
		{
			"logic_handler":"fixture_start_shield",
			"handler":shield_fixture,
			"bindings":[{
				"content_id":"FIXTURE_START_SHIELD",
				"logic_handler":"fixture_start_shield",
				"source_key":"A1:FIXTURE_START_SHIELD",
				"owner_key":"A1",
				"kind":"slot",
				"subscribes":["battle_start"]
			}]
		}
	]
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":82,
		"rule_id":"VC21",
		"public_effect_ids":["PE05"],
		"test_fixture":true,
		"teams":{"A":_team("A"),"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE05 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 39:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "PE05 sequential tick before 4 seconds")
	for side in ["A", "B"]:
		for unit in engine.units(side, false):
			_expect(not _has_status(unit, "chill"), "PE05 no early chill at %s" % unit.key)
	var four_second_tick: Dictionary = engine.step()
	_expect(str(four_second_tick.get("error", "")).is_empty(), "PE05 4-second engine step")
	for side in ["A", "B"]:
		for unit in engine.units(side, false):
			var chilled := _has_status(unit, "chill")
			_expect(chilled == (str(unit.key) != "A1"), "PE05 only current unshielded units chill at %s" % unit.key)
			if chilled:
				_expect(_status_expiry(unit, "chill") == 60, "PE05 chill expires exactly 2 seconds after application")
	while int(engine.state.tick) <= 59:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "PE05 sequential tick to chill expiry")
	_expect(_has_status(engine.unit("A2"), "chill"), "PE05 chill remains through tick 59")
	var expiry_tick: Dictionary = engine.step()
	_expect(str(expiry_tick.get("error", "")).is_empty(), "PE05 expiry engine step")
	for side in ["A", "B"]:
		for unit in engine.units(side, false):
			_expect(not _has_status(unit, "chill"), "PE05 chill expires at tick 60 after 2 seconds at %s" % unit.key)


func _test_prepare_handlers() -> void:
	_run_prepare_case("AR01", "arena", "A2", "melee", "medium", false, 1, 59, -1)
	_run_prepare_case("AR02", "arena", "A2", "melee", "medium", false, 1, 50, -1)
	_run_prepare_case("AR05", "arena", "A1", "melee", "light", false, 1, 55, 110)
	_run_prepare_case("AR05", "arena", "A2", "melee", "medium", false, 2, 53, 103)
	_run_prepare_case("AR05", "arena", "A3", "melee", "heavy", false, 3, 50, 100)
	_run_prepare_case("AR10", "arena", "A1", "ranged", "light", false, 1, 40, 80)
	_run_prepare_case("AR10", "arena", "A3", "ranged", "heavy", true, 3, 40, 80)
	_run_prepare_case("AR10", "arena", "A2", "ranged", "medium", false, 2, 50, -1)
	_run_prepare_case("AR17", "arena", "A1", "melee", "medium", false, 3, 58, -1)
	_run_prepare_case("AR17", "arena", "A2", "melee", "medium", false, 1, 54, -1)
	_run_prepare_case("AR17", "arena", "A3", "melee", "medium", false, 1, 50, -1)
	_run_prepare_case("PE09", "public", "A2", "ranged", "medium", false, 1, 56, -1)
	_run_prepare_case("PE10", "public", "A2", "melee", "light", false, 1, 61, -1)
	_run_prepare_case("PE21", "public", "A1", "ranged", "medium", false, 1, 25, 75)
	_run_prepare_case("PE22", "public", "A1", "ranged", "medium", false, 1, 60, 110)


func _test_pe23_natural_rhythm() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{"logic_handler":"environment_PE23", "handler":environment_handler,
		"bindings":[_binding("PE23", "public", ["prepare_attack"])]}]
	var team_a := _team("A")
	team_a[0].first_attack_tick = 0
	team_a[0].T_ticks = 50
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":923, "rule_id":"VC21", "public_effect_ids":["PE23"],
		"test_fixture":true,"teams":{"A":team_a,"B":_team("B")}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE23 engine setup with source binding")
	if not str(initialized.get("error", "")).is_empty(): return
	for target_tick in [0, 50, 100, 150]:
		while int(engine.state.tick) <= target_tick:
			var tick_result: Dictionary = engine.step()
			_expect(str(tick_result.get("error", "")).is_empty(), "PE23 advances each integer tick through %d" % target_tick)
		_expect(engine.get_counter("A1", "natural_attack_count") == 4 if target_tick == 150 else true,
			"PE23 natural preparations advance by completed natural-attack rhythm")
	_expect(int(engine.unit("A1").next_attack_tick) == 175,
		"PE23 shortens only the fourth natural preparation from 50 to 25 ticks")
	_expect(engine.get_counter("A1", "natural_attack_count") == 4,
		"PE23 extra attack events do not advance natural attack counter")


func _test_pe46_wing_lantern() -> void:
	for broken_slot in [1, 2]:
		var environment_handler = Environments.new()
		var fixture := FlankShieldBreakFixture.new()
		fixture.broken_slot = broken_slot
		var handlers := [
			{"logic_handler":"environment_PE46", "handler":environment_handler,
				"bindings":[_binding("PE46", "public", ["shield_broken"])]},
			{"logic_handler":"fixture_flank_break", "handler":fixture,
				"bindings":[{"content_id":"FIXTURE_FLANK_BREAK","logic_handler":"fixture_flank_break",
				"source_key":"A1:FIXTURE_FLANK_BREAK","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]}]}
		]
		var engine = Battle.new()
		var initialized: Dictionary = engine.setup({"seed":946 + broken_slot,"rule_id":"VC21","public_effect_ids":["PE46"],
			"test_fixture":true,"teams":{"A":_team("A"),"B":_team("B")}}, handlers)
		_expect(str(initialized.get("error", "")).is_empty(), "PE46 flank/center case %d setup" % broken_slot)
		if not str(initialized.get("error", "")).is_empty(): continue
		var first: Dictionary = engine.step()
		_expect(str(first.get("error", "")).is_empty(), "PE46 start shield and timed damage settle")
		var due: Dictionary = engine.step()
		_expect(str(due.get("error", "")).is_empty(), "PE46 real shield break resolves on tick one")
		if broken_slot == 1:
			_expect(engine.shield_amount("A3", "global:PE46") == 40 and engine.get_counter("A1", "PE46_first_flank_break") == 1,
				"PE46 first flank break grants exactly four shield to opposite flank")
		else:
			_expect(engine.shield_amount("A1", "global:PE46") == 0 and engine.get_counter("A1", "PE46_first_flank_break") == 0,
				"PE46 central-slot shield break does not activate the flank effect")
	var negative_fixture := FlankShieldBreakFixture.new()
	negative_fixture.dead_flank = 3
	var negative_handlers := [
		{"logic_handler":"environment_PE46", "handler":Environments.new(),"bindings":[_binding("PE46", "public", ["shield_broken"])]},
		{"logic_handler":"fixture_flank_break", "handler":negative_fixture,"bindings":[{"content_id":"FIXTURE_FLANK_BREAK",
			"logic_handler":"fixture_flank_break","source_key":"A1:FIXTURE_FLANK_BREAK","owner_key":"A1","kind":"equipment","subscribes":["battle_start"]}]}
	]
	var negative = Battle.new()
	var negative_setup: Dictionary = negative.setup({"seed":949,"rule_id":"VC21","public_effect_ids":["PE46"],
		"test_fixture":true,"teams":{"A":_team("A"),"B":_team("B")}}, negative_handlers)
	_expect(str(negative_setup.get("error", "")).is_empty(), "PE46 dead-flank negative setup")
	if str(negative_setup.get("error", "")).is_empty():
		_expect(str(negative.step().get("error", "")).is_empty(), "PE46 kills opposite flank before the shield break")
		_expect(str(negative.step().get("error", "")).is_empty(), "PE46 dead-flank shield break settles")
		_expect(negative.shield_amount("A3", "global:PE46") == 0 and negative.get_counter("A1", "PE46_first_flank_break") == 0,
			"PE46 requires both flank units to remain alive when the break occurs")


func _test_pe12() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_PE12",
		"handler":environment_handler,
		"bindings":[_binding("PE12", "public", ["pre_battle"])]
	}]
	var team_a := _team("A")
	team_a[0].A = 5
	team_a[0].T_ticks = 6
	team_a[0].reach = "ranged"
	team_a[0].damage_type = "physical"
	team_a[0].target_slot = 1
	team_a[1].A = 5
	team_a[1].T_ticks = 6
	team_a[1].reach = "ranged"
	team_a[1].damage_type = "fire"
	team_a[1].target_slot = 2
	var team_b := _team("B")
	for unit in team_b: unit.R = 0
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":87,
		"rule_id":"VC22",
		"public_effect_ids":["PE12"],
		"test_fixture":true,
		"teams":{"A":team_a,"B":team_b}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE12 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var start: Dictionary = engine.step()
	_expect(str(start.get("error", "")).is_empty(), "PE12 environment initial armor setup")
	_expect(int(engine.effective_stats("B1").R) == 2 and int(engine.effective_stats("B2").R) == 2, "PE12 grants +2 armor to both teams")
	while int(engine.state.tick) <= 6:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "PE12 sequential attacks through tick 6")
	_expect(int(engine.unit("B1").hp_tenths) == 1970, "PE12 armor reduces physical damage by exactly 2")
	_expect(int(engine.unit("B2").hp_tenths) == 1950, "PE12 armor does not reduce fire damage")


func _test_pe17() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_PE17",
		"handler":environment_handler,
		"bindings":[_binding("PE17", "public", ["periodic"])]
	}]
	var team_a := _team("A")
	team_a[0].hp_tenths = 1000
	team_a[1].hp_tenths = 1000
	team_a[2].hp_tenths = 1200
	var team_b := _team("B")
	team_b[0].hp_tenths = 1500
	team_b[1].hp_tenths = 1500
	team_b[2].hp_tenths = 900
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":89,
		"rule_id":"VC22",
		"public_effect_ids":["PE17"],
		"test_fixture":true,
		"teams":{"A":team_a,"B":team_b}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE17 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 59:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "PE17 sequential timeline before 6 seconds")
	_expect(engine.shield_amount("A1", "global:PE17") == 0, "PE17 no early shield")
	var tide: Dictionary = engine.step()
	_expect(str(tide.get("error", "")).is_empty(), "PE17 exact 6-second event")
	_expect(engine.shield_amount("A1", "global:PE17") == 50, "PE17 selects A's lowest ratio, lower slot on tie")
	_expect(engine.shield_amount("A2", "global:PE17") == 0, "PE17 does not shield tied higher slot")
	_expect(engine.shield_amount("B3", "global:PE17") == 50, "PE17 independently selects B's lower-health unit")
	_expect(engine.shield_amount("B1", "global:PE17") == 0, "PE17 does not cross-select between teams")


func _test_exact_health_ratio_ordering() -> void:
	var environment_handler = Environments.new()
	_expect(environment_handler._compare_nonnegative_fractions(1, 3, 2, 6) == 0, "health ratio comparer detects equivalent fractions")
	_expect(environment_handler._compare_nonnegative_fractions(3_999_999_999_999_999_999, 4_000_000_000_000_000_000, 3_999_999_999_999_999_998, 3_999_999_999_999_999_999) == 1, "health ratio comparer avoids overflowing cross products")


func _test_pe32() -> void:
	_run_pe32_case(10000, 50, "overflow converts at half rate and caps at five shields")
	_run_pe32_case(500, 0, "actual healing without overheal grants no shield")


func _test_pe26() -> void:
	_run_pe26_case(6, 6, true)
	_run_pe26_case(50, 70, false)


func _run_pe26_case(first_attacker_tick: int, second_attacker_tick: int, expected_shield: bool) -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_PE26",
		"handler":environment_handler,
		"bindings":[_binding("PE26", "public", ["hit"])]
	}]
	var team_a := _team("A")
	team_a[0].T_ticks = first_attacker_tick
	team_a[0].reach = "ranged"
	team_a[0].target_slot = 1
	team_a[1].T_ticks = second_attacker_tick
	team_a[1].reach = "ranged"
	team_a[1].target_slot = 1
	team_a[2].T_ticks = 500
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":126 + second_attacker_tick + first_attacker_tick,
		"rule_id":"VC21",
		"public_effect_ids":["PE26"],
		"test_fixture":true,
		"teams":{"A":team_a,"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE26 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var last_tick := maxi(first_attacker_tick, second_attacker_tick)
	while int(engine.state.tick) <= last_tick:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "PE26 sequential timeline for distinct attacker window")
	var expected_amount := 30 if expected_shield else 0
	_expect(engine.shield_amount("B1", "global:PE26") == expected_amount, "PE26 %s" % ("grants once within 1 second" if expected_shield else "rejects attacks outside a 1-second window"))
	_expect(int(engine.unit("B1").get("ability_counters", {}).get("PE26_shield_used", 0)) == (1 if expected_shield else 0), "PE26 one-shot state is on the targeted defender")


func _run_pe32_case(healing_amount: int, expected_shield: int, label: String) -> void:
	var environment_handler = Environments.new()
	var heal_fixture := HealFixture.new()
	heal_fixture.amount = healing_amount
	var handler_rows := [
		{
			"logic_handler":"environment_PE32",
			"handler":environment_handler,
			"bindings":[_binding("PE32", "public", ["healed"])]
		},
		{
			"logic_handler":"fixture_heal",
			"handler":heal_fixture,
			"bindings":[{
				"content_id":"FIXTURE_HEAL",
				"logic_handler":"fixture_heal",
				"source_key":"A1:FIXTURE_HEAL",
				"owner_key":"A1",
				"kind":"equipment",
				"subscribes":["battle_start"]
			}]
		}
	]
	var team_b := _team("B")
	team_b[0].hp_tenths = 1000
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":132,
		"rule_id":"VC22",
		"public_effect_ids":["PE32"],
		"test_fixture":true,
		"teams":{"A":_team("A"),"B":team_b}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE32 %s engine setup" % label)
	if not str(initialized.get("error", "")).is_empty(): return
	var start: Dictionary = engine.step()
	_expect(str(start.get("error", "")).is_empty(), "PE32 real engine heal/overheal event")
	_expect(engine.shield_amount("B1", "global:PE32") == expected_shield, "PE32 %s" % label)


func _test_pe38() -> void:
	var environment_handler = Environments.new()
	var double_kill := DoubleKillFixture.new()
	var handler_rows := [
		{
			"logic_handler":"environment_PE38",
			"handler":environment_handler,
			"bindings":[_binding("PE38", "public", ["final_departure","periodic"])]
		},
		{
			"logic_handler":"fixture_double_kill",
			"handler":double_kill,
			"bindings":[{
				"content_id":"FIXTURE_DOUBLE_KILL",
				"logic_handler":"fixture_double_kill",
				"source_key":"B1:FIXTURE_DOUBLE_KILL",
				"owner_key":"B1",
				"kind":"equipment",
				"subscribes":["battle_start"]
			}]
		}
	]
	var team_a := _team("A")
	team_a[0].H = 10
	team_a[1].H = 10
	team_a[2].hp_tenths = 1000
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":138,
		"rule_id":"VC21",
		"public_effect_ids":["PE38"],
		"test_fixture":true,
		"teams":{"A":team_a,"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE38 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var solo: Dictionary = engine.step()
	_expect(str(solo.get("error", "")).is_empty(), "PE38 solo transition settles after simultaneous departures")
	_expect(engine.units("A", true).size() == 1, "PE38 has exactly one surviving teammate")
	_expect(engine.shield_amount("A3", "global:PE38") == 60, "PE38 grants exactly one six-point solo shield")
	_expect(engine.get_counter("A1", "PE38_solo_window_used") == 1, "PE38 one-time trigger is team-scoped")
	while int(engine.state.tick) <= 9:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "PE38 no early tick heal")
	_expect(int(engine.unit("A3").hp_tenths) == 1000, "PE38 waits until the first full second")
	var first_heal: Dictionary = engine.step()
	_expect(str(first_heal.get("error", "")).is_empty(), "PE38 first scheduled one-point heal")
	_expect(int(engine.unit("A3").hp_tenths) == 1010, "PE38 heals ten tenths at tick 10")
	while int(engine.state.tick) <= 40:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "PE38 sequential scheduled heal window")
	_expect(int(engine.unit("A3").hp_tenths) == 1040, "PE38 exactly four one-point heals by tick 40")


func _test_pe39() -> void:
	var environment_handler = Environments.new()
	var shield_fixture := EncumbranceShieldFixture.new()
	var team_a := _team("A")
	team_a[0].hp_tenths = 1000
	team_a[1].hp_tenths = 2000
	var team_b := _team("B")
	team_b[0].hp_tenths = 1000
	var handler_rows := [
		{"logic_handler":"environment_PE39", "handler":environment_handler, "bindings":[_binding("PE39", "public", ["periodic"])]},
		{"logic_handler":"fixture_encumbrance_shields", "handler":shield_fixture, "bindings":[{
			"content_id":"FIXTURE_ENCUMBRANCE_SHIELDS", "logic_handler":"fixture_encumbrance_shields", "source_key":"A1:FIXTURE_ENCUMBRANCE_SHIELDS",
			"owner_key":"A1", "kind":"equipment", "subscribes":["battle_start"]
		}]}
	]
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":139, "rule_id":"VC22", "public_effect_ids":["PE39"], "test_fixture":true,
		"teams":{"A":team_a, "B":team_b}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE39 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var start: Dictionary = engine.step()
	_expect(str(start.get("error", "")).is_empty(), "PE39 test shields are installed by battle fixture")
	_expect(engine.shield_amount("A1") == 101 and engine.shield_amount("A2") == 40, "PE39 retains the unmodified shield pools before 12 seconds")
	while int(engine.state.tick) < 120:
		var before: Dictionary = engine.step()
		_expect(str(before.get("error", "")).is_empty(), "PE39 sequentially waits for exact 12-second conversion")
	var deadline: Dictionary = engine.step()
	_expect(str(deadline.get("error", "")).is_empty(), "PE39 exact t=12s shield conversion")
	_expect(engine.shield_amount("A1") == 51 and int(engine.unit("A1").hp_tenths) == 1025, "PE39 floors odd tenth halves and restores half the removed amount")
	_expect(engine.shield_amount("A2") == 20 and int(engine.unit("A2").hp_tenths) == 2000, "PE39 full-health overflow is discarded without a second shield")
	_expect(engine.shield_amount("B1") == 40 and int(engine.unit("B1").hp_tenths) == 1020, "PE39 applies symmetrically to the opposing team")


func _test_pe18() -> void:
	var environment_handler = Environments.new()
	var shield_fixture := ShieldEchoFixture.new()
	var handler_rows := [
		{"logic_handler":"environment_PE18", "handler":environment_handler, "bindings":[_binding("PE18", "public", ["shield_gained"])]},
		{"logic_handler":"fixture_shield_echo", "handler":shield_fixture, "bindings":[{
			"content_id":"FIXTURE_SHIELD_ECHO", "logic_handler":"fixture_shield_echo", "source_key":"A1:FIXTURE_SHIELD_ECHO",
			"owner_key":"A1", "kind":"equipment", "subscribes":["battle_start"]
		}]}
	]
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":118, "rule_id":"VC21", "public_effect_ids":["PE18"], "test_fixture":true,
		"teams":{"A":_team("A"), "B":_team("B")}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE18 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var first: Dictionary = engine.step()
	_expect(str(first.get("error", "")).is_empty(), "PE18 simultaneous primary shields and nonrecursive echo settle")
	_expect(engine.shield_amount("A1") == 30 and engine.shield_amount("B1") == 30, "PE18 preserves each original shield")
	_expect(engine.shield_amount("A2", "global:PE18") == 20 and engine.shield_amount("A3", "global:PE18") == 20, "PE18 echoes once to A's other living allies")
	_expect(engine.shield_amount("B2", "global:PE18") == 20 and engine.shield_amount("B3", "global:PE18") == 20, "PE18 handles same-root first shields on both teams")
	while int(engine.state.tick) < 2:
		var before: Dictionary = engine.step()
		_expect(str(before.get("error", "")).is_empty(), "PE18 waits before independent later shield")
	var later: Dictionary = engine.step()
	_expect(str(later.get("error", "")).is_empty(), "PE18 ignores subsequent shields after the one-time echo")
	_expect(engine.shield_amount("A1", "global:PE18") == 0 and engine.shield_amount("A3", "global:PE18") == 20, "PE18 attached echo does not recursively trigger on later shield gains")
	_expect(engine.shield_amount("A2") == 30, "PE18 retains the later shield without repeating the echo")


func _test_pe30() -> void:
	var environment_handler = Environments.new()
	var healing_fixture := HealingWindowFixture.new()
	var team_a := _team("A")
	team_a[0].T_ticks = 180
	team_a[1].hp_tenths = 1000
	var handler_rows := [
		{"logic_handler":"environment_PE30", "handler":environment_handler, "bindings":[_binding("PE30", "public", ["periodic", "prepare_attack", "healed"])]},
		{"logic_handler":"fixture_healing_window", "handler":healing_fixture, "bindings":[{
			"content_id":"FIXTURE_HEALING_WINDOW", "logic_handler":"fixture_healing_window", "source_key":"A1:FIXTURE_HEALING_WINDOW",
			"owner_key":"A1", "kind":"equipment", "subscribes":["battle_start"]
		}]}
	]
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":130, "rule_id":"VC22", "public_effect_ids":["PE30"], "test_fixture":true,
		"teams":{"A":team_a, "B":_team("B")}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE30 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) < 180:
		var before: Dictionary = engine.step()
		_expect(str(before.get("error", "")).is_empty(), "PE30 full-strength before the exact 18-second mark")
	var sprint: Dictionary = engine.step()
	_expect(str(sprint.get("error", "")).is_empty(), "PE30 exact 18-second sprint and healing reduction")
	_expect(int(engine.unit("A2").hp_tenths) == 1175, "PE30 applies full healing at t179 and 75% healing beginning t180")
	_expect(int(engine.unit("A1").next_attack_tick) == 315, "PE30 reduces the next 180-tick attack interval by exactly 25%")


func _test_pe31() -> void:
	var environment_handler = Environments.new()
	var drought_fixture := DroughtFixture.new()
	var team_b := _team("B")
	team_b[0].hp_tenths = 1000
	var handler_rows := [
		{"logic_handler":"environment_PE31", "handler":environment_handler, "bindings":[_binding("PE31", "public", ["pre_battle"])]},
		{"logic_handler":"fixture_drought", "handler":drought_fixture, "bindings":[{
			"content_id":"FIXTURE_DROUGHT", "logic_handler":"fixture_drought", "source_key":"A1:FIXTURE_DROUGHT",
			"owner_key":"A1", "kind":"equipment", "subscribes":["battle_start"]
		}]}
	]
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":131, "rule_id":"VC21", "public_effect_ids":["PE31"], "test_fixture":true,
		"teams":{"A":_team("A"), "B":team_b}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE31 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var first: Dictionary = engine.step()
	_expect(str(first.get("error", "")).is_empty(), "PE31 pre-battle modifier precedes opening heal")
	_expect(int(engine.unit("B1").hp_tenths) == 1060, "PE31 reduces a 10-point heal by 40%")
	_expect(engine.shield_amount("A1") == 30, "PE31 does not reduce numeric shield gain")


func _test_pe50() -> void:
	_run_pe50_case(true)
	_run_pe50_case(false)


func _run_pe50_case(reciprocal: bool) -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{"logic_handler":"environment_PE50", "handler":environment_handler, "bindings":[_binding("PE50", "public", ["battle_start", "hit"])]}]
	var team_a := _team("A")
	team_a[0].hp_tenths = 1500
	team_a[0].T_ticks = 6
	team_a[0].target_slot = 1
	team_a[0].first_attack_tick = 6
	var team_b := _team("B")
	team_b[0].hp_tenths = 1500
	team_b[0].T_ticks = 6 if reciprocal else 1000
	team_b[0].target_slot = 1 if reciprocal else 2
	team_b[0].first_attack_tick = 6 if reciprocal else 1000
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":150 if reciprocal else 151, "rule_id":"VC21", "public_effect_ids":["PE50"], "test_fixture":true,
		"teams":{"A":team_a, "B":team_b}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE50 engine setup reciprocal=%s" % reciprocal)
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) <= 6:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "PE50 first natural target hit settles")
	if reciprocal:
		_expect(int(engine.unit("A1").hp_tenths) == 1520 and int(engine.unit("B1").hp_tenths) == 1520, "PE50 reciprocal first attacks each restore 3 health after damage")
		_expect(engine.get_counter("A1", "PE50_duel_mark") == 0 and engine.get_counter("B1", "PE50_duel_mark") == 0, "PE50 consumes both reciprocal marks once")
	else:
		_expect(int(engine.unit("B1").hp_tenths) == 1470, "PE50 one-way first hit adds 2 fixed damage after normal damage")
		_expect(engine.get_counter("A1", "PE50_duel_mark") == 0 and engine.get_counter("B1", "PE50_duel_mark") == 1, "PE50 consumes only the mark of a unit that hit its own target")


func _test_pe35() -> void:
	var environment_handler = Environments.new()
	var kill_fixture := FirstEnemyKillFixture.new()
	var handler_rows := [
		{"logic_handler":"environment_PE35", "handler":environment_handler, "bindings":[_binding("PE35", "public", ["final_departure"])]},
		{"logic_handler":"fixture_first_enemy_kill", "handler":kill_fixture, "bindings":[{
			"content_id":"FIXTURE_FIRST_ENEMY_KILL", "logic_handler":"fixture_first_enemy_kill", "source_key":"A1:FIXTURE_FIRST_ENEMY_KILL",
			"owner_key":"A1", "kind":"equipment", "subscribes":["battle_start"]
		}]}
	]
	var team_a := _team("A")
	team_a[0].hp_tenths = 1500
	team_a[1].hp_tenths = 1000
	team_a[2].hp_tenths = 2000
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":135, "rule_id":"VC21", "public_effect_ids":["PE35"], "test_fixture":true,
		"teams":{"A":team_a, "B":_team("B")}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE35 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var first: Dictionary = engine.step()
	_expect(str(first.get("error", "")).is_empty(), "PE35 credited enemy departure and post-batch heals settle")
	_expect(int(engine.unit("A1").hp_tenths) == 1530 and int(engine.unit("A2").hp_tenths) == 1030, "PE35 heals only living credited-side teammates by 3 health")
	_expect(int(engine.unit("A3").hp_tenths) == 2000, "PE35 heal overflow is discarded")
	_expect(int(engine.unit("B1").hp_tenths) == 0, "PE35 does not revive the same-batch departed enemy")
	_expect(engine.get_counter("A1", "PE35_harvest_used") == 1, "PE35 consumes first-kill trigger once per attacking team")


func _run_prepare_case(content_id: String, binding_kind: String, attacker_key: String, reach: String, armor_kind: String, flying: bool, target_slot: int, expected_first: int, expected_second: int) -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{
		"logic_handler":"environment_%s" % content_id,
		"handler":environment_handler,
		"bindings":[_binding(content_id, binding_kind, ["prepare_attack"])]
	}]
	var team_a := _team("A")
	var attacker_slot := attacker_key.substr(1).to_int()
	team_a[attacker_slot - 1].T_ticks = 50
	team_a[attacker_slot - 1].reach = reach
	team_a[attacker_slot - 1].armor_kind = armor_kind
	team_a[attacker_slot - 1].flying = flying
	team_a[attacker_slot - 1].target_slot = target_slot
	team_a[attacker_slot - 1].first_attack_tick = 0
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({
		"seed":90 + attacker_slot,
		"rule_id":"VC22",
		"arena_id":content_id if binding_kind == "arena" else "",
		"public_effect_ids":[content_id] if binding_kind == "public" else [],
		"test_fixture":true,
		"teams":{"A":team_a,"B":_team("B")}
	}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "%s prepare handler engine setup" % content_id)
	if not str(initialized.get("error", "")).is_empty(): return
	var first: Dictionary = engine.step()
	_expect(str(first.get("error", "")).is_empty(), "%s first preparation settles" % content_id)
	_expect(int(engine.unit(attacker_key).get("next_attack_tick", -1)) == expected_first, "%s exact first attack preparation tick" % content_id)
	if expected_second < 0: return
	while int(engine.state.tick) <= expected_first:
		var advanced: Dictionary = engine.step()
		_expect(str(advanced.get("error", "")).is_empty(), "%s sequential timeline through first attack" % content_id)
	_expect(int(engine.unit(attacker_key).get("next_attack_tick", -1)) == expected_second, "%s exact subsequent preparation timing" % content_id)


func _test_pe47() -> void:
	var environment_handler = Environments.new()
	var handler_rows := [{"logic_handler":"environment_PE47", "handler":environment_handler, "bindings":[_binding("PE47", "public", ["periodic"])]}]
	var team_a := _team("A")
	team_a[0].R = 2
	team_a[1].R = 4
	team_a[2].R = 4
	var team_b := _team("B")
	team_b[0].R = 5
	team_b[1].R = 1
	team_b[2].R = 0
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":147, "rule_id":"VC21", "public_effect_ids":["PE47"], "test_fixture":true,
		"teams":{"A":team_a, "B":team_b}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE47 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	while int(engine.state.tick) < 20:
		var before: Dictionary = engine.step()
		_expect(str(before.get("error", "")).is_empty(), "PE47 no premature judgment before tick 20")
	_expect(int(engine.unit("A2").hp_tenths) == 2000 and int(engine.unit("B1").hp_tenths) == 2000, "PE47 waits through tick 19")
	var deadline: Dictionary = engine.step()
	_expect(str(deadline.get("error", "")).is_empty(), "PE47 exact t=2s lightning judgment")
	_expect(int(engine.unit("A2").hp_tenths) == 1960 and int(engine.unit("A3").hp_tenths) == 2000, "PE47 team A armor tie chooses lower slot and deals 4 lightning")
	_expect(int(engine.unit("B1").hp_tenths) == 1960 and int(engine.unit("B2").hp_tenths) == 2000, "PE47 independently selects team B's highest armor")


func _test_pe48() -> void:
	var environment_handler = Environments.new()
	var damage_fixture := FirstHpLossFixture.new()
	var handler_rows := [
		{"logic_handler":"environment_PE48", "handler":environment_handler, "bindings":[_binding("PE48", "public", ["hp_lost", "periodic"])]},
		{"logic_handler":"fixture_first_hp_loss", "handler":damage_fixture, "bindings":[{
			"content_id":"FIXTURE_FIRST_HP_LOSS", "logic_handler":"fixture_first_hp_loss", "source_key":"B1:FIXTURE_FIRST_HP_LOSS",
			"owner_key":"B1", "kind":"equipment", "subscribes":["battle_start"]
		}]}
	]
	var engine = Battle.new()
	var initialized: Dictionary = engine.setup({"seed":148, "rule_id":"VC21", "public_effect_ids":["PE48"], "test_fixture":true,
		"teams":{"A":_team("A"), "B":_team("B")}}, handler_rows)
	_expect(str(initialized.get("error", "")).is_empty(), "PE48 real BattleEngine setup")
	if not str(initialized.get("error", "")).is_empty(): return
	var first: Dictionary = engine.step()
	_expect(str(first.get("error", "")).is_empty(), "PE48 records actual HP loss at battle start")
	_expect(not bool(engine.unit("A1").barrier.active), "PE48 has not granted before tick 80")
	while int(engine.state.tick) < 80:
		var before: Dictionary = engine.step()
		_expect(str(before.get("error", "")).is_empty(), "PE48 sequentially waits until 8 seconds")
	var deadline: Dictionary = engine.step()
	_expect(str(deadline.get("error", "")).is_empty(), "PE48 exact t=8s shelter event")
	_expect(not bool(engine.unit("A1").barrier.active), "PE48 excludes a unit that ever lost actual HP")
	_expect(bool(engine.unit("A2").barrier.active) and bool(engine.unit("A3").barrier.active), "PE48 shields each never-damaged living unit")
	_expect(bool(engine.unit("B1").barrier.active) and bool(engine.unit("B2").barrier.active) and bool(engine.unit("B3").barrier.active), "PE48 applies independently across both teams")


func _has_status(unit: Dictionary, status_id: String) -> bool:
	for status in unit.get("statuses", []):
		if str(status.get("id", "")) == status_id: return true
	return false


func _status_expiry(unit: Dictionary, status_id: String) -> int:
	for status in unit.get("statuses", []):
		if str(status.get("id", "")) == status_id: return int(status.get("expires_tick", -1))
	return -1


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition and failures.size() < 30: failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: %d real BattleEngine environment assertions; 36 arena/public handlers, exact preparation/damage, timed damage/status, barriers" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		printerr("FAIL: %d environment engine assertion(s) failed across %d checks" % [failures.size(), checks])
		quit(1)
