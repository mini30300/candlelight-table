extends SceneTree
## ทำภาพทหาร (xvfb, opengl3): หมุนรอบตัว, ชั้นโครงกระดูก/กล้าม/ผิว, ท่าทดสอบก่อน/หลังท่าแก้, ท่าจากคลิปเกม
## + วัดงบ (draw/สามเหลี่ยม ต่อระดับ) + เวลาตัวขับ + ยืนนิ่งบน min ; เขียน PNG และ render_report.json ลง OUT_DIR
## + ภาพตรวจผิว (หน้า hi/min, ไหปลาร้า, รักแร้, ขาหนีบ, ศอก 0-150°) + ภาพเทียบระดับไขมัน (กล้อง/แสงเดียวกัน)

const Fig := preload("res://src/gd/soldier_figure.gd")
const DATA := "res://out/data/"
var OUT := ""
var cam: Camera3D
var fig: Node3D
var holder: Node3D
var extra: Array[Node3D] = []
var report := {}
var poses: Dictionary


func _initialize() -> void:
	OUT = OS.get_environment("OUT_DIR")
	DirAccess.make_dir_recursive_absolute(OUT)
	RenderingServer.set_default_clear_color(Color(0.16, 0.17, 0.19))
	poses = JSON.parse_string(FileAccess.get_file_as_string(DATA + "poses.json"))
	holder = Node3D.new()
	get_root().add_child(holder)
	cam = Camera3D.new()
	cam.fov = 24.0
	get_root().add_child(cam)
	cam.current = true
	fig = Fig.new()
	holder.add_child(fig)
	print("setup start ", Time.get_ticks_msec())
	fig.setup({"role": &"player", "level": "hi", "seed": 7})
	print("setup done ", Time.get_ticks_msec())
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	print("shot ", name, " t=", Time.get_ticks_msec())
	await _frames(3)
	var img := get_root().get_texture().get_image()
	img.save_png(OUT + "/" + name + ".png")


func _frame_body(centre: Vector3, height: float, yaw_deg: float) -> void:
	var d := height / (2.0 * tan(deg_to_rad(cam.fov * 0.5))) * 1.08
	var dir := Vector3(sin(deg_to_rad(yaw_deg)), 0.0, cos(deg_to_rad(yaw_deg)))
	cam.position = centre + dir * d
	cam.look_at(centre, Vector3.UP)


## กล้องเงย/ก้ม: pitch บวก = มองลงจากข้างบน
func _frame_view(centre: Vector3, height: float, yaw_deg: float, pitch_deg: float) -> void:
	var d := height / (2.0 * tan(deg_to_rad(cam.fov * 0.5))) * 1.08
	var cp := cos(deg_to_rad(pitch_deg))
	var dir := Vector3(sin(deg_to_rad(yaw_deg)) * cp, sin(deg_to_rad(pitch_deg)), cos(deg_to_rad(yaw_deg)) * cp)
	cam.position = centre + dir * d
	cam.look_at(centre, Vector3.UP)


## ท่าจาก poses.json แล้วแทนบางกระดูก (ชื่อ -> Quaternion)
func _pose_mod(name: String, over: Dictionary) -> void:
	var p: Dictionary = poses[name]
	var L := {}
	for b in p["local"]:
		var q: Array = p["local"][b]
		L[b] = Quaternion(q[0], q[1], q[2], q[3])
	for b in over:
		L[b] = over[b]
	var pv: Array = p["pelvis"]
	fig.set_pose(L, Vector3(pv[0], pv[1], pv[2]))


func _pose(name: String) -> void:
	var p: Dictionary = poses[name]
	var L := {}
	for b in p["local"]:
		var q: Array = p["local"][b]
		L[b] = Quaternion(q[0], q[1], q[2], q[3])
	var pv: Array = p["pelvis"]
	fig.set_pose(L, Vector3(pv[0], pv[1], pv[2]))


func _mode(mesh: String, helpers: bool, corr: bool) -> void:
	fig.use_mesh(mesh)
	fig.level = "hi" if mesh != "min" else "min"
	fig.helpers_on = helpers
	fig.correctives_on = corr
	if not corr:
		var mi: MeshInstance3D = fig.body()
		for i in mi.mesh.get_blend_shape_count():
			mi.set_blend_shape_value(i, 0.0)


func _clear_extra() -> void:
	for n in extra:
		n.queue_free()
	extra.clear()


func _add_static(path: String, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = load(path)
	mi.position = offset
	holder.add_child(mi)
	extra.append(mi)
	return mi


func _add_skeleton_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = load("res://out/godot/skeleton_mesh.res")
	fig.skeleton().add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = load("res://out/godot/skin.res")
	extra.append(mi)
	return mi


func _run() -> void:
	var what := OS.get_environment("WHAT")
	if what == "" or what.contains("turn"):
		await _turntable()
	if what == "" or what.contains("layers"):
		await _layers()
	if what == "" or what.contains("poses"):
		await _pose_tests()
	if what == "" or what.contains("clips"):
		await _clips()
	if what == "" or what.contains("budget"):
		await _budgets()
	if what == "" or what.contains("checks"):
		await _checks()
	if what == "" or what.contains("fat"):
		await _fat_levels()
	var f := FileAccess.open(OUT + "/render_report_%s.json" % (what if what != "" else "all"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))
	quit()


# ---- 1) หมุนรอบตัว (ท่า A ที่ปั้น = ผิวไม่ถูกบิด) + ท่ายืนในเกม ----
func _turntable() -> void:
	_mode("hi", true, true)
	_pose("bind")
	for yaw in [0, 45, 90, 180]:
		_frame_body(Vector3(0, 0.90, 0), 1.95, yaw)
		await _shot("turn_%03d" % yaw)
	_pose("idle")
	for yaw in [0, 30, 90, 180]:
		_frame_body(Vector3(0, 0.90, 0), 1.95, yaw)
		await _shot("idle_%03d" % yaw)
	# ใกล้: หน้า มือ เท้า
	_pose("bind")
	_frame_body(Vector3(0, 1.64, 0.02), 0.34, 20)
	await _shot("close_head")
	_frame_body(Vector3(0, 1.64, 0.02), 0.34, 90)
	await _shot("close_head_side")
	_frame_body(Vector3(0, 1.25, 0.0), 0.75, 0)
	await _shot("close_torso")
	_frame_body(Vector3(0, 1.25, 0.0), 0.75, 180)
	await _shot("close_back")


# ---- 2) ชั้น: โครงกระดูก / กล้ามเนื้อ / ผิว (ท่า A) + ผ่าครึ่ง ----
func _layers() -> void:
	_mode("hi", true, true)
	_pose("bind")
	var body: MeshInstance3D = fig.body()
	for yaw in [0, 180]:
		_frame_body(Vector3(0, 0.90, 0), 1.95, yaw)
		body.visible = false
		_add_skeleton_mesh()
		await _shot("layer_skeleton_%03d" % yaw)
		_clear_extra()
		_add_static("res://out/godot/muscles_bind.res")
		await _shot("layer_muscles_%03d" % yaw)
		_add_skeleton_mesh()
		await _shot("layer_muscles_bones_%03d" % yaw)
		_clear_extra()
		body.visible = true
		await _shot("layer_skin_%03d" % yaw)
	# ผ่าครึ่ง: ซ้ายของภาพ = ผิว, ขวา = กล้ามเนื้อ+โครง (ตัดด้วยระนาบในเชดเดอร์ไม่ได้ -> ซ้อน 2 ภาพแล้วตัดใน PIL)
	report["layers"] = "ok"


# ---- 3) ท่าทดสอบ: LBS ล้วน (min) / +กระดูกช่วย (lo) / +ท่าแก้ (hi) + กล้ามในท่านั้น ----
func _pose_tests() -> void:
	var views := {"elbow120": [Vector3(0.0, 1.20, 0.05), 0.85, 60.0], "knee120": [Vector3(0.05, 0.55, 0.0), 1.15, 90.0],
		"overhead": [Vector3(0.0, 1.45, 0.0), 1.0, 20.0], "squat": [Vector3(0.0, 0.62, 0.05), 1.35, 60.0],
		"rifle": [Vector3(0.0, 1.22, 0.10), 1.0, 35.0], "idle": [Vector3(0.0, 1.25, 0.0), 0.9, 0.0]}
	var zooms := {"elbow120": ["elbowL", 0.42, 70.0, Vector3(0, 0.02, 0.05)], "knee120": ["kneeL", 0.5, 90.0, Vector3(0, 0.02, -0.04)],
		"overhead": ["shoulderL", 0.5, 25.0, Vector3(-0.05, -0.05, 0)], "squat": ["kneeL", 0.62, 70.0, Vector3(0, 0.08, -0.08)],
		"rifle": ["shoulderR", 0.5, 20.0, Vector3(0.06, -0.06, 0.06)]}
	var drv := {}
	for pn in views:
		var v: Array = views[pn]
		for m in [["lbs", "hilbs", false, false], ["helpers", "hi", true, false], ["full", "hi", true, true]]:
			_mode(m[1], m[2], m[3])
			_pose(pn)
			_frame_body(v[0], v[1], v[2])
			await _shot("pose_%s_%s" % [pn, m[0]])
			if m[0] == "full":
				drv[pn] = fig.last_weights.duplicate()
			# ใกล้ข้อที่ทดสอบ (เห็นความต่างก่อน/หลังชัด)
			var z: Array = zooms.get(pn, [])
			if not z.is_empty():
				var sk: Skeleton3D = fig.skeleton()
				var c: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(z[0])).origin + (z[3] as Vector3)
				_frame_body(c, z[1], z[2])
				await _shot("posez_%s_%s" % [pn, m[0]])
		var mi: MeshInstance3D = fig.body()
		mi.visible = false
		_add_static("res://out/godot/muscles_%s.res" % pn)
		_frame_body(v[0], v[1], v[2])
		await _shot("pose_%s_muscles" % pn)
		var zz: Array = zooms.get(pn, [])
		if not zz.is_empty():
			var sk2: Skeleton3D = fig.skeleton()
			var c2: Vector3 = sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone(zz[0])).origin + (zz[3] as Vector3)
			_frame_body(c2, zz[1], zz[2])
			await _shot("posez_%s_muscles" % pn)
		_clear_extra()
		mi.visible = true
	# ตัวขับฝั่ง Godot ต้องตรงกับ Python
	var diff := 0.0
	for pn in drv:
		var py: Dictionary = poses[pn]["driver"]
		for k in drv[pn]:
			diff = maxf(diff, absf(float(drv[pn][k]) - float(py.get(k, 0.0))))
	report["driver_max_diff_godot_vs_python"] = diff
	report["driver_weights"] = drv


# ---- 4) ท่าจากคลิปเกม (humanoid.res ตรง ๆ) ----
func _clips() -> void:
	_mode("hi", true, true)
	var ap: AnimationPlayer = fig.animation_player()
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var list := {"idle": 4, "walk": 6, "run": 6, "fire": 6, "bash_0": 6, "flinch": 4, "die_back": 5, "die_fwd": 5, "die_spin": 5}
	for clip in list:
		var anim := ap.get_animation("humanoid/" + clip)
		var n: int = list[clip]
		for i in n:
			var t := anim.length * float(i) / float(n - 1 if anim.loop_mode == Animation.LOOP_NONE else n)
			if clip == "idle":
				t = anim.length * float(i) / float(n)
			ap.play("humanoid/" + clip)
			ap.seek(t, true)
			ap.advance(0.0)
			fig.deform()
			var pv: Vector3 = (fig.skeleton() as Skeleton3D).get_bone_global_pose(0).origin
			_frame_body(Vector3(pv.x, 0.85 if not clip.begins_with("die") else 0.5, pv.z), 2.0, 35.0)
			await _shot("clip_%s_%d" % [clip, i])
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


# ---- 5) งบต่อระดับ + เวลาตัวขับ + ยืนนิ่ง min ----
func _budgets() -> void:
	var res := {}
	var ap: AnimationPlayer = fig.animation_player()
	for lv in ["hi", "mid", "lo", "min"]:
		fig.apply_level(lv)
		fig.helpers_on = true
		fig.correctives_on = true
		fig.play(&"walk", 1.0)
		_frame_body(Vector3(0, 0.9, 0), 2.0, 30)
		await _frames(6)
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		# เวลาตัวขับ (เฉลี่ย 200 ครั้ง)
		var t0 := Time.get_ticks_usec()
		for i in 200:
			fig.deform()
		var us := float(Time.get_ticks_usec() - t0) / 200.0
		var mesh: ArrayMesh = fig.body().mesh
		res[lv] = {"draws": draws, "primitives": prims, "mesh_tris": mesh.surface_get_array_index_len(0) / 3,
			"surfaces": mesh.get_surface_count(), "blend_shapes": mesh.get_blend_shape_count(), "driver_us": us}
		await _shot("budget_%s" % lv)
	# ยืนนิ่งบน min ภายในกี่เฟรม
	fig.apply_level("min")
	fig.play(&"walk")
	await _frames(5)
	fig.set_move(0.0, false)
	var frames := 0
	while not fig.is_still() and frames < 60:
		await process_frame
		frames += 1
	res["min_still_after_frames"] = frames
	res["figure_api_missing"] = _missing_api()
	res["foot_slide"] = {"walk": _slide("walk", 1.0), "run": _slide("run", 1.0), "walk_control_90pct": _slide("walk", 0.9)}
	res["clip_events_fire"] = await _events()
	report["budgets"] = res


## เท้าที่แตะพื้นไถลเท่าไร (มม.) ตามธงสัมผัสของคลิป: ตรรกะเดียวกับ tests/render/test_anim_footslide.gd (240 ครั้ง/วิ)
static func _planted(anim: Animation, side: String, point: String, t: float) -> bool:
	var key := "contact_l" if side == "L" else "contact_r"
	if not anim.has_meta(key):
		return false
	var c: PackedStringArray = anim.get_meta(key)
	var n := c.size()
	var k0 := posmod(int(floor(t * 30.0 + 1e-6)), n)
	var k1 := posmod(k0 + 1, n)
	var want := ["heel", "flat"] if point == "heel" else ["ball", "flat"]
	return want.has(c[k0]) and want.has(c[k1])


func _slide(clip: String, speed_k: float) -> Dictionary:
	fig.apply_level("hi")
	var ap: AnimationPlayer = fig.animation_player()
	var sk: Skeleton3D = fig.skeleton()
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var anim := ap.get_animation("humanoid/" + clip)
	ap.play("humanoid/" + clip, 0.0)
	var span := anim.length * 3.0
	var n := int(ceil(span * 240.0))
	var anchor := {}
	var worst := 0.0
	var plants := 0
	for i in n + 1:
		var t := minf(float(i) / 240.0, span)
		var tc := fmod(t, anim.length)
		ap.seek(tc, true)
		fig.position.z = float(anim.get_meta("speed", 0.0)) * t * Fig.S * speed_k
		for side in ["L", "R"]:
			for point in ["heel", "toe"]:
				var key: String = point + side
				if not _planted(anim, side, "heel" if point == "heel" else "ball", tc):
					anchor.erase(key)
					continue
				var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(key)).origin
				if not anchor.has(key):
					anchor[key] = p
					plants += 1
					continue
				var a: Vector3 = anchor[key]
				worst = maxf(worst, Vector2(p.x - a.x, p.z - a.z).length())
	fig.position = Vector3.ZERO
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	return {"mm": snappedf(worst * 1000.0, 0.01), "plants": plants, "speed_m_s": float(anim.get_meta("speed", 0.0)) * Fig.S * speed_k}


## สัญญาณ clip_event: ท่ายิง (fire) ต้องส่ง shot 3 ครั้ง
func _events() -> Dictionary:
	fig.apply_level("hi")
	var got: Array = []
	var cb := func(kind: StringName) -> void: got.append(String(kind))
	fig.clip_event.connect(cb)
	var length: float = fig.play(&"fire", 1.0)
	var frames := 0
	while frames < int(length * 60.0) + 30:
		await process_frame
		frames += 1
	fig.clip_event.disconnect(cb)
	return {"events": got, "clip_length_s": length}


func _missing_api() -> Array:
	var api := ["setup", "metrics", "clip_names", "play", "set_move", "set_aim", "set_weapon", "set_flash", "set_telegraph",
		"muzzle", "anchor", "apply_level"]
	var miss := []
	for m in api:
		if not fig.has_method(m):
			miss.append(m)
	if not fig.has_signal("clip_event"):
		miss.append("signal clip_event")
	return miss


# ---- 6) ภาพตรวจผิว: หน้า hi/min (หน้า 3/4 ข้าง + ระยะเกม), ไหปลาร้า, รักแร้ยกแขน, ขาหนีบ/สะโพก, ศอก 0-150° ----
func _checks() -> void:
	for lv in ["hi", "min"]:
		_mode(lv, true, true)
		fig.apply_level(lv)
		_pose("bind")
		for yaw in [0, 35, 90]:
			_frame_body(Vector3(0, 1.655, 0.03), 0.30, yaw)
			await _shot("face_%s_%03d" % [lv, yaw])
		# ระยะเกม (กล้องห่าง ~3.5 ม.)
		_frame_body(Vector3(0, 1.40, 0.0), 1.45, 20)
		await _shot("face_%s_game" % lv)
	_mode("hi", true, true)
	fig.apply_level("hi")
	_pose("bind")
	_frame_view(Vector3(0, 1.43, 0.04), 0.42, 0, 12)
	await _shot("check_collar_000")
	_frame_view(Vector3(0.02, 1.43, 0.04), 0.42, 35, 8)
	await _shot("check_collar_035")
	_frame_view(Vector3(0, 0.90, 0.03), 0.46, 0, 0)
	await _shot("check_groin_000")
	_frame_view(Vector3(0, 0.90, 0.02), 0.46, 35, -8)
	await _shot("check_groin_035")
	_frame_view(Vector3(0, 0.90, -0.02), 0.50, 180, 0)
	await _shot("check_hips_180")
	_frame_view(Vector3(0.10, 0.92, 0.02), 0.50, 90, 0)
	await _shot("check_hips_090")
	# รักแร้ตอนยกแขนเหนือหัว (มองจากหน้าเฉียงต่ำ และจากข้าง)
	_pose("overhead")
	_frame_view(Vector3(0.13, 1.40, 0.0), 0.50, 45, -12)
	await _shot("check_armpit_045")
	_frame_view(Vector3(0.13, 1.40, -0.01), 0.50, 90, -5)
	await _shot("check_armpit_090")
	# ศอก 0-150° (ดูเงาด้านข้าง)
	for a in [0, 30, 60, 90, 120, 150]:
		_pose_mod("elbow120", {"elbowL": Quaternion(Vector3(1, 0, 0), deg_to_rad(-float(a)))})
		var sk: Skeleton3D = fig.skeleton()
		var c: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("elbowL")).origin
		_frame_view(c + Vector3(0.02, -0.05, 0.06), 0.55, 55, 0)
		await _shot("check_elbow_%03d" % a)
	# เข่า 120° และย่อตัว: มุมกว้าง (ด้านข้าง/หน้า)
	_pose("knee120")
	_frame_view(Vector3(0.10, 0.55, 0.05), 0.80, 0, 0)
	await _shot("check_knee120_000")
	_pose("squat")
	_frame_view(Vector3(0.0, 0.55, 0.10), 1.10, 0, 5)
	await _shot("check_squat_000")
	_frame_view(Vector3(0.0, 0.55, 0.05), 1.10, 90, 0)
	await _shot("check_squat_090")
	_pose("bind")


# ---- 7) เทียบระดับไขมัน: ผิวนิ่ง body_static_<tag>.res กล้อง/แสง/วัสดุเดียวกันทุกแบบ ----
func _fat_levels() -> void:
	var tags := []
	for t in ["fat080", "fat100", "fat130"]:
		if ResourceLoader.exists("res://out/godot/body_static_%s.res" % t):
			tags.append(t)
	if tags.is_empty():
		return
	fig.visible = false
	for t in tags:
		var mi := _add_static("res://out/godot/body_static_%s.res" % t)
		mi.material_override = load("res://out/godot/soldier_skin.tres")
		for v in [["front", 0], ["side", 90], ["back", 180]]:
			_frame_body(Vector3(0, 0.90, 0), 1.95, v[1])
			await _shot("fat_%s_%s" % [t, v[0]])
		_frame_body(Vector3(0, 1.645, 0.03), 0.34, 30)
		await _shot("fat_%s_face" % t)
		_frame_body(Vector3(0, 1.12, 0.0), 0.80, 30)
		await _shot("fat_%s_torso" % t)
		_clear_extra()
		await _frames(2)
	fig.visible = true
	report["fat_levels"] = tags
