class_name Rings
extends MultiMeshInstance3D
## วงแหวนบนพื้นทุกวงใน MultiMesh เดียว = 1 draw call ทุกระดับ: สีทีมใต้ฟิกเกอร์ทุกตัว วงเลือก วงปลายทาง วงวัตถุประสงค์
## ฟิกเกอร์ไม่ย้อมสีทีม (มติเจ้าของ 7 ต.ค.) ทีมดูจากวงนี้; สี/รัศมีต่อวงมากับ add_ring/set_ring; ไม่มีงานต่อเฟรม

enum Kind { TEAM, SELECT, DEST, OBJECTIVE }

const SEGMENTS := 20
const INNER := 0.74                 # รัศมีในของเมชหน่วย (รัศมีนอก = 1)
const LIFT := 0.04                  # ยกเหนือพื้นกันภาพซ้อน
const KIND_COLOUR := {
	Kind.SELECT: Color(1.0, 1.0, 1.0, 1.0),
	Kind.DEST: Color(1.0, 0.86, 0.32, 1.0),
	Kind.OBJECTIVE: Color(0.98, 0.95, 0.80, 1.0),
}
## รัศมีคูณเพิ่มของวงพิเศษ (วงเลือกใหญ่กว่าวงทีมเล็กน้อย)
const KIND_SCALE := {Kind.TEAM: 1.0, Kind.SELECT: 1.22, Kind.DEST: 1.1, Kind.OBJECTIVE: 1.0}

var capacity := 0

var _used := PackedByteArray()
var _free := PackedInt32Array()
var _count := 0
var _material: StandardMaterial3D


## เตรียมที่ไว้ capacity วง (ฟิกเกอร์ทุกตัว + วงพิเศษอีกหน่อย); เรียกใหม่ได้เมื่อจำนวนเปลี่ยน
func setup(cap: int) -> void:
	capacity = maxi(cap, 1)
	if multimesh == null or multimesh.mesh == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _ring_mesh()
		multimesh = mm
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh.instance_count = capacity
	_used.resize(capacity)
	_used.fill(0)
	_free.clear()
	for i in capacity:
		_free.append(capacity - 1 - i)
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	_count = 0


## เพิ่มวง: คืนดัชนี หรือ -1 เมื่อเต็ม (pos = จุดบนพื้น, normal = ตั้งฉากพื้นที่นั่น, radius = รัศมีนอก)
func add_ring(pos: Vector3, normal: Vector3, radius: float, colour: Color) -> int:
	if _free.is_empty():
		return -1
	var i := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	_used[i] = 1
	_count += 1
	set_ring(i, pos, normal, radius, colour)
	return i


## วงพิเศษ (เลือก/ปลายทาง/วัตถุประสงค์) สีและขนาดตามชนิด
func add_kind(kind: Kind, pos: Vector3, normal: Vector3, radius: float) -> int:
	return add_ring(pos, normal, radius * float(KIND_SCALE.get(kind, 1.0)), KIND_COLOUR.get(kind, Color.WHITE))


func set_ring(i: int, pos: Vector3, normal: Vector3, radius: float, colour: Color) -> void:
	if i < 0 or i >= capacity:
		return
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	var basis := Basis(Quaternion(Vector3.UP, n)) * Basis.from_scale(Vector3(radius, 1.0, radius))
	multimesh.set_instance_transform(i, Transform3D(basis, pos + n * LIFT))
	multimesh.set_instance_color(i, colour)


func set_colour(i: int, colour: Color) -> void:
	if i >= 0 and i < capacity:
		multimesh.set_instance_color(i, colour)


func remove_ring(i: int) -> void:
	if i < 0 or i >= capacity or _used[i] == 0:
		return
	_used[i] = 0
	_count -= 1
	_free.append(i)
	multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))


func clear() -> void:
	setup(capacity)


func count() -> int:
	return _count


func triangle_count() -> int:
	return _count * SEGMENTS * 2


## วงแหวนแบนในระนาบ XZ รัศมีนอก 1 (ขยายต่อ instance ด้วย transform)
static func _ring_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	for s in SEGMENTS:
		var a0 := TAU * s / SEGMENTS
		var a1 := TAU * (s + 1) / SEGMENTS
		var o0 := Vector3(cos(a0), 0.0, sin(a0))
		var o1 := Vector3(cos(a1), 0.0, sin(a1))
		var i0 := o0 * INNER
		var i1 := o1 * INNER
		# ตามเข็มเมื่อมองจากบน (หน้าหงายขึ้น); cull ปิดอยู่แล้วเพื่อให้เห็นจากมุมต่ำด้วย
		for v in [o0, o1, i0, i0, o1, i1]:
			verts.append(v)
			norms.append(Vector3.UP)
			cols.append(Color.WHITE)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am
