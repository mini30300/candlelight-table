class_name HallBuilder
extends RefCounted
## สร้างเมชและตัวชนของห้องโถงจาก HallLayout (LOBBY_SPEC §2.2): ลายของเราเอง ห้องหินแสงเทียน
## เมชนิ่ง 3 ชิ้น (โครงห้อง เฟอร์นิเจอร์ ผ้า) ใช้วัสดุเดียว unshaded สีต่อจุดยอด แสงเทียนอบลงในสีจุดยอด
## ความสว่าง = 0.32 + Σ 0.85 / (1 + d²/3) ทุกเปลวไฟ (ตัดเพดาน) ยิ่งสว่างยิ่งออกส้ม (#ffb35c) · ไม่มีไฟจริง ไม่มีเงา
## เมชเก็บในแคช static ตามจำนวนเหลี่ยมของเสา (ระดับกราฟิก) สร้างครั้งเดียวต่อการเปิดแอป

const WARM := Color(1.0, 0.702, 0.361)        # #ffb35c
const GLOW_BASE := 0.32
const GLOW_K := 0.85
const GLOW_D2 := 3.0
const GLOW_MAX := 1.75
## โปรไฟล์ไข่ (y / สูง, รัศมี / กว้างสุด) จากฐานขึ้นยอด ตาม LOBBY_SPEC §4.1 (ล็อบบี้เก็บสำเนาของตัวเอง)
const EGG_PROFILE: PackedVector2Array = [Vector2(0.00, 0.55), Vector2(0.06, 0.85), Vector2(0.18, 0.98),
	Vector2(0.32, 1.00), Vector2(0.50, 0.95), Vector2(0.68, 0.80), Vector2(0.84, 0.56), Vector2(0.95, 0.30),
	Vector2(1.00, 0.00)]
const IVORY := Color(0.86, 0.82, 0.74)
const NUB := Color(0.55, 0.48, 0.40)

const STONE := Color(0.40, 0.34, 0.29)
const GROUT := Color(0.17, 0.13, 0.10)
const WALL := Color(0.40, 0.33, 0.27)
const WAINSCOT := Color(0.30, 0.19, 0.12)
const WOOD := Color(0.42, 0.28, 0.17)
const WOOD_DARK := Color(0.26, 0.16, 0.10)
const IRON := Color(0.20, 0.18, 0.17)
const WAX := Color(0.95, 0.90, 0.78)
const GOLD := Color(0.90, 0.70, 0.34)
const CARPET := Color(0.50, 0.11, 0.10)
const PARCHMENT := Color(0.86, 0.76, 0.56)
const BANNER_COLS := [Color(0.55, 0.11, 0.11), Color(0.74, 0.52, 0.16), Color(0.10, 0.44, 0.44)]
## สีธงชายบนตู้โชว์ 15 สี (สีล้วน ไม่มีตรา)
const PENNANTS := [Color(0.80, 0.22, 0.20), Color(0.24, 0.44, 0.80), Color(0.86, 0.68, 0.22), Color(0.30, 0.62, 0.32),
	Color(0.58, 0.32, 0.70), Color(0.92, 0.92, 0.88), Color(0.22, 0.66, 0.70), Color(0.86, 0.46, 0.18),
	Color(0.20, 0.20, 0.24), Color(0.80, 0.40, 0.62), Color(0.56, 0.38, 0.22), Color(0.46, 0.70, 0.30),
	Color(0.64, 0.12, 0.30), Color(0.40, 0.48, 0.58), Color(0.94, 0.80, 0.50)]
const TEAM_A := Color(0.28, 0.52, 0.84)
const TEAM_B := Color(0.83, 0.31, 0.26)

static var _cache: Dictionary = {}        # "meshes|sides" → Array[ArrayMesh]
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


## เมชนิ่ง 3 ชิ้น [โครงห้อง, เฟอร์นิเจอร์, ผ้า] ตามจำนวนเหลี่ยม (14 / 12 / 10 / 8 ตามระดับ)
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


## อบแสงลงทุกจุดยอดของ g
static func bake(g: PropsLayer.Geo, lights: PackedVector3Array) -> void:
	var cols := g.c
	var verts := g.v
	for i in verts.size():
		cols[i] = lit(cols[i], glow(verts[i], lights))
	g.c = cols


## ต่อเมชของ b ท้าย a (b ไม่อบแสง เช่น ช่องประตูเรืองแสงเย็น)
static func append(a: PropsLayer.Geo, b: PropsLayer.Geo) -> void:
	a.v.append_array(b.v)
	a.n.append_array(b.n)
	a.c.append_array(b.c)


static func tris(m: ArrayMesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# ---- โครงห้อง: พื้นหิน พรม ผนัง เสา คาน ประตูโค้ง ประตูทางออก ----

static func _shell(sides: int, lights: PackedVector3Array) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7731
	var hx := HallLayout.HALF.x
	var hz := HallLayout.HALF.y
	# ร่องยาแนวใต้แผ่นหิน
	g.poly([Vector3(-hx, -0.004, -hz), Vector3(hx, -0.004, -hz), Vector3(hx, -0.004, hz), Vector3(-hx, -0.004, hz)], GROUT, Vector3.UP)
	# แผ่นหิน 1 ม. สีต่างกันเล็กน้อย (สุ่มแบบมี seed ภาพคงที่)
	var gap := 0.025
	for iz in int(hz * 2.0):
		for ix in int(hx * 2.0):
			var x0 := -hx + ix + gap
			var z0 := -hz + iz + gap
			var k := rng.randf_range(0.82, 1.08)
			var col := Color(STONE.r * k, STONE.g * k * rng.randf_range(0.97, 1.02), STONE.b * k, 1.0)
			g.poly([Vector3(x0, 0.0, z0), Vector3(x0 + 1.0 - gap * 2.0, 0.0, z0), Vector3(x0 + 1.0 - gap * 2.0, 0.0, z0 + 1.0 - gap * 2.0),
				Vector3(x0, 0.0, z0 + 1.0 - gap * 2.0)], col, Vector3.UP)
	# พรมแดงจากประตูถึงโต๊ะรบ ขอบทอง
	var cz0 := 0.35
	var cz1 := 7.6
	g.poly([Vector3(-1.25, 0.008, cz0), Vector3(1.25, 0.008, cz0), Vector3(1.25, 0.008, cz1), Vector3(-1.25, 0.008, cz1)], GOLD * 0.8, Vector3.UP)
	g.poly([Vector3(-1.1, 0.012, cz0 + 0.12), Vector3(1.1, 0.012, cz0 + 0.12), Vector3(1.1, 0.012, cz1), Vector3(-1.1, 0.012, cz1)], CARPET, Vector3.UP)
	# ผนังสี่ด้าน: ก้อนหินเรียงสลับ 1.5 x 0.75 ม. + แผงไม้ล่าง 1.1 ม.
	_wall(g, rng, Vector3(-hx, 0, -hz), Vector3(1, 0, 0), hx * 2.0, Vector3(0, 0, 1))
	_wall(g, rng, Vector3(hx, 0, hz), Vector3(-1, 0, 0), hx * 2.0, Vector3(0, 0, -1))
	_wall(g, rng, Vector3(-hx, 0, hz), Vector3(0, 0, -1), hz * 2.0, Vector3(1, 0, 0))
	_wall(g, rng, Vector3(hx, 0, -hz), Vector3(0, 0, 1), hz * 2.0, Vector3(-1, 0, 0))
	# เสา: ฐาน ลำเสา หัวเสา
	for p in HallLayout.PILLARS:
		g.prism(p.x, 0.0, p.y, 0.52, 0.2, sides, WALL * 0.9)
		g.prism(p.x, 0.2, p.y, 0.42, 5.35, sides, WALL * 1.02, 1.0, 0.0, false)
		g.prism(p.x, 5.55, p.y, 0.44, 0.12, sides, WALL * 0.85, 1.25)
		g.box(Vector3(p.x, 5.83, p.y), Vector3(0.6, 0.17, 0.6), WALL * 0.92)
	# คานไม้บนหัวเสา (สูงกว่าเพดานล่องหน กล้องไม่ชน)
	for z in [-5.0, 0.5, 5.5]:
		g.box(Vector3(0.0, 6.17, z), Vector3(hx, 0.17, 0.22), WOOD_DARK, 0.0, true)
	for x in [-8.5, 8.5]:
		g.box(Vector3(x, 6.42, 0.0), Vector3(0.2, 0.08, hz), WOOD_DARK, 0.0, true)
	_gate(g, sides)
	_door(g)
	bake(g, lights)
	var cool := PropsLayer.Geo.new()
	_gate_glow(cool)
	append(g, cool)
	return g.mesh()


## ผนังหนึ่งด้าน: o = มุมล่างซ้าย (มองจากในห้อง), u = ทิศตามผนัง, length = ยาว, n = ทิศเข้าห้อง
static func _wall(g: PropsLayer.Geo, rng: RandomNumberGenerator, o: Vector3, u: Vector3, length: float, n: Vector3) -> void:
	var bw := 1.5
	var bh := 0.75
	var rows := int(HallLayout.WALL_H / bh)
	for r in rows:
		var y0 := r * bh
		var shift := 0.0 if r % 2 == 0 else bw * 0.5
		var a := 0.0
		while a < length - 0.001:
			var w := bw - shift if a == 0.0 and shift > 0.0 else bw
			var b := minf(a + w, length)
			var k := rng.randf_range(0.85, 1.07)
			var col := Color(WALL.r * k, WALL.g * k, WALL.b * k * rng.randf_range(0.96, 1.03), 1.0)
			if y0 < 1.1:
				col = col * 0.8
			g.poly([o + u * a + Vector3(0, y0, 0), o + u * b + Vector3(0, y0, 0), o + u * b + Vector3(0, y0 + bh, 0),
				o + u * a + Vector3(0, y0 + bh, 0)], col, n)
			a = b
	# แผงไม้ล่าง (ยื่นออกมา 4 ซม.) กับขอบบน
	var a2 := 0.0
	while a2 < length - 0.001:
		var b2 := minf(a2 + 2.0, length)
		var off := n * 0.04
		var col2 := WAINSCOT * (0.94 if int(a2 / 2.0) % 2 == 0 else 1.0)
		g.poly([o + u * a2 + off, o + u * b2 + off, o + u * b2 + off + Vector3(0, 1.0, 0), o + u * a2 + off + Vector3(0, 1.0, 0)], col2, n)
		g.poly([o + u * a2 + n * 0.07 + Vector3(0, 1.0, 0), o + u * b2 + n * 0.07 + Vector3(0, 1.0, 0),
			o + u * b2 + Vector3(0, 1.0, 0), o + u * a2 + Vector3(0, 1.0, 0)], WOOD_DARK * 1.1, Vector3.UP)
		g.poly([o + u * a2 + n * 0.07 + Vector3(0, 1.0, 0), o + u * b2 + n * 0.07 + Vector3(0, 1.0, 0),
			o + u * b2 + n * 0.07 + Vector3(0, 1.08, 0), o + u * a2 + n * 0.07 + Vector3(0, 1.08, 0)], WOOD_DARK, n)
		a2 = b2


## ประตูโค้งออนไลน์ในผนังหลัง: วงกบ ซุ้มโค้ง ลูกกรงเหล็ก
static func _gate(g: PropsLayer.Geo, sides: int) -> void:
	var r: Rect2 = HallLayout.rect_of("online")
	var zf := r.position.y + r.size.y          # หน้าซุ้ม (ฝั่งห้อง)
	var zc := r.get_center().y
	var hz := r.size.y * 0.5
	var spring := 3.3                           # ความสูงที่โค้งเริ่ม
	var ri := 1.36
	var ro := 1.7
	for sx in [-1.0, 1.0]:
		g.box(Vector3(sx * (ri + ro) * 0.5, spring * 0.5, zc), Vector3((ro - ri) * 0.5, spring * 0.5, hz), WALL * 1.05)
		g.box(Vector3(sx * (ri + ro) * 0.5, 0.12, zc), Vector3((ro - ri) * 0.5 + 0.06, 0.12, hz + 0.05), WALL * 0.8)
	var segs := maxi(sides, 8)
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		var c := Vector3(0.0, spring, 0.0)
		var col := WALL * (1.08 if i % 2 == 0 else 0.98)
		g.poly([c + d0 * ri + Vector3(0, 0, zf), c + d1 * ri + Vector3(0, 0, zf), c + d1 * ro + Vector3(0, 0, zf),
			c + d0 * ro + Vector3(0, 0, zf)], col, Vector3(0, 0, 1))
		g.poly([c + d0 * ri + Vector3(0, 0, zf), c + d1 * ri + Vector3(0, 0, zf), c + d1 * ri + Vector3(0, 0, zf - hz * 2.0),
			c + d0 * ri + Vector3(0, 0, zf - hz * 2.0)], col * 0.75, -(d0 + d1))
	# หินหัวโค้ง
	g.box(Vector3(0.0, spring + ro - 0.1, zf + 0.04), Vector3(0.2, 0.26, 0.06), GOLD * 0.75)
	# ลูกกรง
	var zb := zc + 0.05
	var x := -1.2
	while x <= 1.21:
		var top := spring + sqrt(maxf(ri * ri - x * x, 0.0))
		g.box(Vector3(x, top * 0.5, zb), Vector3(0.03, top * 0.5, 0.03), IRON)
		x += 0.3
	for y in [1.1, 2.2, spring]:
		g.box(Vector3(0.0, y, zb + 0.04), Vector3(ri, 0.035, 0.025), IRON)


## ช่องหลังลูกกรง: เรืองแสงเย็นจาง ๆ (ไม่อบแสงเทียน) บอกว่าเป็นทางไปที่อื่น
static func _gate_glow(g: PropsLayer.Geo) -> void:
	var r: Rect2 = HallLayout.rect_of("online")
	var z := r.position.y + 0.05
	var spring := 3.3
	var ri := 1.36
	var low := Color(0.10, 0.30, 0.34)
	var high := Color(0.03, 0.06, 0.09)
	g.poly([Vector3(-ri, 0.0, z), Vector3(ri, 0.0, z), Vector3(ri, spring, z), Vector3(-ri, spring, z)], low, Vector3(0, 0, 1))
	var cols := g.c
	for i in cols.size():
		cols[i] = low.lerp(high, clampf(g.v[i].y / (spring + ri), 0.0, 1.0))
	g.c = cols
	var start := g.v.size()
	for i in 10:
		var a0 := PI * i / 10.0
		var a1 := PI * (i + 1) / 10.0
		g.poly([Vector3(0, spring, z), Vector3(cos(a0) * ri, spring + sin(a0) * ri, z), Vector3(cos(a1) * ri, spring + sin(a1) * ri, z)],
			low, Vector3(0, 0, 1))
	cols = g.c
	for i in range(start, cols.size()):
		cols[i] = low.lerp(high, clampf(g.v[i].y / (spring + ri), 0.0, 1.0))
	g.c = cols


## ประตูทางออกในผนังหน้า: วงกบหิน บานไม้คู่ คาดเหล็ก ห่วงจับ ธรณีประตู
static func _door(g: PropsLayer.Geo) -> void:
	var r: Rect2 = HallLayout.rect_of("exit")
	var zc := r.get_center().y
	var zf := r.position.y                      # หน้าประตู (ฝั่งห้อง)
	var hw := r.size.x * 0.5
	var top := 3.0
	for sx in [-1.0, 1.0]:
		g.box(Vector3(sx * (hw + 0.02), top * 0.5, zc), Vector3(0.16, top * 0.5, 0.2), WALL * 1.05)
	g.box(Vector3(0.0, top + 0.13, zc), Vector3(hw + 0.18, 0.13, 0.2), WALL * 1.1)
	g.box(Vector3(0.0, 0.03, zf + 0.05), Vector3(hw + 0.1, 0.03, 0.12), WALL * 0.8)
	var zd := zf + 0.12
	for sx in [-1.0, 1.0]:
		var cx: float = sx * (hw - 0.16) * 0.5
		g.box(Vector3(cx, top * 0.5, zd), Vector3((hw - 0.16) * 0.5 - 0.01, top * 0.5, 0.04), WOOD_DARK)
		var px := cx - (hw - 0.16) * 0.5 + 0.18
		while px < cx + (hw - 0.16) * 0.5 - 0.1:
			g.box(Vector3(px, top * 0.5, zd - 0.045), Vector3(0.012, top * 0.5 - 0.05, 0.006), WOOD_DARK * 0.7)
			px += 0.26
		for y in [0.65, 2.25]:
			g.box(Vector3(cx, y, zd - 0.05), Vector3((hw - 0.16) * 0.5 - 0.04, 0.05, 0.012), IRON)
		g.box(Vector3(sx * 0.16, 1.25, zd - 0.07), Vector3(0.05, 0.07, 0.025), GOLD * 0.7)


# ---- เฟอร์นิเจอร์: โต๊ะรบ ตู้โชว์ แท่นอ่าน โต๊ะผจญภัย เชิงเทียน ----

static func _furniture(sides: int, lights: PackedVector3Array) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_war_table(g, rng, sides)
	_shelves(g, sides)
	_lectern(g, sides)
	_adventure(g, sides)
	for s in HallLayout.STANDS:
		_stand(g, s, sides)
	bake(g, lights)
	return g.mesh()


static func _war_table(g: PropsLayer.Geo, rng: RandomNumberGenerator, sides: int) -> void:
	var r: Rect2 = HallLayout.rect_of("battle")
	var c := r.get_center()
	var h := r.size * 0.5
	var top := float(HallLayout.STATIONS["battle"]["height"])
	g.box(Vector3(c.x, top - 0.05, c.y), Vector3(h.x, 0.05, h.y), WOOD_DARK, 0.0, true)
	g.box(Vector3(c.x, top - 0.2, c.y), Vector3(h.x - 0.12, 0.1, h.y - 0.12), WOOD_DARK * 0.8)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.box(Vector3(c.x + sx * (h.x - 0.3), (top - 0.3) * 0.5, c.y + sz * (h.y - 0.3)), Vector3(0.11, (top - 0.3) * 0.5, 0.11), WOOD_DARK * 0.9)
	# สนามจำลองบนโต๊ะ: ผืนหญ้ากับดินเป็นตาราง
	var fx := h.x - 0.32
	var fz := h.y - 0.32
	var nx := 12
	var nz := 8
	for iz in nz:
		for ix in nx:
			var x0 := c.x - fx + ix * fx * 2.0 / nx
			var z0 := c.y - fz + iz * fz * 2.0 / nz
			var pick := rng.randf()
			var col := Color(0.36, 0.50, 0.24) if pick < 0.5 else (Color(0.66, 0.53, 0.28) if pick < 0.8 else Color(0.28, 0.40, 0.20))
			col = col * rng.randf_range(0.92, 1.06)
			g.poly([Vector3(x0, top + 0.004, z0), Vector3(x0 + fx * 2.0 / nx, top + 0.004, z0),
				Vector3(x0 + fx * 2.0 / nx, top + 0.004, z0 + fz * 2.0 / nz), Vector3(x0, top + 0.004, z0 + fz * 2.0 / nz)], col, Vector3.UP)
	# ซากตึกจิ๋วกับต้นไม้จิ๋ว
	for i in 6:
		var p := Vector3(c.x + rng.randf_range(-fx + 0.4, fx - 0.4), top, c.y + rng.randf_range(-fz + 0.4, fz - 0.4))
		if i % 2 == 0:
			g.box(p + Vector3(0, 0.07, 0), Vector3(0.14, 0.07, 0.1), WALL * 0.9, rng.randf() * TAU)
		else:
			g.prism(p.x, top, p.z, 0.08, 0.24, 5, Color(0.22, 0.36, 0.18), 0.0)
	# ตัวไข่จิ๋วสองฝั่ง มีวงสีทีมใต้ตัว
	for side in [-1.0, 1.0]:
		var team := TEAM_A if side < 0.0 else TEAM_B
		for i in 4:
			var p := Vector3(c.x + side * (fx - 0.45) + rng.randf_range(-0.2, 0.2), top + 0.006, c.y - 0.9 + i * 0.6)
			_disc(g, p, 0.075, 8, team)
			lathe(g, p + Vector3(0, 0.004, 0), 0.17, 0.05, 6, IVORY, 1.0, 0.0)
	# เทียนสี่มุม
	for f in HallLayout.flames(true).slice(HallLayout.STANDS.size(), HallLayout.STANDS.size() + 4):
		_candle(g, f, top, 0.04, sides)


static func _shelves(g: PropsLayer.Geo, sides: int) -> void:
	var r: Rect2 = HallLayout.rect_of("army")
	var x_wall := r.position.x
	var x_front := r.position.x + r.size.x
	var z0 := r.position.y
	var z1 := r.position.y + r.size.y
	var zc := (z0 + z1) * 0.5
	var hz := (z1 - z0) * 0.5
	var height := float(HallLayout.STATIONS["army"]["height"])
	# แผ่นหลัง ข้าง และหัวตู้
	g.box(Vector3(x_wall + 0.04, height * 0.5, zc), Vector3(0.04, height * 0.5, hz), WOOD_DARK)
	for sz in [-1.0, 1.0]:
		g.box(Vector3((x_wall + x_front) * 0.5, height * 0.5 - 0.05, zc + sz * (hz - 0.05)), Vector3((x_front - x_wall) * 0.5, height * 0.5 - 0.05, 0.05), WOOD)
	g.box(Vector3((x_wall + x_front) * 0.5 - 0.05, height - 0.06, zc), Vector3((x_front - x_wall) * 0.5 - 0.02, 0.06, hz + 0.04), WOOD)
	# ชั้นสามขั้นแบบขั้นบันได (ล่างลึก บนตื้น) ไข่ 5 ฟองต่อชั้น ธงชายสีล้วนข้างหลัง
	var tiers := [[0.72, x_front], [1.42, x_wall + 0.66], [2.1, x_wall + 0.36]]
	var k := 0
	for t in tiers:
		var y: float = t[0]
		var xf: float = t[1]
		g.box(Vector3((x_wall + xf) * 0.5, y - 0.03, zc), Vector3((xf - x_wall) * 0.5, 0.03, hz - 0.1), WOOD * 1.05, 0.0, true)
		g.box(Vector3((x_wall + xf) * 0.5, y * 0.5, zc), Vector3((xf - x_wall) * 0.5 - 0.02, y * 0.5 - 0.03, hz - 0.12), WOOD_DARK * 0.85)
		for i in 5:
			var z := zc - hz + 0.55 + i * (hz * 2.0 - 1.1) / 4.0
			var ex := xf - 0.2
			_disc(g, Vector3(ex, y + 0.004, z), 0.11, 8, GOLD * 0.6)
			lathe(g, Vector3(ex, y + 0.008, z), 0.3, 0.085, maxi(sides / 2, 6), IVORY, 1.0, 0.0)
			# เสาธงกับธงชายสามเหลี่ยม (สองหน้า)
			var px := ex - 0.16
			g.box(Vector3(px, y + 0.25, z + 0.13), Vector3(0.008, 0.25, 0.008), IRON)
			var col: Color = PENNANTS[k % PENNANTS.size()]
			var a := Vector3(px, y + 0.48, z + 0.13)
			var b := Vector3(px, y + 0.34, z + 0.13)
			var tip := Vector3(px, y + 0.41, z + 0.36)
			g.poly([a, b, tip], col, Vector3(1, 0, 0))
			g.poly([a, b, tip], col * 0.8, Vector3(-1, 0, 0))
			k += 1


static func _lectern(g: PropsLayer.Geo, sides: int) -> void:
	var r: Rect2 = HallLayout.rect_of("settings")
	var c := r.get_center()
	g.prism(c.x, 0.0, c.y, 0.36, 0.08, sides, WOOD_DARK)
	g.box(Vector3(c.x, 0.55, c.y), Vector3(0.09, 0.5, 0.09), WOOD)
	# หน้าเอียงหันไปทาง -x (คนอ่านยืนฝั่งนั้น)
	var lo := 1.0
	var hi := 1.18
	var hx := 0.32
	var hz := 0.36
	var p := [Vector3(c.x - hx, lo, c.y - hz), Vector3(c.x - hx, lo, c.y + hz), Vector3(c.x + hx, hi, c.y + hz), Vector3(c.x + hx, hi, c.y - hz)]
	g.poly(p, WOOD, Vector3(-0.5, 1, 0))
	var d := Vector3(0, -0.06, 0)
	g.poly([p[0], p[1], p[1] + d, p[0] + d], WOOD_DARK, Vector3(-1, 0, 0))
	g.poly([p[3], p[2], p[2] + d, p[3] + d], WOOD_DARK, Vector3(1, 0, 0))
	g.poly([p[0], p[3], p[3] + d, p[0] + d], WOOD_DARK, Vector3(0, 0, -1))
	g.poly([p[1], p[2], p[2] + d, p[1] + d], WOOD_DARK, Vector3(0, 0, 1))
	g.poly([p[0] + d, p[1] + d, p[2] + d, p[3] + d], WOOD_DARK * 0.7, Vector3.DOWN)
	# หนังสือเปิด สองหน้า กับที่คั่นแดง
	var up := Vector3(0, 0.02, 0)
	var s := (hi - lo) / (hx * 2.0)
	for sz in [-1.0, 1.0]:
		var za: float = c.y + sz * 0.02
		var zb: float = c.y + sz * 0.27
		var x0 := c.x - 0.22
		var x1 := c.x + 0.2
		g.poly([Vector3(x0, lo + (x0 - c.x + hx) * s, za) + up, Vector3(x1, lo + (x1 - c.x + hx) * s, za) + up * 1.6,
			Vector3(x1, lo + (x1 - c.x + hx) * s, zb) + up, Vector3(x0, lo + (x0 - c.x + hx) * s, zb) + up], PARCHMENT * 1.1, Vector3(-0.5, 1, 0))
	g.poly([Vector3(c.x - 0.24, lo + 0.03, c.y - 0.012), Vector3(c.x - 0.24, lo + 0.03, c.y + 0.012),
		Vector3(c.x - 0.32, lo - 0.08, c.y + 0.012), Vector3(c.x - 0.32, lo - 0.08, c.y - 0.012)], CARPET, Vector3(-1, 0.3, 0))
	# เทียนเล่มใหญ่บนมุมแท่น
	var f := HallLayout.LECTERN_FLAME
	g.prism(f.x, hi - 0.05, f.z, 0.09, 0.04, sides, GOLD * 0.7)
	g.prism(f.x, hi - 0.01, f.z, 0.055, f.y - hi + 0.01, maxi(sides / 2, 6), WAX)


static func _adventure(g: PropsLayer.Geo, sides: int) -> void:
	var s: Dictionary = HallLayout.STATIONS["adventure"]
	var c: Vector2 = s["c"]
	var rad: float = (s["h"] as Vector2).x
	var top := float(s["height"])
	var n := maxi(sides + 4, 12)
	g.prism(c.x, 0.0, c.y, 0.55, 0.08, n, WOOD_DARK)
	g.prism(c.x, 0.08, c.y, 0.17, top - 0.14, sides, WOOD)
	g.prism(c.x, top - 0.06, c.y, rad, 0.06, n, WOOD, 1.0, 0.0, true, true)
	for p in HallLayout.stools():
		g.prism(p.x, 0.0, p.y, HallLayout.STOOL_R * 0.55, HallLayout.STOOL_H - 0.06, maxi(sides / 2, 6), WOOD_DARK)
		g.prism(p.x, HallLayout.STOOL_H - 0.06, p.y, HallLayout.STOOL_R, 0.06, sides, WOOD)
	# แผนที่ม้วนกับแผ่นที่กางอยู่ และลูกเต๋าสองลูก
	g.poly([Vector3(c.x - 0.6, top + 0.004, c.y + 0.1), Vector3(c.x + 0.25, top + 0.004, c.y + 0.1),
		Vector3(c.x + 0.25, top + 0.004, c.y + 0.75), Vector3(c.x - 0.6, top + 0.004, c.y + 0.75)], PARCHMENT, Vector3.UP)
	g.xprism(c.x - 0.62, c.x + 0.27, top + 0.05, c.y + 0.8, 0.05, 6, PARCHMENT * 0.9)
	g.box(Vector3(c.x + 0.5, top + 0.03, c.y - 0.4), Vector3(0.03, 0.03, 0.03), IVORY, 0.4)
	g.box(Vector3(c.x + 0.62, top + 0.03, c.y - 0.3), Vector3(0.03, 0.03, 0.03), CARPET * 1.4, 1.1)
	_candle(g, HallLayout.ADVENTURE_FLAME, top, 0.045, sides)


## เชิงเทียนตั้งพื้นชิดผนัง: ฐาน ก้าน ถาด แขน เทียนสามเล่ม
static func _stand(g: PropsLayer.Geo, s: Vector2, sides: int) -> void:
	var arm := HallLayout.stand_arm(s)
	var n := maxi(sides / 2, 6)
	g.prism(s.x, 0.0, s.y, 0.24, 0.05, n, IRON)
	g.prism(s.x, 0.05, s.y, 0.12, 0.08, n, IRON, 0.4)
	g.prism(s.x, 0.12, s.y, 0.03, HallLayout.STAND_H - 0.12, 6, IRON)
	g.prism(s.x, HallLayout.STAND_H - 0.02, s.y, 0.11, 0.04, n, IRON)
	var yaw := 0.0 if arm.x > 0.5 else PI * 0.5
	g.box(Vector3(s.x, HallLayout.STAND_H + 0.02, s.y), Vector3(HallLayout.STAND_ARM + 0.03, 0.015, 0.015), IRON, yaw)
	var base := Vector3(s.x, HallLayout.STAND_H + 0.02, s.y)
	_candle_at(g, base, HallLayout.STAND_FLAME_MID, 0.038)
	for side in [-1.0, 1.0]:
		var p: Vector3 = base + arm * HallLayout.STAND_ARM * side
		g.prism(p.x, p.y - 0.01, p.z, 0.05, 0.03, 6, IRON)
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


# ---- ผ้า: ธงแขวนผนังลายเทียนในวงกลม (ลายของเราเอง) ----

static func _cloth(lights: PackedVector3Array) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	for b in HallLayout.BANNERS:
		_banner(g, b["p"], b["n"], BANNER_COLS[int(b["col"]) % BANNER_COLS.size()])
	bake(g, lights)
	return g.mesh()


## ธงหนึ่งผืน: p = กลางบนผิวผนัง, n2 = ทิศเข้าห้อง (x, z)
static func _banner(g: PropsLayer.Geo, p: Vector3, n2: Vector2, col: Color) -> void:
	var n := Vector3(n2.x, 0.0, n2.y)
	var yaw := atan2(n2.x, n2.y)
	var u := Vector3(cos(yaw), 0.0, -sin(yaw))
	var hw := 0.65
	var top := p + Vector3(0, 1.2, 0)
	var o := n * 0.05
	# ราวแขวน
	g.box(top + n * 0.07 + Vector3(0, 0.05, 0), Vector3(hw + 0.15, 0.025, 0.025), WOOD_DARK, yaw)
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
static func build_colliders(body: StaticBody3D, props: StaticBody3D = null) -> int:
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
	for b in HallLayout.blockers():
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
