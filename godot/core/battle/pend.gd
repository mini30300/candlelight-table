class_name BtPend
extends RefCounted
## คิวรอทอยเดียวของทุกอย่าง (R1_PORT_SPEC §1 pend): ยิง ตี ยิงสกัด บุก ทดสอบขวัญ ซ่อมตัวเอง ระเบิดมือ รักษา ทอยใหม่
## ตัวใช้ผลไม่ทอยเอง ลูกที่ขาดเติมจากสตรีม fallback:<seq>:<stage> (pad) ทุกเครื่องได้ค่าเดียวกัน
## จบการรบ (checkOver) ไม่เรียกจากที่นี่: pend อยู่ซ้ายของ turn ผู้เรียก (acts / battle) ตรวจหลังทุก act และหลัง prune
## เหตุการณ์ "p" ของการโจมตีเป็นข้อความ "<u>><t>"

## ดาเมจของส้นเท้า (ตายทันที)
const SLAY_DMG := 999
## ลูกเต๋าต่อจังหวะที่เซิร์ฟเวอร์ส่งได้มากสุด เกินนี้เติมจาก fallback เป็นเรื่องปกติ
const DICE_CAP := 60
## ระยะประชิดเป็น MI (ENGAGE 1")
const ENGAGE_MI := 1000
## edge ของหมู่ว่างบนหน้าเก่าเป็น 1e9 นิ้ว ระยะบุกจึงเป็นค่านี้ (ทิ้งทีหลังใน prune)
const FAR_NEED := 999999999


# ---------------------------------------------------------------- คิว
## pendAt: รายการแรกของ u (t "" = เป้าไหนก็ได้; kind < 0 = ชนิดไหนก็ได้) ทุกขั้น
static func pend_at(st: BattleState, u: String, t: String, kind: int) -> BattleState.Pend:
	for p: BattleState.Pend in st.pend:
		if p.u == u and (t == "" or p.t == t) and (kind < 0 or p.kind == kind):
			return p
	return null


## unPend
static func remove(st: BattleState, p: BattleState.Pend) -> void:
	var i := st.pend.find(p)
	if i >= 0:
		st.pend.remove_at(i)


## mkPend: ต่อท้ายคิว
static func push(st: BattleState, p: BattleState.Pend) -> void:
	st.pend.append(p)


## ลูกเต๋า n ลูกจาก dice (ค่าที่ไม่ใช่ int เป็น 1 ค่านอก 1..6 ตัดเข้า) ขาดเท่าไรเติมจาก st.fallback(stage)
## ส่งมาน้อยกว่า min(n, 60) = ผู้ส่งผิด บันทึก dice_short [stage, ได้, ต้องการ]; เกิน 60 ที่เติมเป็นเรื่องปกติ
static func pad(st: BattleState, dice: Array, n: int, stage: String, out: Array[Dictionary]) -> PackedInt32Array:
	var r := PackedInt32Array()
	var k := mini(dice.size(), maxi(0, n))
	for i: int in k:
		var v: Variant = dice[i]
		r.append(Fx.clampi(int(v), 1, 6) if typeof(v) == TYPE_INT else 1)
	if r.size() < n:
		if dice.size() < mini(n, DICE_CAP):
			_say(st, out, "dice_short", [stage, dice.size(), n])
		var g := st.fallback(stage)
		while r.size() < n:
			r.append(g.d6())
	return r


## จำนวนลูกที่ได้ตั้งแต่ need ขึ้นไป (count ของหน้าเก่า)
static func _count(d: PackedInt32Array, need: int) -> int:
	return BtCombat.count_at_least(d, need)


static func _alive(st: BattleState, id: String) -> int:
	return st.squad_alive(st.squad(id))


static func _say(st: BattleState, out: Array[Dictionary], key: String, args: Array) -> void:
	st.say(key, args)
	out.append(Events.make(Events.Id.LOG_LINE, {"key": key, "args": args.duplicate()}))


static func _pkey(p: BattleState.Pend) -> String:
	return "%s>%s" % [p.u, p.t]


# ---------------------------------------------------------------- การโจมตี
## mkAtk: สร้างการโจมตีต่อท้ายคิว ไม่มีอาวุธหรือไม่มีนัดคืน null
static func mk_atk(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, how: int) -> BattleState.Pend:
	var m := BtCombat.atk_math(st, s, t, how)
	if m.is_empty() or int(m["shots"]) == 0:
		return null
	var p := BattleState.Pend.new()
	p.kind = BattleState.K_ATK
	p.stage = BattleState.S_HIT
	p.how = how
	p.u = s.id
	p.t = t.id
	p.att = s.pl
	p.def = t.pl
	p.melee = bool(m["melee"])
	p.ow = how == BattleState.HOW_OW
	p.shots = int(m["shots"])
	p.need = int(m["need"])
	p.wneed = int(m["wneed"])
	p.sv = int(m["sv"])
	p.dmg = int(m["dmg"])
	p.su = int(m["su"])
	p.tr = bool(m["tr"])
	p.lh = bool(m["lh"])
	p.dw = bool(m["dw"])
	p.heel = bool(m["heel"])
	p.mk = bool(m["mk"])
	push(st, p)
	return p


## markHit: ยิงด้วยอาวุธชี้เป้าเข้าแล้ว เป้าถูกชี้ (mark_key ของตานี้)
static func mark_hit(st: BattleState, p: BattleState.Pend) -> void:
	if p.mk and p.hits != 0:
		var t := st.squad(p.t)
		if t != null:
			t.mk = st.mark_key()


## countHits: พ่นโดนทุกนัด · ได้ 6 นับเพิ่ม su · ได้ 6 กับ lh เจาะเลย (lethal)
static func count_hits(p: BattleState.Pend) -> void:
	var six := _count(p.hit_r, 6)
	p.hits = p.shots if p.tr else _count(p.hit_r, p.need) + p.su * six
	p.lethal = six if p.lh and not p.tr else 0


## applyHit: ลูกเข้าเป้า แล้วไปขั้นเจาะ (ไม่เข้าเลยจบ; เข้าด้วย 6 ทุกนัดกับ lh เจาะเลยไม่ต้องทอย)
static func apply_hit(st: BattleState, p: BattleState.Pend, dice: Array, out: Array[Dictionary]) -> void:
	if p == null or p.stage != BattleState.S_HIT:
		return
	var s := st.squad(p.u)
	if s != null:
		if p.how == BattleState.HOW_SHOOT:
			s.shot = true
		if p.how == BattleState.HOW_FIGHT:
			s.fought = true
	if p.tr:
		p.hit_r = PackedInt32Array()
	else:
		p.hit_r = pad(st, dice, p.shots, "hit", out)
	count_hits(p)
	mark_hit(st, p)
	out.append(Events.make(Events.Id.ATTACK_STAGE, {"p": _pkey(p), "stage": "hit", "dice": Array(p.hit_r)}))
	out.append(Events.make(Events.Id.HIT, {"p": _pkey(p), "n": p.hits}))
	p.stage = BattleState.S_WOUND
	if p.hits == 0:
		finish_atk(st, p, out)
	elif p.hits == p.lethal:
		apply_wnd(st, p, [], out)


## applyReroll: ทอยใหม่ลูกเข้าเป้าที่ต่ำสุดที่ไม่ผ่าน (ลูกแรกถ้าเท่ากัน) ก่อนทอยเจาะ ครั้งเดียว พ่นทอยใหม่ไม่ได้
## ไม่มีลูกที่ไม่ผ่านก็ไม่เปลี่ยนอะไร (CP ถูกหักไปแล้วที่ตัวรับ act เหมือนหน้าเก่า); v 0 = เติมหนึ่งลูกขั้น rr
static func apply_reroll(st: BattleState, p: BattleState.Pend, v: int, out: Array[Dictionary]) -> void:
	if p == null or p.stage != BattleState.S_WOUND or p.rr or p.tr:
		return
	var lo := -1
	for i: int in p.hit_r.size():
		if p.hit_r[i] < p.need and (lo < 0 or p.hit_r[i] < p.hit_r[lo]):
			lo = i
	if lo < 0:
		return
	p.rr = true
	p.hit_r[lo] = v if v != 0 else pad(st, [], 1, "rr", out)[0]
	count_hits(p)
	mark_hit(st, p)
	out.append(Events.make(Events.Id.ATTACK_STAGE, {"p": _pkey(p), "stage": "rr", "dice": [p.hit_r[lo]]}))
	out.append(Events.make(Events.Id.HIT, {"p": _pkey(p), "n": p.hits}))


## woundDice: ลูกเจาะที่ต้องทอย (เข้าที่เจาะเลยไม่ต้องทอย)
static func wound_dice(p: BattleState.Pend) -> int:
	return maxi(0, p.hits - p.lethal)


## saveDice: ลูกเซฟ (แผลตรงกับส้นเท้าเซฟไม่ได้)
static func save_dice(p: BattleState.Pend) -> int:
	return maxi(0, p.wounds - p.mortal - p.slay)


## applyWnd: เจาะ · ได้ 6 ใส่ heel ส้นเท้าหนึ่งครั้ง · ได้ 6 กับ dw เป็นแผลตรง · ไม่มีอะไรให้เซฟก็จบเลย
static func apply_wnd(st: BattleState, p: BattleState.Pend, dice: Array, out: Array[Dictionary]) -> void:
	if p == null or p.stage != BattleState.S_WOUND:
		return
	var nd := wound_dice(p)
	p.wound_r = pad(st, dice, nd, "wound", out)
	var six := _count(p.wound_r, 6)
	p.wounds = p.lethal + _count(p.wound_r, p.wneed)
	p.slay = 1 if p.heel and six != 0 else 0
	p.mortal = six - p.slay if p.dw else 0
	if nd != 0:
		out.append(Events.make(Events.Id.ATTACK_STAGE, {"p": _pkey(p), "stage": "wound", "dice": Array(p.wound_r)}))
	out.append(Events.make(Events.Id.WOUND, {"p": _pkey(p), "n": p.wounds}))
	if p.wounds == 0 or p.sv > 6 or save_dice(p) == 0:
		finish_atk(st, p, out)
		return
	p.stage = BattleState.S_SAVE


## applySav: เซฟ (gtg = หมอบหลบที่ใช้ CP แล้ว: เซฟดีขึ้นหนึ่งเฉพาะยิงและเซฟเกิน 3+) แล้วจบการโจมตี
static func apply_sav(st: BattleState, p: BattleState.Pend, dice: Array, gtg: bool, out: Array[Dictionary]) -> void:
	if p == null or p.stage != BattleState.S_SAVE:
		return
	if gtg and not p.melee and p.sv > 3:
		p.sv -= 1
		p.gtg = true
	p.save_r = pad(st, dice, save_dice(p), "save", out)
	p.saved = _count(p.save_r, p.sv)
	out.append(Events.make(Events.Id.ATTACK_STAGE, {"p": _pkey(p), "stage": "save", "dice": Array(p.save_r)}))
	out.append(Events.make(Events.Id.SAVE, {"p": _pkey(p), "n": p.saved}))
	finish_atk(st, p, out)


## nextVictim: ตัวที่เจ็บอยู่ตัวแรก ไม่งั้นตัวที่ใกล้จุดกลางของ from ที่สุด (เทียบแบบไม่หาร (n·mx − Σx)² + (n·mz − Σz)²
## น้อยกว่าจริงจึงเปลี่ยน ตัวแรกชนะเมื่อเท่ากัน); from null = ตัวแรก; from ไม่เหลือใคร = ใกล้ (0, 0) (sqCenter ของหมู่ว่าง)
static func next_victim(t: BattleState.Squad, from: BattleState.Squad) -> BattleState.Unit:
	if t == null or t.models.is_empty():
		return null
	for m: BattleState.Unit in t.models:
		if m.hp < BtAbilities.num(m.ti, "w"):
			return m
	if from == null:
		return t.models[0]
	var n := from.models.size()
	var sx := 0
	var sz := 0
	for q: BattleState.Unit in from.models:
		sx += q.x
		sz += q.z
	if n == 0:
		n = 1
	var best: BattleState.Unit = null
	var bd := -1
	for m: BattleState.Unit in t.models:
		# n ≤ 40, |x| ≤ 2e5 MI: ผลคูณไม่เกิน 1e14
		var dx := n * m.x - sx
		var dz := n * m.z - sz
		var dd := dx * dx + dz * dz
		if bd < 0 or dd < bd:
			bd = dd
			best = m
	return best


## dealDamage: n ครั้ง ครั้งละ dmg ใส่ t (hd ลดครึ่งปัดขึ้นถ้าต่ำกว่า 999) · โล่ชั้นหนึ่งรับไว้ทั้งครั้ง
## spill = ดาเมจเกินไหลไปตัวถัดไป (แผลตรง) ไม่งั้นทิ้ง · ตัวที่ตายออกจาก units ตามลำดับ (ลูกพระพายนอนรอลม)
## คืนตัวที่ตายตามลำดับ
static func deal_damage(st: BattleState, t: BattleState.Squad, from: BattleState.Squad, n: int, dmg: int, spill: bool,
		out: Array[Dictionary]) -> Array[BattleState.Unit]:
	var acc := {"sh": 0}
	return _deal(st, t, from, n, dmg, spill, out, acc)


static func _deal(st: BattleState, t: BattleState.Squad, from: BattleState.Squad, n: int, dmg0: int, spill: bool,
		out: Array[Dictionary], acc: Dictionary) -> Array[BattleState.Unit]:
	var killed: Array[BattleState.Unit] = []
	if t == null:
		return killed
	var dmg := dmg0
	if BtAbilities.flag(t.ti, "hd") and dmg < SLAY_DMG:
		# ดาเมจไม่ติดลบ: หารตัดเศษ = ปัดลง
		dmg = (dmg + 1) / 2
	for k: int in n:
		var left := dmg
		if t.vs > 0:
			t.vs -= 1
			acc["sh"] = int(acc["sh"]) + 1
			continue
		while left > 0:
			var m := next_victim(t, from)
			if m == null:
				break
			var take := mini(left, m.hp)
			m.hp -= take
			left -= take if spill else left
			if m.hp <= 0:
				st.remove_unit(m)
				killed.append(m)
				out.append(Events.make(Events.Id.DEATH, {"uid": m.id}))
				if BtAbilities.flag(m.ti, "wind"):
					BtAbilities.wind_fall(st, m)
					out.append(Events.make(Events.Id.FALLEN, {"uid": m.id}))
			else:
				out.append(Events.make(Events.Id.DAMAGE, {"uid": m.id, "hp": m.hp}))
	return killed


## finishAtk: ส้นเท้า (999 ไม่ไหล) → แผลตรง (ไหล) → แผลที่เซฟไม่ได้ (ไม่ไหล) → หลังตาย (ม้าไม้) → ฆ่าแล้วฟื้น (ตี)
## บันทึก atk_done [u, t, how, hits, shots, wounds, saved, ตาย, ส้นเท้า, แผลตรง, โล่, ฟื้น, หมดหน่วย 0/1]
static func finish_atk(st: BattleState, p: BattleState.Pend, out: Array[Dictionary]) -> void:
	remove(st, p)
	p.stage = BattleState.S_DONE
	var s := st.squad(p.u)
	var t := st.squad(p.t)
	var dmg_n := save_dice(p) - p.saved if t != null else 0
	var killed: Array[BattleState.Unit] = []
	var acc := {"sh": 0}
	for step: Array in [[p.slay, SLAY_DMG, false], [p.mortal, p.dmg, true], [dmg_n, p.dmg, false]]:
		var n: int = step[0]
		if t == null or n <= 0 or st.squad_alive(t) == 0:
			continue
		killed.append_array(_deal(st, t, s, n, int(step[1]), bool(step[2]), out, acc))
	BtAbilities.after_kills(st, killed, out)
	var gk := 0
	if s != null and p.melee and not killed.is_empty() and BtAbilities.flag(s.ti, "gk"):
		gk = BtAbilities.glory_heal(st, s, killed.size(), out)
	var gone: int = 1 if t != null and st.squad_alive(t) == 0 else 0
	_say(st, out, "atk_done", [p.u, p.t, BattleState.HOWS[p.how], p.hits, p.shots, p.wounds, p.saved, killed.size(),
		p.slay, p.mortal, int(acc["sh"]), gk, gone])


# ---------------------------------------------------------------- ทดสอบขวัญ วิ่ง
## applyShock: สองลูกรวมกันถึงขวัญผ่าน ไม่ถึงขวัญเสีย · brave (ใช้ CP แล้ว) ผ่านโดยไม่ทอย
static func apply_shock(st: BattleState, p: BattleState.Pend, dice: Array, brave: bool, out: Array[Dictionary]) -> void:
	if p == null or p.stage != BattleState.S_SHOCK:
		return
	var s := st.squad(p.u)
	remove(st, p)
	p.stage = BattleState.S_DONE
	if s == null or st.squad_alive(s) == 0:
		return
	if brave:
		_say(st, out, "shock_brave", [s.id])
		return
	p.roll = pad(st, dice, 2, "shock", out)
	var tot := BtCombat.total(p.roll)
	var ok := tot >= p.need
	s.shaken = not ok
	out.append(Events.make(Events.Id.SHOCK, {"sid": s.id, "pass": ok}))
	_say(st, out, "shock_roll", [s.id, tot, p.need, 1 if ok else 0])


## applyAdv: วิ่ง ลูกเดียว (ไม่ค้างในคิว); roll นอก 1..6 เป็น 1 (หน้าเก่า roll|0 || 1)
static func apply_adv(st: BattleState, s: BattleState.Squad, roll: int, out: Array[Dictionary]) -> void:
	if s == null:
		return
	var r: int = roll if roll >= 1 and roll <= 6 else 1
	s.adv = true
	s.adv_r = r
	_say(st, out, "adv_roll", [s.id, r])


# ---------------------------------------------------------------- บุก
## owOk: เป้ายิงสกัดได้ไหม: มีปืน ไม่ติดประชิด มี CP ทีมยังไม่ใช้ ยังไม่เคยสกัดตานี้ ขอบห่างไม่เกินระยะยิง (+1 MI)
static func ow_ok(st: BattleState, t: BattleState.Squad, s: BattleState.Squad) -> bool:
	var g := BtAbilities.gun(t.ti)
	if g.is_empty() or BtSquads.is_engaged(st, t) or not BtStrats.can(st, "ow", t.pl) or t.ow_used:
		return false
	return BtSquads.edge_within(t, s, BtAbilities.wnum(g, "rng") * 1000 + 1)


## declareCharge: ประกาศบุก ต้องทอยได้ max(2, ขอบห่าง − 1" ปัดขึ้น) นิ้ว (รากปัดขึ้นตรงเป๊ะด้วย isqrt_ceil)
static func declare_charge(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, out: Array[Dictionary]) -> BattleState.Pend:
	s.ch_done = true
	var p := BattleState.Pend.new()
	p.kind = BattleState.K_CHG
	p.u = s.id
	p.t = t.id
	p.att = s.pl
	p.def = t.pl
	p.need = charge_need(s, t)
	p.stage = BattleState.S_OW if ow_ok(st, t, s) else BattleState.S_CHARGE
	push(st, p)
	_say(st, out, "chg_declare", [s.id, t.id, p.need])
	return p


## ระยะที่ต้องทอยได้ของการบุก (นิ้ว): หมู่ว่างได้ FAR_NEED เหมือน edge 1e9 ของหน้าเก่า
static func charge_need(s: BattleState.Squad, t: BattleState.Squad) -> int:
	var d2 := BtSquads.dist2_min(s, t)
	if d2 >= BattleState.FAR2:
		return FAR_NEED
	var e := Fx.isqrt_ceil(d2) - BtSquads.radius(s) - BtSquads.radius(t) - ENGAGE_MI
	return maxi(2, Fx.cdiv(e, 1000))


## applyOw: เจ้าของเป้าตัดสินใจยิงสกัด · ใช้ได้: การยิงสกัดแทรกไว้หน้าการบุก แล้วการบุกรอ (owatk)
static func apply_ow(st: BattleState, p: BattleState.Pend, use: bool, out: Array[Dictionary]) -> void:
	if p == null or p.stage != BattleState.S_OW:
		return
	var s := st.squad(p.u)
	var t := st.squad(p.t)
	p.stage = BattleState.S_OWATK
	if use and s != null and t != null and BtStrats.use(st, "ow", t.pl, out):
		t.ow_used = true
		var a := mk_atk(st, t, s, BattleState.HOW_OW)
		if a != null:
			remove(st, a)
			st.pend.insert(st.pend.find(p), a)


## chgReady: ยิงสกัดใส่คนบุกจบหมดแล้ว (หรือไม่มี) การบุกไปทอยต่อได้
static func chg_ready(st: BattleState, p: BattleState.Pend) -> void:
	if p == null or p.kind != BattleState.K_CHG or p.stage != BattleState.S_OWATK:
		return
	for a: BattleState.Pend in st.pend:
		if a.kind == BattleState.K_ATK and a.ow and a.t == p.u:
			return
	p.stage = BattleState.S_CHARGE


## applyCharge: สองลูกรวมถึงระยะ = บุกถึง (รอเดิน move) · พลาดครั้งแรกและทีมยังทอยใหม่ได้ รอเลือก (chrr) · ไม่ถึงจบ
static func apply_charge(st: BattleState, p: BattleState.Pend, dice: Array, rerolled: bool, out: Array[Dictionary]) -> void:
	chg_ready(st, p)
	if p == null or (p.stage != BattleState.S_CHARGE and p.stage != BattleState.S_CHRR):
		return
	var s := st.squad(p.u)
	var t := st.squad(p.t)
	if st.squad_alive(s) == 0 or st.squad_alive(t) == 0:
		remove(st, p)
		p.stage = BattleState.S_DONE
		return
	p.roll = pad(st, dice, 2, "chr", out)
	var tot := BtCombat.total(p.roll)
	var ok := tot >= p.need
	if not ok and not rerolled and BtStrats.can(st, "rr", p.att):
		p.stage = BattleState.S_CHRR
		return
	p.ok = ok
	p.stage = BattleState.S_MOVE
	if not ok:
		remove(st, p)
		p.stage = BattleState.S_DONE
		_say(st, out, "chg_fail", [s.id, tot, p.need])
		return
	_say(st, out, "chg_ok", [s.id, tot])


## keepCharge: ไม่ทอยใหม่ บุกไม่ถึง
static func keep_charge(st: BattleState, p: BattleState.Pend, out: Array[Dictionary]) -> void:
	if p == null or p.stage != BattleState.S_CHRR:
		return
	var s := st.squad(p.u)
	remove(st, p)
	p.stage = BattleState.S_DONE
	if s != null:
		_say(st, out, "chg_fail", [s.id, BtCombat.total(p.roll), p.need])


## applyCMove: เดินเข้าติดฐาน จับคู่ s.models กับ to ตามลำดับ (ไม่ตรวจ ไม่มีเกณฑ์ 50 MI) ตัดเข้าขอบโต๊ะ
## ตั้ง charged ch_tgt moved และเลิก still · หมู่หันจากจุดกลางของตัวเองไปจุดกลางเป้า (ทับกันพอดีคงทิศเดิม)
static func apply_cmove(st: BattleState, p: BattleState.Pend, to: Array, out: Array[Dictionary]) -> void:
	if p == null or p.stage != BattleState.S_MOVE:
		return
	var s := st.squad(p.u)
	var t := st.squad(p.t)
	remove(st, p)
	p.stage = BattleState.S_DONE
	if s == null or t == null:
		return
	for i: int in mini(s.models.size(), to.size()):
		var m := s.models[i]
		var q := _point(to[i])
		m.x = Fx.clampi(q[0], -st.w * 500, st.w * 500)
		m.z = Fx.clampi(q[1], -st.d * 500, st.d * 500)
		out.append(Events.make(Events.Id.MOVE_STEP, {"uid": m.id, "gx": m.x, "gz": m.z}))
	s.charged = true
	s.ch_tgt = t.id
	s.moved = true
	s.still = false
	if not s.models.is_empty() and not t.models.is_empty():
		var a := BtSquads.center(s)
		var b := BtSquads.center(t)
		var f := Fx.norm1000(b[0] - a[0], b[1] - a[1])
		if f[0] != 0 or f[1] != 0:
			s.fx = f[0]
			s.fz = f[1]
	out.append(Events.make(Events.Id.CHARGE, {"sid": s.id, "tid": t.id}))


## จุด [x, z] ของ act (Array หรือ Packed สองค่า int) อย่างอื่นเป็น [0, 0] ตามตัวกรองของเซิร์ฟเวอร์
static func _point(v: Variant) -> PackedInt64Array:
	var tp := typeof(v)
	if tp == TYPE_ARRAY or tp == TYPE_PACKED_INT64_ARRAY or tp == TYPE_PACKED_INT32_ARRAY:
		var a := Array(v)
		if a.size() >= 2 and typeof(a[0]) == TYPE_INT and typeof(a[1]) == TYPE_INT:
			return PackedInt64Array([int(a[0]), int(a[1])])
	return PackedInt64Array([0, 0])


# ---------------------------------------------------------------- ระเบิดมือ รักษา ซ่อมตัวเอง
## applyGren: หกลูก ได้ 4+ ลูกละแผลตรงหนึ่ง (ไหล ไม่มีเซฟ) แล้วหลังตาย; คนปาใช้การยิงไปแล้ว (ไม่ค้างในคิว)
static func apply_gren(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, dice: Array, out: Array[Dictionary]) -> void:
	if s != null:
		s.shot = true
	var roll := pad(st, dice, 6, "gren", out)
	var mw := _count(roll, 4)
	var killed: Array[BattleState.Unit] = []
	if t != null and mw != 0:
		killed = deal_damage(st, t, s, mw, 1, true, out)
	BtAbilities.after_kills(st, killed, out)
	_say(st, out, "gren_done", [s.id if s != null else "", t.id if t != null else "", mw, killed.size()])


## applyHeal: ได้ HEAL_ON ขึ้นไป: ตัวที่เจ็บตัวแรก (ลำดับ units) +1 แผล ไม่มีใครเจ็บชุบตัวที่ล้มกลับมาหนึ่งตัว
## roll นอก 1..6 เป็น 1 (หน้าเก่า roll|0 || 1); คนรักษาใช้การกระทำไปแล้ว (shot)
static func apply_heal(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, roll: int, out: Array[Dictionary]) -> void:
	if s != null:
		s.shot = true
	var r: int = roll if roll >= 1 and roll <= 6 else 1
	var ok := r >= GameData.const_int("HEAL_ON", 3)
	var what := ""
	if ok and t != null:
		var hurt: BattleState.Unit = null
		for m: BattleState.Unit in t.models:
			if m.hp < BtAbilities.num(m.ti, "w"):
				hurt = m
				break
		if hurt != null:
			hurt.hp += 1
			what = hurt.id
			out.append(Events.make(Events.Id.HEAL, {"uid": hurt.id, "hp": hurt.hp}))
		else:
			var back := BtAbilities.revive_one(st, t, out)
			if back != null:
				what = back.id
	_say(st, out, "heal_roll", [s.id if s != null else "", t.id if t != null else "", r, 1 if ok else 0, what])


## applyRez: ซ่อมตัวเอง n ลูก ได้ถึง need ลุกลูกละตัว แผลเต็ม (revive_one ตามลำดับเลขที่หาย)
## ลูกพระพาย (wind): ลูกเดียว ถึงเกณฑ์ลุกที่เดิมแผลเต็ม ไม่ถึงร่างหายไปจริง
static func apply_rez(st: BattleState, p: BattleState.Pend, dice: Array, out: Array[Dictionary]) -> void:
	if p == null or p.stage != BattleState.S_REZ:
		return
	var s := st.squad(p.u)
	remove(st, p)
	p.stage = BattleState.S_DONE
	if p.wind:
		p.roll = pad(st, dice, 1, "rez", out)
		var up := s != null and p.roll[0] >= p.need
		var m: BattleState.Unit = BtAbilities.wind_up(st, s, out) if up else null
		if not up and s != null:
			BtAbilities.wind_gone(st, s, out)
		_say(st, out, "wind_roll", [p.u, p.roll[0], p.need, 1 if m != null else 0])
		return
	if s == null or st.squad_alive(s) == 0:
		return
	p.roll = pad(st, dice, p.n, "rez", out)
	var ok := _count(p.roll, p.need)
	var back := 0
	for k: int in ok:
		var m := BtAbilities.revive_one(st, s, out)
		if m == null:
			break
		m.hp = BtAbilities.num(s.ti, "w")
		back += 1
	_say(st, out, "rez_roll", [s.id, p.need, ok, back])


# ---------------------------------------------------------------- ใครทอย ทิ้งของค้าง ทั้งครั้ง
## rollerOf: เซฟของการโจมตีกับการตัดสินใจยิงสกัดเป็นของเจ้าของเป้า ที่เหลือของคนทำ
static func roller_of(p: BattleState.Pend) -> int:
	if (p.kind == BattleState.K_ATK and p.stage == BattleState.S_SAVE) or (p.kind == BattleState.K_CHG and p.stage == BattleState.S_OW):
		return p.def
	return p.att


## prunePend: ทิ้งของที่ไม่มีวันเกิดแล้ว (เป้าหมดหน่วย: จบการโจมตี · คนตีตายก่อนทอยเข้าเป้า · การบุกที่คนบุกหรือเป้าหมด)
## แล้ว v10: การบุกที่รอยิงสกัด (owatk) ไปขั้นบุกทันทีเมื่อการยิงสกัดจบ (หน้าเก่าทำในเฟรมของ myRoll ต่างกันแต่ละเครื่อง)
static func prune(st: BattleState, out: Array[Dictionary]) -> void:
	var i := 0
	while i < st.pend.size():
		var p := st.pend[i]
		if p.kind == BattleState.K_ATK and _alive(st, p.t) == 0:
			finish_atk(st, p, out)
			continue
		if p.kind == BattleState.K_ATK and _alive(st, p.u) == 0 and p.stage == BattleState.S_HIT:
			remove(st, p)
			continue
		if p.kind == BattleState.K_CHG and (_alive(st, p.u) == 0 or _alive(st, p.t) == 0):
			remove(st, p)
			continue
		i += 1
	for p: BattleState.Pend in st.pend.duplicate():
		chg_ready(st, p)


## applyWhole: การโจมตีทั้งครั้งที่ทอยมาครบ (act shoot) เล่นสามขั้นเหมือนกัน ไม่มีหมอบหลบ; ไม่มีอาวุธคืน null
static func apply_whole(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, hit: Array, wound: Array, save: Array,
		how: int, out: Array[Dictionary]) -> BattleState.Pend:
	var p := mk_atk(st, s, t, how)
	if p == null:
		return null
	apply_hit(st, p, hit, out)
	if p.stage == BattleState.S_DONE:
		return p
	apply_wnd(st, p, wound, out)
	if p.stage == BattleState.S_DONE:
		return p
	apply_sav(st, p, save, false, out)
	return p
