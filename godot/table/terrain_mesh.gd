class_name TerrainMesh
extends MeshInstance3D
## พื้นสนาม: ArrayMesh ชิ้นเดียวจาก heightfield ชั่วคราว (สุ่มจาก seed) 42x30 ช่อง สีตามธีมและความชัน + ราวไม้รอบขอบ
## R1 เปลี่ยนแหล่งความสูงเป็น core/field (HG); height_at()/normal_at() คงชื่อเดิม ไม่มีงานต่อเฟรม

const CELLS_X := 42
const CELLS_Z := 30
const EDGE_FADE := 3.0      # เมตร: ความสูงลู่เข้า 0 ใกล้ขอบ ให้ราวนั่งเรียบ
const RAIL_W := 0.7
const RAIL_H := 0.45
const RAIL_DOWN := 0.6      # ราวลงไปใต้โต๊ะเท่านี้ (เป็นข้างโต๊ะเมื่อมองจากมุมต่ำ)
const PIT := 0.35           # ก้นหลุมลึกสุด = relief * PIT
const DEFAULT_THEME := {"ground": [112, 104, 94], "ground2": [68, 64, 62], "rock": [138, 134, 128],
	"wood": [126, 96, 62], "relief": 3.4, "rough": 1.2}

var width := 48.0
var depth := 34.0
var relief := 3.4
var rough := 1.2
var grid_step := 1          # 1 ปกติ, 2 บนระดับ min
var seed_value := 1
var theme_data: Dictionary = DEFAULT_THEME

var _h := PackedFloat32Array()   # (CELLS_X+1)*(CELLS_Z+1) ความสูงที่มุมช่อง
var _tris := 0
var _material: StandardMaterial3D


## สร้างพื้นใหม่ทั้งชิ้นจาก seed และธีม (ground/ground2/rock/wood/relief/rough อย่าง data/themes.json)
func build(seed: int, theme_in: Dictionary, w: float = 48.0, d: float = 34.0, step: int = 1) -> void:
	seed_value = seed
	theme_data = theme_in if not theme_in.is_empty() else DEFAULT_THEME
	width = w
	depth = d
	relief = float(theme_data.get("relief", 3.4))
	rough = float(theme_data.get("rough", 1.2))
	grid_step = maxi(1, step)
	_gen_heights()
	_build_mesh()


## เปลี่ยนความละเอียดตาข่าย (ระดับ min ใช้ 2) โดยไม่สุ่มความสูงใหม่
func set_grid_step(step: int) -> void:
	step = maxi(1, step)
	if step == grid_step:
		return
	grid_step = step
	if not _h.is_empty():
		_build_mesh()


## แสงต่อจุดยอด (ถูกกว่า) บนระดับ lo/min
func set_per_vertex(on: bool) -> void:
	if _material != null:
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if on else BaseMaterial3D.SHADING_MODE_PER_PIXEL


func triangle_count() -> int:
	return _tris


## ความสูงพื้น ณ จุด (x, z) ในพิกัดโลก (กึ่งกลางโต๊ะคือ 0,0); นอกโต๊ะคืนขอบ
func height_at(x: float, z: float) -> float:
	if _h.is_empty():
		return 0.0
	var fx := clampf((x + width * 0.5) / width * CELLS_X, 0.0, CELLS_X - 0.0001)
	var fz := clampf((z + depth * 0.5) / depth * CELLS_Z, 0.0, CELLS_Z - 0.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := _h[_idx(ix, iz)]
	var h10 := _h[_idx(ix + 1, iz)]
	var h01 := _h[_idx(ix, iz + 1)]
	var h11 := _h[_idx(ix + 1, iz + 1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## เวกเตอร์ตั้งฉากของพื้น ณ จุด (x, z) (จากผลต่างความสูง)
func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func inside(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= width * 0.5 - margin and absf(z) <= depth * 0.5 - margin


# ---- heightfield ----

func _idx(ix: int, iz: int) -> int:
	return iz * (CELLS_X + 1) + ix


func _gen_heights() -> void:
	_h.resize((CELLS_X + 1) * (CELLS_Z + 1))
	var cw := width / CELLS_X
	var cd := depth / CELLS_Z
	for iz in CELLS_Z + 1:
		for ix in CELLS_X + 1:
			var x := ix * cw - width * 0.5
			var z := iz * cd - depth * 0.5
			var n := _fbm(x * 0.055 * rough, z * 0.055 * rough)      # ประมาณ [-1, 1]
			var h := n * relief
			h = maxf(h, -relief * PIT)
			var ex := minf(x + width * 0.5, width * 0.5 - x)
			var ez := minf(z + depth * 0.5, depth * 0.5 - z)
			var e := clampf(minf(ex, ez) / EDGE_FADE, 0.0, 1.0)
			h *= e * e * (3.0 - 2.0 * e)
			_h[_idx(ix, iz)] = h


## hash จำนวนเต็ม → [0, 1): ผลเหมือนกันทุกเครื่อง (ไม่ใช้ RNG ของเครื่องยนต์)
static func hash01(ix: int, iz: int, s: int) -> float:
	var h := ix * 374761393 + iz * 668265263 + s * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


static func _vnoise(x: float, z: float, s: int) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var tx := x - ix
	var tz := z - iz
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var a := hash01(ix, iz, s)
	var b := hash01(ix + 1, iz, s)
	var c := hash01(ix, iz + 1, s)
	var d := hash01(ix + 1, iz + 1, s)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz) * 2.0 - 1.0


func _fbm(x: float, z: float) -> float:
	return _vnoise(x, z, seed_value) * 0.58 + _vnoise(x * 2.1 + 7.3, z * 2.1 + 3.1, seed_value + 1) * 0.28 \
		+ _vnoise(x * 4.3 + 1.7, z * 4.3 + 9.2, seed_value + 2) * 0.14


# ---- mesh ----

func _build_mesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var ground := _rgb(theme_data.get("ground", DEFAULT_THEME["ground"]))
	var ground2 := _rgb(theme_data.get("ground2", DEFAULT_THEME["ground2"]))
	var rock := _rgb(theme_data.get("rock", DEFAULT_THEME["rock"]))
	var wood := _rgb(theme_data.get("wood", DEFAULT_THEME["wood"]))
	var cw := width / CELLS_X
	var cd := depth / CELLS_Z
	var step := grid_step
	var iz := 0
	while iz < CELLS_Z:
		var iz2 := mini(iz + step, CELLS_Z)
		var ix := 0
		while ix < CELLS_X:
			var ix2 := mini(ix + step, CELLS_X)
			var p00 := Vector3(ix * cw - width * 0.5, _h[_idx(ix, iz)], iz * cd - depth * 0.5)
			var p10 := Vector3(ix2 * cw - width * 0.5, _h[_idx(ix2, iz)], iz * cd - depth * 0.5)
			var p01 := Vector3(ix * cw - width * 0.5, _h[_idx(ix, iz2)], iz2 * cd - depth * 0.5)
			var p11 := Vector3(ix2 * cw - width * 0.5, _h[_idx(ix2, iz2)], iz2 * cd - depth * 0.5)
			var patch := _vnoise((ix + 0.5) * 0.21, (iz + 0.5) * 0.21, seed_value + 9) * 0.5 + 0.5
			var base := ground.lerp(ground2, patch)
			if hash01(ix, iz, seed_value + 5) < 0.5:   # สลับแนวทแยงให้ดูเป็นโพลิกอนต่ำ
				_tri(verts, norms, cols, p00, p10, p11, base, rock, ix * 2, iz)
				_tri(verts, norms, cols, p00, p11, p01, base, rock, ix * 2 + 1, iz)
			else:
				_tri(verts, norms, cols, p00, p10, p01, base, rock, ix * 2, iz)
				_tri(verts, norms, cols, p10, p11, p01, base, rock, ix * 2 + 1, iz)
			ix = ix2
		iz = iz2
	# ราวไม้สี่ด้าน
	var hw := width * 0.5
	var hd := depth * 0.5
	var ry := (RAIL_H - RAIL_DOWN) * 0.5
	var rh := RAIL_H + RAIL_DOWN
	_box(verts, norms, cols, Vector3(0.0, ry, -hd - RAIL_W * 0.5), Vector3(width + RAIL_W * 2.0, rh, RAIL_W), wood)
	_box(verts, norms, cols, Vector3(0.0, ry, hd + RAIL_W * 0.5), Vector3(width + RAIL_W * 2.0, rh, RAIL_W), wood)
	_box(verts, norms, cols, Vector3(-hw - RAIL_W * 0.5, ry, 0.0), Vector3(RAIL_W, rh, depth), wood)
	_box(verts, norms, cols, Vector3(hw + RAIL_W * 0.5, ry, 0.0), Vector3(RAIL_W, rh, depth), wood)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = am
	_tris = verts.size() / 3
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 1.0
		_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material_override = _material


## สามเหลี่ยมหนึ่งหน้า (แสงแบน): สีจากความชันและ jitter เล็กน้อย; จัดลำดับจุดยอดให้หน้าหงายขึ้น (Godot: ตามเข็ม)
func _tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, base: Color, rock: Color, fx: int, fz: int) -> void:
	var n := (b - a).cross(c - a)
	if n.y < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	var slope := 1.0 - n.y
	var col := base.lerp(rock, clampf((slope - 0.06) * 4.5, 0.0, 1.0))
	var hmid := (a.y + b.y + c.y) / 3.0
	col *= (0.9 + 0.12 * clampf(hmid / maxf(relief, 0.1), -1.0, 1.0)) * (0.94 + 0.12 * hash01(fx, fz, seed_value + 3))
	col.a = 1.0
	_push(verts, norms, cols, a, b, c, n, col)


func _push(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Godot วาดหน้าที่จุดยอดเรียงตามเข็มเมื่อมองจากด้านที่ normal ชี้ออก
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	verts.append(a)
	verts.append(b)
	verts.append(c)
	for i in 3:
		norms.append(n)
		cols.append(col)


func _box(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		centre: Vector3, size: Vector3, col: Color) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for i in 8:
		p.append(centre + Vector3(h.x if (i & 1) else -h.x, h.y if (i & 2) else -h.y, h.z if (i & 4) else -h.z))
	var faces := [[0, 1, 3, 2, Vector3(0, 0, -1)], [4, 6, 7, 5, Vector3(0, 0, 1)], [0, 2, 6, 4, Vector3(-1, 0, 0)],
		[1, 5, 7, 3, Vector3(1, 0, 0)], [2, 3, 7, 6, Vector3(0, 1, 0)], [0, 4, 5, 1, Vector3(0, -1, 0)]]
	for f in faces:
		var n: Vector3 = f[4]
		var shade := 1.0 if n.y > 0.5 else (0.8 if n.y > -0.5 else 0.6)
		var c := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
		_push(verts, norms, cols, p[f[0]], p[f[1]], p[f[2]], n, c)
		_push(verts, norms, cols, p[f[0]], p[f[2]], p[f[3]], n, c)


static func _rgb(v: Variant) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]) / 255.0, float(v[1]) / 255.0, float(v[2]) / 255.0, 1.0)
	return Color(0.5, 0.5, 0.5, 1.0)
