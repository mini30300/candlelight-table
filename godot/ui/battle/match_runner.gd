class_name MatchRunner
extends RefCounted
## สะพานเดียวระหว่างหน้ารบกับกติกา (LOBBY_SPEC §4.2) ไม่มี Node: ทุกการเปลี่ยนผ่าน Battle.apply / bot_step / flush
## ไม่เขียน BattleState เอง ไม่คิดกติกาเอง · ที่นั่งคนจริงไม่เกินหนึ่งที่ (human = -1: บอทเล่นกันเอง)
## step() = ปั๊มหนึ่งก้าว: ทอยที่ค้าง → บอท (เพื่อนร่วมทีมก่อน) → รอคน / ให้บอทเล่นแทน → จบเฟสของทีมบอท → ทอยที่เหลือ
## act ของคนจริงถือ pid ของที่นั่ง ("L<ที่นั่ง>" หลัง start) ลูกเต๋าจาก dice:<ที่นั่ง> · ให้บอทเล่นแทนใช้นโยบายของ BtBot เอง

## Battle ที่เก็บทุกเหตุการณ์ (รวมของ bot_step / flush ที่คืนแค่สตริงหรือจำนวน)
class Rec extends Battle:
	var evs: Array[Dictionary] = []
	var over_why := ""

	func apply(act: Dictionary) -> Array[Dictionary]:
		var out := super(act)
		note(out)
		return out

	func note(out: Array[Dictionary]) -> void:
		evs.append_array(out)
		for e in out:
			if Events.id_of(e) == Events.Id.OVER:
				over_why = str(e.get("why", ""))


const HERE := {"online": false}
const MAX_DICE := 60
## เฟสที่คนจริงต้องกด (คำสั่งและตะลุมบอนเดินเอง)
const HUMAN_PHASES: PackedInt32Array = [BattleState.PH_MOVE, BattleState.PH_SHOOT, BattleState.PH_CHARGE]

var plan: Dictionary
var b: Rec
var st: BattleState
var human := -1
var pid := ""
var auto_human := false
var started := false
## args ของเหตุผลล่าสุดที่ทำไม่ได้ (สำหรับ BattleText.why)
var why_args: Array = []


## plan = SeatPlan.build(...)
func _init(p: Dictionary) -> void:
	plan = p
	var seats: Array[Dictionary] = []
	for sd: Variant in p.get("seats", []):
		if sd is Dictionary:
			seats.append((sd as Dictionary).duplicate())
	var base := Battle.make(p.get("setup", {}), seats, {})
	b = Rec.new()
	b.st = base.st
	b.seed = base.seed
	st = b.st
	human = int(p.get("human", -1))
	if human >= st.seats.size():
		human = -1


## เริ่มนัดครั้งเดียว (วางกอง จุดยึด ทีมแรก เฟสคำสั่งจบเอง) คืนเหตุการณ์ (เข้าคิวของ take_events ด้วย)
func start() -> Array[Dictionary]:
	if started:
		return []
	started = true
	var out := b.start()
	b.note(out)
	if human >= 0:
		pid = st.seats[human].pid
	return out


## ปั๊มหนึ่งก้าว: {"state": acted|wait_human|over|stuck, "events": เหตุการณ์ที่ยังไม่มีใครอ่าน}
func step() -> Dictionary:
	if not started:
		start()
	var k0 := b.evs.size()
	if st.over:
		return _res("over", k0)
	var n0 := b.actlog.size()
	if not st.pend.is_empty():
		b.flush(true, HERE)
		if b.actlog.size() != n0:
			return _res("acted", k0)
	if b.bot_step() != "" or b.actlog.size() != n0:
		return _res("acted", k0)
	if st.over:
		return _res("over", k0)
	if is_human_turn():
		if not _human_alive():
			end_phase()   # ไม่มีหมู่เหลือให้สั่ง: กดจบเฟสแทน (ไม่ใช่ทางเลือก)
			return _res("acted", k0)
		if auto_human:
			auto_step()
			return _res("over" if st.over else "acted", k0)
		return _res("wait_human", k0)
	var e := BtBot.finished_act(st)
	if not e.is_empty():
		e["pid"] = ""
		b.apply(e)
		return _res("over" if st.over else "acted", k0)
	b.flush(true, HERE)
	if b.actlog.size() == n0:
		return _res("over" if st.over else "stuck", k0)
	return _res("over" if st.over else "acted", k0)


## ผลของก้าว: เหตุการณ์ทั้งหมดที่ยังไม่มีใครอ่าน (รวมของการกระทำของคุณก่อนหน้า) แล้วล้างคิว
func _res(state: String, _k0: int) -> Dictionary:
	return {"state": state, "events": take_events()}


## ตาของคุณในเฟสที่ต้องกด (เคลื่อนที่ ยิง บุก) และยังไม่ได้กดจบ
func is_human_turn() -> bool:
	if human < 0 or not st.on or st.over:
		return false
	var q := st.seats[human]
	return st.turn == q.team and HUMAN_PHASES.has(st.phase) and not q.done


func _human_alive() -> bool:
	for s: BattleState.Squad in st.alive_squads():
		if s.pl == human:
			return true
	return false


## ประตู canAct ของ UI (R1_PORT_SPEC §1.18): หมู่ของคุณ ตาของทีมคุณ ไม่มีลูกเต๋าค้าง และตามเฟส
func can_select(s: BattleState.Squad) -> bool:
	if s == null or human < 0 or st.over or not st.pend.is_empty() or s.models.is_empty():
		return false
	if s.pl != human or s.side != st.turn:
		return false
	var q := st.seats[human]
	if q.bot or q.ai or q.done:
		return false
	match st.phase:
		BattleState.PH_MOVE:
			return not s.moved
		BattleState.PH_SHOOT:
			return not s.shot and (not BtAbilities.gun(s.ti).is_empty() or BtAbilities.num(s.ti, "heal") != 0)
		BattleState.PH_CHARGE:
			return BtCombat.charge_gate(st, s) == ""
	return false


## เหตุที่เลือกหมู่ของคุณไม่ได้ในเฟสนี้ (รหัสของ BattleText.why) "" = เลือกได้ · เฟสบุกใช้เหตุของกติกา (BtCombat.charge_gate)
func select_why(s: BattleState.Squad) -> String:
	if can_select(s):
		return ""
	if s == null or human < 0 or s.pl != human or not is_human_turn():
		return "not_now"
	match st.phase:
		BattleState.PH_MOVE:
			return "already_moved" if s.moved else "not_now"
		BattleState.PH_SHOOT:
			return "already_shot" if s.shot else "no_gun"
		BattleState.PH_CHARGE:
			var w := BtCombat.charge_gate(st, s)
			return w if w != "" else "not_now"
	return "not_now"


## หมู่ของคุณที่ยังทำอะไรได้ในเฟสนี้ (ลำดับที่สร้าง)
func selectable() -> Array[BattleState.Squad]:
	var out: Array[BattleState.Squad] = []
	for s: BattleState.Squad in st.alive_squads():
		if can_select(s):
			out.append(s)
	return out


# ---- การกระทำของคนจริง: คืน "" = ทำแล้ว หรือรหัสเหตุผล (BattleText.why) ----

## เดินหมู่ s ไป (x, z) MI · fall_back = ถอยออกจากประชิด
func move(s: BattleState.Squad, x_mi: int, z_mi: int, fall_back: bool = false) -> String:
	why_args = []
	if st.phase != BattleState.PH_MOVE or not can_select(s):
		return "not_now"
	var r := BtMoves.try_move(st, s, x_mi, z_mi, fall_back)
	if str(r["key"]) != "":
		why_args = r["args"]
		return str(r["key"])
	var a: Dictionary = r["act"]
	return _human_act(a)


## วิ่ง (ทอยเพิ่มระยะก่อนเดิน)
func advance(s: BattleState.Squad) -> String:
	why_args = []
	if st.phase != BattleState.PH_MOVE or not can_select(s) or s.adv:
		return "not_now"
	if BtSquads.is_engaged(st, s):
		return "engaged_need_fb"
	return _human_act({"a": "adv", "u": s.id, "roll": _dice().d6()})


## อยู่กับที่ (เฟสเคลื่อนที่)
func stay(s: BattleState.Squad) -> String:
	why_args = []
	if st.phase != BattleState.PH_MOVE or not can_select(s):
		return "not_now"
	return _human_act({"a": "stay", "u": s.id})


## ข้าม (เฟสยิง / บุก)
func skip(s: BattleState.Squad) -> String:
	why_args = []
	if (st.phase != BattleState.PH_SHOOT and st.phase != BattleState.PH_CHARGE) or not can_select(s):
		return "not_now"
	return _human_act({"a": "skip", "u": s.id, "ph": st.phase_name()})


## ยิงหมู่ t: ลูกเต๋าโดนจาก dice:<ที่นั่ง> แล้วทอยเจาะ/เซฟต่อ
func shoot(s: BattleState.Squad, t: BattleState.Squad) -> String:
	why_args = []
	if st.phase != BattleState.PH_SHOOT or not can_select(s) or t == null:
		return "not_now"
	var w := BtCombat.shot_why_not(st, s, t)
	if str(w["key"]) != "":
		why_args = w["args"]
		return str(w["key"])
	var m := BtCombat.atk_math(st, s, t, BattleState.HOW_SHOOT)
	if m.is_empty() or int(m["shots"]) <= 0:
		return "no_gun"
	var hit: Array = [] if bool(m["tr"]) else _roll(int(m["shots"]))
	var why := _human_act({"a": "atk", "u": s.id, "t": t.id, "how": "shoot", "hit": hit})
	if why == "":
		b.flush(true, HERE)
	return why


## บุกหมู่ t: ประกาศแล้วทอย (ยิงสกัด ทอยบุก เดินเข้าประชิด)
func charge(s: BattleState.Squad, t: BattleState.Squad) -> String:
	why_args = []
	if st.phase != BattleState.PH_CHARGE or not can_select(s) or t == null:
		return "not_now"
	var w := BtCombat.charge_why_not(st, s, t)
	if str(w["key"]) != "":
		why_args = w["args"]
		return str(w["key"])
	var why := _human_act({"a": "chg", "u": s.id, "t": t.id})
	if why == "":
		b.flush(true, HERE)
	return why


## จบเฟส: เฉพาะตาของคุณในเฟสเคลื่อนที่/ยิง/บุก ไม่มีลูกเต๋าค้าง · ทอยที่ค้างก่อน แล้วส่ง done พร้อมชื่อเฟสเสมอ
func end_phase() -> String:
	why_args = []
	if not is_human_turn():
		return "not_now"
	b.flush(true, HERE)
	if not st.pend.is_empty() or not is_human_turn():
		return "not_now"
	return _human_act({"a": "done", "ph": st.phase_name()})


## ให้บอทเล่นแทนหนึ่งก้าว: หมู่แรกของคุณที่ยังต้องทำในเฟสนี้ ใช้ BtBot.move_decision + plan_move / shoot_act / charge_act
## (นโยบายเดียวกับบอท ไม่คิดกติกาเอง) ส่งผ่าน apply ด้วย pid ของคุณ · ไม่เหลือหมู่ก็จบเฟส
func auto_step() -> String:
	if not is_human_turn():
		return "not_now"
	if not st.pend.is_empty():
		b.flush(true, HERE)
		return ""
	for s: BattleState.Squad in st.alive_squads():
		if s.pl != human:
			continue
		var a := {}
		match st.phase:
			BattleState.PH_MOVE:
				if s.moved:
					continue
				var d := BtBot.move_decision(st, s)
				if str(d["a"]) == "smove":
					var to := BtMoves.plan_move(st, s, int(d["x"]), int(d["z"]))
					a = {"a": "smove", "u": s.id, "to": BtMoves.pts(to), "how": str(d["how"])}
				else:
					a = d
			BattleState.PH_SHOOT:
				if s.shot:
					continue
				a = BtBot.shoot_act(st, s, _dice())
			BattleState.PH_CHARGE:
				a = BtBot.charge_act(st, s)
				if a.is_empty():
					continue
		if a.is_empty():
			continue
		var why := _human_act(a)
		if why != "":
			# ไม่รับ (ไม่ควรเกิด): ข้ามหมู่นี้ไป จะได้ไม่วนซ้ำ
			_human_act({"a": "skip", "u": s.id, "ph": st.phase_name()})
		if not st.pend.is_empty():
			b.flush(true, HERE)
		return why
	return end_phase()


func _human_act(a: Dictionary) -> String:
	a["pid"] = pid
	b.apply(a)
	return "" if b.last_error == "" else "refused"


func _dice() -> Rng:
	return st.rng("dice:%d" % human)


func _roll(n: int) -> Array:
	var r := _dice()
	var out: Array = []
	for i in mini(n, MAX_DICE):
		out.append(r.d6())
	return out


# ---- ตัวช่วย ----

func is_over() -> bool:
	return st.over


## ทีมที่ชนะ หรือ BattleState.DRAW (-1); ยังเล่นอยู่ = BattleState.NO_WINNER (-2)
func winner() -> int:
	return st.winner


## เหตุที่จบจากเหตุการณ์ OVER: over_last / over_rounds / over_kill_rounds ("" = ยังไม่จบ)
func over_why() -> String:
	return b.over_why


func human_team() -> int:
	return st.seats[human].team if human >= 0 else -1


## เหตุการณ์ที่ยังไม่มีใครอ่าน (แล้วล้างคิว)
func take_events() -> Array[Dictionary]:
	var out := b.evs.duplicate()
	b.evs.clear()
	return out


func digest() -> String:
	return b.digest()


func acts() -> Array:
	return b.actlog.acts()


## เล่นซ้ำจากบันทึก act บนโต๊ะใหม่ (setup + ที่นั่งเดิม) แล้วคืน digest: ต้องเท่ากับ digest() เสมอ
func replayed_digest() -> String:
	var seats: Array[Dictionary] = []
	for sd: Variant in plan.get("seats", []):
		seats.append((sd as Dictionary).duplicate())
	var r := Battle.make(plan.get("setup", {}), seats, {})
	r.start()
	r.replay(acts())
	return r.digest()


## เล่นจนจบโดยไม่มีจอ (บอทเล่นแทนคุณด้วย): "ok" | "stuck" | "steps"
func run_to_end(max_steps: int = 20000) -> String:
	auto_human = true
	for i in max_steps:
		var r := step()
		var state := str(r["state"])
		if state == "over" or st.over:
			return "ok"
		if state == "stuck":
			return "stuck"
	return "steps"
