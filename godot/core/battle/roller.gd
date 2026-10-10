class_name BtRoller
extends RefCounted
## ตัวจัดคิวทอยของถาด (R1_PORT_SPEC หัวข้อ roller.gd): iRollFor / myRoll / doRoll / flushPend ของหน้าเก่า ไม่มีถาด
## อ่านสถานะอย่างเดียวแล้วคืน act ไม่แก้อะไรเลย (ผู้เรียกส่ง act เข้า apply แล้วค่อยถามรายการถัดไป)
## here = {online, owner, pid, since_ok, force} จาก Net: since_ok = รายการแรกที่รออยู่รอนานเกิน OWNER_WAIT แล้ว
## (เวลาเครื่องอยู่ใน Net ไม่เข้าแกน) · force = ทอยให้ทุกคน (เล่นคนเดียว ตะขอเทสต์)
## ลูกเต๋ามาจากสตรีมที่ผู้เรียกให้ (dice:<seat> ของคนจริงบนเครื่องนี้ ไม่งั้น bot:<seat>, §3) ส่งไม่เกิน 60 ลูกต่อแถว
## CP ของทอยใหม่ หมอบหลบ ใจเหล็ก ตัวรับ act เป็นคนหัก ที่นี่แค่ดูว่าใช้ได้ไหม (ให้ act ตรงกับที่หน้าเก่าส่ง)

## ลูกต่อแถวที่ส่งได้ (ตัวกรองของเซิร์ฟเวอร์ตัดที่ 60 ส่วนที่ขาดทุกเครื่องเติมจาก fallback เหมือนกัน)
const MAX_DICE := 60
## ลูกซ่อมตัวเองต่อครั้งไม่เกิน (ตัวกรอง rez)
const MAX_REZ := 10


# ---------------------------------------------------------------- ใครทอย
## iRollFor: เครื่องนี้ทอยให้ที่นั่ง pi ไหม · บอทกับ Claude: ออฟไลน์ทุกเครื่อง ออนไลน์เจ้าของห้อง
## · คนจริง: ออฟไลน์ หรือนั่งเครื่องนี้ (pid ตรง) · เพื่อนเงียบนาน (since_ok) เจ้าของห้องทอยแทน
static func rolls_here(st: BattleState, pi: int, here: Dictionary) -> bool:
	var q := st.seat(pi)
	var online: bool = bool(here.get("online", false))
	var owner: bool = bool(here.get("owner", false))
	if q == null or q.bot or q.ai:
		return not online or owner
	if not online or q.pid == str(here.get("pid", "")):
		return true
	return owner and bool(here.get("since_ok", false))


## isHumanHere: ที่นั่งนี้เป็นคนจริงที่เล่นบนเครื่องนี้
static func human_here(st: BattleState, pi: int, here: Dictionary) -> bool:
	var q := st.seat(pi)
	if q == null or q.bot or q.ai:
		return false
	return not bool(here.get("online", false)) or q.pid == str(here.get("pid", ""))


## ชื่อสตรีมลูกเต๋าของรายการนี้ (§3): คนจริงบนเครื่องนี้ dice:<seat> ที่เหลือ (บอท Claude คนที่เงียบ) bot:<seat>
static func stream_name(st: BattleState, p: BattleState.Pend, here: Dictionary) -> String:
	if p == null:
		return ""
	var pi := BtPend.roller_of(p)
	return ("dice:%d" if human_here(st, pi, here) else "bot:%d") % pi


## การบุกที่ยังรอการยิงสกัดใส่ตัวมันอยู่ (owatk ที่ chgReady ยังเลื่อนไม่ได้)
static func _ow_waiting(st: BattleState, p: BattleState.Pend) -> bool:
	if p.kind != BattleState.K_CHG or p.stage != BattleState.S_OWATK:
		return false
	for a: BattleState.Pend in st.pend:
		if a.kind == BattleState.K_ATK and a.ow and a.t == p.u:
			return true
	return false


## รายการที่ไม่มีวันทอยแล้ว (prune จะทิ้ง): เป้าการโจมตีหมด · คนตีหมดก่อนทอยเข้าเป้า · คนบุกหรือเป้าหมด
static func _dead(st: BattleState, p: BattleState.Pend) -> bool:
	if p.kind == BattleState.K_ATK:
		if st.squad_alive(st.squad(p.t)) == 0:
			return true
		return p.stage == BattleState.S_HIT and st.squad_alive(st.squad(p.u)) == 0
	if p.kind == BattleState.K_CHG:
		return st.squad_alive(st.squad(p.u)) == 0 or st.squad_alive(st.squad(p.t)) == 0
	return false


## รายการแรกในคิวที่ยังต้องทอย (ข้ามที่รอยิงสกัดและที่ไม่มีวันทอย) หรือ null
static func _first_live(st: BattleState) -> BattleState.Pend:
	for p: BattleState.Pend in st.pend:
		if _ow_waiting(st, p) or _dead(st, p):
			continue
		return p
	return null


## myRoll: รายการแรกที่ต้องทอยตอนนี้ ถ้าเครื่องนี้เป็นคนทอย ไม่งั้น null (ลำดับสำคัญ: อันแรกยังไม่มีใครทอย อันหลังรอ)
## หน้าเก่าทิ้งของค้างไประหว่างหา ที่นี่แค่ข้าม (prune ทำหลังทุก act อยู่แล้ว)
static func next(st: BattleState, here: Dictionary) -> BattleState.Pend:
	var p := _first_live(st)
	if p == null:
		return null
	return p if rolls_here(st, BtPend.roller_of(p), here) else null


## ตัวช่วยของ flushPend: รายการที่จะทอยต่อ · force และไม่มีของเครื่องนี้ ทอยรายการแรกให้เลย
## (การบังคับ owatk เป็น charge ของหน้าเก่าไม่มี: การยิงสกัดอยู่หน้าการบุกเสมอ ไม่เหลือแล้ว prune เลื่อนให้)
static func flush_plan(st: BattleState, here: Dictionary) -> BattleState.Pend:
	var p := next(st, here)
	if p == null and bool(here.get("force", false)):
		p = _first_live(st)
	return p


# ---------------------------------------------------------------- ทอย
## ลูกเต๋า n ลูก (ไม่เกิน 60) จากสตรีม dice เป็น Array ของ int
static func _dice(dice: Rng, n: int) -> Array:
	var out: Array = []
	for i: int in mini(maxi(0, n), MAX_DICE):
		out.append(dice.d6())
	return out


## doRoll: act ของรายการนี้ (ไม่เกินหนึ่ง act ต่อครั้ง: อันถัดไปขึ้นกับสถานะหลังใช้อันนี้ ผู้เรียกใช้แล้วถาม next ใหม่)
## opt = {yes, gtg, brave} ของคนทอย (บอทได้จาก BtBot.choice) · รายการที่ไม่ต้องทอยหรือรออยู่ได้ []
## atk: hit (พ่นไม่ทอย) / wnd / sav {gtg} · shock {brave ไม่ทอย} · rez · chg: ow {use} → (การยิงสกัดเป็นรายการของมันเอง)
## → chr {roll, rr 0, keep 0} → cmove {to จาก charge_spots} · chrr: ทอยใหม่ chr {rr 1} ไม่งั้น chr {keep 1, roll เดิม}
static func roll(st: BattleState, p: BattleState.Pend, opt: Dictionary, dice: Rng) -> Array[Dictionary]:
	var acts: Array[Dictionary] = []
	if p == null:
		return acts
	if p.kind == BattleState.K_ATK:
		if p.stage == BattleState.S_HIT:
			acts.append({"a": "atk", "u": p.u, "t": p.t, "how": BattleState.HOWS[p.how],
				"hit": [] if p.tr else _dice(dice, p.shots)})
		elif p.stage == BattleState.S_WOUND:
			acts.append({"a": "wnd", "u": p.u, "t": p.t, "wound": _dice(dice, BtPend.wound_dice(p))})
		elif p.stage == BattleState.S_SAVE:
			var g: bool = bool(opt.get("gtg", false)) and BtStrats.can(st, "gtg", p.def)
			acts.append({"a": "sav", "u": p.u, "t": p.t, "save": _dice(dice, BtPend.save_dice(p)), "gtg": 1 if g else 0})
	elif p.kind == BattleState.K_SHOCK:
		if p.stage == BattleState.S_SHOCK:
			var b: bool = bool(opt.get("brave", false)) and BtStrats.can(st, "brave", p.att)
			acts.append({"a": "shock", "u": p.u, "roll": [] if b else _dice(dice, 2), "brave": 1 if b else 0})
	elif p.kind == BattleState.K_REZ:
		if p.stage == BattleState.S_REZ:
			acts.append({"a": "rez", "u": p.u, "roll": _dice(dice, mini(p.n, MAX_REZ))})
	elif p.kind == BattleState.K_CHG:
		var stg := p.stage
		if stg == BattleState.S_OWATK and not _ow_waiting(st, p):
			stg = BattleState.S_CHARGE
		if stg == BattleState.S_OW:
			acts.append({"a": "ow", "u": p.u, "t": p.t, "use": 1 if bool(opt.get("yes", false)) else 0})
		elif stg == BattleState.S_CHARGE:
			acts.append({"a": "chr", "u": p.u, "t": p.t, "roll": _dice(dice, 2), "rr": 0, "keep": 0})
		elif stg == BattleState.S_CHRR:
			if bool(opt.get("yes", false)) and BtStrats.can(st, "rr", p.att):
				acts.append({"a": "chr", "u": p.u, "t": p.t, "roll": _dice(dice, 2), "rr": 1, "keep": 0})
			else:
				acts.append({"a": "chr", "u": p.u, "t": p.t, "roll": Array(p.roll), "rr": 0, "keep": 1})
		elif stg == BattleState.S_MOVE:
			var cm := cmove(st, p)
			if not cm.is_empty():
				acts.append(cm)
	return acts


## sendCMove: เดินเข้าติดฐานหลังบุกถึง (ระยะ = ผลทอยรวม x 1000 MI) · ไม่มีหมู่ใดหมู่หนึ่งได้ {}
static func cmove(st: BattleState, p: BattleState.Pend) -> Dictionary:
	if p == null:
		return {}
	var s := st.squad(p.u)
	var t := st.squad(p.t)
	if s == null or t == null:
		return {}
	var to := BtMoves.charge_spots(st, s, t, BtCombat.total(p.roll) * 1000)
	return {"a": "cmove", "u": p.u, "t": p.t, "to": BtMoves.pts(to)}


## rollFor: ลูกทั้งครั้งของการโจมตี (act shoot ของเทสต์) เข้าเป้า n (พ่นไม่ทอย) เจาะ 2n เซฟ 2n แถวละไม่เกิน 60
## ไม่มีอาวุธ: ทุกแถวว่าง
static func roll_whole(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, how: int, dice: Rng) -> Dictionary:
	var m := BtCombat.atk_math(st, s, t, how)
	var n: int = int(m["shots"]) if not m.is_empty() else 0
	var tr: bool = not m.is_empty() and bool(m["tr"])
	var hit: Array = [] if tr else _dice(dice, n)
	var wound := _dice(dice, n * 2)
	var save := _dice(dice, n * 2)
	return {"hit": hit, "wound": wound, "save": save}
