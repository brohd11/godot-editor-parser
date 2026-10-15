extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures := 0
	for name in ["options", "registry", "scanner", "metadata", "editor_service", "warmup"]:
		if name in ["editor_service", "warmup"] and "--core" in OS.get_cmdline_user_args():
			continue
		var suite = load("res://addons/_lib/editor_parser/_export_ignore/test/%s_test.gd" % name)
		if suite == null or not suite.can_instantiate() or not suite.has_method("run_tests"):
			failures += 1
			continue
		var result:Dictionary = suite.run_tests()
		failures += result.get("result", 1)
		print("\n".join(result.get("output", ["FAIL suite did not return a report: " + name])))
	quit(0 if failures == 0 else 1)
