extends SceneTree
## Opens scenes/main.tscn (the look build: table + the GPU-check screen), saves tests/out/main_th.png, switches the
## screen to English and saves main_en.png. Asserts: 400 figures with 400 team rings, the images are not black, the
## Thai screen shows Thai, and no Label/Button/OptionButton item/LineEdit placeholder shows Thai in English mode (the
## language button's "ไทย" label is the one deliberate exception, as on the old page). Run like tests/render_probe.gd:
##   timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_main_screens.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/main.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const FRAMES := 4

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _frame := 0
var _english_done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("FAIL  cannot load " + SCENE)
		quit(1)
		return
	_main = scene.instantiate()
	_main.set("first_run_guess", false)   # never write this machine's settings.cfg from a test
	var app := root.get_node_or_null(^"App")
	if app != null:
		app.call("set_lang", "th")
	root.add_child(_main)
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame <= FRAMES:
		return false
	var screen: Node = _screen()
	if screen == null:
		print("FAIL  no GPU-check screen on the stack")
		quit(1)
		return true
	if not _english_done:
		var table := _main.get_node_or_null(^"World/BattleTable")
		_check(table != null, "main.tscn holds the battle table under World")
		if table != null:
			var c: Dictionary = table.call("counts")
			print("scene: " + str(c))
			_check(int(c["figures"]) == 400, "400 figures (%d)" % int(c["figures"]))
			_check(int(c["rings"]) == 400, "400 team rings (%d)" % int(c["rings"]))
			# the props come from the rules field of the default setup (core/field), every one of them drawn
			_check(int(c["props"]) == int(c["field_props"]) and int(c["props"]) > 0,
				"every prop of the rules field is drawn (%d of %d)" % [int(c["props"]), int(c["field_props"])])
		_check(_thai_re.search(str(screen.get_node("%Title").get("text"))) != null, "Thai mode: the title is Thai")
		_check(_thai_in(screen, []).size() > 0, "Thai mode: Thai text on screen")
		var en_names := str(screen.get_node("%LangButton").get("text"))
		_check(en_names == "ENGLISH", "Thai mode: the language button says ENGLISH")
		if not _save("main_th.png"):
			return true
		screen.call("set_language", true)
		_english_done = true
		_frame = 0
		return false
	_check(str(screen.get_node("%Title").get("text")) == "GPU check", "English mode: the title is translated")
	var left := _thai_in(screen, ["LangButton"])
	_check(left.is_empty(), "English mode: no Thai left on screen", str(left))
	var ok := _save("main_en.png")
	_check_table_api(_main.get_node_or_null(^"World/BattleTable"))
	var app := root.get_node_or_null(^"App")
	if app != null:
		app.call("set_lang", "th")
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	quit(0 if ok and _failed == 0 else 1)
	return true


## The table's non-visual API the GPU-check screen and later tracks rely on: the stress toggle, the selection
## ring, and the camera rig's clamps and tap-vs-drag rule.
func _check_table_api(table: Node) -> void:
	if table == null:
		return
	var rings: Node = table.get("rings")
	var figures: Node = table.get("figures")
	var outside := 0
	var teams := {}
	for f in figures.get("figures"):
		var p: Vector3 = f.get("pos")
		if absf(p.x) > 24.0 or absf(p.z) > 17.0:
			outside += 1
		teams[int(f.get("team"))] = true
	_check(outside == 0, "every figure stands inside the rails (%d outside)" % outside)
	_check(teams.size() == 8, "figures belong to 8 teams (%d)" % teams.size())
	table.call("select_figure", 0)
	_check(int(rings.call("count")) == 401, "select_figure adds one selection ring (%d rings)" % int(rings.call("count")))
	table.call("select_figure", 3)
	_check(int(rings.call("count")) == 401, "selecting another figure moves the ring, it does not add one")
	table.call("select_figure", -1)
	_check(int(rings.call("count")) == 400, "clearing the selection removes the ring")
	table.call("set_stress", true)
	var c: Dictionary = table.call("counts")
	_check(int(c["figures"]) == 900, "stress on: 400 + 400 rigid + 100 skinned figures (%d)" % int(c["figures"]))
	_check(int(c["skinned"]) >= 100, "stress on: the 100 stress figures are skinned beyond the level cap (%d skinned)" % int(c["skinned"]))
	table.call("set_stress", false)
	c = table.call("counts")
	_check(int(c["figures"]) == 400 and int(figures.call("stress_on")) == 0, "stress off: back to 400 figures")
	var rig: Node = table.get("camera_rig")
	rig.call("fit_table", 48.0, 34.0)
	var d0: float = rig.get("distance")
	_check(d0 > 30.0 and d0 < 80.0, "fit_table puts the camera at a sensible distance (%.1f m)" % d0)
	rig.call("_orbit", Vector2(0.0, -10000.0))   # drag up: the camera comes down towards the horizon
	_check(absf(float(rig.get("pitch")) + 0.3491) < 0.001, "pitch is clamped at 20 degrees above the table")
	rig.call("_orbit", Vector2(0.0, 10000.0))    # drag down: the camera climbs
	_check(absf(float(rig.get("pitch")) + 1.3963) < 0.001, "pitch is clamped at 80 degrees down")
	rig.call("_pan", Vector2(100000.0, 0.0))
	var t: Vector3 = rig.get("target")
	_check(absf(t.x) <= 24.0 + 0.001 and absf(t.z) <= 17.0 + 0.001, "pan keeps the target on the table " + str(t))
	rig.call("_zoom", 0.0001)
	_check(float(rig.get("distance")) == float(rig.get("min_distance")), "zoom in stops at min_distance")
	rig.call("_zoom", 100000.0)
	_check(float(rig.get("distance")) == float(rig.get("max_distance")), "zoom out stops at max_distance")
	var taps: Array[Vector2] = []
	rig.connect("tapped", func(p: Vector2) -> void: taps.append(p))
	rig.call("_begin_press", Vector2(100.0, 100.0))
	rig.call("_end_press", Vector2(104.0, 103.0))
	_check(taps.size() == 1, "a short press that barely moves is a tap")
	rig.call("_begin_press", Vector2(100.0, 100.0))
	rig.set("_press_moved", 60.0)
	rig.call("_end_press", Vector2(160.0, 100.0))
	_check(taps.size() == 1, "a drag is not a tap")
	rig.call("fit_table", 48.0, 34.0)


func _screen() -> Node:
	var app := root.get_node_or_null(^"App")
	if app == null:
		return null
	return app.call("current")


## Every visible text of the screen that still contains Thai: "NodeName: text"
func _thai_in(node: Node, exempt: Array) -> PackedStringArray:
	var out := PackedStringArray()
	_scan(node, exempt, out)
	return out


func _scan(node: Node, exempt: Array, out: PackedStringArray) -> void:
	if not exempt.has(String(node.name)):
		var texts := PackedStringArray()
		if node is Label or node is Button:
			texts.append(str(node.get("text")))
		if node is OptionButton:
			for i in (node as OptionButton).item_count:
				texts.append((node as OptionButton).get_item_text(i))
		if node is LineEdit:
			texts.append((node as LineEdit).placeholder_text)
		for t in texts:
			if _thai_re.search(t) != null:
				out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		_scan(c, exempt, out)


func _save(name: String) -> bool:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	if err != OK:
		print("FAIL  could not save " + path + ": " + error_string(err))
		quit(1)
		return false
	print("ok    saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))
	_check(_mean_luma(img) > 0.04, name + " is not black")
	return true


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))


static func _mean_luma(img: Image) -> float:
	var sum := 0.0
	var n := 0
	var size := img.get_size()
	var x := 7
	while x < size.x:
		var y := 5
		while y < size.y:
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
			y += 29
		x += 31
	return sum / maxi(n, 1)
