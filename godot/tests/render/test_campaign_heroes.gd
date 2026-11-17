extends SceneTree
## Campaign hero scenes under xvfb (CAMPAIGN_SPEC §3, §4, track B). Every built-in hero (normal, hard, veryhard,
## catastrophe) on hi / mid / lo / min in a 16:9 card (640×360) and a tall phone card (360×640), each in its own world
## the way HeroStage shows it (3D scale per level). Checks: draw calls and primitives of the live hero inside its viewport
## within §4 (hi 60 / 80k, mid 45 / 60k, lo 30 / 35k; min is a still, measured once and kept under the lo numbers);
## framing: the subject's head and feet project inside the frame in both aspects (the normal hero: head and chest, it is
## an upper-body close-up); the picture is not empty (the subject is brighter than the backdrop's corners); the normal
## hero shows the selected figure (the egg, a kit, the fixture pack figure); the catastrophe row has 7 figures, all
## visible in the poster; no processing once inactive. PNGs (TEST_OUT, default tests/out): hero_<id>_<level>_<w>x<h>.png
## and hero_normal_<figure>.png. Run:
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s tests/render/test_campaign_heroes.gd

const DEFAULT_OUT_DIR := "res://tests/out"
const IDS: PackedStringArray = ["normal", "hard", "veryhard", "catastrophe"]
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const SIZES: Array[Vector2i] = [Vector2i(640, 360), Vector2i(360, 640)]
## review fix: near-square cards (English stats wrapping on 19.5:9 / 20:9 phones) once put the Hard camera under the floor
const SQUARE_SIZES: Array[Vector2i] = [Vector2i(400, 400), Vector2i(440, 400), Vector2i(500, 400), Vector2i(536, 400)]
const BUDGET := {"hi": [60, 80000], "mid": [45, 60000], "lo": [30, 35000], "min": [30, 35000]}
const SCALE := {"hi": 1.0, "mid": 0.75, "lo": 0.5, "min": 0.5}
const FIG_LIST := "res://tests/fixtures/figure_pack/figures.json"

var _out_dir := DEFAULT_OUT_DIR
var _headless := false
var _passed := 0
var _failed := 0
var _done := false
var _started := false
var HEROES: Script
var KIT: Script


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	_headless = DisplayServer.get_name() == "headless"
	HEROES = load("res://scenes/campaign/hero_loader.gd")
	KIT = load("res://scenes/campaign/hero_kit.gd")
	HEROES.set("test_dirs", PackedStringArray(["res://tests/fixtures/none"]))


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _done


func _run() -> void:
	var egg := {"figure": "egg", "scheme": "original"}
	for id in IDS:
		for lv in LEVELS:
			for sz in SIZES:
				await _one(id, lv, sz, egg)
	for id in IDS:
		for sz in SQUARE_SIZES:
			await _one(id, "mid", sz, egg, "hero_%s_square_%dx%d.png" % [id, sz.x, sz.y])
	await _normal_figures()
	_finish()


func _one(id: String, lv: String, sz: Vector2i, sel: Dictionary, png := "") -> String:
	var vp := SubViewport.new()
	vp.size = sz
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(SCALE[lv])
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var h: Node3D = HEROES.call("make", id)
	vp.add_child(h)
	var aspect := float(sz.x) / sz.y
	h.call("setup", {"level": lv, "sel": sel, "aspect": aspect})
	var tag := "%s %s %dx%d" % [id, lv, sz.x, sz.y]
	var cam := vp.get_camera_3d()
	_check(cam != null and h.is_ancestor_of(cam), tag + ": the hero's own camera is current")
	_check(cam != null and cam.global_position.y >= 0.09, tag + ": the camera stays above the floor",
		str(cam.global_position) if cam != null else "")
	if lv != "min":
		h.call("set_active", true)
		# วัดตอนฉากเต็มที่สุด (ทุกตัวโผล่ ทางดาบ คลื่นกระแทก)
		h.call("seek", float(h.call("poster_t")))
	var m := await _measure(vp)
	var b: Array = BUDGET[lv]
	print("info  %s: %d draws, %d primitives" % [tag, m[0], m[1]])
	_check(_headless or (m[0] <= int(b[0]) and m[1] <= int(b[1])), "%s: within %d draws / %d primitives" % [tag, b[0], b[1]], str(m))
	if lv != "min":
		h.call("seek", float(h.call("poster_t")))
		await _frames(2)
	if cam != null:
		var bad := _framing(h, cam, sz)
		_check(bad.is_empty(), tag + ": the subject is inside the frame", ", ".join(bad))
	if not _headless:
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		_check(_has_subject(img), tag + ": the picture shows a lit subject over a dark backdrop")
		_save(img, png if png != "" else "hero_%s_%s_%dx%d.png" % [id, lv, sz.x, sz.y])
	if id == "catastrophe":
		var row: Array = h.get("row")
		_check(row.size() == 7 and row.all(func(n: Node3D) -> bool: return n.visible), tag + ": seven figures in the poster row")
	h.call("set_active", false)
	_check(not h.is_processing() and not h.is_physics_processing(), tag + ": inactive = no processing")
	var music: Variant = h.call("music") if h.has_method("music") else null
	_check(music == null or not (music as AudioStreamPlayer).playing, tag + ": no music once inactive")
	var fig: Node3D = h.get("figure") if id == "normal" else null
	var fig_path := str((fig.get_script() as Script).resource_path) if fig != null and fig.get_script() != null else ""
	vp.queue_free()
	await _frames(1)
	return fig_path


func _normal_figures() -> void:
	for sel: Dictionary in [{"figure": "egg", "scheme": "original"}, {"figure": "kit_kblade", "scheme": "blue"},
			{"figure": "kit_cxw", "scheme": "original"}, {"figure": "prim", "scheme": "pink"}]:
		var fid := str(sel["figure"])
		if fid.begins_with("kit_") and not KitLibrary.has_kit(fid.trim_prefix("kit_")):
			continue
		if fid == "prim":
			Figures.pack_list = FIG_LIST
		var fig := await _one("normal", "hi", Vector2i(640, 360), sel, "hero_normal_%s.png" % fid)
		var want := "egg_gunner.gd" if fid == "egg" else ("kit_fighter.gd" if fid.begins_with("kit_") else "prim_figure.gd")
		_check(fig.ends_with(want), "normal shows the selected figure: " + fid, fig)
		Figures.pack_list = Figures.PACK_LIST


## จุดของตัวหลักที่ต้องอยู่ในกรอบ (หัว + เท้า, ตัวธรรมดา: หัว + อก)
func _framing(h: Node3D, cam: Camera3D, sz: Vector2i) -> PackedStringArray:
	var out := PackedStringArray()
	var pts: Array = []
	match str((h.get_script() as Script).resource_path.get_file()):
		"hero_normal.gd":
			var head: float = h.get("head")
			var f: Node3D = h.get("figure")
			pts.append(["head", f.position + Vector3(0.0, head + 0.12, 0.0)])
			pts.append(["chest", f.position + Vector3(0.0, head - 0.35, 0.0)])
		"hero_hard.gd":
			for k: Node3D in h.get("knights"):
				pts.append_array(_head_feet(k, h))
		"hero_veryhard.gd":
			pts.append_array(_head_feet(h.get("knight"), h))
		"hero_catastrophe.gd":
			for k: Node3D in h.get("row"):
				pts.append_array(_head_feet(k, h))
	var r := Rect2(Vector2(-0.02, -0.02) * Vector2(sz), Vector2(sz) * 1.04)
	for p in pts:
		var w: Vector3 = h.global_transform * (p[1] as Vector3)
		if cam.is_position_behind(w) or not r.has_point(cam.unproject_position(w)):
			out.append("%s at %s" % [p[0], str(cam.unproject_position(w).round())])
	return out


func _head_feet(k: Node3D, h: Node3D) -> Array:
	var y: float = KIT.call("head_y", k, h) - k.position.y
	return [[str(k.name) + " head", k.position + Vector3(0.0, y + 0.12, 0.0)], [str(k.name) + " feet", k.position]]


## ภาพมีตัว: กลางภาพสว่างกว่ามุมบนซ้าย/ขวาอย่างเห็นได้ชัด
func _has_subject(img: Image) -> bool:
	if img == null or img.is_empty():
		return false
	var w := img.get_width()
	var hh := img.get_height()
	var corner := (img.get_pixel(2, 2).get_luminance() + img.get_pixel(w - 3, 2).get_luminance()) * 0.5
	var best := 0.0
	for y in range(int(hh * 0.2), int(hh * 0.8), 4):
		for x in range(int(w * 0.25), int(w * 0.75), 4):
			best = maxf(best, img.get_pixel(x, y).get_luminance())
	return best > corner + 0.15


func _measure(vp: SubViewport) -> Array:
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


func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var err := img.save_png(_out_dir + "/" + name)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(_out_dir + "/" + name))


func _finish() -> void:
	HEROES.set("test_dirs", PackedStringArray())
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
