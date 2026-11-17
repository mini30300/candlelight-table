extends SceneTree
## Round D (owner, 14 Nov; ARENA_SPEC §9.6): the arena plays the figure picked in the dressing room. Inside
## scenes/main.tscn the arena screen is pushed twice with a selection saved through Figures.select: a battle-table kit
## (infantry, red) -> KitFighter painted red, and the dressed pack fixture (tests/fixtures/figure_pack_paint, painted,
## pink) -> its own script dressed pink after setup. Per case and level (hi/mid/lo/min): the arena overview within the
## §11.2 budgets of test_arena, a shot from the figure's muzzle (a tracer, the muzzle within 1.3 m of the chest), A/D
## turning the camera with the body (no sideways motion), and on min with the kit, after idle frames, nothing under the
## arena processes and the kit holds a still pose. Saves arena_fig_<case>_<level>.png (a close walk view, mid and min).
## Run:
##   timeout 900 nice -n 10 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_arena_figures.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/main.tscn"
const ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_arena_figures.cfg"
const PAINT_LIST := "res://tests/fixtures/figure_pack_paint/figures.json"
const NONE_PACK := "res://tests/unit/fixtures/no_such_pack/pack.json"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
## the overview budgets of test_arena (ARENA_SPEC §11.2) [draw calls, primitives]
const OVERVIEW := {"hi": [50, 80000], "mid": [45, 60000], "lo": [35, 40000], "min": [30, 30000]}
const CASES: Array[Dictionary] = [
	{"name": "kit", "figure": "kit_infantry", "scheme": "red", "list": ""},
	{"name": "pack", "figure": "painted", "scheme": "pink", "list": PAINT_LIST},
]

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0


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
	Figures.store_path = SETTINGS_FILE
	Figures.pack_manifest = NONE_PACK
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
	for c in CASES:
		Figures.pack_list = str(c["list"]) if str(c["list"]) != "" else "res://tests/unit/fixtures/no_such_pack/figures.json"
		if Figures.entry(str(c["figure"])).is_empty():
			_check(false, "%s: the figure %s is in the list" % [c["name"], c["figure"]])
			continue
		Figures.select(str(c["figure"]), str(c["scheme"]))
		await _case(c)
	_finish()


func _case(c: Dictionary) -> void:
	var nm := str(c["name"])
	var arena: Node = _app().call("push", load(ARENA_SCREEN))
	await _frames(20)
	var world: Node3D = arena.get("world")
	var player: Node3D = world.get("player")
	var fig: Node3D = player.call("figure")
	var want: Dictionary = Figures.scheme(str(c["scheme"]))
	if nm == "kit":
		_check(fig is KitFighter and str(fig.get("walk_kit")) == "infantry", "kit: the arena player is KitFighter on the chosen kit", str(fig))
		_check(fig != null and fig.call("scheme") == [want["primary"], want["secondary"]], "kit: …painted with the chosen scheme (H10)")
		_check(not bool(player.call("strafes")), "kit: it turns instead of strafing (H9)")
	else:
		_check(fig != null and fig.get("scheme_colors") == [want["primary"], want["secondary"]], "pack: the pack figure is dressed with the chosen scheme after setup")
	for level in LEVELS:
		_app().call("set_gfx", level)
		arena.call("refresh")
		await _view(world, ArenaLayout.RESPAWN, 0.0, -0.1, true)
		var m := await _measure()
		print("arena figure %-4s %-4s draw calls %4d  primitives %7d" % [nm, level, m.x, m.y])
		var t: Array = OVERVIEW[level]
		_check(m.x <= int(t[0]) and m.y <= int(t[1]), "%s %s: the arena overview, %d draw calls, %d primitives within %d / %d" % [nm, level, m.x, m.y, int(t[0]), int(t[1])])
		# a shot from the figure's muzzle
		var fx: Node = player.get("fx")
		fx.call("clear")
		var mp: Vector3 = player.call("_muzzle_point")
		var chest: Vector3 = player.global_position + ArenaPlayer.CHEST
		_check(mp.distance_to(chest) < 1.3 and mp.distance_to(chest) > 0.05, "%s %s: the muzzle is by the figure's hands (%.2f m from the chest)" % [nm, level, mp.distance_to(chest)])
		player.call("press", &"fire", true)
		await _physics(3)
		player.call("press", &"fire", false)
		_check(int(fx.call("alive")) > 0, "%s %s: firing draws a tracer" % [nm, level])
		await _physics(30)
		# A/D: the camera and the body turn together, no sideways motion
		var rig: Node3D = player.call("camera_rig")
		var y0 := float(rig.get("yaw"))
		var p0 := player.global_position
		_key(KEY_D, true)
		await _physics(30)
		_key(KEY_D, false)
		var turned := angle_difference(y0, float(rig.get("yaw")))
		_check(turned < -0.8, "%s %s: D turns the camera right (%.2f rad)" % [nm, level, turned])
		_check(absf(angle_difference(float(player.get("face")), float(rig.get("yaw")) + PI)) < 0.01, "%s %s: …the body with it" % [nm, level])
		_check(player.global_position.distance_to(p0) < 0.05, "%s %s: …without sliding sideways" % [nm, level], str(player.global_position - p0))
		await _physics(10)
		if level == "mid" or level == "min":
			# a close walk view; the body is turned toward the camera for the picture only (it faces the camera's way)
			await _view(world, ArenaLayout.RESPAWN + Vector3(0, 0, -3), 0.6, -0.2, false)
			rig.call("set_view", 0.6, -0.2, 2.6)
			await _frames(4)
			player.rotation.y = float(player.get("face")) + 2.6
			await _frames(4)
			_save("arena_fig_%s_%s.png" % [nm, level])
			player.rotation.y = float(player.get("face"))
		if level == "min" and nm == "kit":
			world.call("place_player", ArenaLayout.RESPAWN, PI, 0.0)
			await _physics(30)
			await _frames(50)
			var probs := _idle_problems(arena)
			_check(probs.is_empty(), "kit min: after idle frames nothing under the arena processes", ", ".join(probs))
			_check(bool(fig.call("is_still")) and not (fig.call("animation_player") as AnimationPlayer).is_playing(), "kit min: the kit holds a still pose")
	_app().call("set_gfx", "mid")
	_app().call("pop")
	await _frames(6)


func _view(world: Node3D, foot: Vector3, yaw: float, pitch: float, shoot: bool) -> void:
	var player: Node3D = world.get("player")
	world.call("place_player", foot, yaw + PI, yaw)
	player.call("set_mode", &"shoot" if shoot else &"walk")
	var rig: Node3D = player.call("camera_rig")
	rig.call("set_view", yaw, pitch, ArenaCamera.SHOULDER_ARM if shoot else 4.5)
	await _physics(6)
	await _frames(3)


func _measure() -> Vector2i:
	var idle := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await _frames(3)
	var draws := 0
	var prims := 0
	for i in 4:
		await process_frame
		draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	OS.low_processor_usage_mode = idle
	return Vector2i(draws, prims)


func _idle_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.can_process() and (n.is_processing() or n.is_physics_processing()):
			out.append(String(n.name) + " processes")
		if n is Timer and not (n as Timer).is_stopped():
			out.append(String(n.name) + " timer runs")
		stack.append_array(n.get_children())
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))


func _finish() -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_key(k, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var app := _app()
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	Figures.store_path = ""
	Figures.pack_list = Figures.PACK_LIST
	Figures.pack_manifest = ArenaActors.PACK_MANIFEST
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
