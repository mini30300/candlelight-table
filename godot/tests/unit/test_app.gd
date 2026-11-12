extends "res://tests/testing.gd"
## The App autoload: settings round-trip through a ConfigFile, validation of the values, and the
## ScreenStack router (push / pop / replace / current / back). Fresh instances are used so the live autoload keeps its state.

const AppScript := preload("res://app/app.gd")
const TEST_DIR := "user://tests"


func setup() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))


func test_autoload_is_live() -> void:
	assert_true(App != null and App.is_inside_tree(), "the App autoload is in the tree under the runner")
	assert_true(AppScript.GFX_LEVELS.has(App.gfx), "gfx level is one of hi/mid/lo/min: " + App.gfx)
	assert_true(AppScript.LANGS.has(App.lang), "lang is th or en: " + App.lang)
	assert_true(App.server.begins_with("http"), "server URL is set: " + App.server)
	# the live App may already show a screen (inside the exported game main.tscn pushes the GPU check),
	# so the empty start state is checked on a fresh instance
	var fresh: Node = AppScript.new()
	assert_eq(fresh.current(), null, "a fresh App has no screen pushed")
	fresh.free()


func test_settings_round_trip() -> void:
	var path := TEST_DIR + "/settings_roundtrip.cfg"
	var a: Node = AppScript.new()
	assert_true(a.set_gfx("min"), "set_gfx accepts min")
	assert_true(a.set_lang("en"), "set_lang accepts en")
	a.snd = false
	a.set_server("http://localhost:8787/")
	assert_eq(a.server, "http://localhost:8787", "set_server strips the trailing slash")
	assert_true(a.set_fig("kit"), "set_fig accepts kit")
	assert_true(a.set_touch("on"), "set_touch accepts on")
	assert_true(a.save_settings(path), "save_settings writes " + path)
	var b: Node = AppScript.new()
	assert_true(b.load_settings(path), "load_settings reads the file back")
	assert_eq([b.gfx, b.lang, b.snd, b.server, b.fig, b.touch], ["min", "en", false, "http://localhost:8787", "kit", "on"], "every setting survives the round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	a.free()
	b.free()


func test_settings_validation_and_defaults() -> void:
	var a: Node = AppScript.new()
	a.reset_settings()
	assert_eq([a.gfx, a.lang, a.snd, a.server], [AppScript.DEFAULT_GFX, AppScript.DEFAULT_LANG, true, AppScript.DEFAULT_SERVER], "defaults after reset")
	assert_eq([a.fig, a.touch], ["egg", "auto"], "figure style egg and touch auto by default")
	assert_false(a.set_gfx("ultra"), "an unknown gfx level is refused")
	assert_eq(a.gfx, AppScript.DEFAULT_GFX, "…and the level is unchanged")
	assert_false(a.set_lang("fr"), "an unknown language is refused")
	a.set_server("   ")
	assert_eq(a.server, AppScript.DEFAULT_SERVER, "an empty server URL means the default")
	assert_false(a.load_settings(TEST_DIR + "/no-such-file.cfg"), "a missing settings file loads defaults and returns false")
	assert_eq(a.gfx, AppScript.DEFAULT_GFX, "defaults after a missing file")
	var broken := TEST_DIR + "/settings_broken.cfg"
	var f := FileAccess.open(broken, FileAccess.WRITE)
	f.store_string("[app\ngfx = = \"lo\"\n")
	f.close()
	a.set_gfx("lo")
	print("      (expected: the engine prints a ConfigFile parse error for the corrupt file next)")
	assert_false(a.load_settings(broken), "a corrupt settings file loads defaults and returns false")
	assert_eq(a.gfx, AppScript.DEFAULT_GFX, "defaults after a corrupt file (the app still opens)")
	var partial := TEST_DIR + "/settings_partial.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("app", "gfx", "hi")
	cfg.set_value("app", "lang", "klingon")
	cfg.save(partial)
	assert_true(a.load_settings(partial), "a partial file loads")
	assert_eq([a.gfx, a.lang, a.snd], ["hi", AppScript.DEFAULT_LANG, true], "missing or invalid keys fall back to defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(broken))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(partial))
	a.free()


func test_screen_stack_push_pop_current() -> void:
	var a: Node = AppScript.new()
	var host := Node.new()
	a.set_screen_root(host)
	var first := _packed("ScreenA")
	var second := _packed("ScreenB")
	assert_eq(a.depth(), 0, "empty stack")
	assert_false(a.pop(), "pop on an empty stack returns false")
	var s1: Node = a.push(first)
	assert_eq(a.current(), s1, "push returns the screen and it is current")
	assert_eq(s1.get_parent(), host, "the screen is added under the screen root")
	var s2: Node = a.push(second)
	assert_eq([a.current().name, a.depth()], [&"ScreenB", 2], "second push is current, depth 2")
	assert_false((s1 as CanvasItem).visible, "the previous screen is hidden, not freed")
	assert_true(a.pop(), "pop returns true")
	assert_eq(a.current(), s1, "the first screen is current again")
	assert_true((s1 as CanvasItem).visible, "…and visible again")
	assert_true(s2.is_queued_for_deletion(), "the popped screen is queued for deletion")
	assert_true(a.pop(), "pop the last screen")
	assert_eq([a.current(), a.depth()], [null, 0], "stack empty again")
	a.free()
	host.free()


## The figure style and touch settings: validation, unknown values in a file, and touch_active().
func test_fig_and_touch_settings() -> void:
	var a: Node = AppScript.new()
	a.reset_settings()
	assert_eq(Array(AppScript.FIG_STYLES), ["egg", "kit"], "two figure styles")
	assert_eq(Array(AppScript.TOUCH_MODES), ["auto", "on", "off"], "three touch modes")
	assert_false(a.set_fig("box"), "an unknown figure style is refused")
	assert_eq(a.fig, "egg", "…and the style is unchanged")
	assert_false(a.set_touch("maybe"), "an unknown touch mode is refused")
	assert_eq(a.touch, "auto", "…and the mode is unchanged")
	var bad := TEST_DIR + "/settings_bad_fig.cfg"
	var cfg := ConfigFile.new()
	cfg.set_value("app", "fig", "statue")
	cfg.set_value("app", "touch", "always")
	cfg.save(bad)
	a.set_fig("kit")
	a.set_touch("off")
	assert_true(a.load_settings(bad), "a file with unknown fig/touch values loads")
	assert_eq([a.fig, a.touch], ["egg", "auto"], "unknown fig/touch values in the file fall back to the defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))
	a.set_touch("on")
	assert_true(a.touch_active(), "touch on: the on-screen controls are active")
	a.set_touch("off")
	assert_false(a.touch_active(), "touch off: never active")
	a.set_touch("auto")
	assert_eq(a.touch_active(), OS.has_feature("mobile"), "touch auto: active only on a phone")
	a.free()


## Tests point settings_file at their own file, so load/save without a path never touch user://settings.cfg.
func test_settings_file_redirect() -> void:
	var path := TEST_DIR + "/settings_redirect.cfg"
	var a: Node = AppScript.new()
	assert_eq(a.settings_file, AppScript.SETTINGS_PATH, "settings_file defaults to user://settings.cfg")
	a.settings_file = path
	a.set_gfx("lo")
	a.set_fig("kit")
	assert_true(a.save_settings(), "save_settings() writes settings_file")
	assert_true(FileAccess.file_exists(path), "the redirected file exists")
	var b: Node = AppScript.new()
	b.settings_file = path
	assert_true(b.load_settings(), "load_settings() reads settings_file")
	assert_eq([b.gfx, b.fig], ["lo", "kit"], "the redirected file round-trips")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	a.free()
	b.free()


## replace(): the top screen is swapped, the depth stays and the screen below is never shown in between.
func test_screen_stack_replace() -> void:
	var a: Node = AppScript.new()
	var host := Node.new()
	a.set_screen_root(host)
	var s1: Node = a.push(_packed("Hall"))
	var s2: Node = a.push(_packed("Setup"))
	var shown := [0]
	(s1 as CanvasItem).visibility_changed.connect(func() -> void: shown[0] += 1)
	var s3: Node = a.replace(_packed("Battle"))
	assert_eq([a.current(), a.depth()], [s3, 2], "replace keeps the depth and the new screen is current")
	assert_false((s1 as CanvasItem).visible, "the screen below stays hidden")
	assert_eq(shown[0], 0, "the screen below never changed visibility")
	assert_true(s2.is_queued_for_deletion() and s2.get_parent() == null, "the replaced screen is removed and freed")
	assert_true(a.pop(), "pop the new screen")
	assert_eq(a.current(), s1, "pop after replace shows the screen below")
	assert_true((s1 as CanvasItem).visible, "…visible again")
	var e: Node = AppScript.new()
	var host2 := Node.new()
	e.set_screen_root(host2)
	var only: Node = e.replace(_packed("Menu"))
	assert_eq([e.current(), e.depth()], [only, 1], "replace on an empty stack is a push")
	a.free()
	host.free()
	e.free()
	host2.free()


## back(): the screen's handle_back() is asked first (true = handled, nothing popped), otherwise it pops.
func test_back_honours_handle_back() -> void:
	var a: Node = AppScript.new()
	var host := Node.new()
	a.set_screen_root(host)
	a.push(_packed("Menu"))
	var s2: Node = a.push(_packed_with_back("Panel"))
	s2.set("handled", true)
	a.back()
	assert_eq([a.current(), a.depth()], [s2, 2], "handle_back() returned true: the screen stays")
	assert_eq(s2.get("calls"), 1, "handle_back() was called once")
	s2.set("handled", false)
	a.back()
	assert_eq(a.depth(), 1, "handle_back() returned false: back pops")
	assert_eq(s2.get("calls"), 2, "handle_back() was asked again before the pop")
	a.back()
	assert_eq(a.depth(), 1, "at depth 1 a fresh App outside the tree neither pops nor quits")
	a.free()
	host.free()


static func _packed_with_back(name: String) -> PackedScene:
	var gs := GDScript.new()
	gs.source_code = "extends Control\nvar handled := false\nvar calls := 0\nfunc handle_back() -> bool:\n\tcalls += 1\n\treturn handled\n"
	gs.reload()
	var c := Control.new()
	c.set_script(gs)
	c.name = name
	var ps := PackedScene.new()
	ps.pack(c)
	c.free()
	return ps


static func _packed(name: String) -> PackedScene:
	var c := Control.new()
	c.name = name
	var ps := PackedScene.new()
	ps.pack(c)
	c.free()
	return ps
