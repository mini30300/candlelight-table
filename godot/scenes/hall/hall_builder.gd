class_name HallBuilder
extends RefCounted
## สร้างเมชและตัวชนของดาดฟ้ายานรบจาก HallLayout (SHIP_LOBBY_SPEC §2–§3, §7): ยานอวกาศแบบโบสถ์ที่ออกแบบเอง
## เพดานโค้งแหลม เสาเหล็กเป็นกลุ่ม ท่อ จอ เทียน ธงลายเทียนของเรา หน้าต่างบานใหญ่มองออกไปอวกาศ (อวกาศอยู่ใน HallSpace)
## เมชนิ่ง 3 ชิ้น (โครงยาน เฟอร์นิเจอร์ ผ้า) ใช้วัสดุเดียว unshaded สีต่อจุดยอด แสงอบลงในสีจุดยอด ไม่มีไฟจริง ไม่มีเงา
## แสงเทียน = 0.32 + Σ 0.85 / (1 + d²/3) (ยิ่งสว่างยิ่งออกส้ม #ffb35c) + แสงเย็น Σ k / (1 + d²/D) × สีของมัน (HallLayout.COOL_LIGHTS)
## เมชเก็บในแคช static ตามจำนวนเหลี่ยมของเสา (ระดับกราฟิก) สร้างครั้งเดียวต่อการเปิดแอป

const WARM := Color(1.0, 0.702, 0.361)        # #ffb35c
const GLOW_BASE := 0.28
const GLOW_K := 0.85
const GLOW_D2 := 3.0
const GLOW_MAX := 1.75
const COOL_MAX := 1.2
const DECK_WARM := 0.8         # แสงเทียนบนดาดฟ้า (คูณส่วนที่เกินแสงพื้น)
const DECK_TINT := 0.55        # ส้มของแสงเทียนบนดาดฟ้า (lit() ใช้ 0.85)
## โปรไฟล์ไข่ (y / สูง, รัศมี / กว้างสุด) จากฐานขึ้นยอด ตาม LOBBY_SPEC §4.1 (ล็อบบี้เก็บสำเนาของตัวเอง)
const EGG_PROFILE: PackedVector2Array = [Vector2(0.00, 0.55), Vector2(0.06, 0.85), Vector2(0.18, 0.98),
	Vector2(0.32, 1.00), Vector2(0.50, 0.95), Vector2(0.68, 0.80), Vector2(0.84, 0.56), Vector2(0.95, 0.30),
	Vector2(1.00, 0.00)]
## ไข่โฮโลแกรมหยาบกว่า (4 ชั้น)
const HOLO_EGG: PackedVector2Array = [Vector2(0.00, 0.6), Vector2(0.2, 0.98), Vector2(0.55, 0.92), Vector2(0.85, 0.55),
	Vector2(1.00, 0.0)]
const IVORY := Color(0.86, 0.82, 0.74)
const NUB := Color(0.55, 0.48, 0.40)

const STEEL := Color("4a4f55")
const STEEL_DARK := Color("2b2f35")
const DECK := Color("3f4348")
const DECK_SEAM := Color("1c1e22")
const GRATE := Color("2a2d31")
const BRONZE := Color("8a6a3a")
const BRASS := Color("b08d4a")
const IRON := Color(0.20, 0.18, 0.17)
const WAX := Color(0.95, 0.90, 0.78)
const GOLD := Color(0.90, 0.70, 0.34)
const CARPET := Color(0.50, 0.11, 0.10)
const PARCHMENT := Color(0.86, 0.76, 0.56)
const HOLO := Color("59f0b4")
const HOLO_AMBER := Color("ffc35a")
const HAZARD := Color("d9a521")
const HAZARD_DARK := Color("18181a")
const LAMP_AMBER := Color(1.0, 0.72, 0.30)
const SEAM_GLOW := Color(1.0, 0.84, 0.48)
const AIRLOCK_GLOW := Color(0.45, 0.72, 1.0)
const BANNER_COLS := [Color("7f1717"), Color("1f1c22"), Color("8c6630")]
## สีธงชายในคลังแสง 15 สี (สีล้วน ไม่มีตรา)
const PENNANTS := [Color(0.80, 0.22, 0.20), Color(0.24, 0.44, 0.80), Color(0.86, 0.68, 0.22), Color(0.30, 0.62, 0.32),
	Color(0.58, 0.32, 0.70), Color(0.92, 0.92, 0.88), Color(0.22, 0.66, 0.70), Color(0.86, 0.46, 0.18),
	Color(0.20, 0.20, 0.24), Color(0.80, 0.40, 0.62), Color(0.56, 0.38, 0.22), Color(0.46, 0.70, 0.30),
	Color(0.64, 0.12, 0.30), Color(0.40, 0.48, 0.58), Color(0.94, 0.80, 0.50)]
const TEAM_A := Color(0.28, 0.52, 0.84)
const TEAM_B := Color(0.83, 0.31, 0.26)
const BAYS: PackedFloat32Array = [-8.0, -5.0, 0.5, 5.5, 8.0]   # ช่วงโค้งเพดานตามแนวเสา (z)
const ARENA_K := 5         # ช่องต่อครึ่งโค้งของประตูอารีน่า
const OVERLAP := 0.08     # ผิวที่ชนกันยื่นเลยกันเล็กน้อย ไม่ให้มีรอยแยกเห็นทะลุ (ส่วนเกินอยู่นอกห้อง มองไม่เห็น)

static var _cache: Dictionary = {}        # "meshes|sides" → Array[ArrayMesh], "holo|thick" → ArrayMesh
static var _material: StandardMaterial3D
static var _flame_mesh: ArrayMesh
static var _flame_plain: StandardMaterial3D


## วัสดุเดียวของทุกเมชนิ่งและตัวผู้เล่น: ไม่รับแสง ใช้สีจุดยอด (sRGB)
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
	return _material


## เมชนิ่ง 3 ชิ้น [โครงยาน, เฟอร์นิเจอร์, ผ้า] ตามจำนวนเหลี่ยม (14 / 12 / 10 / 8 ตามระดับ)
static func meshes(sides: int) -> Array[ArrayMesh]:
	var key := "meshes|%d" % sides
	if _cache.has(key):
		return _cache[key]
	var lights := HallLayout.flames()
	var out: Array[ArrayMesh] = [_shell(sides, lights), _furniture(sides, lights), _cloth(lights)]
	_cache[key] = out
	return out


## ความสว่างของแสงเทียนที่จุด p (ก่อนตัดเพดาน)
static func glow(p: Vector3, lights: PackedVector3Array) -> float:
	var s := GLOW_BASE
	for f in lights:
		s += GLOW_K / (1.0 + p.distance_squared_to(f) / GLOW_D2)
	return s


## สีที่อบแสงเทียนแล้ว: มืด = สีเดิมจาง ๆ, สว่าง = สีเดิมอมส้ม
static func lit(col: Color, b: float) -> Color:
	b = clampf(b, 0.0, GLOW_MAX)
	var tint := Color(1.0, 1.0, 1.0).lerp(WARM, clampf((b - GLOW_BASE) / 1.0, 0.0, 1.0) * 0.85)
	return Color(minf(col.r * b * tint.r, 1.0), minf(col.g * b * tint.g, 1.0), minf(col.b * b * tint.b, 1.0), 1.0)


## แสงเย็นที่จุด p (สี rgb รวมของทุกดวง ตัดที่ COOL_MAX)
static func cool_at(p: Vector3, cool: Array) -> Color:
	var r := 0.0
	var gg := 0.0
	var bb := 0.0
	for l in cool:
		var k := float(l["k"]) / (1.0 + p.distance_squared_to(l["p"]) / float(l["d"]))
		var c: Color = l["col"]
		r += k * c.r
		gg += k * c.g
		bb += k * c.b
	return Color(minf(r, COOL_MAX), minf(gg, COOL_MAX), minf(bb, COOL_MAX), 1.0)


## สีที่อบทั้งแสงเทียนและแสงเย็น: ไม่มีแสงเย็น = lit() ตรงตัว
## มีแสงเย็น: แสงเทียนอ่อนลง (DECK_WARM) และส้มน้อยลง (DECK_TINT) ให้เหล็กยังเป็นสีเหล็ก ไม่กลายเป็นหินอุ่น
static func lit_cool(col: Color, b: float, cool: Color) -> Color:
	if cool.r == 0.0 and cool.g == 0.0 and cool.b == 0.0:
		return lit(col, b)
	b = clampf(GLOW_BASE + (b - GLOW_BASE) * DECK_WARM, 0.0, GLOW_MAX)
	var tint := Color(1.0, 1.0, 1.0).lerp(WARM, clampf((b - GLOW_BASE) / 1.0, 0.0, 1.0) * DECK_TINT)
	return Color(minf(col.r * (b * tint.r + cool.r), 1.0), minf(col.g * (b * tint.g + cool.g), 1.0),
		minf(col.b * (b * tint.b + cool.b), 1.0), 1.0)


## อบแสงลงทุกจุดยอดของ g (cool = รายการแสงเย็นแบบ HallLayout.COOL_LIGHTS, ว่าง = แสงเทียนอย่างเดียว)
static func bake(g: PropsLayer.Geo, lights: PackedVector3Array, cool: Array = []) -> void:
	var cols := g.c
	var verts := g.v
	# แสงขึ้นกับตำแหน่งอย่างเดียว: จุดยอดที่ตำแหน่งซ้ำกัน (ราว 2 ใน 3) ใช้ผลที่คิดไว้แล้ว ผลเหมือนเดิมทุกบิต
	var memo := {}
	if cool.is_empty():
		for i in verts.size():
			var p := verts[i]
			var b: Variant = memo.get(p)
			if b == null:
				b = glow(p, lights)
				memo[p] = b
			cols[i] = lit(cols[i], b)
	else:
		# แตกแสงเย็นเป็นอาร์เรย์ครั้งเดียว (อ่าน Dictionary ทุกจุดยอดช้าราว 3 เท่า) ผลตรงกับ cool_at ทุกบิต
		var cp := PackedVector3Array()
		var ck := PackedFloat64Array()
		var cd := PackedFloat64Array()
		var cc := PackedColorArray()
		for l in cool:
			cp.append(l["p"])
			ck.append(float(l["k"]))
			cd.append(float(l["d"]))
			cc.append(l["col"])
		var nl := cp.size()
		for i in verts.size():
			var p := verts[i]
			var hit: Variant = memo.get(p)
			if hit == null:
				var r := 0.0
				var gg := 0.0
				var bb := 0.0
				for j in nl:
					var k := ck[j] / (1.0 + p.distance_squared_to(cp[j]) / cd[j])
					var c := cc[j]
					r += k * c.r
					gg += k * c.g
					bb += k * c.b
				hit = [glow(p, lights), Color(minf(r, COOL_MAX), minf(gg, COOL_MAX), minf(bb, COOL_MAX), 1.0)]
				memo[p] = hit
			cols[i] = lit_cool(cols[i], hit[0], hit[1])
	g.c = cols


## ต่อเมชของ b ท้าย a (b ไม่อบแสง เช่น จอ ไฟสถานะ ช่องเรืองแสง)
static func append(a: PropsLayer.Geo, b: PropsLayer.Geo) -> void:
	a.v.append_array(b.v)
	a.n.append_array(b.n)
	a.c.append_array(b.c)


static func tris(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# ---- ตัวช่วยรูปทรง ----

## ความสูงของโค้งแหลมที่ระยะ dx จากกลาง (ครึ่งกว้าง a, เริ่มโค้งที่ spring, ยอดที่ apex) · จุดบนโค้งครึ่งขวา k ช่อง
## เรียงจากจุดเริ่มโค้ง (dx = a) ถึงยอด (dx = 0) แบ่งตามมุม
static func arch_pts(a: float, spring: float, apex: float, k: int) -> PackedVector2Array:
	var h := apex - spring
	var xc := (a * a - h * h) / (2.0 * a)
	var r := a - xc
	var tmax := acos(clampf(-xc / r, -1.0, 1.0))
	var out := PackedVector2Array()
	for j in k + 1:
		var t := tmax * j / k
		out.append(Vector2(maxf(xc + r * cos(t), 0.0), spring + r * sin(t)))
	out[k] = Vector2(0.0, apex)
	return out


## รูปโค้งแหลมทั้งช่อง (s, y) จากล่างซ้ายวนขึ้นไปลงล่างขวา: กลาง cs ครึ่งกว้าง a พื้น y0 (รูปนูน ใช้ poly ได้)
static func arch_outline(cs: float, a: float, y0: float, spring: float, apex: float, k: int) -> Array[Vector2]:
	var pts := arch_pts(a, spring, apex, k)
	var out: Array[Vector2] = [Vector2(cs - a, y0)]
	for j in pts.size():
		out.append(Vector2(cs - pts[j].x, pts[j].y))
	for j in range(pts.size() - 2, -1, -1):
		out.append(Vector2(cs + pts[j].x, pts[j].y))
	out.append(Vector2(cs + a, y0))
	return out


## แปลงจุดบนผนัง (s ตามผนัง, y) เป็นจุด 3 มิติ: o = จุด s = 0 บนผิว, u = ทิศตามผนัง, n = ทิศเข้าห้อง, off = ยื่นออก
static func wp(o: Vector3, u: Vector3, n: Vector3, s: float, y: float, off: float) -> Vector3:
	return o + u * s + Vector3(0.0, y, 0.0) + n * off


static func _wall_poly(g: PropsLayer.Geo, o: Vector3, u: Vector3, n: Vector3, pts: Array, off: float, col: Color) -> void:
	var p3: Array[Vector3] = []
	for q: Vector2 in pts:
		p3.append(wp(o, u, n, q.x, q.y, off))
	g.poly(p3, col, n)


static func _wall_rect(g: PropsLayer.Geo, o: Vector3, u: Vector3, n: Vector3, s0: float, s1: float, y0: float, y1: float,
		off: float, col: Color) -> void:
	g.poly([wp(o, u, n, s0, y0, off), wp(o, u, n, s1, y0, off), wp(o, u, n, s1, y1, off), wp(o, u, n, s0, y1, off)], col, n)


## แถบกรอบโค้งแหลมระหว่างโค้งนอกกับโค้งใน (หน้าเดียวหันไปทาง n)
static func _arch_band(g: PropsLayer.Geo, o: Vector3, u: Vector3, n: Vector3, cs: float, outer: Vector3, inner: Vector3,
		k: int, off: float, col: Color) -> void:
	var po := arch_pts(outer.x, outer.y, outer.z, k)
	var pin := arch_pts(inner.x, inner.y, inner.z, k)
	for side in [-1.0, 1.0]:
		for j in k:
			_wall_poly(g, o, u, n, [Vector2(cs + side * po[j].x, po[j].y), Vector2(cs + side * po[j + 1].x, po[j + 1].y),
				Vector2(cs + side * pin[j + 1].x, pin[j + 1].y), Vector2(cs + side * pin[j].x, pin[j].y)], off, col)


## ท่อตรงจาก a ถึง b รัศมี r (sides เหลี่ยม ไม่มีฝาปิด)
static func tube(g: PropsLayer.Geo, a: Vector3, b: Vector3, r: float, sides: int, col: Color) -> void:
	var d := (b - a).normalized()
	var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := d.cross(t1).normalized()
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var o0 := t1 * cos(a0) + t2 * sin(a0)
		var o1 := t1 * cos(a1) + t2 * sin(a1)
		g.poly([a + o0 * r, a + o1 * r, b + o1 * r, b + o0 * r], col, o0 + o1)


## แถบลายเตือนเหลืองดำบนพื้น: กลาง c, u = ทิศตามแถบ, ครึ่งยาว hu, ครึ่งกว้าง hv
static func _chevrons(g: PropsLayer.Geo, c: Vector3, u: Vector3, hu: float, hv: float) -> void:
	var v := Vector3.UP.cross(u).normalized()
	g.poly([c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv], HAZARD_DARK, Vector3.UP)
	var w := 0.12
	var step := 0.3
	var skew := hv * 1.2
	var s := -hu + 0.04
	var lift := Vector3(0.0, 0.002, 0.0)
	while s + w + skew <= hu - 0.04:
		g.poly([c + u * s - v * hv + lift, c + u * (s + w) - v * hv + lift, c + u * (s + w + skew) + v * hv + lift,
			c + u * (s + skew) + v * hv + lift], HAZARD, Vector3.UP)
		s += step


## ลายเทียนของเรา (เทียนในวงกลม) บนผิวที่ c: u = ทิศขวา, n = ทิศหน้า, rad = รัศมีวง
static func emblem(g: PropsLayer.Geo, c: Vector3, u: Vector3, n: Vector3, rad: float, ring: Color, wax: Color,
		flame: Color, segs: int = 16) -> void:
	var up := n.cross(u).normalized()
	if up.y < 0.0:
		up = -up
	var ri := rad * 0.84
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := u * cos(a0) + up * sin(a0)
		var d1 := u * cos(a1) + up * sin(a1)
		g.poly([c + d0 * ri, c + d1 * ri, c + d1 * rad, c + d0 * rad], ring, n)
	var o := n * 0.004
	g.poly([c - u * rad * 0.18 - up * rad * 0.7 + o, c + u * rad * 0.18 - up * rad * 0.7 + o, c + u * rad * 0.18 + o,
		c - u * rad * 0.18 + o], wax, n)
	var fb := c + up * rad * 0.1 + o * 1.5
	g.poly([fb - u * rad * 0.22 + up * rad * 0.18, fb, fb + u * rad * 0.22 + up * rad * 0.18, fb + up * rad * 0.66], flame, n)


# ---- โครงยาน: พื้นเหล็ก พรม ผนัง หน้าต่าง เสา เพดานโค้ง สายไฟ ประตู ช่องเทียบยาน ----

static func _shell(sides: int, lights: PackedVector3Array) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	var glow_g := PropsLayer.Geo.new()       # ส่วนที่ไม่อบแสง (จอ ไฟ ช่องเรืองแสง)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7731
	_floor(g, rng, sides)
	_side_wall(g, glow_g, rng, -1.0, sides)
	_side_wall(g, glow_g, rng, 1.0, sides)
	_front_wall(g, rng)
	_back_wall(g)
	_columns(g, sides)
	_vault(g, rng)
	_cables(g)
	_exit_door(g, glow_g)
	_airlock(g, glow_g, sides)
	_arena_door(g, glow_g)
	bake(g, lights, HallLayout.COOL_LIGHTS)
	append(g, glow_g)
	append(g, _arena_stub())
	return g.mesh()


static func _floor(g: PropsLayer.Geo, rng: RandomNumberGenerator, sides: int) -> void:
	var hx := HallLayout.HALF.x
	var hz := HallLayout.HALF.y
	var e := OVERLAP
	g.poly([Vector3(-hx - e, -0.004, -hz - e), Vector3(hx + e, -0.004, -hz - e), Vector3(hx + e, -0.004, hz + e), Vector3(-hx - e, -0.004, hz + e)],
		DECK_SEAM, Vector3.UP)
	# แผ่นเหล็กพื้น 1.5 x 1.0 ม. ในโถงกลาง สีต่างกันเล็กน้อย (สุ่มแบบมี seed)
	var gap := 0.025
	var px := 1.5
	var nx := 12
	var x_in := px * nx * 0.5                  # 9 ม.
	for iz in int(hz * 2.0):
		for ix in nx:
			var x0 := -x_in + ix * px + gap
			var z0 := -hz + iz + gap
			var k := rng.randf_range(0.84, 1.08)
			var col := Color(DECK.r * k, DECK.g * k, DECK.b * k * rng.randf_range(0.98, 1.04), 1.0)
			g.poly([Vector3(x0, 0.0, z0), Vector3(x0 + px - gap * 2.0, 0.0, z0), Vector3(x0 + px - gap * 2.0, 0.0, z0 + 1.0 - gap * 2.0),
				Vector3(x0, 0.0, z0 + 1.0 - gap * 2.0)], col, Vector3.UP)
	# หมุดที่มุมแผ่น (hi/mid เท่านั้น)
	if sides >= 12:
		for iz in range(1, int(hz * 2.0)):
			for ix in range(1, nx):
				var p := Vector3(-x_in + ix * px, 0.003, -hz + iz)
				g.poly([p + Vector3(-0.035, 0, 0), p + Vector3(0, 0, 0.035), p + Vector3(0.035, 0, 0), p + Vector3(0, 0, -0.035)],
					STEEL * 1.15, Vector3.UP)
	# ตะแกรงทางเดินข้าง: พื้นมืด + ซี่ตามยาว + คานขวาง
	for sx in [-1.0, 1.0]:
		var xa: float = sx * x_in
		var xb: float = sx * hx
		g.poly([Vector3(minf(xa, xb), 0.0, -hz), Vector3(maxf(xa, xb), 0.0, -hz), Vector3(maxf(xa, xb), 0.0, hz),
			Vector3(minf(xa, xb), 0.0, hz)], GRATE * 0.7, Vector3.UP)
		var x := x_in + 0.12
		while x < hx - 0.05:
			var bx: float = sx * x
			g.poly([Vector3(bx - 0.025, 0.004, -hz), Vector3(bx + 0.025, 0.004, -hz), Vector3(bx + 0.025, 0.004, hz),
				Vector3(bx - 0.025, 0.004, hz)], GRATE * 1.5, Vector3.UP)
			x += 0.22
		for iz in range(1, int(hz * 2.0)):
			var z := -hz + iz
			g.poly([Vector3(minf(xa, xb), 0.006, z - 0.04), Vector3(maxf(xa, xb), 0.006, z - 0.04), Vector3(maxf(xa, xb), 0.006, z + 0.04),
				Vector3(minf(xa, xb), 0.006, z + 0.04)], STEEL * 0.9, Vector3.UP)
	# พรมแดงจากประตูถึงโต๊ะรบ ขอบบรอนซ์
	var cz0 := 0.35
	var cz1 := 7.6
	g.poly([Vector3(-1.25, 0.008, cz0), Vector3(1.25, 0.008, cz0), Vector3(1.25, 0.008, cz1), Vector3(-1.25, 0.008, cz1)], BRONZE, Vector3.UP)
	g.poly([Vector3(-1.1, 0.012, cz0 + 0.12), Vector3(1.1, 0.012, cz0 + 0.12), Vector3(1.1, 0.012, cz1), Vector3(-1.1, 0.012, cz1)], CARPET, Vector3.UP)
	# ลายเตือนหน้าประตูทางออกและช่องเทียบยาน
	_chevrons(g, Vector3(0.0, 0.014, 7.58), Vector3.RIGHT, 1.2, 0.11)
	var ol: Rect2 = HallLayout.rect_of("online")
	_chevrons(g, Vector3(ol.position.x - 0.14, 0.014, ol.get_center().y), Vector3.BACK, ol.size.y * 0.5 - 0.15, 0.11)


## ผนังข้าง sx = -1 (ซ้าย) / +1 (ขวา): แผงเหล็ก แผงล่างบรอนซ์ ซุ้มโค้งแหลมทึบทุกช่วงเสา ท่อ วาล์ว จอ
static func _side_wall(g: PropsLayer.Geo, glow_g: PropsLayer.Geo, rng: RandomNumberGenerator, sx: float, sides: int) -> void:
	var hx := HallLayout.HALF.x
	var hz := HallLayout.HALF.y
	var top := HallLayout.AISLE_Y
	var o := Vector3(sx * hx, 0.0, -hz)
	var u := Vector3(0, 0, 1)
	var n := Vector3(-sx, 0, 0)
	var length := hz * 2.0
	_wall_rect(g, o, u, n, -OVERLAP, length + OVERLAP, -OVERLAP, top + OVERLAP, 0.0, STEEL_DARK * 0.6)
	_panels(g, rng, o, u, n, length, top)
	_wainscot(g, o, u, n, 0.0, length)
	# ซุ้มโค้งแหลมทึบกลางแต่ละช่วงเสา (เว้นที่ช่องเทียบยาน)
	var ol: Rect2 = HallLayout.rect_of("online")
	for i in BAYS.size() - 1:
		var zc := (BAYS[i] + BAYS[i + 1]) * 0.5
		if sx > 0.0 and zc > ol.position.y - 0.5 and zc < ol.end.y + 0.5:
			continue
		var a := minf(1.1, (BAYS[i + 1] - BAYS[i]) * 0.5 - 0.2)
		_wall_poly(g, o, u, n, arch_outline(zc + hz, a + 0.08, 1.02, 3.86, 5.28, 5), 0.008, BRONZE * 0.55)
		_wall_poly(g, o, u, n, arch_outline(zc + hz, a, 1.1, 3.9, 5.2, 5), 0.014, STEEL_DARK * 0.85)
	# จอบนผนัง
	var srng := RandomNumberGenerator.new()
	srng.seed = 5150 + int(sx * 3.0)
	for s in HallLayout.SCREENS:
		var p: Vector3 = s["p"]
		if signf(p.x) != sx:
			continue
		var amber := bool(s["amber"])
		var sc := HallLayout.SCREEN_AMBER if amber else HallLayout.SCREEN_GREEN
		g.box(Vector3(p.x - sx * 0.04, p.y, p.z), Vector3(0.04, 0.42, 0.47), BRONZE * 0.5)
		var f := p.x - sx * 0.082
		glow_g.poly([Vector3(f, p.y - 0.34, p.z - 0.4), Vector3(f, p.y - 0.34, p.z + 0.4), Vector3(f, p.y + 0.34, p.z + 0.4),
			Vector3(f, p.y + 0.34, p.z - 0.4)], sc * 0.3, n)
		var lines := srng.randi_range(3, 5)
		for k in lines:
			var y := p.y + 0.24 - k * 0.48 / maxf(lines - 1, 1)
			var w := srng.randf_range(0.3, 0.7)
			var z0 := p.z - 0.32
			glow_g.poly([Vector3(f - sx * 0.002, y - 0.025, z0), Vector3(f - sx * 0.002, y - 0.025, z0 + w),
				Vector3(f - sx * 0.002, y + 0.025, z0 + w), Vector3(f - sx * 0.002, y + 0.025, z0)], sc * 0.95, n)
	# ท่อสองเส้นตามผนัง เว้นช่วงที่มีจอ คลังแสง ช่องเทียบยาน · ท่อตั้งที่แนวเสาขึ้นไปถึงเพดาน
	var cut: Array[Vector2] = []
	for s in HallLayout.SCREENS:
		var p: Vector3 = s["p"]
		if signf(p.x) == sx:
			cut.append(Vector2(p.z - 0.55, p.z + 0.55))
	if sx < 0.0:
		var ar: Rect2 = HallLayout.rect_of("army")
		cut.append(Vector2(ar.position.y - 0.15, ar.end.y + 0.15))
	else:
		cut.append(Vector2(ol.position.y - 0.15, ol.end.y + 0.15))
	var runs := _subtract(Vector2(-hz + 0.1, hz - 0.1), cut)
	var px := sx * (hx - 0.1)
	var pn := maxi(sides / 2, 5)
	for r in runs:
		if r.y - r.x < 0.6:
			continue
		for y in [2.3, 2.55]:
			tube(g, Vector3(px, y, r.x), Vector3(px, y, r.y), 0.06, pn, BRONZE * 0.75)
			for e in [r.x + 0.06, r.y - 0.06]:
				tube(g, Vector3(px, y, e - 0.04), Vector3(px, y, e + 0.04), 0.08, pn, BRASS * 0.8)
		# วาล์ววงล้อหนึ่งอันต่อช่วง (วงบาง ๆ ขนานผนัง)
		var vz := (r.x + r.y) * 0.5
		var vc := Vector3(sx * (hx - 0.17), 2.42, vz)
		tube(g, Vector3(sx * (hx - 0.1), 2.42, vz), vc, 0.015, 4, BRASS)
		for i in 8:
			var a0 := TAU * i / 8.0
			var a1 := TAU * (i + 1) / 8.0
			var d0 := Vector3(0, sin(a0), cos(a0))
			var d1 := Vector3(0, sin(a1), cos(a1))
			g.poly([vc + d0 * 0.1, vc + d1 * 0.1, vc + d1 * 0.13, vc + d0 * 0.13], BRASS, n)
	for z in [-5.0, 0.5, 5.0 if sx > 0.0 else 5.5]:
		var blocked := false
		for c in cut:
			blocked = blocked or (z > c.x and z < c.y)
		var y0 := 2.62 if sx < 0.0 and absf(z - 0.5) < 0.01 else 2.55
		if not blocked or y0 > 2.6:
			tube(g, Vector3(px, y0, z), Vector3(px, top, z), 0.05, pn, BRONZE * 0.7)


## ช่วง base ลบช่วงใน cut ทั้งหมด (x = เริ่ม, y = จบ)
static func _subtract(base: Vector2, cut: Array[Vector2]) -> Array[Vector2]:
	var out: Array[Vector2] = [base]
	for c in cut:
		var nxt: Array[Vector2] = []
		for r in out:
			if c.y <= r.x or c.x >= r.y:
				nxt.append(r)
				continue
			if c.x > r.x:
				nxt.append(Vector2(r.x, c.x))
			if c.y < r.y:
				nxt.append(Vector2(c.y, r.y))
		out = nxt
	return out


## แผงเหล็ก 2 x 1.5 ม. เหนือแผงล่าง (ขอบมืดคือผนังข้างหลังที่เห็นตามร่อง)
## cut = ช่องประตู (s เริ่ม, s จบ, แถวที่เริ่มต่ำกว่า y นี้ถูกตัด); สุ่มสีครบทุกแผ่นเท่าเดิม ลายส่วนอื่นของยานไม่เปลี่ยน
static func _panels(g: PropsLayer.Geo, rng: RandomNumberGenerator, o: Vector3, u: Vector3, n: Vector3, length: float, top: float,
		cut: Vector3 = Vector3.ZERO) -> void:
	var gap := 0.03
	var y := 1.0
	while y < top - 0.01:
		var y1 := minf(y + 1.5, top)
		var a := 0.0
		while a < length - 0.01:
			var b := minf(a + 2.0, length)
			var k := rng.randf_range(0.86, 1.06)
			if y < cut.z and b > cut.x and a < cut.y:
				if a + gap < cut.x:
					_wall_rect(g, o, u, n, a + gap, cut.x, y + gap, y1 - gap, 0.004, STEEL * k)
				if b - gap > cut.y:
					_wall_rect(g, o, u, n, cut.y, b - gap, y + gap, y1 - gap, 0.004, STEEL * k)
			else:
				_wall_rect(g, o, u, n, a + gap, b - gap, y + gap, y1 - gap, 0.004, STEEL * k)
			a = b
		y = y1


## แผงล่างบรอนซ์เข้มสูง 1 ม. (เรียบไปกับผนัง) กับคิ้วบน
static func _wainscot(g: PropsLayer.Geo, o: Vector3, u: Vector3, n: Vector3, s0: float, s1: float) -> void:
	var a := s0
	while a < s1 - 0.001:
		var b := minf(a + 2.0, s1)
		_wall_rect(g, o, u, n, a, b, 0.0, 1.0, 0.006, BRONZE * (0.42 if int(a / 2.0) % 2 == 0 else 0.46))
		a = b
	_wall_rect(g, o, u, n, s0, s1, 0.96, 1.04, 0.03, BRASS * 0.7)
	g.poly([wp(o, u, n, s0, 1.04, 0.03), wp(o, u, n, s1, 1.04, 0.03), wp(o, u, n, s1, 1.04, 0.0), wp(o, u, n, s0, 1.04, 0.0)],
		BRASS * 0.8, Vector3.UP)


## ผนังหน้า (z = +8): แผงเหล็ก หน้าจั่วเหนือ 6.3 ตามโค้งเพดาน ดอกกุหลาบทึบมีลายเทียนตรงกลาง
static func _front_wall(g: PropsLayer.Geo, rng: RandomNumberGenerator) -> void:
	var hx := HallLayout.HALF.x
	var hz := HallLayout.HALF.y
	var top := HallLayout.AISLE_Y
	var o := Vector3(hx, 0.0, hz)
	var u := Vector3(-1, 0, 0)
	var n := Vector3(0, 0, -1)
	# ช่องประตูอารีน่า (ARENA_SPEC §2.2): ผนังแผ่นหลัง แผงเหล็ก แผงล่าง เว้นช่องโค้งแหลม
	var ad := HallLayout.ARENA_DOOR
	var s0 := hx - float(ad["x1"])
	var s1 := hx - float(ad["x0"])
	var ah := (s1 - s0) * 0.5
	var sp := float(ad["spring"])
	# แผ่นข้างช่องแบ่งที่จุดเริ่มโค้ง ให้มุมตรงกับแถบเหนือโค้ง (ไม่มีรอยต่อรูปตัว T)
	for r in [Vector2(-OVERLAP, s0), Vector2(s1, hx * 2.0 + OVERLAP)]:
		_wall_rect(g, o, u, n, r.x, r.y, -OVERLAP, sp, 0.0, STEEL_DARK * 0.6)
		_wall_rect(g, o, u, n, r.x, r.y, sp, top + OVERLAP, 0.0, STEEL_DARK * 0.6)
	_over_arch(g, o, u, n, s0 + ah, Vector3(ah, float(ad["spring"]), float(ad["apex"])), top + OVERLAP, 0.0, STEEL_DARK * 0.6)
	_panels(g, rng, o, u, n, hx * 2.0, top, Vector3(s0, s1, float(ad["apex"])))
	_wainscot(g, o, u, n, 0.0, s0)
	_wainscot(g, o, u, n, s1, hx * 2.0)
	var gable: Array[Vector3] = []
	for q in _gable_line():
		gable.append(Vector3(q.x, q.y, hz))
	g.poly(gable, STEEL * 0.8, n)
	# ดอกกุหลาบทึบ
	var c := Vector3(0.0, 8.2, hz - 0.05)
	var segs := 16
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		g.poly([c, c + d0 * 1.6, c + d1 * 1.6], STEEL_DARK * 0.5, n)
		g.poly([c + d0 * 1.5 + n * 0.01, c + d1 * 1.5 + n * 0.01, c + d1 * 1.72 + n * 0.01, c + d0 * 1.72 + n * 0.01], BRONZE * 0.8, n)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		var d := Vector3(cos(a), sin(a), 0)
		var w := Vector3(-d.y, d.x, 0) * 0.04
		g.poly([c + d * 0.5 - w + n * 0.012, c + d * 1.5 - w + n * 0.012, c + d * 1.5 + w + n * 0.012, c + d * 0.5 + w + n * 0.012], BRONZE * 0.7, n)
	emblem(g, c + n * 0.014, Vector3(-1, 0, 0), n, 0.45, BRONZE * 0.9, WAX * 0.8, GOLD)


## ผิวผนังเหนือโค้งแหลม (กลาง cs, arch = ครึ่งกว้าง จุดเริ่มโค้ง ยอด) ถึงความสูง ytop เป็นแถบตั้งตามจุดบนโค้ง
static func _over_arch(g: PropsLayer.Geo, o: Vector3, u: Vector3, n: Vector3, cs: float, arch: Vector3, ytop: float,
		off: float, col: Color) -> void:
	var pts := arch_pts(arch.x, arch.y, arch.z, ARENA_K)
	for side in [-1.0, 1.0]:
		for j in ARENA_K:
			_wall_poly(g, o, u, n, [Vector2(cs + side * pts[j].x, pts[j].y), Vector2(cs + side * pts[j + 1].x, pts[j + 1].y),
				Vector2(cs + side * pts[j + 1].x, ytop), Vector2(cs + side * pts[j].x, ytop)], off, col)


## ประตูอารีน่าฝั่งห้อง (ARENA_SPEC §2.2): คิ้วบรอนซ์เรียบผนังรอบช่อง กรอบโค้งแหลมบรอนซ์ยื่น 0.25 ม. ในช่อง
## (อยู่ในกล่องกันของสถานี) ลายเตือนหน้าธรณี ไฟอำพันที่ยอดกรอบ
static func _arena_door(g: PropsLayer.Geo, glow_g: PropsLayer.Geo) -> void:
	var ad := HallLayout.ARENA_DOOR
	var hx := HallLayout.HALF.x
	var hz := HallLayout.HALF.y
	var o := Vector3(hx, 0.0, hz)
	var u := Vector3(-1, 0, 0)
	var n := Vector3(0, 0, -1)
	var sp := float(ad["spring"])
	var ap := float(ad["apex"])
	var a := (float(ad["x1"]) - float(ad["x0"])) * 0.5
	var cs := hx - (float(ad["x0"]) + float(ad["x1"])) * 0.5
	var fw := 0.18
	var depth := 0.25
	var inner := Vector3(a - fw, sp, ap - 0.24)
	# แผงเหล็กเหนือโค้งถึงแนวแผงแถวบน กับคิ้วบรอนซ์เรียบผนัง
	_over_arch(g, o, u, n, cs, Vector3(a, sp, ap), 3.97, 0.004, STEEL * 0.95)
	_arch_band(g, o, u, n, cs, Vector3(a + 0.12, sp, ap + 0.17), Vector3(a, sp, ap), ARENA_K, 0.012, BRONZE * 0.7)
	for side in [-1.0, 1.0]:
		_wall_rect(g, o, u, n, cs + side * a, cs + side * (a + 0.12), 0.0, sp, 0.012, BRONZE * 0.7)
	# แผ่นรองในเนื้อผนังรอบขอบช่อง (ลึก 0.1 ม.): รอยต่อเส้นผมระหว่างกรอบกับผนังไม่เห็นทะลุ
	_over_arch(g, o, u, n, cs, Vector3(a, sp, ap), ap + 0.4, -0.1, STEEL_DARK * 0.5)
	for side in [-1.0, 1.0]:
		_wall_rect(g, o, u, n, cs + side * (a + 0.25), cs + side * a, -OVERLAP, ap + 0.4, -0.1, STEEL_DARK * 0.5)
	# กรอบ: หน้า ข้างใน ข้างนอก
	_arch_band(g, o, u, n, cs, Vector3(a, sp, ap), inner, ARENA_K, depth, BRONZE * 0.9)
	var pin := arch_pts(inner.x, inner.y, inner.z, ARENA_K)
	var pout := arch_pts(a, sp, ap, ARENA_K)
	for side in [-1.0, 1.0]:
		_wall_rect(g, o, u, n, cs + side * (a - fw), cs + side * a, 0.0, sp, depth, BRONZE * 0.9)
		var si: float = cs + side * (a - fw)
		var so: float = cs + side * a
		g.poly([wp(o, u, n, si, 0.0, 0.0), wp(o, u, n, si, sp, 0.0), wp(o, u, n, si, sp, depth), wp(o, u, n, si, 0.0, depth)],
			BRONZE * 0.7, -u * side)
		g.poly([wp(o, u, n, so, 0.0, 0.0), wp(o, u, n, so, sp, 0.0), wp(o, u, n, so, sp, depth), wp(o, u, n, so, 0.0, depth)],
			BRONZE * 0.75, u * side)
		for j in ARENA_K:
			var q0 := Vector2(cs + side * pin[j].x, pin[j].y)
			var q1 := Vector2(cs + side * pin[j + 1].x, pin[j + 1].y)
			g.poly([wp(o, u, n, q0.x, q0.y, 0.0), wp(o, u, n, q1.x, q1.y, 0.0), wp(o, u, n, q1.x, q1.y, depth), wp(o, u, n, q0.x, q0.y, depth)],
				BRONZE * 0.62, Vector3(0.0, -1.0, 0.0) + u * (cs - q0.x) * 0.5)
			var r0 := Vector2(cs + side * pout[j].x, pout[j].y)
			var r1 := Vector2(cs + side * pout[j + 1].x, pout[j + 1].y)
			g.poly([wp(o, u, n, r0.x, r0.y, 0.0), wp(o, u, n, r1.x, r1.y, 0.0), wp(o, u, n, r1.x, r1.y, depth), wp(o, u, n, r0.x, r0.y, depth)],
				BRONZE * 0.8, Vector3(0.0, 1.0, 0.0) + u * (r0.x - cs) * 0.5)
	# ธรณีเหล็กกับลายเตือนหน้าประตู
	var cx := (float(ad["x0"]) + float(ad["x1"])) * 0.5
	g.box(Vector3(cx, 0.015, hz - 0.12), Vector3(a - fw, 0.015, 0.12), STEEL * 0.7)
	_chevrons(g, Vector3(cx, 0.014, 7.58), Vector3.RIGHT, 1.0, 0.11)
	# ไฟอำพันที่ยอดกรอบ (ไม่อบแสง)
	var ly := (inner.z + ap) * 0.5 - 0.02
	var lz := hz - depth - 0.006
	glow_g.poly([Vector3(cx - 0.07, ly - 0.06, lz), Vector3(cx + 0.07, ly - 0.06, lz), Vector3(cx + 0.07, ly + 0.06, lz),
		Vector3(cx - 0.07, ly + 0.06, lz)], LAMP_AMBER, n)


## ทางเดินสั้นหลังประตูอารีน่า z 8.0 → 11.0 (ARENA_SPEC §2.2): ผิวในช่องผนัง พื้นเหล็กกับตะแกรง ผนังข้าง ซี่โครงหนึ่งวง
## เพดานโค้งแหลมต่อจากโค้งประตู รางสายไฟ ไฟอำพันใต้สัน ปิดท้ายด้วยประตูแรงดันที่ปิดสนิท (ไม่มีช่องมองทะลุ)
## อบแสงแยก: ไม่มีเทียน แสงอำพันดวงเดียว ARENA_STUB_LIGHT แล้วต่อท้ายโครงยาน
static func _arena_stub() -> PropsLayer.Geo:
	var g := PropsLayer.Geo.new()
	var glow_g := PropsLayer.Geo.new()
	var ad := HallLayout.ARENA_DOOR
	var x0 := float(ad["x0"])
	var x1 := float(ad["x1"])
	var sp := float(ad["spring"])
	var ap := float(ad["apex"])
	var a := (x1 - x0) * 0.5
	var cx := (x0 + x1) * 0.5
	var zw := HallLayout.HALF.y
	var zb := zw + HallLayout.WALL_T
	var ze := zb + float(ad["stub"])
	var zr := (zb + ze) * 0.5
	# โปรไฟล์ช่อง (x, y): ผนังซ้าย โค้ง ผนังขวา
	# ผนังเริ่มใต้พื้นเล็กน้อย พื้นกว้างเลยผนัง (ไม่มีรอยต่อรูปตัว T ให้เห็นทะลุ)
	var prof := PackedVector2Array([Vector2(x0, -OVERLAP)])
	var pts := arch_pts(a, sp, ap, ARENA_K)
	for j in pts.size():
		prof.append(Vector2(cx - pts[j].x, pts[j].y))
	for j in range(pts.size() - 2, -1, -1):
		prof.append(Vector2(cx + pts[j].x, pts[j].y))
	prof.append(Vector2(x1, -OVERLAP))
	var segs := [[zw - 0.004, zb, STEEL * 0.7], [zb, zr, STEEL * 0.8], [zr, ze + 0.004, STEEL * 0.8]]
	for sg in segs:
		for i in prof.size() - 1:
			var p := prof[i]
			var q := prof[i + 1]
			var mid := (p + q) * 0.5
			var col: Color = sg[2] if p.y > sp - 0.01 and q.y > sp - 0.01 else (sg[2] as Color) * 0.92
			g.poly([Vector3(p.x, p.y, sg[0]), Vector3(q.x, q.y, sg[0]), Vector3(q.x, q.y, sg[1]), Vector3(p.x, p.y, sg[1])], col,
				Vector3(cx - mid.x, 1.6 - mid.y, 0.0))
	# พื้น: แผ่นเหล็ก ตะแกรงกลาง คานขวาง
	g.poly([Vector3(x0 - OVERLAP, 0.0, zw - 0.004), Vector3(x1 + OVERLAP, 0.0, zw - 0.004), Vector3(x1 + OVERLAP, 0.0, ze + OVERLAP),
		Vector3(x0 - OVERLAP, 0.0, ze + OVERLAP)], DECK * 0.9, Vector3.UP)
	g.poly([Vector3(cx - 0.4, 0.004, zb + 0.1), Vector3(cx + 0.4, 0.004, zb + 0.1), Vector3(cx + 0.4, 0.004, ze - 0.1),
		Vector3(cx - 0.4, 0.004, ze - 0.1)], GRATE * 0.7, Vector3.UP)
	var z := zb + 0.35
	while z < ze - 0.2:
		g.poly([Vector3(cx - 0.4, 0.007, z - 0.03), Vector3(cx + 0.4, 0.007, z - 0.03), Vector3(cx + 0.4, 0.007, z + 0.03),
			Vector3(cx - 0.4, 0.007, z + 0.03)], GRATE * 1.6, Vector3.UP)
		z += 0.3
	# แผงล่างบรอนซ์บนผนังข้าง
	for sx in [-1.0, 1.0]:
		var xw: float = cx + sx * (a - 0.006)
		g.poly([Vector3(xw, 0.0, zb), Vector3(xw, 1.0, zb), Vector3(xw, 1.0, ze), Vector3(xw, 0.0, ze)], BRONZE * 0.44, Vector3(-sx, 0.0, 0.0))
		g.box(Vector3(cx + sx * (a - 0.06), sp * 0.5, zr), Vector3(0.06, sp * 0.5, 0.06), STEEL * 0.95)
	# ซี่โครงโค้งที่กลางทางเดิน (ลึก 0.12 ม.)
	var rin := Vector3(a - 0.12, sp, ap - 0.16)
	_arch_band(g, Vector3(0.0, 0.0, zr - 0.06), Vector3(1, 0, 0), Vector3(0, 0, -1), cx, Vector3(a, sp, ap), rin, ARENA_K, 0.0, STEEL * 0.95)
	var pr := arch_pts(rin.x, rin.y, rin.z, ARENA_K)
	for side in [-1.0, 1.0]:
		for j in ARENA_K:
			var q0 := Vector3(cx + side * pr[j].x, pr[j].y, 0.0)
			var q1 := Vector3(cx + side * pr[j + 1].x, pr[j + 1].y, 0.0)
			g.poly([q0 + Vector3(0, 0, zr - 0.06), q1 + Vector3(0, 0, zr - 0.06), q1 + Vector3(0, 0, zr + 0.06), q0 + Vector3(0, 0, zr + 0.06)],
				STEEL * 0.7, Vector3(cx - q0.x, 1.6 - q0.y, 0.0))
	# รางสายไฟผนังขวา
	g.box(Vector3(x1 - 0.1, 2.2, zr), Vector3(0.09, 0.025, (ze - zb) * 0.5 - 0.02), STEEL_DARK * 0.9, 0.0, true)
	for k in 2:
		var xk := x1 - 0.06 - k * 0.07
		tube(g, Vector3(xk, 2.25, zb), Vector3(xk, 2.25, ze), 0.025, 4, Color(0.30, 0.10, 0.08) if k == 0 else STEEL_DARK * 0.6)
	# ประตูแรงดัน: แผ่นหลังเต็มโปรไฟล์ (ช่องเหนือบานปิดด้วยเหล็ก) บานสองบาน คิ้วบรอนซ์ ลายเตือน
	var back: Array[Vector3] = []
	for q in prof:
		back.append(Vector3(q.x, q.y, ze))
	g.poly(back, STEEL_DARK * 0.85, Vector3(0, 0, -1))
	var lh := 2.3
	var lz := ze - 0.05
	for sx in [-1.0, 1.0]:
		g.box(Vector3(cx + sx * 0.49, lh * 0.5, lz), Vector3(0.47, lh * 0.5, 0.05), STEEL * (0.78 if sx < 0.0 else 0.72))
	var fz := ze - 0.104
	g.poly([Vector3(cx - 0.025, 0.0, fz), Vector3(cx + 0.025, 0.0, fz), Vector3(cx + 0.025, lh, fz), Vector3(cx - 0.025, lh, fz)], STEEL_DARK * 0.4, Vector3(0, 0, -1))
	for y in [0.95, 1.85]:
		g.poly([Vector3(cx - 0.96, y, fz), Vector3(cx + 0.96, y, fz), Vector3(cx + 0.96, y + 0.1, fz), Vector3(cx - 0.96, y + 0.1, fz)], BRONZE * 0.85, Vector3(0, 0, -1))
	g.box(Vector3(cx, lh + 0.06, ze - 0.05), Vector3(a, 0.06, 0.06), BRONZE * 0.8)
	g.poly([Vector3(cx - 0.96, 0.12, fz), Vector3(cx + 0.96, 0.12, fz), Vector3(cx + 0.96, 0.44, fz), Vector3(cx - 0.96, 0.44, fz)], HAZARD_DARK, Vector3(0, 0, -1))
	var xs := cx - 0.92
	while xs + 0.3 <= cx + 0.94:
		g.poly([Vector3(xs, 0.14, fz - 0.002), Vector3(xs + 0.12, 0.14, fz - 0.002), Vector3(xs + 0.26, 0.42, fz - 0.002),
			Vector3(xs + 0.14, 0.42, fz - 0.002)], HAZARD, Vector3(0, 0, -1))
		xs += 0.3
	bake(g, PackedVector3Array(), [HallLayout.ARENA_STUB_LIGHT])
	# ไฟอำพันใต้สันเพดาน กับไฟเหนือประตูแรงดัน (ไม่อบแสง)
	var ry := ap - 0.06
	glow_g.poly([Vector3(cx - 0.05, ry, zb + 0.2), Vector3(cx + 0.05, ry, zb + 0.2), Vector3(cx + 0.05, ry, ze - 0.2),
		Vector3(cx - 0.05, ry, ze - 0.2)], LAMP_AMBER * 0.9, Vector3.DOWN)
	glow_g.poly([Vector3(cx - 0.12, 2.72, fz), Vector3(cx + 0.12, 2.72, fz), Vector3(cx + 0.12, 2.86, fz), Vector3(cx - 0.12, 2.86, fz)],
		LAMP_AMBER, Vector3(0, 0, -1))
	append(g, glow_g)
	return g


## เส้นขอบบนของหน้าจั่ว (x, y): จาก 6.3 ด้านขวา ตามโค้งเพดานถึงซ้าย (รูปนูน)
static func _gable_line() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var prof := HallLayout.VAULT_PROFILE
	var top := HallLayout.AISLE_Y
	var x_r := _vault_x_at(top)
	out.append(Vector2(x_r, top))
	for i in range(1, prof.size()):
		out.append(prof[i])
	for i in range(prof.size() - 2, 0, -1):
		out.append(Vector2(-prof[i].x, prof[i].y))
	out.append(Vector2(-x_r, top))
	return out


## x ของโค้งเพดาน (ซีกขวา) ที่ความสูง y (ช่วงแรกของโปรไฟล์)
static func _vault_x_at(y: float) -> float:
	var prof := HallLayout.VAULT_PROFILE
	for i in prof.size() - 1:
		if y >= prof[i].y and y <= prof[i + 1].y:
			return lerpf(prof[i].x, prof[i + 1].x, (y - prof[i].y) / (prof[i + 1].y - prof[i].y))
	return 0.0


## ผนังหลัง (z = -8) กับหน้าต่างโค้งแหลมสามช่อง: แถบตั้งรอบช่อง ผิวในช่องเต็มความหนาผนัง ลายฉลุบรอนซ์ ขอบหน้าต่าง ป้ายชื่อ
static func _back_wall(g: PropsLayer.Geo) -> void:
	var hx := HallLayout.HALF.x
	var zf := -HallLayout.HALF.y
	var zb := zf - HallLayout.WALL_T
	var n := Vector3(0, 0, 1)
	var k_of := func(w: Dictionary) -> int: return 7 if float(w["x1"]) - float(w["x0"]) > 4.0 else 4
	# ขอบโค้งของแต่ละช่อง เป็นเส้นหลายเหลี่ยม (x, y) จากจุดเริ่มโค้งซ้ายถึงขวา
	var arcs: Array = []
	var xs := PackedFloat32Array([-hx - OVERLAP, hx + OVERLAP, -HallLayout.VAULT_PROFILE[0].x, HallLayout.VAULT_PROFILE[0].x])
	for q in HallLayout.VAULT_PROFILE:
		xs.append(q.x)
		xs.append(-q.x)
	for w in HallLayout.WINDOWS:
		var cx := (float(w["x0"]) + float(w["x1"])) * 0.5
		var a := (float(w["x1"]) - float(w["x0"])) * 0.5
		var pts := arch_pts(a, float(w["spring"]), float(w["apex"]), k_of.call(w))
		var line := PackedVector2Array()
		for j in pts.size():
			line.append(Vector2(cx - pts[j].x, pts[j].y))
		for j in range(pts.size() - 2, -1, -1):
			line.append(Vector2(cx + pts[j].x, pts[j].y))
		arcs.append(line)
		for q in line:
			xs.append(q.x)
	xs.sort()
	var top_at := func(x: float) -> float: return maxf(HallLayout.vault_y(x), HallLayout.AISLE_Y) + OVERLAP
	for i in xs.size() - 1:
		var xa := xs[i]
		var xb := xs[i + 1]
		if xb - xa < 0.0005:
			continue
		var mid := (xa + xb) * 0.5
		var win := -1
		for wi in HallLayout.WINDOWS.size():
			var w: Dictionary = HallLayout.WINDOWS[wi]
			if mid > float(w["x0"]) and mid < float(w["x1"]):
				win = wi
		var ta: float = top_at.call(xa)
		var tb: float = top_at.call(xb)
		if win < 0:
			g.poly([Vector3(xa, -OVERLAP, zf), Vector3(xb, -OVERLAP, zf), Vector3(xb, tb, zf), Vector3(xa, ta, zf)], STEEL * 0.92, n)
			continue
		var w2: Dictionary = HallLayout.WINDOWS[win]
		var sill := float(w2["sill"])
		var ya := _line_y(arcs[win], xa)
		var yb := _line_y(arcs[win], xb)
		g.poly([Vector3(xa, -OVERLAP, zf), Vector3(xb, -OVERLAP, zf), Vector3(xb, sill, zf), Vector3(xa, sill, zf)], STEEL * 0.92, n)
		g.poly([Vector3(xa, ya, zf), Vector3(xb, yb, zf), Vector3(xb, tb, zf), Vector3(xa, ta, zf)], STEEL * 0.92, n)
	# แผงล่างบรอนซ์บนเสาระหว่างช่อง กับเส้นตะเข็บแนวนอน
	var solid := _subtract(Vector2(-hx, hx), _window_cuts())
	for r in solid:
		_wainscot(g, Vector3(0, 0, zf), Vector3(1, 0, 0), n, r.x, r.y)
		for y in [2.5, 4.0, 5.5]:
			g.poly([Vector3(r.x, y - 0.015, zf + 0.004), Vector3(r.y, y - 0.015, zf + 0.004), Vector3(r.y, y + 0.015, zf + 0.004),
				Vector3(r.x, y + 0.015, zf + 0.004)], STEEL_DARK * 0.7, n)
	for wi in HallLayout.WINDOWS.size():
		var w: Dictionary = HallLayout.WINDOWS[wi]
		var x0 := float(w["x0"])
		var x1 := float(w["x1"])
		var sill := float(w["sill"])
		var sp := float(w["spring"])
		var line: PackedVector2Array = arcs[wi]
		# ผิวในช่อง: ข้างสองด้าน ขอบล่าง ใต้โค้ง (เต็มความหนาผนัง)
		g.poly([Vector3(x0, sill, zf), Vector3(x0, sp, zf), Vector3(x0, sp, zb), Vector3(x0, sill, zb)], STEEL * 0.7, Vector3.RIGHT)
		g.poly([Vector3(x1, sill, zf), Vector3(x1, sp, zf), Vector3(x1, sp, zb), Vector3(x1, sill, zb)], STEEL * 0.7, Vector3.LEFT)
		g.poly([Vector3(x0, sill, zf), Vector3(x1, sill, zf), Vector3(x1, sill, zb), Vector3(x0, sill, zb)], STEEL * 0.8, Vector3.UP)
		var cx := (x0 + x1) * 0.5
		for j in line.size() - 1:
			var p0 := line[j]
			var p1 := line[j + 1]
			var inward := Vector3(cx - (p0.x + p1.x) * 0.5, -1.0, 0.0)
			g.poly([Vector3(p0.x, p0.y, zf), Vector3(p1.x, p1.y, zf), Vector3(p1.x, p1.y, zb), Vector3(p0.x, p0.y, zb)], STEEL * 0.62, inward)
		# ขอบหน้าต่างด้านใน (ยื่น SILL_DEPTH ไม่ตัดผ่านไข่ที่ยืนชิด) กับราวเครื่องวัดทองเหลืองใต้ขอบ
		var sd := HallLayout.SILL_DEPTH * 0.5
		g.box(Vector3(cx, sill - 0.03, zf + sd), Vector3((x1 - x0) * 0.5 + 0.12, 0.03, sd), BRONZE * 0.8)
		g.poly([Vector3(x0, 0.62, zf + 0.005), Vector3(x1, 0.62, zf + 0.005), Vector3(x1, 0.8, zf + 0.005), Vector3(x0, 0.8, zf + 0.005)], BRASS * 0.8, n)
		for k in int((x1 - x0) / 0.8):
			var dc := Vector3(x0 + 0.4 + k * 0.8, 0.71, zf + 0.008)
			g.poly([dc + Vector3(-0.05, 0, 0), dc + Vector3(0, -0.05, 0), dc + Vector3(0.05, 0, 0), dc + Vector3(0, 0.05, 0)], STEEL_DARK, n)
		# ลูกกรงเหล็กเข้ม (กลางความหนาผนัง) วงกลมกับลายเทียนบรอนซ์ ไม่ให้ดูเป็นกรอบหน้าต่างไม้
		var zt := zf - 0.25
		var tc := STEEL_DARK * 0.8
		var rc := BRONZE * 0.54
		if x1 - x0 > 4.0:
			for mx in [-1.6, 1.6]:
				g.box(Vector3(cx + mx, (sill + 8.7) * 0.5, zt), Vector3(0.05, (8.7 - sill) * 0.5, 0.06), tc, 0.0, true)
			g.box(Vector3(cx, (sill + 6.7) * 0.5, zt), Vector3(0.05, (6.7 - sill) * 0.5, 0.06), tc, 0.0, true)
			for ty in [2.6, 4.4]:
				g.box(Vector3(cx, ty, zt), Vector3((x1 - x0) * 0.5, 0.05, 0.06), tc, 0.0, true)
			# วงกลมด้านบนกับลายเทียน
			var oc := Vector3(cx, 7.6, zt + 0.07)
			for i in 16:
				var a0 := TAU * i / 16.0
				var a1 := TAU * (i + 1) / 16.0
				var d0 := Vector3(cos(a0), sin(a0), 0)
				var d1 := Vector3(cos(a1), sin(a1), 0)
				g.poly([oc + d0 * 0.8, oc + d1 * 0.8, oc + d1 * 0.92, oc + d0 * 0.92], rc, n)
			emblem(g, oc, Vector3.RIGHT, n, 0.5, rc, rc * 1.25, BRONZE * 0.9, 12)
		else:
			g.box(Vector3(cx, (sill + float(w["apex"])) * 0.5, zt), Vector3(0.05, (float(w["apex"]) - sill) * 0.5, 0.06), tc, 0.0, true)
			g.box(Vector3(cx, 2.6, zt), Vector3((x1 - x0) * 0.5, 0.05, 0.06), tc, 0.0, true)
	# ป้ายชื่อสถานที่: แผ่นบรอนซ์ใต้โค้งหน้าต่างกลาง (ข้อความเป็น Label3D ของ HallWorld)
	var ts := HallLayout.TITLE_SIGN
	g.box(Vector3(ts.x, ts.y, zf + 0.03), Vector3(2.0, 0.35, 0.03), BRONZE * 0.7, 0.0, true)
	g.box(Vector3(ts.x, ts.y, zf + 0.05), Vector3(1.9, 0.29, 0.012), STEEL_DARK * 0.6)


static func _window_cuts() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for w in HallLayout.WINDOWS:
		out.append(Vector2(float(w["x0"]), float(w["x1"])))
	return out


## y ของเส้นหลายเหลี่ยม line (x เรียงจากน้อยไปมาก) ที่ x
static func _line_y(line: PackedVector2Array, x: float) -> float:
	for j in line.size() - 1:
		var a := line[j]
		var b := line[j + 1]
		if x >= a.x - 0.0001 and x <= b.x + 0.0001:
			return a.y if b.x - a.x < 0.0001 else lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return line[0].y


## เสาเหล็กเป็นกลุ่ม: ฐานแปดเหลี่ยม ลำเสากลาง + เสาเล็กสี่ต้น หัวเสาบรอนซ์ที่ซี่โค้งเริ่ม
static func _columns(g: PropsLayer.Geo, sides: int) -> void:
	var small := maxi(sides / 2, 5)
	for p in HallLayout.PILLARS:
		g.prism(p.x, 0.0, p.y, 0.52, 0.25, 8, STEEL * 0.75, 1.0, PI / 8.0)
		g.prism(p.x, 0.25, p.y, 0.33, 5.15, sides, STEEL * 0.95, 1.0, 0.0, false)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			g.prism(p.x + d.x * 0.33, 0.25, p.y + d.y * 0.33, 0.1, 5.15, small, STEEL * 1.08, 1.0, 0.0, false)
		g.prism(p.x, 5.4, p.y, 0.46, 0.2, sides, BRONZE * 0.9)
		g.prism(p.x, 5.6, p.y, 0.38, 0.4, sides, STEEL * 0.8, 1.0, 0.0, false)


## เพดานโค้งแหลมเหนือโถงกลาง ซี่โค้งขวาง ซี่ทแยงทุกช่วง สันกลาง และเพดานเรียบของทางเดินข้าง
static func _vault(g: PropsLayer.Geo, rng: RandomNumberGenerator) -> void:
	var hz := HallLayout.HALF.y
	var prof := _full_profile()
	var cen := Vector2(0.0, 6.5)
	# แผ่นเพดาน
	for b in BAYS.size() - 1:
		var z0 := BAYS[b] - (OVERLAP if b == 0 else 0.0)
		var z1 := BAYS[b + 1] + (OVERLAP if b == BAYS.size() - 2 else 0.0)
		for i in prof.size() - 1:
			var p0 := prof[i]
			var p1 := prof[i + 1]
			var m := (p0 + p1) * 0.5
			var col := STEEL_DARK * (rng.randf_range(0.92, 1.1) * (1.06 if i % 2 == 0 else 0.94))
			g.poly([Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1)], col,
				Vector3(cen.x - m.x, cen.y - m.y, 0.0))
	# ซี่โค้งขวางที่แนวเสาและชิดผนังหน้า/หลัง
	var rib := BRONZE * 0.5
	for zr in [-5.0, 0.5, 5.5, -hz + 0.16, hz - 0.16]:
		_rib_arch(g, prof, zr, 0.15, 0.25, rib)
	# ซี่ทแยง (สองเส้นไขว้ในแต่ละช่วง)
	var arc := PackedFloat32Array([0.0])
	for i in prof.size() - 1:
		arc.append(arc[i] + prof[i].distance_to(prof[i + 1]))
	var total := arc[arc.size() - 1]
	for b in BAYS.size() - 1:
		for dirz in [0, 1]:
			var za := BAYS[b] if dirz == 0 else BAYS[b + 1]
			var zz := BAYS[b + 1] if dirz == 0 else BAYS[b]
			for i in prof.size() - 1:
				var q0 := _rib_point(prof, i, za + (zz - za) * arc[i] / total, 0.2, cen)
				var q1 := _rib_point(prof, i + 1, za + (zz - za) * arc[i + 1] / total, 0.2, cen)
				var d := (q1 - q0).normalized()
				var nn := Vector3(cen.x - (prof[i].x + prof[i + 1].x) * 0.5, cen.y - (prof[i].y + prof[i + 1].y) * 0.5, 0.0).normalized()
				var w := d.cross(nn).normalized() * 0.12
				g.poly([q0 - w, q1 - w, q1 + w, q0 + w], rib * 1.1, nn)
	# สันกลาง
	var apex := prof[prof.size() / 2]
	g.box(Vector3(0.0, apex.y - 0.13, 0.0), Vector3(0.15, 0.13, hz), rib, 0.0, true)
	# เพดานเรียบทางเดินข้าง + ซี่ขวางที่แนวเสา
	var ay := HallLayout.AISLE_Y
	var hx := HallLayout.HALF.x
	for sx in [-1.0, 1.0]:
		var xa: float = sx * 8.3
		var xb: float = sx * (hx + OVERLAP)
		g.poly([Vector3(minf(xa, xb), ay, -hz - OVERLAP), Vector3(maxf(xa, xb), ay, -hz - OVERLAP), Vector3(maxf(xa, xb), ay, hz + OVERLAP),
			Vector3(minf(xa, xb), ay, hz + OVERLAP)], STEEL_DARK * 0.9, Vector3.DOWN)
		for z in [-5.0, 0.5, 5.5]:
			g.box(Vector3(sx * (8.5 + hx) * 0.5, ay - 0.13, z), Vector3((hx - 8.5) * 0.5, 0.13, 0.15), rib, 0.0, true)


## โปรไฟล์เพดานเต็ม (x, y) จากซ้าย (-8.5) ผ่านสันถึงขวา (+8.5)
static func _full_profile() -> PackedVector2Array:
	var prof := HallLayout.VAULT_PROFILE
	var out := PackedVector2Array()
	for i in prof.size():
		out.append(Vector2(-prof[i].x, prof[i].y))
	for i in range(prof.size() - 2, -1, -1):
		out.append(prof[i])
	return out


## จุดบนซี่โค้งที่จุดโปรไฟล์ i ที่ z ยื่นลงจากแผ่นเพดาน depth (ไปทางกลาง cen)
static func _rib_point(prof: PackedVector2Array, i: int, z: float, depth: float, cen: Vector2) -> Vector3:
	var p := prof[i]
	var d := (cen - p).normalized()
	return Vector3(p.x + d.x * depth, p.y + d.y * depth, z)


## ซี่โค้งขวางตามโปรไฟล์ที่ z = zr: หน้าล่างกับข้างสองด้าน
static func _rib_arch(g: PropsLayer.Geo, prof: PackedVector2Array, zr: float, hw: float, depth: float, col: Color) -> void:
	var cen := Vector2(0.0, 6.5)
	for i in prof.size() - 1:
		var a := Vector3(prof[i].x, prof[i].y, 0.0)
		var b := Vector3(prof[i + 1].x, prof[i + 1].y, 0.0)
		var ai := _rib_point(prof, i, 0.0, depth, cen)
		var bi := _rib_point(prof, i + 1, 0.0, depth, cen)
		var nn := Vector3(cen.x - (a.x + b.x) * 0.5, cen.y - (a.y + b.y) * 0.5, 0.0)
		var z0 := Vector3(0, 0, zr - hw)
		var z1 := Vector3(0, 0, zr + hw)
		g.poly([ai + z0, bi + z0, bi + z1, ai + z1], col, nn)
		g.poly([a + z0, b + z0, bi + z0, ai + z0], col * 0.85, Vector3.FORWARD)
		g.poly([a + z1, b + z1, bi + z1, ai + z1], col * 0.85, Vector3.BACK)


## สายไฟห้อยโค้งระหว่างซี่โค้งในโถงกลาง (สูง 6.3–7.2) สี่เส้นต่อช่วงต่อข้าง
static func _cables(g: PropsLayer.Geo) -> void:
	var cols := [STEEL_DARK * 0.8, Color(0.30, 0.10, 0.08), STEEL_DARK * 0.6, BRONZE * 0.4]
	var ends := PackedFloat32Array([-7.74, -5.0, 0.5, 5.5, 7.74])
	for sx in [-1.0, 1.0]:
		for b in ends.size() - 1:
			for k in 4:
				var x: float = sx * (7.72 + k * 0.07)
				var y0 := HallLayout.vault_y(x) - 0.08
				var sag := 0.38 + 0.06 * k
				var z0 := ends[b]
				var z1 := ends[b + 1]
				var prev := Vector3(x, y0, z0)
				for s in range(1, 7):
					var t := s / 6.0
					var p := Vector3(x, y0 - sag * 4.0 * t * (1.0 - t), lerpf(z0, z1, t))
					tube(g, prev, p, 0.04, 3, cols[k])
					prev = p


## ประตูทางออกในผนังหน้า: กรอบโค้งแหลม บานเหล็กสองบาน ขอบบรอนซ์ ไฟอำพันด้านบน
static func _exit_door(g: PropsLayer.Geo, glow_g: PropsLayer.Geo) -> void:
	var r: Rect2 = HallLayout.rect_of("exit")
	var hw := r.size.x * 0.5
	var zf := r.position.y + 0.02                # หน้ากรอบ (ฝั่งห้อง)
	var hz := HallLayout.HALF.y
	var o := Vector3(0.0, 0.0, zf)
	var u := Vector3(-1, 0, 0)
	var n := Vector3(0, 0, -1)
	var inner := Vector3(hw - 0.25, 2.0, 2.95)
	var outer := Vector3(hw, 2.2, 3.2)
	# ช่องลึก (ด้านหลังบาน) กับเสาข้างกรอบ
	for sx in [-1.0, 1.0]:
		g.box(Vector3(sx * (hw - 0.125), inner.y * 0.5, (zf + hz) * 0.5), Vector3(0.125, inner.y * 0.5, (hz - zf) * 0.5), STEEL * 0.85)
	_arch_band(g, o, u, n, 0.0, outer, inner, 5, 0.0, STEEL * 0.85)
	_arch_band(g, o, u, n, 0.0, outer, Vector3(hw - 0.08, 2.15, 3.12), 5, 0.006, BRONZE * 0.8)
	# บานประตูสองบาน
	var leaf := arch_outline(0.0, inner.x, 0.0, inner.y, inner.z, 5)
	var left: Array[Vector2] = []
	var right: Array[Vector2] = []
	for q in leaf:
		if q.x <= 0.001:
			left.append(q)
		if q.x >= -0.001:
			right.append(q)
	left.append(Vector2(0.0, 0.0))
	right.push_front(Vector2(0.0, 0.0))
	var zd := zf + 0.08
	_wall_poly(g, Vector3(0, 0, zd), u, n, left, 0.0, STEEL * 0.78)
	_wall_poly(g, Vector3(0, 0, zd), u, n, right, 0.0, STEEL * 0.72)
	g.poly([Vector3(-0.03, 0.0, zd - 0.004), Vector3(0.03, 0.0, zd - 0.004), Vector3(0.03, inner.z, zd - 0.004), Vector3(-0.03, inner.z, zd - 0.004)],
		STEEL_DARK * 0.4, n)
	for y in [0.9, 1.9]:
		g.poly([Vector3(-inner.x, y, zd - 0.006), Vector3(inner.x, y, zd - 0.006), Vector3(inner.x, y + 0.12, zd - 0.006),
			Vector3(-inner.x, y + 0.12, zd - 0.006)], BRONZE * 0.85, n)
	g.box(Vector3(0.0, 0.03, zf - 0.04), Vector3(hw + 0.05, 0.03, 0.08), STEEL * 0.7)
	# ไฟอำพันเหนือประตู
	g.box(Vector3(0.0, 3.42, zf + 0.0), Vector3(0.16, 0.1, 0.06), STEEL_DARK)
	glow_g.poly([Vector3(-0.11, 3.36, zf - 0.07), Vector3(0.11, 3.36, zf - 0.07), Vector3(0.11, 3.48, zf - 0.07), Vector3(-0.11, 3.48, zf - 0.07)],
		LAMP_AMBER, n)


## ช่องเทียบยาน (ออนไลน์) ในผนังขวา: กรอบโค้งแหลม ฝาประตูกลมแบ่งกลีบ แสงฟ้า ไฟสถานะอำพัน
static func _airlock(g: PropsLayer.Geo, glow_g: PropsLayer.Geo, sides: int) -> void:
	var r: Rect2 = HallLayout.rect_of("online")
	var xf := r.position.x                       # หน้ากรอบ (ฝั่งห้อง)
	var hx := HallLayout.HALF.x
	var zc := r.get_center().y
	var hz := r.size.y * 0.5
	var o := Vector3(xf, 0.0, zc)
	var u := Vector3(0, 0, 1)
	var n := Vector3(-1, 0, 0)
	var outer := Vector3(hz, 3.3, 5.2)
	var inner := Vector3(hz - 0.25, 3.1, 4.85)
	for sz in [-1.0, 1.0]:
		g.box(Vector3((xf + hx) * 0.5, inner.y * 0.5, zc + sz * (hz - 0.125)), Vector3((hx - xf) * 0.5, inner.y * 0.5, 0.125), STEEL * 0.8)
	_arch_band(g, o, u, n, 0.0, outer, inner, 5, 0.0, STEEL * 0.8)
	_arch_band(g, o, u, n, 0.0, outer, Vector3(hz - 0.07, 3.25, 5.12), 5, 0.006, BRONZE * 0.75)
	# ช่องตื้นมืดหลังกรอบ (ทั้งช่องยื่นจากผนังไม่เกิน 0.2 ม.)
	var xr := hx - 0.03
	_wall_poly(g, Vector3(xr, 0.0, zc), u, n, arch_outline(0.0, inner.x, 0.0, inner.y, inner.z, 5), 0.0, STEEL_DARK * 0.45)
	# ฝาประตูกลมแบ่ง 8 กลีบ ดุมทองเหลืองตรงกลาง
	var hc := Vector3(xr - 0.05, 1.75, zc)
	var hr := 1.3
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var d0 := Vector3(0, sin(a0), cos(a0))
		var d1 := Vector3(0, sin(a1), cos(a1))
		g.poly([hc + d0 * 0.32, hc + d0 * hr, hc + d1 * hr, hc + d1 * 0.32], STEEL * (0.9 if i % 2 == 0 else 0.78), n)
		var sw := Vector3(0, cos(a0), -sin(a0)) * 0.02
		g.poly([hc + d0 * 0.32 - sw + n * 0.006, hc + d0 * hr - sw + n * 0.006, hc + d0 * hr + sw + n * 0.006,
			hc + d0 * 0.32 + sw + n * 0.006], STEEL_DARK * 0.4, n)
	var hub: Array[Vector3] = []
	for i in sides:
		var a := TAU * i / sides
		hub.append(hc + Vector3(0, sin(a), cos(a)) * 0.3 + n * 0.02)
	g.poly(hub, BRASS * 0.85, n)
	# ลายเตือนรอบขอบฝา (แถบเหลืองดำสลับ)
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		var d0 := Vector3(0, sin(a0), cos(a0))
		var d1 := Vector3(0, sin(a1), cos(a1))
		g.poly([hc + d0 * hr + n * 0.01, hc + d1 * hr + n * 0.01, hc + d1 * (hr + 0.1) + n * 0.01, hc + d0 * (hr + 0.1) + n * 0.01],
			HAZARD if i % 2 == 0 else HAZARD_DARK, n)
	# วงแสงฟ้า (ไม่อบแสง) กับไฟสถานะอำพัน
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		var d0 := Vector3(0, sin(a0), cos(a0))
		var d1 := Vector3(0, sin(a1), cos(a1))
		glow_g.poly([hc + d0 * (hr + 0.1) + n * 0.008, hc + d1 * (hr + 0.1) + n * 0.008, hc + d1 * (hr + 0.19) + n * 0.008,
			hc + d0 * (hr + 0.19) + n * 0.008], AIRLOCK_GLOW * 0.8, n)
	glow_g.poly([Vector3(xr - 0.02, 3.5, zc - 0.12), Vector3(xr - 0.02, 3.5, zc + 0.12), Vector3(xr - 0.02, 3.66, zc + 0.12),
		Vector3(xr - 0.02, 3.66, zc - 0.12)], LAMP_AMBER, n)


# ---- เฟอร์นิเจอร์: โต๊ะแผนที่โฮโลแกรม คลังแสง คอนโซล โต๊ะแผนที่ดาว หีบสมบัติ เชิงเทียน ----

static func _furniture(sides: int, lights: PackedVector3Array) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	var glow_g := PropsLayer.Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_holo_table(g, rng, sides)
	_armoury(g, sides)
	_console(g, glow_g, sides)
	_adventure(g, rng, sides)
	_vault_chest(g, glow_g, sides)
	for s in HallLayout.STANDS:
		_stand(g, s, sides)
	bake(g, lights, HallLayout.COOL_LIGHTS)
	append(g, glow_g)
	return g.mesh()


## โต๊ะรบ: โต๊ะเหล็กหนัก ขอบและเสามุมบรอนซ์ หน้ากระจกมืดมีสนามจำลอง เทียนสี่มุม (ชั้นโฮโลแกรมอยู่ใน holo_mesh)
static func _holo_table(g: PropsLayer.Geo, rng: RandomNumberGenerator, sides: int) -> void:
	var r: Rect2 = HallLayout.rect_of("battle")
	var c := r.get_center()
	var h := r.size * 0.5
	var top := float(HallLayout.STATIONS["battle"]["height"])
	g.box(Vector3(c.x, top - 0.06, c.y), Vector3(h.x, 0.06, h.y), STEEL_DARK * 0.8, 0.0, true)
	g.box(Vector3(c.x, top - 0.42, c.y), Vector3(h.x - 0.2, 0.3, h.y - 0.2), STEEL * 0.7)
	g.box(Vector3(c.x, 0.08, c.y), Vector3(h.x - 0.3, 0.08, h.y - 0.3), STEEL * 0.55)
	g.box(Vector3(c.x, 0.4, c.y), Vector3(h.x - 0.6, 0.25, h.y - 0.6), STEEL_DARK * 0.7)
	for sz in [-1.0, 1.0]:
		g.box(Vector3(c.x, top + 0.015, c.y + sz * (h.y - 0.05)), Vector3(h.x, 0.03, 0.05), BRONZE)
		g.box(Vector3(c.x, top - 0.25, c.y + sz * (h.y - 0.21)), Vector3(h.x - 0.25, 0.04, 0.012), BRASS * 0.7)
	for sx in [-1.0, 1.0]:
		g.box(Vector3(c.x + sx * (h.x - 0.05), top + 0.015, c.y), Vector3(0.05, 0.03, h.y - 0.1), BRONZE)
		for sz in [-1.0, 1.0]:
			g.prism(c.x + sx * (h.x - 0.08), 0.0, c.y + sz * (h.y - 0.08), 0.1, top + 0.12, 6, BRONZE * 0.8)
	# หน้ากระจกมืด: สนามจำลองหญ้า/ดินเป็นตาราง (มืดลง)
	var fx := h.x - 0.12
	var fz := h.y - 0.12
	var nx := 12
	var nz := 8
	for iz in nz:
		for ix in nx:
			var x0 := c.x - fx + ix * fx * 2.0 / nx
			var z0 := c.y - fz + iz * fz * 2.0 / nz
			var pick := rng.randf()
			var col := Color(0.36, 0.50, 0.24) if pick < 0.5 else (Color(0.66, 0.53, 0.28) if pick < 0.8 else Color(0.28, 0.40, 0.20))
			col = col * rng.randf_range(0.25, 0.32)
			g.poly([Vector3(x0, top + 0.004, z0), Vector3(x0 + fx * 2.0 / nx, top + 0.004, z0),
				Vector3(x0 + fx * 2.0 / nx, top + 0.004, z0 + fz * 2.0 / nz), Vector3(x0, top + 0.004, z0 + fz * 2.0 / nz)], col, Vector3.UP)
	for f in HallLayout.flames(true).slice(HallLayout.STANDS.size(), HallLayout.STANDS.size() + 4):
		_candle(g, f, top + 0.045, 0.04, sides)


## คลังแสงกองทัพ: ซุ้มโค้งแหลมสามซุ้ม ชั้นขั้นบันไดสามชั้น ไข่งาช้าง 15 ฟองบนแท่นบรอนซ์ ธงชายสีล้วน ราวปืน 10 กระบอกด้านบน
static func _armoury(g: PropsLayer.Geo, sides: int) -> void:
	var r: Rect2 = HallLayout.rect_of("army")
	var x_wall := r.position.x
	var x_front := r.end.x
	var z0 := r.position.y
	var zc := r.get_center().y
	var hz := r.size.y * 0.5
	var height := float(HallLayout.STATIONS["army"]["height"])
	g.box(Vector3(x_wall + 0.04, height * 0.5, zc), Vector3(0.04, height * 0.5, hz), STEEL_DARK)
	var o := Vector3(x_wall + 0.085, 0.0, z0)
	var u := Vector3(0, 0, 1)
	var n := Vector3(1, 0, 0)
	for i in 3:
		var cs := (i + 0.5) * hz * 2.0 / 3.0
		var a := hz / 3.0 - 0.1
		_wall_poly(g, o, u, n, arch_outline(cs, a + 0.06, 0.12, 1.52, 2.5, 4), 0.0, BRONZE * 0.7)
		_wall_poly(g, o, u, n, arch_outline(cs, a, 0.18, 1.58, 2.42, 4), 0.006, STEEL_DARK * 0.5)
	for sz in [-1.0, 1.0]:
		g.box(Vector3((x_wall + x_front) * 0.5, height * 0.5 - 0.03, zc + sz * (hz - 0.05)), Vector3((x_front - x_wall) * 0.5, height * 0.5 - 0.03, 0.05), STEEL * 0.85)
	g.box(Vector3((x_wall + x_front) * 0.5 - 0.05, height - 0.05, zc), Vector3((x_front - x_wall) * 0.5 - 0.03, 0.05, hz + 0.03), BRONZE * 0.8)
	var tiers := [[0.6, x_front], [1.15, x_wall + 0.66], [1.7, x_wall + 0.38]]
	var k := 0
	for t in tiers:
		var y: float = t[0]
		var xf: float = t[1]
		g.box(Vector3((x_wall + xf) * 0.5, y - 0.03, zc), Vector3((xf - x_wall) * 0.5, 0.03, hz - 0.1), STEEL * 0.9, 0.0, true)
		g.box(Vector3((x_wall + xf) * 0.5, y * 0.5, zc), Vector3((xf - x_wall) * 0.5 - 0.02, y * 0.5 - 0.03, hz - 0.12), STEEL_DARK * 0.9)
		g.box(Vector3(xf - 0.012, y - 0.03, zc), Vector3(0.016, 0.036, hz - 0.1), BRONZE)
		for i in 5:
			var z := zc - hz + 0.55 + i * (hz * 2.0 - 1.1) / 4.0
			var ex := xf - 0.2
			g.prism(ex, y, z, 0.1, 0.06, 8, BRONZE * 0.85)
			lathe(g, Vector3(ex, y + 0.06, z), 0.3, 0.085, maxi(sides / 2, 6), IVORY, 1.0, 0.0)
			var px := ex - 0.12
			g.box(Vector3(px, y + 0.2, z + 0.13), Vector3(0.008, 0.2, 0.008), IRON)
			var col: Color = PENNANTS[k % PENNANTS.size()]
			var pa := Vector3(px, y + 0.38, z + 0.13)
			var pb := Vector3(px, y + 0.26, z + 0.13)
			var tip := Vector3(px, y + 0.32, z + 0.34)
			g.poly([pa, pb, tip], col, Vector3(1, 0, 0))
			g.poly([pa, pb, tip], col * 0.8, Vector3(-1, 0, 0))
			k += 1
	# ราวปืนสองแถว แถวละ 5 กระบอก (รูปทรงเรียบ ไม่มีตรา)
	var xr := x_wall + 0.11
	for y in [2.17, 2.42]:
		for i in 5:
			var zr := z0 + 0.52 + i * 1.04
			g.box(Vector3(xr, y - 0.01, zr - 0.32), Vector3(0.015, 0.035, 0.1), BRONZE * 0.7)
			g.box(Vector3(xr, y, zr - 0.05), Vector3(0.018, 0.03, 0.18), STEEL_DARK * 1.3)
			g.box(Vector3(xr, y + 0.01, zr + 0.27), Vector3(0.01, 0.01, 0.16), STEEL_DARK)
			g.box(Vector3(xr, y - 0.06, zr - 0.02), Vector3(0.012, 0.035, 0.03), STEEL_DARK)


## คอนโซลบัญชาการ (ตั้งค่า): แท่นทองเหลืองแปดเหลี่ยม หน้าจอเขียวเอียง ปุ่มอำพัน/แดง เทียนเล่มใหญ่ด้านข้าง
static func _console(g: PropsLayer.Geo, glow_g: PropsLayer.Geo, sides: int) -> void:
	var r: Rect2 = HallLayout.rect_of("settings")
	var c := r.get_center()
	g.prism(c.x, 0.0, c.y, 0.4, 0.1, 8, BRASS * 0.6, 1.0, PI / 8.0)
	g.prism(c.x, 0.1, c.y, 0.26, 0.75, 8, BRASS * 0.75, 0.8, PI / 8.0)
	g.prism(c.x, 0.85, c.y, 0.38, 0.08, 8, BRONZE * 0.8, 1.0, PI / 8.0)
	var lo := 0.95
	var hi := 1.2
	var hx := 0.34
	var hz := 0.38
	var p := [Vector3(c.x - hx, lo, c.y - hz), Vector3(c.x - hx, lo, c.y + hz), Vector3(c.x + hx, hi, c.y + hz), Vector3(c.x + hx, hi, c.y - hz)]
	var tn := Vector3(-0.5, 1, 0)
	g.poly(p, STEEL_DARK, tn)
	var d := Vector3(0, -0.1, 0)
	g.poly([p[0], p[1], p[1] + d, p[0] + d], BRASS * 0.7, Vector3(-1, 0, 0))
	g.poly([p[3], p[2], p[2] + d, p[3] + d], BRASS * 0.7, Vector3(1, 0, 0))
	g.poly([p[0], p[3], p[3] + d, p[0] + d], BRASS * 0.7, Vector3(0, 0, -1))
	g.poly([p[1], p[2], p[2] + d, p[1] + d], BRASS * 0.7, Vector3(0, 0, 1))
	g.poly([p[0] + d, p[1] + d, p[2] + d, p[3] + d], STEEL_DARK * 0.6, Vector3.DOWN)
	var s := (hi - lo) / (hx * 2.0)
	var ty := func(x: float) -> float: return lo + (x - c.x + hx) * s + 0.012
	# จอเขียว (ไม่อบแสง) กับเส้นข้อมูล
	var xa := c.x - 0.1
	var xb := c.x + 0.3
	var za := c.y - 0.32
	var zb := c.y + 0.14
	glow_g.poly([Vector3(xa, ty.call(xa), za), Vector3(xa, ty.call(xa), zb), Vector3(xb, ty.call(xb), zb), Vector3(xb, ty.call(xb), za)],
		HallLayout.SCREEN_GREEN * 0.3, tn)
	for i in 4:
		var x0 := xa + 0.06 + i * 0.08
		var w := 0.12 + 0.07 * ((i * 3) % 4)
		var lift := 0.004
		glow_g.poly([Vector3(x0, ty.call(x0) + lift, za + 0.05), Vector3(x0, ty.call(x0) + lift, za + 0.05 + w),
			Vector3(x0 + 0.025, ty.call(x0 + 0.025) + lift, za + 0.05 + w), Vector3(x0 + 0.025, ty.call(x0 + 0.025) + lift, za + 0.05)],
			HallLayout.SCREEN_GREEN * 0.95, tn)
	# ปุ่มสองแถว
	for row in 2:
		var bx := c.x - 0.26 + row * 0.08
		for i in 5:
			var bz := c.y - 0.3 + i * 0.12
			var col := LAMP_AMBER if (i + row) % 3 != 0 else Color(0.95, 0.25, 0.18)
			glow_g.poly([Vector3(bx, ty.call(bx), bz), Vector3(bx, ty.call(bx), bz + 0.05), Vector3(bx + 0.04, ty.call(bx + 0.04), bz + 0.05),
				Vector3(bx + 0.04, ty.call(bx + 0.04), bz)], col * 0.85, tn)
	var f := HallLayout.CONSOLE_FLAME
	var base: float = ty.call(f.x)
	g.prism(f.x, base - 0.02, f.z, 0.08, 0.04, maxi(sides / 2, 6), BRASS * 0.8)
	g.prism(f.x, base + 0.02, f.z, 0.055, f.y - base - 0.02, maxi(sides / 2, 6), WAX)


## โต๊ะแผนที่ดาว (ผจญภัย): โต๊ะเหล็กกลม แผนที่ดาวบนกระดาษ ลูกโลกวงแหวนทองเหลืองสามวง ม้านั่งสี่ตัว
static func _adventure(g: PropsLayer.Geo, rng: RandomNumberGenerator, sides: int) -> void:
	var s: Dictionary = HallLayout.STATIONS["adventure"]
	var c: Vector2 = s["c"]
	var rad: float = (s["h"] as Vector2).x
	var top := float(s["height"])
	var n := maxi(sides + 4, 12)
	g.prism(c.x, 0.0, c.y, 0.55, 0.08, n, STEEL_DARK)
	g.prism(c.x, 0.08, c.y, 0.17, top - 0.14, sides, STEEL)
	g.prism(c.x, top - 0.06, c.y, rad, 0.06, n, STEEL_DARK * 1.1, 1.0, 0.0, true, true)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), 0, -sin(a0))
		var d1 := Vector3(cos(a1), 0, -sin(a1))
		var cc := Vector3(c.x, top + 0.003, c.y)
		g.poly([cc + d0 * (rad - 0.12), cc + d1 * (rad - 0.12), cc + d1 * rad, cc + d0 * rad], BRONZE, Vector3.UP)
	for p in HallLayout.stools():
		g.prism(p.x, 0.0, p.y, HallLayout.STOOL_R * 0.55, HallLayout.STOOL_H - 0.06, maxi(sides / 2, 6), STEEL_DARK)
		g.prism(p.x, HallLayout.STOOL_H - 0.06, p.y, HallLayout.STOOL_R, 0.06, sides, STEEL * 0.9)
	# แผนที่ดาว: กระดาษ จุดดาว เส้นทาง
	var mx0 := c.x - 0.75
	var mz0 := c.y + 0.12
	g.poly([Vector3(mx0, top + 0.006, mz0), Vector3(mx0 + 0.9, top + 0.006, mz0), Vector3(mx0 + 0.9, top + 0.006, mz0 + 0.7),
		Vector3(mx0, top + 0.006, mz0 + 0.7)], PARCHMENT * 0.9, Vector3.UP)
	var stars: Array[Vector3] = []
	for i in 7:
		var q := Vector3(mx0 + rng.randf_range(0.1, 0.8), top + 0.009, mz0 + rng.randf_range(0.1, 0.6))
		stars.append(q)
		g.poly([q + Vector3(-0.02, 0, 0), q + Vector3(0, 0, 0.02), q + Vector3(0.02, 0, 0), q + Vector3(0, 0, -0.02)], STEEL_DARK, Vector3.UP)
	for i in 3:
		var a := stars[i]
		var b := stars[i + 1]
		var w := Vector3(-(b.z - a.z), 0, b.x - a.x).normalized() * 0.006
		g.poly([a - w, b - w, b + w, a + w], CARPET, Vector3.UP)
	# ลูกโลกวงแหวนสามวง
	var ac := Vector3(c.x + 0.55, top + 0.26, c.y - 0.45)
	g.prism(ac.x, top, ac.z, 0.08, 0.03, 6, BRASS * 0.7)
	g.prism(ac.x, top + 0.03, ac.z, 0.014, 0.11, 4, BRASS * 0.7)
	_ring(g, ac, Vector3(0, 0, 1), 0.15, 0.018, 12, BRASS)
	_ring(g, ac, Vector3(1, 0, 0), 0.135, 0.018, 12, BRASS * 0.85)
	_ring(g, ac, Vector3(0, 0.7, 0.7).normalized(), 0.12, 0.018, 12, BRONZE)
	_candle(g, HallLayout.ADVENTURE_FLAME, top, 0.045, sides)


## วงแหวนบาง (สองหน้า) กลาง c ระนาบตั้งฉากกับ nrm รัศมี r กว้าง w
static func _ring(g: PropsLayer.Geo, c: Vector3, nrm: Vector3, r: float, w: float, segs: int, col: Color) -> void:
	var t1 := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := nrm.cross(t1).normalized()
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := t1 * cos(a0) + t2 * sin(a0)
		var d1 := t1 * cos(a1) + t2 * sin(a1)
		var q := [c + d0 * (r - w), c + d1 * (r - w), c + d1 * r, c + d0 * r]
		g.poly(q, col, nrm)
		g.poly(q, col * 0.8, -nrm)


## หีบสมบัติ (สถานีใหม่ ระบบสุ่มของรางวัลเร็วๆ นี้): แท่นแปดเหลี่ยมสองขั้น หีบบรอนซ์คาดเหล็ก แสงทองรั่วจากร่องฝา
## แผ่นกุญแจมีลายเทียนของเรา เทียนสองเล่มหน้าแท่น
static func _vault_chest(g: PropsLayer.Geo, glow_g: PropsLayer.Geo, sides: int) -> void:
	var s: Dictionary = HallLayout.STATIONS["vault"]
	var c: Vector2 = s["c"]
	g.prism(c.x, 0.0, c.y, 1.2, 0.16, 8, STEEL * 0.8, 1.0, PI / 8.0)
	g.prism(c.x, 0.16, c.y, 0.95, 0.16, 8, BRONZE * 0.55, 1.0, PI / 8.0)
	var y0 := 0.32
	var hxc := 0.375
	var hzc := 0.65
	var bh := 0.58
	# บรอนซ์เข้มกว่าของอื่น: เทียนสองเล่มกับแสงทองอยู่ชิดหีบ (0.85 เดิมสว่างจนสีแดงล้น ดูเป็นหีบการ์ตูน)
	g.box(Vector3(c.x, y0 + bh * 0.5, c.y), Vector3(hxc, bh * 0.5, hzc), BRONZE * 0.62)
	for z in [-0.45, 0.0, 0.45]:
		g.box(Vector3(c.x, y0 + bh * 0.5, c.y + z), Vector3(hxc + 0.012, bh * 0.5 + 0.004, 0.045), STEEL_DARK)
	# ฝาโค้ง (ตามแกน z) กับแถบเหล็กบนฝา
	var ly := y0 + bh + 0.02
	var prof: Array[Vector2] = []
	for i in 7:
		var t := PI * i / 6.0
		prof.append(Vector2(cos(t) * hxc, sin(t) * 0.24))
	for i in 6:
		var a := prof[i]
		var b := prof[i + 1]
		var out := Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5 + 0.1, 0.0)
		g.poly([Vector3(c.x + a.x, ly + a.y, c.y - hzc), Vector3(c.x + b.x, ly + b.y, c.y - hzc), Vector3(c.x + b.x, ly + b.y, c.y + hzc),
			Vector3(c.x + a.x, ly + a.y, c.y + hzc)], BRONZE * 0.62, out)
		for z in [-0.45, 0.0, 0.45]:
			var k := 1.04
			g.poly([Vector3(c.x + a.x * k, ly + a.y * k, c.y + z - 0.045), Vector3(c.x + b.x * k, ly + b.y * k, c.y + z - 0.045),
				Vector3(c.x + b.x * k, ly + b.y * k, c.y + z + 0.045), Vector3(c.x + a.x * k, ly + a.y * k, c.y + z + 0.045)], STEEL_DARK, out)
	for sz in [-1.0, 1.0]:
		var cap: Array[Vector3] = []
		for q in prof:
			cap.append(Vector3(c.x + q.x, ly + q.y, c.y + sz * hzc))
		g.poly(cap, BRONZE * 0.56, Vector3(0, 0, sz))
	g.box(Vector3(c.x, ly - 0.01, c.y), Vector3(hxc, 0.01, hzc), BRONZE * 0.42)
	# แสงทองรั่วจากร่องฝา (ไม่อบแสง) ด้านหน้าและสองข้าง
	var xs := c.x - hxc - 0.003
	glow_g.poly([Vector3(xs, ly - 0.02, c.y - hzc + 0.02), Vector3(xs, ly - 0.02, c.y + hzc - 0.02), Vector3(xs, ly + 0.012, c.y + hzc - 0.02),
		Vector3(xs, ly + 0.012, c.y - hzc + 0.02)], SEAM_GLOW, Vector3.LEFT)
	for sz in [-1.0, 1.0]:
		var zs: float = c.y + sz * (hzc + 0.003)
		glow_g.poly([Vector3(c.x - hxc + 0.02, ly - 0.02, zs), Vector3(c.x + hxc - 0.02, ly - 0.02, zs), Vector3(c.x + hxc - 0.02, ly + 0.012, zs),
			Vector3(c.x - hxc + 0.02, ly + 0.012, zs)], SEAM_GLOW, Vector3(0, 0, sz))
	# แผ่นกุญแจกับลายเทียน
	var lp := Vector3(c.x - hxc - 0.016, y0 + bh - 0.16, c.y)
	g.box(lp, Vector3(0.016, 0.11, 0.09), BRASS)
	emblem(g, lp + Vector3(-0.018, 0.0, 0.0), Vector3(0, 0, 1), Vector3.LEFT, 0.075, STEEL_DARK, WAX, Color(0.95, 0.45, 0.12), 10)
	for f in HallLayout.VAULT_FLAMES:
		g.prism(f.x, 0.16, f.z, 0.07, 0.1, 6, BRONZE * 0.8)
		_candle_at(g, Vector3(f.x, 0.26, f.z), f.y, 0.04)


## เชิงเทียนตั้งพื้นชิดผนัง (บรอนซ์): ฐาน ก้าน ถาด แขน เทียนสามเล่ม
static func _stand(g: PropsLayer.Geo, s: Vector2, sides: int) -> void:
	var arm := HallLayout.stand_arm(s)
	var n := maxi(sides / 2, 6)
	var col := BRONZE * 0.6
	g.prism(s.x, 0.0, s.y, 0.24, 0.05, n, col)
	g.prism(s.x, 0.05, s.y, 0.12, 0.08, n, col, 0.4)
	g.prism(s.x, 0.12, s.y, 0.03, HallLayout.STAND_H - 0.12, 6, col)
	g.prism(s.x, HallLayout.STAND_H - 0.02, s.y, 0.11, 0.04, n, col * 1.2)
	var yaw := 0.0 if arm.x > 0.5 else PI * 0.5
	g.box(Vector3(s.x, HallLayout.STAND_H + 0.02, s.y), Vector3(HallLayout.STAND_ARM + 0.03, 0.015, 0.015), col, yaw)
	var base := Vector3(s.x, HallLayout.STAND_H + 0.02, s.y)
	_candle_at(g, base, HallLayout.STAND_FLAME_MID, 0.038)
	for side in [-1.0, 1.0]:
		var p: Vector3 = base + arm * HallLayout.STAND_ARM * side
		g.prism(p.x, p.y - 0.01, p.z, 0.05, 0.03, 6, col)
		_candle_at(g, p, HallLayout.STAND_FLAME_SIDE, 0.032)


## เทียนบนโต๊ะ: ฐานรองทองเหลืองบนพื้นโต๊ะ (y0) ถึงยอดเทียนที่ฐานเปลวไฟ f
static func _candle(g: PropsLayer.Geo, f: Vector3, y0: float, r: float, sides: int) -> void:
	g.prism(f.x, y0, f.z, r * 1.7, 0.03, maxi(sides / 2, 6), GOLD * 0.7)
	_candle_at(g, Vector3(f.x, y0 + 0.03, f.z), f.y, r)


static func _candle_at(g: PropsLayer.Geo, base: Vector3, top: float, r: float) -> void:
	g.prism(base.x, base.y, base.z, r, top - base.y, 6, WAX)
	g.prism(base.x, top, base.z, 0.004, 0.012, 3, IRON, 1.0, 0.0, false)


## จานกลมแบนที่ p (หันขึ้น)
static func _disc(g: PropsLayer.Geo, p: Vector3, r: float, n: int, col: Color) -> void:
	var pts: Array[Vector3] = []
	for i in n:
		var a := i * TAU / n
		pts.append(p + Vector3(cos(a) * r, 0.0, -sin(a) * r))
	g.poly(pts, col, Vector3.UP)


## ไข่หมุนรอบแกน y จากโปรไฟล์ EGG_PROFILE: ฐานที่ p สูง height กว้างสุด widest, zk = ยืดตามแกน z
## top_light = ยอดสว่างขึ้นแค่ไหน, nub = ปุ่มบอกทิศด้านหน้า (+z) ที่ 0.6 ของความสูง (0 = ไม่มี)
static func lathe(g: PropsLayer.Geo, p: Vector3, height: float, widest: float, sides: int, col: Color,
		zk: float = 1.0, top_light: float = 0.0, nub: float = 0.0) -> void:
	var rings: Array[PackedVector3Array] = []
	for q in EGG_PROFILE:
		var ring := PackedVector3Array()
		for i in sides:
			var a := TAU * i / sides
			ring.append(p + Vector3(sin(a) * q.y * widest, q.x * height, cos(a) * q.y * widest * zk))
		rings.append(ring)
	for k in EGG_PROFILE.size() - 1:
		var yk := (EGG_PROFILE[k].x + EGG_PROFILE[k + 1].x) * 0.5
		var band := col.lerp(Color.WHITE, top_light * yk)
		for i in sides:
			var j := (i + 1) % sides
			var a := rings[k][i]
			var b := rings[k][j]
			var c := rings[k + 1][j]
			var d := rings[k + 1][i]
			var mid := (a + b + c + d) * 0.25
			var out := Vector3(mid.x - p.x, 0.0, mid.z - p.z)
			var nrm := (out.normalized() * (1.0 - yk) + Vector3.UP * yk).normalized()
			var face := band * (0.8 + 0.2 * nrm.y + 0.08 * nrm.z)
			if EGG_PROFILE[k + 1].y < 0.001:
				g.poly([a, b, c], face, out + Vector3.UP * 0.5)
			else:
				g.poly([a, b, c, d], face, out + Vector3.UP * (yk - 0.4))
	g.poly(Array(rings[0]), col * 0.6, Vector3.DOWN)
	if nub > 0.0:
		var y := 0.6 * height
		var rz := 0.867 * widest * zk
		g.box(p + Vector3(0.0, y, rz + nub * 0.3), Vector3(nub * 0.9, nub * 0.7, nub * 0.6), NUB, 0.0, false)



# ---- ชั้นโฮโลแกรมเหนือโต๊ะรบ ----

## เมชโฮโลแกรม: ตาราง 12 x 8 ช่อง กรอบ ไข่สองทีม เครื่องหมายเป้าหมายหกเหลี่ยม (lo/min เส้นหนากว่า) ไม่อบแสง
static func holo_mesh(level: String) -> ArrayMesh:
	var thick := level == "lo" or level == "min"
	var key := "holo|%s" % ("thick" if thick else "thin")
	if _cache.has(key):
		return _cache[key]
	var g := PropsLayer.Geo.new()
	var c: Vector2 = HallLayout.rect_of("battle").get_center()
	var y := 1.18
	var hx := 2.5
	var hz := 1.5
	var lw := 0.06 if thick else 0.035
	var gc := HOLO * 0.5
	for i in 13:
		var x := c.x - hx + i * hx * 2.0 / 12.0
		g.poly([Vector3(x - lw * 0.5, y, c.y - hz), Vector3(x + lw * 0.5, y, c.y - hz), Vector3(x + lw * 0.5, y, c.y + hz),
			Vector3(x - lw * 0.5, y, c.y + hz)], gc, Vector3.UP)
	for k in 9:
		var z := c.y - hz + k * hz * 2.0 / 8.0
		g.poly([Vector3(c.x - hx, y + 0.001, z - lw * 0.5), Vector3(c.x + hx, y + 0.001, z - lw * 0.5), Vector3(c.x + hx, y + 0.001, z + lw * 0.5),
			Vector3(c.x - hx, y + 0.001, z + lw * 0.5)], gc, Vector3.UP)
	var fw := lw * 1.6
	var fo := 0.1
	for sz in [-1.0, 1.0]:
		var z: float = c.y + sz * (hz + fo)
		g.poly([Vector3(c.x - hx - fo, y, z - fw * 0.5), Vector3(c.x + hx + fo, y, z - fw * 0.5), Vector3(c.x + hx + fo, y, z + fw * 0.5),
			Vector3(c.x - hx - fo, y, z + fw * 0.5)], HOLO * 0.8, Vector3.UP)
	for sx in [-1.0, 1.0]:
		var x: float = c.x + sx * (hx + fo)
		g.poly([Vector3(x - fw * 0.5, y, c.y - hz - fo), Vector3(x + fw * 0.5, y, c.y - hz - fo), Vector3(x + fw * 0.5, y, c.y + hz + fo),
			Vector3(x - fw * 0.5, y, c.y + hz + fo)], HOLO * 0.8, Vector3.UP)
	var eggs := [[-1.7, -0.6, TEAM_A], [-1.35, 0.15, TEAM_A], [-1.9, 0.75, TEAM_A], [1.6, -0.75, TEAM_B], [1.25, 0.05, TEAM_B],
		[1.8, 0.7, TEAM_B]]
	for e in eggs:
		_holo_egg(g, Vector3(c.x + float(e[0]), y + 0.005, c.y + float(e[1])), 0.35, 0.11, 8, (e[2] as Color).lerp(Color.WHITE, 0.25) * 0.75)
	for oc in [Vector2(-0.3, -0.55), Vector2(0.45, 0.7)]:
		var cc := Vector3(c.x + oc.x, y + 0.004, c.y + oc.y)
		for i in 6:
			var a0 := TAU * i / 6.0
			var a1 := TAU * (i + 1) / 6.0
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			g.poly([cc + d0 * 0.22, cc + d1 * 0.22, cc + d1 * (0.22 + lw * 1.4), cc + d0 * (0.22 + lw * 1.4)], HOLO_AMBER * 0.8, Vector3.UP)
	var m := g.mesh()
	_cache[key] = m
	return m


## ไข่โฮโลแกรมหยาบ (โปรไฟล์ HOLO_EGG) ฐานที่ p
static func _holo_egg(g: PropsLayer.Geo, p: Vector3, height: float, widest: float, sides: int, col: Color) -> void:
	var rings: Array[PackedVector3Array] = []
	for q in HOLO_EGG:
		var ring := PackedVector3Array()
		for i in sides:
			var a := TAU * i / sides
			ring.append(p + Vector3(sin(a) * q.y * widest, q.x * height, cos(a) * q.y * widest))
		rings.append(ring)
	for k in HOLO_EGG.size() - 1:
		var band := col * (0.8 + 0.3 * HOLO_EGG[k].x)
		for i in sides:
			var j := (i + 1) % sides
			var mid := (rings[k][i] + rings[k + 1][j]) * 0.5 - p
			var out := Vector3(mid.x, 0.3, mid.z)
			if HOLO_EGG[k + 1].y < 0.001:
				g.poly([rings[k][i], rings[k][j], rings[k + 1][j]], band, out)
			else:
				g.poly([rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]], band, out)


# ---- ผ้า: ธงแขวนผนังลายเทียนในวงกลม (ลายของเราเอง) ----

static func _cloth(lights: PackedVector3Array) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	for b in HallLayout.BANNERS:
		_banner(g, b["p"], b["n"], BANNER_COLS[int(b["col"]) % BANNER_COLS.size()])
	bake(g, lights, HallLayout.COOL_LIGHTS)
	return g.mesh()


## ธงหนึ่งผืน: p = กลางบนผิวผนัง, n2 = ทิศเข้าห้อง (x, z)
static func _banner(g: PropsLayer.Geo, p: Vector3, n2: Vector2, col: Color) -> void:
	var n := Vector3(n2.x, 0.0, n2.y)
	var yaw := atan2(n2.x, n2.y)
	var u := Vector3(cos(yaw), 0.0, -sin(yaw))
	var hw := 0.65
	var top := p + Vector3(0, 1.2, 0)
	var o := n * 0.05
	# ราวแขวนบรอนซ์
	g.box(top + n * 0.07 + Vector3(0, 0.05, 0), Vector3(hw + 0.15, 0.025, 0.025), BRONZE * 0.6, yaw)
	for s in [-1.0, 1.0]:
		g.box(top + n * 0.07 + Vector3(0, 0.05, 0) + u * (hw + 0.17) * s, Vector3(0.04, 0.04, 0.04), GOLD * 0.8, yaw)
	# ผืนผ้าปลายแหลม ขอบทอง
	var pts := [top + o - u * hw, top + o + u * hw, top + o + u * hw - Vector3(0, 2.0, 0), top + o - Vector3(0, 2.4, 0), top + o - u * hw - Vector3(0, 2.0, 0)]
	g.poly([pts[0], pts[1], pts[2], pts[3], pts[4]], GOLD * 0.8, n)
	var t := 0.06
	var o2 := n * 0.055
	g.poly([top + o2 - u * (hw - t) - Vector3(0, t, 0), top + o2 + u * (hw - t) - Vector3(0, t, 0),
		top + o2 + u * (hw - t) - Vector3(0, 2.0 - t * 0.3, 0), top + o2 - Vector3(0, 2.4 - t * 1.5, 0),
		top + o2 - u * (hw - t) - Vector3(0, 2.0 - t * 0.3, 0)], col, n)
	# ลาย: วงกลมทอง เทียนงาช้าง เปลวไฟส้มเหลือง
	var o3 := n * 0.06
	var cc := top + o3 - Vector3(0, 0.95, 0)
	var ro := 0.42
	var ri := 0.35
	for i in 20:
		var a0 := TAU * i / 20.0
		var a1 := TAU * (i + 1) / 20.0
		var d0 := u * cos(a0) + Vector3(0, sin(a0), 0)
		var d1 := u * cos(a1) + Vector3(0, sin(a1), 0)
		g.poly([cc + d0 * ri, cc + d1 * ri, cc + d1 * ro, cc + d0 * ro], GOLD, n)
	g.poly([cc - u * 0.075 - Vector3(0, 0.3, 0), cc + u * 0.075 - Vector3(0, 0.3, 0), cc + u * 0.075 + Vector3(0, 0.02, 0),
		cc - u * 0.075 + Vector3(0, 0.02, 0)], WAX, n)
	var fb := cc + Vector3(0, 0.05, 0)
	var o4 := n * 0.003
	g.poly([fb - u * 0.1 + Vector3(0, 0.08, 0), fb, fb + u * 0.1 + Vector3(0, 0.08, 0), fb + Vector3(0, 0.3, 0)], Color(0.95, 0.45, 0.12), n)
	g.poly([fb - u * 0.05 + Vector3(0, 0.07, 0) + o4, fb + Vector3(0, 0.02, 0) + o4, fb + u * 0.05 + Vector3(0, 0.07, 0) + o4,
		fb + Vector3(0, 0.2, 0) + o4], Color(1.0, 0.85, 0.42), n)


# ---- เปลวไฟ ----

## เปลวไฟกรวยคู่ สูง 0.15 ม. ฐานที่ y = 0 สีจุดยอดไล่จากขาวเหลืองถึงส้มแดง
static func flame_mesh() -> ArrayMesh:
	if _flame_mesh != null:
		return _flame_mesh
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var sides := 6
	var y_mid := 0.045
	var r_mid := 0.03
	var tip := Vector3(0, 0.155, 0)
	var bot := Vector3(0, -0.005, 0)
	var c_bot := Color(1.0, 0.95, 0.70)
	var c_mid := Color(1.0, 0.80, 0.36)
	var c_tip := Color(1.0, 0.40, 0.10)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cos(a0) * r_mid, y_mid, -sin(a0) * r_mid)
		var p1 := Vector3(cos(a1) * r_mid, y_mid, -sin(a1) * r_mid)
		# บน (หน้าออกนอก ตามเข็มเมื่อมองจากนอก)
		verts.append_array([p0, tip, p1])
		cols.append_array([c_mid, c_tip, c_mid])
		# ล่าง
		verts.append_array([p0, p1, bot])
		cols.append_array([c_mid, c_mid, c_bot])
		var nn := ((p0 + p1) * 0.5).normalized()
		for k in 6:
			norms.append(nn)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	_flame_mesh = ArrayMesh.new()
	_flame_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _flame_mesh


## วัสดุเปลวไฟของ lo/min: ไม่มี TIME (หน้าจอไม่ต้องวาดใหม่ทุกเฟรม)
static func flame_plain_material() -> StandardMaterial3D:
	if _flame_plain == null:
		_flame_plain = StandardMaterial3D.new()
		_flame_plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_plain.vertex_color_use_as_albedo = true
		_flame_plain.vertex_color_is_srgb = true
		_flame_plain.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _flame_plain


# ---- ตัวผู้เล่น ----

## ไข่ของตัวผู้เล่น สูง 1.75 กว้างสุด 0.43: สีทีม 60 % ผสมงาช้าง ยอดสว่างกว่า ปุ่มบอกทิศด้าน +z
static func avatar_mesh(team: Color, sides: int) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	var col := team * 0.6 + IVORY * 0.4
	col.a = 1.0
	lathe(g, Vector3.ZERO, 1.75, 0.43, sides, col, 1.0, 0.35, 0.07)
	return g.mesh()


# ---- ตัวชน ----

## ใส่รูปทรงชนทุกชิ้นจาก HallLayout.blockers() คืนจำนวนรูปทรง: ผนังกับเพดานลง body (SHELL_LAYER)
## ของในห้องลง props (PROP_LAYER ที่แขนกล้องไม่ชน); ไม่ให้ props ก็ลง body ทั้งหมด
static func build_colliders(body: StaticBody3D, props: StaticBody3D = null, list: Array[Dictionary] = []) -> int:
	for holder: StaticBody3D in [body, props]:
		if holder == null:
			continue
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		holder.collision_mask = 0
	body.collision_layer = HallLayout.SHELL_LAYER
	if props != null:
		props.collision_layer = HallLayout.PROP_LAYER
	var n := 0
	for b in (list if not list.is_empty() else HallLayout.blockers()):
		var cs := CollisionShape3D.new()
		cs.name = "Shape_%s_%d" % [str(b["tag"]), n]
		if str(b["kind"]) == "box":
			var box := BoxShape3D.new()
			box.size = (b["h"] as Vector3) * 2.0
			cs.shape = box
			cs.position = b["c"]
		else:
			var cyl := CylinderShape3D.new()
			cyl.radius = float(b["r"])
			cyl.height = float(b["y1"]) - float(b["y0"])
			cs.shape = cyl
			var c2: Vector2 = b["c"]
			cs.position = Vector3(c2.x, (float(b["y0"]) + float(b["y1"])) * 0.5, c2.y)
		(body if props == null or HallLayout.is_shell(b) else props).add_child(cs)
		n += 1
	return n
