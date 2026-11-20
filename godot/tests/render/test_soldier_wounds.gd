extends SceneTree
## Wounds on the infantry soldier in the real game, under xvfb (scenes/arena/soldier_figure.gd). Checks:
##  - alone, per level, a chest wound (front of the chest, 5.5 cm): on hi and mid red flesh fills the middle of the hole
##    (within 0.7 r, where the skin and its dark-red rim cannot be) and not one pixel of the background shows through it,
##    bone-white pixels appear around the centre (none there before), the soldier goes from 1 to 3 draw calls (skin,
##    flesh, bone) and back to 1 with the same picture once the wound is cleared; a close-up on hi shows bone through
##    the flesh; on lo one draw call and a red tint without bone; on min add_wound does nothing and the picture, draw
##    calls and primitives are unchanged;
##  - a woman's body (f1, assets/figures/soldier_f1/): a chest wound from its own wound spots shows its own inner layers
##    on hi and mid, red flesh in the middle of the hole, bone through it and no background, three draw calls; a
##    close-up on hi shows bone through the flesh;
##  - poses (run, punch, fire, heavy flinch, the three deaths): with four wounds, not one pixel changes farther than
##    1.85 r from every wound (the inner layers never show through unwounded skin), and the wounds do show;
##  - body parts: a flank wound (8.5 cm) and a chest-side wound by the armpit (as large as its spot allows) in six phases
##    of the run seen from the side: the arm swinging in front of them is not cut (not one arm pixel changes; the arm is
##    found with a body-part shader on the same mesh);
##  - the arena: on hi and mid a real hit (take_hit) leaves one wound and two draw calls more (only while wounded) and the
##    wounded overview stays within ARENA_SPEC §11.2; on hi death adds two or three wounds and the revive after the
##    down time clears them; on lo a hit adds no draw call; on min a hit leaves no wound, no draw call and nothing
##    processing once idle; with f1 chosen in the dressing room a real hit on hi leaves one wound and two draw calls
##    more, a close-up shows bone through flesh, and death adds two or three wounds.
## PNGs (TEST_OUT, default tests/out): soldier_wound_alone.png (the four levels, before | after),
## soldier_wound_close_hi.png, soldier_wound_f1_chest.png (hi and mid, before | after, and the hi close-up), soldier_wound_poses.png (before | after per pose), soldier_wound_run_strip.png (before,
## arm mask, after per phase), soldier_wound_arena_<level>.png, soldier_wound_death_hi.png, soldier_wound_f1_arena_hi.png,
## soldier_wound_f1_close_hi.png, soldier_wound_f1_death_hi.png. Run:
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
const WOUND_R := 0.055
const CAM_FROM := Vector3(0.25, 1.45, 1.6)
const BG := Color(0.22, 0.24, 0.27)
## pixels around the projected wound centre: at least this many red-flesh / bone-white pixels on hi and mid
const MIN_FLESH := 300
const MIN_BONE := 15
## the middle of the hole (0.7 r: the ragged skin edge is at least 0.83 r from the centre, 0.3 r under the skin, seen
## up to ~25° off): at least this many flesh pixels, and no background
const CORE_R := 0.7
const MIN_FLESH_CORE := 250
## poses: no changed pixel farther than this many radii from every wound
const OUTSIDE_R := 1.85
const POSES := [["run", &"run", 0, 0.3], ["punch", &"punch", 0, 0.5], ["fire", &"fire", 0, 0.1],
	["flinch_heavy", &"hit_heavy", 0, 0.4], ["die_back", &"die", 0, 1.0], ["die_fwd", &"die", 1, 1.0], ["die_spin", &"die", 2, 1.0]]
const PART_SHADER := "shader_type spatial;\nrender_mode unshaded, cull_back;\nvarying flat float v_part;\n" \
	+ "void vertex() { v_part = CUSTOM0.w; }\n" \
	+ "void fragment() { ALBEDO = (v_part > 1.5 && v_part < 3.5) ? vec3(1.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0); }\n"
## the arena overview with the soldier wounded stays within ARENA_SPEC §11.2 (as tests/render/test_soldier.gd unwounded)
const ARENA_OVERVIEW := {"hi": [50, 80000], "mid": [45, 60000]}

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
	await _f1_chest()
	await _poses()
	await _run_strip()
	await _arena()
	await _arena_f1()
	_finish()


# ---- alone: one figure per level in its own viewport, a frozen pose (manual clock) ----

func _alone() -> void:
	var sheet := Image.create(CELL.x * 2, CELL.y * LEVELS.size(), false, Image.FORMAT_RGBA8)
	var spot: Array = S.call("wound_spot", &"chest", Vector3(0.3, 0.1, 1.0), WOUND_R)
	_check(spot.size() == 3, "a wound spot on the front of the chest with room for %.1f cm" % (WOUND_R * 100.0), str(spot))
	if spot.size() != 3:
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
		var k1 := _classify(img1, at, rad * CORE_R)
		print("wound alone %-4s draws %d -> %d  primitives %d -> %d  flesh %d -> %d  bone %d -> %d  core: flesh %d background %d  (r %.0f px)"
			% [lv, m0[0], m1[0], m0[1], m1[1], c0[0], c1[0], c0[1], c1[1], k1[0], k1[2], rad])
		sheet.blit_rect(img0, Rect2i(Vector2i.ZERO, CELL), Vector2i(0, i * CELL.y))
		sheet.blit_rect(img1, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x, i * CELL.y))
		_check(m0[0] == 1, "%s: unwounded, the soldier is one draw call" % lv, str(m0))
		_check(c0[0] == 0 and c0[1] == 0, "%s: no flesh or bone pixels at the chest before the wound" % lv, str(c0))
		match lv:
			"hi", "mid":
				_check(added, "%s: add_wound takes the chest wound" % lv)
				_check(m1[0] == 3, "%s: wounded, three draw calls (skin, flesh, bone)" % lv, str(m1))
				_check(c1[0] >= MIN_FLESH, "%s: red flesh shows in the wound (%d px)" % [lv, c1[0]])
				_check(k1[0] >= MIN_FLESH_CORE, "%s: red flesh fills the middle of the hole, where the skin's rim cannot be (%d px within %.1f r)"
					% [lv, k1[0], CORE_R])
				_check(k1[2] == 0, "%s: no background shows through the hole (%d px)" % [lv, k1[2]])
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


# ---- a woman's body (f1): its own wound spots and inner layers ----

func _f1_chest() -> void:
	var dir: String = S.call("folder", "f1")
	var spot: Array = S.call("wound_spot", &"chest", Vector3(0.3, 0.1, 1.0), WOUND_R * 0.8, dir)
	_check(spot.size() == 3, "f1: a wound spot on the front of the chest with room for %.1f cm" % (WOUND_R * 80.0), str(spot))
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
		fig.call("setup", {"role": &"player", "level": lv, "seed": 0, "manual": true, "body": "f1"})
		fig.call("step", 0.0)
		var sk: Skeleton3D = fig.call("skeleton")
		_check(sk != null and is_equal_approx(sk.motion_scale, 1.0), "f1 %s: the figure stands on f1's rig (S 1.0)" % lv)
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
		print("wound f1 %-4s draws %d -> %d  flesh %d -> %d  bone %d -> %d  core: flesh %d background %d  (r %.1f cm, %.0f px)"
			% [lv, m0[0], m1[0], c0[0], c1[0], c0[1], c1[1], k1[0], k1[2], r * 100.0, rad])
		sheet.blit_rect(img0, Rect2i(Vector2i.ZERO, CELL), Vector2i(0, i * CELL.y))
		sheet.blit_rect(img1, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x, i * CELL.y))
		var inner: Array = fig.call("inner_layers")
		var own := inner.size() == 2
		for mi: MeshInstance3D in inner:
			own = own and (mi.mesh == S.call("inner_mesh", "flesh", dir) or mi.mesh == S.call("inner_mesh", "bone", dir)) \
				and mi.mesh != S.call("inner_mesh", "flesh") and mi.mesh != S.call("inner_mesh", "bone")
		_check(added and own, "f1 %s: the chest wound uses f1's own inner layers (not the base body's)" % lv)
		_check(c0[0] == 0 and c0[1] == 0, "f1 %s: no flesh or bone pixels at the chest before the wound" % lv, str(c0))
		_check(m0[0] == 1 and m1[0] == 3, "f1 %s: one draw call, three while wounded (skin, flesh, bone)" % lv, "%s -> %s" % [m0, m1])
		_check(c1[0] >= MIN_FLESH and k1[0] >= MIN_FLESH_CORE, "f1 %s: red flesh in the wound (%d px) and in the middle of the hole (%d px)"
			% [lv, c1[0], k1[0]])
		_check(k1[2] == 0, "f1 %s: no background shows through the hole (%d px)" % [lv, k1[2]])
		_check(c1[1] >= MIN_BONE, "f1 %s: bone shows through the flesh (%d px)" % [lv, c1[1]])
		if lv == "hi":
			var p: Vector3 = fig.call("wound_point", 0)
			var close := p + Vector3(0.12, 0.06, 0.5)
			cam.transform = Transform3D(Basis.looking_at(p - close, Vector3.UP), close)
			var img := await _grab(vp)
			var cc := _classify(img, cam.unproject_position(p), CELL.x * 0.45)
			_check(cc[1] >= MIN_BONE * 8 and cc[0] >= MIN_FLESH * 8, "f1 hi close-up: bone (%d px) through flesh (%d px)" % [cc[1], cc[0]])
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * 2, 0))
		vp.queue_free()
		await _frames(1)
	_save_img(sheet, "soldier_wound_f1_chest.png")


# ---- poses: wounds never show anywhere but in their own circle ----

func _poses() -> void:
	var cell := Vector2i(300, 420)
	var sheet := Image.create(cell.x * 2, cell.y * POSES.size(), false, Image.FORMAT_RGBA8)
	var spots := [[&"chest", Vector3(0.2, 0.0, 1.0), 0.05], [&"spine", Vector3(1.0, 0.1, 0.2), 0.07],
		[&"hipL", Vector3(0.3, 0.0, 1.0), 0.045], [&"shoulderR", Vector3(-0.3, 0.0, 1.0), 0.03]]
	for i in POSES.size():
		var pz: Array = POSES[i]
		var vp := _viewport()
		vp.size = cell
		var fig: Node3D = S.new()
		vp.add_child(fig)
		fig.call("setup", {"role": &"player", "level": "hi", "seed": 5, "manual": true})
		var cam := Camera3D.new()
		cam.fov = 40.0
		vp.add_child(cam)
		cam.current = true
		var dur := 0.0
		if pz[1] == &"fire":
			fig.call("set_weapon", &"gun")
			fig.call("step", 0.3)
			fig.call("play", &"fire", 1.0)
			dur = 0.16
		else:
			fig.call("set_variant", int(pz[2]))
			dur = float(fig.call("play", pz[1], 1.0))
		var t := 0.0
		while t < dur * float(pz[3]):
			fig.call("step", 1.0 / 30.0)
			t += 1.0 / 30.0
		fig.call("step", 1.0 / 30.0)
		fig.call("clear_wounds")
		var sk: Skeleton3D = fig.call("skeleton")
		var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
		if pz[1] == &"die":
			cam.look_at_from_position(hips + Vector3(0.9, 2.2, 1.3), hips)
		else:
			cam.look_at_from_position(hips + Vector3(0.9, 0.35, 2.6), hips + Vector3(0, 0.25, 0))
		var img0 := await _grab(vp)
		var circles := []
		for sp: Array in spots:
			var s: Array = S.call("wound_spot", sp[0], sp[1], 0.6 * float(sp[2]))
			if s.size() != 3:
				continue
			var r := minf(float(sp[2]), float(s[2]))
			var off: Vector3 = (s[0] as Vector3) - (s[1] as Vector3) * r * 0.3
			fig.call("add_wound", sp[0], off, r)
			var c := sk.global_transform * (sk.get_bone_global_pose(sk.find_bone(String(sp[0]))) * off)
			var at := cam.unproject_position(c)
			var edge := cam.unproject_position(c + cam.global_basis.x * r)
			circles.append([at, at.distance_to(edge)])
		var img1 := await _grab(vp)
		var outside := 0
		var inside := 0
		for y in cell.y:
			for x in cell.x:
				var p := img0.get_pixel(x, y)
				var q := img1.get_pixel(x, y)
				if absf(p.r - q.r) <= 0.008 and absf(p.g - q.g) <= 0.008 and absf(p.b - q.b) <= 0.008:
					continue
				var near := false
				for cc: Array in circles:
					if Vector2(x, y).distance_to(cc[0]) <= float(cc[1]) * OUTSIDE_R:
						near = true
						break
				if near:
					inside += 1
				else:
					outside += 1
		print("wound pose %-12s wounds %d  changed pixels inside %d  outside %.2f r: %d" % [pz[0], circles.size(), inside, OUTSIDE_R, outside])
		_check(circles.size() == 4, "%s: four wounds placed" % pz[0])
		_check(outside == 0, "%s: no pixel changes farther than %.2f r from every wound (%d)" % [pz[0], OUTSIDE_R, outside])
		_check(inside >= 150, "%s: the wounds show (%d px changed near them)" % [pz[0], inside])
		sheet.blit_rect(img0, Rect2i(Vector2i.ZERO, cell), Vector2i(0, i * cell.y))
		sheet.blit_rect(img1, Rect2i(Vector2i.ZERO, cell), Vector2i(cell.x, i * cell.y))
		vp.queue_free()
		await _frames(1)
	_save_img(sheet, "soldier_wound_poses.png")


# ---- body parts: a flank wound does not cut the arm that swings in front of it ----

func _run_strip() -> void:
	var cell := Vector2i(300, 360)
	var phases := 6
	var strip := Image.create(cell.x * phases, cell.y * 3, false, Image.FORMAT_RGBA8)
	var vp := _viewport()
	vp.size = cell
	var fig: Node3D = S.new()
	vp.add_child(fig)
	fig.call("setup", {"role": &"player", "level": "hi", "seed": 3, "manual": true})
	fig.call("play", &"run", 1.0)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.current = true
	var body: MeshInstance3D = fig.call("body")
	var dbg := ShaderMaterial.new()
	dbg.shader = Shader.new()
	dbg.shader.code = PART_SHADER
	var s: Array = S.call("wound_spot", &"spine", Vector3(1.0, 0.1, 0.1), 0.08)
	var s2: Array = S.call("wound_spot", &"chest", Vector3(1.0, -0.3, 0.0), 0.025)
	_check(s.size() == 3, "a flank wound spot with room for 8 cm", str(s))
	_check(s2.size() == 3, "a chest-side wound spot by the armpit", str(s2))
	if s.size() != 3 or s2.size() != 3:
		return
	var r := minf(0.085, float(s[2]))
	var off: Vector3 = (s[0] as Vector3) - (s[1] as Vector3) * r * 0.3
	var r2 := minf(0.085, float(s2[2]))
	var off2: Vector3 = (s2[0] as Vector3) - (s2[1] as Vector3) * r2 * 0.3
	var sk: Skeleton3D = fig.call("skeleton")
	var changed_arm := 0
	var arm_over := 0
	var shown := 0
	for i in phases:
		for k in 3:
			fig.call("step", 0.05)
		var ch := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("chest")).origin
		cam.look_at_from_position(ch + Vector3(1.6, 0.05, 0.25), ch + Vector3(0, -0.05, 0))
		fig.call("clear_wounds")
		var img0 := await _grab(vp)
		var keep := body.material_override
		body.material_override = dbg
		var mask := await _grab(vp)
		body.material_override = keep
		fig.call("add_wound", &"spine", off, r)
		fig.call("add_wound", &"chest", off2, r2)
		var img1 := await _grab(vp)
		var c := sk.global_transform * (sk.get_bone_global_pose(sk.find_bone("spine")) * off)
		var at := cam.unproject_position(c)
		var rp := at.distance_to(cam.unproject_position(c + cam.global_basis.y * r))
		var arm_px := 0
		var arm_in := 0
		var arm_diff := 0
		var diff := 0
		for y in cell.y:
			for x in cell.x:
				var m := mask.get_pixel(x, y)
				var arm := m.r > 0.5 and m.b > 0.5 and m.g < 0.5
				var p := img0.get_pixel(x, y)
				var q := img1.get_pixel(x, y)
				var d := absf(p.r - q.r) > 0.008 or absf(p.g - q.g) > 0.008 or absf(p.b - q.b) > 0.008
				if arm:
					arm_px += 1
					if Vector2(x, y).distance_to(at) <= rp:
						arm_in += 1
					if d:
						arm_diff += 1
				elif d:
					diff += 1
		print("wound run phase %d  arm px %d (over the wound %d)  arm px changed %d  other px changed %d  (r %.0f px)" % [i, arm_px, arm_in, arm_diff, diff, rp])
		changed_arm += arm_diff
		arm_over = maxi(arm_over, arm_in)
		shown = maxi(shown, diff)
		strip.blit_rect(img0, Rect2i(Vector2i.ZERO, cell), Vector2i(cell.x * i, 0))
		strip.blit_rect(mask, Rect2i(Vector2i.ZERO, cell), Vector2i(cell.x * i, cell.y))
		strip.blit_rect(img1, Rect2i(Vector2i.ZERO, cell), Vector2i(cell.x * i, cell.y * 2))
	_check(arm_over >= 100, "run: the arm swings in front of the flank wound in some phase (%d px over it)" % arm_over)
	_check(shown >= 300, "run: the wounds show (%d px)" % shown)
	_check(changed_arm == 0, "run: the arm in front of the flank and chest-side wounds is never cut (%d arm pixels changed over %d phases, chest-side r %.1f cm)"
		% [changed_arm, phases, r2 * 100.0])
	_save_img(strip, "soldier_wound_run_strip.png")
	vp.queue_free()
	await _frames(1)


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
	for lv in ["hi", "mid", "lo", "min"]:
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
		_check(m1 == m0 + 2, "%s: wounded, two draw calls more (flesh, bone: %d -> %d)" % [lv, m0, m1])
		# the overview of tests/render/test_soldier.gd, wounded: still within §11.2
		world.call("place_player", ArenaLayout.RESPAWN, PI, 0.0)
		player.call("set_mode", &"shoot")
		(player.call("camera_rig") as Node3D).call("set_view", 0.0, -0.1, ArenaCamera.SHOULDER_ARM)
		await _physics(6)
		var ov := await _measure_total()
		var t: Array = ARENA_OVERVIEW[lv]
		print("wound arena %-4s overview draw calls %d  primitives %d" % [lv, ov[0], ov[1]])
		_check(ov[0] <= int(t[0]) and ov[1] <= int(t[1]), "%s: the wounded overview, %d draws, %d primitives within %d / %d"
			% [lv, ov[0], ov[1], int(t[0]), int(t[1])])
		await _front(world, player)
		if lv == "mid":
			fig.call("clear_wounds")
			continue
		_save("soldier_wound_arena_hi.png")
		player.call("take_hit", {"amount": 1000, "from": player.global_position + Vector3(0, 1, 2)})
		await _physics(80)
		var n := int(fig.call("wound_count"))
		_check(n >= 4 and n <= 5, "hi: death adds two or three wounds to the two (%d in all)" % n)
		# a camera above the body (the arena camera follows the player's feet)
		var sk: Skeleton3D = fig.call("skeleton")
		var pel := _spine_now(fig, sk)
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


## the arena with a woman's body (f1): a real hit, a close-up of bone through flesh, death
func _arena_f1() -> void:
	Figures.select("soldier_f1", "original")
	_app().call("set_gfx", "hi")
	var arena: Node = _app().call("push", load(ARENA_SCREEN))
	await _frames(20)
	var world: Node3D = arena.get("world")
	var player: Node3D = world.get("player")
	var fig: Node3D = player.call("figure")
	_check(fig != null and fig.get_script() == S and str(fig.get("body_id")) == "f1", "f1: the arena player is the f1 body", str(fig))
	if fig == null:
		_app().call("pop")
		return
	var dir: String = S.call("folder", "f1")
	await _front(world, player)
	var m0 := await _measure_main()
	player.call("take_hit", {"amount": 10, "from": player.global_position + Vector3(0, 1, 2)})
	await _physics(30)
	var m1 := await _measure_main()
	print("wound arena f1 hi draws %d -> %d  wounds %d" % [m0, m1, int(fig.call("wound_count"))])
	_check(int(fig.call("wound_count")) == 1 and m1 == m0 + 2, "f1 hi: a real hit leaves one wound and two draw calls more (%d -> %d)" % [m0, m1])
	# the picture: the chest wound of _f1_chest on top of the random hit
	var spot: Array = S.call("wound_spot", &"chest", Vector3(0.3, 0.1, 1.0), WOUND_R * 0.8, dir)
	_check(spot.size() == 3, "f1: a chest spot for the arena picture")
	var r := minf(WOUND_R, float(spot[2])) if spot.size() == 3 else 0.04
	if spot.size() == 3:
		fig.call("add_wound", &"chest", (spot[0] as Vector3) - (spot[1] as Vector3) * r * 0.3, r)
	await _front(world, player)
	_save("soldier_wound_f1_arena_hi.png")
	# close-up on that wound, looking into it along its normal: bone through flesh
	var p: Vector3 = fig.call("wound_point", int(fig.call("wound_count")) - 1)
	var skel: Skeleton3D = fig.call("skeleton")
	var nrm := Vector3(0, 0, 1)
	if spot.size() == 3:
		nrm = (skel.global_basis * skel.get_bone_global_pose(skel.find_bone("chest")).basis * (spot[1] as Vector3)).normalized()
	var old_cam := root.get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	cam.look_at_from_position(p + nrm * 0.5 + Vector3(0, 0.05, 0), p)
	cam.current = true
	await _frames(6)
	var img := root.get_viewport().get_texture().get_image()
	var cc := _classify(img, cam.unproject_position(p), img.get_height() * 0.4)
	_check(cc[1] >= MIN_BONE * 4 and cc[0] >= MIN_FLESH * 4, "f1 hi close-up in the arena: bone (%d px) through flesh (%d px)" % [cc[1], cc[0]])
	_save("soldier_wound_f1_close_hi.png")
	cam.current = false
	if old_cam != null:
		old_cam.current = true
	player.call("take_hit", {"amount": 1000, "from": player.global_position + Vector3(0, 1, 2)})
	await _physics(80)
	var n := int(fig.call("wound_count"))
	_check(n >= 4 and n <= 5, "f1 hi: death adds two or three wounds to the two (%d in all)" % n)
	var sk: Skeleton3D = fig.call("skeleton")
	var pel := _spine_now(fig, sk)
	cam.look_at_from_position(pel + Vector3(0.7, 1.9, 1.0), pel + Vector3(0.0, 0.25, 0.0))
	cam.current = true
	await _frames(6)
	_save("soldier_wound_f1_death_hi.png")
	cam.queue_free()
	if old_cam != null:
		old_cam.current = true
	_app().call("set_gfx", "mid")
	_app().call("pop")
	await _frames(6)
	Figures.select("soldier", "original")


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


## [red-flesh, bone-white, background] pixels within rad of at (skin: g/r ~0.77 and b/r ~0.6 is neither)
## flesh: red over 0.25 with green and blue under 0.45 of it, or the dark cavity (red over 0.07, both under 0.5 of it)
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


## the whole frame (as tests/render/test_soldier.gd): [draw calls, primitives], the most over four frames
func _measure_total() -> Array:
	var idle := OS.low_processor_usage_mode
	OS.low_processor_usage_mode = false
	await _frames(3)
	var d := 0
	var p := 0
	for i in 4:
		await process_frame
		d = maxi(d, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		p = maxi(p, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	OS.low_processor_usage_mode = idle
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


## Where the spine is on screen: on hi the death hands over to a ragdoll (ใหม่ 0.14 item 3) whose pose the skeleton's
## stored pose does not show while it falls, so the camera aims at the ragdoll's spine body then
func _spine_now(fig: Node3D, sk: Skeleton3D) -> Vector3:
	var rag: Variant = fig.call("ragdoll") if fig.has_method("ragdoll") else null
	if rag != null and bool(rag.call("is_falling")) and (rag as Node).has_node("spine"):
		return ((rag as Node).get_node("spine") as Node3D).global_position
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("spine")).origin
