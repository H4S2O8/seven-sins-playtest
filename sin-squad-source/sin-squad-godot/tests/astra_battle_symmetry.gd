extends SceneTree

# Independent side-swap property test using actual combat, not precomputed adjudication.
const Battle = preload("res://core/battle/battle_engine.gd")
var checks := 0
var completed_pairs := 0
var failures: Array[String] = []

func _init() -> void:
	for rule_number in range(1, 31):
		for variant in range(2):
			var config := _config(rule_number, variant)
			var mirror := config.duplicate(true)
			mirror.teams.A = config.teams.B.duplicate(true)
			mirror.teams.B = config.teams.A.duplicate(true)
			var normal: Dictionary = Battle.new().simulate(config)
			var reflected: Dictionary = Battle.new().simulate(mirror)
			var label := "%s variant%d" % [config.rule_id, variant]
			_check(str(normal.get("error", "")).is_empty(), label + " original error " + str(normal.get("error", "")))
			_check(str(reflected.get("error", "")).is_empty(), label + " mirrored error " + str(reflected.get("error", "")))
			if not normal.get("error", "").is_empty() or not reflected.get("error", "").is_empty(): continue
			_check(normal.terminal and reflected.terminal, label + " both actually terminate")
			_check(normal.snapshot.tick == reflected.snapshot.tick, label + " end tick differs")
			_check(_swap_winner(normal.winner) == str(reflected.winner), label + " winner differs " + str(normal.winner) + "/" + str(reflected.winner))
			for side in ["A", "B"]:
				var other := "B" if side == "A" else "A"
				for slot in range(3):
					var a: Dictionary = normal.snapshot.teams[side][slot]
					var b: Dictionary = reflected.snapshot.teams[other][slot]
					for field in ["hp_tenths", "dead", "final_departed", "first_natural_attack_tick"]:
						_check(a.get(field) == b.get(field), "%s %s%d %s differs %s/%s" % [label, side, slot+1, field, str(a.get(field)), str(b.get(field))])
			completed_pairs += 1
	_check(completed_pairs == 60, "all sixty actual mirror pairs complete")
	for failure in failures: print("FAIL: ", failure)
	print("ASTRA_BATTLE_SYMMETRY checks=%d pairs=%d failures=%d" % [checks, completed_pairs, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _config(rule_number: int, variant: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 230937 + rule_number * 17 + variant
	var config := {"test_fixture":true,"seed":rng.seed,"rule_id":"VC%02d" % rule_number,"teams":{"A":[],"B":[]}}
	for side in ["A", "B"]:
		for slot in range(1, 4):
			config.teams[side].append({"definition_id":"FIXTURE_%s%d" % [side,slot],"fixture":true,
				"slot":slot,"H":rng.randi_range(40,150),"A":rng.randi_range(4,20),
				"T_ticks":20 if variant == 0 else rng.randi_range(6,32),"R":rng.randi_range(0,8),
				"reach":"ranged" if variant == 0 else ("ranged" if rng.randi_range(0,1)==0 else "melee"),
				"armor_kind":"medium","target_slot":rng.randi_range(1,3)})
	return config

func _swap_winner(value: Variant) -> String:
	if str(value) == "A": return "B"
	if str(value) == "B": return "A"
	return str(value)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
