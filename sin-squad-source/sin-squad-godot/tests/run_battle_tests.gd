extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script: Script = load("res://tests/battle_test.gd")
	if script == null or not script.can_instantiate():
		printerr("BATTLE_TESTS_FAILED suite_load")
		quit(1)
		return
	var report: Dictionary = script.new().run_all()
	for line: String in report.lines: print(line)
	if int(report.failed) > 0:
		printerr("BATTLE_TESTS_FAILED count=%d passed=%d" % [report.failed, report.passed])
		quit(1)
	else:
		print("BATTLE_TESTS_PASSED count=%d" % report.passed)
		quit(0)
