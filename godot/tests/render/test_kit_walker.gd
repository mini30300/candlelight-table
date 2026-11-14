extends SceneTree
## Kit walkers on the deck (PACK_SPEC §10): the dressing room's choice reaches the deck avatar through Figures.select and
## App.figure_changed. With nothing chosen the avatar keeps its egg; choosing a kit rebuilds it as a KitWalker of that kit
## in the chosen scheme (paint row set); W walks it with the humanoid walk clip at the kit's deck speed (no foot slide:
## playback rate = speed / (clip speed x scale)), Shift+W runs, releasing returns to idle and the avatar stops processing;
## on every level the overview stays within the deck targets (SHIP_LOBBY_SPEC §6) with no more draw calls than the egg;
## standing on lo no AnimationPlayer plays, on min after 10 idle frames nothing under the hall processes; a close view of
## six kits in six schemes is saved; choosing the egg again restores it. Saves kit_walker_<level>.png,
## kit_walker_walk.png and kit_walker_<kit>_<scheme>.png. Run:
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_kit_walker.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/main.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_kit_walker.cfg"
const FAKE_NET := "res://tests/unit/fixtures/fake_net.gd"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const SHIP_TARGET := {"hi": [40, 60000], "mid": [40, 50000], "lo": [35, 40000], "min": [30, 30000]}
const WALK_TICKS := 45
const LOOKS := [["kit_kblade", "blue"], ["kit_warrior", "purple"], ["kit_nob", "green"], ["kit_elguard", "white"],
	["kit_samurai", "red"], ["kit_viking", "pink"], ["kit_cxw", "black"], ["kit_spartan", "gold"]]

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _fake: Node
var _real_net: Node


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_lang", "th")
	app.call("set_gfx", "mid")
	app.call("set_touch", "off")
	_real_net = root.get_node_or_null(^"Net")
	if _real_net != null:
		_real_net.name = "NetReal"
	_fake = (load(FAKE_NET) as GDScript).new()
	_fake.name = "Net"
	root.add_child(_fake)
	_main = (load(SCENE) as PackedScene).instantiate()
	_main.set("first_run_guess", false)
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	await _frames(4)
	var menu: Node = _app().call("current")
	(menu.get_node("%PlayButton") as Button).pressed.emit()
	await _frames(3)
	var hall: Node = _app().call("current")
	var world: Node3D = hall.get("world") if hall != null else null
	_check(world != null and world.has_method("refresh_figure"), "the play button opens the deck; its world has refresh_figure")
	if world == null:
		_finish()
		return
	var av: Node3D = world.get("avatar")
	var rig: Node3D = world.get("camera_rig")
	var egg := av.get_node("Egg") as MeshInstance3D
	_check(av.get("figure") == null and egg.visible and Figures.selected()["figure"] == "egg",
		"nothing chosen (no pack): the deck avatar is the egg")
	# choose a kit: App.figure_changed rebuilds the avatar
	Figures.select("kit_kblade", "pink")
	await _frames(2)
	var fig := av.get("figure") as KitWalker
	_check(fig != null and fig.kit_key() == "kblade" and not egg.visible and fig.get_parent() == av,
		"Figures.select(kit_kblade) rebuilds the avatar as a KitWalker of kblade, the egg hidden")
	if fig == null:
		_finish()
		return
	var mat := (fig.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override as ShaderMaterial
	_check(int(mat.get_shader_parameter("paint_row")) == 0 and fig.scheme()[0] == Figures.scheme("pink")["primary"],
		"it wears the pink scheme (paint row 0)")
	var sp: Vector2 = fig.deck_speeds()
	_check(is_equal_approx(float(av.get("walk_speed")), clampf(sp.x, 0.5, 6.0)) and is_equal_approx(float(av.get("run_speed")), clampf(sp.y, 0.5, 6.0)),
		"the avatar takes the kit's deck speeds %s" % str(sp))
	# walk and run: the humanoid clips at a rate that matches the speed
	var ap := fig.animation_player()
	var lib := load(KitBeast.LIB_PATH) as AnimationLibrary
	rig.call("set_view", 0.0, -0.45, 6.5)
	for run in [false, true]:
		world.call("place_avatar", Vector3(2.0, 0.0, 7.0), PI)
		await _physics(4)
		var keys := [KEY_SHIFT, KEY_W] if run else [KEY_W]
		for k in keys:
			_key(k, true)
		await _physics(WALK_TICKS)
		var clip := "run" if run else "walk"
		var want := float(lib.get_animation(clip).get_meta("speed", 1.0)) * float(fig.get("_scale"))
		var rate := float(av.call("speed")) / want
		_check(ap.current_animation == "humanoid/" + clip and absf(ap.speed_scale - rate) < 0.05,
			"%s: plays humanoid/%s at rate %.2f for %.2f m/s (clip %.2f m/s, no foot slide)" % ["Shift+W" if run else "W", clip,
			ap.speed_scale, float(av.call("speed")), want])
		if not run:
			_save("kit_walker_walk.png")
		for k in keys:
			_key(k, false)
		for i in 180:
			if not av.is_physics_processing():
				break
			await physics_frame
		await _physics(2)
		_check(not av.is_physics_processing() and ap.current_animation == "humanoid/idle", "released: idle, the avatar stops processing")
	# every level: within the deck targets, no more draw calls than the egg
	world.call("place_avatar", Vector3(0.0, 0.0, 3.5), PI)
	rig.call("set_view", 0.0, -0.6, 9.0)
	for level in LEVELS:
		_app().call("set_gfx", level)
		hall.call("refresh")
		Figures.select("egg", "blue")
		var egg_m := await _measure()
		Figures.select("kit_kblade", "pink")
		var kit_m := await _measure()
		fig = av.get("figure") as KitWalker
		print("deck level %-4s kit walker: draw calls %3d  primitives %6d  (egg %d / %d)" % [level, kit_m[0], kit_m[1], egg_m[0], egg_m[1]])
		var t: Array = SHIP_TARGET[level]
		_check(fig != null and fig.gfx == level, "%s: the rebuilt walker gets the app's level" % level)
		_check(kit_m[0] <= int(t[0]) and kit_m[1] <= int(t[1]) and kit_m[0] <= egg_m[0],
			"%s with a kit walker: %d draw calls (egg %d), %d primitives within %d / %d" % [level, kit_m[0], egg_m[0], kit_m[1], int(t[0]), int(t[1])])
		_save("kit_walker_%s.png" % level)
		if level == "lo" or level == "min":
			await _frames(10)
			var playing := PackedStringArray()
			for n in av.find_children("*", "AnimationPlayer", true, false):
				if (n as AnimationPlayer).is_playing():
					playing.append(String(n.name))
			_check(playing.is_empty() and fig.is_still(), "%s: standing, the walker holds a still pose (no AnimationPlayer plays)" % level)
		if level == "min":
			var probs := _idle_problems(hall)
			_check(probs.is_empty(), "min: after 10 idle frames nothing under the hall processes", ", ".join(probs))
	# close views of several kits in several schemes (mid)
	_app().call("set_gfx", "mid")
	hall.call("refresh")
	world.call("place_avatar", Vector3(0.0, 0.0, 3.5), PI)
	rig.call("set_view", PI * 0.85, -0.25, 3.4)
	for look in LOOKS:
		Figures.select(str(look[0]), str(look[1]))
		await _frames(6)
		var f := av.get("figure") as KitWalker
		_check(f != null and "kit_" + f.kit_key() == str(look[0]), "%s in %s on the deck" % [look[0], look[1]])
		_save("kit_walker_%s_%s.png" % [str(look[0]).trim_prefix("kit_"), look[1]])
	# back to the egg
	Figures.select("egg", "blue")
	await _frames(2)
	_check(av.get("figure") == null and egg.visible and is_equal_approx(float(av.get("walk_speed")), HallAvatar.WALK),
		"choosing the egg brings the egg back with the 3.0 m/s walk")
	_finish()


func _measure() -> Array:
	var idle := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await _frames(4)
	var draws := 0
	var prims := 0
	for i in 4:
		await process_frame
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	OS.low_processor_usage_mode = idle
	return [draws, prims]


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


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	_check(img.save_png(path) == OK, "saved " + ProjectSettings.globalize_path(path))


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))


func _finish() -> void:
	for k in [KEY_W, KEY_SHIFT]:
		_key(k, false)
	if _fake != null:
		_fake.name = "FakeNet"
		_fake.queue_free()
	if _real_net != null:
		_real_net.name = "Net"
	var app := _app()
	app.call("set_lang", "th")
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	_done = true
	quit(0 if _failed == 0 else 1)
