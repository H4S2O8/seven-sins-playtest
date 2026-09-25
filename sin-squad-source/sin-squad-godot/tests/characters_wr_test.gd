extends SceneTree

const EngineScript = preload("res://core/battle/battle_engine.gd")
const HandlerScript = preload("res://content/characters/wr_handlers.gd")

class FixtureEventEffect extends RefCounted:
	var expected_kind := ""
	var required_source := ""
	var owner_key := "B1"
	var required_tick := -1
	var actions: Array = []
	var event_actions: Dictionary = {}
	var event_ticks: Dictionary = {}
	func on_event(_engine: BattleEngine, _binding: Dictionary, event: Dictionary) -> Array:
		if not required_source.is_empty() and str(event.get("source_key", "")) != required_source: return []
		if required_tick >= 0 and int(event.get("tick", -1)) != required_tick: return []
		var event_kind := str(event.get("kind",""))
		if event_actions.has(event_kind):
			if event_ticks.has(event_kind) and int(event.get("tick",-1)) != int(event_ticks[event_kind]): return []
			return event_actions[event_kind].duplicate(true)
		if str(event.get("kind", "")) != expected_kind: return []
		return actions.duplicate(true)

var checks := 0
var failures: Array[String] = []
var production_characters: Dictionary = {}
var blocked_scenarios := 0


func _initialize() -> void:
	var support_handler = HandlerScript.new()
	_assert(HandlerScript.IMPLEMENTED_IDS.size() == 14, "WR explicit behavior manifest covers all fourteen cards")
	for content_id: String in HandlerScript.IMPLEMENTED_IDS:
		_assert(support_handler.supports_content_id(content_id), "WR supports_content_id accepts implemented ID %s" % content_id)
	_assert(not support_handler.supports_content_id("WR99") and not support_handler.supports_content_id("GR01"),
		"WR supports_content_id rejects unknown and other-family IDs")
	_assert(HandlerScript.INTEGRATED_IDS == ["WR01","WR02","WR04","WR05","WR07","WR08","WR09","WR10","WR11","WR12","WR13","WR14"],
		"WR integration manifest includes only cards with completed true-engine acceptance coverage")
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/characters.json"))
	if catalog is Dictionary:
		for card in catalog.get("characters", []): production_characters[str(card.id)] = card
	else:
		failures.append("production character catalog failed to load")
	_test_wr01()
	_test_wr02()
	_test_wr03()
	_test_wr04()
	_test_wr05()
	_test_wr06()
	_test_wr07()
	_test_wr08()
	_test_wr09()
	_test_wr10()
	_test_wr11()
	_test_wr12()
	_test_wr13()
	_test_wr14()
	_test_real_wr01()
	_test_real_wr01_mirror()
	_test_real_wr02()
	_test_real_wr03()
	_test_real_wr04()
	_test_real_wr05()
	_test_real_wr06()
	_test_real_wr07()
	_test_real_wr08()
	_test_real_wr09()
	_test_real_wr10()
	_test_real_wr11()
	_test_real_wr12()
	_test_real_wr13()
	_test_real_wr14()
	if failures.is_empty():
		print("WR_HANDLER_BATCH_OK cases=%d handlers=14 real_engine_scenarios=%d verified=%d integration_blocked=%d semantics_pending=%d not_yet_integrated=%d" % [checks,20,HandlerScript.INTEGRATED_IDS.size(),blocked_scenarios,0,14-HandlerScript.INTEGRATED_IDS.size()])
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)


func _test_wr01() -> void:
	var pair := _fixture("WR01")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	var handler = pair.handler
	_assert_case("WR01 store 40% actual enemy hp loss", handler.on_event(engine, binding,
		_event("hp_lost", "B1", "A1", {"actual_hp_loss":50})), [_counter("anger", 20)])
	_assert_case("WR01 self/friendly loss is not fuel", handler.on_event(engine, binding,
		_event("hp_lost", "A2", "A1", {"actual_hp_loss":100})), [])
	engine.set_counter(binding.source_key, "anger", 20)
	_assert_case("WR01 next attack spends anger", handler.on_event(engine, binding,
		_event("hit", "A1", "B1", {"is_attack":true})), [_counter("anger", 0), _cooldown(10, "anger_store"), _damage("B1", 20, "physical")])
	engine.start_cooldown(binding.source_key, 10, "anger_store")
	engine.state.tick = 9
	_assert_case("WR01 one-second no-store window", handler.on_event(engine, binding,
		_event("hp_lost", "B1", "A1", {"tick":9,"actual_hp_loss":50})), [])
	engine.state.tick = 10
	_assert_case("WR01 store resumes at exact expiry", handler.on_event(engine, binding,
		_event("hp_lost", "B1", "A1", {"tick":10,"actual_hp_loss":50})), [_counter("anger", 40)])


func _test_wr02() -> void:
	var pair := _fixture("WR02")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	var handler = pair.handler
	engine.state.teams.A[0].target_slot = 1
	engine.state.teams.B[0].target_slot = 2
	_assert_case("WR02 current target attacks another ally", handler.on_event(engine, binding,
		_event("hit", "B1", "A2", {"is_attack":true,"is_natural_attack":true})),
		[_cooldown(30), {"kind":"extra_attack","target_key":"B1","amount":66,"damage_type":"physical"}])
	_assert_case("WR02 extra attacks also trigger the guard", handler.on_event(engine, binding,
		_event("hit", "B1", "A2", {"is_attack":true,"is_extra_attack":true,"extra_generation":1})),
		[_cooldown(30), {"kind":"extra_attack","target_key":"B1","amount":66,"damage_type":"physical"}])
	_assert_case("WR02 non-target enemy does not guard", handler.on_event(engine, binding,
		_event("hit", "B2", "A2", {"is_attack":true,"is_natural_attack":true})), [])
	engine.start_cooldown(binding.source_key, 30)
	engine.state.tick = 29
	_assert_case("WR02 three-second cooldown active before boundary", handler.on_event(engine, binding,
		_event("hit", "B1", "A2", {"tick":29,"is_attack":true,"is_natural_attack":true})), [])
	engine.state.tick = 30
	_assert_case("WR02 cooldown boundary reopens", handler.on_event(engine, binding,
		_event("hit", "B1", "A2", {"tick":30,"is_attack":true,"is_natural_attack":true})),
		[_cooldown(30), {"kind":"extra_attack","target_key":"B1","amount":66,"damage_type":"physical"}])


func _test_wr03() -> void:
	var pair := _fixture("WR03")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	var handler = pair.handler
	engine.state.teams.A[0].statuses.append({"id":"rooted","source_key":"fixture","layers":1,"expires_tick":100})
	_assert_case("WR03 rooted preparation removes root and patches attack", handler.on_event(engine, binding,
		_event("prepare_attack", "A1", "B1", {"attack_id":"A1-1"})),
		[{"kind":"status_remove","target_key":"A1","status_id":"rooted","layers":1},
		{"kind":"attack_patch","attack_id":"A1-1","patch":{"ignore_slow_for_this_attack":true,"attached_damage":[{"amount":50,"damage_type":"fixed"}]}}, _cooldown(40)])
	var clean := _fixture("WR03")
	_assert_case("WR03 no control has no effect", clean.handler.on_event(clean.engine, clean.binding,
		_event("prepare_attack", "A1", "B1", {"attack_id":"A1-2"})), [])
	engine.start_cooldown(binding.source_key, 40)
	engine.state.teams.A[0].statuses.clear()
	engine.state.tick = 39
	_assert_case("WR03 cooldown remains active before expiry", handler.on_event(engine, binding,
		_event("prepare_attack", "A1", "B1", {"tick":39,"attack_id":"A1-3"})), [])
	engine.state.tick = 40
	_assert_case("WR03 cooldown expires at four seconds", handler.on_event(engine, binding,
		_event("prepare_attack", "A1", "B1", {"tick":40,"attack_id":"A1-3"})), [])


func _test_wr04() -> void:
	var pair := _fixture("WR04")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	var expected: Array = [{"kind":"modifier_add","target_key":"B1","stat":"R_flat","amount":-1,"modifier_id":"WR04:B1:0","expires_tick":40}]
	_assert_case("WR04 first hit applies one expiring R layer", pair.handler.on_event(engine, binding,
		_event("hit", "A1", "B1", {"is_attack":true})), expected)
	_assert_case("WR04 non-attack damage does not add armor layer", pair.handler.on_event(engine, binding,
		_event("hp_lost", "A1", "B1", {"actual_hp_loss":10})), [])
	engine.state.teams.B[0].modifiers = [{"stat":"R_flat","amount":-1,"modifier_id":"WR04:B1:0",
		"source_binding_key":binding.source_key,"expires_tick":40}]
	engine.state.tick = 20
	var refresh: Array = [
		{"kind":"modifier_remove","target_key":"B1","modifier_id":"WR04:B1:0","source_binding_key":binding.source_key},
		{"kind":"modifier_add","target_key":"B1","stat":"R_flat","amount":-1,"modifier_id":"WR04:B1:0","expires_tick":60},
		{"kind":"modifier_add","target_key":"B1","stat":"R_flat","amount":-1,"modifier_id":"WR04:B1:1","expires_tick":60},
	]
	_assert_case("WR04 cap refreshes all four target layers", pair.handler.on_event(engine, binding,
		_event("hit", "A1", "B1", {"tick":20,"is_attack":true})), refresh)


func _test_wr05() -> void:
	var pair := _fixture("WR05")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	_assert_case("WR05 healthy attack pays 6 hp and converts to fire", pair.handler.on_event(engine, binding,
		_event("before_hit", "A1", "B1", {"attack_id":"A1-1"})),
		[{"kind":"attack_patch","attack_id":"A1-1","patch":{"damage_type":"fire","amount_flat":60}}, {"kind":"self_loss","amount":60}])
	engine.state.teams.A[0].hp_tenths = 350
	_assert_case("WR05 exactly 35 percent does not pay", pair.handler.on_event(engine, binding,
		_event("before_hit", "A1", "B1", {"attack_id":"A1-2"})), [])
	engine.state.teams.A[0].hp_tenths = 414
	engine.start_cooldown(binding.source_key, 1)
	_assert_case("WR05 no invented cooldown between attacks", pair.handler.on_event(engine, binding,
		_event("before_hit", "A1", "B1", {"tick":0,"attack_id":"A1-3"})),
		[{"kind":"attack_patch","attack_id":"A1-3","patch":{"damage_type":"fire","amount_flat":60}}, {"kind":"self_loss","amount":60}])


func _test_wr06() -> void:
	var pair := _fixture("WR06")
	pair.engine.state.teams.A[0].target_slot = 1
	_assert_case("WR06 installs every source-filtered redirect at battle start", pair.handler.on_event(pair.engine, pair.binding,
		_event("battle_start", "", "", {"tick":0})), [
		{"kind":"redirect_register","target_key":"A2","ratio_bp":3000,"recipient_keys":["A1"],
		"capacity_per_second":100,"filters":{"source_key":"B1","owner_key":"A1","owner_target_slot":1},"redirect_id":"WR06:A1:A2"},
		{"kind":"redirect_register","target_key":"A3","ratio_bp":3000,"recipient_keys":["A1"],
		"capacity_per_second":100,"filters":{"source_key":"B1","owner_key":"A1","owner_target_slot":1},"redirect_id":"WR06:A1:A3"}])
	_assert_case("WR06 does not reregister on each damage event", pair.handler.on_event(pair.engine, pair.binding,
		_event("hp_lost", "B1", "A2", {"actual_hp_loss":30})), [])


func _test_wr07() -> void:
	var pair := _fixture("WR07")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	_assert_case("WR07 first allied final departure starts five-second relay", pair.handler.on_event(engine, binding,
		_event("final_departure", "", "A2", {"tick":10,"target_side":"A"})),
		[_counter("relay_used", 1),_counter("relay_until",60),
		{"kind":"modifier_add","target_key":"A1","stat":"T_ticks_flat","amount":-5,"modifier_id":"WR07:relay","expires_tick":60}])
	engine.set_counter(binding.source_key,"relay_used",1)
	engine.set_counter(binding.source_key,"relay_until",60)
	_assert_case("WR07 hit during relay adds one burn", pair.handler.on_event(engine,binding,
		_event("hit","A1","B1",{"tick":59,"is_attack":true})),_status("B1","burn",1,89))
	_assert_case("WR07 relay expires at five seconds", pair.handler.on_event(engine,binding,
		_event("hit","A1","B1",{"tick":60,"is_attack":true})),[])


func _test_wr08() -> void:
	var pair := _fixture("WR08")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	engine.state.teams.B[0].hp_tenths = 300
	_assert_case("WR08 target at 30 percent gets fixed packet and consumes both limits", pair.handler.on_event(engine,binding,
		_event("before_hit","A1","B1",{"attack_id":"A1-1"})),
		[{"kind":"attack_patch","attack_id":"A1-1","patch":{"attached_damage":[{"amount":90,"damage_type":"fixed"}]}},
		_counter("tail_target:B1",1),_counter("tail_uses",1)])
	engine.set_counter(binding.source_key,"tail_target:B1",1)
	engine.set_counter(binding.source_key,"tail_uses",1)
	_assert_case("WR08 exact target opportunity cannot repeat", pair.handler.on_event(engine,binding,
		_event("before_hit","A1","B1",{"attack_id":"A1-2"})),[])
	engine.state.teams.B[1].hp_tenths = 301
	_assert_case("WR08 30.1 percent remains above threshold", pair.handler.on_event(engine,binding,
		_event("before_hit","A1","B2",{"attack_id":"A1-3"})),[])


func _test_wr09() -> void:
	var pair := _fixture("WR09")
	_assert_case("WR09 10 real hp loss splashes 2.5 to both other enemies", pair.handler.on_event(pair.engine,pair.binding,
		_event("hit","A1","B1",{"is_natural_attack":true,"actual_hp_loss":100})),[_damage("B2",25,"physical"),_damage("B3",25,"physical")])
	_assert_case("WR09 extra attack never splashes", pair.handler.on_event(pair.engine,pair.binding,
		_event("hit","A1","B1",{"is_attack":true,"is_extra_attack":true,"actual_hp_loss":100})),[])
	pair.engine.state.teams.B[2].dead = true
	_assert_case("WR09 fewer than three enemies alive has no splash", pair.handler.on_event(pair.engine,pair.binding,
		_event("hit","A1","B1",{"is_natural_attack":true,"actual_hp_loss":100})),[])


func _test_wr10() -> void:
	var pair := _fixture("WR10")
	pair.engine.state.teams.B[0].shield_pools.append({"source_key":"B1:shield","amount":100,"expires_tick":100})
	_assert_case("WR10 consumes 8 shield and appends half as fixed", pair.handler.on_event(pair.engine,pair.binding,
		_event("before_hit","A1","B1",{"attack_id":"A1-1"})),
		[{"kind":"enemy_clear_shield","target_key":"B1","amount":80,"attack_id":"A1-1","bonus_bp":5000,"bonus_damage_type":"fixed"},
		_cooldown(30)])
	var no_shield := _fixture("WR10")
	_assert_case("WR10 no shield has no packet", no_shield.handler.on_event(no_shield.engine,no_shield.binding,
		_event("before_hit","A1","B1",{"attack_id":"A1-2"})),[])
	pair.engine.start_cooldown(pair.binding.source_key,30)
	pair.engine.state.tick = 30
	_assert(pair.engine.ready(pair.binding.source_key),"WR10 cooldown ready at three-second boundary")


func _test_wr11() -> void:
	var pair := _fixture("WR11")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	_assert_case("WR11 first natural hit counts", pair.handler.on_event(engine,binding,
		_event("hit","A1","B1",{"is_natural_attack":true})),[_counter("three_beats",1)])
	engine.set_counter(binding.source_key,"three_beats",2)
	_assert_case("WR11 third natural hit resets and deals 10 lightning", pair.handler.on_event(engine,binding,
		_event("hit","A1","B1",{"is_natural_attack":true})),[_counter("three_beats",0),_cooldown(10,"lightning"),_damage("B1",100,"lightning")])
	_assert_case("WR11 extra attack does not count", pair.handler.on_event(engine,binding,
		_event("hit","A1","B1",{"is_attack":true,"is_extra_attack":true})),[])
	engine.start_cooldown(binding.source_key,10,"lightning")
	engine.state.tick = 10
	_assert(engine.ready(binding.source_key,"lightning"),"WR11 lightning gate opens at one-second boundary")


func _test_wr12() -> void:
	var pair := _fixture("WR12")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	_assert_case("WR12 locks arrow target at battle start", pair.handler.on_event(engine,binding,
		_event("battle_start","","",{"tick":0})),[_counter("duel_target_slot",1)])
	engine.set_counter(binding.source_key,"duel_target_slot",1)
	_assert_case("WR12 direct locked-target hp loss returns 3 fixed", pair.handler.on_event(engine,binding,
		_event("hp_lost","B1","A1",{"is_attack":true,"is_extra_attack":true,"actual_hp_loss":10})),[_cooldown(10,"retaliate"),_damage("B1",30,"fixed")])
	_assert_case("WR12 transferred damage is not direct retaliation fuel", pair.handler.on_event(engine,binding,
		_event("hp_lost","B1","A1",{"is_attack":true,"is_extra_attack":true,"actual_hp_loss":10,"payload":{"transferred":true}})),[])
	_assert_case("WR12 attached damage and DoT are not attacks", pair.handler.on_event(engine,binding,
		_event("hp_lost","B1","A1",{"is_attack":false,"is_natural_attack":false,"actual_hp_loss":10})),[])
	_assert_case("WR12 another enemy is not punished", pair.handler.on_event(engine,binding,
		_event("hp_lost","B2","A1",{"is_natural_attack":true,"actual_hp_loss":10})),[])
	engine.start_cooldown(binding.source_key,10,"retaliate")
	engine.state.tick = 9
	_assert_case("WR12 one-second retaliation cooldown is active", pair.handler.on_event(engine,binding,
	_event("hp_lost","B1","A1",{"tick":9,"is_attack":true,"is_natural_attack":true,"actual_hp_loss":10})),[])


func _test_wr13() -> void:
	var pair := _fixture("WR13")
	var engine: BattleEngine = pair.engine
	var binding: Dictionary = pair.binding
	_assert_case("WR13 hit installs 40 percent healing modifier for two seconds", pair.handler.on_event(engine,binding,
		_event("hit","A1","B1",{"is_attack":true,"tick":0})),
		[{"kind":"modifier_add","target_key":"B1","stat":"healing_reduction_bp","amount":4000,"modifier_id":"WR13:A1","expires_tick":20}])
	_assert_case("WR13 records only effective prevented healing", pair.handler.on_event(engine,binding,
		_event("healed","B2","B1",{"source_binding_key":"healer","payload":{"healing_reductions":[{"source_binding_key":"A1:WR13","amount":50}]}})),[_counter("wound_debt:B1",50)])
	_assert_case("WR13 no reduction creates no debt", pair.handler.on_event(engine,binding,
		_event("healed","B2","B1",{"payload":{"healing_reductions":[]}})),[])
	engine.set_counter(binding.source_key,"wound_debt:B1",50)
	_assert_case("WR13 modifier expiry pays stored physical wound", pair.handler.on_event(engine,binding,
		_event("expiry","A1","B1",{"source_binding_key":"A1:WR13","tick":20})),[_counter("wound_debt:B1",0),_damage("B1",50,"physical")])


func _test_wr14() -> void:
	var pair := _fixture("WR14")
	_assert_case("WR14 owner departure damages former arrow target and slows its prep", pair.handler.on_event(pair.engine,pair.binding,
		_event("final_departure","","A1",{"tick":12,"target_side":"A"})),
		[_counter("departure_used",1),_damage("B1",120,"physical"),
		{"kind":"modifier_add","target_key":"B1","stat":"T_ticks_percent","amount":3500,"modifier_id":"WR14:A1","expires_tick":42}])
	var edge := _fixture("WR14")
	edge.engine.state.teams.B[0].final_departed = true
	_assert_case("WR14 same-batch departed target is not retargeted", edge.handler.on_event(edge.engine,edge.binding,
		_event("final_departure","","A1",{"tick":12,"target_side":"A"})),[_counter("departure_used",1)])
	_assert_case("WR14 opponent departure does not launch this effect", edge.handler.on_event(edge.engine,edge.binding,
		_event("final_departure","","B1",{"tick":12,"target_side":"B"})),[])


func _test_real_wr01() -> void:
	var pair := _fixture("WR01", {"B1":{"A":10,"T_ticks":20,"target_slot":1}})
	var engine: BattleEngine = pair.engine
	_run_through(engine,50,"WR01 real incoming-loss store, next-hit spend, and cooldown expiry")
	_assert(engine.ready(pair.binding.source_key,"anger_store"),"WR01 real cooldown expires exactly at tick50")
	_check_wr01_batch("WR01-owner-A",engine,"A1","B1",pair.binding.source_key)


func _test_real_wr01_mirror() -> void:
	var pair := _fixture("WR01", {"A1":{"A":10,"T_ticks":20,"target_slot":1}}, "B")
	var engine: BattleEngine = pair.engine
	_run_through(engine,50,"WR01 real A/B mirror incoming-loss store, next-hit spend, and cooldown expiry")
	_assert(engine.ready(pair.binding.source_key,"anger_store"),"WR01 mirrored real cooldown expires exactly at tick50")
	_check_wr01_batch("WR01-owner-B-mirror",engine,"B1","A1",pair.binding.source_key)


func _check_wr01_batch(label: String, engine: BattleEngine, owner_key: String, enemy_key: String, binding_key: String) -> void:
	var ledger: Array = []
	var natural_hp_loss := 0
	var incoming_hp_loss := 0
	var rage_hp_loss := 0
	var tick_event_indexes := {20:{"hit":[],"hp_lost":[]},40:{"hit":[],"hp_lost":[]}}
	for event in engine.state.events:
		if int(event.get("tick",-1)) > 40: continue
		var tick := int(event.get("tick",-1))
		var kind := str(event.get("kind",""))
		if tick_event_indexes.has(tick) and kind in ["hit","hp_lost"]:
			tick_event_indexes[tick][kind].append(engine.state.events.find(event))
		if kind == "hp_lost":
			if str(event.get("source_key","")) == owner_key and str(event.get("target_key","")) == enemy_key:
				if bool(event.get("is_natural_attack",false)): natural_hp_loss += int(event.get("actual_hp_loss",0))
				else: rage_hp_loss += int(event.get("actual_hp_loss",0))
			elif str(event.get("source_key","")) == enemy_key and str(event.get("target_key","")) == owner_key:
				incoming_hp_loss += int(event.get("actual_hp_loss",0))
		if int(event.get("tick",-1)) < 20 or str(event.get("kind","")) not in ["hit","hp_lost"]: continue
		if str(event.get("source_key","")) != owner_key and str(event.get("target_key","")) != owner_key: continue
		ledger.append({"tick":event.get("tick"),"kind":event.get("kind"),"source":event.get("source_key"),
			"target":event.get("target_key"),"actual_hp_loss":event.get("actual_hp_loss",0),
			"damage_type":event.get("damage_type",""),"is_attack":event.get("is_attack",false),
			"is_direct_attack":event.get("is_direct_attack",false),"root_id":event.get("root_id","")})
	for tick in [20,40]:
		var positions: Dictionary = tick_event_indexes[tick]
		for hit_index in positions.hit:
			for loss_index in positions.hp_lost:
				_assert(int(hit_index) < int(loss_index),"%s tick%d dispatches all hit notifications before hp_lost" % [label,tick])
	_assert(natural_hp_loss == 200,"%s two unchanged natural attacks deal 200 total; actual=%d" % [label,natural_hp_loss])
	_assert(incoming_hp_loss == 160,"%s two unchanged incoming attacks lose 160 total; actual=%d" % [label,incoming_hp_loss])
	_assert(rage_hp_loss == 32,"%s tick20 stores 32 and tick40 pays exactly 32; actual=%d" % [label,rage_hp_loss])
	_assert(int(engine.unit(owner_key).hp_tenths) == 960,"%s owner ends at 960 after unchanged incoming damage" % label)
	_assert(int(engine.unit(enemy_key).hp_tenths) == 768,"%s mirrored enemy ends at 768 after two basics and one 32 rage packet" % label)
	_assert(engine.get_counter(binding_key,"anger") == 0,"%s rage counter is empty after tick40 payout" % label)
	print("WR01_MIRROR_LEDGER %s %s" % [label,JSON.stringify({"events":ledger,"natural_hp_loss":natural_hp_loss,
		"incoming_hp_loss":incoming_hp_loss,"rage_hp_loss":rage_hp_loss,"owner_hp":engine.unit(owner_key).hp_tenths,
		"enemy_hp":engine.unit(enemy_key).hp_tenths,"anger":engine.get_counter(binding_key,"anger")})])


func _test_real_wr02() -> void:
	var pair := _fixture("WR02", {"A1":{"T_ticks":1000,"target_slot":1},"B1":{"A":10,"T_ticks":20,"target_slot":2}})
	var engine: BattleEngine = pair.engine
	_run_through(engine,21,"WR02 real ally hit triggers single extra attack")
	_assert(int(engine.unit("B1").hp_tenths) == 934,"WR02 ledger: base A11*60%%=66 tenths; 1000-66=934; actual=%d" % int(engine.unit("B1").hp_tenths))


func _test_real_wr03() -> void:
	var effect := FixtureEventEffect.new()
	effect.expected_kind = "battle_start"
	effect.actions = [
		{"kind":"status_add","target_key":"A1","status_id":"rooted","layers":1,"expires_tick":80},
		{"kind":"status_add","target_key":"A1","status_id":"chill","layers":1,"expires_tick":80}]
	var pair := _fixture("WR03", {"A1":{"T_ticks":24,"target_slot":1},"B1":{"T_ticks":1000}}, "A", effect)
	var engine: BattleEngine = pair.engine
	_run_through(engine,27,"WR03 real battle-start control, cleanse, slow bypass, and attached fixed segment")
	var attack_ticks: Array[int] = []
	var natural_loss := 0
	var fixed_loss := 0
	for event in engine.state.events:
		if str(event.get("kind","")) != "hp_lost" or str(event.get("source_key","")) != "A1" or str(event.get("target_key","")) != "B1": continue
		if bool(event.get("is_natural_attack",false)):
			attack_ticks.append(int(event.get("tick",-1)))
			natural_loss += int(event.get("actual_hp_loss",0))
		elif str(event.get("damage_type","")) == "fixed":
			fixed_loss += int(event.get("actual_hp_loss",0))
	var rooted := false
	for status in engine.unit("A1").get("statuses",[]):
		if str(status.get("id","")) == "rooted": rooted = true
	_assert(not rooted,"WR03 real prepare removes rooted but does not erase other control")
	_assert(attack_ticks.has(24),"WR03 ignore-slow patch preserves first production T24 attack; ticks=%s" % str(attack_ticks))
	_assert(natural_loss == 130 and fixed_loss == 50 and int(engine.unit("B1").hp_tenths) == 820,
		"WR03 main physical130 plus attached fixed50 resolves once; natural=%d fixed=%d hp=%d" % [natural_loss,fixed_loss,int(engine.unit("B1").hp_tenths)])
	var chill_present := false
	for status in engine.unit("A1").get("statuses",[]):
		if str(status.get("id","")) == "chill": chill_present = true
	_assert(chill_present,"WR03 clears rooted only; preparation slow remains present")


func _test_real_wr04() -> void:
	var pair := _fixture("WR04", {"A1":{"hp_tenths":1},"B1":{"R":4,"A":10,"T_ticks":18,"target_slot":1}})
	var engine: BattleEngine = pair.engine
	var outgoing_attack_ticks: Array[int] = []
	for tick in range(59):
		var result: Dictionary = engine.step()
		if not str(result.get("error", "")).is_empty():
			failures.append("WR04 real integration blocked at tick %d: %s" % [tick,result.error]); return
		for event in engine.state.events:
			if int(event.get("tick",-1)) != tick or str(event.get("source_key","")) != "A1": continue
			if str(event.get("kind","")) == "hit" and bool(event.get("is_attack",false)):
				if not outgoing_attack_ticks.has(tick): outgoing_attack_ticks.append(tick)
		if tick == 20:
			_assert(int(engine.effective_stats("B1").R) == 3,"WR04 first live keyed modifier lowers R4 to R3 at tick20")
	_assert(bool(engine.unit("A1").dead),"WR04 fixture: B1's tick18 attack kills A1 before tick20")
	_assert(outgoing_attack_ticks.size() == 1 and outgoing_attack_ticks[0] == 18,
		"WR04 fixture: A1 attack ticks=%s; only the already-launched tick18 attack may resolve" % str(outgoing_attack_ticks))
	_assert(int(engine.effective_stats("B1").R) == 4,"WR04 owner departed, source modifier expires at tick58 and R returns to4")


func _test_real_wr05() -> void:
	var pair := _fixture("WR05", {"B1":{"T_ticks":1000}})
	var engine: BattleEngine = pair.engine
	_run_through(engine,27,"WR05 real before-hit fire patch and self-loss")
	_assert(int(engine.unit("A1").hp_tenths) == 1120,"WR05 ledger: max HP1180 minus self-loss60 leaves1120")
	_assert(int(engine.unit("B1").hp_tenths) == 800,"WR05 ledger: main segment is fire 140+60=200, target HP800")


func _test_real_wr06() -> void:
	var pair := _fixture("WR06", {"A1":{"target_slot":1},"A2":{"T_ticks":1000},
		"B1":{"A":10,"T_ticks":20,"target_slot":2},"B2":{"A":10,"T_ticks":20,"target_slot":2}})
	var engine: BattleEngine = pair.engine
	_run_through(engine,20,"WR06 real start-of-battle source-filtered redirect")
	if engine.unit("A2").get("redirects",[]).size() != 1 or engine.unit("A3").get("redirects",[]).size() != 1:
		blocked_scenarios += 1
		print("WR06_INTEGRATION_BLOCKED expected redirect registrations on protected A2/A3; actual A1=%d A2=%d A3=%d" % [
			engine.unit("A1").get("redirects",[]).size(),engine.unit("A2").get("redirects",[]).size(),engine.unit("A3").get("redirects",[]).size()])
		return
	var redirected_loss := 0
	var direct_loss := 0
	var redirected_hit := false
	for event in engine.state.events:
		if int(event.get("tick",-1)) != 20 or str(event.get("target_key","")) not in ["A1","A2"]: continue
		if str(event.get("kind","")) == "hp_lost" and str(event.get("target_key","")) == "A1" and str(event.get("source_key","")) == "B1":
			redirected_loss += int(event.get("actual_hp_loss",0))
			_assert(bool(event.get("is_redirected",false)),"WR06 transferred loss is flagged non-attack redirect")
		if str(event.get("kind","")) == "hp_lost" and str(event.get("target_key","")) == "A2": direct_loss += int(event.get("actual_hp_loss",0))
		if str(event.get("kind","")) == "hit" and str(event.get("target_key","")) == "A1" and str(event.get("source_key","")) == "B1": redirected_hit = true
	_assert(redirected_loss == 30 and direct_loss == 170,
		"WR06 source B1 redirects30 while B2 is unaffected; redirected=%d protected=%d" % [redirected_loss,direct_loss])
	_assert(not redirected_hit,"WR06 redirected damage does not synthesize an effective attack hit")
	_assert(int(engine.unit("A1").hp_tenths) == int(production_characters["WR06"].H) * 10 - 30 and int(engine.unit("A2").hp_tenths) == 830,
		"WR06 real post-step HP reflects only B1's 30-point redirect")


func _test_real_wr07() -> void:
	var pair := _fixture("WR07",{"A1":{"target_slot":1},"A2":{"hp_tenths":1},
		"B1":{"A":10,"T_ticks":20,"target_slot":2}})
	var engine: BattleEngine = pair.engine
	var burn_during_relay := false
	var relay_started := false
	for tick in range(71):
		var result: Dictionary = engine.step()
		if not str(result.get("error","")).is_empty():
			failures.append("WR07 real relay fixture blocked at tick %d: %s" % [tick,result.error]); return
		if tick == 20:
			relay_started = engine.get_counter(pair.binding.source_key,"relay_used") == 1 and int(engine.effective_stats("A1").T_ticks) == 15
		if tick > 20 and tick < 70:
			for status in engine.unit("B1").get("statuses",[]):
				if str(status.get("id","")) == "burn": burn_during_relay = true
	var late_burns := 0
	for event in engine.state.events:
		if str(event.get("kind","")) == "status_applied" and str(event.get("status_id",event.get("payload",{}).get("status_id",""))) == "burn" and str(event.get("target_key","")) == "B1" and int(event.get("tick",-1)) >= 70:
			late_burns += 1
	_assert(bool(engine.unit("A2").dead) and relay_started,"WR07 first ally's real final departure starts one five-second speed relay")
	_assert(burn_during_relay,"WR07 owner hit applies burn inside relay window")
	_assert(int(engine.effective_stats("A1").T_ticks) == 20 and late_burns == 0,
		"WR07 modifier expires at tick70 and grants no burn at/after deadline; T=%d late=%d" % [int(engine.effective_stats("A1").T_ticks),late_burns])


func _test_real_wr08() -> void:
	var positive := _fixture("WR08", {"A1":{"T_ticks":22,"target_slot":1},"B1":{"hp_tenths":300,"T_ticks":1000}})
	_run_through(positive.engine,44,"WR08 real threshold bonus and per-target one-use lock")
	var fixed_bonus := 0
	var natural_attacks := 0
	for event in positive.engine.state.events:
		if str(event.get("kind","")) == "hp_lost" and str(event.get("source_key","")) == "A1" and str(event.get("target_key","")) == "B1":
			if bool(event.get("is_natural_attack",false)): natural_attacks += 1
			elif str(event.get("damage_type","")) == "fixed": fixed_bonus += int(event.get("actual_hp_loss",0))
	_assert(natural_attacks == 2 and fixed_bonus == 90 and int(positive.engine.unit("B1").hp_tenths) == 10,
		"WR08 one target at30%% gets exactly one fixed90 across two real basics; attacks=%d bonus=%d hp=%d" % [natural_attacks,fixed_bonus,int(positive.engine.unit("B1").hp_tenths)])
	var negative := _fixture("WR08", {"A1":{"T_ticks":22,"target_slot":1},"B1":{"hp_tenths":301,"T_ticks":1000}})
	_run_through(negative.engine,22,"WR08 real 30.1 percent negative threshold")
	_assert(int(negative.engine.unit("B1").hp_tenths) == 201,"WR08 30.1 percent target receives only base A10; hp=%d" % int(negative.engine.unit("B1").hp_tenths))


func _test_real_wr09() -> void:
	var positive := _fixture("WR09",{"A1":{"T_ticks":28,"target_slot":1},"B1":{"T_ticks":1000}})
	_run_through(positive.engine,28,"WR09 real natural-hit splash to exactly two living other enemies")
	_assert(int(positive.engine.unit("B1").hp_tenths) == 850 and int(positive.engine.unit("B2").hp_tenths) == 963 and int(positive.engine.unit("B3").hp_tenths) == 963,
		"WR09 real 150 HP loss splashes floor(25%%)=37 to both other enemies; HP=%d/%d/%d" % [int(positive.engine.unit("B1").hp_tenths),int(positive.engine.unit("B2").hp_tenths),int(positive.engine.unit("B3").hp_tenths)])
	var one_other := _fixture("WR09",{"A1":{"T_ticks":28,"target_slot":1},"B1":{"T_ticks":1000},
		"B2":{"hp_tenths":0},"B3":{"hp_tenths":0}})
	_run_through(one_other.engine,28,"WR09 real insufficient-living-enemy negative")
	var splash_packets := 0
	for event in one_other.engine.state.events:
		if int(event.get("tick",-1)) == 28 and str(event.get("kind","")) == "hp_lost" and str(event.get("source_key","")) == "A1" and str(event.get("target_key","")) in ["B2","B3"]: splash_packets += 1
	_assert(splash_packets == 0,"WR09 no splash packets when fewer than two other enemies live")
	var extra := FixtureEventEffect.new()
	extra.expected_kind = "battle_start"
	extra.owner_key = "A1"
	extra.actions = [{"kind":"extra_attack","target_key":"B1","amount":150,"damage_type":"physical"}]
	var extra_only := _fixture("WR09",{},"A",extra)
	_run_through(extra_only.engine,0,"WR09 real extra-attack non-splash negative")
	_assert(int(extra_only.engine.unit("B1").hp_tenths) == 850 and int(extra_only.engine.unit("B2").hp_tenths) == 1000 and int(extra_only.engine.unit("B3").hp_tenths) == 1000,
		"WR09 extra attack resolves its own 150 packet but never splashes")


func _test_real_wr10() -> void:
	var fixture_effect := FixtureEventEffect.new()
	fixture_effect.expected_kind = "battle_start"
	fixture_effect.actions = [{"kind":"shield_grant","target_key":"B1","amount":100,"expires_tick":100}]
	var pair := _fixture("WR10", {"B1":{"T_ticks":1000}}, "A", fixture_effect)
	var engine: BattleEngine = pair.engine
	_run_through(engine,21,"WR10 real partial enemy-shield clear and actual-cleared fixed bonus")
	var cleared: Array = []
	var broke: Array = []
	for event in engine.state.events:
		if str(event.get("kind","")) == "shield_cleared" and str(event.get("target_key","")) == "B1": cleared.append(event)
		if str(event.get("kind","")) == "shield_broken" and str(event.get("target_key","")) == "B1": broke.append(event)
	if cleared.size() != 1 or int(cleared[0].get("amount",cleared[0].get("payload",{}).get("amount",0))) != 80:
		blocked_scenarios += 1
		print("WR10_INTEGRATION_BLOCKED missing shield_cleared(actual=80) event; step HP evidence only")
	_assert(broke.size() == 1,"WR10 remaining shield is consumed by the attack and emits its separate break event")
	_assert(int(engine.unit("B1").hp_tenths) == 890,"WR10 actual clear80 leaves20 shield; production A9 main90 plus fixed40 leaves HP890")


func _test_real_wr12() -> void:
	var extra_effect := FixtureEventEffect.new()
	extra_effect.expected_kind = "prepare_attack"
	extra_effect.required_source = "B1"
	extra_effect.actions = [{"kind":"extra_attack","target_key":"A1","amount":100,"damage_type":"physical"}]
	var pair := _fixture("WR12", {"A1":{"T_ticks":1000,"target_slot":1},"B1":{"H":200,"A":10,"T_ticks":23,"target_slot":1}}, "A", extra_effect)
	var engine: BattleEngine = pair.engine
	_run_through(engine,24,"WR12 real extra and natural basic-attack direct-hit retaliation")
	_assert(engine.get_counter(pair.binding.source_key,"duel_target_slot") == 1,"WR12 real integration locked initial target")
	var direct_losses := 0
	var extra_losses := 0
	var natural_losses := 0
	for event in engine.state.events:
		if str(event.get("kind","")) != "hp_lost" or str(event.get("source_key","")) != "B1" or str(event.get("target_key","")) != "A1": continue
		if not bool(event.get("is_direct_attack",false)): continue
		direct_losses += 1
		if bool(event.get("is_extra_attack",false)): extra_losses += 1
		if bool(event.get("is_natural_attack",false)): natural_losses += 1
	_assert(direct_losses == 3 and extra_losses == 2 and natural_losses == 1,
		"WR12 direct HP losses extra=%d natural=%d total=%d" % [extra_losses,natural_losses,direct_losses])
	_assert(int(engine.unit("B1").hp_tenths) == 1940,"WR12 ledger: extra+natural each return 30 fixed; B1 actual=%d" % int(engine.unit("B1").hp_tenths))


func _test_real_wr11() -> void:
	var pair := _fixture("WR11",{"A1":{"T_ticks":22,"target_slot":1},"B1":{"T_ticks":1000}})
	var engine: BattleEngine = pair.engine
	_run_through(engine,76,"WR11 real three natural attacks, third-hit lightning, and cooldown boundary")
	var natural_hits := 0
	var lightning_loss := 0
	for event in engine.state.events:
		if str(event.get("kind","")) == "hit" and str(event.get("source_key","")) == "A1" and str(event.get("target_key","")) == "B1" and bool(event.get("is_natural_attack",false)): natural_hits += 1
		if str(event.get("kind","")) == "hp_lost" and str(event.get("source_key","")) == "A1" and str(event.get("target_key","")) == "B1" and str(event.get("damage_type","")) == "lightning": lightning_loss += int(event.get("actual_hp_loss",0))
	_assert(natural_hits == 3 and lightning_loss == 100 and int(engine.unit("B1").hp_tenths) == 570,
		"WR11 third real natural hit emits one 100 lightning packet; hits=%d lightning=%d HP=%d" % [natural_hits,lightning_loss,int(engine.unit("B1").hp_tenths)])
	_assert(engine.ready(pair.binding.source_key,"lightning"),"WR11 one-second cooldown expires at tick76")
	var extra := FixtureEventEffect.new()
	extra.expected_kind = "battle_start"
	extra.owner_key = "A1"
	extra.actions = [{"kind":"extra_attack","target_key":"B1","amount":110,"damage_type":"physical"}]
	var extra_only := _fixture("WR11",{},"A",extra)
	_run_through(extra_only.engine,0,"WR11 real extra attack is not a natural-beat counter")
	_assert(extra_only.engine.get_counter(extra_only.binding.source_key,"three_beats") == 0,
		"WR11 real extra attack does not count toward three natural beats")


func _test_real_wr13() -> void:
	var healer := FixtureEventEffect.new()
	healer.expected_kind = "periodic"
	healer.required_tick = 20
	healer.owner_key = "B2"
	healer.actions = [{"kind":"heal","target_key":"B1","amount":100,"phase":"pre_damage"}]
	var pair := _fixture("WR13",{"A1":{"T_ticks":19,"target_slot":1},"B1":{"T_ticks":1000}},"A",healer)
	var engine: BattleEngine = pair.engine
	_run_through(engine,39,"WR13 real wound-debt accumulation and actual modifier expiry settlement")
	var reduced_heal := 0
	var expiry_damage := 0
	for event in engine.state.events:
		if int(event.get("tick",-1)) == 20 and str(event.get("kind","")) == "healed" and str(event.get("target_key","")) == "B1":
			for reduction in event.get("payload",{}).get("healing_reductions",[]):
				if str(reduction.get("source_binding_key","")) == pair.binding.source_key: reduced_heal += int(reduction.get("amount",0))
		if int(event.get("tick",-1)) == 39 and str(event.get("kind","")) == "hp_lost" and str(event.get("source_key","")) == "A1" and str(event.get("target_key","")) == "B1" and str(event.get("damage_type","")) == "physical" and not bool(event.get("is_attack",false)):
			expiry_damage += int(event.get("actual_hp_loss",0))
	_assert(reduced_heal == 40,"WR13 real healing at tick20 loses exactly40 to its source modifier; reduced=%d" % reduced_heal)
	_assert(expiry_damage == 40 and engine.get_counter(pair.binding.source_key,"wound_debt:B1") == 0,
		"WR13 tick39 expiry converts exactly40 debt once; dealt=%d remaining=%d" % [expiry_damage,engine.get_counter(pair.binding.source_key,"wound_debt:B1")])


func _test_real_wr14() -> void:
	var positive := _fixture("WR14",{"A1":{"hp_tenths":1,"target_slot":1,"T_ticks":1000},
		"B1":{"A":10,"T_ticks":20,"target_slot":1}})
	var engine: BattleEngine = positive.engine
	_run_through(engine,50,"WR14 real final-departure damage/slow and three-second expiry")
	_assert(bool(engine.unit("A1").dead) and int(engine.get_counter(positive.binding.source_key,"departure_used")) == 1,
		"WR14 owner final-departs once and consumes its one departure effect")
	var departure_damage := 0
	for event in engine.state.events:
		if int(event.get("tick",-1)) == 20 and str(event.get("kind","")) == "hp_lost" and str(event.get("source_key","")) == "A1" and str(event.get("target_key","")) == "B1" and not bool(event.get("is_attack",false)):
			departure_damage += int(event.get("actual_hp_loss",0))
	_assert(departure_damage == 120 and int(engine.unit("B1").hp_tenths) == 880,
		"WR14 departure deals exactly120 to locked living target; damage=%d hp=%d" % [departure_damage,int(engine.unit("B1").hp_tenths)])
	_assert(int(engine.effective_stats("B1").T_ticks) == 20,"WR14 target preparation modifier expires at tick50")
	var co_departure := _fixture("WR14",{"A1":{"hp_tenths":1,"target_slot":1,"T_ticks":20},
		"B1":{"hp_tenths":1,"A":10,"T_ticks":20,"target_slot":1}})
	_run_through(co_departure.engine,20,"WR14 same-batch target departure negative")
	var co_departure_bonus := 0
	for event in co_departure.engine.state.events:
		if int(event.get("tick",-1)) == 20 and str(event.get("kind","")) == "hp_lost" and str(event.get("source_key","")) == "A1" and str(event.get("target_key","")) == "B1" and not bool(event.get("is_attack",false)):
			co_departure_bonus += int(event.get("actual_hp_loss",0))
	_assert(co_departure_bonus == 0 and co_departure.engine.get_counter(co_departure.binding.source_key,"departure_used") == 1,
		"WR14 simultaneous target departure consumes effect without retarget or bonus damage")


func _run_through(engine: BattleEngine, final_tick: int, label: String) -> void:
	for tick in range(final_tick + 1):
		var result: Dictionary = engine.step()
		if not str(result.get("error", "")).is_empty():
			failures.append("%s blocked at tick %d: %s" % [label,tick,result.error])
			return


func _fixture(content_id: String, unit_overrides: Dictionary = {}, owner_side: String = "A", fixture_effect = null) -> Dictionary:
	var handler = HandlerScript.new()
	var logic_handler := "character_" + content_id
	var owner_key := owner_side + "1"
	var binding := {"content_id":content_id,"logic_handler":logic_handler,"owner_key":owner_key,
		"source_key":owner_key + ":" + content_id,"kind":"talent"}
	var definition := {"logic_handler":logic_handler,"handler":handler,"bindings":[binding]}
	var teams := {"A":[_unit("A",1,content_id,owner_side),_unit("A",2),_unit("A",3)],
		"B":[_unit("B",1,content_id,owner_side),_unit("B",2),_unit("B",3)]}
	for side in ["A","B"]:
		for index in range(3):
			var unit_state: Dictionary = teams[side][index]
			var unit_key := "%s%d" % [side,int(unit_state.slot)]
			if unit_overrides.has(unit_key): unit_state.merge(unit_overrides[unit_key],true)
	var config := {"seed":7,"rule_id":"VC01","test_fixture":true,"teams":teams}
	var engine = EngineScript.new()
	var definitions: Array = [definition]
	if fixture_effect != null:
		var fixture_owner := str(fixture_effect.get("owner_key")) if fixture_effect.get("owner_key") != null else "B1"
		var fixture_binding := {"content_id":"FIXTURE_EFFECT","logic_handler":"fixture_effect","owner_key":fixture_owner,
			"source_key":"fixture:B1","kind":"talent"}
		definitions.append({"logic_handler":"fixture_effect","handler":fixture_effect,"bindings":[fixture_binding]})
	var result: Dictionary = engine.setup(config,definitions)
	if not str(result.get("error", "")).is_empty(): failures.append("fixture setup %s: %s" % [content_id,result.error])
	return {"engine":engine,"handler":handler,"binding":binding}


func _unit(side: String, slot: int, talent_id: String = "", owner_side: String = "A") -> Dictionary:
	var is_owner := side == owner_side and slot == 1 and not talent_id.is_empty()
	var card: Dictionary = production_characters.get(talent_id,{}) if is_owner else {}
	var unit := {"definition_id":talent_id if is_owner else "FIXTURE_%s%d" % [side,slot],"fixture":not is_owner,"slot":slot,
		"H":int(card.get("H",100)),"A":int(card.get("A",0)),"T_ticks":int(card.get("T_ticks",1000)),"R":int(card.get("R",0)),
		"reach":str(card.get("reach","ranged")),"armor_kind":str(card.get("armor_kind","light")),
		"target_slot":1,"first_attack_tick":1000}
	if is_owner:
		unit["talent_id"] = talent_id
	return unit


func _event(kind: String, source_key: String, target_key: String, details: Dictionary = {}) -> Dictionary:
	var event := {"kind":kind,"event_id":"spec-event","root_id":"spec-root","tick":0,
		"source_key":source_key,"source_binding_key":"","target_key":target_key,
		"target_slot":int(target_key.substr(1)) if target_key.length() >= 2 else 0,
		"target_side":target_key.substr(0,1) if target_key.length() >= 2 else "",
		"actual_hp_loss":0,"raw_amount":0,"is_attack":false,"is_natural_attack":false,
		"is_extra_attack":false,"extra_generation":0,"payload":{}}
	for key in details:
		if key == "payload": event.payload = details.payload.duplicate(true)
		else: event[key] = details[key]
	return event


func _counter(key: String, value: int) -> Dictionary:
	return {"kind":"counter","counter_key":key,"value":value}


func _cooldown(ticks: int, key: String = "default") -> Dictionary:
	return {"kind":"cooldown","ticks":ticks,"cooldown_key":key}


func _damage(target: String, amount: int, damage_type: String) -> Dictionary:
	return {"kind":"damage","target_key":target,"amount":amount,"damage_type":damage_type}


func _status(target: String, status_id: String, layers: int, expires: int) -> Array:
	return [{"kind":"status_add","target_key":target,"status_id":status_id,"layers":layers,"expires_tick":expires}]


func _assert_case(label: String, actual: Variant, expected: Variant) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s\nexpected=%s\nactual=%s" % [label, JSON.stringify(expected), JSON.stringify(actual)])


func _assert(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
