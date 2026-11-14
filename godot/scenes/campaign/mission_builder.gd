class_name MissionBuilder
extends RefCounted
## เมชนิ่งของสนามรบ (CAMPAIGN_SPEC §5.4, track C): พื้น + ของตกแต่ง เป็นเมชหนึ่ง, หน้าผา + ของบัง + รั้วค่าย + ฐาน เป็นอีกเมชหนึ่ง
## = 2 draw call ทุกระดับ · สีจุดยอดกับวัสดุเดียวของ HallBuilder (ไม่รับแสง) แสงอบลงสีตามทิศหน้า (แดดจากบนเฉียง) ไม่มีงานต่อเฟรม
## สีและรูปทรงตามชีวนิเวศ (ซากเมือง ป่าดงดิบ ทะเลทราย ทุ่งน้ำแข็ง ภูเขาไฟ หนองพิษ) · จำนวนเหลี่ยมตามระดับ (hi 10 … min 5)
## สุ่มลายพื้นด้วย seed ของภารกิจ (ภาพล้วน ไม่มีผลกับกติกา) · เสาพิธีกับกรงตัวประกันเป็นเมชแยก (พังได้/เปิดได้)

const SIDES := {"hi": 10, "mid": 8, "lo": 6, "min": 5}
const SUN := Vector3(0.35, 0.85, 0.4)
const GROUND_N := 12
## [พื้น, พื้นลาย, หน้าผา, หิน, ของสร้าง, ไม้/ลำต้น, ใบไม้/ผลึก, เรืองแสง, ท้องฟ้า]
const PALETTES := {
	"ruin": ["4a4944", "5a5852", "3a3935", "6c6a63", "807a6e", "5e4b34", "8a857a", "ffb35c", "1a2230"],
	"forest": ["2e4626", "3b5a2c", "3c3a2b", "5b5c52", "4f5a3a", "4a3523", "2f6e2b", "c8f06a", "1d3328"],
	"desert": ["a9864f", "bb9862", "8c683c", "9a7246", "8a6d4a", "6b5a3e", "c4a06a", "ffcf6a", "8f7556"],
	"ice": ["c3d0da", "d6e1e8", "8ea4b6", "71818e", "9aaab6", "5d6c78", "9fd8f2", "c8f4ff", "7f95a8"],
	"volcanic": ["2a2421", "352d29", "1f1a18", "3d3430", "4a3d36", "2b2421", "4a3a33", "ff6a1a", "33160f"],
	"toxic": ["394628", "475a2e", "3a4232", "585d4e", "5a6452", "6b5a3e", "8fc23a", "b8ff4a", "26331b"],
}
const STAKE := Color("3a2a1c")
const STAKE_TIP := Color("c9b48a")
const STEEL := Color("4a4f55")
const STEEL_DARK := Color("2b2f35")
const TEAM := Color(0.28, 0.52, 0.84)
const CULT := Color("6b1414")
const CULT_GLOW := Color("ff3b2a")
const PAD := Color("2f3238")
const HAZARD := Color("d9a521")


static func palette(biome: String) -> Array[Color]:
	var out: Array[Color] = []
	for h: String in PALETTES.get(biome, PALETTES["ruin"]):
		out.append(Color(h))
	return out


static func sky(biome: String) -> Color:
	return palette(biome)[8]


## [พื้น, ของในสนาม] ของผังนี้ที่ระดับนี้ (seed = spec.seed ใช้ลายพื้น)
static func meshes(layout: Dictionary, level: String, seed_v: int) -> Array[ArrayMesh]:
	var sides := int(SIDES.get(level, 8))
	var pal := palette(str(layout.get("biome", "ruin")))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ 0x6D3E
	var g := PropsLayer.Geo.new()
	_ground(g, layout, pal, rng)
	_decor(g, layout, pal, sides)
	_shade(g)
	var p := PropsLayer.Geo.new()
	_cliffs(p, pal, rng)
	for b: Dictionary in layout["blockers"]:
		_piece(p, b, pal, sides, str(layout.get("biome", "ruin")))
	_landmarks(p, layout, pal, sides)
	_shade(p)
	return [g.mesh(), p.mesh()]


## เสาพิธีกรรม (ทำลายได้): เสาหินดำทรงสอบ ร่องอักษรแดงเรือง ฐานวงหิน · origin ที่พื้น
static func pylon_mesh(sides: int) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	g.prism(0.0, 0.0, 0.0, 0.85, 0.35, sides, Color("2a2224"), 0.9)
	g.prism(0.0, 0.35, 0.0, 0.45, 2.6, 4, Color("1e1a1d"), 0.55, PI * 0.25)
	g.prism(0.0, 2.95, 0.0, 0.25, 0.5, 4, Color("1e1a1d"), 0.0, PI * 0.25)
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var n := Vector3(cos(a), 0.0, -sin(a))
		for j in 3:
			var y := 0.7 + j * 0.7
			var c := n * (0.43 - j * 0.07) + Vector3(0.0, y, 0.0)
			g.box(c, Vector3(0.05, 0.14, 0.05), CULT_GLOW, a)
	_shade(g, false)
	return g.mesh()


## ซากเสาที่พังแล้ว: ฐานกับเศษหิน
static func rubble_mesh(sides: int) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	g.prism(0.0, 0.0, 0.0, 0.85, 0.35, sides, Color("2a2224"), 0.9)
	g.prism(0.0, 0.35, 0.0, 0.42, 0.5, 4, Color("1e1a1d"), 0.8, 0.4)
	for k in 5:
		var a := k * TAU / 5.0 + 0.3
		g.box(Vector3(cos(a) * 1.1, 0.12, sin(a) * 1.1), Vector3(0.18, 0.12, 0.14), Color("2b2427"), a)
	_shade(g, false)
	return g.mesh()


## กรงตัวประกัน: ฐาน ลูกกรง 8 ต้น หลังคา (ซ่อนเมื่อปล่อยแล้ว)
static func cage_mesh(sides: int) -> ArrayMesh:
	var g := PropsLayer.Geo.new()
	g.prism(0.0, 0.0, 0.0, 0.95, 0.12, sides, STEEL_DARK, 1.0)
	for k in 8:
		var a := k * TAU / 8.0
		g.prism(cos(a) * 0.85, 0.12, -sin(a) * 0.85, 0.045, 2.1, 4, STEEL, 1.0)
	g.prism(0.0, 2.2, 0.0, 0.95, 0.12, sides, STEEL_DARK, 0.8)
	_shade(g, false)
	return g.mesh()


static func tris(m: ArrayMesh) -> int:
	return HallBuilder.tris(m)


# ---- ภายใน ----

static func _ground(g: PropsLayer.Geo, layout: Dictionary, pal: Array[Color], rng: RandomNumberGenerator) -> void:
	var half: Vector2 = layout.get("half", MissionLayout.HALF)
	var ext := half + Vector2(3.0, 3.0)
	var n := GROUND_N
	var cols: Array[Color] = []
	for j in n + 1:
		for i in n + 1:
			cols.append(pal[0].lerp(pal[1], rng.randf()) * rng.randf_range(0.9, 1.05))
	for j in n:
		for i in n:
			var x0 := -ext.x + i * ext.x * 2.0 / n
			var x1 := -ext.x + (i + 1) * ext.x * 2.0 / n
			var z0 := -ext.y + j * ext.y * 2.0 / n
			var z1 := -ext.y + (j + 1) * ext.y * 2.0 / n
			var c00 := cols[j * (n + 1) + i]
			var c10 := cols[j * (n + 1) + i + 1]
			var c01 := cols[(j + 1) * (n + 1) + i]
			var c11 := cols[(j + 1) * (n + 1) + i + 1]
			_quad(g, Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0), Vector3(x1, 0.0, z1), Vector3(x0, 0.0, z1), [c00, c10, c11, c01])


## สี่เหลี่ยมหน้าขึ้นที่สีต่างกันต่อมุม (Geo.poly ใช้สีเดียว)
static func _quad(g: PropsLayer.Geo, a: Vector3, b: Vector3, c: Vector3, d: Vector3, cs: Array) -> void:
	for tri: Array in [[0, 2, 1], [0, 3, 2]]:
		var pts := [a, b, c, d]
		for k: int in tri:
			g.v.append(pts[k])
			g.n.append(Vector3.UP)
			var col: Color = cs[k]
			col.a = 1.0
			g.c.append(col)


static func _decor(g: PropsLayer.Geo, layout: Dictionary, pal: Array[Color], sides: int) -> void:
	var biome := str(layout.get("biome", "ruin"))
	for d: Dictionary in layout.get("decor", []):
		var p: Vector3 = d["pos"]
		var s := float(d["s"])
		match int(d["kind"]):
			0:
				g.prism(p.x, 0.0, p.z, 0.25 * s, 0.22 * s, maxi(sides - 3, 4), pal[3] * 0.9, 0.5, float(d["yaw"]))
			1:
				var col := pal[6] if biome in ["forest", "ice", "toxic"] else pal[3] * 1.1
				g.prism(p.x, 0.0, p.z, 0.12 * s, 0.6 * s, 3, col, 0.0, float(d["yaw"]))
			2:
				var pc := pal[1] * 0.8
				if biome == "volcanic":
					pc = pal[7]
				elif biome == "toxic":
					pc = pal[6] * 0.85
				elif biome == "ice":
					pc = pal[6] * 1.05
				_disc_at(g, p + Vector3(0.0, 0.015, 0.0), 0.7 * s, maxi(sides, 6), pc)


static func _disc_at(g: PropsLayer.Geo, c: Vector3, r: float, sides: int, col: Color) -> void:
	var pts: Array[Vector3] = []
	for i in sides:
		var a := i * TAU / sides
		pts.append(c + Vector3(cos(a) * r, 0.0, -sin(a) * r))
	g.poly(pts, col, Vector3.UP)


## หน้าผาเป็นแท่งสูงต่ำสลับ ยื่นเข้ามาที่ขอบ (อยู่หลังตัวชนหน้าผา)
static func _cliffs(g: PropsLayer.Geo, pal: Array[Color], rng: RandomNumberGenerator) -> void:
	var h := MissionLayout.HALF
	for side in 4:
		var along := h.x if side < 2 else h.y
		var x := -along - 2.0
		while x < along + 2.0:
			var w := rng.randf_range(2.5, 4.5)
			var ht := rng.randf_range(4.5, 8.5)
			var depth := rng.randf_range(1.6, 2.6)
			var col := pal[2] * rng.randf_range(0.85, 1.1)
			var cx := x + w * 0.5
			var c := Vector3.ZERO
			var hh := Vector3.ZERO
			match side:
				0:
					c = Vector3(cx, ht * 0.5, -h.y - depth * 0.5 + 0.2)
					hh = Vector3(w * 0.5, ht * 0.5, depth * 0.5)
				1:
					c = Vector3(cx, ht * 0.5, h.y + depth * 0.5 - 0.2)
					hh = Vector3(w * 0.5, ht * 0.5, depth * 0.5)
				2:
					c = Vector3(-h.x - depth * 0.5 + 0.2, ht * 0.5, cx)
					hh = Vector3(depth * 0.5, ht * 0.5, w * 0.5)
				3:
					c = Vector3(h.x + depth * 0.5 - 0.2, ht * 0.5, cx)
					hh = Vector3(depth * 0.5, ht * 0.5, w * 0.5)
			g.box(c, hh, col)
			x += w * 0.85


static func _piece(g: PropsLayer.Geo, b: Dictionary, pal: Array[Color], sides: int, biome: String) -> void:
	var tag := str(b.get("tag", ""))
	if tag.begins_with("cliff"):
		return
	var kind := tag.get_slice("_", 0)
	if tag.begins_with("wall_low"):
		kind = "wall_low"
	elif tag.begins_with("wall_high"):
		kind = "wall_high"
	if str(b["kind"]) == "box":
		var c: Vector3 = b["c"]
		var hh: Vector3 = b["h"]
		match kind:
			"crate":
				var col := pal[5] if biome != "toxic" else pal[4]
				g.box(c, hh, col)
				g.box(c + Vector3(0.0, hh.y * 0.2, 0.0), Vector3(hh.x + 0.02, 0.05, hh.z + 0.02), col * 0.7)
			"wall_high":
				g.box(c, hh, pal[4])
				# ขอบบนแตก (ซากเมือง)
				var long_x := hh.x > hh.z
				var cap := Vector3(hh.x * 0.3 if long_x else hh.x, 0.25, hh.z if long_x else hh.z * 0.3)
				g.box(c + Vector3(hh.x * 0.5 if long_x else 0.0, hh.y + 0.25, 0.0 if long_x else hh.z * 0.5), cap, pal[4] * 0.92)
			_:
				var col := pal[4] if biome in ["ruin", "toxic"] else pal[3]
				if biome == "forest":
					col = pal[5]
				g.box(c, hh, col)
				g.box(c + Vector3(0.0, hh.y, 0.0), Vector3(hh.x + 0.04, 0.05, hh.z + 0.04), col * 1.12)
		return
	var c2: Vector2 = b["c"]
	var r := float(b["r"])
	var top := float(b["y1"])
	match kind:
		"tree":
			g.prism(c2.x, 0.0, c2.y, r, top * 0.55, maxi(sides - 2, 4), pal[5], 0.7)
			g.prism(c2.x, top * 0.35, c2.y, r * 5.0, top * 0.4, sides, pal[6], 0.35)
			g.prism(c2.x, top * 0.6, c2.y, r * 3.6, top * 0.42, sides, pal[6] * 1.12, 0.0)
		"spire":
			var col := pal[6] if biome in ["ice"] else pal[4]
			g.prism(c2.x, 0.0, c2.y, r, top, maxi(sides - 2, 4), col, 0.25, r)
			if biome == "volcanic":
				g.prism(c2.x, top * 0.8, c2.y, r * 0.3, top * 0.2, 4, pal[7], 0.2)
		"barrel":
			g.prism(c2.x, 0.0, c2.y, r, top, sides, pal[7] * 0.75, 1.0)
			g.prism(c2.x, top * 0.45, c2.y, r + 0.02, 0.1, sides, Color(0.12, 0.12, 0.1), 1.0)
		"stake":
			for k in 3:
				var a := k * TAU / 3.0
				var o := Vector2(cos(a), sin(a)) * r * 0.45
				g.prism(c2.x + o.x, 0.0, c2.y + o.y, 0.16, top * 0.82, 5, STAKE, 0.9)
				g.prism(c2.x + o.x, top * 0.82, c2.y + o.y, 0.15, top * 0.18, 5, STAKE_TIP, 0.0)
		"base":
			# เครื่องกำเนิดของฐาน: แท่นเหล็ก ทรงกระบอก แถบสีทีม โดมบน
			g.prism(c2.x, 0.0, c2.y, r + 0.5, 0.3, sides, STEEL_DARK, 0.95)
			g.prism(c2.x, 0.3, c2.y, r, 1.6, sides, STEEL, 1.0)
			g.prism(c2.x, 1.2, c2.y, r + 0.03, 0.18, sides, TEAM, 1.0)
			g.prism(c2.x, 1.9, c2.y, r, 0.7, sides, STEEL_DARK, 0.3)
		"boulder":
			g.prism(c2.x, 0.0, c2.y, r, top * 0.75, sides, pal[3], 0.75, r)
			g.prism(c2.x, top * 0.75, c2.y, r * 0.75, top * 0.25, sides, pal[3] * 1.08, 0.45, r)
		_:
			g.prism(c2.x, 0.0, c2.y, r, top, maxi(sides - 1, 4), pal[3] * 0.95, 0.6, r * 2.0)


## จุดสำคัญที่ไม่มีตัวชน: ลานจุดรับ เสาสัญญาณ วงพิธีกลางค่าย
static func _landmarks(g: PropsLayer.Geo, layout: Dictionary, _pal: Array[Color], sides: int) -> void:
	var pts: Dictionary = layout["points"]
	var pk: Vector3 = pts["pickup"]
	var t := str(layout.get("type", ""))
	_disc_at(g, pk + Vector3(0.0, 0.02, 0.0), MissionTypes.PICKUP_R + 0.4, sides + 4, PAD)
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		g.box(pk + Vector3(cos(a), 0.0, sin(a)) * (MissionTypes.PICKUP_R + 0.2) + Vector3(0.0, 0.05, 0.0), Vector3(0.3, 0.05, 0.3), HAZARD)
	var bc: Vector3 = pts["beacon"]
	g.prism(bc.x, 0.0, bc.z, 0.12, 2.8, 4, STEEL, 1.0)
	g.prism(bc.x, 2.8, bc.z, 0.22, 0.3, 6, HAZARD, 0.6)
	if t == "destroy_camp":
		var cp: Vector3 = pts["camp"]
		_disc_at(g, cp + Vector3(0.0, 0.025, 0.0), 2.4, sides + 4, CULT * 0.8)
		_disc_at(g, cp + Vector3(0.0, 0.03, 0.0), 1.6, sides + 4, Color("1a1012"))
		g.prism(cp.x, 0.0, cp.z, 0.5, 0.9, 4, Color("2a2224"), 0.8, PI * 0.25)


## แสงอบ: หน้าที่หันหาแดดสว่าง ใกล้พื้นมืดลงเล็กน้อย (ไม่มีไฟจริง) · ground = false ไม่มืดที่ฐาน (เมชลอยเหนือพื้น)
static func _shade(g: PropsLayer.Geo, ao := true) -> void:
	var sun := SUN.normalized()
	for i in g.v.size():
		var k := 0.58 + 0.42 * clampf(g.n[i].dot(sun), 0.0, 1.0)
		if ao and g.v[i].y < 0.45 and g.n[i].y < 0.9:
			k *= 0.8 + 0.2 * (g.v[i].y / 0.45)
		var c := g.c[i]
		g.c[i] = Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0), 1.0)
