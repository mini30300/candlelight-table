class_name EggShapes
extends RefCounted
## ตัวไข่แทนฟิกเกอร์ (LOBBY_SPEC §4.1) ระหว่างรอโมเดลจริง: ขนาดจาก data/types.json ผ่าน GameData
## (ไม่อ่าน kits.json ที่สร้างทีหลัง โหมดนี้จึงใช้ได้แม้ไม่มีชุดโมเดลในเครื่อง)
## R = รัศมีฐาน (เมตร = นิ้วเกม) เท่ากับ baseR ของตัวส่งออกชุดโมเดล วงทีมจึงเท่ากับโหมดชุดโมเดล
## เมชเป็นหน่วย R ต่อขนาดหนึ่งชั้น: instance ใช้แค่หัน + ขยายเท่ากันทุกแกน (ขยายไม่เท่ากัน normal ของ shader เพี้ยน)
## ตัวยาว (พาหนะ ตัวขี่) ยืดแกน z ในเมชเอง · ปุ่มสีเข้มด้าน +z บอกทิศหน้า · กว้างสุดไม่เกิน 0.70 R ให้เห็นวงทีม

## โปรไฟล์ไข่จากฐานขึ้นยอด: (y / ความสูง, รัศมี / ความกว้างสุด)
const PROFILE: Array[Vector2] = [Vector2(0.00, 0.55), Vector2(0.06, 0.85), Vector2(0.18, 0.98), Vector2(0.32, 1.00),
	Vector2(0.50, 0.95), Vector2(0.68, 0.80), Vector2(0.84, 0.56), Vector2(0.95, 0.30), Vector2(1.00, 0.00)]
## ชั้นขนาดตามลำดับที่ตรวจ
const CLASSES: PackedStringArray = ["titan", "giant", "vehicle", "infantry", "big", "cavalry", "walker"]
## [ความสูง, รัศมีกว้างสุด, ครึ่งความยาวตาม z] หน่วย R
const SHAPE := {
	"titan": [3.4, 0.70, 0.70], "giant": [2.9, 0.70, 0.70], "vehicle": [1.6, 0.70, 1.0],
	"infantry": [2.82, 0.70, 0.70], "big": [2.75, 0.70, 0.70], "cavalry": [2.0, 0.60, 1.0], "walker": [2.55, 0.70, 0.70],
}
const IVORY := Color(0.86, 0.82, 0.74)
const NUB := Color(0.55, 0.48, 0.40)
## ปุ่มบอกทิศ: สูง 0.6 ของตัว ยื่นออก 0.09 R กว้างครึ่ง 0.14 R สูงครึ่ง 0.18 R
const NUB_Y := 0.6
const NUB_OUT := 0.09
const NUB_HW := 0.14
const NUB_HH := 0.18
## ไม่ซับซ้อน (lo/min): 8 ด้าน × 4 แถบ = 64 สามเหลี่ยม · เต็ม (hi/mid): 10 ด้าน × 8 แถบ = 160 สามเหลี่ยม
## (14 ด้าน × 8 แถบเกิน 160 สามเหลี่ยม จึงใช้โปรไฟล์ครบทุกจุดกับ 10 ด้าน)
const SIMPLE_SIDES := 8
const FULL_SIDES := 10
const SIMPLE_RINGS: PackedInt32Array = [0, 2, 4, 6, 8]
const SIMPLE_MAX_TRIS := 64
const FULL_MAX_TRIS := 160
## รัศมีฐานเมื่อ types.json ไม่ใส่ r (0.8 นิ้ว) และสูตรของตัวส่งออก round(r × 17.27) / 20
const SMALL_R_MI := 800
const SMALL_R := 0.62

static var _cache: Dictionary = {}   # "ชั้น|simple" → ArrayMesh (ใช้ร่วมทุกโต๊ะ)


## รัศมีฐาน R (เมตร) ของชนิด k: 0.62 สำหรับฐานไม่เกิน 0.8 นิ้ว ที่เหลือตามสูตรของตัวส่งออก (ใหญ่สุด 6.9)
static func base_r(k: String) -> float:
	var r := GameData.base_r_mi(k)
	return SMALL_R if r <= SMALL_R_MI else roundf(r * 0.01727) / 20.0


## ชั้นขนาดของชนิด k (ตรวจตามลำดับ): ไททัน อัศวินยักษ์ พาหนะ ทหารเดินเท้า ทหารตัวใหญ่ ตัวขี่/สัตว์เล็ก ที่เหลือ
## ชนิดที่ไม่รู้จักนับเป็นทหารเดินเท้า
static func class_of(k: String) -> String:
	var t := GameData.ty(k)
	if t.is_empty():
		return "infantry"
	var r := GameData.base_r_mi(k)
	if _on(t, "ttn"):
		return "titan"
	if _on(t, "gk"):
		return "giant"
	if _on(t, "veh"):
		return "vehicle"
	if _on(t, "inf"):
		return "infantry" if r <= SMALL_R_MI else "big"
	if r <= 1200 and int(t.get("w", 1)) <= 5:
		return "cavalry"
	return "walker"


## (R, ความสูง, ครึ่งความยาวตาม z) เป็นเมตร
static func size_of(k: String) -> Vector3:
	var r := base_r(k)
	var sh: Array = SHAPE[class_of(k)]
	return Vector3(r, float(sh[0]) * r, float(sh[2]) * r)


## เมชของชั้น cls หน่วย R (เก็บแคช): simple = lo/min
static func mesh(cls: String, simple: bool) -> ArrayMesh:
	if not SHAPE.has(cls):
		cls = "infantry"
	var key := "%s|%s" % [cls, "s" if simple else "f"]
	if _cache.has(key):
		return _cache[key]
	var m := _build(cls, simple)
	_cache[key] = m
	return m


## จำนวนสามเหลี่ยมของเมช (เมชไม่มีดัชนี)
static func tris(m: Mesh) -> int:
	if m == null or m.get_surface_count() < 1:
		return 0
	return (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


static func _on(t: Dictionary, flag: String) -> bool:
	var v: Variant = t.get(flag, 0)
	if typeof(v) == TYPE_BOOL:
		return v
	return typeof(v) == TYPE_INT and int(v) != 0


## รัศมีโปรไฟล์ที่ความสูงสัมพัทธ์ y (เส้นตรงระหว่างจุด)
static func profile_at(y: float) -> float:
	for i in range(1, PROFILE.size()):
		var a: Vector2 = PROFILE[i - 1]
		var b: Vector2 = PROFILE[i]
		if y <= b.x:
			var t := 0.0 if b.x <= a.x else clampf((y - a.x) / (b.x - a.x), 0.0, 1.0)
			return lerpf(a.y, b.y, t)
	return 0.0


## กลึงไข่: วงตามโปรไฟล์ (normal เรียบจากความชันของโปรไฟล์) ยอดเป็นกรวย ฐานปิดด้วยแผ่น ปุ่มบอกทิศสองสามเหลี่ยม
static func _build(cls: String, simple: bool) -> ArrayMesh:
	var sh: Array = SHAPE[cls]
	var h := float(sh[0])
	var wd := float(sh[1])
	var zs := float(sh[2]) / wd      # ยืดแกน z ของตัวยาว
	var sides := SIMPLE_SIDES if simple else FULL_SIDES
	var pts: Array[Vector2] = []     # (y, รัศมี) หน่วย R
	if simple:
		for i in SIMPLE_RINGS:
			pts.append(Vector2(PROFILE[i].x * h, PROFILE[i].y * wd))
	else:
		for p in PROFILE:
			pts.append(Vector2(p.x * h, p.y * wd))
	# normal ในระนาบ (รัศมี, y) ของแต่ละวง: ตั้งฉากกับความชันเฉลี่ยสองข้าง
	var nrm: Array[Vector2] = []
	for j in pts.size():
		var a := pts[maxi(j - 1, 0)]
		var b := pts[mini(j + 1, pts.size() - 1)]
		var dy := b.x - a.x
		var dr := b.y - a.y
		var n := Vector2(dy, -dr)       # (ทางรัศมี, ทางขึ้น)
		if pts[j].y <= 0.0001:
			n = Vector2(0.0, 1.0)
		nrm.append(n.normalized())
	var g := PropsLayer.Geo.new()
	for j in pts.size() - 1:
		var ya := pts[j].x
		var yb := pts[j + 1].x
		var ca := IVORY * (0.9 + 0.1 * ya / h)
		var cb := IVORY * (0.9 + 0.1 * yb / h)
		ca.a = 1.0
		cb.a = 1.0
		for i in sides:
			var a0 := i * TAU / sides
			var a1 := (i + 1) * TAU / sides
			var p00 := _ring_point(pts[j], a0, zs)
			var p01 := _ring_point(pts[j], a1, zs)
			var p10 := _ring_point(pts[j + 1], a0, zs)
			var p11 := _ring_point(pts[j + 1], a1, zs)
			var n00 := _ring_normal(nrm[j], a0, zs)
			var n01 := _ring_normal(nrm[j], a1, zs)
			var n10 := _ring_normal(nrm[j + 1], a0, zs)
			var n11 := _ring_normal(nrm[j + 1], a1, zs)
			if pts[j + 1].y <= 0.0001:
				# ยอด: กรวยสามเหลี่ยมเดียวต่อด้าน
				_tri(g, [p00, p01, p10], [n00, n01, Vector3.UP], [ca, ca, cb])
			else:
				_tri(g, [p00, p01, p11], [n00, n01, n11], [ca, ca, cb])
				_tri(g, [p00, p11, p10], [n00, n11, n10], [ca, cb, cb])
	# ฐาน: แผ่นปิดล่าง
	var base: Array = []
	for i in sides:
		base.append(_ring_point(pts[0], i * TAU / sides, zs))
	g.poly(base, IVORY * 0.6, Vector3.DOWN)
	# ปุ่มบอกทิศด้าน +z
	var yn := NUB_Y * h
	var rn := profile_at(NUB_Y) * wd
	var rt := profile_at((yn + NUB_HH) / h) * wd
	var side_z := sqrt(maxf(rn * rn - NUB_HW * NUB_HW, 0.0)) * zs
	var l := Vector3(-NUB_HW, yn, side_z)
	var r := Vector3(NUB_HW, yn, side_z)
	var t := Vector3(0.0, yn + NUB_HH, rt * zs)
	var tip := Vector3(0.0, yn - NUB_HH * 0.3, rn * zs + NUB_OUT)
	var nub := NUB
	nub.a = 1.0
	g.poly([l, tip, t], nub, Vector3(-0.5, 0.4, 1.0))
	g.poly([t, tip, r], nub, Vector3(0.5, 0.4, 1.0))
	return g.mesh()


static func _ring_point(p: Vector2, a: float, zs: float) -> Vector3:
	return Vector3(cos(a) * p.y, p.x, -sin(a) * p.y * zs)


## normal ของผิวกลึงที่มุม a (แกน z ยืด zs: normal หารด้วย zs แล้วทำให้ยาวหนึ่ง)
static func _ring_normal(n: Vector2, a: float, zs: float) -> Vector3:
	return Vector3(cos(a) * n.x, n.y, -sin(a) * n.x / zs).normalized()


## สามเหลี่ยมพร้อม normal เรียบต่อจุดยอด เรียงตามเข็มเมื่อมองจากด้านนอก (แบบ Geo.poly)
static func _tri(g: PropsLayer.Geo, p: Array, n: Array, c: Array) -> void:
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var d: Vector3 = p[2]
	var out: Vector3 = (n[0] as Vector3) + (n[1] as Vector3) + (n[2] as Vector3)
	var order := [0, 1, 2]
	if (b - a).cross(d - a).dot(out) > 0.0:
		order = [0, 2, 1]
	for k in order:
		g.v.append(p[k])
		g.n.append(n[k])
		g.c.append(c[k])
