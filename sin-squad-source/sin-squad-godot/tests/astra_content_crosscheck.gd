extends SceneTree

const Assembler = preload("res://content/battle_assembler.gd")
const PEOPLE := ["WR01","WR02","WR04","WR05","WR10","WR12","GR04","GR09"]
const EQUIPMENT := ["EQ01","EQ02","EQ03","EQ04","EQ05","EQ06","EQ07","EQ08","EQ10","EQ11","EQ18","EQ23"]
const SLOTS := ["FX02","FX06","FX18","FX43"]
const ARENAS := ["AR01","AR02","AR05","AR08","AR13","AR16"]
const PUBLIC_EFFECTS := ["PE05","PE09","PE17","PE31"]
var checks := 0
var pairs := 0
var failures: Array[String] = []
var coverage: Dictionary = {}

func _init() -> void:
	var assembler = Assembler.new()
	for index in range(16):
		var request := _request(index)
		var mirror := request.duplicate(true)
		for field in ["teams", "arrows", "installed_cards"]:
			mirror[field].player = request[field].opponent.duplicate(true)
			mirror[field].opponent = request[field].player.duplicate(true)
		var normal: Dictionary = assembler.simulate(request,true)
		var reflected: Dictionary = assembler.simulate(mirror,true)
		_check(str(normal.get("error","")).is_empty(), "case%d error=%s" % [index,normal.get("error","")])
		_check(str(reflected.get("error","")).is_empty(), "mirror%d error=%s" % [index,reflected.get("error","")])
		if not str(normal.get("error","")).is_empty() or not str(reflected.get("error","")).is_empty(): continue
		_check(normal.terminal and reflected.terminal, "case%d actual completion" % index)
		_check(normal.snapshot.tick == reflected.snapshot.tick, "case%d end tick %s/%s" % [index,normal.snapshot.tick,reflected.snapshot.tick])
		_check(_swap(normal.winner) == str(reflected.winner), "case%d winner %s/%s" % [index,normal.winner,reflected.winner])
		_check(normal.get("content_coverage",{}).get("fixture_ids",["MISSING"]).is_empty() and reflected.get("content_coverage",{}).get("fixture_ids",["MISSING"]).is_empty(), "case%d no fixture replacements" % index)
		for id in normal.get("content_coverage",{}).get("handler_ids",[]): coverage[id] = true
		for side in ["A","B"]:
			for slot in range(3):
				var before: Dictionary = normal.snapshot.teams[side][slot]
				var after: Dictionary = reflected.snapshot.teams[_swap(side)][slot]
				for field in ["hp_tenths","dead","final_departed","first_natural_attack_tick"]:
					_check(before.get(field) == after.get(field), "case%d %s%d %s %s/%s" % [index,side,slot+1,field,before.get(field),after.get(field)])
		pairs += 1
		if failures.size() > 30: break
	_check(pairs == 16, "all16 real-content pairs reached completion")
	for failure in failures: print("FAIL: ",failure)
	var ids: Array = coverage.keys(); ids.sort()
	print("COVERED_IDS: ",JSON.stringify(ids))
	print("ASTRA_CONTENT_CROSSCHECK checks=%d pairs=%d unique_handlers=%d failures=%d" % [checks,pairs,coverage.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)

func _request(index: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 92593 + index * 41
	var request := {"seed":int(rng.seed),"rule_id":"VC%02d" % ([1,2,6,9,14,18,21,22][index%8]),
		"arena_id":ARENAS[index % ARENAS.size()],"public_effect_ids":[PUBLIC_EFFECTS[index % PUBLIC_EFFECTS.size()]],
		"teams":{"player":[],"opponent":[]},"installed_cards":{"player":[],"opponent":[]},
		"arrows":{"player":[],"opponent":[]}}
	for side in ["player","opponent"]:
		var people: Array = PEOPLE.duplicate()
		for i in range(people.size()-1,0,-1):
			var swap := rng.randi_range(0,i)
			var old: Variant = people[i]; people[i] = people[swap]; people[swap] = old
		for slot in range(3):
			request.teams[side].append({"slot":slot+1,"definition_id":people[slot]})
			request.arrows[side].append(rng.randi_range(1,3))
			request.installed_cards[side].append(EQUIPMENT[rng.randi_range(0,EQUIPMENT.size()-1)])
		for slot in range(3): request.installed_cards[side].append(SLOTS[rng.randi_range(0,SLOTS.size()-1)])
	return request

func _swap(value: Variant) -> String:
	return "B" if str(value) == "A" else ("A" if str(value) == "B" else str(value))

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
