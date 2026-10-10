class_name BtCombat
extends RefCounted
## คณิตของการโจมตีและเงื่อนไขของการกระทำ (R1_PORT_SPEC §1 combat): ทอยเจาะ ใครยิงถึง ออร่า ตัวปรับ
## ค่าที่ต้องทอยของการยิง/ตี/ยิงสกัด และเหตุที่ยิง/รักษา/บุก/ปาระเบิดไม่ได้ ตามหน้าเก่า (atkMath, shotWhyNot …)
## ระยะเทียบเป็นกำลังสองตรงเป๊ะ: "ไม่เกิน X นิ้วบวกหนึ่งในพันนิ้ว" = d2 <= (X·1000 + 1)^2 (หนึ่งในพันนิ้วคือ 1 MI)
## ยิงวัดกลางฐานถึงกลางฐาน บุกและติดประชิดวัดขอบฐาน; ข้อมูลหน่วยอ่านผ่าน BtAbilities เท่านั้น
## เหตุที่ทำไม่ได้เป็น {key, args} ("" = ทำได้) ข้อความไทยอยู่ฝั่ง UI


# ---------------------------------------------------------------- ทอยเจาะและตัวเลขพื้นฐาน
## ค่าที่ต้องทอยเจาะ: แรง s เทียบความทน t ของเป้า (woundNeed)
static func wound_need(s: int, t: int) -> int:
	if s >= 2 * t:
		return 2
	if s > t:
		return 3
	if s == t:
		return 4
	if 2 * s <= t:
		return 6
	return 5


## ค่าที่ต้องทอยอยู่ในช่วง 2..6 เสมอ (clampNeed)
static func clamp_need(n: int) -> int:
	return Fx.clampi(n, 2, 6)


## ทหารเดินเท้า (INF): ช่อง inf ของข้อมูล; นอกตาราง = ไม่ใช่
static func inf(ti: int) -> bool:
	return GameData.is_inf(GameData.key_at(ti))


## จำนวนลูกที่ได้ไม่ต่ำกว่า need (count)
static func count_at_least(d: PackedInt32Array, need: int) -> int:
	var n := 0
	for v: int in d:
		if v >= need:
			n += 1
	return n


## ผลรวมลูกเต๋า (sum)
static func total(d: PackedInt32Array) -> int:
	var n := 0
	for v: int in d:
		n += v
	return n


# ---------------------------------------------------------------- ระยะ ออร่า กฎของกองทัพ
## ตัวไหนในหมู่ s ยิงถึงหมู่ t (shootersOf): [ตำแหน่งใน s.models, d2 ที่ใกล้สุด] ตามลำดับโมเดล
## ถึงเมื่อ d2 <= (rng·1000 + 1)^2 กลางฐานถึงกลางฐาน; อาวุธไม่มี rng หรือเป้าว่าง = ไม่มีใครยิงถึง
static func shooters_of(s: BattleState.Squad, t: BattleState.Squad, gun: Dictionary) -> Array[PackedInt64Array]:
	var out: Array[PackedInt64Array] = []
	if s == null or t == null or not gun.has("rng"):
		return out
	var lim := BtAbilities.wnum(gun, "rng") * 1000 + 1
	if lim < 0:
		return out
	var lim2 := lim * lim
	for i: int in s.models.size():
		var m := s.models[i]
		var best := BattleState.FAR2
		for q: BattleState.Unit in t.models:
			var d2 := Fx.dist2(m.x, m.z, q.x, q.z)
			if d2 < best:
				best = d2
		if best <= lim2:
			out.append(PackedInt64Array([i, best]))
	return out


## ความเจ็บปวดของเอลฟ์มืด (painOn): กองทัพ de ตั้งแต่รอบ PAIN_ROUND
static func pain_on(st: BattleState, ti: int) -> bool:
	return BtAbilities.text(ti, "fac") == "de" and st.round_no >= GameData.const_int("PAIN_ROUND", 3)


## สัญญาปีศาจ (pactOn): กองทัพ cx
static func pact_on(ti: int) -> bool:
	return BtAbilities.text(ti, "fac") == "cx"


## ถูกชี้เป้าในตานี้ไหม (marked)
static func marked(st: BattleState, t: BattleState.Squad) -> bool:
	return t != null and t.mk == st.mark_key()


## อยู่ในออร่าชนิด kind ไหม (inAura): หมู่ที่ยังอยู่ฝ่ายเดียวกัน (รวมตัวเอง) ที่มีออร่านั้น
## และระยะใกล้สุดไม่เกิน AURA_R นิ้วบวก 1 MI; kind ว่างไม่ตรงกับใคร (undefined ของหน้าเก่าไม่เท่ากับ "")
static func in_aura(st: BattleState, s: BattleState.Squad, kind: String) -> bool:
	if s == null or kind == "":
		return false
	var lim := _lim("AURA_R", 6)
	for q: BattleState.Squad in st.alive_squads():
		if q.side == s.side and BtAbilities.text(q.ti, "aura") == kind and _within(BtSquads.dist2_min(s, q), lim):
			return true
	return false


# ---------------------------------------------------------------- คณิตของการโจมตี
## ตัวเลขของการโจมตีหนึ่งครั้ง (atkMath) how = BattleState.HOW_*; ไม่มีอาวุธ = {}
## {melee, shots, need, wneed, mod, sv, dmg, su, tr, lh, dw, heel, mk, who, d2}
## ตี: ทุกโมเดลตี a (+1 ถ้า ca และบุกเข้ามาตานี้) · ยิง/ยิงสกัด: ตัวที่ยิงถึงยิง a + ระเบิด (เป้าทุกห้าตัว)
## + rf ถ้าใกล้สุดไม่เกินครึ่งระยะ (rng·500 + 1 MI: ระยะเป็นนิ้วเต็ม ครึ่งนิ้วจึงลงตัวใน MI)
## ตัวปรับรวมไม่เกินบวกลบหนึ่ง: hv ยืนนิ่ง, ออร่า hit, ความเจ็บปวด (ตี), ถูกชี้เป้า (ยิง) / st หรือออร่า veil (ยิง ไม่ใช่สกัด)
static func atk_math(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, how: int) -> Dictionary:
	if s == null or t == null:
		return {}
	var melee := how == BattleState.HOW_FIGHT
	var w: Dictionary = BtAbilities.mel(s.ti) if melee else BtAbilities.gun(s.ti)
	if w.is_empty():
		return {}
	var a := BtAbilities.wnum(w, "a")
	var shots := 0
	var who := PackedStringArray()
	var fury: int = 1 if melee and BtAbilities.flag(s.ti, "ca") and s.charged else 0
	if melee:
		for m: BattleState.Unit in s.models:
			shots += a + fury
			who.append(m.id)
	else:
		# จำนวนโมเดลไม่ติดลบ หารตัดเศษ = ปัดลง
		var blast: int = t.models.size() / 5 if BtAbilities.wflag(w, "bl") else 0
		var rf := BtAbilities.wnum(w, "rf")
		var half := BtAbilities.wnum(w, "rng") * 500 + 1
		for x: PackedInt64Array in shooters_of(s, t, w):
			var extra: int = rf if rf != 0 and _within(x[1], half) else 0
			shots += a + blast + extra
			who.append(s.models[x[0]].id)
	var mod := 0
	if not melee and BtAbilities.wflag(w, "hv") and s.still:
		mod += 1
	if in_aura(st, s, "hit"):
		mod += 1
	if melee and pain_on(st, s.ti):
		mod += 1
	if how == BattleState.HOW_SHOOT and marked(st, t):
		mod += 1
	if not melee and how != BattleState.HOW_OW and (BtAbilities.flag(t.ti, "st") or in_aura(st, t, "veil")):
		mod -= 1
	mod = Fx.clampi(mod, -1, 1)
	var tr := BtAbilities.wflag(w, "tr")
	var need := 0
	if tr:
		need = 0
	elif how == BattleState.HOW_OW:
		need = 6
	else:
		need = clamp_need(BtAbilities.wnum(w, "ws" if melee else "bs") - mod)
	var lance: int = 1 if melee and BtAbilities.wflag(w, "la") and s.charged else 0
	var wneed := clamp_need(wound_need(BtAbilities.wnum(w, "s"), BtAbilities.num(t.ti, "T")) - lance)
	var po := BtAbilities.wnum(w, "po")
	if po != 0 and inf(t.ti):
		wneed = mini(wneed, clamp_need(po))
	var aoc: int = 1 if BtAbilities.flag(t.ti, "aoc") else 0
	var ap := maxi(0, BtAbilities.wnum(w, "ap") - aoc)
	var inv0 := BtAbilities.num(t.ti, "inv")
	var inv_own: int = inv0 if inv0 != 0 else 7
	var inv_aura: int = GameData.const_int("BLESS_INV", 5) if in_aura(st, t, "bless") else 7
	var inv := mini(inv_own, inv_aura)
	var dmg := BtAbilities.wnum(w, "d")
	var su := BtAbilities.wnum(w, "su")
	if su == 0:
		su = 1 if melee and pact_on(s.ti) else 0
	return {
		"melee": melee, "shots": shots, "need": need, "wneed": wneed, "mod": mod,
		"sv": mini(BtAbilities.num(t.ti, "sv") + ap, inv), "dmg": dmg if dmg != 0 else 1, "su": su,
		"tr": tr, "lh": BtAbilities.wflag(w, "lh"), "dw": BtAbilities.wflag(w, "dw"),
		"heel": BtAbilities.flag(t.ti, "heel"), "mk": how == BattleState.HOW_SHOOT and BtAbilities.wflag(w, "mk"),
		"who": who, "d2": BtSquads.dist2_min(s, t),
	}


# ---------------------------------------------------------------- ทำได้ไหม: {key, args}, key "" = ได้ (ลำดับตรวจตามหน้าเก่า)
## ยิงได้ไหม (shotWhyNot): no_gun, own_side, already_shot, fell_back, advanced, engaged [ปืนพก 0/1],
## target_engaged, too_far [ระยะใกล้สุด MI, ระยะยิงเป็นนิ้ว]
static func shot_why_not(st: BattleState, s: BattleState.Squad, t: BattleState.Squad) -> Dictionary:
	if s == null:
		return _why("no_gun", [])
	return shot_why_not_with(st, s, t, BtSquads.engaged_with(st, s))


## shot_why_not เมื่อรู้ศัตรูที่ติดประชิด s อยู่แล้ว (eng = engaged_with(st, s) ของสถานะนี้) ผลเท่ากันทุกกรณี
## บอทถามทุกเป้าในเฟสเดียว จึงคิด eng ครั้งเดียวต่อหมู่ (โต๊ะแน่นหกฝ่ายเคยช้าเป็นสิบวินาทีต่อเทิร์น)
static func shot_why_not_with(st: BattleState, s: BattleState.Squad, t: BattleState.Squad,
		eng: Array[BattleState.Squad]) -> Dictionary:
	if s == null:
		return _why("no_gun", [])
	var w := BtAbilities.gun(s.ti)
	if w.is_empty():
		return _why("no_gun", [])
	if not BtSquads.can_target(st, s, t):
		return _why("own_side", [])
	if s.shot:
		return _why("already_shot", [])
	if s.fell and not BtAbilities.flag(s.ti, "fly") and not BtAbilities.flag(s.ti, "ttn"):
		return _why("fell_back", [])
	if s.adv and not BtAbilities.wflag(w, "as") and BtAbilities.text(s.ti, "fac") != "el":
		return _why("advanced", [])
	var pistol := BtAbilities.wflag(w, "pi")
	if not eng.is_empty() and not BtAbilities.flag(s.ti, "ttn") and (not pistol or not eng.has(t)):
		return _why("engaged", [1 if pistol else 0])
	if eng.is_empty() and t.side != s.side:
		# เป้าติดประชิดกับพวกเรา: ยิงไม่ได้ เดี๋ยวโดนพวกเดียวกัน (หมู่ของฝ่ายเราใน real_foes(t) = หมู่ที่ยังอยู่ของฝ่ายเรา
		# เมื่อเป้าอยู่คนละฝ่าย; เป้าฝ่ายเดียวกันตอนฟรีฟายไม่มีหมู่แบบนั้น) ไม่ต้องสร้างรายการศัตรูของเป้า
		for q: BattleState.Squad in st.squads:
			if q.side == s.side and not q.models.is_empty() and BtSquads.edge_within(t, q, BtSquads.ENGAGE_LIM):
				return _why("target_engaged", [])
	if shooters_of(s, t, w).is_empty():
		return _why("too_far", [BtSquads.dist_min(s, t), BtAbilities.wnum(w, "rng")])
	return _why("", [])


## รักษาได้ไหม (canHeal): หมอ ฝ่ายเดียวกัน ยังไม่ได้ใช้การกระทำ ไม่ได้ถอยมา ระยะใกล้สุดไม่เกิน heal นิ้วบวก 1 MI
## และเป้ามีคนเจ็บหรือมีคนล้ม
static func can_heal(st: BattleState, s: BattleState.Squad, t: BattleState.Squad) -> bool:
	if s == null or t == null:
		return false
	var heal := BtAbilities.num(s.ti, "heal")
	if heal == 0 or t.side != s.side or s.shot or s.fell:
		return false
	if not _within(BtSquads.dist2_min(s, t), heal * 1000 + 1):
		return false
	return _needs_care(t)


## เหตุที่รักษาไม่ได้ (healWhyNot): already_acted, nobody_hurt, too_far [ระยะรักษาเป็นนิ้ว]
## หน้าเก่าไม่แยกเหตุอื่น (ไม่ใช่หมอ ต่างฝ่าย ถอยมา) จึงตกไปที่ nobody_hurt หรือ too_far
static func heal_why_not(st: BattleState, s: BattleState.Squad, t: BattleState.Squad) -> Dictionary:
	if s == null or t == null:
		return _why("nobody_hurt", [])
	if can_heal(st, s, t):
		return _why("", [])
	if s.shot:
		return _why("already_acted", [])
	if not _needs_care(t):
		return _why("nobody_hurt", [])
	return _why("too_far", [BtAbilities.num(s.ti, "heal")])


## บุกได้ไหม (chargeWhyNot): enemies_only, charge_done, advanced, fell_back, engaged, too_far [ขอบฐาน MI]
## ขอบฐานไม่เกิน CHARGE_R นิ้วบวก 1 MI
static func charge_why_not(st: BattleState, s: BattleState.Squad, t: BattleState.Squad) -> Dictionary:
	return charge_why_not_with(st, s, t, -1)


## charge_why_not เมื่อรู้แล้วว่า s ติดประชิดไหม (engaged 1/0 = is_engaged(st, s) ของสถานะนี้, -1 = ให้คิดเอง)
static func charge_why_not_with(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, engaged: int) -> Dictionary:
	if not BtSquads.can_target(st, s, t) or t.side == s.side:
		return _why("enemies_only", [])
	if s.ch_done:
		return _why("charge_done", [])
	if s.adv and not BtAbilities.flag(s.ti, "ac") and not pain_on(st, s.ti):
		return _why("advanced", [])
	if s.fell and not BtAbilities.flag(s.ti, "fly") and not BtAbilities.flag(s.ti, "ttn"):
		return _why("fell_back", [])
	if engaged == 1 or (engaged < 0 and BtSquads.is_engaged(st, s)):
		return _why("engaged", [])
	if not BtSquads.edge_within(s, t, _lim("CHARGE_R", 12)):
		return _why("too_far", [BtSquads.edge(s, t)])
	return _why("", [])


## ปาระเบิดมือได้ไหม (grenWhyNot): not_infantry, already_shot, moved_fast, engaged, enemies_only, too_far
## ระยะใกล้สุดไม่เกิน GREN_R นิ้วบวก 1 MI (ค่าแต้มคำสั่งเป็นเรื่องของ BtStrats)
static func gren_why_not(st: BattleState, s: BattleState.Squad, t: BattleState.Squad) -> Dictionary:
	return gren_why_not_with(st, s, t, -1)


## gren_why_not เมื่อรู้แล้วว่า s ติดประชิดไหม (engaged 1/0 = is_engaged(st, s) ของสถานะนี้, -1 = ให้คิดเอง)
static func gren_why_not_with(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, engaged: int) -> Dictionary:
	if s == null or not inf(s.ti) or BtAbilities.gun(s.ti).is_empty():
		return _why("not_infantry", [])
	if s.shot:
		return _why("already_shot", [])
	if s.adv or s.fell:
		return _why("moved_fast", [])
	if engaged == 1 or (engaged < 0 and BtSquads.is_engaged(st, s)):
		return _why("engaged", [])
	if not BtSquads.can_target(st, s, t) or t.side == s.side:
		return _why("enemies_only", [])
	if not _within(BtSquads.dist2_min(s, t), _lim("GREN_R", 8)):
		return _why("too_far", [])
	return _why("", [])


# ---------------------------------------------------------------- ตัวช่วย
static func _why(key: String, args: Array) -> Dictionary:
	return {"key": key, "args": args}


## ระยะของค่าคงที่เป็นนิ้ว -> MI บวกหนึ่ง (ขอบ "ไม่เกิน X นิ้วบวกหนึ่งในพันนิ้ว" ของหน้าเก่า)
static func _lim(name: String, dflt_in: int) -> int:
	return GameData.const_int(name, dflt_in) * 1000 + 1


## d2 ไม่เกิน lim^2 (lim ติดลบ = ไม่มีระยะใดผ่าน)
static func _within(d2: int, lim: int) -> bool:
	return lim >= 0 and d2 <= lim * lim


## มีคนเจ็บ (hp ต่ำกว่า w ของชนิด) หรือมีคนล้ม (เหลือน้อยกว่า n0)
static func _needs_care(t: BattleState.Squad) -> bool:
	for m: BattleState.Unit in t.models:
		if m.hp < BtAbilities.num(m.ti, "w"):
			return true
	return t.models.size() < t.n0
