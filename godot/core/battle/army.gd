class_name BtArmy
extends RefCounted
## กองทัพ (R1_PORT_SPEC หัวข้อ army.gd): ที่นั่งออฟไลน์ รายชื่อกองทัพ (จำนวนหมู่ต่อชนิดตามลำดับ TYPES) เพดาน แต้ม
## กองของบอท (auto_list) จุดลงสนาม (dep) และการวางกองลงโต๊ะ (deploy) ตามหน้าเก่า 31008–31272
## หน่วยลับ: ชนิดละไม่เกินหนึ่งหมู่ ไม่คิดแต้ม ไม่อยู่ในกองของบอท (ไม่บอกว่าได้มาอย่างไร)
## ตำแหน่งเป็น MI จุดลงสนามที่สร้างที่นี่และที่ยืนทุกตัวอยู่บนตาราง 10 MI

## เพดานตัวหมากต่อคน (baseCap): ทั้งโต๊ะห้าร้อย ต่อคนไม่เกินสองร้อยห้าสิบ
const CAP_TABLE := 500
const CAP_SEAT := 250
## เพดานตัวหมากของกองบอท: อย่างน้อยหก และอย่างน้อยสี่สิบหารจำนวนคนในทีม
const MIN_MODELS := 6
const TEAM_MODELS := 40
## จุดลงสนามต้องห่างขอบโต๊ะสามนิ้ว (MI)
const DEP_EDGE := 3000
## ระยะวงที่หมู่ล้อมจุดลงสนาม วงละ 5200 MI (เก็บเป็นหน่วยสิบ MI)
const RING_10 := 520
## วงแรกของเพื่อนร่วมทีมคือ DEP_MATE คูณสิบเก้าส่วนสิบ
const MATE_RING_NUM := 19
const MATE_RING_DEN := 10
## ตารางสำรองตอนหาจุดลงสนาม ทีละ 1500 MI
const DEP_STEP := 1500
## ทีมไม่เกินสี่คน: วงเพื่อนร่วมทีมหันไปสี่ทิศตรง ๆ ทีละเศษหนึ่งส่วนสี่รอบ
const DIR4 := [[1, 0], [0, 1], [-1, 0], [0, -1]]
## จำนวนหน้าตาของหน่วยที่มีสกิน ตาม data/skins.json (test_army เทียบกับไฟล์ทุกครั้ง)
const SKIN_N := {"loki": 2}
## สุ่มซื้อเพิ่มในรอบสองและสาม: สุ่มยี่สิบช่อง ได้น้อยกว่าเก้า = ซื้อ (สี่สิบห้าส่วนร้อย)
const BUY_DIE := 20
const BUY_HIT := 9
## คีย์เรียงของตารางสำรอง = ระยะกำลังสอง x 2^20 + ลำดับที่ใส่: ระยะเท่ากันคงลำดับเดิม (เท่ากับเรียงแบบเสถียร)
const KEY_SHIFT := 1048576


# ---------------------------------------------------------------- ที่นั่ง
## ที่นั่งออฟไลน์ (mkPlayers): ทีม 0..teams-1 ทีมละ per_team คน ตามลำดับ id; pve ทีมอื่นเป็นบอท
## spectator ทุกที่นั่งเป็นบอท; ชื่อบนจอเป็นงานของ UI; pid ว่าง (ที่นั่งคนได้ pid ประจำเครื่องตอนเริ่มนัด)
static func mk_players(st: BattleState) -> void:
	# ที่นั่งไม่มีดัชนีให้ดูแล (id = ตำแหน่ง) ล้างแล้วสร้างใหม่ได้ เหมือนหน้าเก่าที่แทน G.players ทั้งชุด
	st.seats.clear()
	for t: int in st.teams:
		for i: int in st.per_team:
			var bot := (st.mode == "pve" and t != 0) or st.mode == "spectator"
			st.add_seat(t, "", bot, false, "")


# ---------------------------------------------------------------- รายชื่อกองทัพ
## ค่าแบบ x | 0 ของหน้าเก่า: จำนวนเต็มตัดเหลือ 32 บิต (มีเครื่องหมาย) bool เป็น 0/1 อย่างอื่นเป็นศูนย์
## (core รับแต่จำนวนเต็ม ตัวเลขจาก JSON แปลงก่อนถึงที่นี่)
static func js_int(v: Variant) -> int:
	match typeof(v):
		TYPE_INT:
			var u: int = int(v) & 4294967295
			return u - 4294967296 if u >= 2147483648 else u
		TYPE_BOOL:
			return 1 if bool(v) else 0
	return 0


## ค่าในช่องของชนิดเป็นจริงแบบ JavaScript ไหม (ไม่มี ศูนย์ สตริงว่าง false = ไม่จริง)
static func _flag(t: Dictionary, name: String) -> bool:
	var v: Variant = t.get(name, null)
	match typeof(v):
		TYPE_INT:
			return int(v) != 0
		TYPE_BOOL:
			return bool(v)
		TYPE_STRING:
			return str(v) != ""
		TYPE_NIL:
			return false
	return true


## หน่วยลับ (sec หรือ lk) ของชนิดที่ตำแหน่ง ti
static func _hidden(ti: int) -> bool:
	var types := GameData.types()
	if ti < 0 or ti >= types.size():
		return false
	return _flag(types[ti], "sec") or _flag(types[ti], "lk")


## รายชื่อที่ส่งมาเป็นแบบที่ใช้ได้ (fitList): ยาวเท่า TYPES เสมอ ช่องละ 0..SLOT_MAX หน่วยลับ 0..1 (ทุกโหมด)
## ช่องที่ไม่มีเป็นศูนย์ ช่องเกินทิ้ง
static func fit_list(raw: Array) -> PackedInt32Array:
	var n := GameData.count()
	var cap := GameData.const_int("SLOT_MAX", 99)
	var out := PackedInt32Array()
	out.resize(n)
	for i: int in n:
		var v: int = js_int(raw[i]) if i < raw.size() else 0
		out[i] = Fx.clampi(v, 0, 1 if _hidden(i) else cap)
	return out


## กองทัพของรายชื่อ (facOf): ชนิดแรกที่มีหมู่และไม่ใช่ตัวลับ sec (หน่วยลับ lk นับ) ไม่มีใช้ dflt หรือ mod
static func fac_of(list: PackedInt32Array, dflt: String) -> String:
	var types := GameData.types()
	for i: int in mini(list.size(), types.size()):
		if list[i] > 0 and not _flag(types[i], "sec"):
			return str(types[i].get("fac", ""))
	return dflt if dflt != "" else "mod"


## สกินที่ส่งมาเป็นแบบที่ใช้ได้ (fitSkin): เฉพาะหน่วยที่มีสกิน และเลข 1 ถึงน้อยกว่าจำนวนหน้าตา
static func fit_skin(raw: Dictionary) -> Dictionary:
	var out := {}
	for k: String in SKIN_N:
		if raw.has(k):
			var i := js_int(raw[k])
			if i > 0 and i < int(SKIN_N[k]):
				out[k] = i
	return out


# ---------------------------------------------------------------- เพดานและแต้ม
## งบต่อคน (shareOf): งบทีมหารจำนวนคนในทีม อย่างน้อยสี่สิบ
static func share_of(st: BattleState) -> int:
	return maxi(40, Fx.idiv(st.budget, maxi(1, st.per_team)))


## จำนวนที่นั่งที่ใช้คิดเพดาน (ไม่มีที่นั่งนับเป็นสอง เหมือน G.players.length || 2)
static func _seat_n(st: BattleState) -> int:
	return st.seats.size() if st.seats.size() > 0 else 2


## เพดานตัวหมากต่อคนตามกติกา (baseCap)
static func base_cap(st: BattleState) -> int:
	return mini(CAP_SEAT, Fx.idiv(CAP_TABLE, maxi(1, _seat_n(st))))


## เพดานตัวหมากที่จัดเองได้ (armyCap): โหมดผู้ชมใหญ่กว่ามาก
static func army_cap(st: BattleState) -> int:
	if st.mode == "spectator":
		return Fx.idiv(GameData.const_int("SPEC_TOTAL", 3000), maxi(1, _seat_n(st)))
	return base_cap(st)


## จำนวนหมู่สูงสุดของชนิดนี้ที่จัดเองได้ (slotMax): หน่วยลับหนึ่งนอกโหมดผู้ชม; ชนิดที่ไม่มีได้ศูนย์
static func slot_max(st: BattleState, ti: int) -> int:
	if ti < 0 or ti >= GameData.count():
		return 0
	if _hidden(ti) and st.mode != "spectator":
		return 1
	return GameData.const_int("SLOT_MAX", 99)


## แต้มของกองที่นั่ง pi (ptsOf): ตัวลับกับหน่วยลับไม่คิดแต้ม
static func pts_of(st: BattleState, pi: int) -> int:
	var p := st.seat(pi)
	if p == null:
		return 0
	var types := GameData.types()
	var t := 0
	for i: int in mini(p.list.size(), types.size()):
		if p.list[i] != 0 and not _hidden(i):
			t += p.list[i] * int(types[i]["pts"])
	return t


## แต้มรวมของทีม (teamPts)
static func team_pts(st: BattleState, t: int) -> int:
	var n := 0
	for p: BattleState.Seat in st.team_seats(t):
		n += pts_of(st, p.id)
	return n


## กองมีหมู่ไหม (hasUnits): หน่วยลับนับเป็นหมู่
static func has_units(st: BattleState, pi: int) -> bool:
	var p := st.seat(pi)
	if p == null:
		return false
	for i: int in mini(p.list.size(), GameData.count()):
		if p.list[i] > 0:
			return true
	return false


# ---------------------------------------------------------------- กองของบอท
## จัดกองให้ที่นั่ง pi (autoList) แล้วเขียน list กับ fac ของที่นั่ง
## dev == null: แบบผูก seed (บอท Claude ที่นั่งว่างตอนเริ่ม) สตรีม armies:<pi> ใหม่ทุกครั้ง ผลจึงเป็นฟังก์ชันของ
## (seed, ที่นั่ง, setup) และลูกแรกสุ่มกองทัพ; มี dev: กองทัพของที่นั่ง (ไม่รู้จักหรือไม่มีหน่วยให้สุ่ม = mod) สุ่มจาก dev
## ขั้นตอนตามหน้าเก่า: รอบแรกซื้อที่ราคาไม่เกินครึ่งของเงินเหลือ (สองชนิดแรกซื้อเสมอ) สองรอบต่อมาสุ่มซื้อ
## เติมหน่วยถูกสุดจนเต็ม แล้วเปลี่ยนหน่วยเป็นตัวแพงขึ้นจนเหลือเงินไม่เกินหนึ่งในห้า (กองที่ตัวหมากเต็มแล้วไม่เปลี่ยน)
## v10: ไม่มีชนิดใดเกิน SLOT_MAX หมู่ ทั้งตอนซื้อและตอนเปลี่ยน (หน้าเก่าเคยได้สองร้อยกว่า)
static func auto_list(st: BattleState, pi: int, dev: Rng) -> void:
	var p := st.seat(pi)
	if p == null:
		return
	var rng := dev
	var fac := p.fac
	if dev == null:
		rng = Rng.make("armies:%d" % pi, st.seed)
		var facs := GameData.factions()
		fac = facs[rng.bounded(facs.size())] if facs.size() > 0 else "mod"
	if GameData.pool(fac).is_empty():
		fac = "mod"
	var types := GameData.types()
	var order := PackedInt64Array()
	for key: String in GameData.pool(fac):
		var ti := GameData.index_of(key)
		# ข้อมูลตรวจแล้วว่าทุกคีย์ในกองมีอยู่จริง
		if ti >= 0:
			order.append(ti)
	if order.is_empty():
		return
	var share := share_of(st)
	var left := share
	var slot_cap := GameData.const_int("SLOT_MAX", 99)
	var max_m := mini(base_cap(st), maxi(maxi(MIN_MODELS, Fx.cdiv(TEAM_MODELS, maxi(1, st.per_team))), Fx.js_round(share, 25)))
	# ราคาและจำนวนตัวต่อหมู่ ตามลำดับใน order
	var L := order.size()
	var pts := PackedInt64Array()
	var nn := PackedInt64Array()
	pts.resize(L)
	nn.resize(L)
	for k: int in L:
		pts[k] = int(types[order[k]]["pts"])
		nn[k] = int(types[order[k]]["n"])
	var cheap := cheapest(fac)
	var ck := order.find(cheap)
	var out := PackedInt32Array()
	out.resize(types.size())
	var models := 0
	for pass_no: int in 3:
		for k: int in L:
			var i: int = order[k]
			if not (pts[k] <= left and models + nn[k] <= max_m and out[i] < slot_cap):
				continue
			var buy := false
			if pass_no == 0:
				buy = 2 * pts[k] <= left or k < 2
			else:
				buy = rng.bounded(BUY_DIE) < BUY_HIT
			if buy:
				out[i] += 1
				left -= pts[k]
				models += nn[k]
	while pts[ck] <= left and models + nn[ck] <= max_m and out[cheap] < slot_cap:
		out[cheap] += 1
		left -= pts[ck]
		models += nn[ck]
	# ไล่หาตัวเปลี่ยนจากราคาแพงลงมา (ราคาเท่ากันตามลำดับใน order) ตัวแรกที่ผ่านคือตัวแพงสุดตัวแรกของหน้าเก่า
	var by_pts := _by_pts_desc(pts)
	var up := models + nn[ck] <= max_m
	while up and 5 * left > share:
		up = false
		for ka: int in L:
			var a: int = order[ka]
			if out[a] == 0:
				continue
			var kb := -1
			for kk: int in by_pts:
				var dp: int = pts[kk] - pts[ka]
				if dp <= 0:
					break
				if dp <= left and models - nn[ka] + nn[kk] <= max_m and out[order[kk]] < slot_cap:
					kb = kk
					break
			if kb >= 0:
				var b: int = order[kb]
				out[a] -= 1
				out[b] += 1
				left -= pts[kb] - pts[ka]
				models += nn[kb] - nn[ka]
				up = true
				break
	if models == 0:
		out[cheap] = 1
	p.list = out
	p.fac = fac


## หน่วยถูกสุดของกองทัพ (cheap ของ autoList): ตำแหน่งใน TYPES ของชนิดแรกในกองที่ราคาน้อยที่สุด
## (เทียบแบบน้อยกว่าจริง ตัวแรกชนะ) กองไม่มีหน่วยให้สุ่มคืน -1
static func cheapest(fac: String) -> int:
	var types := GameData.types()
	var best := -1
	for key: String in GameData.pool(fac):
		var ti := GameData.index_of(key)
		if ti >= 0 and (best < 0 or int(types[ti]["pts"]) < int(types[best]["pts"])):
			best = ti
	return best


## ตำแหน่งใน order เรียงราคามากไปน้อย ราคาเท่ากันคงลำดับเดิม (insertion sort เสถียร ชนิดในกองไม่เกินห้าสิบ)
static func _by_pts_desc(pts: PackedInt64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for k: int in pts.size():
		var j := out.size()
		out.append(k)
		while j > 0 and pts[out[j - 1]] < pts[k]:
			out[j] = out[j - 1]
			j -= 1
		out[j] = k
	return out


# ---------------------------------------------------------------- จุดลงสนาม
## จุดลงสนามผิดกฎไหม (depWhyNot): {key, args} ตามลำดับหน้าเก่า "" = ผ่าน
## edge = ใกล้ขอบโต๊ะเกินสามนิ้ว · blocked = ปักไม่ได้ (roomToLand) · mate [ที่นั่ง] = ใกล้เพื่อนร่วมทีมไม่ถึง DEP_MATE
## foe [ทีม] = ใกล้ทีมอื่นไม่ถึง DEP_FOE (ดูที่นั่งอื่นที่มีจุดแล้วตามลำดับ ตัวแรกที่ผิดชนะ)
static func dep_why_not(st: BattleState, pi: int, x: int, z: int) -> Dictionary:
	if absi(x) > st.w * 500 - DEP_EDGE or absi(z) > st.d * 500 - DEP_EDGE:
		return {"key": "edge", "args": []}
	if not BtBlocking.room_to_land(st, x, z):
		return {"key": "blocked", "args": []}
	var q := _too_close(st, pi, x, z)
	if q != null:
		return {"key": "mate", "args": [q.id]} if q.team == _team_of(st, pi) else {"key": "foe", "args": [q.team]}
	return {"key": "", "args": []}


## ทีมของที่นั่ง (ไม่มีที่นั่ง = -1 ทุกจุดของคนอื่นนับเป็นทีมอื่น)
static func _team_of(st: BattleState, pi: int) -> int:
	var p := st.seat(pi)
	return p.team if p != null else -1


## ที่นั่งแรกที่จุดลงสนามใกล้ (x, z) เกินกฎ (เพื่อนร่วมทีม DEP_MATE ทีมอื่น DEP_FOE) ไม่มีคืน null
static func _too_close(st: BattleState, pi: int, x: int, z: int) -> BattleState.Seat:
	var team := _team_of(st, pi)
	var mate := GameData.const_int("DEP_MATE", 5) * 1000
	var foe := GameData.const_int("DEP_FOE", 20) * 1000
	for q: BattleState.Seat in st.seats:
		if q.id == pi or not q.has_dep:
			continue
		var need := mate if q.team == team else foe
		if Fx.dist2(q.dep_x, q.dep_z, x, z) < need * need:
			return q
	return null


## ผ่านกฎไหม (ผลเท่ากับ dep_why_not ได้ "" แต่ดูระยะก่อน เพราะถูกกว่า roomToLand)
static func _dep_ok(st: BattleState, pi: int, x: int, z: int) -> bool:
	if absi(x) > st.w * 500 - DEP_EDGE or absi(z) > st.d * 500 - DEP_EDGE:
		return false
	return _too_close(st, pi, x, z) == null and BtBlocking.room_to_land(st, x, z)


## ช่องลงสนามมาตรฐาน (depSlots): ตารางห่างกันอย่างน้อย DEP_FOE แถว z ก่อน ปัดเป็น 10 MI
## แถวหรือคอลัมน์เดียวอยู่ที่ -W / -D (มุมโต๊ะ ไม่ใช่กลาง) ตามหน้าเก่า (R1_PORT_SPEC §9 Q7)
static func dep_slots(st: BattleState) -> Array[PackedInt64Array]:
	var ww := st.w * 500 - DEP_EDGE
	var dd := st.d * 500 - DEP_EDGE
	var foe := GameData.const_int("DEP_FOE", 20) * 1000
	var nx := Fx.idiv(2 * ww, foe) + 1
	var nz := Fx.idiv(2 * dd, foe) + 1
	var out: Array[PackedInt64Array] = []
	for iz: int in maxi(0, nz):
		var z := -dd + (10 * Fx.js_round(iz * 2 * dd, 10 * (nz - 1)) if nz > 1 else 0)
		for ix: int in maxi(0, nx):
			var x := -ww + (10 * Fx.js_round(ix * 2 * ww, 10 * (nx - 1)) if nx > 1 else 0)
			out.append(PackedInt64Array([x, z]))
	return out


## จำนวนจุดลงสนามที่โต๊ะ w x d นิ้วรับได้ (depCapacity ของหน้าจอ): สูตร w - 5 ของหน้าเก่า (ต่างจาก dep_slots ที่ w คี่)
static func dep_capacity(w: int, d: int) -> int:
	var foe := GameData.const_int("DEP_FOE", 20)
	return (Fx.idiv(w - 5, foe) + 1) * (Fx.idiv(d - 5, foe) + 1)


## หาจุดลงสนามให้ที่นั่ง pi (autoDep) ไม่เขียนที่นั่ง: ช่องของทีม (กระจายทีมทั่วโต๊ะ) คนแรกของทีมได้ช่องนั้นถ้าผ่าน
## ไม่งั้นวนรอบช่อง 32 ครั้ง (วงแรก DEP_MATE x 19/10 ขยายทีละ DEP_MATE ทุกแปดครั้ง) แล้วไล่ตารางทีละ 1500 MI
## จากใกล้ช่องไปไกล สุดท้ายคืนช่องของทีม; ผลอยู่บนตาราง 10 MI
static func auto_dep(st: BattleState, pi: int) -> PackedInt64Array:
	var p := st.seat(pi)
	if p == null:
		return PackedInt64Array([0, 0])
	var slots := dep_slots(st)
	var c := PackedInt64Array([0, 0])
	if not slots.is_empty():
		var ns := slots.size()
		c = slots[Fx.imod(Fx.js_round(p.team * ns, maxi(1, st.teams)), ns)].duplicate()
	var mates := st.team_seats(p.team)
	var k := 0
	for i: int in mates.size():
		if mates[i].id == p.id:
			k = i
	if k == 0 and _dep_ok(st, pi, c[0], c[1]):
		return c
	var ww := st.w * 500 - DEP_EDGE
	var dd := st.d * 500 - DEP_EDGE
	var step := GameData.const_int("DEP_MATE", 5) * 1000
	var r := Fx.idiv(step * MATE_RING_NUM, MATE_RING_DEN)
	var m := maxi(4, mates.size())
	for i: int in 32:
		var x := 0
		var z := 0
		if m == 4:
			var dv: Array = DIR4[Fx.imod(k + i, 4)]
			x = c[0] + int(dv[0]) * r
			z = c[1] + int(dv[1]) * r
		else:
			# ทีมใหญ่กว่าสี่คน (ห้องออนไลน์ย้ายทีมได้): มุม (k + i) / m รอบ แบบ Q16 ปัดเป็น 10 MI
			var th := Fx.idiv((k + i) * FieldProps.TWO_PI, m)
			x = c[0] + 10 * Fx.js_round(FieldProps.cos_q(th) * r, 655360)
			z = c[1] + 10 * Fx.js_round(FieldProps.sin_q(th) * r, 655360)
		x = Fx.clampi(x, -ww, ww)
		z = Fx.clampi(z, -dd, dd)
		if _dep_ok(st, pi, x, z):
			return PackedInt64Array([x, z])
		if Fx.imod(i, 8) == 7:
			r += step
	# ตารางสำรอง: แถว z นอก x ใน เรียงตามระยะถึงช่อง ระยะเท่ากันตามลำดับที่ใส่
	var cx := PackedInt64Array()
	var cz := PackedInt64Array()
	var keys := PackedInt64Array()
	var zz := -dd
	while zz <= dd:
		var xx := -ww
		while xx <= ww:
			# d2 ไม่เกินราว 7e10 (< 2^37) คูณ 2^20 ยังไม่ถึง 2^63
			keys.append(Fx.dist2(xx, zz, c[0], c[1]) * KEY_SHIFT + cx.size())
			cx.append(xx)
			cz.append(zz)
			xx += DEP_STEP
		zz += DEP_STEP
	keys.sort()
	for key: int in keys:
		var j := Fx.imod(key, KEY_SHIFT)
		if _dep_ok(st, pi, cx[j], cz[j]):
			return PackedInt64Array([cx[j], cz[j]])
	return c


# ---------------------------------------------------------------- วางกองลงโต๊ะ
## วางทุกกองลงโต๊ะ (deploy) ต้องเป็นโต๊ะว่าง (ยังไม่มีหมู่หรือโมเดล ไม่งั้นไม่ทำอะไร)
## ที่นั่งตามลำดับ กองว่างข้าม: ไม่มีจุดลงสนามใช้ auto_dep แล้วเขียนลงที่นั่ง (ที่นั่งหลังเห็นจุดนี้)
## ทุกหมู่หันเข้ากลางโต๊ะ (จุดลงสนามที่กลางโต๊ะพอดีหัน -z) หมู่ที่ i ตามลำดับ TYPES x จำนวน: หมู่แรกที่จุด
## หมู่ต่อไปวงละหก วงที่ R ห่าง R x 5200 MI มุม k/6 รอบ + R x DEP_ANG_STEP
## โมเดลยืนตาม formation แล้ว free_spot ทีละตัว (ตัวหลังเห็นตัวก่อน) hp = w; ส่ง LOG_LINE deployed ที่นั่งละบรรทัด
static func deploy(st: BattleState, out: Array[Dictionary]) -> void:
	if not st.squads.is_empty() or not st.units.is_empty():
		return
	var types := GameData.types()
	var none := PackedInt64Array()
	for p: BattleState.Seat in st.seats:
		var row := PackedInt64Array()
		for i: int in mini(p.list.size(), types.size()):
			for j: int in p.list[i]:
				row.append(i)
		if row.is_empty():
			continue
		if not p.has_dep:
			var c := auto_dep(st, p.id)
			p.has_dep = true
			p.dep_x = c[0]
			p.dep_z = c[1]
		var face := Fx.norm1000(-p.dep_x, -p.dep_z)
		if face[0] == 0 and face[1] == 0:
			# หน้าเก่าได้มุม -pi เมื่อจุดอยู่กลางโต๊ะพอดี: หันไปทาง -z
			face = PackedInt64Array([0, -1000])
		var models := 0
		for i: int in row.size():
			var ti: int = row[i]
			var t: Dictionary = types[ti]
			var cx := p.dep_x
			var cz := p.dep_z
			if i > 0:
				var ring := 1 + Fx.idiv(i - 1, 6)
				var th := Fx.idiv(Fx.imod(i - 1, 6) * FieldProps.TWO_PI, 6) + ring * BtOffsets.DEP_ANG_STEP
				cx += 10 * Fx.js_round(FieldProps.cos_q(th) * ring * RING_10, 65536)
				cz += 10 * Fx.js_round(FieldProps.sin_q(th) * ring * RING_10, 65536)
			var id := "%d:%d" % [p.id, i]
			var n: int = int(t["n"])
			var s := st.add_squad(id, str(t["k"]), p.team, p.id, n, int(t.get("vsh", 0)))
			s.fx = face[0]
			s.fz = face[1]
			var r := BtSquads.radius_of(ti)
			var slots := BtSquads.formation(n, cx, cz, face[0], face[1], r)
			for j: int in slots.size():
				var sp := BtBlocking.free_spot(st, slots[j][0], slots[j][1], null, none, 0, r)
				st.add_unit("%s.%d" % [id, j], s, int(t["w"]), sp[0], sp[1])
			models += slots.size()
		var args: Array = [p.id, row.size(), models]
		st.say("deployed", args)
		out.append(Events.make(Events.Id.LOG_LINE, {"key": "deployed", "args": args.duplicate()}))
