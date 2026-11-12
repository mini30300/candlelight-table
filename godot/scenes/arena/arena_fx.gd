class_name ArenaFx
extends MultiMeshInstance3D
## เอฟเฟกต์ปืนของอารีน่า (ARENA_SPEC §6.4): MultiMesh เดียว (1 draw call) ของแผ่นสี่เหลี่ยม: รอยกระสุน 0.03 ม. จากปากกระบอก
## ถึงจุดโดน (0.06 วิ) ประกายปากกระบอกสองแผ่นไขว้ (0.05 วิ) และสะเก็ดที่จุดโดน (0.15 วิ: hi 8, mid 5, lo 3; min แผ่นเดียว 0.1 วิ)
## hi/mid วัสดุบวกแสง (blend_add) ไม่รับแสง, lo/min วัสดุทึบไม่รับแสง · ทิศสะเก็ดจาก RNG ที่ตั้ง seed ไว้ (เทสซ้ำได้)
## พิกัดโลก (top_level) · ไม่มีเอฟเฟกต์ = ซ่อนโหนด (ไม่มี draw call) · งานต่อเฟรม: _process เฉพาะตอนมีเอฟเฟกต์ค้างอยู่ แล้วปิดตัวเอง

const POOL := 48
const TRACER_W := 0.03
const TRACER_LIFE := 0.06
const FLASH_LIFE := 0.05
const FLASH_SIZE := 0.22
const SPARK_LIFE := 0.15
const SPARK_SIZE := 0.05
const SPARK_SPEED := 3.5
const IMPACT_LIFE := 0.1
const IMPACT_SIZE := 0.12
const SPARKS := {"hi": 8, "mid": 5, "lo": 3, "min": 0}
const TRACER_COL := Color(1.0, 0.86, 0.5)
const FLASH_COL := Color(1.0, 0.78, 0.35)
const SPARK_COL := Color(1.0, 0.7, 0.3)

var level := "mid"
var additive := true
var rng := RandomNumberGenerator.new()
## กล้องที่ใช้หันแผ่นรอยกระสุนให้เห็นหน้ากว้าง
var view: Camera3D

var _items: Array[Dictionary] = []   # {"kind", "t", "life", "a", "b", "vel", "size"}
var _add_mat: StandardMaterial3D
var _plain_mat: StandardMaterial3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _quad()
	mm.instance_count = POOL
	mm.visible_instance_count = 0
	multimesh = mm
	visible = false
	# กล่องตัดภาพครอบทั้งอารีน่า (แผ่นกระจายไปทั่ว ตำแหน่ง instance ไม่ใช่ของโหนด)
	custom_aabb = AABB(Vector3(-40.0, -2.0, -60.0), Vector3(80.0, 14.0, 80.0))
	apply_level(level)
	set_process(false)


func apply_level(l: String) -> void:
	level = l if SPARKS.has(l) else "mid"
	additive = level == "hi" or level == "mid"
	if additive:
		if _add_mat == null:
			_add_mat = _material(true)
		material_override = _add_mat
	else:
		if _plain_mat == null:
			_plain_mat = _material(false)
		material_override = _plain_mat


func reseed(s: int) -> void:
	rng.seed = s


## นัดหนึ่ง: ประกายที่ปากกระบอก รอยกระสุนถึงจุด to และสะเก็ดที่จุดโดน (hit = โดนอะไรจริง ไม่ใช่ยิงลอยไปสุดระยะ)
func shot(from: Vector3, to: Vector3, hit: bool, normal: Vector3 = Vector3.UP) -> void:
	_add({"kind": &"tracer", "life": TRACER_LIFE, "a": from, "b": to})
	_add({"kind": &"flash", "life": FLASH_LIFE, "a": from, "b": to, "turn": 0.0})
	_add({"kind": &"flash", "life": FLASH_LIFE, "a": from, "b": to, "turn": PI * 0.5})
	if hit:
		impact(to, normal)


## สะเก็ดที่จุดโดน (ใช้กับหมัด/ดาบด้วย)
func impact(at: Vector3, normal: Vector3 = Vector3.UP) -> void:
	var n := int(SPARKS[level])
	if n <= 0:
		_add({"kind": &"impact", "life": IMPACT_LIFE, "a": at})
		return
	var nn := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	for i in n:
		var d := (nn + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 1.0), rng.randf_range(-1.0, 1.0)) * 0.9).normalized()
		_add({"kind": &"spark", "life": SPARK_LIFE, "a": at, "vel": d * SPARK_SPEED * rng.randf_range(0.6, 1.0)})


func alive() -> int:
	return _items.size()


func clear() -> void:
	_items.clear()
	multimesh.visible_instance_count = 0
	visible = false
	set_process(false)


## หยุดเกม: ค้างภาพไว้ (ไม่นับเวลา)
func set_paused(on: bool) -> void:
	set_process(not on and not _items.is_empty())


func _process(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for it in _items:
		it["t"] = float(it["t"]) + delta
		if float(it["t"]) < float(it["life"]):
			keep.append(it)
	_items = keep
	_write()
	if _items.is_empty():
		visible = false
		set_process(false)


func _add(it: Dictionary) -> void:
	it["t"] = 0.0
	if _items.size() >= POOL:
		_items.pop_front()
	_items.append(it)
	_write()
	visible = true
	set_process(true)


func _write() -> void:
	var mm := multimesh
	var eye := view.global_position if view != null and view.is_inside_tree() else Vector3(0.0, 1.6, 0.0)
	var n := mini(_items.size(), POOL)
	for i in n:
		var it: Dictionary = _items[i]
		var t := float(it["t"])
		var k := clampf(t / float(it["life"]), 0.0, 1.0)
		var xf := Transform3D()
		var col := Color.WHITE
		match it["kind"]:
			&"tracer":
				var a: Vector3 = it["a"]
				var b: Vector3 = it["b"]
				xf = _strip(a, b, TRACER_W, eye)
				col = TRACER_COL
			&"flash":
				var a: Vector3 = it["a"]
				var d: Vector3 = (it["b"] - a).normalized()
				var s := FLASH_SIZE * (1.0 - 0.5 * k)
				xf = _strip(a, a + d * s, s * 0.7, a + d.cross(Vector3.UP).rotated(d, float(it["turn"])) * 2.0)
				col = FLASH_COL
			&"spark":
				var p: Vector3 = it["a"] + it["vel"] * t
				var s := SPARK_SIZE * (1.0 - k * 0.6)
				xf = _facing(p, s, eye)
				col = SPARK_COL
			&"impact":
				xf = _facing(it["a"], IMPACT_SIZE, eye)
				col = SPARK_COL
		mm.set_instance_transform(i, xf)
		mm.set_instance_color(i, col)
	mm.visible_instance_count = n


## แผ่นยาวจาก a ถึง b กว้าง w หันหน้ากว้างไปหาจุด eye
static func _strip(a: Vector3, b: Vector3, w: float, eye: Vector3) -> Transform3D:
	var along := b - a
	var len := along.length()
	if len < 0.0001:
		return Transform3D(Basis().scaled(Vector3.ONE * 0.0001), a)
	var y := along / len
	var to_eye := eye - (a + b) * 0.5
	var x := y.cross(to_eye)
	if x.length_squared() < 1e-8:
		x = y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Transform3D(Basis(x * w, y * len, z), (a + b) * 0.5)


## แผ่นสี่เหลี่ยมขนาด s หันหน้าหาจุด eye
static func _facing(p: Vector3, s: float, eye: Vector3) -> Transform3D:
	var z := eye - p
	if z.length_squared() < 1e-8:
		z = Vector3.BACK
	z = z.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-8:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	return Transform3D(Basis(x * s, y * s, z), p)


static func _quad() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(-0.5, -0.5, 0.0), Vector3(0.5, -0.5, 0.0), Vector3(0.5, 0.5, 0.0),
		Vector3(-0.5, -0.5, 0.0), Vector3(0.5, 0.5, 0.0), Vector3(-0.5, 0.5, 0.0)])
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	for i in 6:
		cols.append(Color.WHITE)
		norms.append(Vector3.BACK)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


static func _material(add: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m
