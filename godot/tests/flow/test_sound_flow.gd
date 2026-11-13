extends SceneTree
## Sound through the real flow, headless (Dummy driver: Sfx and Music keep their bookkeeping without players).
## Main menu → music mood "menu"; a menu button clicks (ui, one tree-level hook) → Settings: the sound rows (effects
## volume, music volume, mute) change App, the settings file and the buses at once; English mode labels them in English
## → ‹ กลับ → เล่นกับบอท → the deck: mood "deck", footsteps while walking, a ping in range of a station. Every change goes
## to the test settings file (never this machine's settings.cfg). Run:
##   timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_sound_flow.gd
## Exit code 1 on any failure; the last line is PASS or FAIL.

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_sound_flow.cfg"
const WALK_MS := 2500

var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("reset_settings")
	app.call("set_gfx", "min")
	var scene: PackedScene = load(SCENE)
	_main = scene.instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(3)
	var app := _app()
	var sfx := root.get_node(^"Sfx")
	var music := root.get_node(^"Music")
	_check(bool(sfx.get("quiet")) and bool(music.get("quiet")), "the Dummy driver keeps Sfx and Music quiet")
	_check(int((sfx.get("kinds") as Dictionary).size()) >= 42, "Sfx read the baked manifest (%d kinds)" % (sfx.get("kinds") as Dictionary).size())
	var menu: Node = app.call("current")
	if menu == null or menu.get_node_or_null("%SettingsButton") == null:
		_check(false, "main.tscn opens the main menu")
		_finish()
		return
	_check(music.get("mood") == &"menu", "the main menu plays the menu music (%s)" % str(music.get("mood")))

	# 1. a button anywhere clicks; Settings has the sound rows
	var clicks := _asked(sfx, "ui")
	(menu.get_node("%SettingsButton") as Button).pressed.emit()
	await _frames(3)
	_check(_asked(sfx, "ui") == clicks + 1, "pressing a menu button plays the click")
	var st: Node = app.call("current")
	if st == null or st.get_node_or_null("%SfxSlider") == null:
		_check(false, "Settings opens with the sound rows")
		_finish()
		return
	var fx := st.get_node("%SfxSlider") as HSlider
	var mus := st.get_node("%MusSlider") as HSlider
	var mute := st.get_node("%MuteButton") as Button
	_check(fx.is_visible_in_tree() and mus.is_visible_in_tree() and mute.is_visible_in_tree(), "effects slider, music slider and mute show")
	_check(is_equal_approx(fx.value, 0.8) and is_equal_approx(mus.value, 0.6) and not mute.button_pressed, "they start at the defaults (0.8, 0.6, sound on)")
	fx.value = 0.4
	mus.value = 0.2
	await _frames(1)
	_check(is_equal_approx(float(app.get("sfx_vol")), 0.4) and is_equal_approx(float(app.get("mus_vol")), 0.2), "the sliders set App's volumes")
	_check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects")) - linear_to_db(0.4)) < 0.01
		and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.2)) < 0.01, "…and the Effects and Music buses at once")
	mute.button_pressed = true
	await _frames(1)
	_check(not bool(app.get("snd")) and AudioServer.is_bus_mute(0), "mute silences everything (Master muted)")
	_check(not bool(sfx.call("play", &"boom")), "nothing plays while muted")
	_check(_saved() == {"sfx_vol": 0.4, "mus_vol": 0.2, "snd": false}, "every change is saved to the settings file", str(_saved()))
	mute.button_pressed = false
	await _frames(1)
	_check(bool(app.get("snd")) and not AudioServer.is_bus_mute(0), "unmute")

	# 2. English mode
	(st.get_node("%LangButton") as Button).pressed.emit()
	await _frames(2)
	var labels := [str((st.get_node("%SfxLabel") as Label).text), str((st.get_node("%MusLabel") as Label).text), mute.text]
	_check(labels == ["Sound effects", "Music", "Mute"], "the sound rows are English (%s)" % str(labels))
	var left := _thai_in(st)
	_check(left.is_empty(), "no Thai left on Settings", str(left))
	(st.get_node("%LangButton") as Button).pressed.emit()
	(st.get_node("%BackButton") as Button).pressed.emit()
	await _frames(3)
	_check(app.call("current") == menu and music.get("mood") == &"menu", "‹ กลับ: the main menu again, menu music")

	# 3. the deck: deck music, footsteps, a ping near a station
	menu.get_node("%PlayButton").pressed.emit()
	await _frames(3)
	var hall: Node = app.call("current")
	if hall == null or not hall.has_method("station"):
		_check(false, "เล่นกับบอท opens the deck")
		_finish()
		return
	_check(music.get("mood") == &"deck", "the deck plays the deck music (%s)" % str(music.get("mood")))
	var steps := int((sfx.get("stats")["by"] as Dictionary).get("stomp", 0))
	var pings := _asked(sfx, "ui")
	_key(KEY_W, true)
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < WALK_MS and str(hall.call("station")) == "":
		await process_frame
	_key(KEY_W, false)
	await _frames(2)
	var walked := int((sfx.get("stats")["by"] as Dictionary).get("stomp", 0)) - steps
	_check(walked >= 2, "footsteps sound while walking on the deck (%d steps)" % walked)
	if str(hall.call("station")) != "":
		_check(_asked(sfx, "ui") > pings, "reaching a station pings (%s)" % str(hall.call("station")))
	_finish()


func _asked(sfx: Node, kind: String) -> int:
	return int(((sfx.get("stats") as Dictionary)["ask"] as Dictionary).get(kind, 0))


func _saved() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return {}
	return {"sfx_vol": snappedf(float(cfg.get_value("app", "sfx_vol", -1.0)), 0.001),
		"mus_vol": snappedf(float(cfg.get_value("app", "mus_vol", -1.0)), 0.001), "snd": cfg.get_value("app", "snd", null)}


func _thai_in(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return out
	if n.name != &"LangButton":
		var txt := ""
		if n is Label:
			txt = (n as Label).text
		elif n is Button:
			txt = (n as Button).text
		if txt != "" and _thai_re.search(txt) != null:
			out.append("%s: %s" % [n.name, txt])
	for ch in n.get_children():
		out.append_array(_thai_in(ch))
	return out


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _finish() -> void:
	var app := _app()
	app.call("set_lang", "th")
	app.call("reset_settings")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 and _passed > 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 and _passed > 0 else 1)


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))
