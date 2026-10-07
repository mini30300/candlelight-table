class_name TerrainMesh
extends MeshInstance3D
## พื้นสนาม: ArrayMesh ชิ้นเดียวจากความสูงของกติกา (core/field: FieldTerrain.hg หลัง FieldProps ปรับพื้นใต้ของแล้ว)
## จุดยอดอยู่บนจุดกริดของกติกาทุก cell_mi (MI/1000 = เมตร, 1 นิ้วเกม = 1 ม.) สีตามธีม ความสูง ความชัน + ราวรอบขอบ
## height_at() เป็นสองเส้นตรงแบบเดียวกับ FieldTerrain.height_at; normal_at() คงชื่อเดิม; ไม่มีงานต่อเฟรม

const RAIL_W := 0.7
const RAIL_H := 0.45        # ราวสูงกว่าพื้นที่ขอบเท่านี้ (ไล่ตามความสูงของขอบ)
const RAIL_BAND := 0.9      # แถบไม้ด้านนอกราว ใต้จากนั้นเป็นผ้าคลุมโต๊ะสีเข้ม
const SKIRT_DROP := 3.2     # ผ้าคลุมลงไปใต้ศูนย์อย่างน้อยเท่านี้ (และลึกกว่าจุดต่ำสุดของขอบ 1.2 ม. เสมอ)
const DEFAULT_THEME := {"ground": [112, 104, 94], "ground2": [68, 64, 62], "rock": [138, 134, 128],
	"wood": [126, 96, 62], "relief": 3.4, "rough": 1.2}

var width := 48.0
var depth := 34.0
var cell := 2.0
var grid_step := 1          # 1 ปกติ, 2 บนระดับ min (หน้าเก่าก็วาดพื้นหยาบลงครึ่งหนึ่งบน potato)
var seed_value := 1
var theme_data: Dictionary = DEFAULT_THEME
var field: FieldTerrain

var _h := PackedFloat32Array()   # ความสูงที่จุดกริดของกติกา (เมตร) (hw+1)*(hd+1)
var _hw := 0
var _hd := 0
var _tris := 0
var _material: StandardMaterial3D


## ทำเมชจากสนามของกติกา f (เรียกหลัง FieldProps.generate เพราะมันปรับพื้นใต้ของ) สีจากธีม (data/themes.json)
func build(f: FieldTerrain, theme_in: Dictionary, step: int = 1) -> void:
	field = f
	theme_data = theme_in if not theme_in.is_empty() else DEFAULT_THEME
	seed_value = f.seed_value
	width = float(f.w_in)
	depth = float(f.d_in)
	cell = float(f.cell_mi) / 1000.0
	_hw = f.hw
	_hd = f.hd
	_h = PackedFloat32Array()
	_h.resize(f.hg.size())
	for k in f.hg.size():
		_h[k] = float(f.hg[k]) / 1000.0
	grid_step = maxi(1, step)
	_build_mesh()


## เปลี่ยนความละเอียดตาข่าย (ระดับ min ใช้ 2) โดยไม่สร้างสนามใหม่
func set_grid_step(step: int) -> void:
	step = maxi(1, step)
	if step == grid_step:
		return
	grid_step = step
	if field != null:
		_build_mesh()


## แสงต่อจุดยอด (ถูกกว่า) บนระดับ lo/min
func set_per_vertex(on: bool) -> void:
	if _material != null:
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if on else BaseMaterial3D.SHADING_MODE_PER_PIXEL


func triangle_count() -> int:
	return _tris


## ความสูงพื้น ณ จุด (x, z) เมตร (กึ่งกลางโต๊ะคือ 0,0): สองเส้นตรงบนกริดของกติกา ตัดที่ขอบกริดแบบ FieldTerrain
func height_at(x: float, z: float) -> float:
	if _h.is_empty():
		return 0.0
	var fx := clampf(x + width * 0.5, 0.0, _hw * cell) / cell
	var fz := clampf(z + depth * 0.5, 0.0, _hd * cell) / cell
	var i := mini(int(fx), _hw - 1)
	var j := mini(int(fz), _hd - 1)
	var u := fx - i
	var v := fz - j
	var row := _hw + 1
	var top := lerpf(_h[j * row + i], _h[j * row + i + 1], u)
	var bottom := lerpf(_h[(j + 1) * row + i], _h[(j + 1) * row + i + 1], u)
	return lerpf(top, bottom, v)


## เวกเตอร์ตั้งฉากของพื้น ณ จุด (x, z) (จากผลต่างความสูง)
func normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func inside(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) <= width * 0.5 - margin and absf(z) <= depth * 0.5 - margin


## พิกัดจุดยอดตามแกน (MI): จุดกริดทุก step ช่อง ปิดท้ายที่ขอบโต๊ะ (กริดยาวเกินโต๊ะถูกตัด สั้นกว่าก็ต่อถึงขอบ)
static func axis_nodes(half_mi: int, n: int, cell_mi: int, step: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var i := 0
	while true:
		var x := mini(-half_mi + i * cell_mi, half_mi)
		if out.is_empty() or x > out[out.size() - 1]:
			out.append(x)
		if x >= half_mi:
			break
		if i >= n:
			out.append(half_mi)
			break
		i = mini(i + maxi(step, 1), n)
	return out


# ---- เมช ----

func _build_mesh() -> void:
	var xs := axis_nodes(field.w_in * 500, _hw, field.cell_mi, grid_step)
	var zs := axis_nodes(field.d_in * 500, _hd, field.cell_mi, grid_step)
	var nx := xs.size()
	var nz := zs.size()
	# จุดยอดเอาความสูงจากกติกาตรง ๆ (บนจุดกริดคือ hg พอดี ที่ขอบที่ถูกตัดคือสองเส้นตรงของกติกา)
	var pts := PackedVector3Array()
	pts.resize(nx * nz)
	for jj in nz:
		for ii in nx:
			pts[jj * nx + ii] = Vector3(float(xs[ii]) / 1000.0, float(field.height_at(xs[ii], zs[jj])) / 1000.0, float(zs[jj]) / 1000.0)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var ground := _rgb(theme_data.get("ground", DEFAULT_THEME["ground"]))
	var ground2 := _rgb(theme_data.get("ground2", DEFAULT_THEME["ground2"]))
	var rock := _rgb(theme_data.get("rock", DEFAULT_THEME["rock"]))
	var wood := _rgb(theme_data.get("wood", DEFAULT_THEME["wood"]))
	var patch_col := Color(ground2.r * 0.82, ground2.g * 0.82, ground2.b * 0.8)
	var span := maxf(1.0, float(field.span_mi) / 1000.0) * 2.1
	var peaks := field.terrain == "mountain"
	for jj in nz - 1:
		for ii in nx - 1:
			var p00 := pts[jj * nx + ii]
			var p10 := pts[jj * nx + ii + 1]
			var p01 := pts[(jj + 1) * nx + ii]
			var p11 := pts[(jj + 1) * nx + ii + 1]
			# สีตามความสูงเทียบช่วงสูงจริงของสนาม (หน้าเก่า drawGround) + หย่อมดินเข้ม + หินบนยอดเขา
			var hh := (p00.y + p10.y + p01.y + p11.y) * 0.25
			var m := clampf(0.5 + hh / span, 0.0, 1.0)
			var base := ground2.lerp(ground, m)
			var cx := (p00.x + p11.x) * 0.5
			var cz := (p00.z + p11.z) * 0.5
			var patch := fbm(cx / 5.5 + 41.3, cz / 5.5 + 17.7, 2, seed_value + 9)
			if patch > 0.18:
				base = base.lerp(patch_col, clampf((patch - 0.18) * 2.4, 0.0, 1.0))
			if peaks and m > 0.72:
				base = base.lerp(rock, clampf((m - 0.72) * 2.2, 0.0, 0.7))
			if hash01(ii, jj, seed_value + 5) < 0.5:   # สลับแนวทแยงให้ดูเป็นโพลิกอนต่ำ
				_tri(verts, norms, cols, p00, p10, p11, base, rock, ii * 2, jj)
				_tri(verts, norms, cols, p00, p11, p01, base, rock, ii * 2 + 1, jj)
			else:
				_tri(verts, norms, cols, p00, p10, p01, base, rock, ii * 2, jj)
				_tri(verts, norms, cols, p10, p11, p01, base, rock, ii * 2 + 1, jj)
	_rails(verts, norms, cols, pts, nx, nz, wood, ground2)
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


## ราวไม้รอบขอบโต๊ะ ไล่ตามความสูงของขอบพื้น: หน้าบน หน้าใน แถบไม้ด้านนอก แล้วผ้าคลุมสีเข้มลงไปใต้โต๊ะ + เสามุมสี่ต้น
func _rails(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		pts: PackedVector3Array, nx: int, nz: int, wood: Color, ground2: Color) -> void:
	var lo := 0.0
	for ii in nx:
		lo = minf(lo, minf(pts[ii].y, pts[(nz - 1) * nx + ii].y))
	for jj in nz:
		lo = minf(lo, minf(pts[jj * nx].y, pts[jj * nx + nx - 1].y))
	var drop := maxf(SKIRT_DROP, 1.2 - lo)
	var dark := Color(ground2.r * 0.34, ground2.g * 0.32, ground2.b * 0.32)
	var near_edge := PackedVector3Array()
	var far_edge := PackedVector3Array()
	for ii in nx:
		near_edge.append(pts[ii])
		far_edge.append(pts[(nz - 1) * nx + ii])
	var left_edge := PackedVector3Array()
	var right_edge := PackedVector3Array()
	for jj in nz:
		left_edge.append(pts[jj * nx])
		right_edge.append(pts[jj * nx + nx - 1])
	_edge(verts, norms, cols, near_edge, Vector3(0, 0, -1), drop, wood, dark)
	_edge(verts, norms, cols, far_edge, Vector3(0, 0, 1), drop, wood, dark)
	_edge(verts, norms, cols, left_edge, Vector3(-1, 0, 0), drop, wood, dark)
	_edge(verts, norms, cols, right_edge, Vector3(1, 0, 0), drop, wood, dark)
	for corner in [[pts[0], -1.0, -1.0], [pts[nx - 1], 1.0, -1.0], [pts[(nz - 1) * nx], -1.0, 1.0], [pts[nz * nx - 1], 1.0, 1.0]]:
		_post(verts, norms, cols, corner[0], corner[1], corner[2], drop, wood, dark)


func _edge(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		edge: PackedVector3Array, out: Vector3, drop: float, wood: Color, dark: Color) -> void:
	var up := Vector3.UP
	for k in edge.size() - 1:
		var a := edge[k]
		var b := edge[k + 1]
		var a_top := a + up * RAIL_H
		var b_top := b + up * RAIL_H
		var a_out := a_top + out * RAIL_W
		var b_out := b_top + out * RAIL_W
		_quad(verts, norms, cols, a_top, b_top, b_out, a_out, up, wood)
		_quad(verts, norms, cols, a, b, b_top, a_top, -out, wood * 0.8)
		var a_band := a_out - up * RAIL_BAND
		var b_band := b_out - up * RAIL_BAND
		_quad(verts, norms, cols, a_out, b_out, b_band, a_band, out, wood * 0.7)
		_quad(verts, norms, cols, a_band, b_band, Vector3(b_band.x, -drop, b_band.z), Vector3(a_band.x, -drop, a_band.z), out, dark)


## เสามุม: เติมช่องสี่เหลี่ยมระหว่างราวสองด้านที่มุมโต๊ะ (sx, sz = ทิศออกนอกโต๊ะ)
func _post(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		c: Vector3, sx: float, sz: float, drop: float, wood: Color, dark: Color) -> void:
	var top := c.y + RAIL_H
	var band := top - RAIL_BAND
	var x0 := c.x
	var x1 := c.x + sx * RAIL_W
	var z0 := c.z
	var z1 := c.z + sz * RAIL_W
	_quad(verts, norms, cols, Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(x0, top, z1), Vector3.UP, wood)
	var ox := Vector3(sx, 0, 0)
	var oz := Vector3(0, 0, sz)
	_quad(verts, norms, cols, Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(x1, band, z1), Vector3(x1, band, z0), ox, wood * 0.7)
	_quad(verts, norms, cols, Vector3(x1, band, z0), Vector3(x1, band, z1), Vector3(x1, -drop, z1), Vector3(x1, -drop, z0), ox, dark)
	_quad(verts, norms, cols, Vector3(x0, top, z1), Vector3(x1, top, z1), Vector3(x1, band, z1), Vector3(x0, band, z1), oz, wood * 0.7)
	_quad(verts, norms, cols, Vector3(x0, band, z1), Vector3(x1, band, z1), Vector3(x1, -drop, z1), Vector3(x0, -drop, z1), oz, dark)


## สามเหลี่ยมพื้นหนึ่งหน้า (แสงแบน): สีฐานผสมหินตามความชัน และสั่นเล็กน้อยต่อหน้า; หน้าหงายขึ้นเสมอ
func _tri(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, base: Color, rock: Color, fx: int, fz: int) -> void:
	var n := (b - a).cross(c - a)
	if n.y < 0.0:
		n = -n
	n = n.normalized()
	var slope := 1.0 - n.y
	var col := base.lerp(rock, clampf((slope - 0.08) * 3.5, 0.0, 0.8))
	col *= 0.95 + 0.1 * hash01(fx, fz, seed_value + 3)
	col.a = 1.0
	_push(verts, norms, cols, a, b, c, n, col)


func _quad(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	col.a = 1.0
	_push(verts, norms, cols, a, b, c, n, col)
	_push(verts, norms, cols, a, c, d, n, col)


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


# ---- นอยส์ของภาพ (ไม่ใช่กติกา) ----

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


## fbm แบบหน้าเก่า (ครึ่งแอมพลิจูด สองเท่าความถี่ หารผลรวม) คืนค่าประมาณ -1..1
static func fbm(x: float, z: float, oct: int, s: int) -> float:
	var sum := 0.0
	var amp := 1.0
	var norm := 0.0
	var f := 1.0
	for i in oct:
		sum += amp * _vnoise(x * f, z * f, s + i * 31)
		norm += amp
		amp *= 0.5
		f *= 2.0
	return sum / norm


static func _rgb(v: Variant) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]) / 255.0, float(v[1]) / 255.0, float(v[2]) / 255.0, 1.0)
	return Color(0.5, 0.5, 0.5, 1.0)
