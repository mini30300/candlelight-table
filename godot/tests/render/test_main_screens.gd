extends SceneTree
## Opens scenes/main.tscn. Since LOBBY_SPEC (12 Nov) the first screen is the main menu and the demo table is built
## lazily (hidden, processing off) — before, the GPU check was the first screen and the table built at startup; these
## expectations changed on purpose. The menu must pass the Thai / English scan; then Settings → GPU check builds and
## shows the demo table (the figure style pinned to kit, as before) and every earlier check runs there: saves
## tests/out/main_th.png, switches the screen to English and saves main_en.png. Asserts: 400 figures with 400 team rings,
## the images are not black, the Thai screen shows Thai, and no Label/Button/OptionButton item/LineEdit placeholder
## shows Thai in English mode (the language button's "ไทย" label is the one deliberate exception, as on the old page).
## Leaving the GPU check hides the table and disables it again. Run like tests/render_probe.gd:
##   timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_main_screens.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/main.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const FRAMES := 4
const SETTINGS_FILE := "user://test_main_screens.cfg"

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _fig_was := "egg"
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
		app.set("settings_file", SETTINGS_FILE)   # the language switch below saves: into the test file
		_fig_was = str(app.get("fig"))
		app.call("set_fig", "kit")   # the demo table below is the kit look (LOBBY_SPEC §7.2), restored at the end
		app.call("set_lang", "th")
	root.add_child(_main)
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(FRAMES)
	var menu: Node = _screen()
	_check(menu != null and menu.has_method("handle_back") and menu.get_node_or_null("%PlayButton") != null,
		"main.tscn opens the main menu first (the GPU check moved to Settings)")
	if menu == null or menu.get_node_or_null("%PlayButton") == null:
		_end(false)
		return
	var table0 := _main.get_node_or_null(^"World/BattleTable") as Node3D
	_check(table0 != null and not bool(table0.get("built")) and int(table0.call("counts")["figures"]) == 0,
		"the demo table is not built at startup (built lazily)")
	_check(table0 != null and not table0.visible and table0.process_mode == Node.PROCESS_MODE_DISABLED,
		"the demo table is hidden and its processing disabled under the menu")
	_check(_thai_re.search(str(menu.get_node("%Title").get("text"))) != null, "menu, Thai mode: the title is Thai")
	_check(_thai_in(menu, []).size() > 0, "menu, Thai mode: Thai text on screen")
	_check(str(menu.get_node("%LangButton").get("text")) == "ENGLISH", "menu, Thai mode: the language button says ENGLISH")
	menu.call("set_language", true, false)
	_check(str(menu.get_node("%Title").get("text")) == "Candlelight Table", "menu, English mode: the title is translated")
	var menu_left := _thai_in(menu, ["LangButton"])
	_check(menu_left.is_empty(), "menu, English mode: no Thai left on screen", str(menu_left))
	menu.call("set_language", false, false)
	menu.get_node("%SettingsButton").pressed.emit()
	await _frames(2)
	var settings: Node = _screen()
	_check(settings != null and settings.get_node_or_null("%GpuCheckButton") != null, "the menu's settings button opens Settings")
	if settings == null or settings.get_node_or_null("%GpuCheckButton") == null:
		_end(false)
		return
	settings.get_node("%GpuCheckButton").pressed.emit()
	await _frames(FRAMES)
	var screen: Node = _screen()
	if screen == null or not screen.has_signal("army_requested"):
		print("FAIL  Settings → GPU check did not open the GPU-check screen")
		_end(false)
		return
	var table := _main.get_node_or_null(^"World/BattleTable")
	_check(table != null, "main.tscn holds the battle table under World")
	if table != null:
		_check((table as Node3D).visible and table.process_mode == Node.PROCESS_MODE_INHERIT,
			"the GPU check shows the table and turns its processing on")
		_check(bool(table.get("camera_rig").get("camera").get("current")), "the GPU check makes the table camera current")
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
		_end(false)
		return
	screen.call("set_language", true)
	await _frames(FRAMES)
	_check(str(screen.get_node("%Title").get("text")) == "GPU check", "English mode: the title is translated")
	var left := _thai_in(screen, ["LangButton"])
	_check(left.is_empty(), "English mode: no Thai left on screen", str(left))
	var ok := _save("main_en.png")
	_check_table_api(_main.get_node_or_null(^"World/BattleTable"))
	screen.get_node("%BackButton").pressed.emit()
	await _frames(2)
	var t := _main.get_node_or_null(^"World/BattleTable") as Node3D
	_check(_screen() == settings, "the GPU check's back button returns to Settings")
	_check(t != null and not t.visible and t.process_mode == Node.PROCESS_MODE_DISABLED, "leaving the GPU check hides the table and disables it again")
	_end(ok)


func _end(ok: bool) -> void:
	var app := root.get_node_or_null(^"App")
	if app != null:
		app.call("set_lang", "th")
		app.call("set_fig", _fig_was)
		app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 and ok else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if ok and _failed == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


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
