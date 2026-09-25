extends SceneTree
const AI = preload("res://core/ai/table_ai.gd")
const Session = preload("res://core/session/session.gd")
const Legal = preload("res://core/legal_actions/legal_actions.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ai = AI.new(true,["WR01","WR02","WR04","WR05","WR10"])
	ai.hypothesis_count = 1
	var session = _session()
	var observed: Dictionary = session.observation("player")
	var frozen := var_to_str(observed)
	var actions: Array = Legal.list_actions(observed)
	var first: Dictionary = await ai.choose(observed,actions,9245,"cautious",self)
	_check(str(first.error).is_empty(),"actual handler-backed estimate succeeds: "+str(first.error))
	if not str(first.error).is_empty(): _finish(); return
	_check(first.diagnostics.simulations>0 and first.diagnostics.covered_handler_ids.has("WR01"),"actual character handlers simulated, not zero-handler fixture")
	_check(var_to_str(observed)==frozen,"observation input remains immutable")
	_check(first.command.actor=="player" and first.command.expected_revision==observed.revision,"legal side and exact revision preserved")
	var modified := observed.duplicate(true)
	modified["private"] = {"opponent_team":["PR14","GR08","SL14"]}
	modified.opponent_public["team"] = [{"definition_id":"PR14"}]
	modified.opponent_public["team_sealed"] = false
	var second: Dictionary = await ai.choose(modified,actions,9245,"cautious",self)
	_check(second.command.type==first.command.type and second.command.payload==first.command.payload,"extraneous hidden or untrusted enemy identity never changes decision")
	_check(second.diagnostics.simulations==0 and second.diagnostics.cache_hits>0,"cache uses observable committed configuration, not hidden fields")
	_check(bool(session.apply(first.command).accepted),"real Session accepts AI command")
	var same_hypotheses: Array = first.diagnostics.hypotheses
	observed.phase = "DRAFT_SELECTION"
	observed.revision = 5
	var draft_actions: Array = [{"type":"choose_draft_card","offer":["EQ01","EQ02","EQ18"],"external_slots":[1,2,3]}]
	var drafted: Dictionary = await ai.choose(observed,draft_actions,9245,"cautious",self)
	_check(str(drafted.error).is_empty(),"three cards by three concrete sockets evaluated")
	if not str(drafted.error).is_empty(): _finish(); return
	_check(drafted.command.type=="choose_draft_card","draft chooses an actual card")
	_check(drafted.command.payload.card_id in ["EQ01","EQ02","EQ18"] and drafted.command.payload.slot in [1,2,3],"draft stays inside supplied offer and sockets")
	_check(drafted.diagnostics.simulations==9,"all nine offered-card/socket combinations are simulated once")
	_check(drafted.diagnostics.hypotheses==same_hypotheses,"same hand retains the same hypothetical enemy teams across revisions")
	_check(drafted.diagnostics.covered_handler_ids.has("EQ18"),"card valuation executes its real on-hit heal")
	var before_public := observed.duplicate(true)
	before_public.phase = "PUBLIC_COMMIT"
	before_public.revision = 6
	before_public.your_private.installed_cards = ["EQ18","EQ18","EQ18","","",""]
	before_public.public.current_public_effect = "PE31"
	before_public.public.revealed_effects = [{"id":"PE31","status":"awaiting_joint_decision"}]
	var public_actions: Array = [{"type":"public_decision","activate":true},{"type":"public_decision","activate":false}]
	var public_choice: Dictionary = await ai.choose(before_public,public_actions,9245,"cautious",self)
	_check(str(public_choice.error).is_empty(),"effect-on and effect-off simulations complete")
	_check(public_choice.diagnostics.covered_handler_ids.has("PE31"),"public effect is executed, not assigned a constant preference")
	_check(float(public_choice.diagnostics.public_effect_delta) != 0.0,"healing-sensitive team yields a real public effect value difference")
	_check(bool(public_choice.command.payload.activate)==(float(public_choice.diagnostics.public_effect_delta)>0),"choice follows simulated relative benefit")
	var unknown := before_public.duplicate(true)
	unknown.public.current_public_effect = "PE999"
	var rejected: Dictionary = await ai.choose(unknown,public_actions,9245,"cautious",self)
	_check(not str(rejected.error).is_empty() and rejected.command==null,"missing content cannot silently turn into a baseline bot")
	var release_ai = AI.new()
	var blocked: Dictionary = await release_ai.choose(session.observation("opponent"),Legal.list_actions(session.observation("opponent")),5,"cautious",self)
	_check(not str(blocked.error).is_empty(),"unapproved content remains blocked in release mode")
	print("ASTRA_AI_CHOICE draft=%s slot=%d public_delta=%.6f public_want=%s" % [drafted.command.payload.card_id,drafted.command.payload.slot,public_choice.diagnostics.public_effect_delta,public_choice.command.payload.activate])
	_finish()

func _session() -> SinSession:
	var session = Session.new({"seed":777,"first_actor":"player","public_effect_pool":["PE05","PE17","PE31"],
		"teams":{"player":[_u(1,"WR01"),_u(2,"WR02"),_u(3,"WR05")],"opponent":[_u(1,"WR01"),_u(2,"WR04"),_u(3,"WR10")]}})
	session.state.rule_id = "VC21"
	session.state.arena_id = "AR02"
	return session
func _u(slot: int,id: String) -> Dictionary: return {"slot":slot,"definition_id":id}
func _check(condition: bool,message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
func _finish() -> void:
	for failure in failures: push_error(failure)
	print("ASTRA_TABLE_AI checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
