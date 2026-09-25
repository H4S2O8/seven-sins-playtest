extends SceneTree
const Assembler = preload("res://content/battle_assembler.gd")
const Battle = preload("res://core/battle/battle_engine.gd")
const Session = preload("res://core/session/session.gd")
const Command = preload("res://core/types/command.gd")
const AttachmentHandlers = preload("res://content/attachments/attachment_handlers.gd")
const EnvironmentHandlers = preload("res://content/environment/environment_handlers.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void:
	var assembly = Assembler.new()
	_check(assembly.load_error.is_empty(), "all 268 behavior definitions load without gaps")
	var request := _request()
	var fingerprint := JSON.stringify(request)
	var formal: Dictionary = assembly.build(request)
	_check(str(formal.error).is_empty(), "formal play admits a request composed only of real supported handlers: " + str(formal.error))
	var built: Dictionary = assembly.build(request, true)
	_check(str(built.error).is_empty(), "real installed contents assemble: " + str(built.error))
	if not str(built.error).is_empty(): _finish(); return
	_check(JSON.stringify(request) == fingerprint, "assembler never mutates committed source")
	_check(not built.config.has("test_fixture"), "real source data, no fixture substitution")
	_check(built.integration_review_only, "local review marked, not production acceptance")
	_check(built.config.teams.A[0].A == 10, "bare WR01 A remains10 before setup EQ01")
	_check(built.config.teams.A[1].H == 86, "bare WR02 H remains86 before setup EQ02")
	_check(built.config.teams.B[0].definition_id == "WR01", "same character can occur on opposite teams")
	_check(built.config.teams.A[0].target_slot == 3, "committed public arrow reaches correct engine unit")
	var fx43_bindings: Array = []
	var wr01_sources: Array = []
	var global_arena_count := 0
	for row in built.handlers:
		for binding in row.bindings:
			if binding.content_id == "FX43": fx43_bindings.append(binding)
			if binding.content_id == "WR01": wr01_sources.append(binding.source_key)
			if binding.content_id == "AR02": global_arena_count += 1
	_check(fx43_bindings.size() == 1 and fx43_bindings[0].get("trigger_scope", "") == "event_target", "explicit per-recipient guard retained through actual adapter")
	_check(wr01_sources.has("A1:WR01") and wr01_sources.has("B1:WR01"), "same-ID opposing talents keep independent instance counters")
	_check(global_arena_count == 1, "global arena is bound once, not once per team")
	var engine = Battle.new()
	var setup: Dictionary = engine.setup(built.config, built.handlers)
	_check(str(setup.get("error", "")).is_empty(), "real engine accepts assembled config")
	_check(engine.effective_stats("A1").A == 13 and engine.unit("A1").base_A == 10, "equipment changes actual attack but not bare panel")
	_check(engine.unit("A2").hp_tenths == 1040 and engine.unit("A2").base_H == 86, "+18H changes both max and current once")
	var simulation: Dictionary = assembly.simulate(request, true)
	_check(str(simulation.get("error", "")).is_empty(), "real full battle completes without missing ability errors")
	_check(bool(simulation.get("terminal", false)), "assembled battle reaches actual victory/deadline")
	_check(simulation.has("content_coverage") and simulation.get("content_coverage", {}).has("fixture_ids"), "coverage evidence must be present, not default to an empty list")
	_check(simulation.get("content_coverage", {}).get("fixture_ids", ["MISSING"]).is_empty(), "full battle has zero fake fixture units")
	var replay: Dictionary = assembly.simulate(request, true)
	_check(simulation.get("tick_hashes", []) == replay.get("tick_hashes", []), "same request reproduces identical real battle")
	_test_rejections(assembly)
	_test_default_supported_pools(assembly)
	_test_session_bridge(assembly)
	_finish()

func _request() -> Dictionary:
	return {"seed":93421,"rule_id":"VC21","arena_id":"AR02","public_effect_ids":["PE05"],
		"teams":{"player":[_slot(1,"WR01"),_slot(2,"WR02"),_slot(3,"WR05")],
			"opponent":[_slot(1,"WR01"),_slot(2,"WR04"),_slot(3,"WR10")]},
		"installed_cards":{"player":["EQ01","EQ02","EQ03","FX43","", ""],"opponent":[]},
		"arrows":{"player":[3,2,1],"opponent":[1,2,3]}}

func _slot(n: int, id: String) -> Dictionary:
	return {"slot":n,"definition_id":id}

func _test_rejections(assembly) -> void:
	var request := _request()
	request.teams.player[1].definition_id = "WR01"
	_check(str(assembly.build(request,true).error).begins_with("duplicate_character_in_team"), "duplicate within same team rejected")
	request = _request(); request.teams.player[1].definition_id = "FAKE"
	_check(str(assembly.build(request,true).error).begins_with("unknown_character"), "unknown talent cannot become blank unit")
	request = _request(); request.teams.player[1].definition_id = "GL03"
	_check(str(assembly.build(request).error).begins_with("unimplemented_content_handler"), "known but unsupported talent stays outside formal play")
	request = _request(); request.installed_cards.player[0] = "EQ50"
	_check(str(assembly.build(request).error).begins_with("unimplemented_content_handler"), "known but unsupported attachment stays outside formal play")
	request = _request(); request.arena_id = "AR12"
	_check(str(assembly.build(request).error).begins_with("unimplemented_content_handler"), "known but unsupported arena stays outside formal play")
	request = _request(); request.installed_cards.player[0] = "FX43"
	_check(str(assembly.build(request,true).error).begins_with("attachment_wrong_slot"), "effect cannot occupy equipment socket")
	request = _request(); request.arrows.player[1] = 4
	_check(str(assembly.build(request,true).error).begins_with("target_slot_invalid"), "out of range arrow rejected")
	request = _request(); request.public_effect_ids = ["PE05","PE05"]
	_check(str(assembly.build(request,true).error).begins_with("invalid_or_duplicate_public_effect"), "public effect duplicated by corrupt state rejected")
	request = _request(); request.rule_id = "VC99"
	_check(str(assembly.build(request,true).error).begins_with("unknown_victory_rule"), "unknown rule rejected")
	request = _request(); request.teams.player[2].slot = 2
	_check(str(assembly.build(request,true).error).begins_with("team_slot_order_invalid"), "slots cannot be silently sorted into a different roster")

func _test_default_supported_pools(assembly) -> void:
	var session = Session.new({"seed":20260925,"first_actor":"player","ante":0})
	var environment = EnvironmentHandlers.new()
	_check(session.draft_pool.all(func(id: Variant) -> bool: return AttachmentHandlers.supports_content_id(str(id))),
		"default draft pool contains only attachments with real handlers")
	_check(session.public_effect_pool.all(func(id: Variant) -> bool: return environment.supports_content_id(str(id))),
		"default public-effect queue contains only effects with real handlers")
	_check(environment.supports_content_id(str(session.state.arena_id)),
		"default arena draw contains only arenas with real handlers")
	session.state.phase = "BATTLE_READY"
	var built: Dictionary = assembly.build_from_session(session.state)
	_check(str(built.error).is_empty(), "a default formal Session assembles without review mode: " + str(built.error))

func _test_session_bridge(assembly) -> void:
	var session = Session.new({"seed":91,"teams":_request().teams,"first_actor":"player",
		"public_effect_pool":["PE05","PE09","PE10"],"player_table":100,"opponent_table":100})
	# Rule/arena are fixed scenario input; all progression below is via legal commands.
	session.state.rule_id = "VC21"
	session.state.arena_id = "AR02"
	_check(assembly.build_from_session(session.state,true).error == "hand_not_ready_for_battle", "cannot peek/finalize unresolved hand through bridge")
	var safety := 0
	while session.state.phase != "BATTLE_READY" and safety < 25:
		safety += 1
		var result: Dictionary
		if session.state.phase == "BETTING":
			result = session.apply(Command.new("bridge%d" % safety, session.state.acting_side, "check", {}, session.state.revision))
		elif session.state.phase == "PUBLIC_COMMIT":
			var side := "opponent" if session.state.public_commits.has("player") else "player"
			result = session.apply(Command.new("bridge%d" % safety, side, "public_decision", {"activate":session.state.current_public_effect == "PE05"}, session.state.revision))
		else:
			_check(false,"unexpected legal session phase:" + str(session.state.phase)); return
		_check(bool(result.get("accepted",false)), "session command accepted at step%d: %s" % [safety,result.get("reason","")])
	_check(session.state.phase == "BATTLE_READY", "checks and public choices actually reach battle")
	var before := session.snapshot()
	var built: Dictionary = assembly.build_from_session(session.state,true)
	_check(str(built.error).is_empty(), "committed session assembles")
	if not str(built.error).is_empty(): return
	_check(built.config.public_effect_ids == ["PE05"], "declined public effects do not enter battle")
	_check(session.snapshot() == before, "assembly cannot spend money, advance RNG or reveal teams")
	var engine = Battle.new()
	var battle: Dictionary = engine.simulate(built.config,built.handlers)
	_check(str(battle.get("error","")).is_empty() and bool(battle.get("terminal",false)), "session-derived battle completes")
	var winning_side := "tie" if battle.get("winner",null) == null else ("player" if str(battle.winner) == "A" else "opponent")
	var settled: Dictionary = session.settle_battle(winning_side)
	_check(bool(settled.get("accepted",false)), "real winner pays pot through original economy")
	_check(session.ledger.total_chips() == 200 and session.ledger.balances.pot == 0, "full check→reveal→battle→payout conserves chips")
	var after := session.snapshot()
	_check(not session.settle_battle(winning_side).accepted and session.snapshot() == after, "payout cannot be collected twice")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _finish() -> void:
	for failure in failures: print("FAIL: ",failure)
	print("ASTRA_ASSEMBLER_REVIEW checks=%d failed=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
