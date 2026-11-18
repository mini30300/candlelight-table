extends SceneTree
## นำเข้าผลของขั้นปั้นทหารเข้าเกม (tools/soldier/import_stage.sh เรียก รันแบบ headless ในโปรเจกต์ชั่วคราว)
## + ชั้นในของบาดแผล (inner_bone/inner_flesh + inner.gdshader) ถ้าขั้นปั้นทำมา
## โปรเจกต์ชั่วคราววางไฟล์ของขั้นปั้นไว้ที่เดิม (res://out/godot, res://src/gd) จึงโหลดได้ตามที่ทำมา
## แล้วบันทึกใหม่ที่ res://assets/figures/soldier/ ด้วยชื่อกลางและทางไฟล์ของเกม (เมชอ้างวัสดุของเกม ไม่อ้างโฟลเดอร์ขั้นปั้น)
## UID เดิมของเกม (สำเนาใน res://old/) ใช้ต่อ ไฟล์จึงเปลี่ยนเฉพาะเนื้อหา · รายงานต่อระดับพิมพ์ออกจอ + REPORT

const SRC := "res://out/godot/"
const SHADER_SRC := "res://src/gd/soldier_skin.gdshader"
const INNER_SHADER_SRC := "res://src/gd/soldier_inner.gdshader"
const DST := "res://assets/figures/soldier/"
const OLD := "res://old/"
const RIG_JSON := "res://out/data/rig.json"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min", "crowd"]
const REPORT := "res://report.json"


func _initialize() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	var report := {"levels": {}, "bones": [], "shapes": {}, "files": []}
	# เชดเดอร์: ข้อความเดิม ชื่อใหม่
	if not FileAccess.file_exists(SHADER_SRC):
		push_error("no shader at " + SHADER_SRC)
		return false
	var f := FileAccess.open(DST + "body.gdshader", FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(SHADER_SRC))
	f.close()
	var sh := load(DST + "body.gdshader") as Shader
	if sh == null:
		push_error("the shader does not load")
		return false
	report["files"].append("body.gdshader")
	# วัสดุ: ค่าที่ขั้นปั้นตั้งไว้ (ถ้ามี) บนเชดเดอร์ชื่อใหม่
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.resource_name = "soldier_body"
	var src_mat := load(SRC + "soldier_skin.tres") as ShaderMaterial if ResourceLoader.exists(SRC + "soldier_skin.tres") else null
	if src_mat != null:
		for u in sh.get_shader_uniform_list():
			var v: Variant = src_mat.get_shader_parameter(u["name"])
			if v != null:
				mat.set_shader_parameter(u["name"], v)
	if not _save(mat, "body_material.tres", 0, report):
		return false
	mat = load(DST + "body_material.tres") as ShaderMaterial
	# โครง (+ ค่าคงที่ของตัวขับจาก rig.json ของขั้นปั้น เป็น meta "soldier_rig" ของราก) + bind
	var src_rig := load(SRC + "rig.tscn") as PackedScene
	var skin: Resource = load(SRC + "skin.res")
	if src_rig == null or skin == null:
		push_error("missing rig.tscn or skin.res in " + SRC)
		return false
	var root := src_rig.instantiate()
	var sk := root.get_node_or_null("Skeleton3D") as Skeleton3D
	if sk == null:
		push_error("rig.tscn has no Skeleton3D")
		root.free()
		return false
	if FileAccess.file_exists(RIG_JSON):
		var rj: Variant = JSON.parse_string(FileAccess.get_file_as_string(RIG_JSON))
		if rj is Dictionary:
			var meta := {}
			for k in ["drivers", "keys", "bind_angles", "arm_keys", "shapes", "S", "H"]:
				if (rj as Dictionary).has(k):
					meta[k] = rj[k]
			root.set_meta("soldier_rig", meta)
			report["drivers"] = meta
	var ps := PackedScene.new()
	ps.pack(root)
	for i in sk.get_bone_count():
		report["bones"].append(sk.get_bone_name(i))
	report["motion_scale"] = sk.motion_scale
	root.free()
	if not _save(ps, "rig.tscn", 0, report) or not _save(skin, "skin.res", 0, report):
		return false
	# ผิวต่อระดับ: 1 พื้นผิว วัสดุของเกม บีบอัด
	for lv in LEVELS:
		var p := SRC + "body_%s.res" % lv
		if not ResourceLoader.exists(p):
			if lv != "crowd":
				push_error("missing " + p)
				return false
			continue
		var m := load(p) as ArrayMesh
		if m == null:
			push_error(p + " is not an ArrayMesh")
			return false
		for s in m.get_surface_count():
			m.surface_set_material(s, mat)
		if not _save(m, "body_%s.res" % lv, ResourceSaver.FLAG_COMPRESS, report):
			return false
		var arr := m.surface_get_arrays(0)
		var shapes := PackedStringArray()
		for i in m.get_blend_shape_count():
			shapes.append(String(m.get_blend_shape_name(i)))
		report["levels"][lv] = {"surfaces": m.get_surface_count(), "verts": (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			"tris": (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, "shapes": shapes.size(),
			"bytes": FileAccess.get_file_as_bytes(DST + "body_%s.res" % lv).size()}
		report["shapes"][lv] = shapes
	# ชั้นในของบาดแผล (ถ้าขั้นปั้นทำมา ต้องมาครบชุด): เชดเดอร์ชื่อใหม่ + วัสดุฝังในเมช ค่าเดิมของขั้นปั้น
	if ResourceLoader.exists(SRC + "inner_bone.res") or ResourceLoader.exists(SRC + "inner_flesh.res"):
		if not _inner(report):
			return false
	# ชุดท่าของทหารเอง (ถ้าขั้นปั้นทำมา)
	for name in ["clips.res", "soldier_clips.res", "humanoid_soldier.res"]:
		if ResourceLoader.exists(SRC + name):
			var lib := load(SRC + name) as AnimationLibrary
			if lib == null:
				push_error(SRC + name + " is not an AnimationLibrary")
				return false
			if not _save(lib, "clips.res", ResourceSaver.FLAG_COMPRESS, report):
				return false
			report["clips"] = {"from": name, "count": lib.get_animation_list().size()}
			break
	var out := FileAccess.open(REPORT, FileAccess.WRITE)
	out.store_string(JSON.stringify(report, " ", true))
	out.close()
	print(JSON.stringify(report["levels"], " ", true))
	return true


## ชั้นในของบาดแผล: inner.gdshader + inner_bone.res / inner_flesh.res (1 พื้นผิว วัสดุของเชดเดอร์ชื่อใหม่ บีบอัด)
func _inner(report: Dictionary) -> bool:
	if not FileAccess.file_exists(INNER_SHADER_SRC):
		push_error("no shader at " + INNER_SHADER_SRC)
		return false
	var f := FileAccess.open(DST + "inner.gdshader", FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(INNER_SHADER_SRC))
	f.close()
	var sh := load(DST + "inner.gdshader") as Shader
	if sh == null:
		push_error("the inner shader does not load")
		return false
	report["files"].append("inner.gdshader")
	report["inner"] = {}
	for lv in ["bone", "flesh"]:
		var p := SRC + "inner_%s.res" % lv
		var m := load(p) as ArrayMesh if ResourceLoader.exists(p) else null
		if m == null or m.get_surface_count() != 1:
			push_error("missing or not a one-surface ArrayMesh: " + p)
			return false
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.resource_name = "soldier_inner_" + lv
		var src_mat := m.surface_get_material(0) as ShaderMaterial
		if src_mat != null:
			mat.render_priority = src_mat.render_priority
			for u in sh.get_shader_uniform_list():
				var v: Variant = src_mat.get_shader_parameter(u["name"])
				if v != null:
					mat.set_shader_parameter(u["name"], v)
		m.surface_set_material(0, mat)
		if not _save(m, "inner_%s.res" % lv, ResourceSaver.FLAG_COMPRESS, report):
			return false
		var arr := m.surface_get_arrays(0)
		report["inner"][lv] = {"surfaces": 1, "verts": (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			"tris": (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3,
			"bytes": FileAccess.get_file_as_bytes(DST + "inner_%s.res" % lv).size()}
	return true


## บันทึก r ที่ DST/name แล้วใช้ UID เดิมของเกม (ไฟล์ชื่อเดียวกันใน res://old/) ถ้ามี
func _save(r: Resource, name: String, flags: int, report: Dictionary) -> bool:
	var path := DST + name
	var err := ResourceSaver.save(r, path, flags)
	if err != OK:
		push_error("cannot save %s: %s" % [path, error_string(err)])
		return false
	var old := OLD + name
	if FileAccess.file_exists(old):
		var uid := ResourceLoader.get_resource_uid(old)
		if uid != ResourceUID.INVALID_ID:
			ResourceSaver.set_uid(path, uid)
			if ResourceUID.has_id(uid):
				ResourceUID.set_id(uid, path)
			else:
				ResourceUID.add_id(uid, path)
	report["files"].append(name)
	return true
