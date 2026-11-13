class_name BtTurn
extends RefCounted
## ผลัดตาและเฟส (R1_PORT_SPEC หัวข้อ turn.gd) ตามหน้าเก่า 33945–34118 และ startMatch 35409–35428
## เทิร์นของทีม: คำสั่ง (CP ทดสอบขวัญ ซ่อมตัวเอง ลม ม้าไม้ นับจุด) → เคลื่อนที่ → ยิง → บุก → ตะลุมบอน → ทีมถัดไป
## สิ่งที่เกิดเองตามกติกาอยู่ใน advance_step ผู้เรียก (Battle.advance) รันหลังทุก act ทุกเครื่องจึงข้ามเฟสตรงกัน
## ที่นั่งกับ CP ตายตัวตั้งแต่เริ่มนัด (§7 #10): ไม่มีอะไรที่นี่สร้างที่นั่งใหม่
## ผู้เรียก (acts / battle) เรียก check_over หลังตัวใช้ผลของ pend ทุกตัวและหลัง BtPend.prune

## ตัวคูณร่วมของจำนวนตัวต่อหมู่ทุกชนิด (ค.ร.น.): แต้มที่เหลือ Σ pts·(30/n) เป็นจำนวนเต็มพอดี (test_turn ตรวจกับข้อมูล)
const PTS_LCM := 30
## advance_step ต่อหนึ่ง advance ไม่เกินนี้ (guard ของหน้าเก่า)
const ADVANCE_GUARD := 60


static func _say(st: BattleState, out: Array[Dictionary], key: String, args: Array) -> void:
	st.say(key, args)
	out.append(Events.make(Events.Id.LOG_LINE, {"key": key, "args": args.duplicate()}))


static func _phase(st: BattleState, ph: int, out: Array[Dictionary]) -> void:
	st.phase = ph
	out.append(Events.make(Events.Id.PHASE, {"ph": st.phase_name()}))


static func _undone(st: BattleState) -> void:
	for p: BattleState.Seat in st.seats:
		p.done = false


# ---------------------------------------------------------------- ทีม
## ทีมนี้มีแต่บอท (teamIsBot): ไม่มีที่นั่งเลย = ไม่ใช่
static func team_is_bot(st: BattleState, t: int) -> bool:
	var ps := st.team_seats(t)
	if ps.is_empty():
		return false
	for p: BattleState.Seat in ps:
		if not p.bot:
			return false
	return true


## คนจริงในทีมกดเสร็จครบแล้ว (allDone) บอทไม่ต้องรอ
static func all_done(st: BattleState, t: int) -> bool:
	for p: BattleState.Seat in st.team_seats(t):
		if not p.bot and not p.done:
			return false
	return true


## ทีมที่ยังมีตัว (teamsAlive) รวมร่างที่รอลม
static func teams_alive(st: BattleState) -> PackedInt32Array:
	var out := PackedInt32Array()
	for t: int in st.teams:
		if st.live_of(t) > 0:
			out.append(t)
	return out


# ---------------------------------------------------------------- เริ่มนัด
## เริ่มนัด (startMatch ส่วนกติกา) บนสถานะที่ยังไม่ได้วางกอง: ล้างสถานะนัด ทุกที่นั่ง CP 1
## ที่นั่งคนที่ไม่มี pid ได้ pid ประจำเครื่อง "L<ที่นั่ง>" (D8) ที่นั่งที่กองว่างได้กองผูก seed (§7 #12)
## วางกอง วางจุดยึด (ไม่ใช่โหมดตีกันจนตาย และไม่ได้ใส่มาจากภายนอก) ตรวจจบ แล้วเริ่มตาของทีมแรกที่ยังมีตัว
## บันทึก match_start [เป้าหมาย, จำนวนจุด, รอบสุดท้าย, แต้มกองทัพต่อทีม...]; advance เป็นงานของ Battle.start
static func start_match(st: BattleState, out: Array[Dictionary]) -> void:
	st.on = true
	st.over = false
	st.winner = BattleState.NO_WINNER
	st.turn = 0
	st.round_no = 1
	st.phase = BattleState.PH_CMD
	st.cmd_wait = false
	st.log_lines.clear()
	st.pend.clear()
	st.used = {}
	st.fights = PackedStringArray()
	st.fights_null = false
	st.fight_at = 0
	for p: BattleState.Seat in st.seats:
		p.done = false
		p.cp = 1
		if not p.bot and p.pid == "":
			p.pid = "L%d" % p.id
		if not BtArmy.has_units(st, p.id):
			BtArmy.auto_list(st, p.id, null)
	st.vp = PackedInt64Array()
	st.vp.resize(st.teams)
	BtArmy.deploy(st, out)
	if st.goal == BattleState.GOAL_KILL:
		st.objs.clear()
	elif st.objs.is_empty():
		BtObjectives.place(st)
	var args: Array = [BattleState.GOALS[st.goal], st.objs.size(), st.max_round()]
	for t: int in st.teams:
		args.append(BtArmy.team_pts(st, t))
	_say(st, out, "match_start", args)
	check_over(st, out)
	if not st.over:
		st.turn = 0
		while st.live_of(st.turn) == 0 and st.turn < st.teams - 1:
			st.turn += 1
		start_turn(st, out)


# ---------------------------------------------------------------- เทิร์น
## ต้นเทิร์น (startTurn) ลำดับนี้เป็นโพรโทคอล: ล้างยิงสกัดทุกหมู่ที่ยังอยู่ + ล้างธงและขวัญของทีมในตา → โล่กลับมา
## → ทุกที่นั่งยังไม่เสร็จ → เฟสคำสั่ง → ทุกที่นั่งของทีม +1 CP → ทดสอบขวัญ (เหลือไม่ถึงครึ่ง ไม่ใช่ brave ไม่อยู่ในออร่า ld)
## → ซ่อมตัวเอง (rez ที่มีตัวหาย ในออร่า rez ใช้ min(rez, REZ_AURA) ไม่เกินสิบลูก) → ลม → ม้าไม้ตั้งแต่รอบ 2 → รอจบเฟสคำสั่ง
static func start_turn(st: BattleState, out: Array[Dictionary]) -> void:
	for s: BattleState.Squad in st.alive_squads():
		s.ow_used = false
		if s.side == st.turn:
			s.reset_turn()
			s.shaken = false
	BtAbilities.refill_shields(st, out)
	_undone(st)
	_phase(st, BattleState.PH_CMD, out)
	st.fights = PackedStringArray()
	st.fights_null = false
	st.fight_at = 0
	out.append(Events.make(Events.Id.TURN, {"team": st.turn, "round": st.round_no}))
	_say(st, out, "turn_start", [st.turn, st.round_no, 0 if st.goal == BattleState.GOAL_KILL else st.max_round()])
	for p: BattleState.Seat in st.team_seats(st.turn):
		p.cp += 1
	for s: BattleState.Squad in st.alive_squads():
		if s.side != st.turn or not BtSquads.half(s):
			continue
		if BtAbilities.flag(s.ti, "brave"):
			_say(st, out, "shock_free_brave", [s.id])
			continue
		if BtCombat.in_aura(st, s, "ld"):
			_say(st, out, "shock_free_ld", [s.id])
			continue
		var p := BattleState.Pend.new()
		p.kind = BattleState.K_SHOCK
		p.stage = BattleState.S_SHOCK
		p.u = s.id
		p.att = s.pl
		p.need = BtAbilities.num(s.ti, "ld")
		BtPend.push(st, p)
	for s: BattleState.Squad in st.alive_squads():
		var lost := s.n0 - st.squad_alive(s)
		if s.side != st.turn or not BtAbilities.flag(s.ti, "rez") or lost <= 0:
			continue
		var rez := BtAbilities.num(s.ti, "rez")
		var p := BattleState.Pend.new()
		p.kind = BattleState.K_REZ
		p.stage = BattleState.S_REZ
		p.u = s.id
		p.att = s.pl
		p.need = mini(rez, GameData.const_int("REZ_AURA", 4)) if BtCombat.in_aura(st, s, "rez") else rez
		p.n = mini(10, lost)
		BtPend.push(st, p)
	BtAbilities.wind_turn(st, out)
	if st.round_no >= 2:
		# รายการหมู่ก่อนเปิด: หมู่ที่เพิ่งออกมาไม่ถูกวนถึง (sqList ของหน้าเก่าคิดครั้งเดียว)
		for s: BattleState.Squad in st.alive_squads():
			if s.side == st.turn and BtAbilities.flag(s.ti, "spawn") and not s.opened:
				BtAbilities.spawn_from(st, s, 0, 0, out)
	st.cmd_wait = true


## จบเฟสคำสั่ง (finishCommand): นับจุดยึดตั้งแต่รอบ 2 (ไม่ใช่โหมดตีกันจนตาย) แล้วเข้าเฟสเคลื่อนที่
static func finish_command(st: BattleState, out: Array[Dictionary]) -> void:
	st.cmd_wait = false
	if st.goal != BattleState.GOAL_KILL and st.round_no >= 2:
		BtObjectives.score(st, st.turn, out)
	_phase(st, BattleState.PH_MOVE, out)


## เฟสถัดไป (nextPhase): เคลื่อนที่ → ยิง → บุก → ตะลุมบอน (ลำดับตีคิดทีหลังใน advance) · ตะลุมบอนหรือคำสั่ง → จบตา
static func next_phase(st: BattleState, out: Array[Dictionary]) -> void:
	if not st.on or st.over:
		return
	_undone(st)
	match st.phase:
		BattleState.PH_MOVE:
			_phase(st, BattleState.PH_SHOOT, out)
		BattleState.PH_SHOOT:
			_phase(st, BattleState.PH_CHARGE, out)
		BattleState.PH_CHARGE:
			st.fights_null = true
			st.fights = PackedStringArray()
			st.fight_at = 0
			_phase(st, BattleState.PH_FIGHT, out)
		_:
			end_turn(st, out)


## ลำดับตะลุมบอน (startFight): หมู่ที่ติดประชิดทั้งหมดยังไม่ได้ตี · หมู่ของทีมในตาที่บุกเข้ามาก่อน
## แล้วสลับ ฝ่ายที่ไม่ได้เป็นตา / ทีมในตาที่ไม่ได้บุก (เริ่มจากฝ่ายที่ไม่ได้เป็นตา) ตามลำดับที่สร้าง
static func start_fight(st: BattleState, out: Array[Dictionary]) -> void:
	var first := PackedStringArray()
	var rest_a := PackedStringArray()
	var rest_b := PackedStringArray()
	for s: BattleState.Squad in st.alive_squads():
		if not BtSquads.is_engaged(st, s):
			continue
		s.fought = false
		if s.side != st.turn:
			rest_b.append(s.id)
		elif s.charged:
			first.append(s.id)
		else:
			rest_a.append(s.id)
	var order := first
	var i := 0
	var j := 0
	while i < rest_b.size() or j < rest_a.size():
		if i < rest_b.size():
			order.append(rest_b[i])
			i += 1
		if j < rest_a.size():
			order.append(rest_a[j])
			j += 1
	st.fights = order
	st.fights_null = false
	st.fight_at = 0
	_say(st, out, "fight_start", [order.size()])


## เป้าที่ตี (fightTarget): เป้าที่บุกใส่ถ้ายังติดประชิด ไม่งั้นขอบใกล้สุด (หมู่ที่สร้างก่อนชนะเมื่อเท่ากัน); ไม่ติดใคร null
static func fight_target(st: BattleState, s: BattleState.Squad) -> BattleState.Squad:
	var eng := BtSquads.engaged_with(st, s)
	if eng.is_empty():
		return null
	if s.ch_tgt != "":
		for q: BattleState.Squad in eng:
			if q.id == s.ch_tgt:
				return q
	# engaged_with เรียงตามลำดับที่สร้างแล้ว: น้อยกว่าจริงจึงเปลี่ยน = ดัชนีน้อยชนะเมื่อเท่ากัน
	var best: BattleState.Squad = eng[0]
	var be := BtSquads.edge(s, best)
	for k: int in range(1, eng.size()):
		var e := BtSquads.edge(s, eng[k])
		if e < be:
			be = e
			best = eng[k]
	return best


## หมู่ถัดไปในลำดับที่ยังตีได้ (scheduleFight): สร้างการโจมตีแบบตีรอทอย; ไม่เหลือใครคืน false
static func schedule_fight(st: BattleState, out: Array[Dictionary]) -> bool:
	while st.fight_at < st.fights.size():
		var s := st.squad(st.fights[st.fight_at])
		st.fight_at += 1
		if s == null or st.squad_alive(s) == 0 or s.fought:
			continue
		var t := fight_target(st, s)
		if t == null:
			continue
		if BtPend.mk_atk(st, s, t, BattleState.HOW_FIGHT) != null:
			_say(st, out, "fight_next", [s.id, t.id])
			return true
	return false


## หนึ่งรอบของ advance(): จบเฟสคำสั่งเมื่อไม่มีทดสอบขวัญ/ซ่อมตัวเองค้าง · ตะลุมบอนเมื่อคิวว่าง (จัดลำดับครั้งแรก
## ตีทีละหมู่ ครบแล้วจบตา); true = วนต่อ (ผู้เรียกวนไม่เกิน ADVANCE_GUARD ครั้ง หลัง BtPend.prune ครั้งเดียว)
static func advance_step(st: BattleState, out: Array[Dictionary]) -> bool:
	if not st.on or st.over:
		return false
	if st.phase == BattleState.PH_CMD and st.cmd_wait:
		var waiting := false
		for p: BattleState.Pend in st.pend:
			if p.kind == BattleState.K_SHOCK or p.kind == BattleState.K_REZ:
				waiting = true
				break
		if not waiting:
			finish_command(st, out)
			return true
	if st.phase == BattleState.PH_FIGHT and st.pend.is_empty():
		if st.fights_null:
			start_fight(st, out)
		if schedule_fight(st, out):
			return false
		end_turn(st, out)
		return true
	return false


## ที่นั่ง pi กดเสร็จเฟส ph (playerDone ส่วนกติกา; ph "" = เฟสไหนก็ได้): ต้องเป็นทีมในตา ยังไม่จบ ยังไม่กด
## คนจริงในทีมครบ → เฟสถัดไป (advance ตามมาจากผู้เรียก) ไม่งั้นบันทึก seat_done [ที่นั่ง, เฟส]
static func player_done(st: BattleState, pi: int, ph: String, out: Array[Dictionary]) -> void:
	var p := st.seat(pi)
	if p == null or p.team != st.turn or st.over or p.done or (ph != "" and ph != st.phase_name()):
		return
	p.done = true
	if all_done(st, st.turn):
		next_phase(st, out)
		return
	_say(st, out, "seat_done", [pi, st.phase_name()])


## จบตา (endTurn): ทีมถัดไปที่ยังมีตัว (ข้ามทีมที่หมด วนกลับทีม 0 = รอบใหม่) เกินรอบสุดท้ายตัดสินด้วย end_round_check
static func end_turn(st: BattleState, out: Array[Dictionary]) -> void:
	if not st.on or st.over:
		return
	_undone(st)
	var t := st.turn
	var n := 0
	while true:
		t = Fx.imod(t + 1, maxi(1, st.teams))
		if t == 0:
			st.round_no += 1
		n += 1
		if st.live_of(t) != 0 or n > st.teams:
			break
	st.turn = t
	if st.round_no > st.max_round():
		end_round_check(st, out)
		return
	start_turn(st, out)


## จบนัด (finish): w = ทีมที่ชนะ หรือ BattleState.DRAW · ของที่ค้างทอยทิ้งหมด · บันทึก why [w] และส่ง OVER
static func finish(st: BattleState, w: int, why: String, out: Array[Dictionary]) -> void:
	st.over = true
	st.winner = w
	st.pend.clear()
	_say(st, out, why, [w])
	out.append(Events.make(Events.Id.OVER, {"result": w, "why": why}))


## เหลือทีมเดียวที่ยังมีตัว (รวมร่างรอลม) = จบ ไม่เหลือใครเลย = เสมอ (checkOver)
static func check_over(st: BattleState, out: Array[Dictionary]) -> void:
	if not st.on or st.over:
		return
	var alive := teams_alive(st)
	if alive.size() > 1:
		return
	finish(st, alive[0] if alive.size() == 1 else BattleState.DRAW, "over_last", out)


## ครบรอบสุดท้าย (endRoundCheck): ทีมที่ยังมีตัว (ร่างรอลมนับ) แต้มชัยมากสุด · เท่ากันดูแต้มที่เหลือของโมเดลที่ยืนอยู่
## Σ pts·(30/n) แบบตรงเป๊ะ · หนึ่งทีมชนะ ไม่งั้นเสมอ · round_no = รอบสุดท้าย
static func end_round_check(st: BattleState, out: Array[Dictionary]) -> void:
	if st.over:
		return
	var top := -1
	var best := PackedInt32Array()
	for t: int in st.teams:
		if st.live_of(t) == 0:
			continue
		var v: int = st.vp[t] if t < st.vp.size() else 0
		if v > top:
			top = v
			best = PackedInt32Array([t])
		elif v == top:
			best.append(t)
	if best.size() > 1:
		var bp := -1
		var b2 := PackedInt32Array()
		for q: int in best:
			var p := left_pts(st, q)
			if p > bp:
				bp = p
				b2 = PackedInt32Array([q])
			elif p == bp:
				b2.append(q)
		best = b2
	st.round_no = st.max_round()
	finish(st, best[0] if best.size() == 1 else BattleState.DRAW,
		"over_kill_rounds" if st.goal == BattleState.GOAL_KILL else "over_rounds", out)


## แต้มกองทัพที่เหลือของทีม คูณ 30: Σ pts·(30/n) ของโมเดลที่ยืนอยู่ (ไม่นับร่างรอลม)
static func left_pts(st: BattleState, team: int) -> int:
	var p := 0
	for m: BattleState.Unit in st.units:
		if m.side == team:
			# n ≥ 1 และหาร 30 ลงตัวทุกชนิด (test_turn ตรวจ) หารบวกด้วยบวก
			p += BtAbilities.num(m.ti, "pts") * (PTS_LCM / maxi(1, BtAbilities.num(m.ti, "n")))
	return p
