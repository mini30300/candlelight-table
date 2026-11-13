extends SceneTree
## Budget gate of ARCHITECTURE §6: builds the look scene (400 figures / 8 teams) from scenes/battle_table.tscn,
## applies every graphics level and prints draw calls, primitives and frame time from
## RenderingServer.get_rendering_info; asserts the draw-call and triangle budgets per level. Two fields from
## core/field: the default setup the app opens with (seed 1, 48" ruin, hills, buildings x1 -> tests/out/budgets_<level>.png)
## and the densest one, where FieldProps stops at PROP_CAP = 480 props (180" ruin, dense forest, buildings x2.5 ->
## budgets_dense_<level>.png); the drawn prop count must equal FieldProps.items.size() in both. These two phases draw the
## kits: the figure style is pinned with App.set_fig("kit") (the app's default became the egg placeholders, LOBBY_SPEC §4.1).
## A third phase (LOBBY_SPEC §7.4) switches the same default 400-figure / 8-team scene to eggs: the same budgets, no
## skinned figure, at most 7 egg MultiMeshes, 400 rings, and on min at least 30 % fewer draw calls than the kit phase
## (budgets_egg_<level>.png).
## Needs a display and a GPU or Mesa (llvmpipe), like tests/render_probe.gd:
##   timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_budgets.gd
## Run `<godot> --headless --path godot --import` first; the kits must exist (node godot/tools/export_kits.js).
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/battle_table.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
## [draw calls, primitives] per level (ARCHITECTURE §6)
const BUDGET := {"hi": [600, 1500000], "mid": [350, 800000], "lo": [200, 400000], "min": [120, 250000]}
const SKINNED_CAP := {"hi": 160, "mid": 80, "lo": 24, "min": 8}
const SETTLE := 3      # frames before measuring a level
const MEASURE := 4     # frames measured per level
## the field with the most props the rules allow: FieldProps reaches PROP_CAP here
const DENSE_SETUP := {"seed": 1, "w": 180, "theme": "ruin", "terrain": "forest", "buildings": true, "density": 2500}
const PHASES: PackedStringArray = ["default", "dense", "egg"]
## egg phase on min: draw calls at most this share of the kit phase on min
const EGG_MIN_SHARE := 0.7

var _out_dir := DEFAULT_OUT_DIR
var _table: Node3D
var _phase := 0
var _level := -1
var _frame := 0
var _draws := 0
var _prims := 0
var _usec_sum := 0
var _usec_n := 0
var _last_usec := 0
var _passed := 0
var _failed := 0
var _kit_draws := {}     # level → draw calls of the default (kit) phase


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("FAIL  cannot load " + SCENE)
		quit(1)
		return
	var app := root.get_node_or_null(^"App")
	if app != null:
		app.call("set_fig", "kit")   # the kit phases draw the kits (not saved: no settings file is written)
	_table = scene.instantiate()
	root.add_child(_table)
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


func _process(_delta: float) -> bool:
	if _level < 0:
		# first frame: the table's _ready() has run (the look scene is built); check it, then start the levels
		_table.call("set_measuring", true)
		_check_scene()
		_start_level(0)
		return false
	var now := Time.get_ticks_usec()
	_frame += 1
	if _frame > SETTLE:
		_draws = maxi(_draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		_prims = maxi(_prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		if _last_usec > 0:
			_usec_sum += now - _last_usec
			_usec_n += 1
	_last_usec = now
	if _frame < SETTLE + MEASURE + 1:
		return false
	_finish_level()
	if _level + 1 < LEVELS.size():
		_start_level(_level + 1)
		return false
	if _phase + 1 < PHASES.size():
		_phase += 1
		if PHASES[_phase] == "egg":
			# the default field of the table script (read at run time: TableView itself is not compiled into a -s script)
			_table.call("rebuild", (_table.get_script() as Script).get_script_constant_map()["DEFAULT_SETUP"])
			_table.call("set_figure_style", "egg")
		else:
			_table.call("rebuild", DENSE_SETUP)
		_check_scene()
		_start_level(0)
		return false
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	quit(0 if _failed == 0 else 1)
	return true


## the scene of the current phase: 400 figures with rings, 8 teams, and every prop of the rules field drawn
func _check_scene() -> void:
	var c: Dictionary = _table.call("counts")
	var tag := PHASES[_phase]
	print("scene %s %s: %s" % [tag, str(_table.call("setup")), str(c)])
	_check(int(c["figures"]) == 400, "%s: 400 figures in the look scene (%d)" % [tag, int(c["figures"])])
	_check(int(c["rings"]) == 400, "%s: a team ring under every figure (%d rings)" % [tag, int(c["rings"])])
	_check(int(c["props"]) == int(c["field_props"]) and int(c["props"]) > 0,
		"%s: every prop of the rules field is drawn (%d of %d)" % [tag, int(c["props"]), int(c["field_props"])])
	if tag == "dense":
		_check(int(c["props"]) == FieldProps.PROP_CAP, "dense: the props stop at PROP_CAP %d (%d)" % [FieldProps.PROP_CAP, int(c["props"])])
	_check(int(c["teams"]) == 8, "%s: 8 teams" % tag)
	if tag == "egg":
		_check(str(c.get("style", "")) == "egg", "egg: the figures are eggs (style %s)" % str(c.get("style", "")))
		_check(int(c["kits"]) >= 1 and int(c["kits"]) <= 7, "egg: at most 7 egg MultiMeshes, one per size class (%d)" % int(c["kits"]))
	else:
		_check(str(c.get("style", "")) == "kit", "%s: the figures are kits (style %s)" % [tag, str(c.get("style", ""))])
		_check(int(c["kits"]) >= 8, "%s: at least 8 kit MultiMeshes (%d)" % [tag, int(c["kits"])])


func _start_level(i: int) -> void:
	_level = i
	_table.call("apply_level", LEVELS[i])
	_frame = 0
	_draws = 0
	_prims = 0
	_usec_sum = 0
	_usec_n = 0
	_last_usec = 0


func _finish_level() -> void:
	var level := LEVELS[_level]
	var tag := PHASES[_phase]
	var ms := (_usec_sum / maxi(_usec_n, 1)) / 1000.0
	var c: Dictionary = _table.call("counts")
	print("%-7s level %-4s draw calls %5d  primitives %8d  frame %7.1f ms  (skinned %d, rigid %d, kits %d, mesh tris %d, props %d in %d kinds, %d prop tris, %d terrain tris)" % [
		tag, level, _draws, _prims, ms, int(c["skinned"]), int(c["rigid"]), int(c["kits"]), int(c["tris"]), int(c["props"]),
		int(c["prop_kinds"]), int(c["props_tris"]), int(c["terrain_tris"])])
	var label := level if tag == "default" else tag + " " + level
	var b: Array = BUDGET[level]
	_check(_draws > 0 and _prims > 0, "%s: counters are live" % label)
	_check(_draws <= int(b[0]), "%s: draw calls %d <= %d" % [label, _draws, int(b[0])])
	_check(_prims <= int(b[1]), "%s: primitives %d <= %d" % [label, _prims, int(b[1])])
	_check(int(c["skinned"]) <= int(SKINNED_CAP[level]), "%s: skinned figures %d <= cap %d" % [label, int(c["skinned"]), int(SKINNED_CAP[level])])
	_check(int(c["figures"]) == 400, "%s: still 400 figures" % label)
	if tag == "default":
		_kit_draws[level] = _draws
	elif tag == "egg":
		_check(int(c["skinned"]) == 0, "%s: no skinned figure (%d)" % [label, int(c["skinned"])])
		_check(int(c["rings"]) == 400, "%s: still 400 rings" % label)
		if level == "min" and _kit_draws.has(level):
			var lim := int(float(_kit_draws[level]) * EGG_MIN_SHARE)
			_check(_draws <= lim, "%s: draw calls %d <= 70 %% of the kit phase (%d of %d)" % [label, _draws, lim, int(_kit_draws[level])])
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/budgets_" + label.replace(" ", "_") + ".png"
	var err := img.save_png(path)
	_check(err == OK, "%s: saved %s" % [label, ProjectSettings.globalize_path(path)])
	_check(_mean_luma(img) > 0.04, "%s: image is not black" % label)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg)


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
