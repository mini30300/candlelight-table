class_name PropsLayer
extends Node3D
## อุปกรณ์ฉากชั่วคราว: MultiMesh ต่อชนิด (8 ชนิด = 8 draw call) กล่อง/ทรงกระบอกสีเรียบ วางสุ่มจาก seed บนพื้น
## R1 ใช้รายการจาก core/field/props แทนการสุ่มที่นี่ (place()/blocked_at() คงเดิม); ไม่มีงานต่อเฟรม

enum Kind { BLOCK, WALL, TOWER, CRATE, TRUNK, CROWN, BARREL, PILLAR }

const KIND_COUNT := 8
const MARGIN := 1.5                    # ห่างราวขอบโต๊ะ
const CELL := 4.0                      # ตารางค้นหาการซ้อนทับ
const PACK := 0.5                      # อุปกรณ์ซ้อนกันได้ครึ่งรัศมี (กองซาก) — ฟิกเกอร์ถาม blocked_at ด้วยระยะเผื่อของตัวเอง
## น้ำหนักสุ่มชนิด (ต้นไม้ = ลำต้น + พุ่ม; ของเล็กเยอะเหมือน PROP_CAP 480 ของหน้าเก่า)
const WEIGHTS: Array[float] = [12.0, 8.0, 4.0, 30.0, 12.0, 0.0, 20.0, 14.0]
## รัศมีกันชนของแต่ละชนิด (เมตร)
const RADIUS: Array[float] = [1.5, 2.2, 1.2, 0.6, 0.9, 0.0, 0.5, 0.5]
## ชนิดเล็กที่ใช้เติมให้ครบจำนวนเมื่อที่ว่างหมด
const SMALL_KINDS: Array[int] = [Kind.CRATE, Kind.BARREL, Kind.PILLAR]

var seed_value := 1
var simplified := false

var _mmi: Array[MultiMeshInstance3D] = []
var _material: StandardMaterial3D
var _grid: Dictionary = {}             # Vector2i → Array[Vector3] (x, z, r)
var _count := 0
var _tris := 0


## วาง count ชิ้นบนพื้น terrain ด้วย RNG จาก seed; สีจากธีม (rock/ground2/wood)
func build(seed: int, count: int, terrain: TerrainMesh, theme: Dictionary, simple: bool = false) -> void:
	seed_value = seed
	simplified = simple
	for c in get_children():
		c.queue_free()
	_mmi.clear()
	_grid.clear()
	_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 17
	var rock := TerrainMesh._rgb(theme.get("rock", [138, 134, 128]))
	var ground2 := TerrainMesh._rgb(theme.get("ground2", [68, 64, 62]))
	var wood := TerrainMesh._rgb(theme.get("wood", [126, 96, 62]))
	var leaf := Color(0.30, 0.46, 0.22)
	var per_kind: Array = []
	for k in KIND_COUNT:
		per_kind.append([])   # [Transform3D, Color] คู่
	var total_w := 0.0
	for w in WEIGHTS:
		total_w += w
	var hw := terrain.width * 0.5 - MARGIN
	var hd := terrain.depth * 0.5 - MARGIN
	var colours: Array[Color] = [rock, rock, ground2.lerp(rock, 0.5), wood, wood * 0.8, leaf, wood, rock]
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 40:
		tries += 1
		var r := rng.randf() * total_w
		var kind := 0
		for k in KIND_COUNT:
			r -= WEIGHTS[k]
			if r <= 0.0:
				kind = k
				break
		var x := rng.randf_range(-hw, hw)
		var z := rng.randf_range(-hd, hd)
		var rad: float = RADIUS[kind] * PACK
		if blocked_at(x, z, rad + 0.3):
			continue
		_add(per_kind, colours, kind, x, z, terrain, rng)
		place(x, z, rad)
		placed += 1
	# ที่ว่างหมดก่อนครบจำนวน: เติมของเล็กโดยไม่ตรวจซ้อน (กองซากเล็ก ๆ)
	while placed < count:
		var kind: int = SMALL_KINDS[placed % SMALL_KINDS.size()]
		var x := rng.randf_range(-hw, hw)
		var z := rng.randf_range(-hd, hd)
		_add(per_kind, colours, kind, x, z, terrain, rng)
		place(x, z, RADIUS[kind] * PACK)
		placed += 1
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.95
	_tris = 0
	for k in KIND_COUNT:
		var items: Array = per_kind[k]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kind%d" % k
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _kind_mesh(k, simplified)
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_color(i, items[i][1])
		mmi.multimesh = mm
		mmi.material_override = _material
		add_child(mmi)
		_mmi.append(mmi)
		_tris += items.size() * _mesh_tris(mm.mesh)
	_count = placed


## หนึ่งชิ้นที่ (x, z): transform + สีลงรายการของชนิดนั้น (ต้นไม้ได้ลำต้นและพุ่ม)
func _add(per_kind: Array, colours: Array[Color], kind: int, x: float, z: float, terrain: TerrainMesh, rng: RandomNumberGenerator) -> void:
	var y := terrain.height_at(x, z)
	var yaw := rng.randf() * TAU
	var jitter := 0.85 + rng.randf() * 0.35
	var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * Basis.from_scale(Vector3(jitter, jitter, jitter))
	var shade := 0.85 + rng.randf() * 0.3
	var colour := _shade(colours[kind], shade)
	match kind:
		Kind.BLOCK:
			per_kind[kind].append([Transform3D(basis, Vector3(x, y + 0.7 * jitter, z)), colour])
		Kind.WALL:
			per_kind[kind].append([Transform3D(basis, Vector3(x, y + 0.55 * jitter, z)), colour])
		Kind.TOWER:
			per_kind[kind].append([Transform3D(basis, Vector3(x, y + 1.9 * jitter, z)), colour])
		Kind.CRATE:
			per_kind[kind].append([Transform3D(basis, Vector3(x, y + 0.3 * jitter, z)), colour])
		Kind.TRUNK:
			per_kind[Kind.TRUNK].append([Transform3D(basis, Vector3(x, y + 1.1 * jitter, z)), colour])
			per_kind[Kind.CROWN].append([Transform3D(basis, Vector3(x, y + (2.2 + 1.4) * jitter, z)), _shade(colours[Kind.CROWN], shade)])
		Kind.BARREL:
			per_kind[kind].append([Transform3D(basis, Vector3(x, y + 0.45 * jitter, z)), colour])
		Kind.PILLAR:
			per_kind[kind].append([Transform3D(basis, Vector3(x, y + 1.5 * jitter, z)), colour])


## จดตำแหน่งที่ถูกใช้เพื่อ blocked_at (อุปกรณ์จดที่รัศมี × PACK; ฟิกเกอร์ถามด้วยรัศมีตัวเอง + ระยะเผื่อ)
func place(x: float, z: float, r: float) -> void:
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	if not _grid.has(key):
		_grid[key] = []
	(_grid[key] as Array).append(Vector3(x, z, r))


## มีอะไรอยู่ในรัศมี r รอบ (x, z) ไหม (ช่อง 3x3 รอบจุด)
func blocked_at(x: float, z: float, r: float) -> bool:
	var cx := floori(x / CELL)
	var cz := floori(z / CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var items: Variant = _grid.get(Vector2i(cx + dx, cz + dz))
			if items == null:
				continue
			for p in items:
				var d: float = (p as Vector3).z + r
				if Vector2((p as Vector3).x - x, (p as Vector3).y - z).length_squared() < d * d:
					return true
	return false


## เมชง่ายขึ้นบน lo/min (ทรงกระบอก 6 เหลี่ยมแทน 12) โดยไม่วางใหม่
func set_simplified(on: bool) -> void:
	if on == simplified and not _mmi.is_empty() and _mmi[0].multimesh.mesh != null:
		return
	simplified = on
	_tris = 0
	for k in _mmi.size():
		_mmi[k].multimesh.mesh = _kind_mesh(k, simplified)
		_tris += _mmi[k].multimesh.instance_count * _mesh_tris(_mmi[k].multimesh.mesh)


func set_per_vertex(on: bool) -> void:
	if _material != null:
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if on else BaseMaterial3D.SHADING_MODE_PER_PIXEL


func count() -> int:
	return _count


func draw_calls() -> int:
	return _mmi.size()


func triangle_count() -> int:
	return _tris


static func _shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), 1.0)


static func _kind_mesh(kind: int, simple: bool) -> Mesh:
	var sides := 6 if simple else 12
	match kind:
		Kind.BLOCK:
			return _box(Vector3(2.0, 1.4, 2.0))
		Kind.WALL:
			return _box(Vector3(4.2, 1.1, 0.5))
		Kind.TOWER:
			return _box(Vector3(1.7, 3.8, 1.7))
		Kind.CRATE:
			return _box(Vector3(0.8, 0.6, 0.8))
		Kind.TRUNK:
			return _cylinder(0.22, 0.22, 2.2, sides)
		Kind.CROWN:
			return _cylinder(0.0, 1.3, 2.8, sides)
		Kind.BARREL:
			return _cylinder(0.4, 0.4, 0.9, sides)
		_:
			return _cylinder(0.35, 0.35, 3.0, sides)


static func _box(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cylinder(top: float, bottom: float, h: float, sides: int) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = sides
	m.rings = 0
	m.cap_top = top > 0.0
	return m


static func _mesh_tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n += ((idx as PackedInt32Array).size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n
