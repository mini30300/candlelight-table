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
		return false
	_ran = true
	_run()                 # a coroutine: test methods and the physics check await frames, then it quits
	return false


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
				await t.call(name)
		passed += int(t.get("passed"))
		failed += int(t.get("failed"))
		# บรรทัด FAIL ลงรายงานด้วย (บันทึก CI ตัดหัวทิ้ง เหลือแต่รายงาน)
		var fl: Variant = t.get("fail_lines")
		if fl is PackedStringArray:
			_lines.append_array(fl)
	var phys: Array = await _physics_check()
	passed += int(phys[0])
	failed += int(phys[1])
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	if scripts.is_empty():
		_say("FAIL  no test scripts found under " + TESTS_DIR + " (are tests/**/*.gd in the export?)")
	var ok := failed == 0 and not scripts.is_empty()
	_say("%s  %d passed, %d failed in %d scripts (%.1fs)" % ["PASS " if ok else "FAIL ", passed, failed, scripts.size(), secs])
	_write_report()
	quit(0 if ok else 1)


## Jolt is the 3D engine (the project setting, the module present, and a ray on a one-triangle concave shape giving
## face index -1, Jolt's default where Godot Physics gives 0), and a soldier ragdoll on hi runs 60 physics frames
## without NaN (ใหม่ 0.14 item 3). Returns [passed, failed]; the lines go to the report.
func _physics_check() -> Array:
	var res := [0, 0]
	var tri := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cp := ConcavePolygonShape3D.new()
	cp.set_faces(PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(0, 0, 1)]))
	cs.shape = cp
	tri.add_child(cs)
	tri.position = Vector3(0.0, -50.0, 0.0)
	root.add_child(tri)
	await physics_frame
	await physics_frame
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, -49, 0), Vector3(0, -51, 0))
	var hit: Dictionary = root.get_world_3d().direct_space_state.intersect_ray(q)
	tri.queue_free()
	var setting := str(ProjectSettings.get_setting("physics/3d/physics_engine", ""))
	var jolt := setting == "Jolt Physics" and ClassDB.class_exists("JoltPhysicsServer3D") and not hit.is_empty() \
		and int(hit.get("face_index", 0)) == -1
	_tally(res, jolt, "Jolt Physics is the active 3D engine (setting '%s', ray face index %s)" % [setting, str(hit.get("face_index", "none"))])
	if not ResourceLoader.exists("res://assets/figures/soldier/rig.tscn"):
		_say("info  no soldier rig in this build: the ragdoll frames are skipped")
		return res
	var fig: Node3D = (load("res://scenes/arena/soldier_figure.gd") as GDScript).new()
	fig.position = Vector3(0.0, -40.0, 0.0)
	root.add_child(fig)
	fig.call("setup", {"role": &"player", "level": "hi", "seed": 7})
	fig.call("set_hit_push", Vector3(0.0, 0.0, -2.4))
	fig.call("play", &"die", 1.0)
	var fell := 0
	var finite := true
	for i in 60:
		await physics_frame
		var rag: Variant = fig.call("ragdoll")
		if rag == null:
			continue
		if bool(rag.call("is_falling")):
			fell += 1
		for pb: PhysicalBone3D in rag.call("bodies"):
			finite = finite and pb.global_transform.is_finite()
	await process_frame
	var sk: Skeleton3D = fig.call("skeleton")
	for b in sk.get_bone_count():
		finite = finite and sk.get_bone_global_pose(b).is_finite()
	fig.queue_free()
	_tally(res, fell >= 40 and finite, "a soldier ragdoll (hi) falls through 60 physics frames without NaN (%d frames falling)" % fell)
	return res


func _tally(res: Array, ok: bool, what: String) -> void:
	_say(("ok    " if ok else "FAIL  ") + what)
	res[0 if ok else 1] += 1


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
