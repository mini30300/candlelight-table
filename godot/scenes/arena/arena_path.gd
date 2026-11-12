class_name ArenaPath
extends RefCounted
## ทางเดินของสัตว์รัง (ARENA_SPEC §8.4): ตาราง 0.5 ม. บนพื้นห้อง ช่องว่างคือช่องที่วงกลมรัศมี radius วางได้ไม่ชนที่กัน
## A* 8 ทิศ (ห้ามตัดมุม) แล้วดึงเส้นให้ตรงด้วย clear_line · ข้อมูลล้วน ไม่มีโหนด ไม่มีฟิสิกส์ ผลเหมือนเดิมทุกครั้ง
## ที่กันรับรูปแบบ HallLayout.blockers() (box / cyl) จากโลก · เอาเฉพาะชิ้นที่ถึงพื้น (ล่างต่ำกว่า GROUND_Y)

const GROUND_Y := 2.0
## ช่องว่างกันเผื่ออีกนิด เส้นตรงระหว่างจุดกลางช่องติดกัน (ยาวไม่เกิน 0.71 ม.) จึงห่างที่กันไม่น้อยกว่า radius
const CELL_PAD := 0.1
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var bounds: Rect2
var radius := 0.7
var cell := 0.5
var cols := 0
var rows := 0
var free := PackedByteArray()
var _boxes: Array[Rect2] = []          # รอยพื้นของกล่อง (x, z)
var _circles: Array[Vector3] = []      # (x, z, r)


func _init(p_bounds: Rect2, blockers: Array, p_radius: float, p_cell := 0.5) -> void:
	bounds = p_bounds
	radius = p_radius
	cell = p_cell
	cols = maxi(int(ceil(bounds.size.x / cell - 0.0001)), 1)
	rows = maxi(int(ceil(bounds.size.y / cell - 0.0001)), 1)
	var near := bounds.grow(radius + cell)
	for b in blockers:
		if not (b is Dictionary):
			continue
		if str(b.get("kind", "")) == "box":
			var c: Vector3 = b["c"]
			var h: Vector3 = b["h"]
			if c.y - h.y >= GROUND_Y:
				continue
			var r := Rect2(c.x - h.x, c.z - h.z, h.x * 2.0, h.z * 2.0)
			if r.intersects(near):
				_boxes.append(r)
		elif str(b.get("kind", "")) == "cyl":
			if float(b.get("y0", 0.0)) >= GROUND_Y:
				continue
			var cc: Vector2 = b["c"]
			var rr := float(b["r"])
			if near.grow(rr).has_point(cc):
				_circles.append(Vector3(cc.x, cc.y, rr))
	free.resize(cols * rows)
	for j in rows:
		for i in cols:
			free[j * cols + i] = 1 if point_free(centre(Vector2i(i, j)), radius + CELL_PAD) else 0


## จุดกลางของช่อง
func centre(c: Vector2i) -> Vector2:
	return bounds.position + Vector2((c.x + 0.5) * cell, (c.y + 0.5) * cell)


func cell_of(p: Vector2) -> Vector2i:
	var q := (p - bounds.position) / cell
	return Vector2i(clampi(int(floor(q.x)), 0, cols - 1), clampi(int(floor(q.y)), 0, rows - 1))


func is_free(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows and free[c.y * cols + c.x] == 1


## วงกลม (p, r) อยู่ในขอบเขตและไม่แตะที่กันชิ้นไหนเลย
func point_free(p: Vector2, r: float) -> bool:
	if p.x < bounds.position.x + r or p.y < bounds.position.y + r or p.x > bounds.end.x - r or p.y > bounds.end.y - r:
		return false
	for b in _boxes:
		var q := Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y))
		if p.distance_squared_to(q) < r * r:
			return false
	for c in _circles:
		var rr := c.z + r
		if p.distance_squared_to(Vector2(c.x, c.y)) < rr * rr:
			return false
	return true


## ระยะใกล้สุดจากจุดถึงที่กัน (เทสใช้ตรวจว่าทางไม่เฉียดเกิน radius)
func clearance(p: Vector2) -> float:
	var d := INF
	for b in _boxes:
		var q := Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y))
		d = minf(d, p.distance_to(q))
	for c in _circles:
		d = minf(d, p.distance_to(Vector2(c.x, c.y)) - c.z)
	return d


## เส้นตรง a → b ที่วงกลมรัศมี radius กวาดผ่านได้: ไม่แตะที่กันและอยู่ในขอบเขต (คิดตรง ไม่สุ่มจุด)
func clear_line(a: Vector2, b: Vector2) -> bool:
	var inner := Rect2(bounds.position + Vector2(radius, radius), bounds.size - Vector2(radius, radius) * 2.0)
	if not (inner.has_point(a) or _on_edge(inner, a)) or not (inner.has_point(b) or _on_edge(inner, b)):
		return false
	for c in _circles:
		if _seg_point_dist(a, b, Vector2(c.x, c.y)) < c.z + radius:
			return false
	for r in _boxes:
		# กล่องขยายด้วย radius = กากบาทสองกล่อง + วงกลมสี่มุม
		if _seg_hits_rect(a, b, r.grow_individual(radius, 0.0, radius, 0.0)) or _seg_hits_rect(a, b, r.grow_individual(0.0, radius, 0.0, radius)):
			return false
		for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			if _seg_point_dist(a, b, corner) < radius:
				return false
	return true


## ทางจาก from ถึง to: เส้นตรงสองจุดเมื่อโล่ง ไม่งั้น A* แล้วดึงเส้น · เป้าในช่องที่กันไว้ใช้ช่องว่างที่ใกล้สุดแทน
func find(from: Vector2, to: Vector2) -> PackedVector2Array:
	if clear_line(from, to):
		return PackedVector2Array([from, to])
	var s := nearest_free(cell_of(from))
	var gc := cell_of(to)
	var goal_ok := is_free(gc) and point_free(to, radius)
	var g := gc if goal_ok else nearest_free(gc)
	if s.x < 0 or g.x < 0:
		return PackedVector2Array([from])
	var end := to if goal_ok else centre(g)
	var cells := _astar(s, g)
	if cells.is_empty():
		# ไปไม่ถึง: ไปช่องที่ใกล้เป้าที่สุดในส่วนที่ถึงได้
		return PackedVector2Array([from])
	var raw := PackedVector2Array([from])
	for k in range(1, cells.size() - 1):
		raw.append(centre(cells[k]))
	raw.append(end)
	return _pull(raw)


## ช่องว่างที่ใกล้สุด (วนเป็นวงรอบออกไป; ระยะเท่ากันเลือกตามลำดับคงที่) · ไม่มีเลยคืน (-1, -1)
func nearest_free(c: Vector2i) -> Vector2i:
	if is_free(c):
		return c
	for ring in range(1, maxi(cols, rows)):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dj in range(-ring, ring + 1):
			for di in range(-ring, ring + 1):
				if maxi(absi(di), absi(dj)) != ring:
					continue
				var q := Vector2i(c.x + di, c.y + dj)
				if not is_free(q):
					continue
				var d := float(di * di + dj * dj)
				if d < best_d:
					best_d = d
					best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _astar(s: Vector2i, g: Vector2i) -> Array[Vector2i]:
	var n := cols * rows
	var gs := PackedFloat32Array()
	gs.resize(n)
	gs.fill(INF)
	var came := PackedInt32Array()
	came.resize(n)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var si := s.y * cols + s.x
	var gi := g.y * cols + g.x
	gs[si] = 0.0
	var heap_k := PackedFloat64Array()
	var heap_v := PackedInt32Array()
	_push(heap_k, heap_v, _key(_h(s, g), si), si)
	while heap_v.size() > 0:
		var cur := _pop(heap_k, heap_v)
		if closed[cur] == 1:
			continue
		if cur == gi:
			break
		closed[cur] = 1
		var cx := cur % cols
		var cy := cur / cols
		for d in DIRS:
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var ni := ny * cols + nx
			if free[ni] == 0 or closed[ni] == 1:
				continue
			# ทแยงได้เมื่อสองช่องข้างว่าง (ไม่ตัดมุม)
			if d.x != 0 and d.y != 0 and (free[cy * cols + nx] == 0 or free[ny * cols + cx] == 0):
				continue
			var step := 1.41421356 if d.x != 0 and d.y != 0 else 1.0
			var ng := gs[cur] + step
			if ng < gs[ni] - 0.00001:
				gs[ni] = ng
				came[ni] = cur
				_push(heap_k, heap_v, _key(ng + _h(Vector2i(nx, ny), g), ni), ni)
	if came[gi] < 0 and gi != si:
		return []
	var out: Array[Vector2i] = []
	var k := gi
	while k >= 0:
		out.push_front(Vector2i(k % cols, k / cols))
		if k == si:
			break
		k = came[k]
	return out


## ดึงเส้น: จากจุดปัจจุบันข้ามไปจุดไกลสุดที่ยังเห็นตรง ๆ
func _pull(raw: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([raw[0]])
	var i := 0
	while i < raw.size() - 1:
		var j := raw.size() - 1
		while j > i + 1 and not clear_line(raw[i], raw[j]):
			j -= 1
		out.append(raw[j])
		i = j
	return out


static func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return float(maxi(dx, dy)) + 0.41421356 * float(mini(dx, dy))


## ลำดับในกอง: ค่า f (ละเอียด 1/1000 ช่อง) แล้วเลขช่อง ทำให้ผลคงที่
static func _key(f: float, idx: int) -> float:
	return float(roundi(f * 1000.0)) * 8192.0 + float(idx)


static func _push(k: PackedFloat64Array, v: PackedInt32Array, key: float, val: int) -> void:
	k.append(key)
	v.append(val)
	var i := k.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if k[p] <= key:
			break
		k[i] = k[p]
		v[i] = v[p]
		i = p
	k[i] = key
	v[i] = val


static func _pop(k: PackedFloat64Array, v: PackedInt32Array) -> int:
	var top := v[0]
	var last_k := k[k.size() - 1]
	var last_v := v[v.size() - 1]
	k.resize(k.size() - 1)
	v.resize(v.size() - 1)
	var n := k.size()
	if n == 0:
		return top
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var r := l + 1
		var m := r if r < n and k[r] < k[l] else l
		if k[m] >= last_k:
			break
		k[i] = k[m]
		v[i] = v[m]
		i = m
	k[i] = last_k
	v[i] = last_v
	return top


static func _on_edge(r: Rect2, p: Vector2) -> bool:
	return p.x >= r.position.x - 0.0001 and p.y >= r.position.y - 0.0001 and p.x <= r.end.x + 0.0001 and p.y <= r.end.y + 0.0001


static func _seg_point_dist(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0000001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


## ส่วนของเส้นตัดสี่เหลี่ยม (เปิด) ไหม: ตัดช่วงตามแกน (Liang–Barsky)
static func _seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for axis in 2:
		var p0 := a.x if axis == 0 else a.y
		var dd := d.x if axis == 0 else d.y
		var lo := r.position.x if axis == 0 else r.position.y
		var hi := r.end.x if axis == 0 else r.end.y
		if absf(dd) < 0.0000001:
			if p0 <= lo or p0 >= hi:
				return false
			continue
		var ta := (lo - p0) / dd
		var tb := (hi - p0) / dd
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 >= t1:
			return false
	return true
