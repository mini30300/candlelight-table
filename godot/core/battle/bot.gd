class_name BtBot
extends RefCounted
## บอท (R1_PORT_SPEC หัวข้อ bot.gd): botChoice / botSquads / expDmg / melee / botStep / ส่วนกติกาของ botTick ของหน้าเก่า
## อ่านสถานะอย่างเดียวแล้วคืน act ทีละอัน (stay/skip ก็ทีละอัน) ผู้เรียกใช้ act แล้วถามใหม่ ไม่แก้อะไรเลย
## ระยะเทียบเป็นกำลังสองตรงเป๊ะ (นิ้วของหน้าเก่า x 1000 = MI) ความเสียหายที่คาดเป็นเศษส่วน [ตัวเศษ, ตัวส่วน] เทียบด้วยการคูณไขว้
## ลูกเต๋าของบอท (รักษา ระเบิดมือ ยิง) มาจากสตรีม bot:<seat> ที่ผู้เรียกให้ · CP ของระเบิดมือตัวรับ act หัก
## ไม่ดูคิวรอทอย: ผู้เรียกรอให้คิวว่างก่อนถามเหมือน botTick (finished_act ดูเอง)

## ยืนบนจุดแล้วไม่ไปไหนถ้าศัตรูใกล้ไม่ถึงนี้ (หน่วยประชิด, MI)
const HOLD_NEAR := 14000
## หน่วยประชิดที่ศัตรูใกล้กว่านี้ไม่ไปจุด ไปตีแทน
const FIGHT_NEAR := 9000
## ไปจุด: หยุดก่อนถึงจุด 1200 MI · หน่วยประชิดหยุดห่างศัตรู 7000 · หน่วยยิง 1500
const OBJ_STOP := 1200
const MELEE_STOP := 7000
const GUN_STOP := 1500
## ระยะที่น้อยกว่านี้ไม่เดิน ยืนเฉย
const MIN_STEP := 800
## ปืนระยะไม่เกินนี้ (นิ้ว) นับเป็นหน่วยประชิด
const MELEE_RNG := 12
## บุก: ขอบห่างไม่เกิน 11 นิ้ว (หน่วยประชิด) / 7 นิ้ว (หน่วยยิงที่ตีคุ้มกว่า)
const CHARGE_MELEE := 11000
const CHARGE_GUN := 7000
## เพดานของ d2·4^j ใน _toward (2^58: คูณสี่อีกทีก็ยังไม่ถึง 2^63)
const SQRT_LIM := 288230376151711744


# ---------------------------------------------------------------- ทางเลือก
## botChoice: ทางเลือกของที่นั่งที่ทอยรายการนี้ (บอท Claude หรือคนที่ทอยอัตโนมัติ: คนจริงไม่ใช้ CP แทน)
## ยิงสกัดเมื่อ CP เหลือ 2 · บุกพลาดทอยใหม่เมื่อมี CP · หมอบหลบเมื่อโดนยิงหนักพอ · ใจเหล็กกับหน่วยแพง
static func choice(st: BattleState, p: BattleState.Pend) -> Dictionary:
	var out := {"yes": false, "gtg": false, "brave": false}
	if p == null:
		return out
	var pi := BtPend.roller_of(p)
	var q := st.seat(pi)
	var cp: int = q.cp if q != null else 0
	var auto: bool = q != null and not q.bot and not q.ai
	if p.kind == BattleState.K_CHG and p.stage == BattleState.S_OW:
		out["yes"] = not auto and cp >= 2
	elif p.kind == BattleState.K_CHG and p.stage == BattleState.S_CHRR:
		out["yes"] = not auto and cp >= 1
	elif p.kind == BattleState.K_ATK and p.stage == BattleState.S_SAVE:
		var t := st.squad(p.t)
		var inf: bool = t != null and BtCombat.inf(t.ti)
		out["gtg"] = not auto and cp >= 2 and not p.melee and inf and p.wounds >= 3 and p.sv > 3 \
			and BtStrats.can(st, "gtg", p.def)
	elif p.kind == BattleState.K_SHOCK:
		var s := st.squad(p.u)
		var ti: int = s.ti if s != null else _infantry()
		out["brave"] = not auto and cp >= 2 and BtStrats.can(st, "brave", p.att) and BtAbilities.num(ti, "pts") >= 90
	return out


## TY('infantry') ของหน้าเก่า (คีย์ที่ไม่รู้จักได้ชนิดแรก)
static func _infantry() -> int:
	var i := GameData.index_of("infantry")
	return i if i >= 0 else 0


# ---------------------------------------------------------------- ตัวช่วย
## botSquads: หมู่ที่ยังอยู่ของฝ่ายที่ถึงตา ที่นั่งเป็นบอท ตามลำดับที่สร้าง
static func squads(st: BattleState) -> Array[BattleState.Squad]:
	var out: Array[BattleState.Squad] = []
	for s: BattleState.Squad in st.alive_squads():
		if s.side != st.turn:
			continue
		var q := st.seat(s.pl)
		if q != null and q.bot:
			out.append(s)
	return out


## expDmg: ความเสียหายที่คาดของ s ใส่ t (how = BattleState.HOW_*) เป็น [ตัวเศษ, ตัวส่วน] ตรงเป๊ะ ไม่มีอาวุธหรือไม่มีนัด [0, 1]
## ทุกความน่าจะเป็นคูณหก: เข้า A = 7 − need (พ่น 6) · หกเข้า P6 = 1 (พ่น 0) · เจาะ W = 7 − wneed · ไม่เซฟ S = sv − 1 (เกิน 6 = 6)
## e·216 = นัด·(hw36·S·d + dw: A·(6 − S)·d + heel: 6·A·w เป้า) โดย hw36 = lh ? (A − P6)·W + 6·P6 : A·W
## คูณ (1 + แต้มต่อตัว / 100) ของเป้า: ตัวเศษ e216·(100N + pts) ตัวส่วน 216·100·N (N = max(1, n ของชนิด))
## ขนาด: นัด ≤ 60, e216 ต่อนัด ≤ ราวหมื่น, (100N + pts) ≤ ราวหมื่น: ตัวเศษ ≤ 1e10, ตัวส่วน ≤ 1e6 คูณไขว้ ≤ 1e17
static func exp_dmg(st: BattleState, s: BattleState.Squad, t: BattleState.Squad, how: int) -> PackedInt64Array:
	var m := BtCombat.atk_math(st, s, t, how)
	if m.is_empty() or int(m["shots"]) == 0:
		return PackedInt64Array([0, 1])
	var shots: int = m["shots"]
	var tr: bool = m["tr"]
	var a: int = 6 if tr else 7 - int(m["need"])
	var p6: int = 0 if tr else 1
	var w: int = 7 - int(m["wneed"])
	var sv: int = m["sv"]
	var sx: int = 6 if sv > 6 else sv - 1
	var dmg: int = m["dmg"]
	var hw36: int = (a - p6) * w + 6 * p6 if bool(m["lh"]) else a * w
	var e := hw36 * sx * dmg
	if bool(m["dw"]):
		e += a * (6 - sx) * dmg
	if bool(m["heel"]):
		e += 6 * a * BtAbilities.num(t.ti, "w")
	e *= shots
	var n := maxi(1, BtAbilities.num(t.ti, "n"))
	var pts := BtAbilities.num(t.ti, "pts")
	return PackedInt64Array([e * (100 * n + pts), 216 * 100 * n])


## a > b (เศษส่วนที่ตัวส่วนบวก)
static func gt(a: PackedInt64Array, b: PackedInt64Array) -> bool:
	return a[0] * b[1] > b[0] * a[1]


## melee: ไม่มีปืน หรือปืนระยะไม่เกิน 12 นิ้ว
static func melee(s: BattleState.Squad) -> bool:
	var g := BtAbilities.gun(s.ti)
	return g.is_empty() or BtAbilities.wnum(g, "rng") <= MELEE_RNG


## botSkip: ไม่มีอะไรให้ทำในเฟสนี้ (ทุกเครื่องตั้งธงเดียวกันจาก act)
static func _skip(st: BattleState, s: BattleState.Squad) -> Dictionary:
	return {"a": "skip", "u": s.id, "ph": st.phase_name()}


static func _stay(s: BattleState.Squad) -> Dictionary:
	return {"a": "stay", "u": s.id}


## ลูกเต๋า n ลูกจากสตรีม (null = แค่ดูว่ามี act ไหม ไม่ทอย)
static func _roll(dice: Rng, n: int) -> Array:
	var out: Array = []
	if dice == null:
		return out
	for i: int in mini(n, BtRoller.MAX_DICE):
		out.append(dice.d6())
	return out


## จุดจาก c ไปทาง (gx, gz) เป็นระยะ step MI (ยาวศูนย์ = ที่เดิม เหมือน || 1 ของหน้าเก่า)
## ความยาวคิดละเอียด: isqrt(d2·4^j)/2^j (d2·4^j ไม่เกิน 2^58) isqrt ตรง ๆ ของเวกเตอร์สั้นคลาดเป็นร้อย MI
## ตัวเศษ dx·step·2^j: |dx|·2^j ไม่เกินราว 2^30, step ไม่เกินราว 1e5 = ไม่เกินราว 1e14
static func _toward(c: PackedInt64Array, gx: int, gz: int, step: int) -> PackedInt64Array:
	var dx := gx - c[0]
	var dz := gz - c[1]
	var q := dx * dx + dz * dz
	if q == 0:
		return PackedInt64Array([c[0], c[1]])
	var k := 1
	while q < SQRT_LIM:
		q *= 4
		k *= 2
	var l := Fx.isqrt(q)
	return PackedInt64Array([c[0] + Fx.js_round(dx * step * k, l), c[1] + Fx.js_round(dz * step * k, l)])


## ศัตรูที่ใกล้ที่สุด (ระยะใกล้สุดระหว่างโมเดล ตรงเป๊ะ เท่ากันเอาหมู่แรก)
static func _nearest(s: BattleState.Squad, foes: Array[BattleState.Squad]) -> BattleState.Squad:
	var best: BattleState.Squad = null
	var bd := 0
	for q: BattleState.Squad in foes:
		var d2 := BtSquads.dist2_min(s, q)
		if best == null or d2 < bd:
			best = q
			bd = d2
	return best


# ---------------------------------------------------------------- เฟสเดิน
## การตัดสินใจเดินของหมู่ s (ยังไม่วางแผน): {a: skip|stay} หรือ {a: smove, u, how, x, z} = เป้าที่ส่งให้ plan_move
## ไม่มีศัตรู: ข้าม · ติดประชิด: ถอยถ้าไม่ใช่หน่วยประชิดและอีกฝ่ายตีเราได้มากกว่า ไม่งั้นยืน
## ยืนบนจุด (ไม่เกิน OBJ_R) และไม่ใช่ (หน่วยประชิดที่ศัตรูใกล้ไม่เกิน 14") ยืนเฝ้า
## จุดที่ใกล้สุดที่ฝ่ายเรายังไม่คุมถ้าไม่เกินสองเท่าระยะเดิน + OBJ_R (หน่วยประชิดที่ศัตรูใกล้กว่า 9" ไม่ไป)
## ไม่ไปจุด: หน่วยประชิด ไม่มีจุด หรือศัตรูใกล้กว่า 7/10 ของระยะจุด ไปหาศัตรูแทน (ระยะ = ระยะใกล้สุดถึงศัตรู)
## หน่วยยิง: ยืนยิงถ้าศัตรูไม่เกิน 17/20 ของระยะยิงกับปืน hv หรือไม่เกิน 3/5 ของระยะยิง
## เดินไม่เกินระยะเดิน หยุดก่อนเป้า (จุด 1200 MI, ศัตรู 7000 / 1500 MI) เหลือไม่ถึง 800 MI ยืนเฉย
static func move_decision(st: BattleState, s: BattleState.Squad) -> Dictionary:
	var foes := BtSquads.real_foes(st, s)
	if foes.is_empty():
		return _skip(st, s)
	var mv: int = BtAbilities.num(s.ti, "mv") * 1000
	var mel := melee(s)
	if BtSquads.is_engaged(st, s):
		var e: BattleState.Squad = BtSquads.engaged_with(st, s)[0]
		if not mel and gt(exp_dmg(st, e, s, BattleState.HOW_FIGHT), exp_dmg(st, s, e, BattleState.HOW_FIGHT)):
			var away := BtSquads.center(e)
			var c0 := BtSquads.center(s)
			var fb := _toward(c0, c0[0] * 2 - away[0], c0[1] * 2 - away[1], mv)
			return {"a": "smove", "u": s.id, "how": "fb", "x": fb[0], "z": fb[1]}
		return _stay(s)
	var c := BtSquads.center(s)
	var obj_r: int = GameData.const_int("OBJ_R", 3) * 1000
	var on_obj := false
	var goal: BattleState.Obj = null
	var gd2 := 0
	for o: BattleState.Obj in st.objs:
		var d2 := Fx.dist2(o.x, o.z, c[0], c[1])
		if d2 <= obj_r * obj_r:
			on_obj = true
		if BtObjectives.ctl(st, o) == s.side:
			continue
		if goal == null or d2 < gd2:
			gd2 = d2
			goal = o
	var nf := _nearest(s, foes)
	var fd2 := BtSquads.dist2_min(s, nf)
	if on_obj and not (mel and fd2 <= HOLD_NEAR * HOLD_NEAR):
		return _stay(s)
	var reach := 2 * mv + obj_r
	var for_obj: bool = goal != null and gd2 <= reach * reach and not (mel and fd2 < FIGHT_NEAR * FIGHT_NEAR)
	var gx := 0
	var gz := 0
	if goal != null:
		gx = goal.x
		gz = goal.z
	# fd < 7/10 gd: 100·fd² < 49·gd² (ระยะไม่ติดลบ ไม่เกินราว 5e12)
	if not for_obj and (mel or goal == null or 100 * fd2 < 49 * gd2):
		var fc := BtSquads.center(nf)
		gx = fc[0]
		gz = fc[1]
		gd2 = fd2
	var g := BtAbilities.gun(s.ti)
	if not for_obj and not mel and not g.is_empty():
		var rng: int = BtAbilities.wnum(g, "rng") * 1000
		# fd ≤ 17/20 rng: 400·fd² ≤ 289·rng² · fd ≤ 3/5 rng: 25·fd² ≤ 9·rng²
		if BtAbilities.wflag(g, "hv") and 400 * fd2 <= 289 * rng * rng:
			return _stay(s)
		if 25 * fd2 <= 9 * rng * rng:
			return _stay(s)
	var stop: int = OBJ_STOP if for_obj else (MELEE_STOP if mel else GUN_STOP)
	# เหลือไม่ถึง 800 MI: gd − stop < 800 (ไปจุดแล้ว gd − 1200 ติดลบปัดเป็นศูนย์ก็ยังน้อยกว่า)
	var lim := stop + MIN_STEP
	if gd2 < lim * lim:
		return _stay(s)
	var step := mini(mv, Fx.isqrt(gd2) - stop)
	var p := _toward(c, gx, gz, step)
	return {"a": "smove", "u": s.id, "how": "move", "x": p[0], "z": p[1]}


# ---------------------------------------------------------------- เฟสยิง เฟสบุก
## act เฟสยิงของหมู่ s: หมอรักษาหมู่แรก (ลำดับที่สร้าง รวมตัวเอง) ที่รักษาได้ · ไม่มีปืนข้าม
## ยิงศัตรูจริงที่ยิงได้และคาดว่าเสียหายมากที่สุด (มากกว่าจริงจึงเปลี่ยน) · ไม่มีเป้า: ระเบิดมือใส่ศัตรูจริงหมู่แรกที่ปาได้
## เมื่อที่นั่งมี CP ตั้งแต่ 2 และใช้ได้ ไม่งั้นข้าม
static func shoot_act(st: BattleState, s: BattleState.Squad, dice: Rng) -> Dictionary:
	if BtAbilities.num(s.ti, "heal") != 0:
		for q: BattleState.Squad in st.alive_squads():
			if BtCombat.can_heal(st, s, q):
				var r := _roll(dice, 1)
				return {"a": "heal", "u": s.id, "t": q.id, "roll": int(r[0]) if not r.is_empty() else 0}
	if BtAbilities.gun(s.ti).is_empty():
		return _skip(st, s)
	var foes := BtSquads.real_foes(st, s)
	var best: BattleState.Squad = null
	var bv := PackedInt64Array([0, 1])
	for t: BattleState.Squad in foes:
		if str(BtCombat.shot_why_not(st, s, t)["key"]) != "":
			continue
		var v := exp_dmg(st, s, t, BattleState.HOW_SHOOT)
		if gt(v, bv):
			bv = v
			best = t
	if best == null:
		var seat := st.seat(s.pl)
		for t: BattleState.Squad in foes:
			if str(BtCombat.gren_why_not(st, s, t)["key"]) != "":
				continue
			if seat != null and seat.cp >= 2 and BtStrats.can(st, "gren", s.pl):
				return {"a": "gren", "u": s.id, "t": t.id, "roll": _roll(dice, 6)}
			break
		return _skip(st, s)
	var m := BtCombat.atk_math(st, s, best, BattleState.HOW_SHOOT)
	if m.is_empty() or int(m["shots"]) == 0:
		return _skip(st, s)
	return {"a": "atk", "u": s.id, "t": best.id, "how": "shoot", "hit": [] if bool(m["tr"]) else _roll(dice, int(m["shots"]))}


## act เฟสบุกของหมู่ s ({} = หมู่นี้ไม่ต้องทำอะไร: บุกแล้ว วิ่ง ถอย หรือติดประชิด)
## เป้า = ศัตรูจริงที่บุกได้ที่ขอบใกล้สุด (เท่ากันเอาหมู่แรก) · บุกเมื่อเป็นหน่วยประชิด หรือตีคาดว่าได้มากกว่ายิง 6/5 เท่า
## และขอบห่างไม่เกิน 11" (ประชิด) / 7" ไม่งั้นข้าม
static func charge_act(st: BattleState, s: BattleState.Squad) -> Dictionary:
	if s.ch_done or s.adv or s.fell or BtSquads.is_engaged(st, s):
		return {}
	var tg: BattleState.Squad = null
	var td := 0
	for t: BattleState.Squad in BtSquads.real_foes(st, s):
		if str(BtCombat.charge_why_not(st, s, t)["key"]) != "":
			continue
		var d := BtSquads.edge(s, t)
		if tg == null or d < td:
			td = d
			tg = t
	if tg == null:
		return _skip(st, s)
	var mel := melee(s)
	var worth := mel
	if not worth:
		var f := exp_dmg(st, s, tg, BattleState.HOW_FIGHT)
		var g := exp_dmg(st, s, tg, BattleState.HOW_SHOOT)
		# fight > 6/5 shoot: 5·fight > 6·shoot
		worth = 5 * f[0] * g[1] > 6 * g[0] * f[1]
	if not worth or not BtSquads.edge_within(s, tg, CHARGE_MELEE if mel else CHARGE_GUN):
		return _skip(st, s)
	return {"a": "chg", "u": s.id, "t": tg.id}


# ---------------------------------------------------------------- หนึ่งก้าว
## botStep: act ถัดไปของบอทฝ่ายที่ถึงตา ({} = ทีมบอทนี้ทำครบเฟสนี้แล้ว หรือไม่ใช่เฟสของบอท)
## หมู่ตามลำดับที่สร้าง ข้ามหมู่ที่ทำแล้วในเฟสนี้ · stay/skip มาทีละอัน การกระทำจริงจบก้าว (ผู้เรียกใช้ act แล้วถามใหม่)
## dice = สตรีม bot:<seat> (null = แค่ดูว่ามี act ไหม ไม่ทอย แถวลูกเต๋าว่าง)
static func next_act(st: BattleState, dice: Rng) -> Dictionary:
	if not st.on or st.over:
		return {}
	var ph := st.phase
	if ph != BattleState.PH_MOVE and ph != BattleState.PH_SHOOT and ph != BattleState.PH_CHARGE:
		return {}
	for s: BattleState.Squad in squads(st):
		if ph == BattleState.PH_MOVE:
			if s.moved:
				continue
			var d := move_decision(st, s)
			if str(d["a"]) != "smove":
				return d
			var to := BtMoves.plan_move(st, s, int(d["x"]), int(d["z"]))
			return {"a": "smove", "u": s.id, "to": BtMoves.pts(to), "how": str(d["how"])}
		if ph == BattleState.PH_SHOOT:
			if s.shot:
				continue
			return shoot_act(st, s, dice)
		var a := charge_act(st, s)
		if not a.is_empty():
			return a
	return {}


## ส่วนกติกาของ botTick: endph {ph} เมื่อฝ่ายที่ถึงตามีที่นั่งบอท คิวรอทอยว่าง บอทไม่มีอะไรทำแล้ว (next_act ว่าง)
## และที่นั่งที่ไม่ใช่บอทของฝ่ายนั้นกดจบครบ (ฝ่ายที่มีแต่บอทครบเสมอ) ไม่งั้น {}
## ไม่ตั้ง done ของที่นั่งบอท (หน้าเก่าตั้งเฉพาะเครื่องเจ้าของห้อง ไม่มีกติกาไหนอ่าน, §7 #17)
## เฟสคำสั่งกับเฟสตีเดินเอง ไม่ใช่งานของบอท
static func finished_act(st: BattleState) -> Dictionary:
	if not st.on or st.over or not st.pend.is_empty():
		return {}
	var ph := st.phase
	if ph != BattleState.PH_MOVE and ph != BattleState.PH_SHOOT and ph != BattleState.PH_CHARGE:
		return {}
	var has_bot := false
	var done := true
	for q: BattleState.Seat in st.team_seats(st.turn):
		if q.bot:
			has_bot = true
		elif not q.done:
			done = false
	if not has_bot or not done:
		return {}
	if not next_act(st, null).is_empty():
		return {}
	return {"a": "endph", "ph": st.phase_name()}
