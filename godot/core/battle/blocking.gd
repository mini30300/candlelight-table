class_name BtBlocking
extends RefCounted
## พื้นที่ที่ยืนไม่ได้ (R1_PORT_SPEC หัวข้อ blocking.gd): รูปกีดขวางของสิ่งของ ขอบโต๊ะ ฐานทับกัน และการหาที่ว่างที่ใกล้ที่สุด
## ตามหน้าเก่า propBlocks / blockAt / crowded / freeSpot / roomToLand (31219–31339) แต่เทียบแบบจำนวนเต็มตรงเป๊ะ
## (กำลังสอง ไม่ถอดราก) มุมเป็น Q16 จาก FieldProps.sin_q / cos_q; ของที่เตรียมแล้วมีแต่ int กับ String (เข้า snapshot ได้)
## ระยะ "ไม่เกิน X บวกหนึ่งในพันนิ้ว" ของหน้าเก่าคือไม่เกิน (X + 1 MI) ยกกำลังสอง: เลขเดียวกัน ไม่ใช่ค่าเผื่อ

const ONE := 65536
## ขนาด s4 ของชิ้นขนาดเดิม (s4 = ขนาด x หมื่น)
const S4 := 10000
## รัศมีกีดขวางของชิ้นทรงกลม (MI ที่ขนาดเดิม); ศูนย์ = ยืนได้ (หลุม ซุ้ม พุ่มไม้)
const BLOCK_R_MI := {"crater": 0, "arch": 0, "bush": 0, "rubble": 1500, "barricade": 1500, "log": 1100, "pipe": 1900,
	"tower": 3000, "boulder": 2200, "iceslab": 2200, "obelisk": 1800, "buried": 1600, "tree": 1100, "deadtree": 1100,
	"pine": 1200}
## ชนิดที่ไม่รู้จัก
const BLOCK_R_DEFAULT := 2000
## ขอบโต๊ะ: ใกล้กว่านี้ยืนไม่ได้ (blockAt) / ที่ว่างต้องห่างขอบเท่านี้ (freeSpot)
const EDGE_BLOCK := 800
const EDGE_FREE := 1200
## รัศมีฐานเมื่อชนิดไม่มี r (หน้าเก่า radOfType)
const BASE_R := 800
## คีย์ตำแหน่งเสาทั้งสี่ของ pillars
const POSTS := [["p0x", "p0z"], ["p1x", "p1z"], ["p2x", "p2z"], ["p3x", "p3z"]]

## ตารางช่องของ props (ARCHITECTURE §4): ช่องละสี่นิ้ว เก็บเลขชิ้นที่กรอบ bb แตะช่อง
## จุดในรูปกีดขวางอยู่ในกรอบ bb ของชิ้นเสมอ block_at จึงได้ผลเท่ากับไล่ทุกชิ้น แค่เร็วกว่า
const CELL := 4000

## รัศมีฐานตามตำแหน่งใน TYPES (ไม่มี r หรือศูนย์ = 800) เก็บไว้ครั้งเดียว ข้อมูลไม่เปลี่ยนระหว่างเล่น
static var _rad_ti := PackedInt64Array()
## ตารางช่องที่สร้างล่าสุด และของชุดไหน: อาร์เรย์ props ตัวเดียวกัน จำนวน แฮช ขนาดโต๊ะ
## (set_props สร้างอาร์เรย์ใหม่ทุกครั้ง; แก้ props ทางอื่นผิดสัญญาของ state.gd อยู่แล้ว)
static var _g_props: Array[Dictionary] = []
static var _g_key := PackedInt64Array()
static var _g_nx := 1
static var _g_nz := 1
## ช่อง k มีเลขชิ้น _g_idx[_g_off[k] .. _g_off[k + 1] - 1] ตามลำดับใน props
static var _g_off := PackedInt32Array()
static var _g_idx := PackedInt32Array()


# ---------------------------------------------------------------- เตรียมรูปกีดขวาง
## ของจาก FieldProps เป็นรูปกีดขวาง ตามลำดับเดิม (s4 = ส่วนพัน x สิบ, ขนาดตึกจาก bld_size)
static func prep_field(fp: FieldProps) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in fp.items:
		var kind := str(o["kind"])
		var bw := 0
		var bd := 0
		if kind == "building":
			var b := fp.bld_size(o)
			bw = b[0]
			bd = b[1]
		out.append(prep_one(kind, int(o["x"]), int(o["z"]), int(o["rot"]), int(o["s"]) * 10, int(o["h"]), bw, bd))
	return out


## ชิ้นเดียว: ตำแหน่ง MI, มุม rot แบบ Q16, ขนาด s4 (ไม่เกินสองแสน ผลคูณจึงไม่ล้น), h แบบ Q16, ตึกกว้าง/ลึก MI ตามที่วาด
## bb = รัศมีที่ไกลกว่าทุกจุดที่ชิ้นนี้กันได้ (ตัดทิ้งเร็ว ไม่เปลี่ยนผล)
static func prep_one(kind: String, x: int, z: int, rot_q16: int, s4: int, h_q16: int, bw: int, bd: int) -> Dictionary:
	var c := FieldProps.cos_q(rot_q16)
	var sn := FieldProps.sin_q(rot_q16)
	var o := {"kind": kind, "x": x, "z": z, "c": c, "sn": sn, "s4": s4, "h": h_q16}
	var bb := 0
	match kind:
		"building":
			o["bw"] = bw
			o["bd"] = bd
			bb = _turned_reach(Fx.cdiv(bw + 1400, 2), Fx.cdiv(bd + 1400, 2))
		"wall":
			# หน้าเก่า: สามช่อง บวก h x 3 ปัดแบบ Math.round ช่องละ 2400 x s MI
			var segs := 3 + Fx.js_round(3 * h_q16, ONE)
			o["segs"] = segs
			bb = _turned_reach(Fx.cdiv(segs * 1200 * s4 + 600 * S4, S4), Fx.cdiv(900 * s4 + 600 * S4, S4))
		"pillars":
			# เสาสี่ต้นห่างกลาง 3200 x s MI ที่มุม rot + k/4 รอบ: (c, sn) (-sn, c) (-c, -sn) (sn, -c)
			var vs := [[c, sn], [-sn, c], [-c, -sn], [sn, -c]]
			var reach := 0
			for k: int in 4:
				var v: Array = vs[k]
				var px := Fx.js_round(int(v[0]) * 3200 * s4, ONE * S4)
				var pz := Fx.js_round(int(v[1]) * 3200 * s4, ONE * S4)
				o[POSTS[k][0]] = px
				o[POSTS[k][1]] = pz
				reach = maxi(reach, Fx.isqrt_ceil(px * px + pz * pz))
			bb = reach + Fx.cdiv(1300 * s4, S4) + 1
		_:
			var rb: int = BLOCK_R_MI.get(kind, BLOCK_R_DEFAULT)
			o["rb"] = rb
			bb = Fx.cdiv(rb * s4 + 600 * S4, S4) if rb > 0 else 0
	o["bb"] = bb
	return o


## รัศมีครอบสี่เหลี่ยมครึ่งกว้าง hx ครึ่งลึก hz ที่หมุนด้วย cos/sin แบบ Q16 (ยาวคลาดจากหนึ่งได้ไม่ถึงหนึ่งในพัน จึงเผื่อ)
static func _turned_reach(hx: int, hz: int) -> int:
	var r := Fx.isqrt_ceil(hx * hx + hz * hz)
	return r + Fx.cdiv(r, 1024) + 2


# ---------------------------------------------------------------- กันที่ยืน
## propBlocks: จุด (x, z) อยู่ในรูปกีดขวางของชิ้น o หรือไม่
static func prop_blocks(o: Dictionary, x: int, z: int) -> bool:
	var dx: int = x - int(o["x"])
	var dz: int = z - int(o["z"])
	var bb: int = o["bb"]
	if absi(dx) > bb or absi(dz) > bb or dx * dx + dz * dz > bb * bb:
		return false
	return _hit(o, dx, dz)


## รูปกีดขวางแบบตรงเป๊ะ (dx, dz จากกลางชิ้น MI) เรียกหลังผ่าน bb แล้วเท่านั้น: ผลคูณราว 25e14 ที่ขนาดปกติ
## และไม่เกิน 1e18 เมื่อ s4 ไม่เกินสองแสน (ต่ำกว่า 2^63)
## เป็น MI: ตึก |lx| < bw/2 + 700 · กำแพง |ax| < ช่อง x 1200 s + 600 และ |az| < 900 s + 600 · เสา ห่างเสาใดน้อยกว่า 1300 s
## ชิ้นกลม ห่างกลางน้อยกว่า r x s + 600 (s = s4 / หมื่น)
static func _hit(o: Dictionary, dx: int, dz: int) -> bool:
	var s4: int = o["s4"]
	match str(o["kind"]):
		"building":
			var c: int = o["c"]
			var sn: int = o["sn"]
			var lx := dx * c - dz * sn
			var lz := dx * sn + dz * c
			return absi(2 * lx) < (int(o["bw"]) + 1400) * ONE and absi(2 * lz) < (int(o["bd"]) + 1400) * ONE
		"wall":
			var c: int = o["c"]
			var sn: int = o["sn"]
			var ax := dx * c - dz * sn
			var az := dx * sn + dz * c
			return absi(ax) * S4 < (int(o["segs"]) * 1200 * s4 + 600 * S4) * ONE and absi(az) * S4 < (900 * s4 + 600 * S4) * ONE
		"pillars":
			var lim := 1300 * s4
			for k: int in 4:
				var ex: int = dx - int(o[POSTS[k][0]])
				var ez: int = dz - int(o[POSTS[k][1]])
				if (ex * ex + ez * ez) * 100000000 < lim * lim:
					return true
			return false
	var rb: int = o["rb"]
	if rb <= 0:
		return false
	var lim2 := rb * s4 + 600 * S4
	return (dx * dx + dz * dz) * 100000000 < lim2 * lim2


## blockAt: นอกโต๊ะ (ใกล้ขอบกว่า 800 MI) หรือในรูปกีดขวางชิ้นใดก็ได้ (ผลไม่ขึ้นกับลำดับ)
static func block_at(st: BattleState, x: int, z: int) -> bool:
	if absi(x) > st.w * 500 - EDGE_BLOCK or absi(z) > st.d * 500 - EDGE_BLOCK:
		return true
	return _props_block(st, x, z)


## ชิ้นใดกันจุด (x, z) ที่อยู่บนโต๊ะแล้ว: ดูเฉพาะชิ้นในช่องของจุด
static func _props_block(st: BattleState, x: int, z: int) -> bool:
	_grid(st)
	var ci := Fx.clampi(Fx.idiv(x + st.w * 500, CELL), 0, _g_nx - 1)
	var cj := Fx.clampi(Fx.idiv(z + st.d * 500, CELL), 0, _g_nz - 1)
	var k := cj * _g_nx + ci
	for t: int in range(_g_off[k], _g_off[k + 1]):
		if prop_blocks(st.props[_g_idx[t]], x, z):
			return true
	return false


## สร้างตารางช่องใหม่เมื่อ props หรือขนาดโต๊ะเปลี่ยน (นับก่อนแล้วเติม เลขชิ้นในช่องเรียงตาม props)
static func _grid(st: BattleState) -> void:
	var key := PackedInt64Array([st.props.size(), st.props_hash, st.w, st.d])
	if is_same(_g_props, st.props) and _g_key == key:
		return
	var hw := st.w * 500
	var hd := st.d * 500
	var nx := maxi(1, Fx.cdiv(2 * hw, CELL))
	var nz := maxi(1, Fx.cdiv(2 * hd, CELL))
	var box := PackedInt64Array()
	var count := PackedInt32Array()
	count.resize(nx * nz + 1)
	for i: int in st.props.size():
		var o := st.props[i]
		var bb: int = o["bb"]
		var px: int = o["x"]
		var pz: int = o["z"]
		var i0 := maxi(0, Fx.idiv(px - bb + hw, CELL))
		var i1 := mini(nx - 1, Fx.idiv(px + bb + hw, CELL))
		var j0 := maxi(0, Fx.idiv(pz - bb + hd, CELL))
		var j1 := mini(nz - 1, Fx.idiv(pz + bb + hd, CELL))
		# bb ศูนย์ (หลุม ซุ้ม พุ่มไม้) หรือกรอบอยู่นอกโต๊ะทั้งหมด: ไม่กันจุดใดบนโต๊ะ
		if bb <= 0 or i0 > i1 or j0 > j1:
			box.append_array(PackedInt64Array([1, 0, 1, 0]))
			continue
		box.append_array(PackedInt64Array([i0, i1, j0, j1]))
		for j: int in range(j0, j1 + 1):
			for ii: int in range(i0, i1 + 1):
				count[j * nx + ii + 1] += 1
	for k: int in range(1, count.size()):
		count[k] += count[k - 1]
	var idx := PackedInt32Array()
	idx.resize(count[count.size() - 1])
	var fill := count.duplicate()
	for i: int in st.props.size():
		for j: int in range(box[4 * i + 2], box[4 * i + 3] + 1):
			for ii: int in range(box[4 * i], box[4 * i + 1] + 1):
				idx[fill[j * nx + ii]] = i
				fill[j * nx + ii] += 1
	_g_props = st.props
	_g_key = key
	_g_nx = nx
	_g_nz = nz
	_g_off = count
	_g_idx = idx


## รัศมีฐานตามตำแหน่งใน TYPES (ค่าจาก BtSquads.radius_of ที่เดียว เก็บไว้ให้ crowded เร็ว)
static func _radii() -> PackedInt64Array:
	var n := GameData.count()
	if _rad_ti.size() != n:
		_rad_ti.resize(n)
		for i: int in n:
			_rad_ti[i] = BtSquads.radius_of(i)
	return _rad_ti


## รัศมีฐานของโมเดล (radOfType: ไม่มี r หรือเป็นศูนย์ = 800)
static func unit_rad(u: BattleState.Unit) -> int:
	var rt := _radii()
	return rt[u.ti] if u.ti >= 0 and u.ti < rt.size() else BASE_R


## รัศมีของตัวที่กำลังวาง: r_mi < 0 = หน้าเก่าไม่ส่ง r (ใช้ของ skip หรือ 800)
static func _me(skip: BattleState.Unit, r_mi: int) -> int:
	if r_mi >= 0:
		return r_mi
	return unit_rad(skip) if skip != null else BASE_R


## crowded: ฐานรัศมี r ที่ (x, z) ทับฐานโมเดลอื่นตัวใด (ไม่นับ skip) — ห่างน้อยกว่าผลรวมรัศมีพอดีคือทับ
static func crowded(st: BattleState, x: int, z: int, skip: BattleState.Unit, r_mi: int) -> bool:
	var me := _me(skip, r_mi)
	var rt := _radii()
	var n := rt.size()
	for q: BattleState.Unit in st.units:
		if q == skip:
			continue
		var rr := me + (rt[q.ti] if q.ti >= 0 and q.ti < n else BASE_R)
		# ห่างตามแกนเกินผลรวมรัศมีก็ไม่ทับแน่ (ตัดก่อนคูณ)
		var dx := q.x - x
		if dx >= rr or dx <= -rr:
			continue
		var dz := q.z - z
		if dz >= rr or dz <= -rr:
			continue
		if dx * dx + dz * dz < rr * rr:
			return true
	return false


# ---------------------------------------------------------------- หาที่ว่าง
## จำนวนวงของการหาแบบกว้าง: เส้นทแยงโต๊ะหารด้วยวงละ 1250 MI ปัดขึ้น (w, d เป็นนิ้ว เท่าหน้าเก่าทุกขนาด)
static func far_rings(w_in: int, d_in: int) -> int:
	return Fx.cdiv(Fx.isqrt_ceil((w_in * w_in + d_in * d_in) * 1000000), 1250)


## freeSpot: ที่ว่างที่ใกล้ (x, z) ที่สุด วนออกทีละวง; from = จุดเริ่มเดิน (ว่าง = ไม่จำกัด) กับเพดาน max_d (MI)
## ลำดับ: จุดเดิม → สิบวงใกล้ (BtOffsets.FREESPOT_NEAR) → ถ้ามี from แล้วไม่เจอ คืนว่าง (หน้าเก่า null)
## → วงกว้าง 11..far ห้ามทับฐาน แล้ว 1..far ยอมทับฐาน → จุดเดิม; จุดเข้า (x, z) บนกริดสิบ MI ผลก็บนกริดสิบ
static func free_spot(st: BattleState, x: int, z: int, skip: BattleState.Unit, from: PackedInt64Array, max_d: int,
		rad: int) -> PackedInt64Array:
	var p := _Probe.new()
	p.init(st, skip, from, max_d, rad)
	if p.edge_ok(x, z) and p.from_ok(x, z) and not block_at(st, x, z) and not crowded(st, x, z, skip, rad):
		return PackedInt64Array([x, z])
	p.pack()
	for o: Array in BtOffsets.FREESPOT_NEAR:
		var nx: int = x + int(o[0])
		var nz: int = z + int(o[1])
		if p.ok(nx, nz, true):
			return PackedInt64Array([nx, nz])
	if p.has_from:
		return PackedInt64Array()
	var far := far_rings(st.w, st.d)
	for pass_no: int in 2:
		var r := 1 if pass_no == 1 else 11
		while r <= far:
			var n := BtOffsets.fs_ring_n(r)
			# มุมเริ่มของวง = r x 41/100 เรเดียน ปัดเป็น Q16 ทีละวง (คลาดไม่ถึงครึ่งหน่วย) ไม่ใช่ r x FS_ANG_STEP
			# ที่คลาดสะสมจนจุดที่วงไกลเลื่อนเป็นร้อย MI
			var t0 := Fx.js_round(r * 41 * ONE, 100)
			for a: int in n:
				var th := Fx.idiv(a * FieldProps.TWO_PI, n) + t0
				var nx := x + 10 * Fx.js_round(FieldProps.cos_q(th) * r * 125, ONE)
				var nz := z + 10 * Fx.js_round(FieldProps.sin_q(th) * r * 125, ONE)
				if p.ok(nx, nz, pass_no == 0):
					return PackedInt64Array([nx, nz])
			r += 1
	return PackedInt64Array([x, z])


## roomToLand: ปักจุดลงสนามที่ (x, z) ได้ไหม — ตัวจุดว่าง หรือมีจุดลองรอบ ๆ (สองวง) ที่ว่างสักจุด
static func room_to_land(st: BattleState, x: int, z: int) -> bool:
	if not block_at(st, x, z):
		return true
	for o: Array in BtOffsets.ROOM_TO_LAND:
		if not block_at(st, x + int(o[0]), z + int(o[1])):
			return true
	return false


## ตัวช่วยของ free_spot: เก็บขอบและโมเดลเป็นอาร์เรย์ครั้งเดียวต่อการค้น (ของใช้ตารางช่อง) ผลเท่ากับ block_at / crowded
class _Probe extends RefCounted:
	var st: BattleState
	var skip: BattleState.Unit
	var me := 0
	var lw := 0
	var ld := 0
	var bw := 0
	var bd := 0
	var has_from := false
	var fx := 0
	var fz := 0
	## เพดานระยะกำลังสอง; -1 = ไม่มีจุดใดผ่าน (หน้าเก่า maxD ติดลบเกินหนึ่ง MI)
	var lim2 := 0
	var ux := PackedInt64Array()
	var uz := PackedInt64Array()
	var ur2 := PackedInt64Array()

	func init(s: BattleState, sk: BattleState.Unit, from: PackedInt64Array, max_d: int, rad: int) -> void:
		st = s
		skip = sk
		me = BtBlocking._me(sk, rad)
		lw = s.w * 500 - BtBlocking.EDGE_FREE
		ld = s.d * 500 - BtBlocking.EDGE_FREE
		bw = s.w * 500 - BtBlocking.EDGE_BLOCK
		bd = s.d * 500 - BtBlocking.EDGE_BLOCK
		has_from = from.size() >= 2
		if has_from:
			fx = from[0]
			fz = from[1]
			# เพดานเกินพันล้าน MI ก็คือไม่จำกัด (กันกำลังสองล้น)
			var md := mini(max_d, 1000000000)
			lim2 = (md + 1) * (md + 1) if md >= -1 else -1

	func edge_ok(x: int, z: int) -> bool:
		return absi(x) <= lw and absi(z) <= ld

	func from_ok(x: int, z: int) -> bool:
		return not has_from or Fx.dist2(x, z, fx, fz) <= lim2

	func pack() -> void:
		for q: BattleState.Unit in st.units:
			if q == skip:
				continue
			var rr := me + BtBlocking.unit_rad(q)
			ux.append(q.x)
			uz.append(q.z)
			ur2.append(rr * rr)

	func ok(x: int, z: int, crowd: bool) -> bool:
		if absi(x) > lw or absi(z) > ld:
			return false
		if has_from and Fx.dist2(x, z, fx, fz) > lim2:
			return false
		if absi(x) > bw or absi(z) > bd or BtBlocking._props_block(st, x, z):
			return false
		if crowd:
			for i: int in ux.size():
				var ex := x - ux[i]
				var ez := z - uz[i]
				if ex * ex + ez * ez < ur2[i]:
					return false
		return true
