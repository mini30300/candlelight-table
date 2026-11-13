class_name HallSpace
extends RefCounted
## อวกาศนอกหน้าต่างดาดฟ้ายานรบ (SHIP_LOBBY_SPEC §4): สร้างเมชล้วน ไม่มีโหนด ไม่มีข้อความบนจอ
## ครึ่งทรงกลมด้านใน (เนบิวลา) + ดาว + ดาวเคราะห์ + ดวงจันทร์ = เมชนิ่งชิ้นเดียวต่อระดับ ไม่อบแสงเทียน ไม่มี TIME
## ทุกอย่างอยู่หลังผนังหลัง (z < -8.5) เห็นผ่านหน้าต่างเท่านั้น ไม่โดนกล้องหรือฟิสิกส์
## ยานไกล ๆ เป็นรูปทรงของเราเอง: hi/mid ลอยด้วย shader, lo จอดนิ่ง, min ไม่มี

const DOME_C := Vector3(0.0, 4.0, -8.5)
const DOME_R := 42.0
const WALL_Z := -8.5                    # ผิวหลังของผนังหลัง: ทุกจุดของอวกาศอยู่หลังระนาบนี้
const STAR_R := 41.0
const PLANET_C := Vector3(-10.0, -5.0, -32.0)
const PLANET_R := 11.0
const MOON_C := Vector3(14.0, 9.0, -34.0)
const MOON_R := 2.0
const SUN := Vector3(0.8571, 0.5143, 0.2571)  # (1, 0.6, 0.3) ทำให้ยาว 1
const STAR_SEED := 4401
## ต่อระดับกราฟิก (§6): จำนวนดาว ขนาดดาว (ม.) ช่องรอบ × ช่องตั้งของโดม ดาวเคราะห์ จำนวนยาน
const STARS := {"hi": 700, "mid": 500, "lo": 320, "min": 180}
const STAR_SIZE := {"hi": Vector2(0.10, 0.22), "mid": Vector2(0.10, 0.22), "lo": Vector2(0.14, 0.28), "min": Vector2(0.18, 0.34)}
const DOME_SEGS := {"hi": Vector2i(24, 12), "mid": Vector2i(20, 10), "lo": Vector2i(16, 8), "min": Vector2i(12, 6)}
const PLANET_SEGS := {"hi": Vector2i(16, 10), "mid": Vector2i(16, 10), "lo": Vector2i(10, 6), "min": Vector2i(10, 6)}
const SHIPS := {"hi": 5, "mid": 3, "lo": 3, "min": 0}

const SPACE := Color("03040a")
const NEBULA_A := Color("2c1745")
const NEBULA_B := Color("0c3340")
const STAR_COLS := [Color("f2f4ff"), Color("b8ccff"), Color("ffd9a0")]
const PLANET_OCEAN := Color("1d4b5c")
const PLANET_LAND := Color("9a6a3a")
const PLANET_CLOUD := Color("d8d2c4")
const PLANET_NIGHT := Color("070a10")
const PLANET_AIR := Color("8fc4ff")
const MOON := Color(0.62, 0.60, 0.58)
const MOON_NIGHT := Color(0.10, 0.11, 0.14)   # ด้านมืดของดวงจันทร์ฟ้าเทาจาง ๆ ไม่ใช่ก้อนดำบนเนบิวลา
const HULL := Color("1a1c22")
const HULL_TOP := Color("3a3f4a")
const HULL_LIT := Color("ffbf66")
const ENGINE := Color("7fb8ff")
## เนบิวลา: ทิศ (จากกลางโดม), สี, ความกว้าง (cos ของมุม), แรง
const BLOBS := [
	{"d": Vector3(0.55, 0.35, -0.76), "col": NEBULA_A, "w": 0.55, "k": 1.0},
	{"d": Vector3(-0.35, 0.55, -0.76), "col": NEBULA_B, "w": 0.6, "k": 0.9},
	{"d": Vector3(0.1, -0.2, -0.97), "col": NEBULA_A, "w": 0.75, "k": 0.45},
]
const BAND_N := Vector3(0.28, 0.93, 0.24)    # ตั้งฉากกับแถบทางช้างเผือก (ทิศสุ่มแบบคงที่ของเรา)
const BAND_COL := Color(0.10, 0.10, 0.14)
## ยานไกล: จุดเริ่ม (x, y, z), ทิศ (+1 = +x), ยาว (ม.), ความเร็ว (ม./วิ), ยานคุ้มกันใช้ช่วงลอยของยานแม่ (lead)
const SHIP_LIST := [
	{"p": Vector3(-20.0, 8.0, -34.0), "dir": 1.0, "len": 7.0, "speed": 0.35, "lead": -1},
	{"p": Vector3(14.0, 3.0, -20.0), "dir": -1.0, "len": 4.0, "speed": 0.2, "lead": -1},
	{"p": Vector3(0.0, 12.0, -38.0), "dir": 1.0, "len": 9.0, "speed": 0.12, "lead": -1},
	{"p": Vector3(-17.0, 9.6, -32.5), "dir": 1.0, "len": 2.2, "speed": 0.35, "lead": 0},
	{"p": Vector3(-23.0, 6.6, -35.5), "dir": 1.0, "len": 2.0, "speed": 0.35, "lead": 0},
]

static var _cache: Dictionary = {}       # level → ArrayMesh
static var _ship_mesh: ArrayMesh


## เมชนิ่งของอวกาศตามระดับ (สร้างครั้งเดียวต่อการเปิดแอป)
static func mesh(level: String) -> ArrayMesh:
	if not STARS.has(level):
		level = "mid"
	if _cache.has(level):
		return _cache[level]
	var g := PropsLayer.Geo.new()
	_dome(g, DOME_SEGS[level])
	_stars(g, int(STARS[level]), STAR_SIZE[level])
	_sphere(g, PLANET_C, PLANET_R, PLANET_SEGS[level], true)
	# ดวงจันทร์ใช้จำนวนช่องเท่าดาวเคราะห์ เส้นแบ่งกลางวัน-กลางคืนไม่หยัก
	_sphere(g, MOON_C, MOON_R, PLANET_SEGS[level], false)
	var m := g.mesh()
	_cache[level] = m
	return m


## สีท้องฟ้าในทิศ d (ยาว 1): ดำอมน้ำเงิน + เนบิวลานุ่ม ๆ + แถบจาง ๆ
static func sky_colour(d: Vector3) -> Color:
	var c := SPACE
	for b in BLOBS:
		var bd: Vector3 = (b["d"] as Vector3).normalized()
		var t := clampf((d.dot(bd) - float(b["w"])) / (1.0 - float(b["w"])), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t) * float(b["k"])
		c = c + (b["col"] as Color) * t
	var band := d.dot(BAND_N.normalized())
	c = c + BAND_COL * exp(-band * band / 0.02)
	c.a = 1.0
	return c


static func _dome(g: PropsLayer.Geo, segs: Vector2i) -> void:
	# มุมจากแกน -z: 0 (กลาง) ถึงเกือบ 90° (ขอบอยู่หลังระนาบผนัง 2 ซม.)
	var tmax := acos(0.02 / DOME_R)
	var rings: Array[PackedVector3Array] = []
	for j in segs.y + 1:
		var th := tmax * j / segs.y
		var ring := PackedVector3Array()
		for i in segs.x:
			var ph := TAU * i / segs.x
			ring.append(Vector3(sin(th) * cos(ph), sin(th) * sin(ph), -cos(th)))
		rings.append(ring)
	var start := g.v.size()
	for j in segs.y:
		for i in segs.x:
			var k := (i + 1) % segs.x
			var a := DOME_C + rings[j][i] * DOME_R
			var b := DOME_C + rings[j][k] * DOME_R
			var c := DOME_C + rings[j + 1][k] * DOME_R
			var d := DOME_C + rings[j + 1][i] * DOME_R
			var inward := -(rings[j][i] + rings[j + 1][k])
			if j == 0:
				g.poly([a, c, d], SPACE, inward)
			else:
				g.poly([a, b, c, d], SPACE, inward)
	_recolour(g, start, func(p: Vector3) -> Color: return sky_colour((p - DOME_C).normalized()))


static func _stars(g: PropsLayer.Geo, n: int, size: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	var made := 0
	var tries := 0
	while made < n and tries < n * 40:
		tries += 1
		var d := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 0.0))
		var l := d.length()
		if l < 0.2 or l > 1.0:
			continue
		d /= l
		var c := DOME_C + d * STAR_R
		if c.z > WALL_Z - 0.5:
			continue
		# แถบทางช้างเผือกหนาแน่นเป็นสองเท่า
		var band := d.dot(BAND_N.normalized())
		if rng.randf() > 0.5 + 0.5 * exp(-band * band / 0.02):
			continue
		if star_hidden(c):
			continue
		var s := rng.randf_range(size.x, size.y)
		var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2 := d.cross(t1).normalized()
		var col: Color = STAR_COLS[rng.randi() % STAR_COLS.size()] * rng.randf_range(0.6, 1.0)
		g.poly([c + t1 * s, c + t2 * s, c - t1 * s, c - t2 * s], col, -d)
		made += 1


## ดาวที่ c ถูกดาวเคราะห์หรือดวงจันทร์บัง (มองจากกลางโดม): ไม่วางดาวในวงของมัน
static func star_hidden(c: Vector3) -> bool:
	for body in [[PLANET_C, PLANET_R + 0.8], [MOON_C, MOON_R + 0.5]]:
		var q: Vector3 = body[0]
		var r: float = body[1]
		var d := (c - DOME_C).normalized()
		var t := (q - DOME_C).dot(d)
		if t > 0.0 and (DOME_C + d * t).distance_to(q) < r:
			return true
	return false


## ทรงกลม (ดาวเคราะห์ / ดวงจันทร์) อบแสงจากดวงอาทิตย์ทิศ SUN ลงสีจุดยอด
static func _sphere(g: PropsLayer.Geo, c: Vector3, r: float, segs: Vector2i, planet: bool) -> void:
	var start := g.v.size()
	for j in segs.y:
		var a0 := PI * j / segs.y
		var a1 := PI * (j + 1) / segs.y
		for i in segs.x:
			var b0 := TAU * i / segs.x
			var b1 := TAU * (i + 1) / segs.x
			var p00 := _sph(a0, b0)
			var p01 := _sph(a0, b1)
			var p11 := _sph(a1, b1)
			var p10 := _sph(a1, b0)
			var out := (p00 + p11).normalized()
			if j == 0:
				g.poly([c + p00 * r, c + p11 * r, c + p10 * r], MOON, out)
			elif j == segs.y - 1:
				g.poly([c + p00 * r, c + p01 * r, c + p11 * r], MOON, out)
			else:
				g.poly([c + p00 * r, c + p01 * r, c + p11 * r, c + p10 * r], MOON, out)
	var view := (c - Vector3(0.0, 2.5, 6.0)).normalized()
	_recolour(g, start, func(p: Vector3) -> Color: return _body_colour((p - c) / r, view, planet))


static func _sph(a: float, b: float) -> Vector3:
	return Vector3(sin(a) * cos(b), cos(a), sin(a) * sin(b))


## สีผิวที่ทิศ n: แถบทะเล/แผ่นดิน/เมฆตามละติจูด ด้านกลางคืนมืด ขอบด้านสว่างมีแถบอากาศสีฟ้า
static func _body_colour(n: Vector3, view: Vector3, planet: bool) -> Color:
	var lit := n.dot(SUN)
	var day := clampf((lit + 0.15) / 0.55, 0.0, 1.0)
	day = day * day * (3.0 - 2.0 * day)
	var base := MOON
	if planet:
		var lat := n.y
		var wave := sin(lat * 9.0 + sin(atan2(n.z, n.x) * 3.0) * 0.8)
		base = PLANET_OCEAN
		if wave > 0.35:
			base = PLANET_OCEAN.lerp(PLANET_LAND, clampf((wave - 0.35) * 2.5, 0.0, 1.0))
		var cloud := sin(lat * 23.0 + atan2(n.z, n.x) * 2.0)
		if cloud > 0.75:
			base = base.lerp(PLANET_CLOUD, (cloud - 0.75) * 3.0)
		var night := PLANET_NIGHT
		var col := night.lerp(base * (0.75 + 0.5 * maxf(lit, 0.0)), day)
		var rim := 1.0 - absf(n.dot(-view))
		col = col + PLANET_AIR * pow(rim, 3.0) * clampf(lit + 0.2, 0.0, 1.0) * 0.9
		col.a = 1.0
		return col
	var mc := MOON_NIGHT.lerp(base * (0.6 + 0.6 * maxf(lit, 0.0)), day)
	mc.a = 1.0
	return mc


## ตั้งสีจุดยอดใหม่ตั้งแต่ start ตามตำแหน่ง (ไล่สีนุ่มต่อจุดยอด ไม่ใช่สีเดียวต่อหน้า)
static func _recolour(g: PropsLayer.Geo, start: int, f: Callable) -> void:
	var cols := g.c
	for i in range(start, g.v.size()):
		cols[i] = f.call(g.v[i])
	g.c = cols


# ---- ยานไกล ----

## เมชยานหนึ่งลำ ยาว 1 ตามแกน +x (หัวแหลมที่ +0.5) ~40 สามเหลี่ยม: ลำเรือรูปลิ่ม หอท้าย หน้าต่างอำพัน แผ่นไอพ่น
static func ship_mesh() -> ArrayMesh:
	if _ship_mesh != null:
		return _ship_mesh
	var g := PropsLayer.Geo.new()
	var s0 := [Vector3(-0.5, 0.05, 0.0), Vector3(-0.5, 0.0, 0.08), Vector3(-0.5, -0.05, 0.0), Vector3(-0.5, 0.0, -0.08)]
	var s1 := [Vector3(0.28, 0.03, 0.0), Vector3(0.28, 0.0, 0.05), Vector3(0.28, -0.03, 0.0), Vector3(0.28, 0.0, -0.05)]
	var tip := Vector3(0.5, 0.0, 0.0)
	for i in 4:
		var k := (i + 1) % 4
		var out: Vector3 = (s0[i] + s0[k]) * 0.5 - Vector3(-0.5, 0.0, 0.0)
		var col := HULL_TOP if out.y > 0.0 else HULL
		g.poly([s0[i], s0[k], s1[k], s1[i]], col, out)
		g.poly([s1[i], s1[k], tip], col * 0.9, out + Vector3(0.3, 0.0, 0.0))
	g.poly(s0, ENGINE, Vector3.LEFT)
	# หอท้ายเป็นขั้น
	g.box(Vector3(-0.35, 0.085, 0.0), Vector3(0.1, 0.04, 0.035), HULL_TOP)
	g.box(Vector3(-0.38, 0.15, 0.0), Vector3(0.05, 0.03, 0.02), HULL_TOP * 0.9)
	# หน้าต่างจุดเล็ก ๆ ด้าน +z (ฝั่งที่หันเข้าห้อง)
	for i in 3:
		var x := -0.42 + i * 0.06
		g.poly([Vector3(x, 0.07, 0.0365), Vector3(x + 0.025, 0.07, 0.0365), Vector3(x + 0.025, 0.095, 0.0365),
			Vector3(x, 0.095, 0.0365)], HULL_LIT, Vector3.BACK)
	_ship_mesh = g.mesh()
	return _ship_mesh


## ช่วงลอยของยาน (ม.) ไม่ให้หลุดโดม: 2 × (ครึ่งคอร์ดของโดมตามแกน x ที่ y, z ของยาน − ความยาว)
static func ship_span(p: Vector3, length: float) -> float:
	var dy := p.y - DOME_C.y
	var dz := p.z - DOME_C.z
	var hc := sqrt(maxf(DOME_R * DOME_R - dy * dy - dz * dz, 0.0))
	return maxf(2.0 * (hc - length), 0.0)


## ยานต่อระดับ: {"centre": กลางช่วงลอย, "dir", "len", "speed", "phase", "span"} (ตำแหน่ง x = centre.x + dir × (s − span/2),
## s = (เวลา × speed + phase) mod span) · ยานคุ้มกันใช้ span ของยานแม่ ลอยไปพร้อมกัน
static func ship_instances(level: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := int(SHIPS.get(level, 0))
	for i in mini(n, SHIP_LIST.size()):
		var s: Dictionary = SHIP_LIST[i]
		var p: Vector3 = s["p"]
		var dir := float(s["dir"])
		var length := float(s["len"])
		var lead := int(s["lead"])
		var centre := Vector3(DOME_C.x, p.y, p.z)
		var span := ship_span(p, length)
		if lead >= 0:
			var ld: Dictionary = SHIP_LIST[lead]
			var lp: Vector3 = ld["p"]
			span = ship_span(lp, float(ld["len"]))
			centre.x = DOME_C.x + (p.x - lp.x)
		var phase := fposmod((p.x - centre.x) * dir + span * 0.5, span) if span > 0.0 else 0.0
		out.append({"centre": centre, "dir": dir, "len": length, "speed": float(s["speed"]), "phase": phase, "span": span})
	return out


## ตำแหน่งกลางลำของยาน d ที่จุด s ของช่วงลอย (0..span)
static func ship_pos(d: Dictionary, s: float) -> Vector3:
	var c: Vector3 = d["centre"]
	return c + Vector3(float(d["dir"]) * (s - float(d["span"]) * 0.5), 0.0, 0.0)


## ทรานส์ฟอร์มของยาน d ที่ตำแหน่ง p (ยาวตาม len หันตาม dir)
static func ship_transform(d: Dictionary, p: Vector3) -> Transform3D:
	var b := Basis.from_scale(Vector3.ONE * float(d["len"]))
	if float(d["dir"]) < 0.0:
		b = Basis(Vector3.UP, PI) * b
	return Transform3D(b, p)
