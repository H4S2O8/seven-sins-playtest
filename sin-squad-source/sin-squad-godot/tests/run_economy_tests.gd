extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite_script: Script = load("res://tests/economy_test.gd")
	if suite_script == null:
		printerr("ECONOMY_TESTS_FAILED could_not_load_suite")
		quit(1)
		return
	if not suite_script.can_instantiate():
		printerr("ECONOMY_TESTS_FAILED suite_parse_error")
		quit(1)
		return
	var suite = suite_script.new()
	var report: Dictionary = suite.run_all()
	for line: String in report.lines:
		print(line)
	if int(report.failed) > 0:
		printerr("ECONOMY_TESTS_FAILED count=%d" % report.failed)
		quit(1)
	else:
		print("ECONOMY_TESTS_PASSED count=%d" % report.passed)
		quit(0)
