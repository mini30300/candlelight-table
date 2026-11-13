@tool
extends EditorScenePostImport
## นำเข้าชุดโมเดล (assets/kits/*.glb): รวมทุกพื้นผิวของฟิกเกอร์เป็นพื้นผิวเดียว ใช้วัสดุเดียว
## (res://assets/shaders/figure_material.tres) จึงวาดตัวละ 1 draw call — สัญญาอยู่ใน assets/kits/CONTRACT.md
##  - COLOR   = สีจานสีของวัสดุเดิม (sRGB 0..1 ตรงกับ MINI.SOLID ของหน้าเว็บ)
##  - CUSTOM0 = (ธงทาสีได้ 0/1, ดัชนีจานสี 0..22, 0, 0) แบบ RGBA_FLOAT (ดัชนี = ลำดับวัสดุใน glTF/kits.json)
##  - เชื่อมจุดที่ตำแหน่ง+normal+กระดูกเท่ากัน (แรเงาแบบแบนคงเดิม) ; กระดูก/skin ของชุดที่มีโครงคงไว้
## ตั้งผ่าน [importer_defaults] ใน project.godot (import_script/path); พิมพ์ 1 บรรทัดต่อชุดไว้ตรวจนับ

const VERSION := 1                                           ## รุ่นของผลลัพธ์ (เก็บใน meta "kit")
const KITS_DIR := "res://assets/kits/"
const MANIFEST := KITS_DIR + "kits.json"
const MATERIAL_PATH := "res://assets/shaders/figure_material.tres"
const POS_Q := 100000.0                                      ## ควอนไทซ์ตำแหน่ง 0.01 มม. ไว้เทียบจุดซ้ำ
const NRM_Q := 1000.0                                        ## ควอนไทซ์ normal ไว้เทียบจุดซ้ำ

var _manifest: Dictionary = {}
var _natural: Dictionary = {}


func _post_import(scene: Node) -> Object:
	var src := get_source_file()
	if not src.begins_with(KITS_DIR):
		return scene                                         # ไม่ใช่ชุดโมเดล: ปล่อยตามเดิม
	var kit := src.get_file().get_basename()
	_load_manifest()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(scene, meshes)
	if meshes.size() != 1:
		push_error("kit_post_import %s: expected one MeshInstance3D, found %d" % [kit, meshes.size()])
		return scene
	var mi := meshes[0]
	var info := _merge(kit, mi)
	if info.is_empty():
		return scene
	_flatten(scene, kit)
	scene.set_meta("kit", info)
	print("kit_post_import %s: %d surfaces -> 1, %d -> %d verts, %d tris, %s" % [kit, info["surfaces"], info["verts_in"], info["verts"], info["tris"], "skinned" if info["skinned"] else "rigid"])
	return scene


func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


func _load_manifest() -> void:
	_natural.clear()
	_manifest.clear()
	if not FileAccess.file_exists(MANIFEST):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not (data is Dictionary):
		return
	for n in data.get("natural", []):
		_natural[String(n)] = true
	var kits: Variant = data.get("kits")
	if kits is Dictionary:
		_manifest = kits


## วัสดุเดิม -> {key, rgb(sRGB 0..255), tint}: จาก extras ของ glTF ก่อน แล้ว kits.json แล้วรายชื่อ NATURAL
func _palette_entry(kit: String, mesh: Mesh, s: int) -> Dictionary:
	var mat := mesh.surface_get_material(s)
	var key := ""
	if mesh is ArrayMesh:
		key = (mesh as ArrayMesh).surface_get_name(s)
	if key == "" and mat != null:
		key = mat.resource_name
	var entry := {"key": key, "rgb": [128, 128, 128], "tint": true}
	var found := false
	if mat != null and mat.has_meta("extras"):
		var ex: Variant = mat.get_meta("extras")
		if ex is Dictionary and ex.has("tint") and ex.has("rgb"):
			var rgb: Array = ex["rgb"]
			entry["rgb"] = [int(rgb[0]), int(rgb[1]), int(rgb[2])]
			entry["tint"] = bool(ex["tint"])
			if ex.has("key"):
				entry["key"] = String(ex["key"])
			found = true
	if not found and _manifest.has(kit):
		for m in _manifest[kit].get("materials", []):
			if String(m["key"]) == key:
				var rgb: Array = m["rgb"]
				entry["rgb"] = [int(rgb[0]), int(rgb[1]), int(rgb[2])]
				entry["tint"] = bool(m["tint"])
				found = true
				break
	if not found:
		if mat is BaseMaterial3D:
			var c: Color = (mat as BaseMaterial3D).albedo_color
			entry["rgb"] = [c.r8, c.g8, c.b8]
		entry["tint"] = not _natural.has(key)
		push_warning("kit_post_import %s: material '%s' has no extras/manifest entry; tint=%s from NATURAL" % [kit, key, str(entry["tint"])])
	return entry


## รวมพื้นผิวทั้งหมดของ mi เป็น ArrayMesh พื้นผิวเดียว; คืน meta ของผลลัพธ์ ({} เมื่อผิดพลาด)
func _merge(kit: String, mi: MeshInstance3D) -> Dictionary:
	var mesh := mi.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("kit_post_import %s: mesh has no surfaces" % kit)
		return {}
	var skinned := mi.skin != null
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var cust := PackedFloat32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var lookup: Dictionary = {}                               # Vector3i(ตำแหน่ง) -> { Vector4i(normal, พื้นผิว*256+กระดูก: กระดูกไม่เกิน 255): ดัชนีใหม่ }
	var palette: Array = []                                   # ดัชนีจานสี = ลำดับใน kits.json materials[] (glTF อาจขาดพื้นผิวที่หน้าเสื่อมหมด)
	var slot_of: Dictionary = {}                              # key -> ดัชนีจานสี
	if _manifest.has(kit):
		for m in _manifest[kit].get("materials", []):
			var mrgb: Array = m["rgb"]
			slot_of[String(m["key"])] = palette.size()
			palette.append({"key": String(m["key"]), "rgb": [int(mrgb[0]), int(mrgb[1]), int(mrgb[2])], "tint": bool(m["tint"])})
	var verts_in := 0
	var aabb := AABB()
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			push_error("kit_post_import %s: surface %d is not triangles" % [kit, s])
			return {}
		var found := _palette_entry(kit, mesh, s)
		var key := String(found["key"])
		if not slot_of.has(key):                              # ไม่มีใน kits.json: ต่อท้ายตามลำดับพื้นผิว
			slot_of[key] = palette.size()
			palette.append(found)
		var slot: int = slot_of[key]
		var entry: Dictionary = palette[slot]
		var rgb: Array = entry["rgb"]
		var colour := Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
		var custom := PackedFloat32Array([1.0 if entry["tint"] else 0.0, float(slot), 0.0, 0.0])
		var arr := mesh.surface_get_arrays(s)
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var sb: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var sw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var si: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if sn.size() != sv.size():
			push_error("kit_post_import %s: surface %d has no normals" % [kit, s])
			return {}
		if skinned and (sb.size() != sv.size() * 4 or sw.size() != sv.size() * 4):
			push_error("kit_post_import %s: surface %d bones/weights are not 4 per vertex" % [kit, s])
			return {}
		if si.is_empty():
			si.resize(sv.size())
			for i in sv.size():
				si[i] = i
		verts_in += sv.size()
		var remap := PackedInt32Array()
		remap.resize(sv.size())
		remap.fill(-1)
		for i in si.size():
			var o := si[i]
			if remap[o] < 0:
				var v := sv[o]
				var n := sn[o]
				var bone := sb[o * 4] if skinned else 0
				var pk := Vector3i(int(roundf(v.x * POS_Q)), int(roundf(v.y * POS_Q)), int(roundf(v.z * POS_Q)))
				var nk := Vector4i(int(roundf(n.x * NRM_Q)), int(roundf(n.y * NRM_Q)), int(roundf(n.z * NRM_Q)), s * 256 + bone)
				var bucket: Dictionary = lookup.get(pk, {})
				if bucket.has(nk):
					remap[o] = bucket[nk]
				else:
					var ni := pos.size()
					pos.append(v)
					nrm.append(n)
					col.append(colour)
					cust.append_array(custom)
					if skinned:
						for k in 4:
							bones.append(sb[o * 4 + k])
							weights.append(sw[o * 4 + k])
					if ni == 0:
						aabb = AABB(v, Vector3.ZERO)
					else:
						aabb = aabb.expand(v)
					bucket[nk] = ni
					lookup[pk] = bucket
					remap[o] = ni
			idx.append(remap[o])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_CUSTOM0] = cust
	arrays[Mesh.ARRAY_INDEX] = idx
	if skinned:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
	# RGBA_FLOAT: ใน Compatibility renderer 4.7 แบบ RGBA8_UNORM ไม่ถึง vertex shader และ RGBA_HALF มาแค่ 2 ช่อง (ทดสอบแล้ว)
	var flags: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	if not skinned:
		flags |= Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES            # ชุดแข็ง: บีบ attribute ได้ (skin ต้องการความละเอียดเต็ม)
	var out := ArrayMesh.new()
	out.resource_name = kit
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	out.surface_set_name(0, kit)
	var material: Material = load(MATERIAL_PATH)
	if material == null:
		push_error("kit_post_import %s: cannot load %s" % [kit, MATERIAL_PATH])
		return {}
	out.surface_set_material(0, material)
	mi.mesh = out
	mi.material_override = null
	return {
		"key": kit, "version": VERSION, "skinned": skinned, "surfaces": mesh.get_surface_count(),
		"verts_in": verts_in, "verts": pos.size(), "tris": idx.size() / 3, "palette": palette,
		"aabb": [aabb.position.x, aabb.position.y, aabb.position.z, aabb.end.x, aabb.end.y, aabb.end.z],
	}


## glTF มี node ราก "<kit>" ซ้อนใต้รากของฉาก: ยกลูกขึ้นมาแล้วตัดชั้นนั้นทิ้ง รากชื่อ = ชื่อชุด
func _flatten(scene: Node, kit: String) -> void:
	if scene.get_child_count() == 1:
		var inner := scene.get_child(0)
		if inner.get_class() == "Node3D" and (inner as Node3D).transform.is_equal_approx(Transform3D.IDENTITY):
			for c in inner.get_children().duplicate():
				c.owner = null                               # ย้ายโดยไม่ให้ owner ค้างระหว่างทาง (ลูกหลานยังชี้ราก)
				inner.remove_child(c)
				scene.add_child(c)
				c.owner = scene
			scene.remove_child(inner)
			inner.free()
	scene.name = kit
