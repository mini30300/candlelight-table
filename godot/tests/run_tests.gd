extends SceneTree
## Test runner with no addons. Discovers res://tests/test_*.gd, runs every `test_*` method and quits
## with exit code 1 on any failure.
##   <godot> --headless --path godot -s tests/run_tests.gd
##   <godot> --headless --path godot -s tests/run_tests.gd -- test_i18n     (only scripts whose name contains the word)

const TESTS_DIR := "res://tests"


func _initialize() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var scripts := _discover(filter)
	if scripts.is_empty():
		print("FAIL  no test scripts found in " + TESTS_DIR)
		quit(1)
		return
	var passed := 0
	var failed := 0
	var started := Time.get_ticks_msec()
	for path in scripts:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FAIL  cannot load " + path)
			failed += 1
			continue
		var t: Object = script.new()
		if not t.has_method("assert_true"):
			print("FAIL  " + path + " does not extend res://tests/testing.gd")
			failed += 1
			continue
		print("--- " + path.get_file())
		t.call("setup")
		for m in t.get_method_list():
			var name: String = m["name"]
			if name.begins_with("test_") and m["args"].size() == 0:
				t.call(name)
		passed += t.get("passed")
		failed += t.get("failed")
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	print("%s  %d passed, %d failed in %d scripts (%.1fs)" % ["PASS " if failed == 0 else "FAIL ", passed, failed, scripts.size(), secs])
	quit(1 if failed > 0 else 0)


func _discover(filter: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and (filter == "" or f.contains(filter)):
			out.append(TESTS_DIR + "/" + f)
	out.sort()
	return out
