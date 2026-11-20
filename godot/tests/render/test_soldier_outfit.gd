extends SceneTree
## The soldier's field uniform (ใหม่ 0.15) in the real game, under xvfb (scenes/arena/soldier_figure.gd, opts "outfit").
## Checks, on the m2 body (it ships with the uniform; the base body and f2 follow when their builds are imported):
##  - each level, bare (training shorts) next to the uniform, same pose and camera: one draw call each; the trunk and
##    the knee are cloth (most pixels there change from the bare body) while the face and both hands stay skin (almost
##    no pixel there changes, and they are not background);
##  - a chest wound on the uniform (a cloth spot, as large as the spot allows up to 5.5 cm: the chest bone's spots are
##    small, 3.9 cm on m2) on hi and mid: one draw call before, three while wounded
##    (uniform, flesh, bone), red flesh in the wound and in the middle of the hole, no background through it, bone
##    through the flesh, and a close-up on hi with bone through flesh;
##  - the dressing room with m2 and the Outfit row on ชุดสนาม: the preview wears the uniform; ใช้ตัวนี้ saves it;
##  - the arena: the player (m2 chosen in the dressing room, uniform saved) wears the uniform.
## PNGs (TEST_OUT, default tests/out): soldier_outfit_lods.png (per level: bare | uniform), soldier_outfit_wound.png
## (hi and mid: before | after, and the hi close-up), soldier_outfit_dressing.png, soldier_outfit_arena.png. Run:
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_soldier_outfit.gd

const SCENE := "res://scenes/main.tscn"
const ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"
const DRESSING := "res://ui/screens/dressing_screen.tscn"
const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_soldier_outfit_render.cfg"
const FAKE_NET := "res://tests/unit/fixtures/fake_net.gd"
const NONE_LIST := "res://tests/unit/fixtures/no_such_pack/figures.json"
const NONE_PACK := "res://tests/unit/fixtures/no_such_pack/pack.json"
const BODY := "m2"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const CELL := Vector2i(360, 520)
const BG := Color(0.22, 0.24, 0.27)
const WOUND_R := 0.055
const MIN_FLESH := 300
const MIN_BONE := 15
const CORE_R := 0.7
const MIN_FLESH_CORE := 250
## a pixel "changes" when a channel moves more than CHANGE between bare and uniform, or its warmth (red - green)
## moves more than WARM (dark olive cloth on dark skin differs in hue more than in brightness)
const CHANGE := 0.1
const WARM := 0.04
## least room of the chest spot (the chest bone's spots on the uniform reach 3.9 cm on m2 and 4.0 cm on m3)
const SPOT_ROOM := 0.035

var _out_dir := DEFAULT_OUT_DIR
var _main: Node
var _started := false
var _done := false
var _passed := 0
var _failed := 0
var _fake: Node
var _real_net: Node
var S: GDScript


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	var app := _app()
	app.set("settings_file", SETTINGS_FILE)
	app.call("set_lang", "th")
	app.call("set_gfx", "hi")
	app.call("set_touch", "off")
	Figures.store_path = SETTINGS_FILE
	Figures.pack_list = NONE_LIST
	Figures.pack_manifest = NONE_PACK
	S = load(SCRIPT)
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
	var ok := bool(S.call("has_outfit", "uniform", S.call("folder", BODY)))
	_check(ok, "%s has the field uniform at every level" % BODY)
	if ok:
		await _lods()
		await _chest_wound()
		await _dressing()
		await _arena()
	_finish()


# ---- each level: bare | uniform ----

func _lods() -> void:
	var sheet := Image.create(CELL.x * 2, CELL.y * LEVELS.size(), false, Image.FORMAT_RGBA8)
	for i in LEVELS.size():
		var lv := LEVELS[i]
		var imgs: Array[Image] = []
		var draws: Array[int] = []
		var at := {}
		var px := {}
		for k in 2:
			var vp := _viewport()
			var fig: Node3D = S.new()
			vp.add_child(fig)
			fig.call("setup", {"role": &"player", "level": lv, "seed": 0, "manual": true, "body": BODY, "outfit": "uniform" if k == 1 else ""})
			fig.call("step", 0.0)
			var cam := Camera3D.new()
			cam.fov = 30.0
			vp.add_child(cam)
			cam.current = true
			var from := Vector3(0.0, 0.95, 4.2)
			cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.92, 0.0) - from, Vector3.UP), from)
			var sk: Skeleton3D = fig.call("skeleton")
			if k == 0:
				var head := _bone(sk, "head")
				var pts := {"face": [head + Vector3(0.0, 0.06, 0.09), 0.035], "hand_l": [_bone(sk, "handL"), 0.022],
					"hand_r": [_bone(sk, "handR"), 0.022], "trunk": [_bone(sk, "spine"), 0.07], "knee": [_bone(sk, "kneeL"), 0.035]}
				for key in pts:
					var p: Vector3 = pts[key][0]
					at[key] = cam.unproject_position(p)
					px[key] = float(pts[key][1]) / (cam.global_position.distance_to(p) * tan(deg_to_rad(cam.fov * 0.5))) * CELL.y * 0.5
			var m := await _measure_vp(vp)
			draws.append(int(m[0]))
			imgs.append(await _grab(vp))
			if k == 1:
				_check(str(fig.call("outfit_shown")) == "uniform", "%s: the uniform is worn" % lv)
			sheet.blit_rect(imgs[k], Rect2i(Vector2i.ZERO, CELL), Vector2i(k * CELL.x, i * CELL.y))
			vp.queue_free()
			await _frames(1)
		_check(draws[0] == 1 and draws[1] == 1, "%s: one draw call bare and in uniform" % lv, str(draws))
		var line := "outfit %-4s" % lv
		for key in ["trunk", "knee", "face", "hand_l", "hand_r"]:
			var d := _diff(imgs[0], imgs[1], at[key], px[key])
			line += "  %s %.0f%% (body %.0f%%)" % [key, d[0] * 100.0, d[1] * 100.0]
			if key == "trunk" or key == "knee":
				_check(d[0] >= 0.6, "%s: the %s is cloth in the uniform (%.0f%% of its pixels change)" % [lv, key, d[0] * 100.0])
			else:
				_check(d[0] <= (0.12 if key == "face" else 0.25) and d[1] >= 0.7,
					"%s: the %s stays skin (%.0f%% change, %.0f%% on the body)" % [lv, key, d[0] * 100.0, d[1] * 100.0])
		print(line)
	_save_img(sheet, "soldier_outfit_lods.png")


# ---- a chest wound on the uniform ----

func _chest_wound() -> void:
	var dir: String = S.call("folder", BODY)
	var spot := _cloth_spot(dir, Vector3(0.3, 0.1, 1.0), SPOT_ROOM)
	_check(spot.size() == 3, "a cloth spot on the front of the chest with room for %.1f cm" % (SPOT_ROOM * 100.0), str(spot))
	if spot.size() != 3:
		return
	var r := minf(WOUND_R, float(spot[2]))
	var offset: Vector3 = (spot[0] as Vector3) - (spot[1] as Vector3) * r * 0.3
	var sheet := Image.create(CELL.x * 3, CELL.y * 2, false, Image.FORMAT_RGBA8)
	for i in 2:
		var lv: String = ["hi", "mid"][i]
		var vp := _viewport()
		var fig: Node3D = S.new()
		vp.add_child(fig)
		fig.call("setup", {"role": &"player", "level": lv, "seed": 0, "manual": true, "body": BODY, "outfit": "uniform"})
		fig.call("step", 0.0)
		var sk: Skeleton3D = fig.call("skeleton")
		var centre := sk.global_transform * (sk.get_bone_global_pose(sk.find_bone("chest")) * offset)
		var cam := Camera3D.new()
		cam.fov = 30.0
		vp.add_child(cam)
		cam.current = true
		var from := centre + Vector3(0.25, 0.15, 1.6)
		cam.transform = Transform3D(Basis.looking_at(centre - from, Vector3.UP), from)
		var at := cam.unproject_position(centre)
		var rad := r / (cam.global_position.distance_to(centre) * tan(deg_to_rad(cam.fov * 0.5))) * CELL.y * 0.5
		var m0 := await _measure_vp(vp)
		var img0 := await _grab(vp)
		var c0 := _classify(img0, at, rad * 1.25)
		var added := bool(fig.call("add_wound", &"chest", offset, r))
		var m1 := await _measure_vp(vp)
		var img1 := await _grab(vp)
		var c1 := _classify(img1, at, rad * 1.25)
		var k1 := _classify(img1, at, rad * CORE_R)
		print("outfit wound %-4s draws %d -> %d  flesh %d -> %d  bone %d -> %d  core: flesh %d background %d  (r %.1f cm, %.0f px)"
			% [lv, m0[0], m1[0], c0[0], c1[0], c0[1], c1[1], k1[0], k1[2], r * 100.0, rad])
		sheet.blit_rect(img0, Rect2i(Vector2i.ZERO, CELL), Vector2i(0, i * CELL.y))
		sheet.blit_rect(img1, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x, i * CELL.y))
		_check(added and int(fig.call("wound_count")) == 1, "%s: the wound is placed on the uniform" % lv)
		_check(c0[0] == 0 and c0[1] == 0, "%s: no flesh or bone pixels on the uniform's chest before the wound" % lv, str(c0))
		_check(m0[0] == 1 and m1[0] == 3, "%s: one draw call, three while wounded (uniform, flesh, bone)" % lv, "%s -> %s" % [m0, m1])
		_check(c1[0] >= MIN_FLESH and k1[0] >= MIN_FLESH_CORE, "%s: the cloth opens on red flesh (%d px, %d px in the middle of the hole)"
			% [lv, c1[0], k1[0]])
		_check(k1[2] == 0, "%s: no background shows through the hole in the cloth (%d px)" % [lv, k1[2]])
		_check(c1[1] >= MIN_BONE, "%s: bone shows through the flesh (%d px)" % [lv, c1[1]])
		if lv == "hi":
			var p: Vector3 = fig.call("wound_point", 0)
			var close := p + Vector3(0.12, 0.06, 0.5)
			cam.transform = Transform3D(Basis.looking_at(p - close, Vector3.UP), close)
			var img := await _grab(vp)
			var cc := _classify(img, cam.unproject_position(p), CELL.x * 0.45)
			_check(cc[1] >= MIN_BONE * 8 and cc[0] >= MIN_FLESH * 8, "hi close-up: bone (%d px) through flesh (%d px)" % [cc[1], cc[0]])
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * 2, 0))
		vp.queue_free()
		await _frames(1)
	_save_img(sheet, "soldier_outfit_wound.png")


# ---- the dressing room and the arena (the player's look) ----

func _dressing() -> void:
	Figures.select("soldier_" + BODY, "original")
	Figures.select_outfit("")
	_app().call("set_gfx", "hi")
	var ds: Node = _app().call("push", load(DRESSING))
	await create_timer(1.0).timeout        # จอเปลี่ยนแบบจางบน hi: รอให้จางเสร็จก่อนถ่ายภาพ
	await _frames(4)
	var bs: Array = ds.call("outfit_buttons")
	_check(bs.size() == 2 and (bs[1] as Button).is_visible_in_tree() and (bs[0] as Button).button_pressed,
		"the dressing room shows the Outfit row with training shorts chosen")
	if bs.size() != 2:
		_app().call("pop")
		return
	(bs[1] as Button).pressed.emit()
	await _frames(8)
	var pf: Node3D = ds.call("preview_figure")
	_check(pf != null and str(pf.call("outfit_shown")) == "uniform" and str(ds.get("outfit_id")) == "uniform",
		"ชุดสนาม dresses the preview in the field uniform")
	ds.set("spinning", false)
	await create_timer(0.5).timeout
	await _frames(4)
	_check(_app().call("current") == ds, "the dressing screen is on top for its picture")
	await _save("soldier_outfit_dressing.png")
	ds.call("use_selection")
	await _frames(6)
	_check(Figures.outfit() == "uniform", "ใช้ตัวนี้ saves the field uniform", Figures.outfit())


func _arena() -> void:
	var arena: Node = _app().call("push", load(ARENA_SCREEN))
	await create_timer(1.0).timeout
	await _frames(20)
	var world: Node3D = arena.get("world")
	var player: Node3D = world.get("player")
	var fig: Node3D = player.call("figure")
	_check(fig != null and fig.get_script() == S and str(fig.get("body_id")) == BODY and str(fig.call("outfit_shown")) == "uniform",
		"the arena player is %s in the field uniform" % BODY, str(fig))
	world.call("place_player", ArenaLayout.RESPAWN + Vector3(0, 0, -3), PI + 0.6, 0.6)
	player.call("set_mode", &"walk")
	var rig: Node3D = player.call("camera_rig")
	rig.call("set_view", 0.6, -0.12, 2.6)
	await _physics(6)
	player.rotation.y = float(player.get("face")) + 2.6
	await create_timer(0.5).timeout
	await _frames(4)
	_check(_app().call("current") == arena, "the arena is on top for its picture")
	await _save("soldier_outfit_arena.png")
	_app().call("pop")
	await _frames(4)


# ---- helpers ----

func _bone(sk: Skeleton3D, name: String) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(name)).origin


## จุดลงแผลบนผ้า (ชนิด ≥ 1 ใน outfit_uniform_lo) ของอก ที่หันไปทาง want มากสุดและมีที่พอ (แบบ wound_spot)
func _cloth_spot(dir: String, want: Vector3, min_room: float) -> Array:
	var spots: Dictionary = S.call("wound_spots", dir, "uniform")
	var skin := load(dir + "skin.res") as Skin
	var bi := -1
	for i in skin.get_bind_count():
		if skin.get_bind_name(i) == &"chest":
			bi = i
	var bp := skin.get_bind_pose(bi)
	var a := (S.call("outfit_mesh", "uniform", "lo", dir) as ArrayMesh).surface_get_arrays(0)
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var cus: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0]
	var best := []
	var score := -INF
	for s: Array in spots.get(&"chest", []):
		if float(s[2]) < min_room:
			continue
		var d := (bp.basis.inverse() * (s[1] as Vector3)).dot(want.normalized())
		if d <= score:
			continue
		var p := bp.affine_inverse() * (s[0] as Vector3)
		for v in pos.size():
			if pos[v].distance_squared_to(p) < 1e-8:
				if cus[v * 4] > 0.5:
					score = d
					best = s
				break
	return best


## [share of pixels in the disc that change, share of disc pixels that are not background (in the bare image)]
func _diff(a: Image, b: Image, at: Vector2, rad: float) -> Array:
	var n := 0
	var ch := 0
	var body := 0
	for y in range(maxi(0, int(at.y - rad)), mini(a.get_height(), int(at.y + rad) + 1)):
		for x in range(maxi(0, int(at.x - rad)), mini(a.get_width(), int(at.x + rad) + 1)):
			if Vector2(x, y).distance_to(at) > rad:
				continue
			n += 1
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > CHANGE or absf(p.g - q.g) > CHANGE or absf(p.b - q.b) > CHANGE \
					or absf((p.r - p.g) - (q.r - q.g)) > WARM:
				ch += 1
			if not (absf(p.r - BG.r) < 0.02 and absf(p.g - BG.g) < 0.02 and absf(p.b - BG.b) < 0.02):
				body += 1
	return [float(ch) / maxf(n, 1.0), float(body) / maxf(n, 1.0)]


## [red-flesh, bone-white, background] pixels within rad of at (as tests/render/test_soldier_wounds.gd)
func _classify(img: Image, at: Vector2, rad: float) -> Array:
	var flesh := 0
	var bone := 0
	var bg := 0
	for y in range(maxi(0, int(at.y - rad)), mini(img.get_height(), int(at.y + rad) + 1)):
		for x in range(maxi(0, int(at.x - rad)), mini(img.get_width(), int(at.x + rad) + 1)):
			if Vector2(x, y).distance_to(at) > rad:
				continue
			var c := img.get_pixel(x, y)
			if (c.r >= 0.25 and c.g <= 0.45 * c.r and c.b <= 0.45 * c.r) or (c.r >= 0.07 and c.g <= 0.5 * c.r and c.b <= 0.5 * c.r):
				flesh += 1
			elif minf(c.r, minf(c.g, c.b)) >= 0.55 and c.b >= 0.75 * c.r and c.g >= 0.85 * c.r:
				bone += 1
			elif absf(c.r - BG.r) < 0.02 and absf(c.g - BG.g) < 0.02 and absf(c.b - BG.b) < 0.02:
				bg += 1
	return [flesh, bone, bg]


func _viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = CELL
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = BG
	vp.add_child(we)
	return vp


func _grab(vp: SubViewport) -> Image:
	await _frames(2)
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


func _measure_vp(vp: SubViewport) -> Array:
	await _frames(3)
	var rid := vp.get_viewport_rid()
	var d := 0
	var p := 0
	for _i in 4:
		await process_frame
		d = maxi(d, RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		p = maxi(p, RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
	return [d, p]


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame


func _app() -> Node:
	return root.get_node(^"App")


## ภาพทั้งจอ: ปิดโหมดประหยัด (low processor) สองสามเฟรมให้จอวาดใหม่ก่อน (แบบ _measure_main ของ test_soldier_wounds)
func _save(name: String) -> void:
	var idle := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await _frames(4)
	await RenderingServer.frame_post_draw
	_save_img(root.get_viewport().get_texture().get_image(), name)
	OS.low_processor_usage_mode = idle


func _save_img(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))


func _finish() -> void:
	var app := _app()
	app.call("set_touch", "auto")
	app.set("settings_file", str(app.get("SETTINGS_PATH")))
	Figures.store_path = ""
	Figures.pack_list = Figures.PACK_LIST
	Figures.pack_manifest = ArenaActors.PACK_MANIFEST
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	if _fake != null:
		_fake.name = "NetFake"
		_fake.queue_free()
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
