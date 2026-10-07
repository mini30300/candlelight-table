extends SceneTree
## Foot-slide gate of the baked clips (ARCHITECTURE §7, PLAN R1-V2). Plays clips of assets/anim/humanoid.res
## (tools/bake_anim.js + bake_anim.gd) on imported skinned kits that travel at the clip's own speed, and measures how
## far each planted foot point (heel / ball bones, planted as the clip's contact flags say) moves on the ground while it
## is planted — the old page's harness measure (web/harness.js slideProbe), at 240 samples a second so the slide
## between the 30 Hz keys counts too. A kit of scale S plays with Skeleton3D.motion_scale = S and moves S times as
## fast, so the walker kits prove the scaled path. Gate: <= MAX_SLIDE_MM on every measured clip.
## Then, with a display, renders strips of frames: tests/out/anim_walk_<case>.png (one walk cycle, the ground marked
## every 25 cm so planted feet can be seen standing still) and tests/out/anim_actions_<n>.png (a contact sheet of the
## action clips). Headless runs measure only.
##   xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy -s tests/render/test_anim_footslide.gd
## Needs the kits (tools/export_kits.js + --import) and the bake (tools/kits.sh). TEST_OUT (absolute) replaces tests/out.

const LIB_PATH := "res://assets/anim/humanoid.res"
const KITS_DIR := "res://assets/kits/"
const MANIFEST := KITS_DIR + "kits.json"
const DEFAULT_OUT_DIR := "res://tests/out"
const MAX_SLIDE_MM := 15.0
const RATE := 240.0                 # samples per second of the measurement
const CYCLES := 3                   # loops measured this many times round
const WALKER_KIT := "mech"          # the page's walker: a heavy scaled up 2.2 times
const CLEAR := Color(0.62, 0.66, 0.70)
const STRIP_FRAMES := 8
const CELL := Vector2i(240, 400)

var _out_dir := DEFAULT_OUT_DIR
var _lib: AnimationLibrary
var _manifest: Dictionary = {}
var _holds: Dictionary = {}
var _passed := 0
var _failed := 0
var _headless := false


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	_headless = DisplayServer.get_name() == "headless"
	_run()


func _run() -> void:
	await process_frame                       # bone global poses follow only once the tree is running
	if not _load():
		_finish()
		return
	var proofs: Dictionary = _lib.get_meta("proofs", {})
	var human := String(proofs.get("humanoid", "infantry"))
	var titan := String(proofs.get("walker", ""))
	# the three proofs: a humanoid walk, the page's walker, the biggest skinned walker (a titan-class figure)
	var cases := [
		{"name": "humanoid", "kit": human, "clips": ["walk", "run", "walk_start", "walk_stop", "run_start", "run_stop", "turn_left", "turn_right", "turn_back", "idle"]},
		{"name": "walker", "kit": WALKER_KIT, "clips": ["walk", "run"]},
	]
	if titan != "" and titan != WALKER_KIT and titan != human:
		cases.append({"name": "titan", "kit": titan, "clips": ["walk"]})
	for c in cases:
		if not _manifest.has(c["kit"]) or not bool(_manifest[c["kit"]].get("skinned", false)):
			_ok(false, "%s: kit %s is in kits.json and skinned" % [c["name"], c["kit"]])
			continue
		for clip in c["clips"]:
			_measure(c["name"], c["kit"], clip)
	_control(human)
	_check_holds(human)
	if _headless:
		print("headless: no strips rendered (run under xvfb for tests/out/anim_*.png)")
	else:
		DirAccess.make_dir_recursive_absolute(_abs(_out_dir))
		RenderingServer.set_default_clear_color(CLEAR)
		await process_frame
		for c in cases:
			await _strip(c["name"], c["kit"], "walk")
		await _contact_sheet()
	_finish()


func _load() -> bool:
	_lib = load(LIB_PATH) as AnimationLibrary
	_ok(_lib != null, "the baked library loads: " + LIB_PATH + " (run godot/tools/kits.sh)")
	if _lib == null:
		return false
	_holds = _lib.get_meta("holds", {})
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)) if FileAccess.file_exists(MANIFEST) else null
	_ok(data is Dictionary and data.get("kits") is Dictionary, "kits.json loads (run tools/export_kits.js and --import)")
	if not (data is Dictionary):
		return false
	_manifest = data["kits"]
	var n := _lib.get_animation_list().size()
	_ok(n >= 10, "the library has %d clips" % n)
	for clip in ["idle", "walk", "run", "turn_left", "fire", "bow", "throw", "thrust_0", "swing_0", "brace", "flinch", "die_back", "die_fwd"]:
		_ok(_lib.has_animation(clip), "clip %s is baked" % clip)
	return true


func _finish() -> void:
	print("%s  %d passed, %d failed (test_anim_footslide)" % ["PASS " if _failed == 0 else "FAIL ", _passed, _failed])
	quit(1 if _failed > 0 else 0)


func _ok(cond: bool, msg: String, detail: Variant = null) -> void:
	if cond:
		_passed += 1
		print("ok    " + msg)
	else:
		_failed += 1
		print("FAIL  " + msg + ("" if detail == null else " " + str(detail).left(1500)))


func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") else p


## A figure: the imported kit + an AnimationPlayer (manual stepping) holding the library; motion_scale = kit scale.
func _figure(kit: String, parent: Node) -> Dictionary:
	var ps: PackedScene = load(KITS_DIR + kit + ".glb")
	var node: Node3D = ps.instantiate()
	parent.add_child(node)
	var sk: Skeleton3D = node.get_node("Skeleton3D")
	var scale := float(_manifest[kit].get("scale", 1.0))
	sk.motion_scale = scale
	var ap := AnimationPlayer.new()
	node.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("humanoid", _lib)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return {"node": node, "sk": sk, "ap": ap, "scale": scale, "kit": kit}


## Puts the figure at clip time t: the pose (AnimationPlayer.seek), the kit's holds, and the travel along +Z.
func _pose_at(f: Dictionary, anim: Animation, clip: String, t: float) -> void:
	var ap: AnimationPlayer = f["ap"]
	if ap.current_animation != "humanoid/" + clip:
		ap.play("humanoid/" + clip)
	ap.seek(t, true)
	apply_holds(f["sk"], _holds.get(f["kit"], {}), anim)
	(f["node"] as Node3D).position = Vector3(0.0, 0.0, travel_at(anim, t) * float(f["scale"]))


## Rig metres travelled by clip time t: speed * t for a clip that plays in place, the per-frame travel of a start or stop.
static func travel_at(anim: Animation, t: float) -> float:
	if anim.has_meta("travel"):
		var tr: PackedFloat32Array = anim.get_meta("travel")
		var x := clampf(t * 30.0, 0.0, float(tr.size() - 1))
		var i := mini(int(floor(x)), tr.size() - 2) if tr.size() > 1 else 0
		return lerpf(tr[i], tr[mini(i + 1, tr.size() - 1)], x - float(i)) if tr.size() > 1 else tr[0]
	return float(anim.get_meta("speed", 0.0)) * t


## The kit's own pose over the clip (bake_anim.js `holds`): slerp toward C by w, or a fixed turn after / before.
## hold_mode all = every bone the hold names; undriven = only the bones the clip leaves alone; ik bones are left to IK.
static func apply_holds(sk: Skeleton3D, hold: Dictionary, anim: Animation) -> void:
	var mode := String(anim.get_meta("hold_mode", "all"))
	if mode == "none" or not (hold.get("joints") is Dictionary):
		return
	var drives: PackedStringArray = anim.get_meta("drives", PackedStringArray())
	var joints: Dictionary = hold["joints"]
	for j in joints.keys():
		var v: Variant = joints[j]
		if not (v is Dictionary) or (mode == "undriven" and drives.has(String(j))):
			continue
		var b := sk.find_bone(String(j))
		if b < 0:
			continue
		var q := sk.get_bone_pose_rotation(b)
		if v.has("C"):
			q = q.slerp(v["C"], float(v["w"]))
		elif v.has("mul"):
			q = q * (v["mul"] as Quaternion)
		elif v.has("pre"):
			q = (v["pre"] as Quaternion) * q
		sk.set_bone_pose_rotation(b, q.normalized())


## Planted = the contact flag says so at the key before and the key after t (a point lifting off between keys is free).
static func planted(anim: Animation, side: String, point: String, t: float) -> bool:
	var key := "contact_l" if side == "L" else "contact_r"
	if not anim.has_meta(key):
		return false
	var c: PackedStringArray = anim.get_meta(key)
	var n := c.size()
	var k0 := int(floor(t * 30.0 + 1e-6))
	var k1 := k0 + 1
	if anim.loop_mode != Animation.LOOP_NONE:
		k0 = posmod(k0, n)
		k1 = posmod(k1, n)
	else:
		k0 = clampi(k0, 0, n - 1)
		k1 = clampi(k1, 0, n - 1)
	var want := ["heel", "flat"] if point == "heel" else ["ball", "flat"]
	return want.has(c[k0]) and want.has(c[k1])


## Max ground slide (mm) of the four foot points over the clip (CYCLES times round for a loop).
func _measure(case_name: String, kit: String, clip: String) -> void:
	if not _lib.has_animation(clip):
		_ok(false, "%s: clip %s exists" % [case_name, clip])
		return
	var r := slide(kit, clip, 1.0)
	var msg := "%s %s on %s (scale %.2f, %.3f m/s): foot slide %.2f mm, height drift %.2f mm while planted (%d plants, %.2f s)" % [
		case_name, clip, kit, r["scale"], r["speed"], r["mm"], r["mm_y"], r["plants"], r["planted_s"]]
	if int(r["plants"]) == 0 and clip != "idle":
		_ok(false, msg, "no planted foot at all: contact flags missing?")
		return
	_ok(float(r["mm"]) <= MAX_SLIDE_MM, msg + (" <= %.0f mm" % MAX_SLIDE_MM), "worst " + String(r["where"]))


## The gate has teeth: the same walk with the figure travelling 10 % too slow must slide well past the limit.
func _control(kit: String) -> void:
	var r := slide(kit, "walk", 0.9)
	_ok(float(r["mm"]) > 3.0 * MAX_SLIDE_MM, "control: walk on %s at 90 %% of its speed slides %.1f mm (the measure sees a wrong speed)" % [kit, r["mm"]])


## Ground slide of the four foot points over `clip` (CYCLES times round for a loop) with the figure moving at
## speed_k times the clip's speed: {mm, mm_y, plants, planted_s, where, scale, speed}.
func slide(kit: String, clip: String, speed_k: float) -> Dictionary:
	var anim := _lib.get_animation(clip)
	var stage := Node3D.new()
	root.add_child(stage)
	var f := _figure(kit, stage)
	var sk: Skeleton3D = f["sk"]
	var loops := anim.loop_mode != Animation.LOOP_NONE
	var span := anim.length * (CYCLES if loops else 1)
	var n := int(ceil(span * RATE))
	var anchor := {}
	var worst := 0.0
	var worst_y := 0.0
	var plants := 0
	var planted_s := 0.0
	var where := ""
	for i in n + 1:
		var t := minf(float(i) / RATE, span)
		var tc := fmod(t, anim.length) if loops else t
		# a loop's travel keeps adding up round the cycle: whole laps plus the part of this one
		_pose_at(f, anim, clip, tc)
		if loops:
			(f["node"] as Node3D).position.z = float(anim.get_meta("speed", 0.0)) * t * float(f["scale"])
		(f["node"] as Node3D).position.z *= speed_k
		for side in ["L", "R"]:
			for point in ["heel", "toe"]:
				var key: String = point + side
				if not planted(anim, side, "heel" if point == "heel" else "ball", tc):
					anchor.erase(key)
					continue
				var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(key)).origin
				if not anchor.has(key):
					anchor[key] = p
					plants += 1
					continue
				var a: Vector3 = anchor[key]
				var d := Vector2(p.x - a.x, p.z - a.z).length()
				planted_s += 1.0 / RATE / 4.0
				if d > worst:
					worst = d
					where = "%s at %.3f s" % [key, tc]
				worst_y = maxf(worst_y, absf(p.y - a.y))
	stage.queue_free()
	return {"mm": worst * 1000.0, "mm_y": worst_y * 1000.0, "plants": plants, "planted_s": planted_s, "where": where,
		"scale": float(f["scale"]), "speed": float(anim.get_meta("speed", 0.0)) * float(f["scale"]) * speed_k}


## The holds of the humanoid proof kit reproduce its own arm pose: a gunner keeps both hands on the rifle while it walks.
func _check_holds(kit: String) -> void:
	var h: Dictionary = _holds.get(kit, {})
	_ok(h.get("joints") is Dictionary and not (h["joints"] as Dictionary).is_empty(), "kit %s has holds (its own arm pose over the clips)" % kit)
	var arms := 0
	for j in (h.get("joints", {}) as Dictionary).keys():
		if String(j).begins_with("shoulder") or String(j).begins_with("elbow"):
			arms += 1
	_ok(arms == 4, "kit %s holds both arms (%d shoulder/elbow bones)" % [kit, arms])


# ---------- pictures ----------

func _camera(parent: Node, target: Vector3, height: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.05
	cam.far = 500.0
	parent.add_child(cam)
	var d := height * 3.4 + 2.0
	cam.look_at_from_position(target + Vector3(d * 0.94, height * 0.55 + d * 0.18, d * 0.34), target + Vector3(0.0, height * 0.45, 0.0), Vector3.UP)
	cam.make_current()
	return cam


## Ground with a stripe every 25 cm (rig metres x scale) so a planted foot can be seen staying put.
func _ground(parent: Node, scale: float, length: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.46, 0.52, 0.42)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60.0 * scale, 60.0 * scale)
	plane.mesh = pm
	plane.material_override = mat
	plane.position = Vector3(0.0, -0.002, length * 0.5)
	parent.add_child(plane)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(0.30, 0.34, 0.28)
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2 * scale, 0.002, 0.125 * scale)
	var step := 0.25 * scale
	var k := -8
	while k * step < length + 4.0 * scale:
		var b := MeshInstance3D.new()
		b.mesh = bm
		b.material_override = dark
		b.position = Vector3(0.0, -0.001, k * step)
		parent.add_child(b)
		k += 1


func _grab_cell(cam: Camera3D, at: Vector3, height: float) -> Image:
	var img := root.get_viewport().get_texture().get_image()
	var c := cam.unproject_position(at + Vector3(0.0, height * 0.5, 0.0))
	var top := cam.unproject_position(at + Vector3(0.0, height * 1.15, 0.0))
	var bottom := cam.unproject_position(at + Vector3(0.0, -height * 0.12, 0.0))
	var h := maxf(bottom.y - top.y, 40.0)
	var w := h * float(CELL.x) / float(CELL.y)
	var r := Rect2i(int(c.x - w * 0.5), int(top.y), int(w), int(h))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var cell := img.get_region(r)
	cell.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	return cell


## One cycle of `clip` in STRIP_FRAMES frames side by side, the camera following the figure.
func _strip(case_name: String, kit: String, clip: String) -> void:
	var anim := _lib.get_animation(clip)
	var stage := Node3D.new()
	root.add_child(stage)
	var f := _figure(kit, stage)
	var scale := float(f["scale"])
	var height := 1.75 * scale
	_ground(stage, scale, anim.length * float(anim.get_meta("speed", 0.0)) * scale)
	var strip := Image.create(CELL.x * STRIP_FRAMES, CELL.y, false, Image.FORMAT_RGBA8)
	var cam: Camera3D = null
	for i in STRIP_FRAMES:
		var t := anim.length * float(i) / float(STRIP_FRAMES)
		_pose_at(f, anim, clip, t)
		var at := (f["node"] as Node3D).position
		if cam != null:
			cam.free()
		cam = _camera(stage, at, height)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var cell := _grab_cell(cam, at, height)
		strip.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), Vector2i(i * CELL.x, 0))
	var file := "anim_%s_%s.png" % [clip, case_name]
	var err := strip.save_png(_out_dir.path_join(file))
	_ok(err == OK, "strip of %s on %s (%d frames over %.2f s) -> %s" % [clip, kit, STRIP_FRAMES, anim.length, file])
	stage.queue_free()
	await process_frame


## Action clips on the kits they belong to, five moments each; two sheets.
func _contact_sheet() -> void:
	var rows := [
		["fire", "infantry"], ["fire_heavy", "hmg"], ["fire_pistol_l", "cmdr"], ["bow", "archer"], ["throw", "peltast"], ["thrust_0", "hoplite"],
		["swing_0", "levy"], ["swing2_1", "samurai"], ["bash_1", "infantry"], ["brace", "hoplite"], ["claw_1", "mummy"], ["twin", "dabsong"],
		["hurl", "herc"], ["cast", "anubis"], ["flame", "flamer"], ["zap", "thunder"], ["flinch_heavy", "infantry"], ["die_kneel", "infantry"],
	]
	var cols := 5
	var per := 6
	var sheet_i := 0
	var r0 := 0
	while r0 < rows.size():
		var part: Array = rows.slice(r0, r0 + per)
		var sheet := Image.create(CELL.x * cols, CELL.y * part.size(), false, Image.FORMAT_RGBA8)
		for ri in part.size():
			var clip: String = part[ri][0]
			var kit: String = part[ri][1]
			if not _lib.has_animation(clip) or not _manifest.has(kit):
				_ok(false, "contact sheet: clip %s and kit %s exist" % [clip, kit])
				continue
			var anim := _lib.get_animation(clip)
			var stage := Node3D.new()
			root.add_child(stage)
			var f := _figure(kit, stage)
			_ground(stage, 1.0, 0.0)
			var cam: Camera3D = null
			for ci in cols:
				var t := anim.length * (0.1 + 0.8 * float(ci) / float(cols - 1))
				_pose_at(f, anim, clip, t)
				if cam != null:
					cam.free()
				cam = _camera(stage, Vector3.ZERO, 1.75)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var cell := _grab_cell(cam, Vector3.ZERO, 1.75)
				sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), Vector2i(ci * CELL.x, ri * CELL.y))
			stage.queue_free()
			await process_frame
		sheet_i += 1
		var file := "anim_actions_%d.png" % sheet_i
		_ok(sheet.save_png(_out_dir.path_join(file)) == OK, "contact sheet %d (%d clips x %d moments) -> %s" % [sheet_i, part.size(), cols, file])
		r0 += per
