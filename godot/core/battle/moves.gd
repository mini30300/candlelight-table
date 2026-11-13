class_name BtMoves
extends RefCounted
## การเดิน (R1_PORT_SPEC หัวข้อ moves.gd): ระยะเดิน ใกล้ศัตรู ที่ว่าง แผนเดินทั้งหมู่ เดินจริง ลองสั่งเดิน เดินเป็นกอง จุดบุก
## ตามหน้าเก่า moveRange / nearFoe / spotFree / planMove / applySMove / tryMoveSq / groupMove / chargeSpots
## ตำแหน่งเป็น MI จุดที่ลองทุกจุดอยู่บนกริดสิบ MI แล้ว (จุดที่ตรวจ = จุดที่ส่ง) ระยะเทียบเป็นกำลังสองทั้งหมด
## ทิศเป็นเวกเตอร์ยาวพัน (Fx.norm1000) หมุนด้วยตาราง [cos, sin] แบบ Q16 ของ BtOffsets ไม่มีตรีโกณ
## ข้อความเหตุผลเป็นคีย์ {key, args} ฝั่ง UI แปลเป็นข้อความไทยของหน้าเก่า

## ใกล้ศัตรู: ขอบฐานห่างไม่เกิน ENGAGE บวก 50 MI (ระยะเผื่อของกติกาหน้าเก่า ไม่ใช่ค่าคลาดของทศนิยม, §9 D4)
const NEAR_PAD := 1050
## เดินจริงเมื่อจุดใหม่ห่างที่เดิมเกิน 50 MI (กำลังสอง)
const STEP_D2 := 2500
## นับว่าขยับ / หันตามเป้า เมื่อเกิน 300 MI (กำลังสอง)
const MOVED_D2 := 90000
## สั่งไกลกว่าระยะเดินได้ไม่เกิน 2500 MI (tryMoveSq)
const TRY_PAD := 2500
## จุดในวงรอบช่อง และเป้าของการเดินเป็นกอง ต้องห่างขอบโต๊ะ 1200 MI
const PLAN_EDGE := 1200
## ทางเลี่ยงเฉียงต้องใกล้ช่องกว่าระยะช่องลบ 300 MI
const SIDE_PAD := 300
## จุดบุก: ห่างกลางฐานเป้าเท่ารัศมีสองฐานบวก 300 MI
const CHARGE_PAD := 300
## เป้าของการเดินเป็นกองไกลสุดเท่านี้ (ไกลกว่าโต๊ะใด ๆ มาก แค่กันเลขล้น)
const GROUP_FAR := 1000000
const ONE := 65536


# ---------------------------------------------------------------- ระยะ
## ข้อมูลชนิด (TY ของหน้าเก่า: คีย์ที่ไม่รู้จักได้ชนิดแรกของ TYPES)
static func _ty(k: String) -> Dictionary:
	var t := GameData.ty(k)
	if t.is_empty() and GameData.count() > 0:
		return GameData.types()[0]
	return t


## moveRange: ระยะเดิน MI = mv บวกแต้มวิ่งเมื่อวิ่งแล้ว
static func move_range(s: BattleState.Squad) -> int:
	if s == null:
		return 0
	var mv: int = int(_ty(s.k).get("mv", 0))
	return (mv + (s.adv_r if s.adv else 0)) * 1000


## ปัดเข้ากริดสิบ MI (ครึ่งปัดขึ้นแบบ js_round)
static func snap(v: int) -> int:
	return 10 * Fx.js_round(v, 10)


## จุด (dx, dz) อยู่ในระยะ lim ไหม: inclusive = ไม่เกิน, ไม่ inclusive = น้อยกว่า (ตัดตามแกนก่อนคูณ)
static func _within(dx: int, dz: int, lim: int, inclusive: bool) -> bool:
	if lim < 0 or (lim == 0 and not inclusive):
		return false
	if dx > lim or dx < -lim or dz > lim or dz < -lim:
		return false
	var d2 := dx * dx + dz * dz
	return d2 <= lim * lim if inclusive else d2 < lim * lim


## nearFoe: ฐานรัศมี r ที่ (x, z) อยู่ในระยะประชิดโมเดลฝ่ายอื่นตัวใด: d2 <= (r + r_q + 1050)^2
## (เพื่อนร่วมทีมไม่นับแม้ฟรีฟาย ตามหน้าเก่า)
static func near_foe(st: BattleState, s: BattleState.Squad, x: int, z: int, r: int) -> bool:
	if s == null:
		return false
	for q: BattleState.Unit in st.units:
		if q.side == s.side:
			continue
		if _within(q.x - x, q.z - z, r + BtBlocking.unit_rad(q) + NEAR_PAD, true):
			return true
	return false


## spotFree: ฐานรัศมี r ของหมู่ s ยืนที่ (x, z) ได้ไหม — ไม่ติดสิ่งกีดขวาง ไม่ใกล้ศัตรู ไม่ทับฐานโมเดลอื่น
## (ตัวในหมู่ s เองไม่นับ เพราะกำลังจะเดิน) และห่างจุดที่ตัวก่อนหน้าจองไว้ (chosen) ไม่น้อยกว่าสองเท่ารัศมี
static func spot_free(st: BattleState, s: BattleState.Squad, x: int, z: int, r: int, chosen: Array[PackedInt64Array]) -> bool:
	if s == null:
		return false
	if BtBlocking.block_at(st, x, z) or near_foe(st, s, x, z, r):
		return false
	for q: BattleState.Unit in st.units:
		if q.sq == s.id:
			continue
		if _within(q.x - x, q.z - z, r + BtBlocking.unit_rad(q), false):
			return false
	for p: PackedInt64Array in chosen:
		if _within(p[0] - x, p[1] - z, 2 * r, false):
			return false
	return true


## หมุนเวกเตอร์ (x, z) ด้วยมุมจากตาราง [c, s] แบบ Q16: บวก = (x c + z s, z c - x s), ลบ = (x c - z s, z c + x s)
## (sin/cos ของ a0 บวกลบมุม เมื่อ a0 มาจาก atan2 ของ x กับ z) ผลไปเป็นตำแหน่งจึงปัดแบบ js_round ไม่ใช่เลื่อนบิต
static func turn(x: int, z: int, c: int, s: int, plus: bool) -> PackedInt64Array:
	if plus:
		return PackedInt64Array([Fx.js_round(x * c + z * s, ONE), Fx.js_round(z * c - x * s, ONE)])
	return PackedInt64Array([Fx.js_round(x * c - z * s, ONE), Fx.js_round(z * c + x * s, ONE)])


## ทิศยาวพันจาก (dx, dz); เวกเตอร์ศูนย์ได้ (0, 1000) (atan2 ของศูนย์ของหน้าเก่าเป็นมุมศูนย์)
static func _dir(dx: int, dz: int) -> PackedInt64Array:
	var v := Fx.norm1000(dx, dz)
	if v[0] == 0 and v[1] == 0:
		return PackedInt64Array([0, 1000])
	return v


# ---------------------------------------------------------------- แผนเดิน
## planMove: จุดยืนใหม่ของทุกตัวตามลำดับ s.models เมื่อสั่งไปที่ (x, z) (ไม่แตะสถานะ)
## หันตามทิศจากจุดกลางไปเป้าเมื่อไกลเกิน 300 MI ไม่งั้นหันตามหมู่; จัดแถวรอบเป้า แต่ละตัวเลือกช่องที่ว่างอยู่ที่ใกล้สุด
## (เท่ากันเอาช่องแรก) แล้วลองตามลำดับ: ช่องกับวงรอบช่อง (PLAN_RING ในระยะเดิน ห่างขอบโต๊ะ 1200 MI) → ตรงจากที่เดิม
## ไปทางช่องสิบขั้น (ไม่ดูระยะและขอบ เหมือนหน้าเก่า) → เฉียงซ้ายขวาแปดทิศ ห้าระยะ ลองครบทุกจุด เอาที่ใกล้ช่องสุด
## (ต้องใกล้กว่าระยะช่องลบ 300 MI) → ยืนที่เดิม
## เป้าปัดเข้ากริดสิบ MI ก่อน (เป้าจากสายอยู่บนกริดอยู่แล้ว) จุดที่ลองทุกจุดจึงอยู่บนกริดเมื่อตัวหมากอยู่บนกริด
static func plan_move(st: BattleState, s: BattleState.Squad, x: int, z: int) -> Array[PackedInt64Array]:
	var out: Array[PackedInt64Array] = []
	if s == null or s.models.is_empty():
		return out
	var tx := snap(x)
	var tz := snap(z)
	var ms := s.models
	var n := ms.size()
	var r := BtSquads.radius(s)
	var rng := move_range(s)
	var c := BtSquads.center(s)
	var fx := s.fx
	var fz := s.fz
	var ex := tx - c[0]
	var ez := tz - c[1]
	if ex * ex + ez * ez > MOVED_D2:
		var f := Fx.norm1000(ex, ez)
		fx = f[0]
		fz = f[1]
	elif fx == 0 and fz == 0:
		fz = 1000
	var slots := BtSquads.formation(n, tx, tz, fx, fz, r)
	var used := PackedInt32Array()
	used.resize(n)
	var probe := _Free.new()
	probe.init(st, s, r)
	# จุดที่ลองทุกแบบของโมเดล m อยู่ห่าง m ไม่เกิน reach (วง: ระยะเดิน + 1, ตรง: + 9, เฉียง: x 1002/1000 + 8)
	var reach := absi(rng) + absi(rng) / 100 + 1000
	var lim2 := (rng + 1) * (rng + 1)
	var ew := st.w * 500 - PLAN_EDGE
	var ed := st.d * 500 - PLAN_EDGE
	var chosen: Array[PackedInt64Array] = []
	for i: int in n:
		var m := ms[i]
		var best := -1
		var bd := 0
		for j: int in n:
			if used[j] != 0:
				continue
			var d2 := Fx.dist2(slots[j][0], slots[j][1], m.x, m.z)
			if best < 0 or d2 < bd:
				best = j
				bd = d2
		used[best] = 1
		var sx: int = slots[best][0]
		var sz: int = slots[best][1]
		probe.focus(m.x, m.z, reach)
		var spot := PackedInt64Array()
		# ระยะเดินติดลบเกินหนึ่ง MI (ไม่เกิดจากข้อมูลจริง) ไม่มีจุดในวงผ่าน เหมือนหน้าเก่า
		if rng >= -1:
			for o: Array in BtOffsets.PLAN_RING:
				var px: int = sx + int(o[0])
				var pz: int = sz + int(o[1])
				if Fx.dist2(px, pz, m.x, m.z) > lim2:
					continue
				if absi(px) > ew or absi(pz) > ed:
					continue
				if probe.open_at(px, pz, chosen):
					spot = PackedInt64Array([px, pz])
					break
		if spot.is_empty():
			spot = _fallback(probe, m, sx, sz, rng, chosen)
		chosen.append(spot)
		out.append(spot)
	return out


## ทางสำรองของ planMove เมื่อช่องกับวงรอบช่องไม่ว่าง: ตรงจากที่เดิมไปทางช่อง แล้วเฉียง แล้วที่เดิม
static func _fallback(probe: _Free, m: BattleState.Unit, sx: int, sz: int, rng: int,
		chosen: Array[PackedInt64Array]) -> PackedInt64Array:
	var dx := sx - m.x
	var dz := sz - m.z
	# ระยะถึงช่อง (ศูนย์ใช้ 1000 แบบ || 1 ของหน้าเก่า)
	var le := Fx.isqrt(dx * dx + dz * dz)
	if le == 0:
		le = 1000
	var f := mini(rng, le)
	for k: int in range(10, 0, -1):
		var qx := m.x + 10 * Fx.js_round(dx * f * k, le * 100)
		var qz := m.z + 10 * Fx.js_round(dz * f * k, le * 100)
		if probe.open_at(qx, qz, chosen):
			return PackedInt64Array([qx, qz])
	var spot := PackedInt64Array([m.x, m.z])
	var lim := le - SIDE_PAD
	if lim <= 0:
		return spot
	var best2 := lim * lim
	var v0 := _dir(dx, dz)
	for a: int in range(1, 9):
		# มุม ceil ของ a/2 คูณสี่ในสิบเรเดียน: a คี่เบี่ยงบวก a คู่เบี่ยงลบ (a เป็นบวก หารตัดเศษ = ปัดลง)
		var rot: Array = BtOffsets.SIDESTEP_ROT[(a - 1) / 2]
		var v := turn(v0[0], v0[1], int(rot[0]), int(rot[1]), a % 2 == 1)
		for k: int in range(5, 0, -1):
			var qx := m.x + 10 * Fx.js_round(v[0] * rng * k, 50000)
			var qz := m.z + 10 * Fx.js_round(v[1] * rng * k, 50000)
			var dd := Fx.dist2(sx, sz, qx, qz)
			if dd < best2 and probe.open_at(qx, qz, chosen):
				best2 = dd
				spot = PackedInt64Array([qx, qz])
	return spot


## ตัวแผนเดินขยับจากที่เดิมเกิน 300 MI สักตัวไหม (จับคู่ตามลำดับ s.models)
static func moves_any(s: BattleState.Squad, to: Array[PackedInt64Array]) -> bool:
	if s == null:
		return false
	for i: int in mini(s.models.size(), to.size()):
		var m := s.models[i]
		if Fx.dist2(to[i][0], to[i][1], m.x, m.z) > MOVED_D2:
			return true
	return false


## จุดเป็นแถว [x, z] ของ act (รูปของ core: Array ของ int สองตัว)
static func pts(to: Array[PackedInt64Array]) -> Array:
	var out: Array = []
	for p: PackedInt64Array in to:
		out.append([p[0], p[1]])
	return out


## จุดหนึ่งจาก to ของ act: Array หรือ Packed ที่มีสองค่า; อย่างอื่นเป็น [0, 0] ตามตัวกรองของเซิร์ฟเวอร์
static func point(v: Variant) -> PackedInt64Array:
	var t := typeof(v)
	if t == TYPE_ARRAY or t == TYPE_PACKED_INT64_ARRAY or t == TYPE_PACKED_INT32_ARRAY:
		var a := Array(v)
		if a.size() >= 2 and typeof(a[0]) == TYPE_INT and typeof(a[1]) == TYPE_INT:
			return PackedInt64Array([int(a[0]), int(a[1])])
	return PackedInt64Array([0, 0])


# ---------------------------------------------------------------- เดินจริง
## unitGoTo (ส่วนกติกา): ตั้งตำแหน่งกติกา ไม่ให้เลยขอบโต๊ะ (การเดินบนจอเป็นเรื่องของฝั่งภาพ)
static func go_to(st: BattleState, u: BattleState.Unit, x: int, z: int) -> void:
	if u == null:
		return
	u.x = Fx.clampi(x, -st.w * 500, st.w * 500)
	u.z = Fx.clampi(z, -st.d * 500, st.d * 500)


## applySMove: เดินตามจุดที่ส่งมา จับคู่ s.models กับ to ตามลำดับ ตัวที่ห่างเกิน 50 MI จึงเดินจริง (MOVE_STEP)
## ตั้ง moved; มีตัวขยับเกิน 50 MI เลิก still; ถอย (fb) ตั้ง fell; จุดกลางเลื่อนเกิน 300 MI หันหมู่ตามทางที่เดิน
## หมู่ที่เดินแล้วไม่ทำอะไร; to ว่างก็ไม่ทำอะไร (หน้าเก่าไม่เคยเรียกด้วย to ว่าง netAct ข้ามไป moved จึงยังเป็น false)
## บันทึก smove_fb / smove_adv / smove_move [หมู่, ระยะไกลสุด MI]
static func apply_smove(st: BattleState, s: BattleState.Squad, to: Array, how: String, out: Array[Dictionary]) -> void:
	if s == null or s.moved or to.is_empty():
		return
	var c0 := BtSquads.center(s)
	var far2 := 0
	for i: int in mini(s.models.size(), to.size()):
		var m := s.models[i]
		var p := point(to[i])
		var d2 := Fx.dist2(m.x, m.z, p[0], p[1])
		if d2 > far2:
			far2 = d2
		if d2 > STEP_D2:
			go_to(st, m, p[0], p[1])
			out.append(Events.make(Events.Id.MOVE_STEP, {"uid": m.id, "gx": m.x, "gz": m.z}))
	s.moved = true
	if far2 > STEP_D2:
		s.still = false
	if how == "fb":
		s.fell = true
	var c1 := BtSquads.center(s)
	var ex := c1[0] - c0[0]
	var ez := c1[1] - c0[1]
	if ex * ex + ez * ez > MOVED_D2:
		var f := Fx.norm1000(ex, ez)
		s.fx = f[0]
		s.fz = f[1]
	var key := "smove_fb" if how == "fb" else ("smove_adv" if s.adv else "smove_move")
	_log(st, out, key, [s.id, Fx.isqrt(far2)])


static func _log(st: BattleState, out: Array[Dictionary], key: String, args: Array) -> void:
	st.say(key, args)
	out.append(Events.make(Events.Id.LOG_LINE, {"key": key, "args": args.duplicate()}))


static func _why(key: String, args: Array) -> Dictionary:
	return {"key": key, "args": args, "act": {}}


## tryMoveSq: ลองสั่งหมู่ s ไปที่ (x, z) คืน {key, args, act}: key ว่าง = ทำได้ และ act คือ smove ที่ต้องส่ง
## (ไม่แตะสถานะ ผู้เรียกส่ง act เข้า apply เอง) fall_back = ผู้เล่นกดถอยแล้ว (G.act fb ของหน้าเก่า)
## เหตุผลตามลำดับหน้าเก่า: already_moved · engaged_need_fb · too_far [ระยะ MI, ระยะเดินเป็นนิ้ว] (ไกลกว่าระยะเดิน
## บวก 2500 MI จากจุดกลาง) · blocked (เป้าติดสิ่งกีดขวาง) · แผนไม่มีใครขยับเกิน 300 MI: cant_fall_back (ติดประชิด) /
## near_foe (เป้าใกล้ศัตรู) / no_room · ถอยแล้วยังมีจุดใกล้ศัตรู: fb_not_clear; ไม่มีหมู่: no_squad
## เป้าปัดเข้ากริดสิบ MI ก่อนตรวจ (ตรงกับที่ plan_move ใช้)
static func try_move(st: BattleState, s: BattleState.Squad, x: int, z: int, fall_back: bool) -> Dictionary:
	if s == null:
		return _why("no_squad", [])
	if s.moved:
		return _why("already_moved", [])
	var eng := BtSquads.is_engaged(st, s)
	var how := "fb" if eng else ("adv" if s.adv else "move")
	if eng and not fall_back:
		return _why("engaged_need_fb", [])
	var tx := snap(x)
	var tz := snap(z)
	var c := BtSquads.center(s)
	var d2 := Fx.dist2(c[0], c[1], tx, tz)
	var rng := move_range(s)
	var lim := rng + TRY_PAD
	if lim < 0 or d2 > lim * lim:
		return _why("too_far", [Fx.isqrt(d2), Fx.idiv(rng, 1000)])
	if BtBlocking.block_at(st, tx, tz):
		return _why("blocked", [])
	var to := plan_move(st, s, tx, tz)
	if not moves_any(s, to):
		if eng:
			return _why("cant_fall_back", [])
		if near_foe(st, s, tx, tz, BtSquads.radius(s)):
			return _why("near_foe", [])
		return _why("no_room", [])
	if eng:
		for k: int in mini(to.size(), s.models.size()):
			if near_foe(st, s, to[k][0], to[k][1], BtBlocking.unit_rad(s.models[k])):
				return _why("fb_not_clear", [])
	return {"key": "", "args": [], "act": {"a": "smove", "u": s.id, "to": pts(to), "how": how}}


# ---------------------------------------------------------------- เดินเป็นกอง
## canGroup (ส่วนกติกา): หมู่ที่ยังอยู่ ยังไม่เดิน ไม่ติดประชิด (UI เพิ่ม canAct: ตาของใคร ที่นั่ง เฟส)
static func can_group(st: BattleState, s: BattleState.Squad) -> bool:
	return s != null and not s.models.is_empty() and not s.moved and not BtSquads.is_engaged(st, s)


## groupAll: หมู่ของฝ่ายที่ถึงตาที่เดินเป็นกองได้ ตามลำดับที่สร้าง
static func group_all(st: BattleState) -> PackedStringArray:
	var out := PackedStringArray()
	for q: BattleState.Squad in st.alive_squads():
		if q.side == st.turn and can_group(st, q):
			out.append(q.id)
	return out


## groupMove (ส่วนวางแผน): หมู่ใน ids ที่ can_group ขยับไปทางเดียวกันเท่า ๆ กัน ตามเวกเตอร์ d จากจุดกลางของ
## จุดกลางทุกหมู่ไปที่ (x, z) หมู่ละไม่เกินระยะเดินของตัวเอง เป้าห่างขอบโต๊ะ 1200 MI
## คืน [{u, x, z, how}] ตามลำดับที่ต้องเดิน: หมู่ที่อยู่หน้าสุดตามทิศ d ก่อน (เท่ากันคงลำดับ ids)
## ผู้เรียกวนทีละหมู่: group_act แล้วใช้ act ก่อนถามหมู่ถัดไป (แผนของหมู่หลังต้องเห็นหมู่ก่อนหน้าที่เดินแล้ว)
## ไม่มีหมู่ หรือ d สั้นกว่า 300 MI: คืนว่าง
static func group_plan(st: BattleState, ids: PackedStringArray, x: int, z: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var list: Array[BattleState.Squad] = []
	for id: String in ids:
		var q := st.squad(id)
		if can_group(st, q):
			list.append(q)
	var n := list.size()
	if n == 0:
		return plan
	var gx := Fx.clampi(x, -GROUP_FAR, GROUP_FAR)
	var gz := Fx.clampi(z, -GROUP_FAR, GROUP_FAR)
	var cs: Array[PackedInt64Array] = []
	var sx := 0
	var sz := 0
	for q: BattleState.Squad in list:
		var c := BtSquads.center(q)
		cs.append(c)
		sx += c[0]
		sz += c[1]
	# n เท่าของ d (ไม่หาร จึงตรงเป๊ะ): |n gx - sx| ไม่เกินราวสองพันล้าน กำลังสองยังไม่ล้น
	var nx := n * gx - sx
	var nz := n * gz - sz
	var nd2 := nx * nx + nz * nz
	if nd2 < 300 * 300 * n * n:
		return plan
	var proj := PackedInt64Array()
	for c: PackedInt64Array in cs:
		proj.append(Fx.dot(c[0], c[1], nx, nz))
	var order: Array = Fx.stable_sort(range(n), func(a: int, b: int) -> bool: return proj[a] > proj[b])
	var ew := st.w * 500 - PLAN_EDGE
	var ed := st.d * 500 - PLAN_EDGE
	for iv: Variant in order:
		var i: int = iv
		var q := list[i]
		var c := cs[i]
		var rng := move_range(q)
		var tx := 0
		var tz := 0
		if rng >= 0 and nd2 <= rng * rng * n * n:
			# ไปได้ถึงเป้าเต็มระยะ: จุดกลาง + d (ปัดครั้งเดียวเข้ากริด)
			tx = 10 * Fx.js_round(c[0] * n + nx, 10 * n)
			tz = 10 * Fx.js_round(c[1] * n + nz, 10 * n)
		else:
			# ไปได้แค่ระยะเดินตามทิศ d: ความยาวคูณพันจาก isqrt (d ปัดเป็น MI ทิศคลาดไม่ถึงหนึ่งในพันเรเดียน)
			var dx := Fx.js_round(nx, n)
			var dz := Fx.js_round(nz, n)
			var lk := Fx.isqrt((dx * dx + dz * dz) * 1000000)
			tx = 10 * Fx.js_round(c[0] * lk + dx * rng * 1000, 10 * lk)
			tz = 10 * Fx.js_round(c[1] * lk + dz * rng * 1000, 10 * lk)
		plan.append({"u": q.id, "x": Fx.clampi(tx, -ew, ew), "z": Fx.clampi(tz, -ed, ed), "how": "adv" if q.adv else "move"})
	return plan


## หนึ่งก้าวของ group_plan: วางแผนหมู่นั้นตอนนี้ (เห็นหมู่ที่เดินไปก่อนแล้ว) คืน act smove
## หรือ {} เมื่อไม่มีใครในหมู่ขยับเกิน 300 MI (หน้าเก่าไม่ส่งอะไร) หรือหมู่เดินไปแล้ว
static func group_act(st: BattleState, step: Dictionary) -> Dictionary:
	var q := st.squad(str(step.get("u", "")))
	if q == null or q.moved:
		return {}
	var to := plan_move(st, q, int(step.get("x", 0)), int(step.get("z", 0)))
	if not moves_any(q, to):
		return {}
	return {"a": "smove", "u": q.id, "to": pts(to), "how": str(step.get("how", "move"))}


# ---------------------------------------------------------------- จุดบุก
## chargeSpots: จุดที่ตัวบุกแต่ละตัว (ลำดับ s.models) วิ่งไปชิดฐานเป้า เมื่อบุกถึงด้วยระยะ dist_mi (ผลทอยรวม x 1000)
## ต่อตัว: โมเดลเป้าที่ใกล้สุด (เท่ากันเอาตัวแรก; เป้าไม่มีใครเลย = ที่เดิม) แล้วลองเก้ามุมรอบตัวนั้นที่ระยะ
## r ตัวเรา + r ตัวเป้า + 300 MI (ทิศจากเป้ามาหาเรา แล้วบวก ลบ ห้าสิบห้าในร้อยเรเดียนทีละขั้น ตาราง CHARGE_ROT)
## ใช้ไม่ได้ถ้าไกลจากที่เดิมเกิน dist + 1 MI, ติดสิ่งกีดขวาง, ใกล้จุดที่ตัวก่อนหน้าจอง (น้อยกว่าสองเท่ารัศมี)
## หรือทับฐานตัวอื่น (crowded ไม่ดูจุดจอง เหมือน crowdedBy ของหน้าเก่า)
## ไม่ได้สักมุม: เดินตรงเข้าหาเป้าเท่าที่ระยะให้แล้ว free_spot (จำกัดระยะจากที่เดิม) ไม่ได้อีกก็ที่เดิม
static func charge_spots(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, dist_mi: int) -> Array[PackedInt64Array]:
	var out: Array[PackedInt64Array] = []
	if s == null:
		return out
	var ts: Array[BattleState.Unit] = []
	if t != null:
		ts = t.models
	var taken: Array[PackedInt64Array] = []
	var lim2 := (dist_mi + 1) * (dist_mi + 1)
	for m: BattleState.Unit in s.models:
		var best: BattleState.Unit = null
		var bd := 0
		for q: BattleState.Unit in ts:
			var d2 := Fx.dist2(m.x, m.z, q.x, q.z)
			if best == null or d2 < bd:
				best = q
				bd = d2
		if best == null:
			out.append(PackedInt64Array([m.x, m.z]))
			continue
		var rm := BtBlocking.unit_rad(m)
		var rr := rm + BtBlocking.unit_rad(best) + CHARGE_PAD
		var v0 := _dir(m.x - best.x, m.z - best.z)
		var spot := PackedInt64Array()
		for tries: int in 9:
			var v := v0
			if tries > 0:
				# ceil ของ tries/2 ขั้น: คี่เบี่ยงบวก คู่เบี่ยงลบ (tries เป็นบวก หารตัดเศษ = ปัดลง)
				var rot: Array = BtOffsets.CHARGE_ROT[(tries - 1) / 2]
				v = turn(v0[0], v0[1], int(rot[0]), int(rot[1]), tries % 2 == 1)
			var cx := best.x + 10 * Fx.js_round(v[0] * rr, 10000)
			var cz := best.z + 10 * Fx.js_round(v[1] * rr, 10000)
			if dist_mi + 1 < 0 or Fx.dist2(cx, cz, m.x, m.z) > lim2:
				continue
			if BtBlocking.block_at(st, cx, cz):
				continue
			var near := false
			for p: PackedInt64Array in taken:
				if _within(p[0] - cx, p[1] - cz, 2 * rm, false):
					near = true
					break
			if near or BtBlocking.crowded(st, cx, cz, m, -1):
				continue
			spot = PackedInt64Array([cx, cz])
			break
		if spot.is_empty():
			var dx := best.x - m.x
			var dz := best.z - m.z
			var le := Fx.isqrt(dx * dx + dz * dz)
			if le == 0:
				le = 1000
			var go := maxi(0, mini(dist_mi, le - rr))
			var px := m.x + 10 * Fx.js_round(dx * go, le * 10)
			var pz := m.z + 10 * Fx.js_round(dz * go, le * 10)
			spot = BtBlocking.free_spot(st, px, pz, m, PackedInt64Array([m.x, m.z]), dist_mi, rm)
			if spot.is_empty():
				spot = PackedInt64Array([m.x, m.z])
		taken.append(spot)
		out.append(spot)
	return out


# ---------------------------------------------------------------- ตัวช่วย
## ตัวช่วยของ plan_move: เก็บโมเดลอื่นเป็นอาร์เรย์ครั้งเดียว แล้วต่อโมเดลเก็บเฉพาะตัวที่ใกล้พอจะกันจุดที่ลองได้
## (จุดที่ลองของ m ห่าง m ไม่เกิน reach ตัวที่ห่างกว่า reach + ระยะกัน จึงกันไม่ได้แน่) ผลเท่ากับ spot_free ทุกจุด
class _Free extends RefCounted:
	var st: BattleState
	## สองเท่ารัศมียกกำลังสอง (ห่างจุดจองน้อยกว่านี้ไม่ได้)
	var c2 := 0
	var ax := PackedInt64Array()
	var az := PackedInt64Array()
	## ระยะกันของแต่ละตัว: ศัตรู r + r_q + 1050 (ไม่เกิน = ติด), ตัวอื่น r + r_q (น้อยกว่า = ติด)
	var alim := PackedInt64Array()
	var afoe := PackedInt32Array()
	var nx := PackedInt64Array()
	var nz := PackedInt64Array()
	## เกณฑ์กำลังสองของตัวใกล้: d2 <= nt คือติด
	var nt := PackedInt64Array()

	func init(s_: BattleState, sq: BattleState.Squad, r: int) -> void:
		st = s_
		# รัศมีไม่เป็นบวก (ไม่มีในข้อมูลจริง) จุดจองกันไม่ได้ เหมือน _within ของ spot_free
		c2 = 4 * r * r if r > 0 else 0
		for q: BattleState.Unit in s_.units:
			# ตัวในหมู่เองกำลังเดิน (ฝ่ายเดียวกัน near_foe ก็ไม่นับ)
			if q.sq == sq.id:
				continue
			var foe := q.side != sq.side
			ax.append(q.x)
			az.append(q.z)
			alim.append(r + BtBlocking.unit_rad(q) + (BtMoves.NEAR_PAD if foe else 0))
			afoe.append(1 if foe else 0)

	func focus(mx: int, mz: int, reach: int) -> void:
		nx.clear()
		nz.clear()
		nt.clear()
		for i: int in ax.size():
			var lim: int = alim[i]
			var foe := afoe[i] == 1
			if lim < 0 or (lim == 0 and not foe):
				continue
			var span := reach + lim
			var dx: int = ax[i] - mx
			var dz: int = az[i] - mz
			if dx > span or dx < -span or dz > span or dz < -span or dx * dx + dz * dz > span * span:
				continue
			nx.append(ax[i])
			nz.append(az[i])
			nt.append(lim * lim if foe else lim * lim - 1)

	func open_at(x: int, z: int, chosen: Array[PackedInt64Array]) -> bool:
		for p: PackedInt64Array in chosen:
			var ex := p[0] - x
			var ez := p[1] - z
			if ex * ex + ez * ez < c2:
				return false
		for i: int in nx.size():
			var dx := nx[i] - x
			var dz := nz[i] - z
			if dx * dx + dz * dz <= nt[i]:
				return false
		return not BtBlocking.block_at(st, x, z)
