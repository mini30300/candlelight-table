class_name BtSquads
extends RefCounted
## เรื่องของหมู่ (R1_PORT_SPEC §1 squads): รัศมีฐาน จุดกลาง ระยะใกล้สุด ขอบฐาน ศัตรู ติดประชิด ครึ่งหมู่ และแถวยืน
## ตำแหน่งเป็น MI (ตำแหน่งกติกา) ระยะเทียบเป็นกำลังสองทั้งหมด ไม่มีการหาร
## ทุกการไล่หาเป็นลำดับใน squads / s.models (ลำดับเป็นกติกา)

## ติดประชิดเมื่อขอบฐานห่างไม่เกิน 1 นิ้ว + 1 MI (ENGAGE บวกหนึ่งในพันนิ้วของหน้าเก่า)
const ENGAGE_LIM := 1001
## รากของ 2^63 ปัดลง: ผลรวมที่ใหญ่กว่านี้ยกกำลังสองแล้วล้น
const _SUM_MAX := 3037000499


## รัศมีฐานของชนิดตามตำแหน่งใน TYPES (radOfType): ไม่รู้จักหรือไม่มี r ใช้ 800
static func radius_of(ti: int) -> int:
	var k := GameData.key_at(ti)
	if k == "":
		return GameData.BASE_R_MI
	var r := GameData.base_r_mi(k)
	# หน้าเก่าใช้ T.r || ค่าตั้งต้น: r เป็นศูนย์ก็ใช้ 800
	return r if r != 0 else GameData.BASE_R_MI


## รัศมีฐานของหมู่ (ทุกโมเดลในหมู่เป็นชนิดเดียวกับหมู่)
static func radius(s: BattleState.Squad) -> int:
	return radius_of(s.ti) if s != null else GameData.BASE_R_MI


## ยิง/เล็งใส่ได้ไหม (canTarget): ไม่ใช่ตัวเอง และ ฟรีฟาย หรือ คนละฝ่าย
static func can_target(st: BattleState, a: BattleState.Squad, b: BattleState.Squad) -> bool:
	if a == null or b == null or a == b:
		return false
	return true if st.free_fire else b.side != a.side


## จุดกลางของหมู่ (sqCenter) = js_round ของค่าเฉลี่ยทีละแกน; หมู่ว่างได้ [0, 0]
static func center(s: BattleState.Squad) -> PackedInt64Array:
	var n := s.models.size() if s != null else 0
	if n == 0:
		return PackedInt64Array([0, 0])
	var sx := 0
	var sz := 0
	for m: BattleState.Unit in s.models:
		sx += m.x
		sz += m.z
	return PackedInt64Array([Fx.js_round(sx, n), Fx.js_round(sz, n)])


## ระยะกำลังสองที่ใกล้ที่สุดระหว่างโมเดลสองหมู่ (sqDist กลางฐานถึงกลางฐาน); ฝั่งใดว่างได้ FAR2
static func dist2_min(a: BattleState.Squad, b: BattleState.Squad) -> int:
	if a == null or b == null or a.models.is_empty() or b.models.is_empty():
		return BattleState.FAR2
	var best := BattleState.FAR2
	for p: BattleState.Unit in a.models:
		for q: BattleState.Unit in b.models:
			var d2 := Fx.dist2(p.x, p.z, q.x, q.z)
			if d2 < best:
				best = d2
	return best


## ระยะใกล้สุดเป็น MI (ปัดลง) ใช้แสดงผลและบอทเท่านั้น; ฝั่งใดว่างได้ FAR2
static func dist_min(a: BattleState.Squad, b: BattleState.Squad) -> int:
	var d2 := dist2_min(a, b)
	return BattleState.FAR2 if d2 == BattleState.FAR2 else Fx.isqrt(d2)


## ขอบฐานถึงขอบฐาน (sqEdge) MI ปัดลง ติดลบได้เมื่อฐานซ้อน; ฝั่งใดว่างได้ FAR2
## เกณฑ์กติกาใช้ edge_within (เทียบกำลังสองตรงเป๊ะ) ไม่ใช้ค่านี้
static func edge(a: BattleState.Squad, b: BattleState.Squad) -> int:
	var d2 := dist2_min(a, b)
	if d2 == BattleState.FAR2:
		return BattleState.FAR2
	return Fx.isqrt(d2) - radius(a) - radius(b)


## ขอบฐานห่างไม่เกิน lim_mi ไหม (sqEdge <= lim): dist2_min <= (ra + rb + lim)^2 ตรงเป๊ะ
## ผลรวมติดลบ = ไม่มีระยะใดผ่าน; ฝั่งใดว่าง = false
static func edge_within(a: BattleState.Squad, b: BattleState.Squad, lim_mi: int) -> bool:
	if a == null or b == null or a.models.is_empty() or b.models.is_empty():
		return false
	var sum := radius(a) + radius(b) + lim_mi
	if sum < 0:
		return false
	if sum > _SUM_MAX:
		return true
	return dist2_min(a, b) <= sum * sum


## หมู่ที่ยิงได้ (foesOf): ยังอยู่ และ คนละฝ่าย หรือ (ฟรีฟาย และไม่ใช่ตัวเอง) ตามลำดับ squads
static func foes_of(st: BattleState, s: BattleState.Squad) -> Array[BattleState.Squad]:
	var out: Array[BattleState.Squad] = []
	if s == null:
		return out
	for q: BattleState.Squad in st.alive_squads():
		if q.side != s.side or (st.free_fire and q != s):
			out.append(q)
	return out


## ศัตรูจริง (realFoes): หมู่ที่ยังอยู่ของฝ่ายอื่น ตามลำดับ squads (ฟรีฟายไม่นับเพื่อน)
static func real_foes(st: BattleState, s: BattleState.Squad) -> Array[BattleState.Squad]:
	var out: Array[BattleState.Squad] = []
	if s == null:
		return out
	for q: BattleState.Squad in st.alive_squads():
		if q.side != s.side:
			out.append(q)
	return out


## ศัตรูที่ติดประชิดอยู่ (engagedWith) ตามลำดับ squads
static func engaged_with(st: BattleState, s: BattleState.Squad) -> Array[BattleState.Squad]:
	var out: Array[BattleState.Squad] = []
	for q: BattleState.Squad in real_foes(st, s):
		if edge_within(s, q, ENGAGE_LIM):
			out.append(q)
	return out


## ติดประชิดไหม (isEngaged) เจอตัวแรกก็หยุด
static func is_engaged(st: BattleState, s: BattleState.Squad) -> bool:
	if s == null:
		return false
	for q: BattleState.Squad in st.alive_squads():
		if q.side != s.side and edge_within(s, q, ENGAGE_LIM):
			return true
	return false


## เหลือไม่ถึงครึ่ง (sqHalf): โมเดลที่อยู่ x2 < n0 หรือ หมู่ตัวเดียวที่ hp x2 < w
static func half(s: BattleState.Squad) -> bool:
	if s == null:
		return false
	var alive := s.models.size()
	if alive * 2 < s.n0:
		return true
	if s.n0 != 1 or alive == 0:
		return false
	var t := GameData.ty(s.k)
	# หน้าเก่า TY(คีย์ที่ไม่รู้จัก) ได้ชนิดแรกของ TYPES
	if t.is_empty() and GameData.count() > 0:
		t = GameData.types()[0]
	# ไม่มี w: hp * 2 < undefined ของหน้าเก่าได้ false
	if not t.has("w"):
		return false
	var w: int = int(t["w"])
	return s.models[0].hp * 2 < w


## ตำแหน่งยืนของ n ตัวรอบ (cx, cz) หันไปทาง (fx, fz) ยาว 1000 รัศมีฐาน r (formation)
## แถวละไม่เกินสาม (สี่ตัวเป็นสองแถวสองตัว) แถว 0 อยู่หน้า ระยะห่าง max(1700, 2r + 350)
## ระยะจากจุดกลางปัดเป็น 10 MI (ครึ่งปัดขึ้นแบบ js_round): cx, cz อยู่บนตาราง 10 MI ผลก็อยู่บนตาราง
static func formation(n: int, cx: int, cz: int, fx: int, fz: int, r: int) -> Array[PackedInt64Array]:
	var out: Array[PackedInt64Array] = []
	if n <= 0:
		return out
	var gap := maxi(1700, 2 * r + 350)
	var per := n if n <= 3 else (2 if n == 4 else 3)
	# ปัดขึ้น (n, per เป็นบวก)
	var rows := (n + per - 1) / per
	for i: int in n:
		# i, per เป็นบวก หารตัดเศษ = ปัดลง
		var row := i / per
		var in_row := mini(per, n - row * per)
		var col := i - row * per
		# o2 = สองเท่าของระยะข้าง, b20 = ยี่สิบเท่าของระยะถอย (เก้าในสิบช่อง)
		var o2 := (2 * col - in_row + 1) * gap
		var b20 := (2 * row - rows + 1) * gap * 9
		var dx := 10 * Fx.js_round(fz * o2 * 10 - fx * b20, 200000)
		var dz := 10 * Fx.js_round(-fx * o2 * 10 - fz * b20, 200000)
		out.append(PackedInt64Array([cx + dx, cz + dz]))
	return out
