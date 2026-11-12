class_name ArenaBuilder
extends RefCounted
## สร้างเมชของอารีน่า (ARENA_SPEC §4.4) ด้วยโค้ด แบบเดียวกับดาดฟ้ายานรบ: สีจุดยอดอบแสงแล้ว (เทียน + แสงเย็น) ไม่มีไฟจริง
## เมชนิ่ง 2 ชิ้น [Shell = ทางเดิน ห้อง แผ่นกระดาน เสากำบัง, Props = เชิงเทียน เสาสวิตช์ แท่นรีเซ็ต ธง เทียน]
## จำไว้ตามจำนวนเหลี่ยม (14 / 12 / 10 / 8) · ชิ้นแยก: แผ่นเป้าสวิตช์ โคมสัญญาณ (สร้างที่ ArenaWorld)
## ดีไซน์ของเราเอง ภาษาเดียวกับดาดฟ้า: เหล็ก บรอนซ์ ลายเตือนเหลืองดำ ลายเทียน · สุ่มแบบมี seed เท่านั้น

const STEEL := HallBuilder.STEEL
const STEEL_DARK := HallBuilder.STEEL_DARK
const DECK := HallBuilder.DECK
const GRATE := HallBuilder.GRATE
const BRONZE := HallBuilder.BRONZE
const BRASS := HallBuilder.BRASS
const HAZARD := HallBuilder.HAZARD
const HAZARD_DARK := HallBuilder.HAZARD_DARK
const LAMP_AMBER := HallBuilder.LAMP_AMBER
const FLOOD_GLOW := Color(0.92, 0.95, 1.0)
const K := 5                    # ช่องต่อครึ่งโค้ง
const OVER := 0.06              # ผิวที่ชนกันยื่นเลยกันเล็กน้อย กันรอยแยก

static var _cache: Dictionary = {}


## เมชนิ่ง [Shell, Props] ตามจำนวนเหลี่ยม
static func meshes(sides: int) -> Array[ArrayMesh]:
	var key := "arena|%d" % sides
	if _cache.has(key):
		return _cache[key]
	var lights := ArenaLayout.flames()
	var out: Array[ArrayMesh] = [_shell(sides, lights), _props(sides, lights)]
	_cache[key] = out
	return out


# ---- โครง: ทางเดิน ผนังหน้าห้องกับช่องโค้ง ห้อง เพดาน กระดาน เสากำบัง ----

static func _shell(sides: int, lights: PackedVector3Array) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	var glow_g := PropsLayer.Geo.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4404
	_corridor(g, glow_g, rng)
	_near_wall(g, rng)
	_room_floor(g, rng)
	_room_walls(g, rng)
	_ceiling(g, glow_g)
	_board(g)
	for p in ArenaLayout.PILLARS:
		_pillar(g, p, sides)
	HallBuilder.bake(g, lights, ArenaLayout.LIGHTS)
	HallBuilder.append(g, glow_g)
	return g.mesh()


static func _quad(g: PropsLayer.Geo, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, n: Vector3) -> void:
	g.poly([a, b, c, d], col, n)


## แผงเหล็ก 2 x 1.5 ม. บนผนังแนวตั้ง: o = มุมล่างของผนัง, u = ทิศตามผนัง, n = ทิศเข้าห้อง, ยาว length ตั้งแต่ y0 ถึง top
## cut = ช่วง s ที่เว้น (ช่องโค้ง) สำหรับแถวที่เริ่มต่ำกว่า cut.z
static func _panels(g: PropsLayer.Geo, rng: RandomNumberGenerator, o: Vector3, u: Vector3, n: Vector3, length: float,
		y0: float, top: float, cut: Vector3 = Vector3.ZERO) -> void:
	var gap := 0.03
	var y := y0
	while y < top - 0.01:
		var y1 := minf(y + 1.5, top)
		var a := 0.0
		while a < length - 0.01:
			var b := minf(a + 2.0, length)
			var k := rng.randf_range(0.84, 1.04)
			var spans: Array[Vector2] = [Vector2(a + gap, b - gap)]
			if y < cut.z and b > cut.x and a < cut.y:
				spans = []
				if a + gap < cut.x:
					spans.append(Vector2(a + gap, cut.x))
				if b - gap > cut.y:
					spans.append(Vector2(cut.y, b - gap))
			for sp in spans:
				var off := n * 0.004
				_quad(g, o + u * sp.x + Vector3(0, y + gap, 0) + off, o + u * sp.y + Vector3(0, y + gap, 0) + off,
					o + u * sp.y + Vector3(0, y1 - gap, 0) + off, o + u * sp.x + Vector3(0, y1 - gap, 0) + off, STEEL * k, n)
			a = b
		y = y1


## แผงล่างบรอนซ์สูง 1 ม. กับคิ้วทองเหลือง จาก s0 ถึง s1
static func _wainscot(g: PropsLayer.Geo, o: Vector3, u: Vector3, n: Vector3, s0: float, s1: float) -> void:
	var a := s0
	while a < s1 - 0.001:
		var b := minf(a + 2.0, s1)
		var off := n * 0.006
		_quad(g, o + u * a + off, o + u * b + off, o + u * b + Vector3(0, 1.0, 0) + off, o + u * a + Vector3(0, 1.0, 0) + off,
			BRONZE * (0.42 if int(roundf(a / 2.0)) % 2 == 0 else 0.46), n)
		a = b
	var c := n * 0.03
	_quad(g, o + u * s0 + Vector3(0, 0.96, 0) + c, o + u * s1 + Vector3(0, 0.96, 0) + c, o + u * s1 + Vector3(0, 1.04, 0) + c,
		o + u * s0 + Vector3(0, 1.04, 0) + c, BRASS * 0.7, n)
	_quad(g, o + u * s0 + Vector3(0, 1.04, 0) + c, o + u * s1 + Vector3(0, 1.04, 0) + c, o + u * s1 + Vector3(0, 1.04, 0),
		o + u * s0 + Vector3(0, 1.04, 0), BRASS * 0.8, Vector3.UP)


## แถบลายเตือนเหลืองดำบนพื้น: กลาง c, u = ทิศตามแถบ, ครึ่งยาว hu, ครึ่งกว้าง hv (แบบดาดฟ้า)
static func _chevrons(g: PropsLayer.Geo, c: Vector3, u: Vector3, hu: float, hv: float, col: Color = HAZARD) -> void:
	var v := Vector3.UP.cross(u).normalized()
	g.poly([c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv], HAZARD_DARK, Vector3.UP)
	var w := 0.12
	var step := 0.3
	var skew := hv * 1.2
	var s := -hu + 0.04
	var lift := Vector3(0.0, 0.002, 0.0)
	while s + w + skew <= hu - 0.04:
		g.poly([c + u * s - v * hv + lift, c + u * (s + w) - v * hv + lift, c + u * (s + w + skew) + v * hv + lift,
			c + u * (s + skew) + v * hv + lift], col, Vector3.UP)
		s += step


static func _corridor(g: PropsLayer.Geo, glow_g: PropsLayer.Geo, rng: RandomNumberGenerator) -> void:
	var hx := ArenaLayout.CORR_X
	var z0 := ArenaLayout.CORR_Z0
	var z1 := ArenaLayout.CORR_Z1
	var h := ArenaLayout.CORR_H
	# พื้น: แผ่นเหล็กสองแถว ตะแกรงกลาง คานขวาง
	_quad(g, Vector3(-hx - OVER, -0.004, z0 + OVER), Vector3(hx + OVER, -0.004, z0 + OVER), Vector3(hx + OVER, -0.004, z1 - OVER),
		Vector3(-hx - OVER, -0.004, z1 - OVER), HallBuilder.DECK_SEAM, Vector3.UP)
	var z := z0
	while z > z1 + 0.01:
		var zn := maxf(z - 1.0, z1)
		for sx in [-1.0, 1.0]:
			var xa: float = sx * 0.42
			var xb: float = sx * (hx - 0.02)
			var k := rng.randf_range(0.86, 1.06)
			_quad(g, Vector3(minf(xa, xb), 0.0, z - 0.02), Vector3(maxf(xa, xb), 0.0, z - 0.02), Vector3(maxf(xa, xb), 0.0, zn + 0.02),
				Vector3(minf(xa, xb), 0.0, zn + 0.02), DECK * k, Vector3.UP)
		z = zn
	_quad(g, Vector3(-0.4, 0.002, z0), Vector3(0.4, 0.002, z0), Vector3(0.4, 0.002, z1), Vector3(-0.4, 0.002, z1), GRATE * 0.7, Vector3.UP)
	z = z0 - 0.25
	while z > z1 + 0.1:
		_quad(g, Vector3(-0.4, 0.006, z + 0.03), Vector3(0.4, 0.006, z + 0.03), Vector3(0.4, 0.006, z - 0.03),
			Vector3(-0.4, 0.006, z - 0.03), GRATE * 1.6, Vector3.UP)
		z -= 0.33
	# ผนังสองข้าง: ผิวมืด แผงเหล็ก แผงล่าง
	for sx in [-1.0, 1.0]:
		var x: float = sx * hx
		var n := Vector3(-sx, 0.0, 0.0)
		var o := Vector3(x, 0.0, z0)
		var u := Vector3(0.0, 0.0, -1.0)
		var length := z0 - z1
		_quad(g, o - u * OVER + Vector3(0, -OVER, 0), o + u * (length + OVER) + Vector3(0, -OVER, 0), o + u * (length + OVER) + Vector3(0, h + OVER, 0),
			o - u * OVER + Vector3(0, h + OVER, 0), STEEL_DARK * 0.6, n)
		_panels(g, rng, o, u, n, length, 1.0, h)
		_wainscot(g, o, u, n, 0.0, length)
	# ซี่โครงทุก 2 ม. (ลึก 0.12 ม.) ผนังกับคานเพดาน
	for i in range(1, 5):
		var zr := z0 - i * 2.0
		for sx in [-1.0, 1.0]:
			g.box(Vector3(sx * (hx - 0.06), h * 0.5, zr), Vector3(0.06, h * 0.5, 0.08), STEEL * 0.95)
		g.box(Vector3(0.0, h - 0.06, zr), Vector3(hx, 0.06, 0.08), STEEL * 0.9, 0.0, true)
	# เพดานเรียบ ไฟแถบอำพัน
	_quad(g, Vector3(-hx - OVER, h, z0 + OVER), Vector3(hx + OVER, h, z0 + OVER), Vector3(hx + OVER, h, z1 - OVER), Vector3(-hx - OVER, h, z1 - OVER),
		STEEL * 0.7, Vector3.DOWN)
	for i in 5:
		var za := z0 - i * 2.0 - 0.3
		var zb := za - 1.4
		glow_g.poly([Vector3(-0.07, h - 0.01, za), Vector3(0.07, h - 0.01, za), Vector3(0.07, h - 0.01, zb), Vector3(-0.07, h - 0.01, zb)],
			LAMP_AMBER * 0.9, Vector3.DOWN)
	# รางสายไฟผนังขวา
	g.box(Vector3(hx - 0.1, 3.6, (z0 + z1) * 0.5), Vector3(0.09, 0.025, (z0 - z1) * 0.5), STEEL_DARK * 0.9, 0.0, true)
	for k in 2:
		var xk := hx - 0.06 - k * 0.07
		HallBuilder.tube(g, Vector3(xk, 3.65, z0), Vector3(xk, 3.65, z1), 0.025, 4, Color(0.30, 0.10, 0.08) if k == 0 else STEEL_DARK * 0.6)
	_pressure_door(g, glow_g)


## ประตูแรงดัน "กลับดาดฟ้า" ที่ปลายทางเดิน (ด้านหน้าที่ z -0.3 ของกล่องกัน DOOR_BACK): แผ่นเต็มช่อง บานสองบาน คิ้วบรอนซ์
## ลายเตือน ไฟอำพันเหนือบาน (ประตูบานเดียวกับที่เห็นจากดาดฟ้า)
static func _pressure_door(g: PropsLayer.Geo, glow_g: PropsLayer.Geo) -> void:
	var hx := ArenaLayout.CORR_X
	var h := ArenaLayout.CORR_H
	var dc: Vector2 = ArenaLayout.DOOR_BACK["c"]
	var dh: Vector2 = ArenaLayout.DOOR_BACK["h"]
	var zf := dc.y - dh.y
	var n := Vector3(0, 0, -1)
	_quad(g, Vector3(-hx - OVER, -OVER, zf), Vector3(hx + OVER, -OVER, zf), Vector3(hx + OVER, h + OVER, zf), Vector3(-hx - OVER, h + OVER, zf),
		STEEL_DARK * 0.85, n)
	var lh := 2.5
	for sx in [-1.0, 1.0]:
		g.box(Vector3(sx * 0.5, lh * 0.5, zf - 0.03), Vector3(0.48, lh * 0.5, 0.03), STEEL * (0.78 if sx < 0.0 else 0.72))
		# เสากรอบข้างบาน
		g.box(Vector3(sx * (hx - 0.13), (lh + 0.2) * 0.5, zf - 0.05), Vector3(0.13, (lh + 0.2) * 0.5, 0.05), STEEL * 0.9)
	var fz := zf - 0.065
	_quad(g, Vector3(-0.025, 0.0, fz), Vector3(0.025, 0.0, fz), Vector3(0.025, lh, fz), Vector3(-0.025, lh, fz), STEEL_DARK * 0.4, n)
	for y in [1.0, 1.95]:
		_quad(g, Vector3(-0.96, y, fz), Vector3(0.96, y, fz), Vector3(0.96, y + 0.1, fz), Vector3(-0.96, y + 0.1, fz), BRONZE * 0.85, n)
	g.box(Vector3(0.0, lh + 0.1, zf - 0.06), Vector3(hx, 0.1, 0.06), BRONZE * 0.8, 0.0, true)
	_quad(g, Vector3(-0.96, 0.12, fz), Vector3(0.96, 0.12, fz), Vector3(0.96, 0.46, fz), Vector3(-0.96, 0.46, fz), HAZARD_DARK, n)
	var xs := -0.92
	while xs + 0.3 <= 0.94:
		_quad(g, Vector3(xs, 0.14, fz - 0.002), Vector3(xs + 0.12, 0.14, fz - 0.002), Vector3(xs + 0.26, 0.44, fz - 0.002),
			Vector3(xs + 0.14, 0.44, fz - 0.002), HAZARD, n)
		xs += 0.3
	# แผ่นป้ายใต้ข้อความ "กลับดาดฟ้า" กับไฟอำพัน
	var sp: Vector3 = ArenaLayout.SIGNS["door_back"]["p"]
	g.box(Vector3(0.0, sp.y, zf - 0.01), Vector3(1.2, 0.42, 0.01), BRONZE * 0.6)
	g.box(Vector3(0.0, lh + 0.42, zf - 0.04), Vector3(0.16, 0.08, 0.04), STEEL_DARK)
	glow_g.poly([Vector3(-0.11, lh + 0.37, zf - 0.085), Vector3(0.11, lh + 0.37, zf - 0.085), Vector3(0.11, lh + 0.47, zf - 0.085),
		Vector3(-0.11, lh + 0.47, zf - 0.085)], LAMP_AMBER, n)


## ผนังหน้าห้อง (z -10.0 ฝั่งทางเดิน ถึง -10.5 ฝั่งห้อง) กับช่องโค้งแหลม: ผิวทั้งสองฝั่ง ผิวในช่อง ลายเตือนที่ธรณี
static func _near_wall(g: PropsLayer.Geo, rng: RandomNumberGenerator) -> void:
	var zc := ArenaLayout.CORR_Z1
	var zr := ArenaLayout.ROOM_MAX.y
	var ar: Dictionary = ArenaLayout.ARCH
	var a := (float(ar["x1"]) - float(ar["x0"])) * 0.5
	var sp := float(ar["spring"])
	var ap := float(ar["apex"])
	var pts := HallBuilder.arch_pts(a, sp, ap, K)
	var hx := ArenaLayout.ROOM_MAX.x
	var top := ArenaLayout.ROOM_H
	var ch := ArenaLayout.CORR_H
	var cx := ArenaLayout.CORR_X
	# ฝั่งทางเดิน (หันไป +z): แถบข้างช่อง เหนือโค้งถึงเพดานทางเดิน
	var nc := Vector3(0, 0, 1)
	# แผ่นข้างช่องแบ่งที่จุดเริ่มโค้ง ให้มุมตรงกับแถบเหนือโค้ง (ไม่มีรอยต่อรูปตัว T ให้เห็นทะลุ)
	for side in [-1.0, 1.0]:
		for yy in [Vector2(-OVER, sp), Vector2(sp, ch + OVER)]:
			_quad(g, Vector3(side * a, yy.x, zc), Vector3(side * (cx + OVER), yy.x, zc), Vector3(side * (cx + OVER), yy.y, zc),
				Vector3(side * a, yy.y, zc), STEEL_DARK * 0.75, nc)
		for j in K:
			_quad(g, Vector3(side * pts[j].x, pts[j].y, zc), Vector3(side * pts[j + 1].x, pts[j + 1].y, zc),
				Vector3(side * pts[j + 1].x, ch + OVER, zc), Vector3(side * pts[j].x, ch + OVER, zc), STEEL_DARK * 0.75, nc)
	# กรอบบรอนซ์รอบช่องฝั่งทางเดิน กับแผ่นป้ายเหนือโค้ง
	for side in [-1.0, 1.0]:
		_quad(g, Vector3(side * a, 0.0, zc + 0.01), Vector3(side * (a + 0.12), 0.0, zc + 0.01), Vector3(side * (a + 0.12), sp, zc + 0.01),
			Vector3(side * a, sp, zc + 0.01), BRONZE * 0.75, nc)
	var po := HallBuilder.arch_pts(a + 0.12, sp, ap + 0.17, K)
	for side in [-1.0, 1.0]:
		for j in K:
			_quad(g, Vector3(side * po[j].x, po[j].y, zc + 0.01), Vector3(side * po[j + 1].x, po[j + 1].y, zc + 0.01),
				Vector3(side * pts[j + 1].x, pts[j + 1].y, zc + 0.01), Vector3(side * pts[j].x, pts[j].y, zc + 0.01), BRONZE * 0.75, nc)
	var sg: Vector3 = ArenaLayout.SIGNS["door_arena"]["p"]
	g.box(Vector3(0.0, sg.y, zc + 0.01), Vector3(1.2, 0.3, 0.01), BRONZE * 0.6)
	# ฝั่งห้อง (หันไป -z): ผิวมืด แผงเหล็ก แผงล่าง เว้นช่อง
	var n := Vector3(0, 0, -1)
	for yy in [Vector2(-OVER, sp), Vector2(sp, top + OVER)]:
		_quad(g, Vector3(-hx - OVER, yy.x, zr), Vector3(-a, yy.x, zr), Vector3(-a, yy.y, zr), Vector3(-hx - OVER, yy.y, zr), STEEL_DARK * 0.6, n)
		_quad(g, Vector3(a, yy.x, zr), Vector3(hx + OVER, yy.x, zr), Vector3(hx + OVER, yy.y, zr), Vector3(a, yy.y, zr), STEEL_DARK * 0.6, n)
	for side in [-1.0, 1.0]:
		for j in K:
			_quad(g, Vector3(side * pts[j].x, pts[j].y, zr), Vector3(side * pts[j + 1].x, pts[j + 1].y, zr),
				Vector3(side * pts[j + 1].x, top + OVER, zr), Vector3(side * pts[j].x, top + OVER, zr), STEEL_DARK * 0.6, n)
	var o := Vector3(-hx, 0.0, zr)
	var u := Vector3(1, 0, 0)
	_panels(g, rng, o, u, n, hx * 2.0, 1.0, top, Vector3(hx - a - 0.15, hx + a + 0.15, ap + 0.3))
	_wainscot(g, o, u, n, 0.0, hx - a)
	_wainscot(g, o, u, n, hx + a, hx * 2.0)
	# คิ้วบรอนซ์รอบช่องฝั่งห้อง
	for side in [-1.0, 1.0]:
		_quad(g, Vector3(side * a, 0.0, zr - 0.012), Vector3(side * (a + 0.15), 0.0, zr - 0.012), Vector3(side * (a + 0.15), sp, zr - 0.012),
			Vector3(side * a, sp, zr - 0.012), BRONZE * 0.8, n)
	var po2 := HallBuilder.arch_pts(a + 0.15, sp, ap + 0.21, K)
	for side in [-1.0, 1.0]:
		for j in K:
			_quad(g, Vector3(side * po2[j].x, po2[j].y, zr - 0.012), Vector3(side * po2[j + 1].x, po2[j + 1].y, zr - 0.012),
				Vector3(side * pts[j + 1].x, pts[j + 1].y, zr - 0.012), Vector3(side * pts[j].x, pts[j].y, zr - 0.012), BRONZE * 0.8, n)
	# ผิวในช่อง (เต็มความหนาผนัง): ข้างสองด้าน ใต้โค้ง ธรณี
	for side in [-1.0, 1.0]:
		_quad(g, Vector3(side * a, 0.0, zc + 0.004), Vector3(side * a, sp, zc + 0.004), Vector3(side * a, sp, zr - 0.004), Vector3(side * a, 0.0, zr - 0.004),
			STEEL * 0.7, Vector3(-side, 0, 0))
		for j in K:
			var p0 := pts[j]
			var p1 := pts[j + 1]
			_quad(g, Vector3(side * p0.x, p0.y, zc + 0.004), Vector3(side * p1.x, p1.y, zc + 0.004), Vector3(side * p1.x, p1.y, zr - 0.004),
				Vector3(side * p0.x, p0.y, zr - 0.004), STEEL * 0.62, Vector3(-side * (p0.x + p1.x) * 0.5, -1.0, 0.0))
	_quad(g, Vector3(-a, 0.0, zc + 0.004), Vector3(a, 0.0, zc + 0.004), Vector3(a, 0.0, zr - 0.004), Vector3(-a, 0.0, zr - 0.004), DECK * 0.9, Vector3.UP)
	_chevrons(g, Vector3(0.0, 0.01, (zc + zr) * 0.5), Vector3.RIGHT, a - 0.02, 0.2)
	# ธงลายเทียนของเราสองข้างช่องโค้ง (ฝั่งห้อง)
	for sx in [-1.0, 1.0]:
		_banner(g, Vector3(sx * 3.6, 3.8, zr), Vector2(0.0, -1.0), HallBuilder.BANNER_COLS[0])


## พื้นห้อง: แผ่นเหล็กมืด 2 x 2 ม. เส้นยิงลายเตือน เส้นระยะ แท่นสัตว์รัง (จานมืด วงลายเตือน)
static func _room_floor(g: PropsLayer.Geo, rng: RandomNumberGenerator) -> void:
	var mn := ArenaLayout.ROOM_MIN
	var mx := ArenaLayout.ROOM_MAX
	_quad(g, Vector3(mn.x - OVER, -0.004, mx.y + OVER), Vector3(mx.x + OVER, -0.004, mx.y + OVER), Vector3(mx.x + OVER, -0.004, mn.y - OVER),
		Vector3(mn.x - OVER, -0.004, mn.y - OVER), HallBuilder.DECK_SEAM, Vector3.UP)
	var gap := 0.03
	var z := mx.y
	while z > mn.y + 0.01:
		var zn := maxf(z - 2.0, mn.y)
		var x := mn.x
		while x < mx.x - 0.01:
			var xn := minf(x + 2.0, mx.x)
			var k := rng.randf_range(0.62, 0.78)
			_quad(g, Vector3(x + gap, 0.0, z - gap), Vector3(xn - gap, 0.0, z - gap), Vector3(xn - gap, 0.0, zn + gap), Vector3(x + gap, 0.0, zn + gap),
				Color(DECK.r * k, DECK.g * k, DECK.b * k * 1.03, 1.0), Vector3.UP)
			x = xn
		z = zn
	_chevrons(g, Vector3(0.0, 0.012, ArenaLayout.SHOOT_Z), Vector3.RIGHT, 2.0, 0.14, HAZARD * 0.85)
	for zl in ArenaLayout.RANGE_LINES:
		_quad(g, Vector3(-2.0, 0.01, zl + 0.03), Vector3(2.0, 0.01, zl + 0.03), Vector3(2.0, 0.01, zl - 0.03), Vector3(-2.0, 0.01, zl - 0.03),
			HAZARD * 0.45, Vector3.UP)
	# แท่นสัตว์รัง
	var bc := ArenaLayout.BEAST_SPAWN
	var r := ArenaLayout.PAD_R
	var segs := 24
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var c := bc + Vector3(0, 0.008, 0)
		g.poly([c, c + d0 * (r - 0.2), c + d1 * (r - 0.2)], STEEL_DARK * 0.55, Vector3.UP)
		g.poly([c + d0 * (r - 0.2), c + d1 * (r - 0.2), c + d1 * r, c + d0 * r], HAZARD * 0.8 if i % 2 == 0 else HAZARD_DARK, Vector3.UP)


## ผนังซ้าย ขวา ไกล: ผิวมืด แผงเหล็กเหนือแผงล่างบรอนซ์ เสาเหลี่ยมนูนทุก 4 ม. (ยื่นไม่เกิน 0.15 ม.)
static func _room_walls(g: PropsLayer.Geo, rng: RandomNumberGenerator) -> void:
	var mn := ArenaLayout.ROOM_MIN
	var mx := ArenaLayout.ROOM_MAX
	var top := ArenaLayout.ROOM_H
	var walls := [
		[Vector3(mn.x, 0.0, mx.y), Vector3(0, 0, -1), Vector3(1, 0, 0), mx.y - mn.y],     # ซ้าย
		[Vector3(mx.x, 0.0, mn.y), Vector3(0, 0, 1), Vector3(-1, 0, 0), mx.y - mn.y],     # ขวา
		[Vector3(mn.x, 0.0, mn.y), Vector3(1, 0, 0), Vector3(0, 0, 1), mx.x - mn.x],      # ไกล
	]
	for w in walls:
		var o: Vector3 = w[0]
		var u: Vector3 = w[1]
		var n: Vector3 = w[2]
		var length: float = w[3]
		_quad(g, o - u * OVER + Vector3(0, -OVER, 0), o + u * (length + OVER) + Vector3(0, -OVER, 0), o + u * (length + OVER) + Vector3(0, top + OVER, 0),
			o - u * OVER + Vector3(0, top + OVER, 0), STEEL_DARK * 0.6, n)
		var far := n.z > 0.5
		# กระดานบนผนังไกล: แผงเว้นช่วงกระดาน
		var bw := float(ArenaLayout.BOARD["w"])
		var cut := Vector3((length - bw) * 0.5 - 0.3, (length + bw) * 0.5 + 0.3, 7.0) if far else Vector3.ZERO
		_panels(g, rng, o, u, n, length, 1.0, top, cut)
		if far:
			# แผงเหนือ/ใต้กระดาน
			var bc: Vector3 = ArenaLayout.BOARD["c"]
			var bh := float(ArenaLayout.BOARD["h"]) * 0.5
			_panels(g, rng, o + u * cut.x, u, n, cut.y - cut.x, bc.y + bh + 0.3, top)
			_panels(g, rng, o + u * cut.x, u, n, cut.y - cut.x, 1.0, bc.y - bh - 0.3)
		_wainscot(g, o, u, n, 0.0, length)
		var s := 4.0
		while s < length - 0.5:
			var p := o + u * s
			if not (far and absf(s - length * 0.5) < bw * 0.5 + 0.5):
				var hu := Vector3(absf(u.x), 0.0, absf(u.z))
				var hn := Vector3(absf(n.x), 0.0, absf(n.z))
				g.box(p + n * 0.075 + Vector3(0, top * 0.5, 0), hu * 0.15 + hn * 0.075 + Vector3(0, top * 0.5, 0), STEEL * 0.9)
				g.box(p + n * 0.08 + Vector3(0, 0.55, 0), hu * 0.18 + hn * 0.08 + Vector3(0, 0.55, 0), BRONZE * 0.5)
			s += 4.0


## เพดานเหล็กมืดที่ 7.0 คานลึกตามขวางทุก 4 ม. คานตามยาวสองแนว โคมไฟสาดหกดวง (สว่าง ไม่อบแสง)
static func _ceiling(g: PropsLayer.Geo, glow_g: PropsLayer.Geo) -> void:
	var mn := ArenaLayout.ROOM_MIN
	var mx := ArenaLayout.ROOM_MAX
	var top := ArenaLayout.ROOM_H
	_quad(g, Vector3(mn.x - OVER, top, mx.y + OVER), Vector3(mx.x + OVER, top, mx.y + OVER), Vector3(mx.x + OVER, top, mn.y - OVER),
		Vector3(mn.x - OVER, top, mn.y - OVER), STEEL_DARK * 0.7, Vector3.DOWN)
	var z := mx.y - 2.0
	while z > mn.y + 0.5:
		g.box(Vector3(0.0, top - 0.2, z), Vector3(mx.x, 0.2, 0.15), STEEL * 0.8, 0.0, true)
		z -= 4.0
	for sx in [-1.0, 1.0]:
		g.box(Vector3(sx * 5.0, top - 0.15, (mn.y + mx.y) * 0.5), Vector3(0.12, 0.15, (mx.y - mn.y) * 0.5), STEEL * 0.75, 0.0, true)
	for f in ArenaLayout.FLOODS:
		g.box(Vector3(f.x, top - 0.32, f.z), Vector3(0.5, 0.06, 0.32), STEEL_DARK, 0.0, false)
		glow_g.poly([Vector3(f.x - 0.42, top - 0.385, f.z - 0.25), Vector3(f.x + 0.42, top - 0.385, f.z - 0.25),
			Vector3(f.x + 0.42, top - 0.385, f.z + 0.25), Vector3(f.x - 0.42, top - 0.385, f.z + 0.25)], FLOOD_GLOW, Vector3.DOWN)


## แผ่นกระดานสถานะสีมืดกรอบบรอนซ์บนผนังไกล (ข้อความเป็น Label3D ของ ArenaWorld)
static func _board(g: PropsLayer.Geo) -> void:
	var c: Vector3 = ArenaLayout.BOARD["c"]
	var hw := float(ArenaLayout.BOARD["w"]) * 0.5
	var hh := float(ArenaLayout.BOARD["h"]) * 0.5
	var zf := ArenaLayout.ROOM_MIN.y
	g.box(Vector3(c.x, c.y, zf + 0.025), Vector3(hw, hh, 0.025), Color(0.05, 0.08, 0.07), 0.0, true)
	var fw := 0.12
	g.box(Vector3(c.x, c.y + hh + fw * 0.5, zf + 0.04), Vector3(hw + fw, fw * 0.5, 0.04), BRONZE * 0.85, 0.0, true)
	g.box(Vector3(c.x, c.y - hh - fw * 0.5, zf + 0.04), Vector3(hw + fw, fw * 0.5, 0.04), BRONZE * 0.85, 0.0, true)
	for sx in [-1.0, 1.0]:
		g.box(Vector3(c.x + sx * (hw + fw * 0.5), c.y, zf + 0.04), Vector3(fw * 0.5, hh, 0.04), BRONZE * 0.85, 0.0, true)
	# เส้นแบ่งหัวกับเนื้อ
	g.poly([Vector3(c.x - hw + 0.3, c.y + 0.62, zf + 0.052), Vector3(c.x + hw - 0.3, c.y + 0.62, zf + 0.052),
		Vector3(c.x + hw - 0.3, c.y + 0.66, zf + 0.052), Vector3(c.x - hw + 0.3, c.y + 0.66, zf + 0.052)], Color(0.20, 0.45, 0.30), Vector3(0, 0, 1))


## เสากำบังแปดเหลี่ยม: ฐาน ตัวเสา แถบบรอนซ์สองแถบ หมวกบน
static func _pillar(g: PropsLayer.Geo, p: Vector2, sides: int) -> void:
	var r := ArenaLayout.PILLAR_R
	var h := ArenaLayout.PILLAR_H
	var rot := PI / 8.0
	g.prism(p.x, 0.0, p.y, r, 0.2, 8, STEEL * 0.7, 1.0, rot)
	g.prism(p.x, 0.2, p.y, r * 0.93, h - 0.45, 8, STEEL * 0.95, 1.0, rot, false)
	for y in [0.9, 2.9]:
		g.prism(p.x, y, p.y, r * 0.97, 0.16, 8, BRONZE * 0.85, 1.0, rot, false)
	g.prism(p.x, h - 0.25, p.y, r, 0.25, 8, STEEL * 0.8, 1.0, rot)
	if sides >= 12:
		# ลายเตือนรอบโคนเสา (hi/mid)
		for i in 8:
			var a := rot + i * TAU / 8.0 + TAU / 16.0
			var d := Vector3(cos(a), 0.0, -sin(a))
			var t := Vector3(-d.z, 0.0, d.x)
			var c := Vector3(p.x, 0.0, p.y) + d * (r * 0.93 * cos(PI / 8.0) + 0.004)
			g.poly([c - t * 0.18 + Vector3(0, 0.3, 0), c + t * 0.18 + Vector3(0, 0.3, 0), c + t * 0.18 + Vector3(0, 0.42, 0),
				c - t * 0.18 + Vector3(0, 0.42, 0)], HAZARD * 0.8, d)


# ---- ของในห้อง: เชิงเทียน เสาสวิตช์ แท่นรีเซ็ต ----

static func _props(sides: int, lights: PackedVector3Array) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	for s in ArenaLayout.STANDS:
		_stand(g, s, sides)
	_switch_post(g, sides)
	_reset_pedestal(g, sides)
	HallBuilder.bake(g, lights, ArenaLayout.LIGHTS)
	return g.mesh()


## เชิงเทียนแบบดาดฟ้า เทียนเล่มเดียว
static func _stand(g: PropsLayer.Geo, s: Vector2, sides: int) -> void:
	var n := maxi(sides / 2, 6)
	var col := BRONZE * 0.6
	var top := ArenaLayout.STAND_H
	g.prism(s.x, 0.0, s.y, 0.24, 0.05, n, col)
	g.prism(s.x, 0.05, s.y, 0.12, 0.08, n, col, 0.4)
	g.prism(s.x, 0.12, s.y, 0.03, top - 0.12, 6, col)
	g.prism(s.x, top - 0.02, s.y, 0.11, 0.04, n, col * 1.2)
	g.prism(s.x, top + 0.02, s.y, 0.038, ArenaLayout.STAND_FLAME_Y - top - 0.02, 6, HallBuilder.WAX)
	g.prism(s.x, ArenaLayout.STAND_FLAME_Y, s.y, 0.004, 0.012, 3, HallBuilder.IRON, 1.0, 0.0, false)


## เสาสวิตช์บอท: ฐาน เสาเหล็ก ปลอกลายเตือน แขนถือแผ่นเป้า (แผ่นเป้ากับโคมเป็นชิ้นแยก)
static func _switch_post(g: PropsLayer.Geo, sides: int) -> void:
	var s: Dictionary = ArenaLayout.STATIONS["switch"]
	var c: Vector2 = s["c"]
	var h := float(s["height"])
	var n := maxi(sides, 8)
	g.prism(c.x, 0.0, c.y, float(s["r"]), 0.12, n, STEEL * 0.7)
	g.prism(c.x, 0.12, c.y, 0.12, h - 0.12, n, STEEL * 0.95, 1.0, 0.0, false)
	for i in 4:
		g.prism(c.x, 0.5 + i * 0.12, c.y, 0.14, 0.06, n, HAZARD if i % 2 == 0 else HAZARD_DARK, 1.0, 0.0, false)
	g.prism(c.x, h - 0.06, c.y, 0.2, 0.06, n, BRONZE * 0.8)
	var plate: Vector3 = s["plate"]
	# ปลอกหลังแผ่นเป้า (แผ่นหันไป -x เข้าหาห้อง)
	g.box(Vector3(plate.x + 0.06, plate.y, plate.z), Vector3(0.05, 0.5, 0.5), STEEL_DARK * 0.9, 0.0, true)


## แท่นรีเซ็ต: แท่นทองเหลืองแปดเหลี่ยม ฝาบรอนซ์ ปุ่มเห็ดเหลือง
static func _reset_pedestal(g: PropsLayer.Geo, sides: int) -> void:
	var s: Dictionary = ArenaLayout.STATIONS["reset"]
	var c: Vector2 = s["c"]
	var h := float(s["height"])
	var r := 0.35
	g.prism(c.x, 0.0, c.y, r * 1.02, 0.12, 8, BRASS * 0.55, 1.0, PI / 8.0)
	g.prism(c.x, 0.12, c.y, r * 0.8, h - 0.22, 8, BRASS * 0.75, 0.86, PI / 8.0, false)
	g.prism(c.x, h - 0.1, c.y, r * 0.95, 0.1, 8, BRONZE * 0.9, 1.0, PI / 8.0)
	var b: Vector3 = s["button"]
	var n := maxi(sides, 8)
	g.prism(c.x, h, c.y, 0.16, b.y - h - 0.03, n, HAZARD_DARK)
	g.prism(c.x, b.y - 0.03, c.y, 0.2, 0.03, n, HAZARD, 0.7)


## ธงผ้าลายเทียนของเรา (แบบธงบนดาดฟ้า): จุดกลางบนผิวผนัง p, ทิศเข้าห้อง n2
static func _banner(g: PropsLayer.Geo, p: Vector3, n2: Vector2, col: Color) -> void:
	var n := Vector3(n2.x, 0.0, n2.y)
	var yaw := atan2(n2.x, n2.y)
	var u := Vector3(cos(yaw), 0.0, -sin(yaw))
	var hw := 0.65
	var topc := p + Vector3(0, 1.2, 0)
	var o := n * 0.05
	g.box(topc + n * 0.07 + Vector3(0, 0.05, 0), Vector3(hw + 0.15, 0.025, 0.025), BRONZE * 0.6, yaw)
	var pts := [topc + o - u * hw, topc + o + u * hw, topc + o + u * hw - Vector3(0, 2.0, 0), topc + o - Vector3(0, 2.4, 0), topc + o - u * hw - Vector3(0, 2.0, 0)]
	g.poly(pts, HallBuilder.GOLD * 0.8, n)
	var t := 0.06
	var o2 := n * 0.055
	g.poly([topc + o2 - u * (hw - t) - Vector3(0, t, 0), topc + o2 + u * (hw - t) - Vector3(0, t, 0),
		topc + o2 + u * (hw - t) - Vector3(0, 2.0 - t * 0.3, 0), topc + o2 - Vector3(0, 2.4 - t * 1.5, 0),
		topc + o2 - u * (hw - t) - Vector3(0, 2.0 - t * 0.3, 0)], col, n)
	HallBuilder.emblem(g, topc + n * 0.06 - Vector3(0, 0.95, 0), u, n, 0.42, HallBuilder.GOLD, HallBuilder.WAX, Color(0.95, 0.55, 0.15), 16)


# ---- ชิ้นแยก ----

## แผ่นเป้าสวิตช์: จานกลมหนา 6 ซม. หันไป -x (ศูนย์กลางที่จุดกำเนิด)
static func plate_mesh(r: float) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	var segs := 16
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	for i in segs:
		var a := TAU * i / segs
		front.append(Vector3(-0.03, sin(a) * r, cos(a) * r))
		back.append(Vector3(0.03, sin(a) * r, cos(a) * r))
	g.poly(front, Color.WHITE, Vector3.LEFT)
	for i in segs:
		var k := (i + 1) % segs
		g.poly([front[i], front[k], back[k], back[i]], Color(0.7, 0.7, 0.7), (front[i] + front[k]) * 0.5)
	# วงกลางเข้ม (เป้า)
	var ring: Array[Vector3] = []
	for i in segs:
		var a := TAU * i / segs
		ring.append(Vector3(-0.034, sin(a) * r * 0.35, cos(a) * r * 0.35))
	g.poly(ring, Color(0.55, 0.55, 0.55), Vector3.LEFT)
	return g.mesh()


## โคมสัญญาณครึ่งทรงกลมเหนือเสาสวิตช์ (ศูนย์กลางฐานที่จุดกำเนิด) สีจุดยอดขาว · UV.x = มุมรอบแกน (shader หมุนแถบแสง)
static func beacon_mesh(sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(sides, 8)
	var rings := 4
	var r := 0.16
	for j in rings:
		var t0 := PI * 0.5 * j / rings
		var t1 := PI * 0.5 * (j + 1) / rings
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var q := [_dome(a0, t0, r), _dome(a1, t0, r), _dome(a1, t1, r), _dome(a0, t1, r)]
			var uv := [Vector2(float(i) / n, t0), Vector2(float(i + 1) / n, t0), Vector2(float(i + 1) / n, t1), Vector2(float(i) / n, t1)]
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_uv(uv[k])
				st.set_normal((q[k] as Vector3).normalized())
				st.add_vertex(q[k])
	return st.commit()


static func _dome(a: float, t: float, r: float) -> Vector3:
	return Vector3(cos(a) * cos(t) * r, sin(t) * r, -sin(a) * cos(t) * r)
