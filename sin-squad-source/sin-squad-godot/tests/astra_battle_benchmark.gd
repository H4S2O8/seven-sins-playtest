extends SceneTree
const Assembler = preload("res://content/battle_assembler.gd")
const Battle = preload("res://core/battle/battle_engine.gd")
func _init() -> void:
	var assembler = Assembler.new()
	var request := {"seed":123,"rule_id":"VC21","arena_id":"AR02","public_effect_ids":["PE05"],
		"teams":{"player":[_u(1,"WR01"),_u(2,"WR02"),_u(3,"WR05")],"opponent":[_u(1,"WR01"),_u(2,"WR04"),_u(3,"WR10")]},
		"installed_cards":{"player":["EQ01","EQ02","EQ03","FX43","", ""],"opponent":[]},
		"arrows":{"player":[3,2,1],"opponent":[1,2,3]}}
	var results: Array = []
	for capture in [true,false]:
		var built: Dictionary = assembler.build(request,true)
		if not str(built.error).is_empty(): push_error(str(built.error)); quit(1); return
		var clock := Time.get_ticks_usec()
		var result: Dictionary = Battle.new().simulate(built.config,built.handlers,{"capture_tick_hashes":capture})
		print("BENCHMARK hashes=%s duration_ms=%.2f events=%d terminal=%s" % [capture,(Time.get_ticks_usec()-clock)/1000.0,result.events.size(),result.terminal])
		results.append(result)
	if results[0].events != results[1].events or results[0].snapshot != results[1].snapshot or results[0].winner != results[1].winner:
		push_error("Fast path semantic difference");quit(1);return
	print("ASTRA_BENCHMARK_SEMANTICS_MATCH")
	quit(0)
func _u(slot: int,id: String) -> Dictionary:
	return {"slot":slot,"definition_id":id}
