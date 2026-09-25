extends SceneTree

const EngineScript = preload("res://core/battle/battle_engine.gd")
const HandlerScript = preload("res://content/characters/gr_handlers.gd")

class FixtureEventEffect extends RefCounted:
	var expected_kind := ""
	var required_tick := -1
	var actions: Array = []
	func on_event(_engine: BattleEngine, _binding: Dictionary, event: Dictionary) -> Array:
		if str(event.get("kind","")) != expected_kind: return []
		if required_tick >= 0 and int(event.get("tick",-1)) != required_tick: return []
		return actions.duplicate(true)

var production: Dictionary = {}
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	var support_handler = HandlerScript.new()
	_assert(HandlerScript.IMPLEMENTED_IDS.size() == 14, "GR explicit behavior manifest covers all fourteen cards")
	for content_id: String in HandlerScript.IMPLEMENTED_IDS:
		_assert(support_handler.supports_content_id(content_id), "GR supports_content_id accepts implemented ID %s" % content_id)
	_assert(not support_handler.supports_content_id("GR99") and not support_handler.supports_content_id("WR01"),
		"GR supports_content_id rejects unknown and other-family IDs")
	_assert(HandlerScript.INTEGRATED_IDS == ["GR04","GR09"],
		"GR integration manifest includes only cards with completed true-engine acceptance coverage")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/characters.json"))
	if parsed is Dictionary:
		for card in parsed.get("characters", []): production[str(card.id)] = card
	else:
		failures.append("production character catalog failed to load")
	_test_each_id_and_negative()
	_test_main_attack_amount_patches()
	_test_debt_and_cooldown_edges()
	_test_real_gr04_debt_survives_silence()
	_test_real_gr09_overlapping_wages()
	if failures.is_empty():
		print("GR_HANDLER_BATCH_OK cases=%d handlers=14 real_engine_integrated=%d integration_blocked=%d" % [checks,HandlerScript.INTEGRATED_IDS.size(),14-HandlerScript.INTEGRATED_IDS.size()])
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)


func _test_each_id_and_negative() -> void:
	var expected := {
		"GR01":[{"kind":"counter","counter_key":"coins","value":1}],
		"GR02":[{"kind":"counter","counter_key":"premium_prepared","value":1},{"kind":"attack_patch","attack_id":"a-1","patch":{"amount_flat":100}}],
		"GR03":[{"kind":"counter","counter_key":"crate_loaded","value":1},{"kind":"attack_suppress","attack_id":"a-1","reason":"first_shot_loads_crate"}],
		"GR04":[{"kind":"shield_grant","target_key":"A2","amount":120,"expires_tick":60},{"kind":"counter","counter_key":"loan_absorbed:A2","value":0},{"kind":"counter","counter_key":"loan_due:A2","value":60},
			{"kind":"schedule","tick":60,"phase":"damage","independent":true,"source_key":"A1","action":{"kind":"counter_settlement","target_key":"A1","counter_key":"loan_absorbed:A2","amount_bp":5000,"max_amount":60,"damage_type":"self_loss"}}],
		"GR05":[{"kind":"cooldown","ticks":20,"cooldown_key":"tax"},{"kind":"shield_consume","target_key":"B1","amount":30,"source_binding_key":"shield-source"},{"kind":"shield_grant","target_key":"A1","amount":30,"expires_tick":30}],
		"GR06":[{"kind":"counter","counter_key":"overheal_reserve","value":60},{"kind":"counter","counter_key":"overheal_reserve","value":0},{"kind":"shield_grant","target_key":"A2","amount":50,"expires_tick":30},{"kind":"cooldown","ticks":10,"cooldown_key":"exchange"}],
		"GR07":[{"kind":"cooldown","ticks":40,"cooldown_key":"repair"},{"kind":"shield_grant","target_key":"A2","amount":60,"expires_tick":20}],
		"GR08":[{"kind":"counter","counter_key":"redemption_marks","value":1}],
		"GR09":[{"kind":"counter","counter_key":"pay_slot","value":2},{"kind":"counter","counter_key":"wage_pending:A1","value":0},{"kind":"counter","counter_key":"wage_expiry:A1","value":0},{"kind":"counter","counter_key":"wage_pending:A1","value":1},{"kind":"counter","counter_key":"wage_expiry:A1","value":70}],
		"GR10":[{"kind":"cooldown","ticks":20,"cooldown_key":"audit"},{"kind":"attack_patch","attack_id":"a-1","patch":{"convert_physical_to_fixed_bypass_shield":60}}],
		"GR11":[{"kind":"counter","counter_key":"contract_target_slot","value":1},{"kind":"counter","counter_key":"contract_target_side","value":2},{"kind":"counter","counter_key":"contract_until","value":20}],
		"GR12":[{"kind":"cooldown","ticks":30,"cooldown_key":"debt"},{"kind":"defer_damage","target_key":"A1","source_key":"B1","source_binding_key":"B1:fixture","amount":80,"due_tick":20,"skip_armor_and_reduction":true,"enter_shield_step":true}],
		"GR13":[{"kind":"counter","counter_key":"damage_type:physical","value":1},{"kind":"counter","counter_key":"type_count","value":1}],
		"GR14":[{"kind":"shield_consume","target_key":"A1","amount":100},{"kind":"heal","target_key":"A2","amount":60},{"kind":"heal","target_key":"A3","amount":60}]
	}
	for content_id in expected:
		var pair := _fixture(str(content_id))
		var event: Dictionary = pair.event
		var actions: Array = pair.handler.on_event(pair.engine,pair.binding,event)
		_assert_case("%s exact action contract" % content_id,actions,expected[content_id])
		_assert_case("%s irrelevant event is negative" % content_id,
			pair.handler.on_event(pair.engine,pair.binding,_event("unrelated","", "")),[])


func _test_main_attack_amount_patches() -> void:
	for entry in [{"id":"GR02","amount":100},{"id":"GR09","amount":50},{"id":"GR11","amount":70}]:
		var pair := _fixture(str(entry.id))
		var event: Dictionary = pair.event
		if str(entry.id) == "GR09":
			pair.engine.set_counter(pair.binding.source_key,"wage_pending:A1",1)
			pair.engine.set_counter(pair.binding.source_key,"wage_expiry:A1",70)
			event = _event("prepare_attack","A1","B1",{"is_natural_attack":true,"attack_id":"a-1","tick":29})
		elif str(entry.id) == "GR11":
			pair.engine.set_counter(pair.binding.source_key,"contract_target_slot",1)
			pair.engine.set_counter(pair.binding.source_key,"contract_target_side",2)
			pair.engine.set_counter(pair.binding.source_key,"contract_until",20)
			event = _event("before_hit","A2","B1",{"is_natural_attack":true,"attack_id":"a-1","target_slot":1,"target_side":"B","tick":1})
		var result: Array = pair.handler.on_event(pair.engine,pair.binding,event)
		var found := false
		for action in result:
			if action.get("kind","") != "attack_patch": continue
			found = int(action.get("patch",{}).get("amount_flat",-1)) == int(entry.amount)
			_assert(not action.get("patch",{}).has("attached_damage"),"%s amount increase modifies main segment, not a bonus packet" % entry.id)
		_assert(found,"%s main segment amount_flat=%d" % [entry.id,int(entry.amount)])


func _test_debt_and_cooldown_edges() -> void:
	var loan := _fixture("GR04")
	loan.engine.set_counter(loan.binding.source_key,"loan_due:A2",60)
	for absorbed in [3,3,1]:
		var accumulated: int = loan.engine.get_counter(loan.binding.source_key,"loan_absorbed:A2") + int(absorbed)
		_assert_case("GR04 accumulates exact absorbed tenths without per-hit rounding",loan.handler.on_event(loan.engine,loan.binding,
			_event("shield_absorbed","A1","A2",{"source_binding_key":loan.binding.source_key,"payload":{"amount":absorbed}})),
			[{"kind":"counter","counter_key":"loan_absorbed:A2","value":accumulated}])
		loan.engine.set_counter(loan.binding.source_key,"loan_absorbed:A2",accumulated)
	_assert_case("GR04 does not settle the 4-second debt via an expiry callback",loan.handler.on_event(loan.engine,loan.binding,
		_event("expiry","A1","A2",{"source_binding_key":loan.binding.source_key,"tick":59,"payload":{"kind":"shield"}})),[])
	_assert_case("GR04 settlement is queue-owned, not an expiry callback",loan.handler.on_event(loan.engine,loan.binding,
		_event("expiry","A1","A2",{"source_binding_key":loan.binding.source_key,"tick":60,"payload":{"kind":"shield"}})),
		[])
	loan.engine.set_counter(loan.binding.source_key,"loan_absorbed:A2",120)
	loan.engine.set_counter(loan.binding.source_key,"loan_due:A2",60)
	_assert_case("GR04 caps a whole-loan half-payment at 60 tenths",loan.handler.on_event(loan.engine,loan.binding,
		_event("expiry","A1","A2",{"source_binding_key":loan.binding.source_key,"tick":60,"payload":{"kind":"shield"}})),
		[])

	var cashier := _fixture("GR06")
	cashier.engine.start_cooldown(cashier.binding.source_key,10,"exchange")
	var first_overheal := _event("healed","healer","A1",{"overheal":40,"tick":1})
	cashier.engine.state.tick = 1
	_assert_case("GR06 accrues overheal during exchange cooldown",cashier.handler.on_event(cashier.engine,cashier.binding,first_overheal),
		[{"kind":"counter","counter_key":"overheal_reserve","value":40}])
	cashier.engine.set_counter(cashier.binding.source_key,"overheal_reserve",40)
	cashier.engine.state.tick = 10
	var second_overheal := _event("healed","healer","A1",{"overheal":20,"tick":10})
	_assert_case("GR06 exchanges on exact cooldown boundary",cashier.handler.on_event(cashier.engine,cashier.binding,second_overheal),[
		{"kind":"counter","counter_key":"overheal_reserve","value":60},{"kind":"counter","counter_key":"overheal_reserve","value":0},
		{"kind":"shield_grant","target_key":"A2","amount":50,"expires_tick":40},{"kind":"cooldown","ticks":10,"cooldown_key":"exchange"}])

	var mechanic := _fixture("GR07")
	_assert_case("GR07 legal shield clearing is not damage break repair",mechanic.handler.on_event(mechanic.engine,mechanic.binding,
		_event("shield_broken","enemy","A2",{"target_side":"A","target_slot":2,"reason":"clear"})),[])

	var payroll := _fixture("GR09")
	payroll.engine.set_counter(payroll.binding.source_key,"wage_pending:A1",1)
	payroll.engine.set_counter(payroll.binding.source_key,"wage_expiry:A1",70)
	_assert_case("GR09 wage is expired at its exclusive boundary",payroll.handler.on_event(payroll.engine,payroll.binding,
		_event("prepare_attack","A1","B1",{"is_natural_attack":true,"attack_id":"a-1","tick":70})),
		[{"kind":"counter","counter_key":"wage_pending:A1","value":0},{"kind":"counter","counter_key":"wage_expiry:A1","value":0}])


func _fixture(content_id: String, unit_overrides: Dictionary = {}, apply_direct_setup: bool = true, fixture_effect = null) -> Dictionary:
	var card: Dictionary = production.get(content_id,{})
	var handler = HandlerScript.new()
	var binding := {"content_id":content_id,"logic_handler":"character_"+content_id,"owner_key":"A1","source_key":"A1:"+content_id,"kind":"talent"}
	var definition := {"logic_handler":"character_"+content_id,"handler":handler,"bindings":[binding]}
	var teams := {"A":[_unit("A",1,card),_unit("A",2),_unit("A",3)],"B":[_unit("B",1),_unit("B",2),_unit("B",3)]}
	for side in ["A","B"]:
		for index in range(3):
			var unit: Dictionary = teams[side][index]
			var key := "%s%d" % [side,int(unit.slot)]
			if unit_overrides.has(key): unit.merge(unit_overrides[key],true)
	var engine = EngineScript.new()
	var definitions: Array = [definition]
	if fixture_effect != null:
		var fixture_binding := {"content_id":"FIXTURE_EFFECT","logic_handler":"fixture_effect","owner_key":"B1","source_key":"fixture:B1","kind":"talent"}
		definitions.append({"logic_handler":"fixture_effect","handler":fixture_effect,"bindings":[fixture_binding]})
	var initialized: Dictionary = engine.setup({"seed":7,"rule_id":"VC01","test_fixture":true,"teams":teams},definitions)
	if not str(initialized.get("error","")).is_empty(): failures.append("fixture setup %s: %s" % [content_id,initialized.error])
	if apply_direct_setup: _prepare_case(content_id,engine,binding)
	return {"engine":engine,"handler":handler,"binding":binding,"event":_positive_event(content_id)}


func _test_real_gr09_overlapping_wages() -> void:
	var pair := _fixture("GR09",{"A1":{"T_ticks":65},"B1":{"H":200,"T_ticks":1000},
		"A2":{"T_ticks":1000},"A3":{"T_ticks":1000}},false)
	var engine: BattleEngine = pair.engine
	for tick in range(131):
		var result: Dictionary = engine.step()
		if not str(result.get("error","")).is_empty():
			failures.append("GR09 real overlap fixture blocked at tick %d: %s" % [tick,result.error])
			return
	var attack_losses: Array[int] = []
	for event in engine.state.events:
		if str(event.get("kind","")) == "hp_lost" and str(event.get("source_key","")) == "A1" and str(event.get("target_key","")) == "B1" and bool(event.get("is_natural_attack",false)):
			attack_losses.append(int(event.get("actual_hp_loss",0)))
	_assert(attack_losses == [80,130],"GR09 slot1 wage survives slot2 payment at tick60 and patches A1's tick130 attack; losses=%s" % str(attack_losses))
	_assert(engine.get_counter(pair.binding.source_key,"wage_pending:A2") == 1,
		"GR09 slot2 has its independent live wage after slot1's attack consumes only slot1 wage")


func _test_real_gr04_debt_survives_silence() -> void:
	var silence := FixtureEventEffect.new()
	silence.expected_kind = "periodic"
	silence.required_tick = 30
	silence.actions = [{"kind":"status_add","target_key":"A1","status_id":"silence","layers":1,"expires_tick":70}]
	var pair := _fixture("GR04",{"A1":{"T_ticks":1000},"A2":{"T_ticks":1000},
		"B1":{"A":12,"T_ticks":20,"target_slot":2}},false,silence)
	var engine: BattleEngine = pair.engine
	for tick in range(61):
		var result: Dictionary = engine.step()
		if not str(result.get("error","")).is_empty():
			failures.append("GR04 real scheduled debt blocked at tick %d: %s" % [tick,result.error])
			return
	var absorbed := 0
	var broken := false
	var settlement := 0
	for event in engine.state.events:
		if str(event.get("kind","")) == "shield_absorbed" and str(event.get("target_key","")) == "A2" and str(event.get("source_binding_key","")) == pair.binding.source_key:
			absorbed += int(event.get("amount",event.get("payload",{}).get("amount",0)))
		if str(event.get("kind","")) == "shield_broken" and str(event.get("target_key","")) == "A2" and str(event.get("source_binding_key","")) == pair.binding.source_key:
			broken = true
		if int(event.get("tick",-1)) == 60 and str(event.get("kind","")) == "hp_lost" and str(event.get("target_key","")) == "A1" and str(event.get("damage_type","")) == "self_loss":
			settlement += int(event.get("actual_hp_loss",0))
	var silenced := false
	for status in engine.unit("A1").get("statuses",[]):
		if str(status.get("id","")) == "silence": silenced = true
	_assert(absorbed == 120 and broken,"GR04 full shield consumed at tick20 with exact source-attributed absorption; amount=%d" % absorbed)
	_assert(silenced,"GR04 owner remains silenced across tick60 settlement")
	_assert(settlement == 60 and int(engine.unit("A1").hp_tenths) == 1000,
		"GR04 scheduled counter settlement pays one capped 60 self-loss under silence; loss=%d hp=%d" % [settlement,int(engine.unit("A1").hp_tenths)])
	_assert(engine.get_counter(pair.binding.source_key,"loan_absorbed:A2") == 0,"GR04 settlement clears exact accumulated debt")
	var idle := _fixture("GR04",{"A1":{"T_ticks":1000},"A2":{"T_ticks":1000},"B1":{"T_ticks":1000}},false)
	for tick in range(61):
		var result: Dictionary = idle.engine.step()
		if not str(result.get("error","")).is_empty():
			failures.append("GR04 real zero-absorption debt blocked at tick %d: %s" % [tick,result.error])
			return
	var idle_loss := 0
	for event in idle.engine.state.events:
		if int(event.get("tick",-1)) == 60 and str(event.get("kind","")) == "hp_lost" and str(event.get("target_key","")) == "A1" and str(event.get("damage_type","")) == "self_loss":
			idle_loss += int(event.get("actual_hp_loss",0))
	_assert(idle_loss == 0 and int(idle.engine.unit("A1").hp_tenths) == 1060,
		"GR04 real unused shield matures with zero debt and no self-loss; loss=%d" % idle_loss)
	var no_borrower := _fixture("GR04",{"A2":{"hp_tenths":0},"A3":{"hp_tenths":0},"B1":{"T_ticks":1000}},false)
	for tick in range(61):
		var result: Dictionary = no_borrower.engine.step()
		if not str(result.get("error","")).is_empty():
			failures.append("GR04 real no-borrower fixture blocked at tick %d: %s" % [tick,result.error])
			return
	var loans_granted := 0
	for event in no_borrower.engine.state.events:
		if str(event.get("kind","")) == "shield_gained" and str(event.get("source_binding_key","")) == no_borrower.binding.source_key: loans_granted += 1
	_assert(loans_granted == 0 and int(no_borrower.engine.unit("A1").hp_tenths) == 1060,
		"GR04 real no-living-borrower schedule creates neither shield nor debt")


func _prepare_case(content_id: String, engine: BattleEngine, binding: Dictionary) -> void:
	match content_id:
		"GR01":
			engine.state.teams.A[0].hp_tenths = 400
			engine.set_counter(binding.source_key,"coins",0)
		"GR03":
			engine.set_counter(binding.source_key,"crate_loaded",0)
			engine.set_counter(binding.source_key,"crate_spent",0)
		"GR05":
			engine.state.teams.A[0].target_slot = 1
		"GR09":
			engine.set_counter(binding.source_key,"pay_slot",1)
			engine.set_counter(binding.source_key,"wage_pending:A1",1)
			engine.set_counter(binding.source_key,"wage_expiry:A1",70)
		"GR10":
			engine.state.teams.A[0].shield_pools.append({"source_key":"self","amount":20,"expires_tick":100})
			engine.state.teams.B[0].shield_pools.append({"source_key":"enemy","amount":100,"expires_tick":100})
		"GR11":
			engine.state.teams.A[1].target_slot = 1
		"GR13":
			engine.set_counter(binding.source_key,"type_count",0)
		"GR14":
			engine.state.teams.A[0].shield_pools.append({"source_key":binding.source_key,"source_binding_key":binding.source_key,"amount":100,"expires_tick":100})


func _positive_event(content_id: String) -> Dictionary:
	match content_id:
		"GR01": return _event("hit","A1","B1",{"is_attack":true})
		"GR02": return _event("prepare_attack","A1","B1",{"is_natural_attack":true,"attack_id":"a-1"})
		"GR03": return _event("prepare_attack","A1","B1",{"is_natural_attack":true,"attack_id":"a-1"})
		"GR04": return _event("periodic","","",{"tick":20})
		"GR05": return _event("shield_gained","shield-source","B1",{"source_binding_key":"shield-source","amount":100,"tick":0})
		"GR06": return _event("healed","healer","A1",{"overheal":60,"tick":0})
		"GR07": return _event("shield_broken","enemy","A2",{"target_side":"A","target_slot":2,"reason":"damage","tick":0})
		"GR08": return _event("hit","A1","B1",{"is_natural_attack":true})
		"GR09": return _event("periodic","","",{"tick":30})
		"GR10": return _event("before_hit","A1","B1",{"is_natural_attack":true,"attack_id":"a-1"})
		"GR11": return _event("hit","A1","B1",{"is_natural_attack":true,"target_slot":1,"target_side":"B","tick":0})
		"GR12": return _event("before_damage","B1","A1",{"amount_before_shield":100,"source_binding_key":"B1:fixture","tick":0})
		"GR13": return _event("hp_lost","A1","B1",{"damage_type":"physical","actual_hp_loss":100,"tick":0})
		"GR14": return _event("periodic","","",{"tick":60})
	return _event("unrelated","", "")


func _unit(side: String, slot: int, card: Dictionary = {}) -> Dictionary:
	var owner := side == "A" and slot == 1 and not card.is_empty()
	return {"definition_id":str(card.get("id","FIXTURE_%s%d" % [side,slot])),"fixture":not owner,"slot":slot,
		"talent_id":str(card.get("id","")),"H":int(card.get("H",100)),"A":int(card.get("A",0)),
		"T_ticks":int(card.get("T_ticks",1000)),"R":int(card.get("R",0)),"reach":str(card.get("reach","ranged")),
		"armor_kind":str(card.get("armor_kind","light")),"target_slot":1,"first_attack_tick":1000}


func _event(kind: String, source_key: String, target_key: String, details: Dictionary = {}) -> Dictionary:
	var event := {"kind":kind,"event_id":"spec-event","root_id":"spec-root","tick":0,"source_key":source_key,
		"source_binding_key":"","target_key":target_key,"target_slot":int(target_key.substr(1)) if target_key.length() >= 2 else 0,
		"target_side":target_key.substr(0,1) if target_key.length() >= 2 else "","actual_hp_loss":0,"raw_amount":0,
		"is_attack":false,"is_natural_attack":false,"is_extra_attack":false,"extra_generation":0,"payload":{}}
	for key in details:
		if key == "payload": event.payload = details.payload.duplicate(true)
		else: event[key] = details[key]
	return event


func _assert_case(label: String, actual: Variant, expected: Variant) -> void:
	checks += 1
	if actual != expected: failures.append("%s\nexpected=%s\nactual=%s" % [label,JSON.stringify(expected),JSON.stringify(actual)])


func _assert(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
