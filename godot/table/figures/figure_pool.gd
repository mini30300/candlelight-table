class_name FigurePool
extends Node3D
## กองฟิกเกอร์ v1: ชั้นใกล้ = ฉากชุดโมเดลพร้อมโครงกระดูก (skinned; โควตาต่อระดับตาม ARCHITECTURE §6)
## ชั้นกลาง/ไกล = MultiMesh หนึ่งชิ้นต่อชุดโมเดล (เมชท่ายืน; บน lo/min ใช้เมชลดรูปจาก ImporterMesh.generate_lods ตอนโหลด
## ให้เข้างบสามเหลี่ยม) · จัดชั้นตอน build/apply_level เท่านั้น ไม่มีงานต่อเฟรม (ไม่มี _process)
## ชุดโมเดลมาจาก kit_post_import.gd (assets/kits/CONTRACT.md): MeshInstance3D เดียว ผิวเดียว วัสดุร่วม figure_material.tres
## (COLOR = สีชุด sRGB, CUSTOM0 = ธงทาสี/ช่องจานสี) จึง 1 draw call ต่อตัว skinned และ 1 ต่อชุดใน MultiMesh
## MultiMesh ต้อง use_colors = true สีขาว (ไม่งั้นตัวดำ) และ use_custom_data x = -1 = ยังไม่มีงานสี (ที่ทาสีของเจ้าของ R7)
## ฟิกเกอร์ไม่ย้อมสีทีม (มติเจ้าของ 7 ต.ค.): สีทีมคือวงแหวน Rings · วัสดุทุกชั้นผ่าน _figure_material() จุดเดียว

## โควตาชั้น skinned ต่อระดับ (§6): min = หน่วยที่เลือก + ผู้เดิน ≤ 8
const SKINNED_CAP := {"hi": 160, "mid": 80, "lo": 24, "min": 8}
## ดัชนี LOD ของชั้น MultiMesh ต่อระดับ: 0 = เมชที่ import, 1 ≈ ครึ่ง, 2 ≈ หนึ่งในห้า
const RIGID_LOD := {"hi": 0, "mid": 0, "lo": 1, "min": 2}
const MATERIAL_PATH := "res://assets/shaders/figure_material.tres"
const NO_PAINT := Color(-1.0, 0.0, 0.0, 0.0)   # INSTANCE_CUSTOM.x < 0 = สีชุดตามเดิม
const STRESS_RIGID := 400
const STRESS_SKINNED := 100
const LOD_MERGE_ANGLE := 60.0
const LOD_SPLIT_ANGLE := 25.0
const CUSTOM_FORMAT_MASK: int = (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
	| (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) \
	| (Mesh.ARRAY_FORMAT_CUSTOM_MASK << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)


class Figure:
	var kit := ""
	var team := 0
	var pos := Vector3.ZERO
	var yaw := 0.0
	var radius := 0.62
	var stress := false          # ตัวทดสอบหนัก
	var force_skinned := false   # ทดสอบหนัก: skinned เสมอ ไม่นับโควตา
	var skinned := false         # ชั้นปัจจุบัน (ผลของ build)


class KitData:
	var name := ""
	var scene: PackedScene
	var skinned := false
	var tris := 0
	var lods: Array[Mesh] = []            # [เมชที่ import, ลด 1, ลด 2]
	var lod_tris := PackedInt32Array()


var level := "mid"
var figures: Array[Figure] = []

var _kits: Dictionary = {}          # ชื่อ → KitData (null เมื่อโหลดไม่ได้)
var _near: Array[Node3D] = []
var _mmis: Dictionary = {}          # ชื่อชุด → MultiMeshInstance3D
var _material: Material
var _material_is_shader := false
var _stress_on := false
var _base_count := 0
var _skinned_count := 0
var _tris := 0


static func make(kit: String, team: int, pos: Vector3, yaw: float, radius: float) -> Figure:
	var f := Figure.new()
	f.kit = kit
	f.team = team
	f.pos = pos
	f.yaw = yaw
	f.radius = radius
	return f


## ชุดโมเดลโหลดได้ไหม (โหลดและเตรียม LOD ไว้ในแคชเลย)
func kit_available(kit: String) -> bool:
	return _kit(kit) != null


func kit_is_skinned(kit: String) -> bool:
	var k := _kit(kit)
	return k != null and k.skinned


## ตั้งรายการฟิกเกอร์หลัก (ยังไม่สร้างโหนด; เรียก build ต่อ)
func set_figures(list: Array[Figure]) -> void:
	figures = list.duplicate()
	_base_count = figures.size()
	_stress_on = false


## สร้างทุกชั้นใหม่สำหรับระดับ l; ตัวที่ใกล้กล้องที่สุดได้ชั้น skinned ตามโควตา
func build(l: String, camera_pos: Vector3) -> void:
	level = l if SKINNED_CAP.has(l) else "mid"
	_clear_nodes()
	var cap: int = SKINNED_CAP[level]
	var lod_index: int = RIGID_LOD[level]
	var order: Array[int] = []
	for i in figures.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return figures[a].pos.distance_squared_to(camera_pos) < figures[b].pos.distance_squared_to(camera_pos))
	var near_used := 0
	var rigid: Dictionary = {}    # ชื่อชุด → Array[Figure]
	_skinned_count = 0
	_tris = 0
	for i in order:
		var f := figures[i]
		var kit := _kit(f.kit)
		f.skinned = false
		if kit == null:
			continue
		var want_skinned := kit.skinned and (f.force_skinned or near_used < cap)
		if want_skinned:
			var node := _spawn_skinned(kit, f)
			if node != null:
				f.skinned = true
				_skinned_count += 1
				_tris += kit.tris
				if not f.force_skinned:
					near_used += 1
				continue
		if not rigid.has(f.kit):
			rigid[f.kit] = []
		(rigid[f.kit] as Array).append(f)
	for name in rigid:
		var kit: KitData = _kits[name]
		var list: Array = rigid[name]
		var li := mini(lod_index, kit.lods.size() - 1)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kit_" + name
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true          # ต้องเปิดและเป็นขาว ไม่งั้น Compatibility วาดตัวดำ (CONTRACT.md §3)
		mm.use_custom_data = true     # INSTANCE_CUSTOM.x = แถวงานสี; -1 = สีชุด
		mm.mesh = kit.lods[li]
		mm.instance_count = list.size()
		for j in list.size():
			var f: Figure = list[j]
			mm.set_instance_transform(j, Transform3D(Basis.from_euler(Vector3(0.0, f.yaw, 0.0)), f.pos))
			mm.set_instance_color(j, Color.WHITE)
			mm.set_instance_custom_data(j, NO_PAINT)
		mmi.multimesh = mm
		if not _material_is_shader:
			mmi.material_override = _figure_material()
		add_child(mmi)
		_mmis[name] = mmi
		_tris += list.size() * kit.lod_tris[li]


func apply_level(l: String, camera_pos: Vector3) -> void:
	build(l, camera_pos)


## ทดสอบหนัก: เพิ่มฟิกเกอร์แข็ง 400 + skinned 100 กระจายทั่วโต๊ะ (ไม่นับโควตา) หรือเอาออก
func set_stress(on: bool, camera_pos: Vector3, half_w: float = 23.0, half_d: float = 16.0) -> void:
	if on == _stress_on:
		return
	_stress_on = on
	figures.resize(_base_count)
	if on:
		var skinned_kits: Array[String] = []
		var all_kits: Array[String] = []
		for name in _kits:
			if _kits[name] == null:
				continue
			all_kits.append(name)
			if (_kits[name] as KitData).skinned:
				skinned_kits.append(name)
		if all_kits.is_empty():
			return
		if skinned_kits.is_empty():
			skinned_kits = all_kits
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for i in STRESS_RIGID + STRESS_SKINNED:
			var is_skinned := i >= STRESS_RIGID
			var name: String = skinned_kits[i % skinned_kits.size()] if is_skinned else all_kits[i % all_kits.size()]
			var f := make(name, i % 8, Vector3(rng.randf_range(-half_w, half_w), 0.0, rng.randf_range(-half_d, half_d)), rng.randf() * TAU, 0.62)
			f.stress = true
			f.force_skinned = is_skinned
			figures.append(f)
	build(level, camera_pos)


func stress_on() -> bool:
	return _stress_on


## แสงต่อจุดยอด (lo/min) หรือต่อพิกเซล — ภาพเท่ากันสำหรับชุดแรเงาแบน (CONTRACT.md §3)
func set_per_vertex(on: bool) -> void:
	var m := _figure_material()
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("per_vertex", on)
	elif m is BaseMaterial3D:
		(m as BaseMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if on else BaseMaterial3D.SHADING_MODE_PER_PIXEL


## แสงของฟิกเกอร์ทุกตัว: ทิศไปหาดวงอาทิตย์ (world) สีแดด สีแสงรอบ — ตั้งครั้งเดียวจาก TableView
func set_lighting(sun_dir: Vector3, sun_colour: Color, ambient: Color) -> void:
	var m := _figure_material()
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		sm.set_shader_parameter("sun_dir", sun_dir)
		sm.set_shader_parameter("sun_colour", Vector3(sun_colour.r, sun_colour.g, sun_colour.b))
		sm.set_shader_parameter("ambient_colour", Vector3(ambient.r, ambient.g, ambient.b))


## ตัวเลขสำหรับหน้าตรวจการ์ดจอและเทสงบ
func counts() -> Dictionary:
	return {"figures": figures.size(), "skinned": _skinned_count, "rigid": figures.size() - _skinned_count,
		"kits": _mmis.size(), "tris": _tris}


# ---- ที่เดียวของวัสดุ ----

## วัสดุร่วมของฟิกเกอร์ทุกชั้น: figure_material.tres (figure.gdshader ของ R0-D); ไม่มีไฟล์นั้นก็ใช้ StandardMaterial3D
## สีจากจุดยอดแทน (ภาพเท่ากัน ยกเว้นงานสี)
func _figure_material() -> Material:
	if _material == null:
		var res: Resource = load(MATERIAL_PATH) if ResourceLoader.exists(MATERIAL_PATH) else null
		if res is ShaderMaterial:
			_material = res
			_material_is_shader = true
		else:
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.roughness = 0.9
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			_material = m
			_material_is_shader = false
	return _material


# ---- โหลดชุดโมเดล ----

func _kit(name: String) -> KitData:
	if _kits.has(name):
		return _kits[name]
	var data := _load_kit(name)
	_kits[name] = data
	return data


func _load_kit(name: String) -> KitData:
	var res: Resource = load(KitLibrary.KITS_DIR + "/" + name + ".glb")
	if not res is PackedScene:
		push_warning("figure_pool: kit not loadable: " + name)
		return null
	var scene := res as PackedScene
	var inst := scene.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(inst, meshes)
	if meshes.is_empty():
		inst.free()
		push_warning("figure_pool: kit has no mesh: " + name)
		return null
	if meshes.size() > 1:
		push_warning("figure_pool: kit %s has %d meshes; the MultiMesh tier draws the first" % [name, meshes.size()])
	var mi := meshes[0]
	var mesh: Mesh = mi.mesh
	if not _relative_transform(mi, inst).is_equal_approx(Transform3D()):
		push_warning("figure_pool: kit %s mesh is offset from its root; the MultiMesh tier ignores that" % name)
	var kit := KitData.new()
	kit.name = name
	kit.scene = scene
	kit.skinned = mi.skin != null
	kit.lods.append(mesh)
	kit.tris = _mesh_tris(mesh)
	kit.lod_tris.append(kit.tris)
	inst.free()
	_append_lods(kit, mesh)
	return kit


## เมชลดรูปสำหรับชั้น MultiMesh บน lo/min: ImporterMesh.generate_lods (meshoptimizer) จากผิวที่ import มา
## แล้วคัดเฉพาะจุดยอดที่ใช้ (ไม่มีกระดูก; COLOR/CUSTOM0 ติดไปด้วย วัสดุเดิม)
func _append_lods(kit: KitData, mesh: Mesh) -> void:
	if mesh.get_surface_count() < 1:
		return
	var src: Array = mesh.surface_get_arrays(0)
	var fmt: int = mesh.surface_get_format(0)
	var flags: int = fmt & (CUSTOM_FORMAT_MASK | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	var material := mesh.surface_get_material(0)
	src[Mesh.ARRAY_BONES] = null
	src[Mesh.ARRAY_WEIGHTS] = null
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, src, [], {}, null, "", flags)
	im.generate_lods(LOD_MERGE_ANGLE, LOD_SPLIT_ANGLE, [])
	var n := im.get_surface_lod_count(0)
	for l in mini(n, 2):
		var idx := im.get_surface_lod_indices(0, l)
		if idx.is_empty():
			break
		kit.lods.append(_compact(src, idx, flags, material))
		kit.lod_tris.append(idx.size() / 3)
	# ไม่มี LOD (แพลตฟอร์มที่ไม่มี meshoptimizer): ใช้เมชเต็มแทน
	while kit.lods.size() < 3:
		kit.lods.append(kit.lods[kit.lods.size() - 1])
		kit.lod_tris.append(kit.lod_tris[kit.lod_tris.size() - 1])


## ArrayMesh ใหม่จากดัชนี idx โดยเก็บเฉพาะจุดยอดที่ใช้; ทุก array ที่มี (ตำแหน่ง normal สี custom …) ถูก remap ตาม stride ของมัน
static func _compact(src: Array, idx: PackedInt32Array, flags: int, material: Material) -> ArrayMesh:
	var vcount: int = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap := PackedInt32Array()
	remap.resize(vcount)
	remap.fill(-1)
	var keep := PackedInt32Array()
	var index := PackedInt32Array()
	for i in idx:
		if remap[i] < 0:
			remap[i] = keep.size()
			keep.append(i)
		index.append(remap[i])
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	for ai in Mesh.ARRAY_MAX:
		if ai == Mesh.ARRAY_INDEX or src[ai] == null:
			continue
		var arr: Variant = src[ai]
		var stride: int = maxi(1, arr.size() / vcount)
		var dst: Variant = arr.slice(0, 0)
		for k in keep:
			if stride == 1:
				dst.append(arr[k])
			else:
				for s in stride:
					dst.append(arr[k * stride + s])
		out[ai] = dst
	out[Mesh.ARRAY_INDEX] = index
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, flags)
	if material != null:
		am.surface_set_material(0, material)
	return am


static func _mesh_tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n += ((idx as PackedInt32Array).size() if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty() else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


static func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


## transform ของโหนดเทียบกับรากฉาก (ไม่ต้องอยู่ใน tree)
static func _relative_transform(n: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


# ---- ชั้นใกล้ ----

## ฉากชุดโมเดลตามที่ import มา (ผิวเดียว วัสดุร่วม = 1 draw call) วางที่ตำแหน่ง/ทิศของฟิกเกอร์
func _spawn_skinned(kit: KitData, f: Figure) -> Node3D:
	var inst := kit.scene.instantiate()
	if not inst is Node3D:
		inst.free()
		return null
	var node := inst as Node3D
	if not _material_is_shader:
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(node, meshes)
		for mi in meshes:
			mi.material_override = _figure_material()
	node.transform = Transform3D(Basis.from_euler(Vector3(0.0, f.yaw, 0.0)), f.pos)
	add_child(node)
	_near.append(node)
	return node


func _clear_nodes() -> void:
	for n in _near:
		n.queue_free()
	_near.clear()
	for name in _mmis:
		(_mmis[name] as Node).queue_free()
	_mmis.clear()
	_skinned_count = 0
	_tris = 0
