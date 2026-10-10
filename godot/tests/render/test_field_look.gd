extends SceneTree
## R1-V1 field look: the battle table drawn from the rules core (core/field). Builds scenes/battle_table.tscn in a
## 640x360 SubViewport for every theme x terrain (4 x 4, seed 1, 48" table, buildings on, density x1) and saves
## tests/out/field_<theme>_<terrain>.png, then one low view per theme at mid level for the sky and its skyline
## (field_sky_<theme>.png). Asserts per field:
##   - the drawn prop count equals FieldProps.items.size(), one MultiMesh per kind with that kind's count;
##   - terrain mesh vertex heights equal the (levelled) field heights at the grid points, and height_at() agrees with
##     FieldTerrain.height_at between them;
##   - every prop stands at its rules position on the levelled ground, turned by rot, scaled by s; buildings are
##     exactly FieldProps.bld_size; every kind's mesh fills its rules footprint (foot_of / rad_of / bld_size);
##   - figures are placed off the drawn props;
## and once: the default setup draws exactly the field core/field makes (digests), the sky per level (min flat colour,
## lo gradient, mid/hi with the skyline), and the coarse min mesh still sits on the field heights.
## Run like the other render suites (Mesa llvmpipe under xvfb):
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_field_look.gd
## TEST_OUT (an absolute folder) in the environment replaces tests/out. Exit code 1 on any failure.

const SCENE := "res://scenes/battle_table.tscn"
const DEFAULT_OUT_DIR := "res://tests/out"
const THEMES: PackedStringArray = ["ruin", "forest", "desert", "ice"]
const TERRAINS: PackedStringArray = ["flat", "hills", "mountain", "forest"]
const SIZE := Vector2i(640, 360)
const SETTLE := 3
## mesh extent / footprint must lie in this band (the drawn piece fills what blocks, and no more)
const FILL_MIN := 0.8
const FILL_MAX := 1.06

var _out_dir := DEFAULT_OUT_DIR
var _vp: SubViewport
var _table: Node3D
var _cases: Array = []
var _case := -1
var _frame := 0
var _passed := 0
var _failed := 0
var _checked_kinds := {}


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	for th in THEMES:
		for terr in TERRAINS:
			_cases.append({"theme": th, "terrain": terr, "sky": false})
	for th in THEMES:
		_cases.append({"theme": th, "terrain": "hills", "sky": true})
	_cases.append({"theme": "ruin", "terrain": "hills", "sky": false, "level": "min"})
	var scene: PackedScene = load(SCENE)
	if scene == null:
		print("FAIL  cannot load " + SCENE)
		quit(1)
		return
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_table = scene.instantiate()
	if not _table.has_method("rebuild"):
		print("FAIL  the battle table script did not load (see the errors above)")
		quit(1)
		return
	_table.set("auto_build", false)
	_table.set("figure_count", 24)     # a few figures for scale; the field is what this suite looks at
	_vp.add_child(_table)
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


func _process(_delta: float) -> bool:
	if _case < 0:
		_table.call("set_measuring", true)
		_table.call("apply_level", "mid")
		_start(0)
		return false
	_frame += 1
	if _frame < SETTLE:
		return false
	_finish()
	if _case + 1 < _cases.size():
		_start(_case + 1)
		return false
	_check_default_setup()
	_check_levels()
	print("%s  %d passed, %d failed" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	quit(0 if _failed == 0 else 1)
	return true


func _start(i: int) -> void:
	_case = i
	_frame = 0
	var c: Dictionary = _cases[i]
	_table.call("rebuild", {"seed": 1, "w": 48, "theme": c["theme"], "terrain": c["terrain"], "buildings": true, "density": 1000})
	if c.has("level"):
		_table.call("apply_level", c["level"])
	if not c["sky"]:
		_table.get("camera_rig").set("yaw", -0.35)   # the rig's default view for every field shot
		_table.get("camera_rig").call("_apply")
	else:
		# low view towards the sun of the theme: the sky gradient, the glow and the skyline above the far rail
		var sun: Array = TableSky.load_all()[c["theme"]]["sun"]
		var rig: Node = _table.get("camera_rig")
		rig.set("yaw", float(sun[0]) - PI + 0.35)
		rig.set("pitch", -0.36)
		rig.set("distance", 46.0)
		rig.call("_apply")


func _finish() -> void:
	var c: Dictionary = _cases[_case]
	var tag := "%s/%s" % [c["theme"], c["terrain"]]
	if c.has("level"):
		_check_min()
	elif not c["sky"]:
		_check_field(tag)
		_save("field_%s_%s.png" % [c["theme"], c["terrain"]])
	else:
		var sky: TableSky = _table.get("table_sky")
		_check(sky.skyline_on and sky.material() != null and bool(sky.material().get_shader_parameter("skyline_on")),
			"%s mid: the sky has its skyline" % c["theme"])
		var env: Environment = (_table.get("world_env") as WorldEnvironment).environment
		_check(env.background_mode == Environment.BG_SKY, "%s mid: the sky is the background" % c["theme"])
		var img := _save("field_sky_%s.png" % c["theme"])
		if img != null:
			# the top rows show the sky gradient, the bottom rows the ground/table: they must differ
			var top := _mean_colour(img, 0, 30)
			_check(top.distance_to(_vec(sky.colour("plain"))) > 0.04,
				"%s: the top of the low view is sky, not the plain (%s)" % [c["theme"], str(top)])


## Every check of one field against the rules objects the table was built from.
func _check_field(tag: String) -> void:
	var field: FieldTerrain = _table.get("field")
	var fp: FieldProps = _table.get("field_props")
	var props: PropsLayer = _table.get("props")
	var terrain: TerrainMesh = _table.get("terrain")
	_check(field != null and fp != null and fp.field == field, tag + ": the table keeps the rules field and its props")
	# 1. props: drawn count == rules count, one MultiMesh per kind
	var want := {}
	for o in fp.items:
		want[str(o["kind"])] = int(want.get(str(o["kind"]), 0)) + 1
	var drawn := 0
	var per_kind_ok := true
	for k in want:
		var mm := props.multimesh_of(k)
		if mm == null or mm.instance_count != int(want[k]):
			per_kind_ok = false
			continue
		drawn += mm.instance_count
	_check(props.count() == fp.items.size() and drawn == fp.items.size(),
		"%s: drawn props %d (MultiMesh instances %d) == FieldProps.items %d" % [tag, props.count(), drawn, fp.items.size()])
	_check(per_kind_ok and props.draw_calls() == want.size(), "%s: one MultiMesh per kind (%d kinds: %s)" % [tag, want.size(), str(want)])
	# 2. terrain: vertex heights == field heights at the grid points
	_check_heights(tag, terrain, field, 1)
	var worst := 0.0
	for k in 200:
		var x := (TerrainMesh.hash01(k, 1, 77) - 0.5) * field.w_in
		var z := (TerrainMesh.hash01(k, 2, 77) - 0.5) * field.d_in
		worst = maxf(worst, absf(terrain.height_at(x, z) - field.height_at(roundi(x * 1000.0), roundi(z * 1000.0)) / 1000.0))
	_check(worst < 0.002, "%s: height_at matches FieldTerrain.height_at at 200 points (worst %.4f m)" % [tag, worst])
	# 3. every prop at its rules spot on the levelled ground, turned and scaled as the rules say
	var bad := PackedStringArray()
	var idx := {}
	for o in fp.items:
		var k := str(o["kind"])
		var i: int = idx.get(k, 0)
		idx[k] = i + 1
		var t: Transform3D = props.multimesh_of(k).get_instance_transform(i)
		var x := float(o["x"]) / 1000.0
		var z := float(o["z"]) / 1000.0
		var rot := float(o["rot"]) / 65536.0
		var ground := float(field.height_at(o["x"], o["z"])) / 1000.0
		if absf(t.origin.x - x) > 0.0005 or absf(t.origin.z - z) > 0.0005 or absf(t.origin.y - ground) > 0.002:
			bad.append("%s at %s, rules (%.3f, %.3f, %.3f)" % [k, str(t.origin), x, ground, z])
		var ax := t.basis.x.normalized()
		if ax.distance_to(Vector3(cos(rot), 0.0, -sin(rot))) > 0.001:
			bad.append("%s turned %s, rules rot %.4f" % [k, str(ax), rot])
		if k == "building":
			var b := fp.bld_size(o)
			if absf(t.basis.x.length() - b[0] / 1000.0) > 0.001 or absf(t.basis.z.length() - b[1] / 1000.0) > 0.001:
				bad.append("building %.3f x %.3f, bld_size %d x %d" % [t.basis.x.length(), t.basis.z.length(), b[0], b[1]])
		elif absf(t.basis.x.length() - float(o["s"]) / 1000.0) > 0.001:
			bad.append("%s scale %.3f, s %d" % [k, t.basis.x.length(), int(o["s"])])
		if k != "crater" and not props.blocked_at(x, z, 0.05):
			bad.append("%s centre is not blocked" % k)
	_check(bad.is_empty(), "%s: every prop at its rules x/z on the levelled ground, rot and s as the rules (%d props)" % [tag, fp.items.size()], str(bad))
	# 4. each kind's mesh fills its rules footprint (once per kind and detail)
	for k in want:
		for simple in [false, true]:
			var key := "%s|%s" % [k, str(simple)]
			if not _checked_kinds.has(key):
				_checked_kinds[key] = true
				_check_footprint(k, simple)
	# 5. figures stand off the drawn props
	var figures: Node = _table.get("figures")
	var inside := 0
	for f in figures.get("figures"):
		var p: Vector3 = f.get("pos")
		if props.blocked_at(p.x, p.z, 0.0):
			inside += 1
	_check(inside == 0, "%s: no figure stands inside a prop (%d)" % [tag, inside])


## Mesh vertices on the grid points of the rules field carry exactly the field height (every step-th point).
func _check_heights(tag: String, terrain: TerrainMesh, field: FieldTerrain, step: int) -> void:
	var arr := terrain.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var at := {}
	for v in verts:
		var key := Vector2i(roundi(v.x * 1000.0), roundi(v.z * 1000.0))
		var list: Array = at.get(key, [])
		list.append(v.y)
		at[key] = list
	var checked := 0
	var missing := 0
	var wrong := PackedStringArray()
	for j in range(0, field.hd + 1, step):
		for i in range(0, field.hw + 1, step):
			var x := -field.w_in * 500 + i * field.cell_mi
			var z := -field.d_in * 500 + j * field.cell_mi
			if absi(x) > field.w_in * 500 or absi(z) > field.d_in * 500:
				continue
			var list: Variant = at.get(Vector2i(x, z))
			if list == null:
				missing += 1
				continue
			var want := float(field.hg[j * (field.hw + 1) + i]) / 1000.0
			var edge := i == 0 or j == 0 or absi(x) == field.w_in * 500 or absi(z) == field.d_in * 500
			var lo := 1e9
			var hi := -1e9
			for y in list:
				lo = minf(lo, y)
				hi = maxf(hi, y)
			# inner points: every vertex there is ground; edge points also carry the rail's inner face above the ground
			if absf(lo - want) > 0.0001 or (not edge and absf(hi - want) > 0.0001):
				wrong.append("(%d,%d) mesh %.4f..%.4f field %.4f" % [i, j, lo, hi, want])
			checked += 1
	_check(checked > 0 and missing == 0 and wrong.is_empty(),
		"%s: terrain vertices at %d grid points (step %d) carry the field heights (%d missing)" % [tag, checked, step, missing], str(wrong))


## The mesh of a kind reaches its unit footprint (s = 1): rectangles along both local axes, circles radially.
func _check_footprint(kind: String, simple: bool) -> void:
	var f := PropsLayer.unit_footprint(kind)
	var mesh := PropsLayer.kind_mesh(kind, simple)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var ex := 0.0
	var ez := 0.0
	var er := 0.0
	for v in verts:
		ex = maxf(ex, absf(v.x))
		ez = maxf(ez, absf(v.z))
		er = maxf(er, Vector2(v.x, v.z).length())
	var tag := "%s%s" % [kind, " (simple)" if simple else ""]
	if f.z > 0.0 and f.x == 0.0:
		_check(er >= f.z * FILL_MIN and er <= (f.z) * FILL_MAX, "%s: mesh radius %.2f fills the rules radius %.2f" % [tag, er, f.z])
	else:
		_check(ex >= f.x * FILL_MIN and ex <= (f.x + f.z) * FILL_MAX and ez >= f.y * FILL_MIN and ez <= (f.y + f.z) * FILL_MAX,
			"%s: mesh %.2f x %.2f fills the rules rectangle %.2f x %.2f" % [tag, ex, ez, f.x, f.y])


## The default setup draws exactly what core/field makes for it (same heights after levelling, same props).
func _check_default_setup() -> void:
	# the table's constants through its script: naming the TableView class here would compile table_view.gd before
	# the autoloads it uses (Log) exist as identifiers
	var d: Dictionary = _table.get_script().get_script_constant_map()["DEFAULT_SETUP"]
	_table.call("rebuild", d)
	var f := FieldTerrain.make(d["w"], FieldTerrain.depth_for(d["w"]), d["theme"], d["terrain"], d["seed"])
	var p := FieldProps.generate(f, d["buildings"], d["density"])
	var field: FieldTerrain = _table.get("field")
	var fp: FieldProps = _table.get("field_props")
	_check(field.digest() == f.digest(), "default setup: the table's levelled field is core/field's (%s)" % f.digest())
	_check(fp.digest() == p.digest(), "default setup: the table's props are core/field's (%d props, %s)" % [p.items.size(), p.digest()])
	_check(_table.call("setup") == d, "default setup: setup() reports DEFAULT_SETUP")
	_check(field.w_in == 48 and field.d_in == 34 and field.theme == "ruin" and field.terrain == "hills" and field.seed_value == 1,
		"default setup: seed 1, 48 x 34 in, ruin, hills")


## The min level (rendered as the last case): a flat background colour, the coarse grid still on the field heights,
## the simplified props, the same prop count.
func _check_min() -> void:
	var env: Environment = (_table.get("world_env") as WorldEnvironment).environment
	var sky: TableSky = _table.get("table_sky")
	var terrain: TerrainMesh = _table.get("terrain")
	var props: PropsLayer = _table.get("props")
	var fp: FieldProps = _table.get("field_props")
	_check(env.background_mode == Environment.BG_COLOR and env.sky == null and not sky.skyline_on, "min: a flat background colour, no sky pass")
	_check(terrain.grid_step == 2, "min: terrain grid step 2")
	_check_heights("min", terrain, _table.get("field"), 2)
	_check(props.simplified and props.count() == fp.items.size(), "min: simplified props, still all %d drawn" % fp.items.size())
	_save("field_ruin_hills_min.png")


## Sky per graphics level: lo a gradient without the skyline, mid/hi with it.
func _check_levels() -> void:
	var env: Environment = (_table.get("world_env") as WorldEnvironment).environment
	var sky: TableSky = _table.get("table_sky")
	_table.call("apply_level", "lo")
	_check(env.background_mode == Environment.BG_SKY and not sky.skyline_on and not bool(sky.material().get_shader_parameter("skyline_on")),
		"lo: gradient sky without the skyline")
	_table.call("apply_level", "hi")
	_check(env.background_mode == Environment.BG_SKY and sky.skyline_on, "hi: sky with the skyline")
	var h := sky.skyline_heights()
	var hmax := 0.0
	for v in h:
		hmax = maxf(hmax, maxf(v.x, v.y))
	_check(h.size() == TableSky.PANO_N and hmax > 0.0 and hmax < TableSky.PANO_MAX, "skyline heights %d around, highest %.3f rad" % [h.size(), hmax])
	_table.call("apply_level", "mid")


func _save(file: String) -> Image:
	var img := _vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + file
	var err := img.save_png(path)
	_check(err == OK and img.get_size() == SIZE, "saved %s %s" % [ProjectSettings.globalize_path(path), str(img.get_size())])
	_check(_mean_luma(img) > 0.04, file + " is not black")
	return img if err == OK else null


func _check(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == "" else " " + detail.left(1500)))


static func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


static func _mean_colour(img: Image, y0: int, y1: int) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for y in range(y0, mini(y1, img.get_height()), 3):
		for x in range(0, img.get_width(), 7):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			n += 1
	return sum / maxi(n, 1)


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
