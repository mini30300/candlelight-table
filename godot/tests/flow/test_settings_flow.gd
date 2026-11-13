extends SceneTree
## Settings reach every screen of the new flow, headless (LOBBY_SPEC §1: screens re-read App on show, Settings never
## reaches into a live 3D scene). Main menu → เล่นกับบอท → the hall's ตั้งค่า button → Settings: English, graphics lo,
## touch controls on, old models (when kits are on disk) → ‹ กลับ → the hall shows English signs and prompts, the stick
## and the touch prompt, level lo → walk to the war table, tap the use button → setup in English → a small bot game:
## old models (or eggs without kits), level lo, English HUD and end panel → กลับล็อบบี้ → Settings again from the hall:
## Thai, mid, touch off, eggs → the hall is Thai, stick hidden, level mid → Esc → the main menu is Thai. Every change
## is saved to the test settings file (never this machine's settings.cfg). Run:
##   timeout 600 <godot> --headless --path godot --audio-driver Dummy -s tests/flow/test_settings_flow.gd
## Exit code 1 on any failure; the last line is PASS or FAIL.

const SCENE := "res://scenes/main.tscn"
const SETTINGS_FILE := "user://test_settings_flow.cfg"
const KITS_DIR := "res://assets/kits"
const WALK_CAP_MS := 15000
const GAME_CAP_MS := 60000

var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")
var _machine_cfg := ""


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	_machine_cfg = _machine_settings()
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)   # never write this machine's settings.cfg from a test
	app.call("set_gfx", "mid")
	app.call("set_lang", "th")
	app.call("set_fig", "egg")
	app.call("set_touch", "off")
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("FAIL  cannot load " + SCENE)
		quit(1)
		return
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
	var menu: Node = app.call("current")
	if menu == null or menu.get_node_or_null("%PlayButton") == null:
		_check(false, "main.tscn opens the main menu")
		_finish()
		return
	menu.get_node("%PlayButton").pressed.emit()
	await _frames(3)
	var hall: Node = app.call("current")
	if hall == null or not hall.has_method("station"):
		_check(false, "เล่นกับบอท opens the hall")
		_finish()
		return
	var world: Node = hall.get("world")
	_check(str(world.call("counts")["level"]) == "mid" and not (hall.get_node("%Stick") as CanvasItem).visible,
		"the hall starts at level mid with no touch stick")

	# 1. the hall's ตั้งค่า button → Settings: English, lo, touch on, old models
	(hall.get_node("%SettingsButton") as Button).pressed.emit()
	await _frames(3)
	var st: Node = app.call("current")
	_check(st != null and st != hall and st.get_node_or_null("%GfxLo") != null, "the hall's settings button opens Settings")
	if st == null or st.get_node_or_null("%GfxLo") == null:
		_finish()
		return
	_check(not (world as Node3D).visible and world.process_mode == Node.PROCESS_MODE_DISABLED, "the hall world sleeps under Settings")
	var kits := _kits_on_disk()
	(st.get_node("%LangButton") as Button).pressed.emit()
	(st.get_node("%GfxLo") as Button).pressed.emit()
	(st.get_node("%TouchOn") as Button).pressed.emit()
	var fig_kit := st.get_node("%FigKit") as Button
	_check(fig_kit.disabled == not kits, "the old-models button is enabled exactly when kits are on disk (%s)" % str(kits))
	if not fig_kit.disabled:
		fig_kit.pressed.emit()
	await _frames(2)
	var want_fig := "kit" if kits else "egg"
	_check(str(app.get("lang")) == "en" and str(app.get("gfx")) == "lo" and str(app.get("touch")) == "on" and str(app.get("fig")) == want_fig,
		"Settings changed App (lang %s, gfx %s, touch %s, fig %s)" % [app.get("lang"), app.get("gfx"), app.get("touch"), app.get("fig")])
	_check(_saved() == {"lang": "en", "gfx": "lo", "touch": "on", "fig": want_fig}, "every change is saved to the settings file", str(_saved()))
	var left := _thai_in(st)
	_check(left.is_empty(), "Settings itself is English now", str(left))
	(st.get_node("%BackButton") as Button).pressed.emit()
	await _frames(3)

	# 2. the hall re-read everything on show
	_check(app.call("current") == hall and (world as Node3D).visible and world.process_mode != Node.PROCESS_MODE_DISABLED,
		"‹ กลับ returns to an active hall")
	_check(str(world.call("counts")["level"]) == "lo", "the hall runs at level lo now (%s)" % str(world.call("counts")["level"]))
	_check(Engine.max_fps == 30 and OS.low_processor_usage_mode, "level lo's frame cap and idle mode apply in the hall (fps %d)" % Engine.max_fps)
	_check((hall.get_node("%Stick") as CanvasItem).visible and bool(hall.get("touch_mode")), "the touch stick shows in the hall")
	_check(str(world.call("sign_text", "battle")) == "Battle Table", "the war table's 3D sign is English (%s)" % str(world.call("sign_text", "battle")))
	left = _thai_in(hall)
	for l: Label3D in world.call("labels"):
		if _thai_re.search(l.text) != null:
			left.append("Label3D " + l.text)
	_check(left.is_empty(), "no Thai in the hall or on its signs", str(left))

	# 3. walk to the war table: the touch prompt, then the use button opens setup
	var avatar := world.get("avatar") as Node3D
	_key(KEY_W, true)
	var t := Time.get_ticks_msec()
	while str(hall.call("station")) != "battle" and Time.get_ticks_msec() - t < WALK_CAP_MS:
		await process_frame
	_key(KEY_W, false)
	await _frames(2)
	var use := hall.get_node("%UseButton") as Button
	_check(str(hall.call("station")) == "battle" and use.visible and use.text == "Battle Table · tap to use",
		"at the war table the big button says '%s'" % use.text, str(avatar.global_position))
	use.pressed.emit()
	await _frames(3)
	var setup: Node = app.call("current")
	_check(setup != null and setup.has_method("start"), "the use button opens battle setup")
	if setup == null or not setup.has_method("start"):
		_finish()
		return
	left = _thai_in(setup)
	_check(left.is_empty(), "battle setup is English", str(left))

	# 4. a small bot game: the figure style and level from Settings, English HUD
	setup.call("set_teams", 2)
	setup.call("set_per_team", 1)
	setup.call("set_seat", 0, "kn", false)
	setup.call("set_seat", 1, "or", false)
	setup.call("set_size", "s")
	setup.call("set_goal", "obj")
	setup.call("set_rounds", 3)
	setup.call("set_budget", 300)
	setup.call("set_seed", 777)
	_check(bool(setup.call("start")), "START is accepted")
	await _frames(3)
	var battle: Node = app.call("current")
	if battle == null or not battle.has_method("is_over"):
		_check(false, "START opens the battle screen")
		_finish()
		return
	var table := root.get_tree().get_first_node_in_group("table_view") as Node3D
	var c: Dictionary = table.call("counts")
	_check(str(c.get("style", "")) == want_fig, "the battle draws the figure style chosen in Settings (%s)" % str(c.get("style", "")))
	_check(str(table.get("level")) == "lo", "the battle table runs at level lo (%s)" % str(table.get("level")))
	left = _thai_in(battle)
	_check(left.is_empty(), "the battle HUD is English", str(left))
	battle.call("set_speed", "instant")
	t = Time.get_ticks_msec()
	while not bool(battle.call("is_over")) and Time.get_ticks_msec() - t < GAME_CAP_MS:
		await process_frame
	await _frames(2)
	_check(bool(battle.call("is_over")) and (battle.get_node("%EndPanel") as CanvasItem).visible, "the game reaches the end panel")
	left = _thai_in(battle)
	_check(left.is_empty(), "the end panel is English", str(left))
	(battle.get_node("%LobbyButton") as Button).pressed.emit()
	await _frames(3)
	_check(app.call("current") == hall and not table.visible, "กลับล็อบบี้ returns to the hall and hides the table")

	# 5. Settings again from the hall: Thai, mid, touch off, eggs
	(hall.get_node("%SettingsButton") as Button).pressed.emit()
	await _frames(3)
	st = app.call("current")
	(st.get_node("%LangButton") as Button).pressed.emit()
	(st.get_node("%GfxMid") as Button).pressed.emit()
	(st.get_node("%TouchOff") as Button).pressed.emit()
	(st.get_node("%FigEgg") as Button).pressed.emit()
	await _frames(2)
	_check(_saved() == {"lang": "th", "gfx": "mid", "touch": "off", "fig": "egg"}, "the second round of changes is saved", str(_saved()))
	(st.get_node("%BackButton") as Button).pressed.emit()
	await _frames(3)
	_check(app.call("current") == hall and str(world.call("counts")["level"]) == "mid", "the hall is back at level mid")
	_check(Engine.max_fps == 60 and not OS.low_processor_usage_mode, "level mid's frame cap applies again (fps %d)" % Engine.max_fps)
	_check(not (hall.get_node("%Stick") as CanvasItem).visible and use.text == "โต๊ะรบ · กด E", "the stick hides and the prompt is Thai again (%s)" % use.text)
	_check(str(world.call("sign_text", "battle")) == "โต๊ะรบ", "the war table's sign is Thai again")

	# 6. Esc → the main menu, in Thai
	_key(KEY_ESCAPE, true)
	await _frames(1)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check(app.call("current") == menu and (menu.get_node("%PlayButton") as Button).text == "เล่นกับบอท", "Esc returns to a Thai main menu")
	_check(_machine_settings() == _machine_cfg, "this machine's settings.cfg was not touched")
	_finish()


## The settings file as the four keys this flow changes.
func _saved() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return {}
	var out := {}
	for k in ["lang", "gfx", "touch", "fig"]:
		out[k] = str(cfg.get_value("app", k, ""))
	return out


func _kits_on_disk() -> bool:
	var d := DirAccess.open(KITS_DIR)
	if d == null:
		return false
	for f in d.get_files():
		if f.ends_with(".glb") or f.ends_with(".glb.import"):
			return true
	return false


## Visible Label / Button / OptionButton texts with Thai in them (the LangButton's "ไทย" excepted).
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
		if n is OptionButton:
			var ob := n as OptionButton
			for i in ob.item_count:
				if _thai_re.search(ob.get_item_text(i)) != null:
					out.append("%s item %d: %s" % [n.name, i, ob.get_item_text(i)])
	for ch in n.get_children():
		out.append_array(_thai_in(ch))
	return out


func _machine_settings() -> String:
	var p := "user://settings.cfg"
	return "%d:%s" % [FileAccess.get_modified_time(p), FileAccess.get_file_as_string(p)] if FileAccess.file_exists(p) else "none"


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
