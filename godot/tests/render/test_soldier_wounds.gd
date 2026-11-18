extends SceneTree
## Wounds on the infantry soldier in the real game, under xvfb (scenes/arena/soldier_figure.gd). Checks:
##  - alone, per level, a chest wound (front of the chest, 7 cm): on hi and mid red flesh and bone-white pixels appear
##    around the projected wound centre (none there before), the soldier goes from 1 to 3 draw calls (skin, flesh, bone)
##    and back to 1 with the same picture once the wound is cleared; a close-up on hi shows bone through the flesh;
##    on lo one draw call and a red tint without bone; on min add_wound does nothing and the picture, draw calls and
##    primitives are unchanged;
##  - the arena: on hi a real hit (take_hit) leaves one wound and two draw calls more (only while wounded), death adds
##    two or three wounds and the revive after the down time clears them; on lo a hit adds no draw call; on min a hit
##    leaves no wound, no draw call and nothing processing once idle.
## PNGs (TEST_OUT, default tests/out): soldier_wound_alone.png (the four levels, before | after),
## soldier_wound_close_hi.png, soldier_wound_arena_<level>.png, soldier_wound_death_hi.png. Run:
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tests/render/test_soldier_wounds.gd

const SCENE := "res://scenes/main.tscn"
const ARENA_SCREEN := "res://ui/screens/arena_screen.tscn"
const SCRIPT := "res://scenes/arena/soldier_figure.gd"
const DEFAULT_OUT_DIR := "res://tests/out"
const SETTINGS_FILE := "user://test_soldier_wounds_render.cfg"
const FAKE_NET := "res://tests/unit/fixtures/fake_net.gd"
const NONE_LIST := "res://tests/unit/fixtures/no_such_pack/figures.json"
const NONE_PACK := "res://tests/unit/fixtures/no_such_pack/pack.json"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const CELL := Vector2i(360, 520)
const WOUND_R := 0.07
const CAM_FROM := Vector3(0.25, 1.45, 1.6)
## pixels around the projected wound centre: at least this many red-flesh / bone-white pixels on hi and mid
const MIN_FLESH := 300
const MIN_BONE := 15

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
	app.call("set_gfx", "mid")
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
	Figures.select("soldier", "original")
	await _alone()
	await _arena()
	_finish()


# ---- alone: one figure per level in its own viewport, a frozen pose (manual clock) ----

func _alone() -> void:
	var sheet := Image.create(CELL.x * 2, CELL.y * LEVELS.size(), false, Image.FORMAT_RGBA8)
	var spot: Array = S.call("wound_spot", &"chest", Vector3(0.3, 0.1, 1.0))
	_check(spot.size() == 2, "a wound spot on the front of the chest", str(spot))
	if spot.size() != 2:
		return
	var offset: Vector3 = (spot[0] as Vector3) - (spot[1] as Vector3) * WOUND_R * 0.3
	for i in LEVELS.size():
		var lv := LEVELS[i]
		var vp := _viewport()
		var fig: Node3D = S.new()
		vp.add_child(fig)
		fig.call("setup", {"role": &"player", "level": lv, "seed": 0, "manual": true})
		fig.call("step", 0.0)
		var cam := Camera3D.new()
		cam.fov = 30.0
		vp.add_child(cam)
		cam.current = true
		cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.3, 0) - CAM_FROM, Vector3.UP), CAM_FROM)
		var sk: Skeleton3D = fig.call("skeleton")
		var centre := sk.global_transform * (sk.get_bone_global_pose(sk.find_bone("chest")) * offset)
		var at := cam.unproject_position(centre)
		var rad := WOUND_R / (cam.global_position.distance_to(centre) * tan(deg_to_rad(cam.fov * 0.5))) * CELL.y * 0.5
		var m0 := await _measure_vp(vp)
		var img0 := await _grab(vp)
		var c0 := _classify(img0, at, rad * 1.25)
		var added := bool(fig.call("add_wound", &"chest", offset, WOUND_R))
		var m1 := await _measure_vp(vp)
		var img1 := await _grab(vp)
		var c1 := _classify(img1, at, rad * 1.25)
		print("wound alone %-4s draws %d -> %d  primitives %d -> %d  flesh %d -> %d  bone %d -> %d  (r %.0f px)"
			% [lv, m0[0], m1[0], m0[1], m1[1], c0[0], c1[0], c0[1], c1[1], rad])
		sheet.blit_rect(img0, Rect2i(Vector2i.ZERO, CELL), Vector2i(0, i * CELL.y))
		sheet.blit_rect(img1, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x, i * CELL.y))
		_check(m0[0] == 1, "%s: unwounded, the soldier is one draw call" % lv, str(m0))
		_check(c0[0] == 0 and c0[1] == 0, "%s: no flesh or bone pixels at the chest before the wound" % lv, str(c0))
		match lv:
			"hi", "mid":
				_check(added, "%s: add_wound takes the chest wound" % lv)
				_check(m1[0] == 3, "%s: wounded, three draw calls (skin, flesh, bone)" % lv, str(m1))
				_check(c1[0] >= MIN_FLESH, "%s: red flesh shows in the wound (%d px)" % [lv, c1[0]])
				_check(c1[1] >= MIN_BONE, "%s: bone shows through the flesh (%d px)" % [lv, c1[1]])
			"lo":
				_check(added, "lo: add_wound takes the wound")
				_check(m1[0] == 1, "lo: still one draw call (no inner layers)", str(m1))
				_check(c1[0] >= MIN_FLESH and c1[1] == 0, "lo: a red tint (%d px), no bone (%d px)" % [c1[0], c1[1]])
			"min":
				_check(not added, "min: add_wound does nothing")
				_check(m1 == m0, "min: draw calls and primitives unchanged", "%s -> %s" % [m0, m1])
				_check(_same(img0, img1) == 0, "min: the picture is unchanged (%d px differ)" % _same(img0, img1))
		if lv == "hi":
			var p: Vector3 = fig.call("wound_point", 0)
			var close := p + Vector3(0.12, 0.06, 0.5)
			cam.transform = Transform3D(Basis.looking_at(p - close, Vector3.UP), close)
			var img := await _grab(vp)
			var cc := _classify(img, cam.unproject_position(p), CELL.x * 0.45)
			_check(cc[1] >= MIN_BONE * 8 and cc[0] >= MIN_FLESH * 8, "hi close-up: bone (%d px) through flesh (%d px)" % [cc[1], cc[0]])
			_save_img(img, "soldier_wound_close_hi.png")
			cam.transform = Transform3D(Basis.looking_at(Vector3(0, 1.3, 0) - CAM_FROM, Vector3.UP), CAM_FROM)
		fig.call("clear_wounds")
		var m2 := await _measure_vp(vp)
		var img2 := await _grab(vp)
		_check(m2 == m0 and _same(img0, img2) == 0, "%s: cleared, the same draws and picture as before (%d px differ)"
			% [lv, _same(img0, img2)], "%s -> %s" % [m0, m2])
		vp.queue_free()
		await _frames(1)
	_save_img(sheet, "soldier_wound_alone.png")


# ---- the arena: real hits through the player ----

func _arena() -> void:
	var arena: Node = _app().call("push", load(ARENA_SCREEN))
	await _frames(20)
	var world: Node3D = arena.get("world")
	var player: Node3D = world.get("player")
	var fig: Node3D = player.call("figure")
	_check(fig != null and fig.get_script() == S, "the arena player is the soldier", str(fig))
	if fig == null:
		return
	for lv in ["hi", "lo", "min"]:
		_app().call("set_gfx", lv)
		arena.call("refresh")
		await _front(world, player)
		var m0 := await _measure_main()
		player.call("take_hit", {"amount": 10, "from": player.global_position + Vector3(0, 1, 2)})
		await _physics(30)
		var m1 := await _measure_main()
		print("wound arena %-4s draws %d -> %d  wounds %d" % [lv, m0, m1, int(fig.call("wound_count"))])
		if lv == "min":
			_check(int(fig.call("wound_count")) == 0, "min: a hit leaves no wound")
			_check(m1 == m0, "min: no draw call more (%d -> %d)" % [m0, m1])
			await _physics(30)
			await _frames(40)
			var probs := _idle_problems(arena)
			_check(probs.is_empty(), "min: after idle frames nothing under the arena processes", ", ".join(probs))
			_save("soldier_wound_arena_min.png")
			continue
		_check(int(fig.call("wound_count")) == 1, "%s: a real hit leaves one wound" % lv)
		# the picture: a hit wound on the chest too (the random one may be on the back or a limb)
		var spot: Array = S.call("wound_spot", &"chest", Vector3(0.25, 0.1, 1.0))
		fig.call("add_wound", &"chest", (spot[0] as Vector3) - (spot[1] as Vector3) * 0.012, 0.042)
		await _frames(4)
		if lv == "lo":
			_check(m1 == m0, "lo: a wound adds no draw call (tint only, %d -> %d)" % [m0, m1])
			_save("soldier_wound_arena_lo.png")
			fig.call("clear_wounds")
			continue
		_check(m1 == m0 + 2, "hi: wounded, two draw calls more (flesh, bone: %d -> %d)" % [m0, m1])
		_save("soldier_wound_arena_hi.png")
		player.call("take_hit", {"amount": 1000, "from": player.global_position + Vector3(0, 1, 2)})
		await _physics(80)
		var n := int(fig.call("wound_count"))
		_check(n >= 4 and n <= 5, "hi: death adds two or three wounds to the two (%d in all)" % n)
		# a camera above the body (the arena camera follows the player's feet)
		var sk: Skeleton3D = fig.call("skeleton")
		var pel := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("spine")).origin
		var old_cam := root.get_viewport().get_camera_3d()
		var cam := Camera3D.new()
		cam.fov = 40.0
		world.add_child(cam)
		cam.look_at_from_position(pel + Vector3(0.7, 1.9, 1.0), pel + Vector3(0.0, 0.25, 0.0))
		cam.current = true
		await _frames(6)
		_save("soldier_wound_death_hi.png")
		cam.queue_free()
		if old_cam != null:
			old_cam.current = true
		# the arena revives the same figure after the down time (play idle): the wounds go
		for i in 300:
			if int(fig.call("wound_count")) == 0:
				break
			await physics_frame
		await _front(world, player)
		var m2 := await _measure_main()
		_check(int(fig.call("wound_count")) == 0, "hi: the revive clears the wounds")
		_check(m2 == m0, "hi: unwounded again, the draw calls are back (%d)" % m2)
	_app().call("set_gfx", "mid")
	_app().call("pop")
	await _frames(6)


## camera in front of the player (walk mode), the soldier facing it
func _front(world: Node3D, player: Node3D) -> void:
	world.call("place_player", ArenaLayout.RESPAWN + Vector3(0, 0, -3), PI + 0.6, 0.6)
	player.call("set_mode", &"walk")
	var rig: Node3D = player.call("camera_rig")
	rig.call("set_view", 0.6, -0.12, 2.6)
	await _physics(6)
	player.rotation.y = float(player.get("face")) + 2.6
	await _frames(6)


# ---- helpers ----

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
	we.environment.background_color = Color(0.22, 0.24, 0.27)
	vp.add_child(we)
	return vp


func _grab(vp: SubViewport) -> Image:
	await _frames(2)
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


## [red-flesh, bone-white] pixels within rad of at (skin: g/r ~0.77 and b/r ~0.6 is neither)
func _classify(img: Image, at: Vector2, rad: float) -> Array:
	var flesh := 0
	var bone := 0
	for y in range(maxi(0, int(at.y - rad)), mini(img.get_height(), int(at.y + rad) + 1)):
		for x in range(maxi(0, int(at.x - rad)), mini(img.get_width(), int(at.x + rad) + 1)):
			if Vector2(x, y).distance_to(at) > rad:
				continue
			var c := img.get_pixel(x, y)
			if c.r >= 0.25 and c.g <= 0.45 * c.r and c.b <= 0.45 * c.r:
				flesh += 1
			elif minf(c.r, minf(c.g, c.b)) >= 0.55 and c.b >= 0.75 * c.r and c.g >= 0.85 * c.r:
				bone += 1
	return [flesh, bone]


## pixels that differ by more than 2/255 in any channel
func _same(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > 0.008 or absf(p.g - q.g) > 0.008 or absf(p.b - q.b) > 0.008:
				n += 1
	return n


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


## 3D draw calls of the main viewport (the arena), the most over four frames
func _measure_main() -> int:
	var idle := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await _frames(3)
	var rid := root.get_viewport_rid()
	var d := 0
	for i in 4:
		await process_frame
		d = maxi(d, RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	OS.low_processor_usage_mode = idle
	return d


func _idle_problems(screen: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var stack: Array[Node] = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.can_process() and (n.is_processing() or n.is_physics_processing()):
			out.append(String(n.name) + " processes")
		if n is AnimationPlayer and (n as AnimationPlayer).is_playing() and n.can_process():
			out.append(String(n.name) + " plays")
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


func _app() -> Node:
	return root.get_node(^"App")


func _save(name: String) -> void:
	_save_img(root.get_viewport().get_texture().get_image(), name)


func _save_img(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var path := _out_dir + "/" + name
	var err := img.save_png(path)
	_check(err == OK, "saved " + ProjectSettings.globalize_path(path) + " " + str(img.get_size()))


func _finish() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
