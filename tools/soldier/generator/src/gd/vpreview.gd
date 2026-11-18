extends SceneTree
## ภาพตัวอย่างร่างหลากหลาย: เมชนิ่งจาก .bin (pos nrm col cus idx) + เชดเดอร์ผิวทหาร (ไฟบนของเกมตามค่าเริ่ม)
## BINS = ไฟล์คั่นด้วย , ; VIEWS = head | body ; OUT_DIR

var cam: Camera3D


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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _frame_view(centre: Vector3, height: float, yaw_deg: float, pitch_deg: float) -> void:
	var d := height / (2.0 * tan(deg_to_rad(cam.fov * 0.5))) * 1.08
	var cp := cos(deg_to_rad(pitch_deg))
	var dir := Vector3(sin(deg_to_rad(yaw_deg)) * cp, sin(deg_to_rad(pitch_deg)), cos(deg_to_rad(yaw_deg)) * cp)
	cam.position = centre + dir * d
	cam.look_at(centre, Vector3.UP)


func _initialize() -> void:
	RenderingServer.set_default_clear_color(Color(0.16, 0.17, 0.19))
	cam = Camera3D.new()
	cam.fov = 24.0
	get_root().add_child(cam)
	cam.current = true
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_environment("OUT_DIR")
	DirAccess.make_dir_recursive_absolute(out)
	var views := OS.get_environment("VIEWS")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/gd/soldier_skin.gdshader") as Shader
	for path in OS.get_environment("BINS").split(","):
		var d := read_bin(path)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v3(d["pos"])
		arr[Mesh.ARRAY_NORMAL] = v3(d["nrm"])
		arr[Mesh.ARRAY_COLOR] = cols(d["col"])
		arr[Mesh.ARRAY_CUSTOM0] = d["cus"]
		arr[Mesh.ARRAY_INDEX] = d["idx"]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = mat
		get_root().add_child(mi)
		var tag := path.get_file().get_basename()
		var shots := []
		if views == "head":
			shots = [["face", Vector3(0, 1.650, 0.03), 0.30, 0.0, 0.0], ["face34", Vector3(0, 1.650, 0.03), 0.30, 35.0, 0.0],
				["side", Vector3(0, 1.650, 0.0), 0.32, 90.0, 0.0], ["back", Vector3(0, 1.650, -0.02), 0.32, 160.0, 5.0]]
		else:
			shots = [["front", Vector3(0, 0.90, 0), 1.95, 0.0, 0.0], ["side", Vector3(0, 0.90, 0), 1.95, 90.0, 0.0],
				["back", Vector3(0, 0.90, 0), 1.95, 180.0, 0.0], ["torso", Vector3(0, 1.20, 0.02), 0.70, 20.0, 0.0],
				["torso_side", Vector3(0, 1.10, 0.0), 0.85, 90.0, 0.0]]
		var cs := OS.get_environment("SHOTS")
		if cs != "":
			# มุมกำหนดเอง: "ชื่อ:cx,cy,cz,สูง,หัน,ก้ม;..."
			shots = []
			for it in cs.split(";"):
				var kv := it.split(":")
				var f := kv[1].split_floats(",")
				shots.append([kv[0], Vector3(f[0], f[1], f[2]), f[3], f[4], f[5]])
		for s in shots:
			_frame_view(s[1], s[2], s[3], s[4])
			await _frames(3)
			get_root().get_texture().get_image().save_png(out + "/" + tag + "_" + s[0] + ".png")
		mi.queue_free()
		await _frames(1)
		print("rendered ", tag)
	quit()
