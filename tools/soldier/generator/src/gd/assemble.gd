extends SceneTree
## ประกอบทหารเป็นทรัพยากร Godot (รันแบบ headless): rig.tscn (โครง 33 กระดูก) + body_<ระดับ>.res (ผิว 1 พื้นผิว/ระดับ)
## + skin.res + เมชชั้นโครงกระดูก/กล้ามเนื้อสำหรับทำภาพ ; อ่านไฟล์ไบนารีจาก out/data (สร้างโดย build.py)

const DATA := "res://out/data/"
const OUT := "res://out/godot/"


static func read_bin(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	var hl := f.get_32()
	var head: Dictionary = JSON.parse_string(f.get_buffer(hl).get_string_from_utf8())
	var base := 4 + hl
	var out := {"meta": head["meta"]}
	for a in head["arrays"]:
		f.seek(base + int(a["offset"]))
		var buf := f.get_buffer(int(a["count"]) * 4)
		out[a["name"]] = buf.to_float32_array() if a["type"] == "f32" else buf.to_int32_array()
	return out


static func v3(a: PackedFloat32Array) -> PackedVector3Array:
	var n := a.size() / 3
	var out := PackedVector3Array()
	out.resize(n)
	for i in n:
		out[i] = Vector3(a[3 * i], a[3 * i + 1], a[3 * i + 2])
	return out


static func cols(a: PackedFloat32Array) -> PackedColorArray:
	var n := a.size() / 4
	var out := PackedColorArray()
	out.resize(n)
	for i in n:
		out[i] = Color(a[4 * i], a[4 * i + 1], a[4 * i + 2], a[4 * i + 3])
	return out


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA + "rig.json"))
	# ---- โครงกระดูก ----
	var root := Node3D.new()
	root.name = "Soldier"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	sk.owner = root
	var bones: Array = rig["bones"]
	for b in bones:
		sk.add_bone(b["name"])
	for i in bones.size():
		var b: Dictionary = bones[i]
		if b["parent"] != null:
			sk.set_bone_parent(i, sk.find_bone(b["parent"]))
		var q: Array = b["rest_q"]
		var p: Array = b["rest_pos"]
		sk.set_bone_rest(i, Transform3D(Basis(Quaternion(q[0], q[1], q[2], q[3])), Vector3(p[0], p[1], p[2])))
	sk.reset_bone_poses()
	sk.motion_scale = float(rig["S"])
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, OUT + "rig.tscn")
	# ---- Skin (bind = ผกผันของท่า A ตอนปั้น) ----
	var skin := Skin.new()
	for b in bones:
		var m: Array = b["bind"]
		var r0: Array = m[0]
		var r1: Array = m[1]
		var r2: Array = m[2]
		var t := Transform3D(Basis(Vector3(r0[0], r1[0], r2[0]), Vector3(r0[1], r1[1], r2[1]), Vector3(r0[2], r1[2], r2[2])),
			Vector3(r0[3], r1[3], r2[3]))
		skin.add_named_bind(b["name"], t)
	ResourceSaver.save(skin, OUT + "skin.res")
	# ---- วัสดุ ----
	var sh := load("res://src/gd/soldier_skin.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.resource_name = "soldier_skin"
	ResourceSaver.save(mat, OUT + "soldier_skin.tres")
	var lmat := ShaderMaterial.new()
	lmat.shader = load("res://src/gd/layer.gdshader") as Shader
	ResourceSaver.save(lmat, OUT + "layer.tres")
	# ---- ผิวแต่ละระดับ ----
	var report := {}
	for lv in ["hi", "mid", "lo", "min", "hilbs"]:
		var path := DATA + "body_%s.bin" % lv
		if not FileAccess.file_exists(path):
			continue
		var d := read_bin(path)
		var meta: Dictionary = d["meta"]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v3(d["pos"])
		arr[Mesh.ARRAY_NORMAL] = v3(d["nrm"])
		arr[Mesh.ARRAY_COLOR] = cols(d["col"])
		arr[Mesh.ARRAY_CUSTOM0] = d["cus"]
		arr[Mesh.ARRAY_BONES] = d["bones"]
		arr[Mesh.ARRAY_WEIGHTS] = d["weights"]
		arr[Mesh.ARRAY_INDEX] = d["idx"]
		var am := ArrayMesh.new()
		am.resource_name = "soldier_body_" + lv
		var shapes: Array = meta.get("shapes", [])
		var bsa := []
		if not shapes.is_empty():
			am.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
			for s in shapes:
				am.add_blend_shape(s)
				var b := []
				b.resize(Mesh.ARRAY_MAX)
				b[Mesh.ARRAY_VERTEX] = v3(d["bs_pos_" + s])
				b[Mesh.ARRAY_NORMAL] = v3(d["bs_nrm_" + s])
				bsa.append(b)
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, bsa, {}, flags)
		am.surface_set_material(0, mat)
		var outp := OUT + "body_%s.res" % lv
		ResourceSaver.save(am, outp, ResourceSaver.FLAG_COMPRESS)
		report[lv] = {"verts": int(meta["verts"]), "tris": int(meta["tris"]), "shapes": shapes.size(),
			"bytes": FileAccess.get_file_as_bytes(outp).size()}
		print("body_%s: %d verts %d tris %d shapes %d bytes" % [lv, meta["verts"], meta["tris"], shapes.size(), report[lv]["bytes"]])
	# ---- ชั้นโครงกระดูก (ผูกแข็งกับกระดูก -> ขยับตามโครงได้ทุกท่า) ----
	if FileAccess.file_exists(DATA + "skeleton.bin"):
		var d := read_bin(DATA + "skeleton.bin")
		var pos := v3(d["pos"])
		var bidx: PackedInt32Array = d["bone"]
		var bb := PackedInt32Array()
		var ww := PackedFloat32Array()
		bb.resize(pos.size() * 4)
		ww.resize(pos.size() * 4)
		for i in pos.size():
			var b := bidx[i]
			bb[4 * i] = b
			ww[4 * i] = 1.0
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_COLOR] = cols(d["col"])
		arr[Mesh.ARRAY_BONES] = bb
		arr[Mesh.ARRAY_WEIGHTS] = ww
		arr[Mesh.ARRAY_INDEX] = d["idx"]
		var st := SurfaceTool.new()
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		st.create_from(am, 0)
		st.generate_normals()
		var am2 := st.commit()
		am2.surface_set_material(0, lmat)
		ResourceSaver.save(am2, OUT + "skeleton_mesh.res", ResourceSaver.FLAG_COMPRESS)
		print("skeleton_mesh: %d verts" % pos.size())
	# ---- ชั้นกล้ามเนื้อ (เมชนิ่งต่อท่า) ----
	var da := DirAccess.open(DATA)
	for fn in da.get_files():
		if not (fn.begins_with("muscles_") and fn.ends_with(".bin")):
			continue
		var d := read_bin(DATA + fn)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v3(d["pos"])
		arr[Mesh.ARRAY_COLOR] = cols(d["col"])
		arr[Mesh.ARRAY_INDEX] = d["idx"]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var st := SurfaceTool.new()
		st.create_from(am, 0)
		st.generate_normals()
		var am2 := st.commit()
		am2.surface_set_material(0, lmat)
		ResourceSaver.save(am2, OUT + fn.replace(".bin", ".res"), ResourceSaver.FLAG_COMPRESS)
		print(fn, " ok")
	var fo := FileAccess.open(DATA + "godot_assets.json", FileAccess.WRITE)
	fo.store_string(JSON.stringify(report, " "))
	quit()
