extends SceneTree
## Difficulty screen under xvfb (CAMPAIGN_SPEC §1.4, §4, track B): the four cards in Thai and English on the desktop
## (1280×720) and the phone layout (1600×720, touch on) on every graphics level. Checks: four cards on screen, each with
## its name, score badge, blurb, what-changes line and revives line inside the card (the name and badge not clipped), the
## เลือก button on the selected card only (on screen, ≥ 44 px, ≥ 64 px with touch); one live hero at most (the selected card) and stills on the other cards; on min four
## stills, no live viewport and nothing under the screen processing after the stills; whole-frame draw calls and
## primitives within §4 (hi 90 / 120k, mid 70 / 90k, lo 45 / 50k, min 30 / 30k); English mode shows no Thai.
## PNGs (TEST_OUT, default tests/out): difficulty_<lang>_<w>x<h>_<level>.png. Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s tests/render/test_difficulty_screen.gd

const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_difficulty_screen.cfg"
const DS_PATH := "res://ui/screens/difficulty_screen.tscn"
const IDS: PackedStringArray = ["normal", "hard", "veryhard", "catastrophe"]
const BUDGET := {"hi": [90, 120000], "mid": [70, 90000], "lo": [45, 50000], "min": [30, 30000]}
## [ขนาด, ภาษา, ระดับ, สัมผัส, ใบที่เลือก]
const CASES: Array = [[Vector2i(1280, 720), "th", "hi", false, "hard"], [Vector2i(1280, 720), "en", "mid", false, "veryhard"],
	[Vector2i(1600, 720), "th", "lo", true, "catastrophe"], [Vector2i(1600, 720), "en", "hi", true, "normal"],
	[Vector2i(1280, 720), "th", "min", false, "catastrophe"], [Vector2i(1600, 720), "en", "min", true, "hard"]]

var _out_dir := DEFAULT_OUT_DIR
var _headless := false
var _passed := 0
var _failed := 0
var _done := false
var _started := false
var _thai_re := RegEx.create_from_string("[฀-๿]")
var HEROES: Script


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	_headless = DisplayServer.get_name() == "headless"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("load_settings")
	HEROES = load("res://scenes/campaign/hero_loader.gd")
	HEROES.set("test_dirs", PackedStringArray(["res://tests/fixtures/none"]))


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var size0 := root.size
	for c: Array in CASES:
		await _case(c[0], c[1], c[2], c[3], c[4])
	root.size = size0
	_finish()


func _case(sz: Vector2i, lang: String, lv: String, touch: bool, sel: String) -> void:
	var app := _app()
	app.call("set_lang", lang)
	app.call("set_gfx", lv)
	app.call("set_touch", "on" if touch else "off")
	root.size = sz
	await _frames(2)
	var tag := "%s %dx%d %s" % [lang, sz.x, sz.y, lv]
	var ds: Node = app.call("push", load(DS_PATH))
	ds.call("open", {"last": sel, "from": "deck"})
	var ok := await _wait_stills(ds, lv)
	_check(ok, tag + ": the stills are made", _info(ds))
	var stages: Array = ds.call("stages")
	var live := stages.filter(func(s: Node) -> bool: return bool(s.counts()["live"]))
	if lv == "min":
		_check(live.is_empty(), tag + ": no live hero on min")
		_check(stages.all(func(s: Node) -> bool: return bool(s.counts()["still"]) and s.viewport() == null),
			tag + ": four stills, no viewport left", _info(ds))
	else:
		_check(live.size() == 1 and live[0] == stages[IDS.find(sel)], tag + ": one live hero, the selected card", _info(ds))
		for i in 4:
			if i != IDS.find(sel):
				_check(bool(stages[i].counts()["still"]) and stages[i].viewport() == null, "%s: %s is a still" % [tag, IDS[i]])
	await _frames(10)
	if lv == "min":
		var busy := _idle_problems(ds)
		_check(busy.is_empty(), tag + ": nothing under the screen processes after the stills", ", ".join(busy))
	var m := await _measure()
	var b: Array = BUDGET[lv]
	print("info  %s: frame %d draws, %d primitives" % [tag, m[0], m[1]])
	_check(_headless or (m[0] <= int(b[0]) and m[1] <= int(b[1])), "%s: within %d draws / %d primitives" % [tag, b[0], b[1]], str(m))
	var vr: Rect2 = ds.get_viewport_rect()
	for id in IDS:
		var c: Dictionary = ds.call("card", id)
		var panel: Control = c["panel"]
		_check(panel.is_visible_in_tree() and vr.encloses(panel.get_global_rect().grow(-1.0)), "%s: the %s card is on screen" % [tag, id])
		var btn: Button = c["button"]
		if id == sel:
			_check(btn.is_visible_in_tree() and vr.encloses(btn.get_global_rect().grow(-1.0)) and btn.size.y >= (63.0 if touch else 44.0),
				"%s: the selected card's เลือก button is on screen and big enough" % tag, str(btn.get_global_rect()))
		else:
			_check(not btn.is_visible_in_tree(), "%s: %s (not selected) shows no button" % [tag, id])
		for key in ["name", "mult"]:
			var l: Label = c[key]
			var w := l.get_theme_font(&"font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size(&"font_size")).x
			_check(w <= l.size.x + 1.0, "%s: %s %s is not clipped" % [tag, id, key], "%s: %.0f > %.0f" % [l.text, w, l.size.x])
		for key in ["blurb", "stats", "revives"]:
			var l2: Label = c[key]
			_check(l2.text != "" and panel.get_global_rect().grow(1.0).encloses(l2.get_global_rect()), "%s: %s %s fits the card" % [tag, id, key])
	if lang == "en":
		var thai := _thai_in(ds)
		_check(thai.is_empty(), tag + ": English mode shows no Thai", ", ".join(thai))
	if not _headless:
		_save("difficulty_%s_%dx%d_%s.png" % [lang, sz.x, sz.y, lv])
	app.call("pop")
	await _frames(3)


func _wait_stills(ds: Node, lv: String) -> bool:
	for _i in 240:
		await process_frame
		var stages: Array = ds.call("stages")
		var sel := IDS.find(String(ds.call("selected")))
		var done := true
		for i in 4:
			var s: Node = stages[i]
			if s.busy() or (i != sel or lv == "min") and not bool(s.counts()["still"]) and not _headless:
				done = false
		if done:
			return true
	return false


func _info(ds: Node) -> String:
	return str((ds.call("stages") as Array).map(func(s: Node) -> Dictionary: return s.counts()))


func _measure() -> Array:
	for _i in 3:
		await process_frame
	var d := 0
	var p := 0
	for _i in 4:
		await process_frame
		d = maxi(d, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		p = maxi(p, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	return [d, p]


func _idle_problems(n0: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [n0]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.can_process() and (n.is_processing() or n.is_physics_processing()):
			out.append(String(n.name) + " processes")
		if n is AnimationPlayer and (n as AnimationPlayer).is_playing() and n.can_process() \
				and (n as AnimationPlayer).callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL:
			out.append(String(n.name) + " plays")
		if n is Timer and not (n as Timer).is_stopped():
			out.append(String(n.name) + " ticks")
		if n is SubViewport and (n as SubViewport).render_target_update_mode != SubViewport.UPDATE_DISABLED:
			out.append(String(n.name) + " renders")
		stack.append_array(n.get_children())
	return out


func _thai_in(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return out
	if node is Label or node is Button:
		var t := str(node.get("text"))
		if _thai_re.search(t) != null:
			out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		out.append_array(_thai_in(c))
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var err := img.save_png(_out_dir + "/" + name)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(_out_dir + "/" + name))


func _finish() -> void:
	HEROES.set("test_dirs", PackedStringArray())
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 else 1)


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))
