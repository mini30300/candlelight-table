extends SceneTree
## Test runner with no addons. Discovers res://tests/unit/**/test_*.gd (recursively) and
## res://tests/golden/test_golden.gd (when present), runs every `test_*` method and quits with
## exit code 1 on any failure.
##   <godot> --headless --path godot -s tests/run_tests.gd
##   <godot> --headless --path godot -s tests/run_tests.gd -- i18n     (only scripts whose path contains the word)
## The tests run on the first frame, after every autoload's _ready(), so App / I18n / Log / Clock are live.
## Autoloads are instantiated by the engine in -s mode too (verified in 4.7.1); should one be missing,
## _ensure_autoloads() instantiates it from project.godot itself.

const TESTS_DIR := "res://tests"
const UNIT_DIR := "res://tests/unit"
const GOLDEN := "res://tests/golden/test_golden.gd"

var _filter := ""
var _ran := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_filter = args[0]
	_ensure_autoloads()


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	quit(_run())
	return true


func _run() -> int:
	var scripts := discover(_filter)
	if scripts.is_empty():
		print("FAIL  no test scripts found under %s/unit (filter '%s')" % [TESTS_DIR, _filter])
		return 1
	print("--- %d test scripts%s" % [scripts.size(), "" if _filter == "" else " matching '" + _filter + "'"])
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
		print("--- " + path.trim_prefix(TESTS_DIR + "/"))
		t.call("setup")
		for m in t.get_method_list():
			var name: String = m["name"]
			if name.begins_with("test_") and m["args"].size() == 0:
				t.call(name)
		passed += t.get("passed")
		failed += t.get("failed")
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	print("%s  %d passed, %d failed in %d scripts (%.1fs)" % ["PASS " if failed == 0 else "FAIL ", passed, failed, scripts.size(), secs])
	return 1 if failed > 0 else 0


## Every tests/unit/**/test_*.gd (sorted by path) plus tests/golden/test_golden.gd; the filter matches the
## path relative to res://tests ("unit/core/test_fx.gd"), so both a file name and a folder work.
static func discover(filter: String) -> PackedStringArray:
	var out := PackedStringArray()
	_walk(UNIT_DIR, out)
	out.sort()
	if FileAccess.file_exists(GOLDEN) or ResourceLoader.exists(GOLDEN):
		out.append(GOLDEN)
	if filter == "":
		return out
	var kept := PackedStringArray()
	for path in out:
		if path.trim_prefix(TESTS_DIR + "/").contains(filter):
			kept.append(path)
	return kept


static func _walk(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")   # exported builds may list x.gd.remap
		if name.ends_with(".gdc"):            # or binary-tokenised scripts
			name = name.trim_suffix(".gdc") + ".gd"
		if name.begins_with("test_") and name.ends_with(".gd"):
			var path := dir_path + "/" + name
			if not out.has(path):
				out.append(path)
	for d in dir.get_directories():
		_walk(dir_path + "/" + d, out)


## Instantiate any autoload from project.godot that the engine did not add to the root (safety net).
func _ensure_autoloads() -> void:
	for p in ProjectSettings.get_property_list():
		var key: String = p["name"]
		if not key.begins_with("autoload/"):
			continue
		var name := key.trim_prefix("autoload/")
		if root.has_node(name):
			continue
		var path := str(ProjectSettings.get_setting(key)).trim_prefix("*")
		var res: Resource = load(path)
		var node: Node = null
		if res is PackedScene:
			node = (res as PackedScene).instantiate()
		elif res is GDScript:
			node = (res as GDScript).new()
		if node == null:
			print("FAIL  cannot instantiate autoload " + name + " from " + path)
			continue
		node.name = name
		root.add_child(node)
		print("--- runner added missing autoload " + name)
