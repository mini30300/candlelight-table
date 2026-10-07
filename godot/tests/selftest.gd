extends SceneTree
class_name SelfTest
## Self-test of a build, for the Windows smoke job in CI and for anyone holding the exported game: prints the engine
## version, the platform and the renderer, runs the unit tests exactly as tests/run_tests.gd discovers them,
## writes the same lines to a report file and quits with exit code 0 (all passed) or 1. Two ways to start it:
##   <godot> --headless --path godot -s tests/selftest.gd -- --out /tmp/selftest.txt      (the editor binary)
##   an exported game: the official 4.7 templates are built without path overrides and ignore -s, so put an
##   override.cfg next to the executable holding
##       [application]
##       run/main_loop_type="SelfTest"
##   and run  CandlelightTable.exe --headless --audio-driver Dummy -- --out D:\path\selftest.txt
##   (SelfTest is the class name below; the main scene still loads first, so autoloads are present).
## Scripts ship as text (export_presets.cfg: script_export_mode=0), so tests that read sources pass in the export
## too; the discovery below also accepts the .gdc / .gd.remap names of a binary-token export.
## The report (default user://selftest.txt) is what CI reads on Windows, where a release build has no console.

const TESTS_DIR := "res://tests"
## The same discovery as tests/run_tests.gd (tests/unit/** and tests/golden); the render and net suites need a
## display or a mock server and are not unit tests.
const RunTests := preload("res://tests/run_tests.gd")

var _lines := PackedStringArray()
var _out_path := "user://selftest.txt"
var _ran := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]


## The tests run on the first frame, after every autoload's _ready() (in _initialize() the autoloads exist but
## are not in the tree yet, and tests/unit/test_app.gd and friends check for that).
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	_say("engine: " + str(Engine.get_version_info().get("string", "?")))
	_say("platform: " + OS.get_name() + " " + OS.get_version() + " " + Engine.get_architecture_name() + (" (exported build)" if not OS.has_feature("editor") else " (editor binary)"))
	_say("renderer: " + _renderer())
	_say("app: " + str(ProjectSettings.get_setting("application/config/name", "?")) + " " + _app_version())
	var scripts: PackedStringArray = RunTests.discover("")
	_say("tests: %d scripts under %s/unit" % [scripts.size(), TESTS_DIR])
	var passed := 0
	var failed := 0
	var started := Time.get_ticks_msec()
	for path: String in scripts:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			_say("FAIL  cannot load " + path)
			failed += 1
			continue
		var t: Object = script.new()
		if not t.has_method("assert_true"):
			_say("FAIL  " + path + " does not extend res://tests/testing.gd")
			failed += 1
			continue
		_say("--- " + path.get_file())
		t.call("setup")
		for m: Dictionary in t.get_method_list():
			var name: String = m["name"]
			if name.begins_with("test_") and m["args"].size() == 0:
				t.call(name)
		passed += int(t.get("passed"))
		failed += int(t.get("failed"))
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	if scripts.is_empty():
		_say("FAIL  no test scripts found under " + TESTS_DIR + " (are tests/**/*.gd in the export?)")
	var ok := failed == 0 and not scripts.is_empty()
	_say("%s  %d passed, %d failed in %d scripts (%.1fs)" % ["PASS " if ok else "FAIL ", passed, failed, scripts.size(), secs])
	_write_report()
	quit(0 if ok else 1)


func _renderer() -> String:
	var method := RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name()
	var adapter := RenderingServer.get_video_adapter_name()
	if adapter.is_empty():
		return method + " / " + driver + " (headless: no video adapter)"
	return method + " / " + driver + " / " + adapter + " " + RenderingServer.get_video_adapter_api_version()


## APP_VER and RULES_V from core/version.gd once R0-B lands; tolerant until then.
func _app_version() -> String:
	if not ResourceLoader.exists("res://core/version.gd"):
		return "(no core/version.gd yet)"
	var script: GDScript = load("res://core/version.gd")
	if script == null:
		return "(core/version.gd does not load)"
	var consts: Dictionary = script.get_script_constant_map()
	return "v" + str(consts.get("APP_VER", "?")) + " rules " + str(consts.get("RULES_V", "?"))


func _say(line: String) -> void:
	print(line)
	_lines.append(line)


func _write_report() -> void:
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f == null:
		print("WARN  cannot write the report " + _out_path + ": " + error_string(FileAccess.get_open_error()))
		return
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("report: " + ProjectSettings.globalize_path(_out_path))
