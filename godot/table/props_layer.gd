class_name PropsLayer
extends Node3D
## ของบนสนามจากกติกา (core/field/props: FieldProps.items): MultiMesh หนึ่งชุดต่อชนิด เมชโพลีต่ำ สีต่อจุดยอด × สีต่อชิ้น
## ขนาดเมชมาจากรอยเท้าของกติกา (ตึก = bld_size, ชนิดที่มี foot_of ใช้ foot_of, ที่เหลือ rad_of) ภาพจึงตรงกับที่กัน
## วางที่ x, z ของกติกา (MI/1000 = เมตร) บนพื้นที่ปรับราบแล้ว หมุน rot/65536 เรเดียน ขยาย s/1000; ไม่มีงานต่อเฟรม

const CELL := 4.0                      # ตารางค้นหาที่กัน (เมตร)
## ลำดับชนิด: ลูกโหนดเรียงตามนี้เสมอ (ชนิดที่ไม่รู้จักต่อท้าย)
const KINDS: PackedStringArray = ["building", "wall", "tower", "rubble", "barricade", "crater", "pipe", "obelisk",
	"pillars", "arch", "buried", "tree", "pine", "deadtree", "bush", "boulder", "iceslab", "log"]
## ชนิดที่ไม่มี foot_of: รัศมีที่วาด = rad_of x s x ตัวคูณนี้ (กิ่งไม้แห้ง พุ่มไม้ หิน เล็กกว่าระยะห่างของมัน)
const RAD_K := {"tree": 1.0, "pine": 1.0, "deadtree": 0.7, "bush": 0.65, "boulder": 0.8, "iceslab": 0.8, "pillars": 0.88}
## กำแพงยาวตามแกน x ของชิ้น: ครึ่งความยาว = rad_of x s, ครึ่งความหนาเท่านี้ x s
const WALL_HALF_T := 0.45
## สีตึกสี่แบบตาม h (หน้าเก่า)
const BUILDING_PALS := [[132, 126, 116], [108, 104, 104], [122, 96, 80], [96, 100, 104]]
const STOREY := 4.2                    # ความสูงชั้นตึก (เมตร ไม่ขยายตาม s แบบหน้าเก่า)
## ชนิดหิน: สีชิ้น = สีหินของธีม
const STONE := ["wall", "tower", "rubble", "crater", "obelisk", "pillars", "arch", "buried", "boulder"]

static var _mesh_cache: Dictionary = {}   # "kind|simple" → ArrayMesh (เมชไม่ขึ้นกับธีม ใช้ร่วมทุกโต๊ะ)

var simplified := false
var field_props: FieldProps

var _mmi: Dictionary = {}              # kind → MultiMeshInstance3D
var _material: StandardMaterial3D
var _grid: Dictionary = {}             # Vector2i → Array[int] ดัชนีใน _foot
var _foot: Array[PackedFloat32Array] = []   # [cx, cz, cos, sin, hx, hz, r] เมตร ต่อที่กันหนึ่งชิ้น
var _count := 0
var _tris := 0


## วางของทุกชิ้นของ p บนพื้น terrain (เรียกหลัง terrain.build); สีหินจากธีม; simple = เมชลดรูปของ lo/min
func build(p: FieldProps, terrain: TerrainMesh, theme: Dictionary, simple: bool = false) -> void:
	field_props = p
	simplified = simple
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_mmi.clear()
	_grid.clear()
	_foot.clear()
	_count = 0
	_tris = 0
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.95
	var rock := TerrainMesh._rgb(theme.get("rock", [138, 134, 128]))
	var per_kind: Dictionary = {}          # kind → Array ของ [Transform3D, Color]
	for o in p.items:
		var kind := str(o["kind"])
		var f := footprint(p, o)
		var x := float(o["x"]) / 1000.0
		var z := float(o["z"]) / 1000.0
		var rot := float(o["rot"]) / 65536.0
		var s := float(o["s"]) / 1000.0
		var hq := float(o["h"]) / 65536.0
		var size_v := Vector3(s, s * height_k(kind, hq), s)
		if kind == "building":
			size_v = Vector3(f.x * 2.0, STOREY * (2.0 if hq > 0.55 else 1.0), f.y * 2.0)
		var basis := Basis(Vector3.UP, rot) * Basis.from_scale(size_v)
		if not per_kind.has(kind):
			per_kind[kind] = []
		(per_kind[kind] as Array).append([Transform3D(basis, Vector3(x, terrain.height_at(x, z), z)), _tint(kind, hq, rock)])
		_add_foot(x, z, rot, f.x, f.y, f.z)
	var order: Array[String] = []
	for k in KINDS:
		if per_kind.has(k):
			order.append(k)
	for k in per_kind:
		if not KINDS.has(str(k)):
			order.append(str(k))
	for kind in order:
		var list: Array = per_kind[kind]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Kind_" + kind
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = kind_mesh(kind, simplified)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		mmi.multimesh = mm
		mmi.material_override = _material
		add_child(mmi)
		_mmi[kind] = mmi
		_count += list.size()
		_tris += list.size() * _mesh_tris(mm.mesh)


## รอยเท้าของชิ้น o เป็นเมตร: x, y = ครึ่งกว้าง/ครึ่งลึกของสี่เหลี่ยมในกรอบของชิ้น, z = รัศมี (วงกลม หรือขอบมน)
static func footprint(p: FieldProps, o: Dictionary) -> Vector3:
	var kind := str(o["kind"])
	var s := float(o["s"]) / 1000.0
	if kind == "building":
		var b := p.bld_size(o)
		return Vector3(float(b[0]) / 2000.0, float(b[1]) / 2000.0, 0.0)
	if kind == "wall":
		return Vector3(float(FieldProps.rad_of(kind)) / 1000.0 * s, WALL_HALF_T * s, 0.0)
	var f := p.foot_of(o)
	if not f.is_empty():
		return Vector3(float(f["hx"]) / 1000.0, float(f["hz"]) / 1000.0, float(f["r"]) / 1000.0)
	return Vector3(0.0, 0.0, float(FieldProps.rad_of(kind)) / 1000.0 * s * float(RAD_K.get(kind, 1.0)))


## รอยเท้าที่ s = 1 (ใช้สร้างเมช): ชนิดเดียวกันขนาดตาม s ทั้งชิ้น
static func unit_footprint(kind: String) -> Vector3:
	if kind == "building":
		return Vector3(0.5, 0.5, 0.0)
	return footprint(FieldProps.new(), {"kind": kind, "s": 1000, "h": 0, "rot": 0, "x": 0, "z": 0})


## ความสูงต่อชิ้นตาม h (หน้าเก่า): คูณกับ s บนแกน y; เมชสร้างที่ค่ากลาง
static func height_k(kind: String, hq: float) -> float:
	match kind:
		"tower":
			return 0.7 + hq * 0.6
		"obelisk":
			return (7.0 + hq * 4.0) / 9.0
		"arch":
			return (3.5 + hq * 2.5) / 4.75
		"tree", "deadtree":
			return (5.0 + hq * 3.0) / 6.5
		"pine":
			return (6.0 + hq * 4.0) / 8.0
		"boulder", "iceslab":
			return (1.6 + hq * 1.6) / 2.4
		"wall":
			return 0.7 + hq * 0.5
	return 1.0


## สีต่อชิ้น (คูณสีจุดยอด): ตึกตามสี่แบบของหน้าเก่า หินตามธีม ของธรรมชาติสว่างมืดต่างกันเล็กน้อย
static func _tint(kind: String, hq: float, rock: Color) -> Color:
	if kind == "building":
		return TerrainMesh._rgb(BUILDING_PALS[int(hq * 4.0) % 4])
	var k := 0.78 + 0.16 * hq
	if STONE.has(kind):
		return Color(clampf(rock.r * k, 0.0, 1.0), clampf(rock.g * k, 0.0, 1.0), clampf(rock.b * k, 0.0, 1.0), 1.0)
	k = 0.88 + 0.22 * hq
	return Color(k, k, k, 1.0)


func _add_foot(x: float, z: float, rot: float, hx: float, hz: float, r: float) -> void:
	var i := _foot.size()
	_foot.append(PackedFloat32Array([x, z, cos(rot), sin(rot), hx, hz, r]))
	var reach := sqrt(hx * hx + hz * hz) + r
	for cz in range(floori((z - reach) / CELL), floori((z + reach) / CELL) + 1):
		for cx in range(floori((x - reach) / CELL), floori((x + reach) / CELL) + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append(i)


## จดที่กันเพิ่มเป็นวงกลม (ใช้กับของที่ไม่ได้มาจากกติกา)
func place(x: float, z: float, r: float) -> void:
	_add_foot(x, z, 0.0, 0.0, 0.0, r)


## มีของอยู่ในระยะ r รอบ (x, z) ไหม (ระยะถึงรอยเท้าที่หมุนแล้ว ตามกรอบเดียวกับกติกา)
func blocked_at(x: float, z: float, r: float) -> bool:
	for cz in range(floori((z - r) / CELL), floori((z + r) / CELL) + 1):
		for cx in range(floori((x - r) / CELL), floori((x + r) / CELL) + 1):
			var list: Variant = _grid.get(Vector2i(cx, cz))
			if list == null:
				continue
			for i in list:
				var f: PackedFloat32Array = _foot[i]
				var dx := x - f[0]
				var dz := z - f[1]
				var lx := absf(dx * f[2] - dz * f[3])
				var lz := absf(dx * f[3] + dz * f[2])
				var ex := maxf(0.0, lx - f[4])
				var ez := maxf(0.0, lz - f[5])
				if sqrt(ex * ex + ez * ez) - f[6] < r:
					return true
	return false


## เมชง่ายขึ้นบน lo/min โดยไม่วางใหม่
func set_simplified(on: bool) -> void:
	if on == simplified:
		return
	simplified = on
	_tris = 0
	for kind in _mmi:
		var mm: MultiMesh = (_mmi[kind] as MultiMeshInstance3D).multimesh
		mm.mesh = kind_mesh(kind, simplified)
		_tris += mm.instance_count * _mesh_tris(mm.mesh)


func set_per_vertex(on: bool) -> void:
	if _material != null:
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if on else BaseMaterial3D.SHADING_MODE_PER_PIXEL


## จำนวนชิ้นที่วาดจริง (ผลรวม instance ทุก MultiMesh)
func count() -> int:
	return _count


func draw_calls() -> int:
	return _mmi.size()


func triangle_count() -> int:
	return _tris


func kinds() -> PackedStringArray:
	return PackedStringArray(_mmi.keys())


func multimesh_of(kind: String) -> MultiMesh:
	var mmi: MultiMeshInstance3D = _mmi.get(kind)
	return mmi.multimesh if mmi != null else null


# ---- เมชต่อชนิด (สร้างครั้งเดียว ขนาดจากรอยเท้าที่ s = 1) ----

static func kind_mesh(kind: String, simple: bool) -> ArrayMesh:
	var key := kind + ("|s" if simple else "|f")
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var g := Geo.new()
	var f := unit_footprint(kind)
	match kind:
		"building":
			_building(g, simple)
		"wall":
			_wall(g, f, simple)
		"tower":
			_tower(g, f, simple)
		"rubble":
			_rubble(g, f, simple)
		"barricade":
			_barricade(g, f, simple)
		"crater":
			_crater(g, f, simple)
		"pipe":
			_pipe(g, f, simple)
		"obelisk":
			_obelisk(g, f)
		"pillars":
			_pillars(g, f, simple)
		"arch":
			_arch(g, f, simple)
		"buried":
			_buried(g, f)
		"tree":
			_tree(g, f, simple)
		"pine":
			_pine(g, f, simple)
		"deadtree":
			_deadtree(g, f, simple)
		"bush":
			g.prism(0, 0, 0, f.z, 1.1, 5 if simple else 6, _c(56, 80, 48), 0.55)
		"boulder":
			_boulder(g, f, simple, Color.WHITE)
		"iceslab":
			_boulder(g, f, simple, _c(176, 196, 214))
		"log":
			if simple:
				g.box(Vector3(0, f.y, 0), Vector3(f.x, f.y, f.y), _c(86, 68, 48))
			else:
				g.xprism(-f.x, f.x, f.y, 0, f.y, 6, _c(86, 68, 48))
		_:
			g.prism(0, 0, 0, maxf(f.z, 1.5), 1.6, 5, Color.WHITE, 0.6)
	var m := g.mesh()
	_mesh_cache[key] = m
	return m


## ตึกพัง: เมชหน่วยพื้น 1 x 1 สูง 1 (ขยายเป็น bld_size x ความสูงชั้น): ผนังสี่ด้านยอดหักไม่เท่ากัน + พื้นชั้นบนที่เหลือหนึ่งมุม
static func _building(g: Geo, simple: bool) -> void:
	var wall := Color.WHITE
	var cap := Color(0.55, 0.55, 0.55)
	var t := 0.035
	if simple:   # ผนังสี่ด้านด้านละกล่องเดียว ยังเห็นข้างในตึก
		g.box(Vector3(0, 0.45, -0.5 + t), Vector3(0.5, 0.45, t), wall)
		g.box(Vector3(0, 0.3, 0.5 - t), Vector3(0.5, 0.3, t), wall)
		g.box(Vector3(-0.5 + t, 0.4, 0), Vector3(t, 0.4, 0.5 - t * 2.0), wall * 0.95)
		g.box(Vector3(0.5 - t, 0.5, 0), Vector3(t, 0.5, 0.5 - t * 2.0), wall * 0.95)
		return
	# แต่ละด้านสองท่อน สูงไม่เท่ากัน (ด้านหน้า หลัง ซ้าย ขวา)
	var tops := [[1.0, 0.78], [0.62, 0.5], [0.9, 0.55], [0.72, 1.0]]
	for side in 4:
		var hs: Array = tops[side]
		for part in 2:
			var hh: float = hs[part]
			var a := -0.5 + part * 0.5
			var c := Vector3.ZERO
			var half := Vector3.ZERO
			if side < 2:
				c = Vector3(a + 0.25, hh * 0.5, (-0.5 + t) if side == 0 else (0.5 - t))
				half = Vector3(0.25, hh * 0.5, t)
			else:
				c = Vector3((-0.5 + t) if side == 2 else (0.5 - t), hh * 0.5, a + 0.25)
				half = Vector3(t, hh * 0.5, 0.25 - t * 2.0)
			g.box(c, half, wall)
			g.box(c + Vector3(0, hh * 0.5 + 0.02, 0), Vector3(half.x * 1.06, 0.02, half.z * 1.06), cap)
	g.box(Vector3(-0.26, 0.5, -0.24), Vector3(0.23, 0.02, 0.25), Color(0.78, 0.78, 0.76), 0.0, true)


## กำแพงพัง: สี่ท่อนเรียงตามแกน x สูงลดลง ยาวเท่ารอยเท้า หนา 2 x hz
static func _wall(g: Geo, f: Vector3, simple: bool) -> void:
	if simple:
		g.box(Vector3(0, 1.3, 0), Vector3(f.x, 1.3, f.y), Color.WHITE)
		return
	var segs := 4
	var seg_len := f.x * 2.0 / segs
	var hs := [3.4, 3.0, 2.2, 1.3]
	for i in segs:
		var cx := -f.x + (i + 0.5) * seg_len
		var hh: float = hs[i]
		g.box(Vector3(cx, hh * 0.5, 0), Vector3(seg_len * 0.5, hh * 0.5, f.y), Color.WHITE)
		if i == 1 or i == 3:
			g.box(Vector3(cx, hh + 0.25, 0), Vector3(seg_len * 0.28, 0.25, f.y), Color(0.8, 0.78, 0.74))


## หอคอยพัง: ตอหกเหลี่ยมสอบ + วงเศษหินที่ฐานกว้างเท่ารอยเท้า
static func _tower(g: Geo, f: Vector3, simple: bool) -> void:
	g.prism(0, 0, 0, f.z * 0.83, 6.5, 5 if simple else 6, Color.WHITE, 0.82)
	if not simple:
		g.prism(0, 0, 0, f.z, 0.5, 6, Color(0.8, 0.78, 0.74), 1.0, 0.3)


static func _rubble(g: Geo, f: Vector3, simple: bool) -> void:
	var n := 2 if simple else 5
	var spots := [[0.0, 0.0, 0.9], [0.9, 0.3, 0.6], [-0.7, 0.6, 0.5], [0.2, -0.9, 0.7], [-0.6, -0.5, 0.4]]
	for i in n:
		var sp: Array = spots[i]
		var hh := 0.4 + float(sp[2])
		# กล่องที่หมุนแล้วยังอยู่ในรัศมีรอยเท้า: ระยะถึงจุด + ครึ่งเส้นทแยง <= รัศมี
		var room := f.z * 0.98 - Vector2(sp[0], sp[1]).length()
		var hz := minf(0.55, room * 0.7)
		var hx := minf(0.8, sqrt(maxf(room * room - hz * hz, 0.01)))
		g.box(Vector3(sp[0], hh * 0.5, sp[1]), Vector3(hx, hh * 0.5, hz), Color.WHITE if i % 2 == 0 else Color(0.8, 0.78, 0.74), i * 1.7)


## สิ่งกีดขวาง: แผงยาวเกือบเต็มแกน x + ราวบน + ลังข้าง (อยู่ในรอยเท้า hx x hz)
static func _barricade(g: Geo, f: Vector3, simple: bool) -> void:
	g.box(Vector3(0, 0.9, 0), Vector3(f.x * 0.97, 0.9, 0.4), _c(92, 90, 86))
	if not simple:
		g.box(Vector3(0, 1.92, 0), Vector3(f.x * 0.97, 0.12, 0.5), _c(140, 120, 70))
	g.box(Vector3(f.x * 0.36, 0.5, f.y - 0.9), Vector3(0.9, 0.5, 0.9), _c(118, 112, 104))


## หลุมระเบิด: ขอบดินนูนรอบรอยเท้า ด้านในเข้ม
static func _crater(g: Geo, f: Vector3, simple: bool) -> void:
	var n := 7 if simple else 9
	var rim := Color(0.8, 0.78, 0.74)
	var inner := Color(0.34, 0.32, 0.3)
	var r0 := f.z
	var r1 := f.z * 0.81
	var r2 := f.z * 0.7
	var r3 := f.z * 0.6
	g.band(r0, 0.0, r1, 0.3, n, rim, false)
	if simple:
		g.band(r1, 0.3, r3, 0.03, n, rim * 0.7, true)
	else:
		g.band(r1, 0.3, r2, 0.3, n, rim, false)
		g.band(r2, 0.3, r3, 0.03, n, rim * 0.7, true)
	g.disc(r3, 0.03, n, inner)


## ท่อ: ท่อนอนตามแกน x กับถังตั้งกลาง (อยู่ในรัศมีรอยเท้า)
static func _pipe(g: Geo, f: Vector3, simple: bool) -> void:
	var pl := f.z * 0.95
	if simple:
		g.box(Vector3(0, 0.75, 0), Vector3(pl, 0.6, 0.6), _c(78, 84, 86))
	else:
		g.xprism(-pl, pl, 0.75, 0, 0.62, 8, _c(78, 84, 86))
		g.box(Vector3(-pl * 0.6, 0.35, 0), Vector3(0.2, 0.35, 0.7), _c(70, 76, 80))
		g.box(Vector3(pl * 0.6, 0.35, 0), Vector3(0.2, 0.35, 0.7), _c(70, 76, 80))
	g.prism(0, 0, 0, f.z * 0.42, 2.2, 5 if simple else 8, _c(70, 76, 80), 1.0)


## เสาหินแหลม: ฐานสี่เหลี่ยม (มุมถึงรัศมีรอยเท้า) + แท่งสี่เหลี่ยมสอบ
static func _obelisk(g: Geo, f: Vector3) -> void:
	var b := f.z * 0.7
	g.box(Vector3(0, 0.5, 0), Vector3(b, 0.5, b), Color(0.8, 0.78, 0.74))
	g.prism(0, 1.0, 0, b * 0.72 * sqrt(2.0), 8.0, 4, Color.WHITE, 0.45, PI * 0.25)


## เสาสี่ต้นเป็นวง (ตรงกลางยืนได้)
static func _pillars(g: Geo, f: Vector3, simple: bool) -> void:
	var cr := 0.75
	var ring := f.z - cr
	var hs := [6.5, 3.2, 5.0, 2.4]
	for i in 4:
		var a := i * TAU / 4.0
		var px := cos(a) * ring
		var pz := sin(a) * ring
		g.prism(px, 0, pz, cr, hs[i], 5 if simple else 8, Color.WHITE, 0.9)
		if not simple and i % 2 == 0:
			g.prism(px, hs[i], pz, cr * 1.13, 0.3, 8, Color(0.8, 0.78, 0.74), 1.0)


## ซุ้มประตู: เสาสองต้นที่ปลายแกน x + คานบน (กว้างเท่ารอยเท้า hx x hz)
static func _arch(g: Geo, f: Vector3, simple: bool) -> void:
	var pr := f.y
	var ah := 4.75
	for sx in [-1.0, 1.0]:
		g.prism(sx * (f.x - pr), 0, 0, pr, ah, 4 if simple else 6, Color.WHITE, 0.85)
	g.box(Vector3(0, ah + 0.45, 0), Vector3(f.x, 0.45, f.y * 0.95), Color(0.9, 0.9, 0.88), 0.0, true)


## ซากที่ฝังทราย: แผ่นนอน + ก้อนตั้ง (อยู่ในรัศมีรอยเท้า)
static func _buried(g: Geo, f: Vector3) -> void:
	g.box(Vector3(0, 0.35, 0), Vector3(f.z * 0.9, 0.5, 0.6), Color(0.8, 0.78, 0.74))
	g.box(Vector3(f.z * 0.72, 1.1, 0), Vector3(0.7, 1.1, 0.6), Color.WHITE)


## ต้นไม้ใบกว้าง: ลำต้น + พุ่มใบสองชั้น (พุ่มกว้างสุดเท่ารัศมีรอยเท้า)
static func _tree(g: Geo, f: Vector3, simple: bool) -> void:
	var th := 6.5
	var trunk := _c(78, 62, 44)
	var leaf := _c(62, 94, 50)
	g.prism(0, 0, 0, 0.42, th * 0.62, 4 if simple else 6, trunk, 0.7)
	if simple:
		g.prism(0, th * 0.4, 0, f.z, th * 0.62, 5, leaf, 0.2, 0.0, true, true)
		return
	g.prism(0, th * 0.42, 0, f.z, 2.0, 7, leaf * 0.84, 0.55, 0.0, true, true)
	g.prism(0, th * 0.58, 0, f.z * 0.85, 3.1, 7, leaf, 0.25, 0.4, true, true)


static func _pine(g: Geo, f: Vector3, simple: bool) -> void:
	var ph := 8.0
	g.prism(0, 0, 0, 0.34, ph * 0.4, 4 if simple else 5, _c(70, 56, 40), 0.8)
	if simple:
		g.prism(0, ph * 0.25, 0, f.z, ph * 0.75, 5, _c(46, 84, 55), 0.04, 0.0, false, true)
		return
	g.prism(0, ph * 0.28, 0, f.z, ph * 0.45, 7, _c(42, 78, 52), 0.12, 0.0, true, true)
	g.prism(0, ph * 0.62, 0, f.z * 0.69, ph * 0.5, 7, _c(50, 88, 58), 0.08, 0.5, true, true)


## ไม้แห้ง: ลำต้นกับกิ่ง (กิ่งยาวสุดถึงรัศมีรอยเท้า)
static func _deadtree(g: Geo, f: Vector3, simple: bool) -> void:
	var th := 6.5
	g.prism(0, 0, 0, 0.42, th, 4 if simple else 6, _c(78, 62, 44), 0.7)
	var n := 2 if simple else 5
	for i in n:
		var a := i * 1.25
		var bl := f.z * (0.8 + 0.1 * (i % 3))
		var y := th * (0.55 + 0.08 * i)
		var dir := Vector3(cos(a), 0, -sin(a))
		g.box(dir * bl * 0.5 + Vector3(0, y, 0), Vector3(bl * 0.5, 0.1, 0.1), _c(92, 76, 58), a)


static func _boulder(g: Geo, f: Vector3, simple: bool, col: Color) -> void:
	g.prism(0, -0.2, 0, f.z, 2.4, 5 if simple else 6, col, 0.55)
	if not simple:
		g.prism(f.z * 0.45, -0.1, f.z * 0.3, f.z * 0.36, 1.0, 5, col * 0.9, 0.6, 1.0)


static func _c(r: int, g: int, b: int) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, 1.0)


static func _mesh_tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		n += ((idx as PackedInt32Array).size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


## ตัวช่วยสร้างเมช: สะสมสามเหลี่ยมแสงแบนพร้อมสีต่อจุดยอด
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	## หน้าหลายเหลี่ยมนูน: เวกเตอร์ตั้งฉากชี้ไปทาง hint (ด้านนอก)
	func poly(pts: Array, col: Color, hint: Vector3) -> void:
		var p0: Vector3 = pts[0]
		var p1: Vector3 = pts[1]
		var p2: Vector3 = pts[2]
		var nn := (p1 - p0).cross(p2 - p0)
		if nn.length_squared() < 1e-12:
			return
		nn = nn.normalized()
		if nn.dot(hint) < 0.0:
			nn = -nn
		col.a = 1.0
		for i in range(1, pts.size() - 1):
			var a: Vector3 = pts[0]
			var b: Vector3 = pts[i]
			var d: Vector3 = pts[i + 1]
			# Godot วาดหน้าที่เรียงตามเข็มเมื่อมองจากด้านที่ normal ชี้ออก
			if (b - a).cross(d - a).dot(nn) > 0.0:
				var t := b
				b = d
				d = t
			v.append(a)
			v.append(b)
			v.append(d)
			for k in 3:
				n.append(nn)
				c.append(col)

	## กล่อง (หมุนรอบแกน y ได้) ไม่มีหน้าล่าง เว้นแต่ bottom
	func box(centre: Vector3, half: Vector3, col: Color, yaw: float = 0.0, bottom: bool = false) -> void:
		var b := Basis(Vector3.UP, yaw)
		var p: Array[Vector3] = []
		for i in 8:
			var q := Vector3(half.x if (i & 1) else -half.x, half.y if (i & 2) else -half.y, half.z if (i & 4) else -half.z)
			p.append(centre + b * q)
		var bx := b.x
		var bz := b.z
		poly([p[2], p[3], p[7], p[6]], col, Vector3.UP)
		poly([p[0], p[1], p[3], p[2]], col * 0.92, -bz)
		poly([p[4], p[5], p[7], p[6]], col * 0.92, bz)
		poly([p[0], p[2], p[6], p[4]], col * 0.86, -bx)
		poly([p[1], p[3], p[7], p[5]], col * 0.86, bx)
		if bottom:
			poly([p[0], p[1], p[5], p[4]], col * 0.6, Vector3.DOWN)

	## เสา n เหลี่ยมตั้งที่ (x, y0, z) รัศมี r สูง h ยอดสอบเหลือ r x taper (0 = กรวย)
	func prism(x: float, y0: float, z: float, r: float, h: float, sides: int, col: Color, taper: float = 1.0,
			rot0: float = 0.0, top: bool = true, bottom: bool = false) -> void:
		var bot: Array[Vector3] = []
		var tp: Array[Vector3] = []
		for i in sides:
			var a := rot0 + i * TAU / sides
			bot.append(Vector3(x + cos(a) * r, y0, z - sin(a) * r))
			tp.append(Vector3(x + cos(a) * r * taper, y0 + h, z - sin(a) * r * taper))
		for i in sides:
			var k := (i + 1) % sides
			var mid := (bot[i] + bot[k]) * 0.5 - Vector3(x, y0, z)
			if taper < 0.001:
				poly([bot[i], bot[k], tp[i]], col, mid)
			else:
				poly([bot[i], bot[k], tp[k], tp[i]], col, mid)
		if top and taper >= 0.001:
			poly(tp, col, Vector3.UP)
		if bottom:
			poly(bot, col * 0.6, Vector3.DOWN)

	## ทรงกระบอก n เหลี่ยมนอนตามแกน x จาก x0 ถึง x1 ศูนย์กลางที่ (y, z) รัศมี r
	func xprism(x0: float, x1: float, y: float, z: float, r: float, sides: int, col: Color) -> void:
		var a0: Array[Vector3] = []
		var a1: Array[Vector3] = []
		for i in sides:
			var a := i * TAU / sides
			a0.append(Vector3(x0, y + sin(a) * r, z + cos(a) * r))
			a1.append(Vector3(x1, y + sin(a) * r, z + cos(a) * r))
		for i in sides:
			var k := (i + 1) % sides
			var mid := (a0[i] + a0[k]) * 0.5 - Vector3(x0, y, z)
			poly([a0[i], a0[k], a1[k], a1[i]], col, mid)
		poly(a0, col * 0.8, Vector3.LEFT)
		poly(a1, col * 0.8, Vector3.RIGHT)

	## แถบวงแหวนจากรัศมี ra ที่ความสูง ya ไปรัศมี rb ที่ yb (inward = หน้าหันเข้าศูนย์กลาง/ขึ้น)
	func band(ra: float, ya: float, rb: float, yb: float, sides: int, col: Color, inward: bool) -> void:
		for i in sides:
			var a := i * TAU / sides
			var b := (i + 1) * TAU / sides
			var pa := Vector3(cos(a), 0, -sin(a))
			var pb := Vector3(cos(b), 0, -sin(b))
			var mid := (pa + pb) * 0.5
			var hint := (Vector3.UP - mid) if inward else (mid + Vector3.UP * 0.5)
			if absf(ya - yb) < 0.001:
				hint = Vector3.UP
			poly([pa * ra + Vector3(0, ya, 0), pb * ra + Vector3(0, ya, 0), pb * rb + Vector3(0, yb, 0), pa * rb + Vector3(0, yb, 0)], col, hint)

	func disc(r: float, y: float, sides: int, col: Color) -> void:
		var pts: Array[Vector3] = []
		for i in sides:
			var a := i * TAU / sides
			pts.append(Vector3(cos(a) * r, y, -sin(a) * r))
		poly(pts, col, Vector3.UP)

	func mesh() -> ArrayMesh:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return am
