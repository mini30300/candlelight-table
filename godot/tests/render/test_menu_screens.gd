extends SceneTree
## The main menu and the settings screen (LOBBY_SPEC §1.1, §5, §7.2) inside scenes/main.tscn, at window sizes
## 640x360 (a logical 1280x720 canvas), 1280x720 and 1280x576 (20:9, a logical 1600x720), in Thai and English:
## nothing sticks out of the canvas or its parent, no two sibling buttons overlap, every button is at least 44x44,
## English mode shows no Thai (the LangButton's "ไทย" excepted) and Thai mode shows Thai titles. Every settings control
## changes App and persists through a test settings file (never this machine's settings.cfg). The toast shows and hides,
## Back and Esc open the quit confirm and close it again, and on the min level nothing runs per frame.
## 0.5 (NET_SPEC §7.1, §12.1): the online button no longer shows a coming-soon toast or badge: it opens the deck with
## the play-with-friends screen on top (depth 3); back returns to the deck (round B: at the spawn, every app shows the
## button), back again to the menu. A fake Net (tests/unit/fixtures/fake_net.gd) stands in for /root/Net for the run, so
## the airlock screen's join list opens no socket.
## Saves menu_th.png, menu_en.png, settings_th.png, settings_en.png (_<w>x<h> added for the other sizes). Run:
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_menu_screens.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/main.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_menu_screens.cfg"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(640, 360), Vector2i(1280, 576)]
const SETTLE := 6
const MIN_TARGET := 44.0
const MENU_NAMES: PackedStringArray = ["PlayButton", "OnlineButton", "SettingsButton", "LangButton", "QuitButton",
	"VersionLabel", "Title", "Toast", "QuitConfirm"]
const SETTINGS_NAMES: PackedStringArray = ["LangButton", "GfxHi", "GfxMid", "GfxLo", "GfxMin", "FigEgg", "FigKit",
	"TouchAuto", "TouchOn", "TouchOff", "GpuCheckButton", "BackButton"]

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _thai_re := RegEx.create_from_string("[฀-๿]")
var _fake_net: Node
var _real_net: Node
var _machine_cfg := ""   # this machine's settings.cfg at the start (must be the same at the end)


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	_machine_cfg = _machine_settings()
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)   # never write this machine's settings.cfg from a test
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_fig", "egg")
	app.call("set_touch", "auto")
	# 0.5: the airlock screen reads /root/Net; a fake takes its place (the real one is renamed aside, put back at the end)
	_real_net = root.get_node_or_null(^"Net")
	if _real_net != null:
		_real_net.name = "NetReal"
	_fake_net = (load("res://tests/unit/fixtures/fake_net.gd") as GDScript).new()
	_fake_net.name = "Net"
	root.add_child(_fake_net)
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("FAIL  cannot load " + SCENE)
		quit(1)
		return
	_main = scene.instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(4)
	var menu: Node = _app().call("current")
	_check(menu != null and menu.has_method("handle_back") and menu.has_method("refresh"), "main.tscn opens the main menu (handle_back, refresh)")
	if menu == null or not menu.has_method("handle_back"):
		_finish()
		return
	var missing := PackedStringArray()
	for n in MENU_NAMES:
		if menu.get_node_or_null("%" + n) == null:
			missing.append(n)
	_check(missing.is_empty(), "the main menu carries every contract node", str(missing))
	_check(menu.get_node("%LangButton").name == &"LangButton", "the language button is a node named LangButton")
	_check(int(_app().call("depth")) == 1, "the main menu is the only screen (depth 1)")
	var table := _main.get_node_or_null(^"World/BattleTable") as Node3D
	_check(table != null and not table.visible and table.process_mode == Node.PROCESS_MODE_DISABLED and not bool(table.get("built")),
		"the demo table is not built at startup, hidden and its processing disabled")

	for sz in SIZES:
		await _resize(sz)
		await _check_menu_at(menu, sz)
		await _check_settings_at(menu, sz)
	await _resize(SIZES[0])

	await _check_settings_controls(menu)
	await _check_online(menu)
	await _check_toast(menu)
	await _check_back(menu)
	await _check_idle_levels(menu)
	_finish()


## One window size: the menu in Thai and English, layout and text.
func _check_menu_at(menu: Node, sz: Vector2i) -> void:
	var vis := root.get_visible_rect().size
	var suffix := _suffix(sz)
	for lang in ["th", "en"]:
		menu.call("set_language", lang == "en", false)
		await _frames(2)
		var probs := _layout_problems(menu)
		_check(probs.is_empty(), "menu %s %dx%d (canvas %dx%d): nothing overflows, no overlaps, targets >= 44" % [lang, sz.x, sz.y, int(vis.x), int(vis.y)], str(probs.slice(0, 8)))
		var title := str(menu.get_node("%Title").get("text"))
		var ver := str(menu.get_node("%VersionLabel").get("text"))
		if lang == "th":
			_check(_thai_re.search(title) != null, "menu th: the title is Thai (%s)" % title)
			_check(str(menu.get_node("%LangButton").get("text")) == "ENGLISH", "menu th: the language button says ENGLISH")
		else:
			_check(title == "Candlelight Table", "menu en: the title is translated (%s)" % title)
			var left := _thai_in(menu, ["LangButton"])
			_check(left.is_empty(), "menu en %dx%d: no Thai left on screen" % [sz.x, sz.y], str(left))
			_check(str(menu.get_node("%LangButton").get("text")) == "ไทย", "menu en: the language button offers ไทย")
			_check(_thai_re.search(ver) == null and ver.contains("0."), "menu en: the version label has no Thai (%s)" % ver)
		_save("menu_%s%s.png" % [lang, suffix])
	menu.call("set_language", false, false)


## One window size: settings in Thai and English, layout and text; back returns to the menu.
func _check_settings_at(menu: Node, sz: Vector2i) -> void:
	menu.get_node("%SettingsButton").pressed.emit()
	await _frames(SETTLE)
	var st: Node = _app().call("current")
	_check(st != null and st != menu and st.get_node_or_null("%GfxMin") != null, "the settings button opens settings (%dx%d)" % [sz.x, sz.y])
	if st == null or st.get_node_or_null("%GfxMin") == null:
		return
	var suffix := _suffix(sz)
	for lang in ["th", "en"]:
		st.call("set_language", lang == "en")
		await _frames(2)
		var probs := _layout_problems(st)
		_check(probs.is_empty(), "settings %s %dx%d: nothing overflows, no overlaps, targets >= 44" % [lang, sz.x, sz.y], str(probs.slice(0, 8)))
		var title := str(st.get_node("%Title").get("text"))
		if lang == "th":
			_check(_thai_re.search(title) != null, "settings th: the title is Thai (%s)" % title)
		else:
			_check(title == "Settings", "settings en: the title is translated (%s)" % title)
			var left := _thai_in(st, ["LangButton"])
			_check(left.is_empty(), "settings en %dx%d: no Thai left on screen" % [sz.x, sz.y], str(left))
		_save("settings_%s%s.png" % [lang, suffix])
	st.call("set_language", false)
	st.get_node("%BackButton").pressed.emit()
	await _frames(2)
	_check(_app().call("current") == menu and (menu as CanvasItem).visible, "settings' back button returns to the visible main menu")


## Every settings control changes App and persists through the test settings file.
func _check_settings_controls(menu: Node) -> void:
	menu.get_node("%SettingsButton").pressed.emit()
	await _frames(2)
	var st: Node = _app().call("current")
	var missing := PackedStringArray()
	for n in SETTINGS_NAMES:
		if st.get_node_or_null("%" + n) == null:
			missing.append(n)
	_check(missing.is_empty(), "settings carries every contract node", str(missing))
	if not missing.is_empty():
		return
	var app := _app()
	var bad := PackedStringArray()
	for pair in [["GfxHi", "gfx", "hi"], ["GfxLo", "gfx", "lo"], ["GfxMin", "gfx", "min"], ["GfxMid", "gfx", "mid"],
			["TouchOn", "touch", "on"], ["TouchOff", "touch", "off"], ["TouchAuto", "touch", "auto"]]:
		st.get_node("%" + str(pair[0])).pressed.emit()
		if str(app.get(pair[1])) != pair[2]:
			bad.append("%s: App.%s = %s" % [pair[0], pair[1], str(app.get(pair[1]))])
		if str(_saved(pair[1])) != pair[2]:
			bad.append("%s: the file has %s = %s" % [pair[0], pair[1], str(_saved(pair[1]))])
		if not (st.get_node("%" + str(pair[0])) as Button).button_pressed:
			bad.append(str(pair[0]) + " is not shown pressed")
	_check(bad.is_empty(), "graphics and touch buttons change App, save the file and show as pressed", str(bad))
	var has_kits := bool(st.call("has_kits"))
	var kit: Button = st.get_node("%FigKit")
	_check(kit.disabled == not has_kits, "the old-models button is enabled exactly when kits are on disk (kits: %s)" % str(has_kits))
	if has_kits:
		kit.pressed.emit()
		_check(str(app.get("fig")) == "kit" and str(_saved("fig")) == "kit", "the old-models button selects kit and saves it")
	st.get_node("%FigEgg").pressed.emit()
	_check(str(app.get("fig")) == "egg" and str(_saved("fig")) == "egg", "the egg button selects egg and saves it")
	st.set("kits_override", 0)
	st.call("refresh")
	_check(kit.disabled, "without kits on disk the old-models button is disabled")
	_check(str(st.get_node("%FigNote").get("text")) == "ไม่พบชุดโมเดลในเครื่องนี้", "…and the note says no kits were found")
	st.call("set_fig", "kit")
	_check(str(app.get("fig")) == "egg", "…and kit cannot be chosen")
	st.set("kits_override", -1)
	st.call("refresh")
	st.get_node("%LangButton").pressed.emit()
	_check(str(app.get("lang")) == "en" and str(_saved("lang")) == "en" and str(st.get_node("%Title").get("text")) == "Settings",
		"the language button switches to English, saves it and redraws")
	st.get_node("%LangButton").pressed.emit()
	_check(str(app.get("lang")) == "th" and str(_saved("lang")) == "th", "…and back to Thai")
	var probe: Node = load("res://app/app.gd").new()
	probe.set("settings_file", SETTINGS_FILE)
	_check(bool(probe.call("load_settings")), "a fresh App reads the test settings file")
	_check([probe.get("gfx"), probe.get("lang"), probe.get("fig"), probe.get("touch")] == [app.get("gfx"), app.get("lang"), app.get("fig"), app.get("touch")],
		"every setting round-trips through the file")
	probe.free()
	_check(_machine_settings() == _machine_cfg, "this machine's settings.cfg was not written by the test")
	# the GPU check stays reachable from settings and shows / hides the demo table
	st.get_node("%GpuCheckButton").pressed.emit()
	await _frames(SETTLE)
	var gpu: Node = app.call("current")
	var table := _main.get_node(^"World/BattleTable") as Node3D
	_check(gpu != null and gpu.has_signal("army_requested"), "the GPU-check button opens the GPU check")
	_check(table.visible and table.process_mode == Node.PROCESS_MODE_INHERIT and int(table.call("counts")["figures"]) > 0,
		"the GPU check builds and shows the demo table")
	gpu.get_node("%BackButton").pressed.emit()
	await _frames(2)
	_check(app.call("current") == st, "the GPU check's back button returns to settings")
	_check(not table.visible and table.process_mode == Node.PROCESS_MODE_DISABLED, "leaving the GPU check hides the table and disables it again")
	st.get_node("%BackButton").pressed.emit()
	await _frames(2)


## 0.5 (NET_SPEC §7.1): the online button opens the deck with the play-with-friends screen on top (depth 3), no badge.
## Round B (14 Nov): every app shows it (the public app plays on the deck); with no pack room the deck opens at the spawn
## and host/join on top right away; back returns to the deck (camera current, no station), back again to the main menu.
func _check_online(menu: Node) -> void:
	var app := _app()
	for flag in [false, true]:
		Features.set_flag(&"online", flag)
		menu.call("refresh")
		var tag := "online flag %s" % ("on" if flag else "off")
		_check((menu.get_node("%OnlineButton") as CanvasItem).visible, tag + ": the main menu shows the online button")
		_check(not (menu.get_node("%OnlineBadge") as CanvasItem).visible, tag + ": the online button has no coming-soon badge")
		_fake_net.set("calls", [])
		menu.get_node("%OnlineButton").pressed.emit()
		await _frames(4)
		var lobby: Node = app.call("current")
		_check(int(app.call("depth")) == 3 and lobby != null and lobby.scene_file_path == "res://ui/screens/lobby.tscn",
			tag + ": the online button opens the deck and the play-with-friends screen on top (depth 3)")
		_check(not (menu.get_node("%Toast") as CanvasItem).visible, tag + ": no coming-soon toast")
		_check(_fake_net.call("calls_of", "find") == [["find", true]], tag + ": the screen opens the join list on the (fake) Net")
		app.call("back")
		await _frames(4)
		var hall: Node = app.call("current")
		var world: Node3D = hall.get("world") if hall != null else null
		_check(int(app.call("depth")) == 2 and world != null and world.visible and (world.get("camera_rig").get("camera") as Camera3D).current,
			tag + ": back returns to the deck with its camera current (depth 2)")
		if world != null:
			var av := world.get("avatar") as Node3D
			_check(av.global_position.distance_to(HallLayout.SPAWN) < 0.05 and str(hall.call("station")) == ""
				and not bool(world.call("station_enabled", "online")),
				tag + ": no pack room: the avatar stands at the spawn, the airlock is no station (%s)" % str(av.global_position))
		app.call("back")
		await _frames(4)
		_check(app.call("current") == menu and int(app.call("depth")) == 1, tag + ": back again returns to the main menu")
	Features.set_flag(&"online", false)
	menu.call("refresh")


## The toast (kept for messages; the online button no longer uses it) shows for 2.5 s, in the current language.
func _check_toast(menu: Node) -> void:
	var toast: Control = menu.get_node("%Toast")
	_check(not toast.visible, "no toast at first")
	# 0.5: the online button opens the airlock now, so the toast is shown directly with a menu key
	menu.call("show_toast", "ออนไลน์กับเพื่อน เร็วๆ นี้")
	await _frames(2)
	var text := str(menu.get_node("%ToastText").get("text"))
	_check(toast.visible and text == "ออนไลน์กับเพื่อน เร็วๆ นี้", "the toast shows its line (%s)" % text)
	var timer: Timer = menu.get_node("%ToastTimer")
	_check(not timer.is_stopped() and absf(timer.wait_time - 2.5) < 0.01, "the toast closes after 2.5 s (timer %.2f)" % timer.wait_time)
	_check(_layout_problems(menu).is_empty(), "the toast fits the screen", str(_layout_problems(menu).slice(0, 4)))
	menu.call("set_language", true, false)
	await _frames(2)
	_check(_thai_re.search(str(menu.get_node("%ToastText").get("text"))) == null, "the toast follows the language switch")
	_save("menu_toast_en.png")
	menu.call("set_language", false, false)
	await create_timer(2.8).timeout
	_check(not toast.visible and timer.is_stopped(), "the toast is gone after 2.5 s")


## Back (App.back, the Android back button) and Esc open the quit confirm; a second press closes it.
func _check_back(menu: Node) -> void:
	var app := _app()
	var confirm: Control = menu.get_node("%QuitConfirm")
	menu.set("quit_for_real", false)
	app.call("back")
	await _frames(2)
	_check(confirm.visible and app.call("current") == menu, "Back on the main menu opens the quit confirm (and does not quit)")
	_check(_layout_problems(menu).is_empty(), "the quit confirm fits", str(_layout_problems(menu).slice(0, 4)))
	_check(str(menu.get_node("%QuitText").get("text")) == "ออกจากเกม?", "the confirm asks ออกจากเกม?")
	_save("menu_quit_th.png")
	app.call("back")
	await _frames(2)
	_check(not confirm.visible, "Back again closes the confirm")
	_esc()
	await _frames(2)
	_check(confirm.visible, "Esc (the back action) opens the quit confirm")
	_esc()
	await _frames(2)
	_check(not confirm.visible, "Esc again closes it")
	menu.get_node("%QuitButton").pressed.emit()
	_check(confirm.visible and (menu.get_node("%QuitButton") as Control).visible, "the desktop quit button opens the confirm")
	menu.get_node("%QuitNo").pressed.emit()
	_check(not confirm.visible, "ยกเลิก closes it")
	var quits := [0]
	menu.connect("quit_confirmed", func() -> void: quits[0] += 1)
	menu.get_node("%QuitButton").pressed.emit()
	menu.get_node("%QuitYes").pressed.emit()
	_check(quits[0] == 1, "ออก confirms the quit")
	menu.call("close_quit_confirm")
	menu.set("quit_override", "off")
	menu.call("refresh")
	_check(not (menu.get_node("%QuitButton") as Control).visible, "the quit button hides on a phone")
	menu.set("quit_override", "")
	menu.call("refresh")


## hi/mid: the candles flicker on a Timer (6 Hz or less); lo/min: drawn once, nothing runs per frame.
func _check_idle_levels(menu: Node) -> void:
	var app := _app()
	var art: Node = menu.get_node("%Art")
	app.call("set_gfx", "hi")
	menu.call("refresh")
	await _frames(1)
	var d0 := int(art.get("draws"))
	await create_timer(0.7).timeout
	var timer: Timer = art.get_node("FlickerTimer")
	_check(bool(art.call("flickering")) and timer.wait_time >= 1.0 / 6.0 - 0.0001, "hi: the candles flicker on a Timer at 6 Hz or less (%.2f s)" % timer.wait_time)
	_check(int(art.get("draws")) - d0 >= 2, "hi: the title art redraws while flickering (%d redraws)" % (int(art.get("draws")) - d0))
	for l in ["lo", "min"]:
		app.call("set_gfx", l)
		menu.call("refresh")
		await _frames(2)
		var d1 := int(art.get("draws"))
		await _frames(10)
		_check(not bool(art.call("flickering")) and int(art.get("draws")) == d1, "%s: the title art is static (no redraw in 10 frames)" % l)
	_check(_idle_problems(menu).is_empty(), "min: nothing on the main menu processes per frame", str(_idle_problems(menu)))
	menu.get_node("%SettingsButton").pressed.emit()
	await _frames(SETTLE)
	var st: Node = app.call("current")
	_check(_idle_problems(st).is_empty(), "min: nothing on the settings screen processes per frame", str(_idle_problems(st)))
	_check(not bool(art.call("flickering")), "the hidden menu's art timer is stopped")
	st.get_node("%BackButton").pressed.emit()
	await _frames(2)
	app.call("set_gfx", "mid")
	menu.call("refresh")


## Nodes under a screen that would run every frame: _process / _physics_process on, or a running Timer.
func _idle_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_processing() or n.is_physics_processing():
			out.append(String(n.name) + " processes")
		if n is Timer and not (n as Timer).is_stopped():
			out.append(String(n.name) + " timer runs")
		stack.append_array(n.get_children())
	return out


## Layout rules of LOBBY_SPEC §7.1 for every visible Control under the screen.
func _layout_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var vis := root.get_visible_rect()
	_walk(screen, func(c: Control) -> void:
		var r := c.get_global_rect()
		if r.position.x < vis.position.x - 1.0 or r.position.y < vis.position.y - 1.0 or r.end.x > vis.end.x + 1.0 or r.end.y > vis.end.y + 1.0:
			out.append("%s outside the canvas %s" % [c.name, str(r)])
		var p := c.get_parent() as Control
		if p != null and not p is ScrollContainer:
			var pr := p.get_global_rect()
			if r.position.x < pr.position.x - 1.0 or r.position.y < pr.position.y - 1.0 or r.end.x > pr.end.x + 1.0 or r.end.y > pr.end.y + 1.0:
				out.append("%s outside its parent %s: %s in %s" % [c.name, p.name, str(r), str(pr)])
		if c is Button and (r.size.x < MIN_TARGET - 0.5 or r.size.y < MIN_TARGET - 0.5):
			out.append("%s smaller than 44x44 %s" % [c.name, str(r.size)])
		var buttons: Array[Control] = []
		for s in c.get_children():
			if s is Button and (s as Control).is_visible_in_tree():
				buttons.append(s)
		for i in buttons.size():
			for j in range(i + 1, buttons.size()):
				if buttons[i].get_global_rect().intersection(buttons[j].get_global_rect()).get_area() > 1.0:
					out.append("%s overlaps %s" % [buttons[i].name, buttons[j].name]))
	return out


func _walk(node: Node, f: Callable) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		f.call(node)
	for c in node.get_children():
		_walk(c, f)


## Every visible text of the screen that still contains Thai: "NodeName: text"
func _thai_in(node: Node, exempt: Array) -> PackedStringArray:
	var out := PackedStringArray()
	_scan(node, exempt, out)
	return out


func _scan(node: Node, exempt: Array, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if not exempt.has(String(node.name)):
		var texts := PackedStringArray()
		if node is Label or node is Button:
			texts.append(str(node.get("text")))
		if node is OptionButton:
			for i in (node as OptionButton).item_count:
				texts.append((node as OptionButton).get_item_text(i))
		if node is LineEdit:
			texts.append((node as LineEdit).placeholder_text)
		if node is Label3D:
			texts.append((node as Label3D).text)
		if node is Control and (node as Control).tooltip_text != "":
			texts.append((node as Control).tooltip_text)
		for t in texts:
			if _thai_re.search(t) != null:
				out.append(String(node.name) + ": " + t.left(60))
	for c in node.get_children():
		_scan(c, exempt, out)


func _esc() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_ESCAPE
		ev.keycode = KEY_ESCAPE
		ev.pressed = pressed
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _machine_settings() -> String:
	var p := "user://settings.cfg"
	return "%d:%s" % [FileAccess.get_modified_time(p), FileAccess.get_file_as_string(p)] if FileAccess.file_exists(p) else "none"


func _saved(key: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE) != OK:
		return null
	return cfg.get_value("app", key, null)


func _resize(sz: Vector2i) -> void:
	root.size = sz
	await _frames(SETTLE)


func _suffix(sz: Vector2i) -> String:
	return "" if sz == SIZES[0] else "_%dx%d" % [sz.x, sz.y]


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))
	_check(_mean_luma(img) > 0.02, name + " is not black")


func _finish() -> void:
	var app := _app()
	app.call("set_lang", "th")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	if _fake_net != null:
		_fake_net.name = "FakeNet"
		_fake_net.queue_free()
	if _real_net != null:
		_real_net.name = "Net"
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
