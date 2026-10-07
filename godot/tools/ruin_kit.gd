extends RefCounted
## Gothic ruin kit (R1-V5), our own design: every piece is emitted from code as low-poly triangles with vertex
## colours into ONE SurfaceTool, so a whole building commits to one ArrayMesh surface (one draw call). No model
## files, no textures, no emblems or marks of any kind: plain architecture only.
## Units are metres, +Y up, the main face looks +Z (like the figure kits). `xf` places the piece being drawn.
## lod 0 = hi (cut-out windows, fluted pillars, mouldings), lod 1 = lo (solid walls with dark window quads, fewer
## flutes and pieces). Random shapes come from a seed per piece, so hi and lo of one building share their outline.
## Offline tool: tools/ruin_sample.gd builds the sample building with it; nothing here runs per frame.

# จานสี: หินเทาอมเบจผุ เขียวสนิมทองแดง ทองเหลือง สนิมแดง เหล็กเก่า
const STONE := Color8(138, 131, 119)
const STONE_DARK := Color8(108, 102, 94)
const STONE_PALE := Color8(156, 149, 136)
const FLOOR := Color8(104, 98, 90)
const DUST := Color8(124, 116, 103)
const TRIM := Color8(70, 128, 114)
const TRIM_DARK := Color8(52, 98, 87)
const BRASS := Color8(160, 128, 68)
const RUST := Color8(142, 66, 42)
const RUST_DARK := Color8(102, 48, 34)
const IRON := Color8(86, 78, 72)
const RECESS := Color8(96, 92, 88)
const GLASS := Color8(28, 27, 33)
const BRONZE := Color8(90, 142, 126)

var lod := 0
var tris := 0
var xf := Transform3D.IDENTITY
var aabb := AABB()

var _has_box := false
var _st := SurfaceTool.new()
var _rng := RandomNumberGenerator.new()


func _init(level: int = 0) -> void:
	lod = level
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func hi() -> bool:
	return lod == 0


## seed ของชิ้นถัดไป (hi กับ lo ใช้ seed เดียวกันจึงได้รูปเดียวกัน)
func seed_piece(s: int) -> void:
	_rng.seed = s * 7919 + 13


func rf(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


## รวมเป็น ArrayMesh ผิวเดียวพร้อมวัสดุ
func commit(material: Material) -> ArrayMesh:
	_st.index()
	var m := _st.commit()
	if material != null and m.get_surface_count() > 0:
		m.surface_set_material(0, material)
	return m


## วัสดุหินด้านแบบพื้นสนามของแอป (สีต่อจุดยอด sRGB ไม่มีแสงสะท้อนเงา: ไม่ซีดเมื่อมองเฉียง และถูกกว่าบนมือถือ)
static func make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m


# ---- รูปพื้นฐาน ----

## สามเหลี่ยม a b c ทวนเข็มเมื่อมองจากด้านนอก (พิกัดของ xf); Godot นับหน้าตามเข็มนาฬิกาจึงส่ง a c b
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var wa := xf * a
	var wb := xf * b
	var wc := xf * c
	var n := (wb - wa).cross(wc - wa)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	_vert(wa, n, col)
	_vert(wc, n, col)
	_vert(wb, n, col)
	tris += 1


## สามเหลี่ยมที่หันไปทาง n (ท้องถิ่น) ไม่ว่าส่งจุดมาลำดับไหน
func tri_to(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) < 0.0:
		tri(a, c, b, col)
	else:
		tri(a, b, c, col)


## สี่เหลี่ยม a b c d (เรียงรอบรูป) หันไปทาง n
func quad_to(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	tri_to(a, b, c, n, col)
	tri_to(a, c, d, n, col)


func _vert(p: Vector3, n: Vector3, col: Color) -> void:
	_st.set_normal(n)
	_st.set_color(_weather(col, p))
	_st.add_vertex(p)
	if _has_box:
		aabb = aabb.expand(p)
	else:
		aabb = AABB(p, Vector3.ZERO)
		_has_box = true


## ผุกร่อน: โคนเปื้อนเข้ม และด่างนุ่ม ๆ ตามตำแหน่ง (ต่อเนื่อง จึงไม่มีรอยต่อระหว่างชิ้น)
static func _weather(col: Color, p: Vector3) -> Color:
	var g := clampf((p.y + 0.3) / 1.8, 0.0, 1.0)
	var k := lerpf(0.8, 1.0, g)
	k *= 1.0 + 0.05 * sin(p.x * 1.7 + p.z * 0.9 + p.y * 2.3) * cos(p.y * 1.1 - p.x * 0.6 + p.z * 1.9)
	return Color(clampf(col.r * k, 0.0, 1.0), clampf(col.g * k, 0.0, 1.0), clampf(col.b * k, 0.0, 1.0), 1.0)


static func shade(col: Color, k: float) -> Color:
	return Color(clampf(col.r * k, 0.0, 1.0), clampf(col.g * k, 0.0, 1.0), clampf(col.b * k, 0.0, 1.0), 1.0)


## หน้ารูปหลายเหลี่ยมแบน: to3 แปลงจุด 2 มิติเป็น 3 มิติ หันไปทาง n
func poly_face(pts: PackedVector2Array, to3: Callable, n: Vector3, col: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		push_warning("ruin_kit: polygon of %d points did not triangulate" % pts.size())
		return
	for i in range(0, idx.size(), 3):
		tri_to(to3.call(pts[idx[i]]), to3.call(pts[idx[i + 1]]), to3.call(pts[idx[i + 2]]), n, col)


## ผิวข้างระหว่างวงล่างกับวงบน (จำนวนจุดเท่ากัน) หันออกจากแกน
func loft(lo_ring: PackedVector3Array, up_ring: PackedVector3Array, col: Color) -> void:
	var c0 := centroid(lo_ring)
	var ax := centroid(up_ring) - c0
	var len2 := maxf(ax.length_squared(), 1e-9)
	var n := lo_ring.size()
	for i in n:
		var j := (i + 1) % n
		var mid := (lo_ring[i] + lo_ring[j] + up_ring[i] + up_ring[j]) * 0.25
		var on_axis := c0 + ax * clampf((mid - c0).dot(ax) / len2, 0.0, 1.0)
		quad_to(lo_ring[i], lo_ring[j], up_ring[j], up_ring[i], mid - on_axis, col)


## ฝาปิดวง: convex = พัดจากจุดแรก, ไม่งั้นพัดจากจุดกลาง (รูปดาวอย่างเสาร่อง)
func cap(ring: PackedVector3Array, n: Vector3, col: Color, convex: bool = true) -> void:
	if convex:
		for i in range(1, ring.size() - 1):
			tri_to(ring[0], ring[i], ring[i + 1], n, col)
		return
	var c := centroid(ring)
	for i in ring.size():
		tri_to(c, ring[i], ring[(i + 1) % ring.size()], n, col)


static func centroid(ring: PackedVector3Array) -> Vector3:
	var s := Vector3.ZERO
	for p in ring:
		s += p
	return s / maxf(1.0, ring.size())


## วงรอบแกนตั้งที่ความสูง y; flute > 0 = จุดคี่หดเข้าเป็นร่องแบบเสาร่อง; sz = ยืดแกน z (วงรี)
static func ring_pts(c: Vector3, r: float, sides: int, y: float, flute: float = 0.0, sz: float = 1.0, phase: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in sides:
		var a := phase + TAU * i / sides
		var rr := r * (1.0 - flute) if (flute > 0.0 and i % 2 == 1) else r
		out.append(Vector3(c.x + cos(a) * rr, y, c.z + sin(a) * rr * sz))
	return out


## กล่องจากจุดกลางก้น base ครึ่งกว้าง hx ครึ่งลึก hz สูง h หมุนรอบแกนตั้ง yaw
func box(base: Vector3, hx: float, hz: float, h: float, col: Color, yaw: float = 0.0, bottom: bool = false) -> void:
	tbox(base, Vector2(hx, hz), Vector2(hx, hz), h, col, yaw, Vector3.ZERO, bottom)


## กล่องสอบ: ครึ่งขนาดล่าง bh บน th สูง h ยอดเลื่อนได้ shift (ท้องถิ่นของกล่อง)
func tbox(base: Vector3, bh: Vector2, th: Vector2, h: float, col: Color, yaw: float = 0.0, shift: Vector3 = Vector3.ZERO,
		bottom: bool = false, top: bool = true) -> void:
	var r := Basis(Vector3.UP, yaw)
	var lo := PackedVector3Array()
	var up := PackedVector3Array()
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		lo.append(base + r * Vector3(s.x * bh.x, 0.0, s.y * bh.y))
		up.append(base + r * (Vector3(s.x * th.x, h, s.y * th.y) + shift))
	loft(lo, up, col)
	if top:
		cap(up, r * Vector3.UP, col)
	if bottom:
		cap(lo, Vector3.DOWN, col)


## ท่อนสี่เหลี่ยมจาก a ถึง b กว้าง w สูง h (ด้านบนหันขึ้นเท่าที่ได้)
func beam(a: Vector3, b: Vector3, w: float, h: float, col: Color, ends: bool = true) -> void:
	var ax := (b - a).normalized()
	var side := ax.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = ax.cross(Vector3.BACK)
	side = side.normalized()
	var up := side.cross(ax).normalized()
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var o := side * (s.x * w * 0.5) + up * (s.y * h * 0.5)
		ra.append(a + o)
		rb.append(b + o)
	loft(ra, rb, col)
	if ends:
		cap(ra, -ax, col)
		cap(rb, ax, col)


## ทรงกระบอกจาก a ถึง b; flute > 0 = ผิวร่อง (sides ต้องคู่)
func cyl(a: Vector3, b: Vector3, r: float, sides: int, col: Color, ends: bool = true, flute: float = 0.0) -> void:
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.UP)
	if u.length_squared() < 1e-6:
		u = ax.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := ax.cross(u).normalized()
	var ra := PackedVector3Array()
	var rb := PackedVector3Array()
	for i in sides:
		var ang := TAU * i / sides
		var rr := r * (1.0 - flute) if (flute > 0.0 and i % 2 == 1) else r
		var o := (u * cos(ang) + v * sin(ang)) * rr
		ra.append(a + o)
		rb.append(b + o)
	loft(ra, rb, col)
	if ends:
		cap(ra, -ax, col, flute <= 0.0)
		cap(rb, ax, col, flute <= 0.0)


## ก้อนหกเหลี่ยมจากมุมล่าง 4 จุดและบน 4 จุด (ก้อนหิน ค้ำยัน)
func hexa(lo4: PackedVector3Array, up4: PackedVector3Array, col: Color, bottom: bool = false) -> void:
	loft(lo4, up4, col)
	var n_up := (up4[1] - up4[0]).cross(up4[2] - up4[0])
	if n_up.y < 0.0:
		n_up = -n_up
	cap(up4, n_up, col)
	if bottom:
		cap(lo4, Vector3.DOWN, col)


# ---- เส้นโค้งและเส้นขอบหัก (2 มิติ) ----

func arch_segments() -> int:
	return 6 if hi() else 2


## ซีกซ้ายของโค้งแหลมจากตีนโค้งถึงยอด: กลาง cx กว้าง w ตีนโค้ง spring, k = รัศมี/ความกว้าง (1 = โค้งด้านเท่า)
## grow = ขยายรัศมีออก (คิ้วบัวรอบช่อง)
func arch_curve(cx: float, w: float, spring: float, k: float, grow: float = 0.0) -> PackedVector2Array:
	var r0 := w * k
	var cl := cx - w * 0.5 + r0
	var r := r0 + grow
	var a_end := acos(clampf((cx - cl) / r, -1.0, 1.0))
	var n := arch_segments()
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(PI, a_end, float(i) / n)
		out.append(Vector2(cl + cos(a) * r, spring + sin(a) * r))
	return out


## โค้งเต็มจากตีนซ้าย ผ่านยอด ถึงตีนขวา
func arch_full(cx: float, w: float, spring: float, k: float, grow: float = 0.0) -> PackedVector2Array:
	var left := arch_curve(cx, w, spring, k, grow)
	var out := left.duplicate()
	for i in range(left.size() - 2, -1, -1):
		out.append(Vector2(2.0 * cx - left[i].x, left[i].y))
	return out


## ช่องหน้าต่าง/ประตูโค้งแหลม (ทวนเข็ม): ขอบล่าง sill ถึงตีนโค้ง spring
func arch_hole(cx: float, w: float, sill: float, spring: float, k: float = 1.0) -> PackedVector2Array:
	var left := arch_curve(cx, w, spring, k)
	var out := PackedVector2Array([Vector2(cx - w * 0.5, sill), Vector2(cx + w * 0.5, sill)])
	for i in left.size():
		out.append(Vector2(2.0 * cx - left[i].x, left[i].y))
	for i in range(left.size() - 2, -1, -1):
		out.append(left[i])
	return out


## ช่องกลม (หน้าต่างกุหลาบ) ทวนเข็ม
func circle_hole(cx: float, cy: float, r: float, sides: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in sides:
		var a := -PI * 0.5 + TAU * i / sides
		out.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return out


## ยอดผนังที่หักเป็นขั้น ๆ จาก a ถึง b (u เพิ่มขึ้น) n ขั้นกว้างไม่เท่ากัน บางขั้นบิ่นเฉียง; ไม่รวมจุด a
func steps(a: Vector2, b: Vector2, n: int, rough: float = 0.2) -> PackedVector2Array:
	var ws: Array[float] = []
	var tot := 0.0
	for i in n:
		var x := rf(0.6, 1.4)
		ws.append(x)
		tot += x
	var out := PackedVector2Array()
	var u := a.x
	var v := a.y
	for i in n:
		var u2 := u + (b.x - a.x) * ws[i] / tot
		var target := b.y if i == n - 1 else lerpf(a.y, b.y, float(i + 1) / n) + rf(-rough, rough)
		var chip := rf(0.0, 1.0) < 0.3
		var cw := minf(0.12, (u2 - u) * 0.4)
		out.append(Vector2(u2 - cw if chip else u2, v))
		out.append(Vector2(u2, target))
		u = u2
		v = target
	return out


## ขอบหักของแผ่นพื้น: จุดระหว่าง a กับ b เบี้ยวตั้งฉากสลับข้าง; รวมจุด a ไม่รวม b
func jag(a: Vector2, b: Vector2, n: int, amp: float) -> PackedVector2Array:
	var out := PackedVector2Array([a])
	var d := b - a
	var perp := Vector2(-d.y, d.x).normalized()
	for i in range(1, n):
		var t := (float(i) + rf(-0.25, 0.25)) / n
		var side := 1.0 if i % 2 == 0 else -1.0
		out.append(a + d * t + perp * side * amp * rf(0.4, 1.0))
	return out


## ความสูงยอดผนังที่ u (ขั้นตั้งฉากใช้ค่าต่ำกว่า)
static func top_at(top: PackedVector2Array, u: float) -> float:
	var best := INF
	for i in top.size() - 1:
		var a := top[i]
		var b := top[i + 1]
		if u < minf(a.x, b.x) - 1e-6 or u > maxf(a.x, b.x) + 1e-6:
			continue
		var v := minf(a.y, b.y) if absf(b.x - a.x) < 1e-6 else lerpf(a.y, b.y, (u - a.x) / (b.x - a.x))
		best = minf(best, v)
	return best if best < INF else 0.0


## ลดจุดของเส้น (Douglas-Peucker) สำหรับ lo
static func simplify(pts: PackedVector2Array, tol: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, pts.size() - 1)]
	while not stack.is_empty():
		var s: Vector2i = stack.pop_back()
		var best := -1.0
		var bi := -1
		for i in range(s.x + 1, s.y):
			var d := _seg_dist(pts[i], pts[s.x], pts[s.y])
			if d > best:
				best = d
				bi = i
		if bi >= 0 and best > tol:
			keep[bi] = 1
			stack.append(Vector2i(s.x, bi))
			stack.append(Vector2i(bi, s.y))
	var out := PackedVector2Array()
	for i in pts.size():
		if keep[i] == 1:
			out.append(pts[i])
	return out


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var d := b - a
	var t := 0.0 if d.length_squared() < 1e-12 else clampf((p - a).dot(d) / d.length_squared(), 0.0, 1.0)
	return p.distance_to(a + d * t)


static func area2(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s


static func rect_of(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for q in p:
		r = r.expand(q)
	return r


# ---- ชิ้นส่วน ----

## แผงผนังหนา t ยาว length ตามแกน x ท้องถิ่น (กึ่งกลางความหนาที่ z = 0 หน้าหลักหัน +z) โคนที่ v0 ยอดตามเส้นหัก top
## holes = [{"poly": ช่อง, "open_lo": bool}] · hi เจาะช่องจริงพร้อมผิวในช่อง (หั่นแถบตั้งผ่านกลางทุกช่องแล้วตัดด้วย
## Geometry2D จึงไม่มีรูกลางชิ้น) · lo ช่องทึบทาสีเข้มสองหน้า (ยกเว้น open_lo เช่นประตู ซุ้มรูปปั้น)
func wall(length: float, t: float, top: PackedVector2Array, holes: Array, col: Color, v0: float = -0.4) -> void:
	var tp := top if hi() else simplify(top, 0.22)
	var outline := PackedVector2Array([Vector2(0.0, v0), Vector2(length, v0)])
	for i in range(tp.size() - 1, -1, -1):
		outline.append(tp[i])
	var cut_holes: Array[PackedVector2Array] = []
	var decals: Array[PackedVector2Array] = []
	for h: Dictionary in holes:
		if hi() or bool(h.get("open_lo", false)):
			cut_holes.append(h["poly"])
		else:
			decals.append(h["poly"])
	var xs: Array[float] = [0.0, length]
	for p in cut_holes:
		xs.append(rect_of(p).get_center().x)
	xs.sort()
	var cuts: Array[float] = []
	for x in xs:
		if cuts.is_empty() or x - cuts[cuts.size() - 1] > 0.002:
			cuts.append(x)
	var hz := t * 0.5
	var front := func(q: Vector2) -> Vector3: return Vector3(q.x, q.y, hz)
	var back := func(q: Vector2) -> Vector3: return Vector3(q.x, q.y, -hz)
	for k in cuts.size() - 1:
		var strip := PackedVector2Array([Vector2(cuts[k], v0 - 1.0), Vector2(cuts[k + 1], v0 - 1.0),
			Vector2(cuts[k + 1], 60.0), Vector2(cuts[k], 60.0)])
		var pieces: Array = Geometry2D.intersect_polygons(outline, strip)
		for hole in cut_holes:
			var next: Array = []
			for p: PackedVector2Array in pieces:
				next.append_array(Geometry2D.clip_polygons(p, hole))
			pieces = next
		for p: PackedVector2Array in pieces:
			if area2(p) <= 0.0:
				push_warning("ruin_kit: wall piece came out as a hole; skipped")
				continue
			poly_face(p, front, Vector3.BACK, col)
			poly_face(p, back, Vector3.FORWARD, col)
			for i in p.size():
				var a := p[i]
				var b := p[(i + 1) % p.size()]
				if absf(a.x - b.x) < 0.002 and _on_cut(a.x, cuts, k):
					continue
				if a.y <= v0 + 0.002 and b.y <= v0 + 0.002:
					continue
				var d := b - a
				var n2 := Vector2(d.y, -d.x)
				# ยอดที่หักเป็นฝุ่นหินสีอ่อน ผิวในช่องเข้มกว่าผนังนิดหนึ่ง
				var sc := DUST if n2.normalized().y > 0.7 and _is_top(a, b, tp) else shade(col, 0.93)
				quad_to(Vector3(a.x, a.y, hz), Vector3(b.x, b.y, hz), Vector3(b.x, b.y, -hz), Vector3(a.x, a.y, -hz),
					Vector3(n2.x, n2.y, 0.0), sc)
	for hole in decals:
		for p: PackedVector2Array in Geometry2D.intersect_polygons(hole, outline):
			if area2(p) <= 0.0:
				continue
			poly_face(p, func(q: Vector2) -> Vector3: return Vector3(q.x, q.y, hz + 0.015), Vector3.BACK, GLASS)
			poly_face(p, func(q: Vector2) -> Vector3: return Vector3(q.x, q.y, -hz - 0.015), Vector3.FORWARD, GLASS)
	if hi():
		_masonry(length, hz, tp, cut_holes, col)


## ก้อนหินก่อเป็นแถวสลับแนว (hi): แผ่นบางสีอ่อนเข้มต่างกันบนสองหน้าผนัง เว้นช่องและยอดที่หัก ให้ผนังดูเป็นหินก่อ
func _masonry(length: float, hz: float, top: PackedVector2Array, holes: Array[PackedVector2Array], col: Color) -> void:
	var keep_out: Array[Rect2] = []
	for h in holes:
		keep_out.append(rect_of(h).grow(0.1))
	var course := 0.55
	for side: float in [1.0, -1.0]:
		var row := 0
		var v := 0.12
		while v < 9.6:
			var u := -rf(0.0, 0.5) if row % 2 == 0 else -rf(0.5, 1.0)
			while u < length:
				var bl := rf(0.7, 1.35)
				var u0 := maxf(u, 0.0) + 0.035
				var u1 := minf(u + bl, length) - 0.035
				var r := Rect2(u0, v + 0.035, u1 - u0, course - 0.07)
				if r.size.x > 0.25 and rf(0.0, 1.0) < 0.42 and _block_ok(r, top, keep_out):
					var z := (hz + 0.008) * side
					quad_to(Vector3(r.position.x, r.position.y, z), Vector3(r.end.x, r.position.y, z), Vector3(r.end.x, r.end.y, z),
						Vector3(r.position.x, r.end.y, z), Vector3(0.0, 0.0, side), shade(col, rf(0.8, 1.12)))
				u += bl
			v += course
			row += 1


static func _block_ok(r: Rect2, top: PackedVector2Array, keep_out: Array[Rect2]) -> bool:
	for x: float in [r.position.x, r.get_center().x, r.end.x]:
		if r.end.y > top_at(top, x) - 0.06:
			return false
	for b in keep_out:
		if b.intersects(r):
			return false
	return true


## ขอบตั้งที่อยู่บนเส้นหั่นภายใน (เส้นหั่นซ้ายหรือขวาของแถบ k ที่ไม่ใช่ปลายผนัง)
static func _on_cut(x: float, cuts: Array[float], k: int) -> bool:
	for c in [k, k + 1]:
		if c > 0 and c < cuts.size() - 1 and absf(x - cuts[c]) < 0.002:
			return true
	return false


static func _is_top(a: Vector2, b: Vector2, top: PackedVector2Array) -> bool:
	var m := (a + b) * 0.5
	return absf(top_at(top, m.x) - m.y) < 0.03


## คิ้วบัวเขียวสนิมเหนือช่องโค้งบนหน้าผนัง (face = z ของผิวหน้า): แถบนูนตามโค้ง หยุดตรงที่ผนังหัก (hi เท่านั้น)
func hood(cx: float, w: float, spring: float, k: float, face: float, top: PackedVector2Array) -> void:
	if not hi():
		return
	var inner := arch_full(cx, w, spring, k, 0.04)
	var outer := arch_full(cx, w, spring, k, 0.19)
	var d := 0.1
	var c := Vector2(cx, spring)
	for i in inner.size() - 1:
		if outer[i].y > top_at(top, outer[i].x) - 0.08 or outer[i + 1].y > top_at(top, outer[i + 1].x) - 0.08:
			continue
		var i0 := inner[i]
		var i1 := inner[i + 1]
		var o0 := outer[i]
		var o1 := outer[i + 1]
		quad_to(Vector3(i0.x, i0.y, face + d), Vector3(o0.x, o0.y, face + d), Vector3(o1.x, o1.y, face + d),
			Vector3(i1.x, i1.y, face + d), Vector3.BACK, TRIM)
		var mo := (o0 + o1) * 0.5 - c
		quad_to(Vector3(o0.x, o0.y, face), Vector3(o1.x, o1.y, face), Vector3(o1.x, o1.y, face + d),
			Vector3(o0.x, o0.y, face + d), Vector3(mo.x, mo.y, 0.0), TRIM_DARK)
		var mi := c - (i0 + i1) * 0.5
		quad_to(Vector3(i0.x, i0.y, face), Vector3(i1.x, i1.y, face), Vector3(i1.x, i1.y, face + d),
			Vector3(i0.x, i0.y, face + d), Vector3(mi.x, mi.y, 0.0), TRIM_DARK)
	# ปลายคิ้วที่ตีนโค้งสองข้าง
	for e in [0, inner.size() - 1]:
		var a := inner[e]
		var b := outer[e]
		if b.y > top_at(top, b.x) - 0.08:
			continue
		quad_to(Vector3(a.x, a.y, face), Vector3(b.x, b.y, face), Vector3(b.x, b.y, face + d), Vector3(a.x, a.y, face + d),
			Vector3.DOWN, TRIM_DARK)


## แถบคาดผนังแนวนอน (ชั้นบัว) จาก u0 ถึง u1 ที่ความสูง v บนผิว face ยื่น d
func band(u0: float, u1: float, v: float, h: float, face: float, d: float, col: Color) -> void:
	box(Vector3((u0 + u1) * 0.5, v, face + d * 0.5 - 0.02), (u1 - u0) * 0.5, d * 0.5 + 0.02, h, col)


## เสาค้ำกลางช่อง (mullion) ในหน้าต่างบานกว้าง
func mullion(cx: float, sill: float, top: float, t: float) -> void:
	if not hi():
		return
	box(Vector3(cx, sill - 0.02, 0.0), 0.06, t * 0.32, top - sill + 0.04, STONE_PALE)


## ซุ้มเว้าหลังช่อง (ที่ตั้งรูปปั้น): ผิวในช่องลึกต่อเข้าไปอีก depth หลังผนัง ปิดด้วยแผ่นหลัง และเปลือกกล่องมองจากในตึก
func niche(hole: PackedVector2Array, back_z: float, depth: float, v0: float = -0.4) -> void:
	var z1 := back_z - depth
	var n := hole.size()
	for i in n:
		var a := hole[i]
		var b := hole[(i + 1) % n]
		var dd := b - a
		var inward := Vector2(-dd.y, dd.x)
		quad_to(Vector3(a.x, a.y, back_z), Vector3(b.x, b.y, back_z), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1),
			Vector3(inward.x, inward.y, 0.0), RECESS)
	poly_face(hole, func(q: Vector2) -> Vector3: return Vector3(q.x, q.y, z1), Vector3.BACK, shade(RECESS, 0.9))
	var r := rect_of(hole)
	var m := 0.14
	var x0 := r.position.x - m
	var x1 := r.end.x + m
	var y1 := r.end.y + m
	var zb := z1 - 0.06
	quad_to(Vector3(x0, v0, zb), Vector3(x1, v0, zb), Vector3(x1, y1, zb), Vector3(x0, y1, zb), Vector3.FORWARD, STONE)
	quad_to(Vector3(x0, v0, zb), Vector3(x0, v0, back_z), Vector3(x0, y1, back_z), Vector3(x0, y1, zb), Vector3.LEFT, STONE)
	quad_to(Vector3(x1, v0, zb), Vector3(x1, v0, back_z), Vector3(x1, y1, back_z), Vector3(x1, y1, zb), Vector3.RIGHT, STONE)
	quad_to(Vector3(x0, y1, zb), Vector3(x1, y1, zb), Vector3(x1, y1, back_z), Vector3(x0, y1, back_z), Vector3.UP, DUST)


## หน้าต่างกุหลาบ (ในช่องกลมของผนัง หนา t): วงหินนอก ซี่รัศมี วงใน และขอบบัวเขียวสนิมบนหน้าผนัง
## lo: แผ่นกลมสีเข้มจากผนังแล้ว ที่นี่เพิ่มแค่ขอบบัว
func rose(cx: float, cy: float, r: float, t: float) -> void:
	var hz := t * 0.5
	var c := Vector3(cx, cy, 0.0)
	var n_out := 16 if hi() else 8
	if hi():
		var d := t * 0.32
		_ring(c, r, r * 0.86, n_out, -d, d, STONE_PALE, false)
		_ring(c, r * 0.4, r * 0.3, 8, -d, d, STONE_PALE, true)
		for i in 8:
			var a := TAU * i / 8.0 + PI / 8.0
			_spoke(c, Vector3(cos(a), sin(a), 0.0), r * 0.37, r * 0.9, r * 0.075, d * 0.8)
	if hi():
		_ring(c, r * 1.13, r, n_out, hz, hz + 0.09, TRIM, true, true)
	else:
		# lo: ซี่หินสี่เส้นไขว้กันบนแผ่นกลมสีเข้ม (ด้านหน้าเท่านั้น)
		for i in 4:
			var a := PI / 8.0 + PI * i / 4.0
			var d := Vector3(cos(a), sin(a), 0.0) * (r * 0.92)
			var p := Vector3(-sin(a), cos(a), 0.0) * (r * 0.05)
			var z := Vector3(0.0, 0.0, hz + 0.03)
			quad_to(c - d - p + z, c + d - p + z, c + d + p + z, c - d + p + z, Vector3.BACK, STONE_PALE)


## ซี่หินของหน้าต่างกุหลาบ: จากรัศมี r0 ถึง r1 ตามทิศ dir (ในระนาบผนัง) กว้าง w ลึก ±d
func _spoke(c: Vector3, dir: Vector3, r0: float, r1: float, w: float, d: float) -> void:
	var p := Vector3(-dir.y, dir.x, 0.0) * (w * 0.5)
	var z := Vector3(0.0, 0.0, d)
	var a := c + dir * r0
	var b := c + dir * r1
	loft(PackedVector3Array([a - p - z, a + p - z, a + p + z, a - p + z]), PackedVector3Array([b - p - z, b + p - z, b + p + z, b - p + z]), STONE_PALE)


## วงแหวนแบนในระนาบผนัง: รัศมีนอก ro ใน ri ที่ z0..z1; outer_face = วาดผิวรอบนอก; front_only = ไม่วาดหน้าหลัง
func _ring(c: Vector3, ro: float, ri: float, n: int, z0: float, z1: float, col: Color, outer_face: bool, front_only: bool = false) -> void:
	for i in n:
		var a0 := -PI * 0.5 + TAU * i / n
		var a1 := -PI * 0.5 + TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		var o0 := c + d0 * ro
		var o1 := c + d1 * ro
		var i0 := c + d0 * ri
		var i1 := c + d1 * ri
		var zf := Vector3(0, 0, z1)
		var zb := Vector3(0, 0, z0)
		quad_to(i0 + zf, o0 + zf, o1 + zf, i1 + zf, Vector3.BACK, col)
		if not front_only:
			quad_to(i0 + zb, o0 + zb, o1 + zb, i1 + zb, Vector3.FORWARD, col)
		var mid := (d0 + d1) * 0.5
		quad_to(i0 + zb, i1 + zb, i1 + zf, i0 + zf, -mid, shade(col, 0.88))
		if outer_face:
			quad_to(o0 + zb, o1 + zb, o1 + zf, o0 + zf, mid, shade(col, 0.88))


## เสาร่องมีปลอกทองเหลืองเป็นช่วง: ฐานสี่เหลี่ยม ตัวเสาร่อง หัวเสาบาน + แผ่นหัวเสา; broken = ยอดหักขรุขระ
func pillar(base: Vector3, height: float, r: float, bands: int, broken: bool = false, seed_value: int = 0) -> void:
	seed_piece(seed_value)
	var flutes := 8 if hi() else 4
	var sides := flutes * 2
	var y0 := base.y + 0.42
	var y1 := base.y + height - (0.0 if broken else 0.55)
	box(base + Vector3(0.0, -0.3, 0.0), r * 1.32, r * 1.32, 0.72, STONE_DARK)
	var lo := ring_pts(base, r, sides, y0, 0.16)
	var up := ring_pts(base, r, sides, y1, 0.16)
	var low_top := y1
	if broken:
		for i in up.size():
			var q := up[i]
			q.y -= rf(0.0, 0.45)
			up[i] = q
			low_top = minf(low_top, q.y)
	loft(lo, up, shade(STONE, 1.06))
	var bs := 10 if hi() else 6
	if broken:
		var c := Vector3(base.x, y1 - 0.3, base.z)
		for i in sides:
			tri_to(c, up[i], up[(i + 1) % sides], Vector3.UP, DUST)
	else:
		if hi():
			loft(ring_pts(base, r * 1.02, bs, y1), ring_pts(base, r * 1.38, bs, y1 + 0.33), STONE_PALE)
			_collar(base, r * 1.1, bs, y1 - 0.04, 0.12, TRIM)
			box(Vector3(base.x, y1 + 0.33, base.z), r * 1.5, r * 1.5, 0.22, STONE_PALE)
		else:
			tbox(Vector3(base.x, y1, base.z), Vector2(r, r), Vector2(r * 1.5, r * 1.5), 0.55, STONE_PALE)
	for kb in bands:
		if not hi() and kb != bands / 2:
			continue
		var yb := lerpf(y0, y1, float(kb + 1) / (bands + 1))
		if yb + 0.1 > low_top - 0.2:
			continue
		_collar(base, r * 1.14, bs, yb - 0.09, 0.18, BRASS)


## ปลอกรอบเสา: วงหลายเหลี่ยมสูง h พร้อมฝาบนล่าง
func _collar(c: Vector3, r: float, sides: int, y: float, h: float, col: Color) -> void:
	var a := ring_pts(c, r, sides, y)
	var b := ring_pts(c, r, sides, y + h)
	loft(a, b, col)
	cap(b, Vector3.UP, col)
	cap(a, Vector3.DOWN, shade(col, 0.8))


## ค้ำยันติดผนัง: base = จุดบนผิวผนังด้านนอกที่ระดับดิน ยื่นออกตาม yaw (+z ท้องถิ่น) กว้าง w สองชั้น หัวลาด
func buttress(base: Vector3, yaw: float, w: float, d1: float, h1: float, d2: float, h2: float, broken: bool = false) -> void:
	var keep := xf
	xf = keep * Transform3D(Basis(Vector3.UP, yaw), base)
	var hw := w * 0.5
	var lo := PackedVector3Array([Vector3(-hw, -0.35, -0.05), Vector3(hw, -0.35, -0.05), Vector3(hw, -0.35, d1), Vector3(-hw, -0.35, d1)])
	var up := PackedVector3Array([Vector3(-hw, h1 + 0.45, -0.05), Vector3(hw, h1 + 0.45, -0.05), Vector3(hw, h1, d1), Vector3(-hw, h1, d1)])
	hexa(lo, up, STONE)
	var w2 := hw * 0.84
	var top2 := h2 + (0.1 if broken else 0.4)
	var lo2 := PackedVector3Array([Vector3(-w2, h1, -0.05), Vector3(w2, h1, -0.05), Vector3(w2, h1, d2), Vector3(-w2, h1, d2)])
	var up2 := PackedVector3Array([Vector3(-w2, top2, -0.05), Vector3(w2, top2 - (0.25 if broken else 0.0), -0.05),
		Vector3(w2, h2 - (0.3 if broken else 0.0), d2), Vector3(-w2, h2, d2)])
	hexa(lo2, up2, STONE)
	xf = keep


## บันไดหินทึบ: เริ่มที่ start (กลางขอบล่างขั้นแรก) ขึ้นไปทาง +z ท้องถิ่นที่หมุน yaw กว้าง w
## n ขั้น สูงขั้นละ rise ลึก run; y_base = ฐานที่ฝังดิน; lo รวมสองขั้นเป็นหนึ่ง
func stair(start: Vector3, yaw: float, w: float, n: int, rise: float, run: float, y_base: float = -0.3) -> void:
	var keep := xf
	xf = keep * Transform3D(Basis(Vector3.UP, yaw), start)
	var step := 1 if hi() else 2
	var hw := w * 0.5
	var i := 0
	while i < n:
		var j := mini(n, i + step)
		var z0 := i * run
		var z1 := j * run
		var y := j * rise
		var last := j >= n
		var col := STONE if (i / step) % 2 == 0 else shade(STONE, 0.95)
		# ขั้น: บน หน้า ข้างสองข้าง (หลังมีเฉพาะขั้นสุดท้าย)
		quad_to(Vector3(-hw, y, z0), Vector3(hw, y, z0), Vector3(hw, y, z1), Vector3(-hw, y, z1), Vector3.UP, DUST if hi() and i % 4 == 3 else STONE_PALE)
		quad_to(Vector3(-hw, y_base, z0), Vector3(hw, y_base, z0), Vector3(hw, y, z0), Vector3(-hw, y, z0), Vector3.FORWARD, col)
		quad_to(Vector3(-hw, y_base, z0), Vector3(-hw, y_base, z1), Vector3(-hw, y, z1), Vector3(-hw, y, z0), Vector3.LEFT, col)
		quad_to(Vector3(hw, y_base, z0), Vector3(hw, y_base, z1), Vector3(hw, y, z1), Vector3(hw, y, z0), Vector3.RIGHT, col)
		if last:
			quad_to(Vector3(-hw, y_base, z1), Vector3(hw, y_base, z1), Vector3(hw, y, z1), Vector3(-hw, y, z1), Vector3.BACK, col)
		i = j
	xf = keep


## แผ่นพื้น: รูปหลายเหลี่ยม (x, z) ผิวบนที่ y_top หนา t ทุกขอบมีผิวข้าง (ขอบหักเห็นความหนา)
func slab(poly: PackedVector2Array, y_top: float, t: float, col: Color) -> void:
	var ccw := area2(poly) > 0.0
	poly_face(poly, func(q: Vector2) -> Vector3: return Vector3(q.x, y_top, q.y), Vector3.UP, col)
	poly_face(poly, func(q: Vector2) -> Vector3: return Vector3(q.x, y_top - t, q.y), Vector3.DOWN, shade(col, 0.8))
	var side := shade(col, 0.9)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := b - a
		var n2 := Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x)
		quad_to(Vector3(a.x, y_top, a.y), Vector3(b.x, y_top, b.y), Vector3(b.x, y_top - t, b.y), Vector3(a.x, y_top - t, a.y),
			Vector3(n2.x, 0.0, n2.y), side)


## กองซาก: เนินฝุ่นรูปรีกับก้อนหินแตก count ก้อน (lo ใช้ครึ่งเดียว เอาก้อนใหญ่) · ก้อนบางก้อนเป็นเศษคิ้วบัว/เศษเหล็ก
func rubble(c: Vector3, rx: float, rz: float, h: float, count: int, seed_value: int, yaw: float = 0.0) -> void:
	seed_piece(seed_value)
	var rot := Basis(Vector3.UP, yaw)
	var n := 8
	var ground := PackedVector3Array()
	var mid := PackedVector3Array()
	var jit: Array[float] = []
	for i in n:
		jit.append(rf(0.8, 1.15))
	for i in n:
		var a := TAU * i / n
		ground.append(c + rot * Vector3(cos(a) * rx * jit[i], -0.06, sin(a) * rz * jit[i]))
		mid.append(c + rot * Vector3(cos(a) * rx * jit[i] * 0.55, h * rf(0.45, 0.65), sin(a) * rz * jit[i] * 0.55))
	var peak := c + rot * Vector3(rf(-0.15, 0.15) * rx, h, rf(-0.15, 0.15) * rz)
	if hi():
		loft(ground, mid, DUST)
		cap_to(mid, peak, DUST)
	else:
		var g2 := PackedVector3Array()
		for i in range(0, n, 2):
			g2.append(ground[i])
		cap_to(g2, peak, DUST)
	var chunks: Array[Dictionary] = []
	for i in count:
		var ang := rf(0.0, TAU)
		var rr := sqrt(rf(0.0, 1.0))
		var size := rf(0.22, 0.55) * (1.0 - 0.45 * rr)
		var p := c + rot * Vector3(cos(ang) * rx * rr * 0.95, 0.0, sin(ang) * rz * rr * 0.95)
		p.y = c.y + h * (1.0 - rr * rr) * 0.75 - size * 0.25
		var pick := rf(0.0, 1.0)
		var col := STONE_PALE if pick < 0.3 else (STONE_DARK if pick < 0.55 else STONE)
		if pick > 0.93:
			col = TRIM
		elif pick > 0.88:
			col = RUST_DARK
		var j := PackedFloat32Array()
		for q in 24:
			j.append(rf(-0.25, 0.25))
		chunks.append({"p": p, "s": size, "yaw": rf(0.0, TAU), "sy": rf(0.45, 0.85), "sz": rf(0.7, 1.25), "j": j,
			"col": shade(col, rf(0.9, 1.06))})
	chunks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) > float(b["s"]))
	var use := count if hi() else (count + 2) / 3
	for i in use:
		chunk(chunks[i])


## เศษหินกระจาย (ไม่มีเนิน) บนพื้นระดับ c.y เช่นบนแผ่นพื้นชั้นบนใกล้ขอบที่หัก; lo ใช้หนึ่งในสาม
func scatter(c: Vector3, rx: float, rz: float, count: int, seed_value: int) -> void:
	seed_piece(seed_value)
	var use := count if hi() else (count + 2) / 3
	for i in count:
		var p := c + Vector3(rf(-rx, rx), 0.0, rf(-rz, rz))
		var j := PackedFloat32Array()
		for q in 24:
			j.append(rf(-0.25, 0.25))
		var q2 := {"p": p, "s": rf(0.18, 0.4), "yaw": rf(0.0, TAU), "sy": rf(0.45, 0.8), "sz": rf(0.7, 1.2), "j": j,
			"col": shade(STONE_PALE if i % 3 == 0 else STONE, rf(0.9, 1.05))}
		if i < use:
			chunk(q2)


## ฝาพัดถึงจุดยอด (เนิน ยอดหัก)
func cap_to(ring: PackedVector3Array, peak: Vector3, col: Color) -> void:
	for i in ring.size():
		tri_to(peak, ring[i], ring[(i + 1) % ring.size()], Vector3.UP, col)


## ก้อนหินแตกหนึ่งก้อนจากค่าที่สุ่มไว้แล้ว (กล่องบิดมุม)
func chunk(q: Dictionary) -> void:
	var s: float = q["s"]
	var size := Vector3(s, s * float(q["sy"]), s * float(q["sz"]))
	var r := Basis(Vector3.UP, float(q["yaw"]))
	var p: Vector3 = q["p"]
	var j: PackedFloat32Array = q["j"]
	var lo := PackedVector3Array()
	var up := PackedVector3Array()
	var k := 0
	for sgn: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		lo.append(p + r * Vector3((sgn.x * 0.5 + j[k]) * size.x, j[k + 1] * size.y * 0.3, (sgn.y * 0.5 + j[k + 2]) * size.z))
		up.append(p + r * Vector3((sgn.x * 0.42 + j[k + 3]) * size.x, size.y * (1.0 + j[k + 4]), (sgn.y * 0.42 + j[k + 5]) * size.z))
		k += 6
	hexa(lo, up, q["col"])


## ท่อนเสาร่องที่ล้มนอน (กลอง): กลาง c ยาว length รัศมี r ตามทิศ yaw เอียง tilt
func drum(c: Vector3, r: float, length: float, yaw: float, tilt: float = 0.0) -> void:
	var ax := Basis(Vector3.UP, yaw) * Vector3(cos(tilt), sin(tilt), 0.0)
	cyl(c - ax * length * 0.5, c + ax * length * 0.5, r, 12 if hi() else 6, STONE, true, 0.14 if hi() else 0.0)


## แผ่นเหล็กสนิมแดงปะผนัง: base = กลางขอบล่างบนผิวผนัง หันออก +z ท้องถิ่น (yaw) กว้าง su สูง sv พร้อมแถบคาด
func panel(base: Vector3, yaw: float, su: float, sv: float, d: float = 0.07) -> void:
	var keep := xf
	xf = keep * Transform3D(Basis(Vector3.UP, yaw), base)
	box(Vector3(0.0, 0.0, d * 0.5), su * 0.5, d * 0.5, sv, RUST)
	var straps: Array = [0.18, sv * 0.5, sv - 0.32] if hi() else [sv * 0.5]
	for y in straps:
		box(Vector3(0.0, y, d + 0.015), su * 0.5 + 0.04, 0.025, 0.14, RUST_DARK)
	if hi():
		for x in [-su * 0.5 + 0.06, su * 0.5 - 0.06]:
			box(Vector3(x, 0.02, d + 0.015), 0.05, 0.025, sv - 0.04, RUST_DARK)
	xf = keep


## ท่อเดินผ่านจุด pts (ข้อต่อทองเหลืองที่หัวมุมและปลายหัก)
func pipe(pts: PackedVector3Array, r: float) -> void:
	var sides := 8 if hi() else 5
	for i in pts.size() - 1:
		cyl(pts[i], pts[i + 1], r, sides, RUST, i == pts.size() - 2 or i == 0)
	if hi():
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var ax := (b - a).normalized()
			cyl(b - ax * 0.12, b + ax * (0.06 if i < pts.size() - 1 else -0.02), r * 1.3, sides, BRASS, true)


## รูปปั้นผู้พิทักษ์สวมเสื้อคลุมมีฮู้ด (กล่องสอบล้วน): ยืนบน base หันหน้า +z (yaw) สูงราว h
## ถือดาบปักลงพื้นตรงหน้า สองมือวางบนด้าม — รูปทรงเรียบ ไม่มีตราหรือสัญลักษณ์
func statue(base: Vector3, h: float, yaw: float) -> void:
	var keep := xf
	var s := h / 2.6
	xf = keep * Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), base)
	var col := BRONZE
	box(Vector3.ZERO, 0.38, 0.32, 0.14, STONE_PALE)
	var folds := 0.12 if hi() else 0.0
	var sides := 12 if hi() else 6
	loft(ring_pts(Vector3(0, 0, 0.02), 0.34, sides, 0.14, folds, 0.78), ring_pts(Vector3(0, 0, 0.01), 0.24, sides, 1.2, folds, 0.72), col)
	tbox(Vector3(0, 1.2, 0), Vector2(0.24, 0.17), Vector2(0.27, 0.16), 0.6, col)
	tbox(Vector3(0, 1.8, 0), Vector2(0.27, 0.16), Vector2(0.17, 0.13), 0.14, col)
	tbox(Vector3(0, 1.92, -0.01), Vector2(0.14, 0.15), Vector2(0.05, 0.07), 0.46, col, 0.0, Vector3(0, 0, 0.04))
	# เงาใบหน้าในฮู้ด
	quad_to(Vector3(-0.07, 2.0, 0.157), Vector3(0.07, 2.0, 0.157), Vector3(0.05, 2.2, 0.135), Vector3(-0.05, 2.2, 0.135),
		Vector3(0, 0.1, 1), shade(RECESS, 0.55))
	tbox(Vector3(0, 0.14, -0.14), Vector2(0.36, 0.07), Vector2(0.26, 0.06), 1.74, shade(col, 0.9))
	for sx in [-1.0, 1.0]:
		beam(Vector3(sx * 0.25, 1.8, 0.0), Vector3(sx * 0.08, 1.3, 0.24), 0.14, 0.14, col, hi())
	box(Vector3(0, 1.22, 0.26), 0.1, 0.07, 0.12, col)
	beam(Vector3(0, 1.17, 0.29), Vector3(0, 0.16, 0.31), 0.08, 0.025, shade(col, 1.08), hi())
	if hi():
		beam(Vector3(-0.18, 1.17, 0.29), Vector3(0.18, 1.17, 0.29), 0.05, 0.05, shade(col, 1.08))
		box(Vector3(0, 1.34, 0.28), 0.045, 0.045, 0.07, shade(col, 1.08))
	xf = keep
